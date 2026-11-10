local socket = require("socket")
local encoding = require("encoding")

local imap = {
    _tag_counter = 0
}

function imap.next_tag()
    imap._tag_counter = imap._tag_counter + 1
    return string.format("A%03d", imap._tag_counter)
end

-- IMAP quoted string: only backslash and double quote need escaping
local function quote(str)
    return '"' .. tostring(str or ""):gsub('[\\"]', "\\%0") .. '"'
end

-- Sends a command and reads up to its tagged completion line.
-- Returns ok, status_line, untagged_lines; ok is nil when the connection dropped.
local function command(conn, text)
    local tag = imap.next_tag()
    local sent, send_err = conn:send(tag .. " " .. text .. "\r\n")
    if not sent then return nil, send_err or "send failed", {} end

    local untagged = {}
    while true do
        local line, err = conn:receive("*l")
        if not line then return nil, err or "connection closed", untagged end
        local status = line:match("^" .. tag .. " (%a+)")
        if status then
            return status:upper() == "OK", line, untagged
        end

        -- A line ending in {n} continues with n raw bytes (a "literal", used for strings that
        -- cannot be quoted, e.g. non-ASCII file names). Splice it back in as a quoted string.
        while true do
            local size = tonumber(line:match("{(%d+)}$"))
            if not size then break end
            local data = ""
            if size > 0 then
                data, err = conn:receive(size)
                if not data then return nil, err or "connection closed", untagged end
            end
            local rest
            rest, err = conn:receive("*l")
            if not rest then return nil, err or "connection closed", untagged end
            line = line:gsub("{%d+}$", "") .. quote(data) .. rest
        end

        table.insert(untagged, line)
    end
end

-- Parses an IMAP parenthesized list starting at s[pos] == "(" into nested Lua tables.
-- Strings and atoms become strings, NIL becomes false (so positions are kept).
local function parse_list(s, pos)
    local list = {}
    pos = pos + 1
    while pos <= #s do
        local c = s:sub(pos, pos)
        if c == ")" then
            return list, pos + 1
        elseif c == "(" then
            local sub
            sub, pos = parse_list(s, pos)
            list[#list + 1] = sub
        elseif c == '"' then
            local buf = {}
            pos = pos + 1
            while pos <= #s do
                local ch = s:sub(pos, pos)
                if ch == "\\" then
                    buf[#buf + 1] = s:sub(pos + 1, pos + 1)
                    pos = pos + 2
                elseif ch == '"' then
                    pos = pos + 1
                    break
                else
                    buf[#buf + 1] = ch
                    pos = pos + 1
                end
            end
            list[#list + 1] = table.concat(buf)
        elseif c:match("%s") then
            pos = pos + 1
        else
            local atom = s:match("^[^%s()]+", pos)
            list[#list + 1] = atom:upper() ~= "NIL" and atom or false
            pos = pos + #atom
        end
    end
    return list, pos
end

-- Looks up a parameter in a flat ("key" "value" "key" "value") list,
-- including the RFC 2231 forms key*, key*0, key*1*, ...
local function param(list, key)
    if type(list) ~= "table" then return nil end
    local plain, extended
    local pieces, piece_count = {}, 0
    for i = 1, #list - 1, 2 do
        local k, v = list[i], list[i + 1]
        if type(k) == "string" and type(v) == "string" then
            k = k:lower()
            if k == key then
                plain = v
            elseif k == key .. "*" then
                extended = v
            else
                local n, encoded = k:match("^" .. key .. "%*(%d+)(%*?)$")
                if n then
                    pieces[tonumber(n)] = { v, encoded == "*" }
                    piece_count = piece_count + 1
                end
            end
        end
    end
    if plain then return plain end
    if extended then return encoding.decode_rfc2231(extended) end
    if piece_count > 0 then
        local out = {}
        for n = 0, piece_count - 1 do
            local piece = pieces[n]
            if not piece then break end
            if piece[2] then
                out[#out + 1] = n == 0 and encoding.decode_rfc2231(piece[1]) or encoding.percent_decode(piece[1])
            else
                out[#out + 1] = piece[1]
            end
        end
        return table.concat(out)
    end
end

-- Walks a BODYSTRUCTURE and appends the file name of every named part, in message order
local function collect_names(part, out)
    if type(part) ~= "table" then return end

    -- multipart: child parts first, then the subtype and its parameters
    if type(part[1]) == "table" then
        for i = 1, #part do
            if type(part[i]) ~= "table" then break end
            collect_names(part[i], out)
        end
        return
    end

    -- single part: type, subtype, parameters, ..., (disposition (parameters)), ...
    local name
    for i = 4, #part do
        local e = part[i]
        if type(e) == "table" and #e == 2 and type(e[1]) == "string" and type(e[2]) == "table" then
            name = param(e[2], "filename")
            if name then break end
        end
    end
    name = name or param(part[3], "name")
    if name then out[#out + 1] = name end

    -- an attached email carries its own structure
    if type(part[1]) == "string" and type(part[2]) == "string"
        and part[1]:lower() == "message" and part[2]:lower() == "rfc822" then
        collect_names(part[9], out)
    end
end

-- Tries IPv4 first, then IPv6, and reports both failures. A plain socket.tcp() walks through
-- every address itself but only returns the last error: on a network without IPv6 that is
-- always "Network is unreachable", which hides why the IPv4 attempt really failed.
local function open_tcp(host, port)
    local errors = {}
    for _, family in ipairs({ { "tcp4", "IPv4" }, { "tcp6", "IPv6" } }) do
        local create = socket[family[1]]
        local conn = create and create()
        if conn then
            conn:settimeout(15)
            local ok, err = conn:connect(host, port)
            if ok then return conn end
            conn:close()
            table.insert(errors, family[2] .. ": " .. tostring(err))
        end
    end

    -- Older LuaSocket without tcp4/tcp6
    if #errors == 0 then
        local conn = socket.tcp()
        conn:settimeout(15)
        local ok, err = conn:connect(host, port)
        if ok then return conn end
        conn:close()
        return nil, tostring(err)
    end
    return nil, table.concat(errors, "; ")
end

function imap.connect(config)
    local conn, err = open_tcp(config.imap_server, config.imap_port)
    if not conn then return nil, err end
    conn:settimeout(30)

    if config.use_ssl then
        local has_ssl, ssl = pcall(require, "ssl")
        if not has_ssl then
            conn:close()
            return nil, "SSL module unavailable"
        end

        local wrapped, wrap_err = ssl.wrap(conn, { mode = "client", protocol = "tlsv1_2", verify = "none" })
        if not wrapped then
            conn:close()
            return nil, "SSL setup failed: " .. tostring(wrap_err)
        end
        conn = wrapped
        -- Shared hosting serves many domains from one address and picks the certificate by SNI
        if conn.sni then pcall(conn.sni, conn, config.imap_server) end
        conn:settimeout(30)

        local hs_ok, hs_err = conn:dohandshake()
        if not hs_ok then
            conn:close()
            return nil, "SSL handshake failed: " .. tostring(hs_err)
        end
    end

    local greeting = conn:receive("*l")
    if not greeting then
        conn:close()
        return nil, "No IMAP greeting received"
    end

    return conn
end

function imap.login(conn, email, password)
    local ok, status = command(conn, "LOGIN " .. quote(email) .. " " .. quote(password))
    if ok then return true end
    -- The server's reason ("Invalid credentials", "Application-specific password required", ...)
    local reason = status and status:match("^%S+ %a+ (.+)$")
    return false, reason or status
end

-- Opens a mailbox. Gmail labels are mailboxes too, e.g. "Books".
-- On success also returns the mailbox's UIDVALIDITY: message UIDs stay valid while it is unchanged.
function imap.select(conn, mailbox)
    local ok, status, untagged = command(conn, "SELECT " .. quote(mailbox or "INBOX"))
    if ok then
        local uidvalidity
        for _, line in ipairs(untagged) do
            uidvalidity = uidvalidity or line:upper():match("%[UIDVALIDITY (%d+)%]")
        end
        return true, uidvalidity
    end
    return false, status and status:match("^%S+ %a+ (.+)$") or status
end

-- Returns the UIDs of all unread messages. UIDs, unlike sequence numbers, identify a message
-- across sessions, which lets a device remember what it already downloaded.
function imap.search_unseen(conn)
    local ok, status, untagged = command(conn, "UID SEARCH UNSEEN")
    if not ok then return nil, status end

    local ids = {}
    for _, line in ipairs(untagged) do
        -- Only "* SEARCH 4 9 12"; other untagged lines such as "* 13 EXISTS" also carry numbers
        local list = line:match("^%* [Ss][Ee][Aa][Rr][Cc][Hh](.*)$")
        if list then
            for id in list:gmatch("%d+") do table.insert(ids, id) end
        end
    end
    return ids
end

-- Returns the file names of a message's attachments without downloading the message itself.
-- Names are returned as sent (they may still be RFC 2047 encoded).
-- Returns nil when the server's answer could not be understood.
function imap.list_attachments(conn, id)
    local ok, _, untagged = command(conn, string.format("UID FETCH %s (BODYSTRUCTURE)", id))
    if not ok then return nil end

    for _, line in ipairs(untagged) do
        local start = line:upper():find("BODYSTRUCTURE%s*%(")
        if start then
            local open = line:find("(", start, true)
            local parsed_ok, structure = pcall(parse_list, line, open)
            if not parsed_ok then return nil end
            local names = {}
            collect_names(structure, names)
            return names
        end
    end
    return nil
end

-- Streams one message. BODY.PEEK leaves it unread, so an interrupted download can be retried;
-- call imap.mark_seen once the message has been handled.
-- The iterator returns chunks, then nil at the end, or nil plus an error message.
function imap.fetch_stream(conn, id)
    local tag = imap.next_tag()

    conn:settimeout(30)
    local sent, send_err = conn:send(string.format("%s UID FETCH %s BODY.PEEK[]\r\n", tag, id))
    if not sent then return nil, send_err or "send failed" end

    local line, err
    local literal_size = nil

    -- Read until we find the literal byte count e.g. {5812345}
    repeat
        line, err = conn:receive("*l")
        if not line then return nil, err or "connection closed" end
        -- The command finished without sending a body (message deleted meanwhile, or an error)
        if line:match("^" .. tag .. " ") then return nil, "no message body: " .. line end
        literal_size = tonumber(line:match("{(%d+)}$"))
    until literal_size

    local remaining = literal_size
    local done = false

    return function()
        if done then return nil end

        -- Once we read the exact byte count, clean up the trailing protocol lines
        if remaining <= 0 then
            done = true
            repeat
                line = conn:receive("*l")
            until not line or line:match("^" .. tag .. " ")
            if not line then return nil, "connection closed" end
            return nil
        end

        local chunk_size = math.min(8192, remaining)
        local chunk, read_err, partial = conn:receive(chunk_size)
        chunk = chunk or partial

        if not chunk or #chunk == 0 then
            done = true
            return nil, read_err or "read failed"
        end

        remaining = remaining - #chunk
        return chunk
    end
end

function imap.mark_seen(conn, id)
    local ok, status = command(conn, string.format("UID STORE %s +FLAGS.SILENT (\\Seen)", id))
    return ok, status
end

function imap.logout(conn)
    local tag = imap.next_tag()
    conn:send(tag .. " LOGOUT\r\n")
    conn:settimeout(5)
    pcall(function() conn:receive("*l") end)
    conn:close()
end

return imap

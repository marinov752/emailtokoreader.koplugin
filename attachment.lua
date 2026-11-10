local mime = require("mime")
local filesystem = require("filesystem")
local encoding = require("encoding")

local attachment = {}

local function percent_decode(str)
    return (str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- Reads a MIME header parameter, including RFC 2231 forms (param*=utf-8''..., param*0=/param*1*=...).
-- The leading [;%s] keeps "name" from matching inside "filename".
local function header_param(block, param)
    -- Header and parameter names are case-insensitive
    local prefix = "[;%s]" .. param:gsub("%a", function(c)
        return "[" .. c:upper() .. c:lower() .. "]"
    end)

    local value = block:match(prefix .. '%s*=%s*"([^"]*)"')
        or block:match(prefix .. '%s*=%s*([^%s;"]+)')
    if value then return value end

    value = block:match(prefix .. "%*%s*=%s*\"?[^'\"%s]*'[^']*'([^%s;\"]+)")
    if value then return percent_decode(value) end

    local parts = {}
    local i = 0
    while true do
        local section = prefix .. "%*" .. i
        local encoded = block:match(section .. '%*%s*=%s*"?([^%s;"]+)')
        if encoded then
            if i == 0 then
                encoded = encoded:gsub("^[^']*'[^']*'", "")
            end
            table.insert(parts, percent_decode(encoded))
        else
            local plain = block:match(section .. '%s*=%s*"([^"]*)"')
                or block:match(section .. '%s*=%s*([^%s;"]+)')
            if not plain then break end
            table.insert(parts, plain)
        end
        i = i + 1
    end
    if #parts > 0 then return table.concat(parts) end
end

local function decode_quoted_printable(line)
    return (line:gsub("=(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- selected: optional set of positions ({[1] = true, [3] = true}) among the attachments with an
-- allowed extension, counted in message order; nil downloads all of them.
function attachment.process_stream(stream_iter, download_path, tick_cb, allowed_extensions, selected)
    local state = "SEARCHING"
    local match_index = 0
    -- Nested multiparts (e.g. text + HTML + attachment) have one boundary per level,
    -- so every boundary seen so far stays valid
    local boundaries = {}

    -- Build a lookup set of the accepted extensions (lowercase, without dot)
    local allowed_set = {}
    for _, ext in ipairs(allowed_extensions or {"epub"}) do
        local key = tostring(ext):lower():match("^%.?(.+)$")
        if key then
            allowed_set[key] = true
        end
    end

    local header_lines = {}
    local current_filename = nil
    local is_quoted_printable = false
    -- Text bodies: the line break before a boundary belongs to the boundary, so breaks are written lazily
    local pending_newline = false

    local chunks = {}
    local chunks_len = 0
    local b64_leftover = ""
    
    local out_file = nil
    local tmp_path = nil
    local final_path = nil
    
    local downloaded_count = 0
    local lines_processed = 0

    -- Drops the half-written file; nothing incomplete may end up next to the real books
    local function abort(message)
        if out_file then
            out_file:close()
            out_file = nil
        end
        if tmp_path then os.remove(tmp_path) end
        error(message, 0)
    end

    -- A failed write (disk full, card removed) must not pass as a finished book
    local function write(data)
        local ok, err = out_file:write(data)
        if not ok then
            abort("Could not write " .. tostring(current_filename) .. ": " .. tostring(err))
        end
    end

    local function finalize_attachment()
        if out_file then
            if chunks_len > 0 or #b64_leftover > 0 then
                local final_string = b64_leftover .. table.concat(chunks)

                -- Ensure the final string is padded to a perfect multiple of 4
                local pad = #final_string % 4
                if pad > 0 then
                    final_string = final_string .. string.rep("=", 4 - pad)
                end

                -- Wrapped the final decode in pcall
                local decode_ok, decoded = pcall(mime.unb64, final_string)
                if decode_ok and decoded and #decoded > 0 then
                    write(decoded)
                end
            end

            local closed, close_err = out_file:close()
            out_file = nil
            if not closed then
                abort("Could not write " .. tostring(current_filename) .. ": " .. tostring(close_err))
            end

            if tmp_path and final_path then
                local ok, err = os.rename(tmp_path, final_path)
                if ok then
                    downloaded_count = downloaded_count + 1
                else
                    abort("Could not save " .. tostring(current_filename) .. ": " .. tostring(err))
                end
            end
        end

        header_lines = {}
        current_filename = nil
        is_quoted_printable = false
        pending_newline = false
        chunks = {}
        chunks_len = 0
        b64_leftover = ""
        tmp_path = nil
        final_path = nil
    end

    local function process_line(line)
        lines_processed = lines_processed + 1
        
        if tick_cb and lines_processed % 250 == 0 then
            tick_cb()
        end

        line = line:gsub("\r$", "")

        -- 1. Catch boundary definitions in headers (never inside an attachment body)
        if state == "SEARCHING" or state == "HEADERS" then
            local new_boundary = line:match('[Bb][Oo][Uu][Nn][Dd][Aa][Rr][Yy]%s*=%s*"([^"]+)"')
                or line:match('[Bb][Oo][Uu][Nn][Dd][Aa][Rr][Yy]%s*=%s*([^%s;"]+)')
            if new_boundary then
                boundaries["--" .. new_boundary] = true
            end
        end

        -- 2. Strict RFC boundary detection; mail servers may pad the line with trailing whitespace
        local delimiter = line:sub(1, 2) == "--" and line:gsub("[ \t]+$", "")
        if delimiter and (boundaries[delimiter] or boundaries[delimiter:match("^(.-)%-%-$") or ""]) then
            finalize_attachment()
            state = "HEADERS"

        -- 3. Accumulate headers
        elseif state == "HEADERS" then
            if line ~= "" then
                -- A line starting with whitespace continues the previous header (folding)
                local continuation = line:match("^[ \t]+(.*)$")
                if continuation and #header_lines > 0 then
                    header_lines[#header_lines] = header_lines[#header_lines] .. " " .. continuation
                else
                    table.insert(header_lines, line)
                end
            else
                -- Leading newline so header_param's [;%s] prefix also works on the first header
                local header_block = "\n" .. table.concat(header_lines, "\n")

                -- 7bit/8bit/binary (and a missing header) are stored as-is
                local transfer_encoding = (header_block:lower():match("content%-transfer%-encoding:%s*([%w%-]+)") or "7bit")

                -- Content-Disposition's filename wins over Content-Type's name
                local fname = header_param(header_block, "filename") or header_param(header_block, "name")

                -- Decode =?UTF-8?...?= names first, the extension may be hidden inside
                if fname then
                    local decode_ok, decoded_name = pcall(encoding.decode_rfc2047, fname)
                    if decode_ok and decoded_name then
                        fname = decoded_name
                    end
                end

                -- Only accept the attachment if its extension is allowed
                if fname then
                    local ext = fname:match("%.([^%.]+)$")
                    if not (ext and allowed_set[ext:lower()]) then
                        fname = nil
                    end
                end

                -- Optional pick by position: the n-th attachment with an allowed extension
                if fname then
                    match_index = match_index + 1
                    if selected and not selected[match_index] then
                        fname = nil
                    end
                end

                if fname then
                    current_filename = encoding.safe_filename(fname)
                    if transfer_encoding == "base64" then
                        state = "BODY_BASE64"
                    else
                        is_quoted_printable = transfer_encoding == "quoted-printable"
                        state = "BODY_TEXT"
                    end

                    filesystem.mkdir_p(download_path)
                    final_path = filesystem.unique_filepath(
                        filesystem.normalize_path(download_path) .. current_filename)
                    tmp_path = final_path .. ".tmp"

                    local open_err
                    out_file, open_err = io.open(tmp_path, "wb")
                    if not out_file then
                        -- Silently skipping here used to look like "no books found"
                        tmp_path = nil
                        abort("Cannot write to the download folder " .. tostring(download_path)
                            .. ": " .. tostring(open_err))
                    end
                else
                    state = "SEARCHING"
                end
            end

        -- 4. Stream and validate Base64 payload
        elseif state == "BODY_BASE64" then
            -- RFC 2045: characters outside the Base64 alphabet are ignored, the rest of the line counts.
            -- Dropping the whole line instead would leave a hole in the file.
            local clean = line:gsub("[^A-Za-z0-9+/=]", "")

            if clean ~= "" then
                table.insert(chunks, clean)
                chunks_len = chunks_len + #clean
                
                if chunks_len >= 8192 then
                    local combined = b64_leftover .. table.concat(chunks)
                    chunks = {}
                    chunks_len = 0
                    
                    local safe_len = math.floor(#combined / 4) * 4
                    if safe_len > 0 then
                        local chunk_to_decode = combined:sub(1, safe_len)
                        b64_leftover = combined:sub(safe_len + 1)
                        
                        -- Wrapped the chunk decode in pcall
                        local decode_ok, decoded = pcall(mime.unb64, chunk_to_decode)
                        if decode_ok and decoded and #decoded > 0 and out_file then
                            write(decoded)
                        end
                    else
                        b64_leftover = combined
                    end
                end
            end

        -- 5. Plain text and quoted-printable payload (e.g. .acsm sent by Apple Mail)
        elseif state == "BODY_TEXT" then
            local soft_break = false
            if is_quoted_printable then
                line = line:gsub("[ \t]+$", "")
                if line:sub(-1) == "=" then
                    soft_break = true
                    line = line:sub(1, -2)
                end
                line = decode_quoted_printable(line)
            end

            if pending_newline then
                write("\n")
            end
            write(line)
            pending_newline = not soft_break
        end
    end

    -- 6. Safe Chunk-to-Line Buffer
    local leftover_text = ""
    while true do
        local chunk, stream_err = stream_iter()

        -- The connection broke mid-message: saving what arrived so far would produce a corrupt book
        if not chunk and stream_err then
            abort("Download interrupted: " .. tostring(stream_err))
        end

        -- End of stream: process any trailing text
        if not chunk then
            if leftover_text ~= "" then process_line(leftover_text) end
            break
        end

        local text = leftover_text .. chunk
        local pos = 1
        
        -- Split strictly on newlines, saving partial text for the next loop
        while true do
            local s, e = text:find("\n", pos)
            if not s then
                leftover_text = text:sub(pos)
                break
            end
            local line = text:sub(pos, s - 1)
            process_line(line)
            pos = e + 1
        end
    end

    finalize_attachment()

    return downloaded_count
end

return attachment
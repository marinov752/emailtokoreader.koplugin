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
    local prefix = "[;%s]" .. param

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

function attachment.process_stream(stream_iter, download_path, tick_cb, allowed_extensions)
    local state = "SEARCHING"
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
                    out_file:write(decoded) 
                end
            end
            
            out_file:close()
            out_file = nil
            
            if tmp_path and final_path then
                local ok, err = os.rename(tmp_path, final_path)
                if ok then
                    downloaded_count = downloaded_count + 1
                else
                    os.remove(tmp_path)
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

        -- 1. Catch global boundary definitions anywhere in the email
        local new_boundary = line:match('boundary="([^"]+)"') or line:match('boundary=([^%s;]+)')
        if new_boundary then
            boundaries["--" .. new_boundary] = true
        end

        -- 2. Strict RFC boundary detection
        if line:sub(1, 2) == "--" and (boundaries[line] or boundaries[line:match("^(.-)%-%-$") or ""]) then
            finalize_attachment()
            state = "HEADERS"
        
        -- 3. Accumulate headers
        elseif state == "HEADERS" then
            if line ~= "" then
                table.insert(header_lines, line)
            else
                -- Leading space so header_param's [;%s] prefix also works on the first header
                local header_block = " " .. table.concat(header_lines, " ")

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

                if fname then
                    current_filename = encoding.safe_filename(fname)
                    if transfer_encoding == "base64" then
                        state = "BODY_BASE64"
                    else
                        is_quoted_printable = transfer_encoding == "quoted-printable"
                        state = "BODY_TEXT"
                    end

                    filesystem.mkdir_p(download_path)
                    final_path = filesystem.unique_filepath(download_path .. "/" .. current_filename)
                    tmp_path = final_path .. ".tmp"
                    
                    out_file = io.open(tmp_path, "wb")
                    if not out_file then
                        state = "SEARCHING"
                    end
                else
                    state = "SEARCHING"
                end
            end

        -- 4. Stream and validate Base64 payload
        elseif state == "BODY_BASE64" then
            local clean = line:gsub("%s+", "")
            
            -- Defensive check: only buffer valid Base64 characters
            if clean ~= "" and clean:match("^[A-Za-z0-9+/=]+$") then
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
                            out_file:write(decoded)
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
                out_file:write("\n")
            end
            out_file:write(line)
            pending_newline = not soft_break
        end
    end

    -- 6. Safe Chunk-to-Line Buffer
    local leftover_text = ""
    while true do
        local chunk = stream_iter()
        
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
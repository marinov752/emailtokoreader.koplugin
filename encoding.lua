local mime = require("mime")

local encoding = {}

function encoding.url_decode(str)
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

function encoding.percent_decode(str)
    return (str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- RFC 2231 extended value: charset'language'percent-encoded-text
function encoding.decode_rfc2231(str)
    return encoding.percent_decode((str:gsub("^[^']*'[^']*'", "")))
end

function encoding.decode_rfc2047(str)
    -- Long names are split into several encoded words; the whitespace between them is not part of the name
    str = str:gsub("(%?=)%s+(=%?)", "%1%2")
    return str:gsub("=%?([^%?]+)%?([bBqQ])%?([^%?]+)%?=", function(_, enc, data)
        if enc:lower() == "q" then
            data = data:gsub("_", " ")
            data = data:gsub("=(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end)
            return data
        end

        local ok, decoded = pcall(mime.unb64, data)
        if ok and decoded then
            return decoded
        end
        return data
    end)
end

function encoding.safe_filename(name)
    name = name:gsub("[\\/:*?\"<>|]", "_")
    name = name:gsub("%c", "")

    -- Most filesystems allow 255 bytes per name; leave room for " (1)" and ".tmp"
    local max_len = 200
    if #name > max_len then
        local base, ext = name:match("^(.*)(%.[^%.]+)$")
        if base and #ext < 20 then
            base = base:sub(1, max_len - #ext)
            -- Do not cut a UTF-8 character in half
            base = base:gsub("[\192-\255][\128-\191]*$", function(tail)
                local lead = tail:byte(1)
                local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
                return #tail == need and tail or ""
            end)
            name = base .. ext
        end
    end
    return name
end

return encoding
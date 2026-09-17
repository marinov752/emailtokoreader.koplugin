local mime = require("mime")

local encoding = {}

function encoding.url_decode(str)
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

function encoding.decode_rfc2047(str)
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
    return name
end

return encoding
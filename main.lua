local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local logger = require("logger")

-- Load config
local config_path = require("ffi/util").joinPath(
    require("datastorage"):getDataDir(), 
    "plugins/sendtokoreader.koplugin/config.lua"
)

local config = {}
local ok, loaded_config = pcall(dofile, config_path)
if ok and loaded_config then
    config = loaded_config
else
    config = {
        imap_server = "imap.gmail.com",
        imap_port = 993,
        email = "your-email@gmail.com",
        password = "your-app-password",
        download_path = "/mnt/us/Books/",
        use_ssl = true,
        debug_mode = false,
    }
end

local SendToKOReader = WidgetContainer:extend{
    name = "sendtokoreader",
    is_doc_only = false,
}

function SendToKOReader:init()
    self.ui.menu:registerToMainMenu(self)
end

function SendToKOReader:addToMainMenu(menu_items)
    menu_items.sendtokoreader = {
        text = _("Email to KOReader"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Check Inbox"),
                callback = function()
                    self:checkInbox()
                end,
            },
            {
                text = _("Test Connection"),
                callback = function()
                    self:testConnection()
                end,
            },
            {
                text = _("Configure Settings"),
                callback = function()
                    self:showSettings()
                end,
            },
            {
                text = _("Advanced Settings"),
                sub_item_table = {
                    {
                        text = _("Toggle Debug Mode"),
                        checked_func = function()
                            return config.debug_mode
                        end,
                        callback = function()
                            config.debug_mode = not config.debug_mode
                            
                            -- Save to config file
                            local config_file = self.path .. "/config.lua"
                            local f = io.open(config_file, "w")
                            if f then
                                f:write("return {\n")
                                f:write(string.format('    email = "%s",\n', (config.email or ""):gsub('"', '\\"')))
                                f:write(string.format('    password = "%s",\n', (config.password or ""):gsub('"', '\\"')))
                                f:write(string.format('    imap_server = "%s",\n', (config.imap_server or "imap.gmail.com"):gsub('"', '\\"')))
                                f:write(string.format('    imap_port = %d,\n', config.imap_port or 993))
                                f:write(string.format('    use_ssl = %s,\n', config.use_ssl and "true" or "false"))
                                f:write(string.format('    download_path = "%s",\n', (config.download_path or "/mnt/us/Books/"):gsub('"', '\\"')))
                                f:write(string.format('    debug_mode = %s,\n', config.debug_mode and "true" or "false"))
                                f:write("}\n")
                                f:close()
                            end
                            
                            UIManager:show(InfoMessage:new{
                                text = config.debug_mode and 
                                    _("[OK] Debug mode enabled\nWill save debug files to download folder") or
                                    _("Debug mode disabled"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("View Debug Files Location"),
                        enabled_func = function()
                            return config.debug_mode
                        end,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _("Debug files saved to:\n" .. config.download_path .. "\n\nFilename: debug_msg_*.txt"),
                                timeout = 4,
                            })
                        end,
                    },
                },
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Email to KOReader v1.0.0\n\nAutomatically download EPUB files from email.\n\nFeatures:\n* Multiple files per email\n* Multiple emails support\n* Large file handling (up to 3.5MB)\n* Auto-refresh file browser\n* Debug mode\n* In-app configuration"),
                        timeout = 5,
                    })
                end,
            },
        },
    }
end

function SendToKOReader:showSettings()
    local InputDialog = require("ui/widget/inputdialog")
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local logger = require("logger")
    
    -- Create settings dialog
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("Send-to-KOReader Settings"),
        fields = {
            {
                text = config.email or "",
                hint = "your.email@gmail.com",
                input_type = "text",
                description = _("Email Address"),
            },
            {
                text = config.password or "",
                hint = "app-specific password",
                input_type = "text",
                text_type = "password",
                description = _("App Password"),
            },
            {
                text = config.imap_server or "imap.gmail.com",
                hint = "imap.gmail.com",
                input_type = "text",
                description = _("IMAP Server"),
            },
            {
                text = tostring(config.imap_port or 993),
                hint = "993",
                input_type = "number",
                description = _("IMAP Port"),
            },
            {
                text = config.download_path or "/mnt/us/Books/",
                hint = "/mnt/us/Books/",
                input_type = "text",
                description = _("Download Path"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = MultiInputDialog:getFields()
                        
                        -- Update config
                        config.email = fields[1]
                        config.password = fields[2]
                        config.imap_server = fields[3]
                        config.imap_port = tonumber(fields[4]) or 993
                        config.download_path = fields[5]
                        
                        -- Ensure download path ends with /
                        if not config.download_path:match("/$") then
                            config.download_path = config.download_path .. "/"
                        end
                        
                        -- Save to config file
                        local config_file = self.path .. "/config.lua"
                        local f = io.open(config_file, "w")
                        if f then
                            f:write("return {\n")
                            f:write(string.format('    email = "%s",\n', config.email:gsub('"', '\\"')))
                            f:write(string.format('    password = "%s",\n', config.password:gsub('"', '\\"')))
                            f:write(string.format('    imap_server = "%s",\n', config.imap_server:gsub('"', '\\"')))
                            f:write(string.format('    imap_port = %d,\n', config.imap_port))
                            f:write(string.format('    use_ssl = %s,\n', config.use_ssl and "true" or "false"))
                            f:write(string.format('    download_path = "%s",\n', config.download_path:gsub('"', '\\"')))
                            f:write(string.format('    debug_mode = %s,\n', config.debug_mode and "true" or "false"))
                            f:write("}\n")
                            f:close()
                            
                            UIManager:close(settings_dialog)
                            UIManager:show(InfoMessage:new{
                                text = _("[OK] Settings saved!"),
                                timeout = 2,
                            })
                            logger.info("Settings saved to", config_file)
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("[ERROR] Failed to save settings"),
                                timeout = 3,
                            })
                        end
                    end,
                },
            },
        },
    }
    
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

function SendToKOReader:testConnection()
    UIManager:show(InfoMessage:new{
        text = _("Testing connection..."),
        timeout = 1,
    })
    
    UIManager:scheduleIn(0.5, function()
        local socket_ok, socket = pcall(require, "socket")
        if not socket_ok then
            UIManager:show(InfoMessage:new{
                text = _("[ERROR] LuaSocket not available"),
                timeout = 3,
            })
            return
        end
        
        local conn = socket.tcp()
        if not conn then
            UIManager:show(InfoMessage:new{
                text = _("[ERROR] Cannot create socket"),
                timeout = 3,
            })
            return
        end
        
        conn:settimeout(5)
        local ok, err = conn:connect(config.imap_server, config.imap_port)
        conn:close()
        
        if ok then
            UIManager:show(InfoMessage:new{
                text = _("[OK] Connection successful!"),
                timeout = 3,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("[ERROR] Connection failed:\n" .. tostring(err)),
                timeout = 5,
            })
        end
    end)
end

function SendToKOReader:checkInbox()
    UIManager:show(InfoMessage:new{
        text = _("Checking inbox...\nThis may take 10-20 seconds."),
        timeout = 2,
    })
    
    UIManager:scheduleIn(1, function()
        local success, result = pcall(function()
            return self:fetchEmails()
        end)
        
        if not success then
            UIManager:show(InfoMessage:new{
                text = _("[ERROR] Error:\n" .. tostring(result)),
                timeout = 5,
            })
        elseif result.success then
            if result.downloaded > 0 then
                local message = "[OK] Downloaded " .. result.downloaded .. " book(s)!"
                if result.files and #result.files > 0 then
                    message = message .. "\n\n"
                    for i, filename in ipairs(result.files) do
                        message = message .. "* " .. filename .. "\n"
                    end
                end
                
                UIManager:show(InfoMessage:new{
                    text = _(message),
                    timeout = 5,
                })
                
                -- Schedule file browser refresh after a short delay
                -- This ensures files are fully written to disk
                UIManager:scheduleIn(0.5, function()
                    -- Refresh file browser if it's open
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then
                        FileManager.instance:onRefresh()
                        -- Force a screen update to show new files
                        UIManager:setDirty(FileManager.instance, "ui")
                        logger.info("File browser refreshed")
                    end
                    
                    -- Force a full screen refresh to fix any UI glitches
                    UIManager:setDirty("all", "full")
                    logger.info("Full screen refresh triggered")
                end)
            else
                UIManager:show(InfoMessage:new{
                    text = _("No new EPUB files found."),
                    timeout = 3,
                })
            end
        else
            UIManager:show(InfoMessage:new{
                text = _("[ERROR] " .. (result.error or "Unknown error")),
                timeout = 5,
            })
        end
    end)
end

function SendToKOReader:fetchEmails()
    -- Base64 decode function
    local function base64_decode(data)
        local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        data = string.gsub(data, '[^'..b..'=]', '')
        return (data:gsub('.', function(x)
            if (x == '=') then return '' end
            local r,f='',(b:find(x)-1)
            for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
            return r;
        end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
            if (#x ~= 8) then return '' end
            local c=0
            for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
        end))
    end
    
    -- Safe file write using standard io
    local function writeFile(filepath, data)
        -- Write to temp file first (atomic write pattern)
        local temp_file = filepath .. ".tmp"
        
        local f, err = io.open(temp_file, "wb")
        if not f then
            return false, "Cannot open temp file: " .. tostring(err)
        end
        
        -- Write in chunks to avoid memory issues
        local chunk_size = 8192
        for i = 1, #data, chunk_size do
            local chunk = data:sub(i, math.min(i + chunk_size - 1, #data))
            f:write(chunk)
        end
        f:close()
        
        -- Atomic rename
        os.remove(filepath) -- Remove if exists
        local rename_ok = os.rename(temp_file, filepath)
        if not rename_ok then
            os.remove(temp_file)
            return false, "Rename failed"
        end
        
        return true
    end
    
    -- Check socket
    local socket_ok, socket = pcall(require, "socket")
    if not socket_ok then
        return {success = false, error = "LuaSocket not available"}
    end
    
    -- Connect
    local conn = socket.tcp()
    if not conn then
        return {success = false, error = "Cannot create socket"}
    end
    
    conn:settimeout(10)
    
    local ok, err = conn:connect(config.imap_server, config.imap_port)
    if not ok then
        conn:close()
        return {success = false, error = "Connection failed: " .. tostring(err)}
    end
    
    -- SSL wrap
    if config.use_ssl then
        local ssl_ok, ssl = pcall(require, "ssl")
        if ssl_ok then
            conn = ssl.wrap(conn, {
                mode = "client",
                protocol = "tlsv1_2",
                verify = "none",
            })
            conn:dohandshake()
        end
    end
    
    -- Read greeting
    conn:receive("*l")
    
    -- Login
    conn:send(string.format('A001 LOGIN "%s" "%s"\r\n', config.email, config.password))
    
    local login_ok = false
    for i = 1, 5 do
        local line = conn:receive("*l")
        if line and line:match("^A001 OK") then
            login_ok = true
            break
        end
    end
    
    if not login_ok then
        conn:close()
        return {success = false, error = "Login failed"}
    end
    
    -- Select INBOX
    conn:send("A002 SELECT INBOX\r\n")
    for i = 1, 10 do
        local line = conn:receive("*l")
        if line and line:match("^A002 OK") then break end
    end
    
    -- Search unseen
    conn:send("A003 SEARCH UNSEEN\r\n")
    local search_line = conn:receive("*l")
    
    local message_ids = {}
    if search_line then
        for id in search_line:gmatch("%d+") do
            table.insert(message_ids, id)
        end
    end
    conn:receive("*l") -- OK line
    
    logger.info("Found", #message_ids, "unseen messages")
    
    -- Limit messages to prevent memory issues
    -- Each large EPUB (2MB+) can be 20K+ lines of base64
    local max_messages = 3
    if #message_ids > max_messages then
        logger.warn("Too many messages, processing only first", max_messages)
        local limited_ids = {}
        for i = 1, max_messages do
            table.insert(limited_ids, message_ids[i])
        end
        message_ids = limited_ids
    end
    
    local downloaded = 0
    local downloaded_files = {}
    
    -- Process messages
    for _, msg_id in ipairs(message_ids) do
        logger.info("Processing message", msg_id)
        conn:send(string.format("A%d FETCH %s BODY[]\r\n", 100 + tonumber(msg_id), msg_id))
        
        -- Debug: save raw lines if debug mode enabled
        local debug_lines = config.debug_mode and {} or nil
        
        -- Track all attachments in this email
        local attachments = {}
        local current_attachment = nil
        
        local line_count = 0
        local in_headers = false
        
        while true do
            local line = conn:receive("*l")
            if not line then break end
            line_count = line_count + 1
            
            -- Save for debug
            if debug_lines and line_count <= 500 then
                table.insert(debug_lines, line)
            end
            
            -- End of this message
            if line:match("^A%d+ OK") then 
                break 
            end
            
            -- Look for EPUB filename in headers
            local fn = line:match('filename="([^"]*%.epub)"')
            if not fn then fn = line:match('name="([^"]*%.epub)"') end
            if not fn then fn = line:match("filename=([^%s;]+%.epub)") end
            if not fn then fn = line:match("name=([^%s;]+%.epub)") end
            
            if fn then
                -- Save previous attachment if exists
                if current_attachment and #current_attachment.base64_chunks > 0 then
                    table.insert(attachments, current_attachment)
                end
                
                -- Start new attachment
                current_attachment = {
                    filename = fn,
                    base64_chunks = {},
                    in_base64 = false,
                    in_headers = true
                }
                logger.info("Found EPUB filename:", fn)
            end
            
            -- Track if we're in attachment headers
            if current_attachment then
                if line:match("[Cc]ontent%-[Tt]ransfer%-[Ee]ncoding:%s*base64") then
                    logger.info("Found base64 encoding marker for", current_attachment.filename)
                    current_attachment.in_headers = false
                end
                
                -- Empty line after headers = start of base64
                if not current_attachment.in_headers and not current_attachment.in_base64 then
                    if line == "" then
                        current_attachment.in_base64 = true
                        logger.info("Starting base64 collection for", current_attachment.filename)
                    end
                end
                
                -- Collect base64 data
                if current_attachment.in_base64 then
                    if line:match("^[A-Za-z0-9+/=]+$") and #line > 10 then
                        table.insert(current_attachment.base64_chunks, line)
                    elseif line:match("^%-%-") or line:match("^[A-Z][a-z]+%-") then
                        -- Boundary - end of this attachment
                        logger.info("Found boundary for", current_attachment.filename, "- collected", #current_attachment.base64_chunks, "lines")
                        table.insert(attachments, current_attachment)
                        current_attachment = nil
                    end
                end
            end
            
            -- Safety limit per message (large EPUBs can be 20K+ lines)
            if line_count > 25000 then
                logger.warn("Safety limit reached at 25000 lines, stopping message", msg_id)
                -- Only save current attachment if it hasn't been saved yet (still collecting)
                if current_attachment and current_attachment.in_base64 and #current_attachment.base64_chunks > 0 then
                    logger.info("Saving incomplete attachment at safety limit:", current_attachment.filename)
                    table.insert(attachments, current_attachment)
                end
                
                -- CRITICAL: Consume rest of message until we see the OK response
                -- Otherwise next FETCH will read leftover data from this message!
                logger.warn("Consuming rest of message to find OK response...")
                local consumed = 0
                while true do
                    local rest_line = conn:receive("*l")
                    if not rest_line then break end
                    consumed = consumed + 1
                    if rest_line:match("^A%d+ OK") then
                        logger.info("Found OK after consuming", consumed, "more lines")
                        break
                    end
                    -- Safety: don't consume forever
                    if consumed > 10000 then
                        logger.warn("Gave up consuming after 10K lines")
                        break
                    end
                end
                
                break
            end
        end
        
        -- Save last attachment if exists
        if current_attachment and #current_attachment.base64_chunks > 0 then
            table.insert(attachments, current_attachment)
        end
        
        logger.info("Found", #attachments, "EPUB attachment(s) in message", msg_id)
        
        -- Remove duplicates (same filename + same size)
        local unique_attachments = {}
        local seen = {}
        for _, att in ipairs(attachments) do
            local key = att.filename .. ":" .. #att.base64_chunks
            if not seen[key] then
                seen[key] = true
                table.insert(unique_attachments, att)
            else
                logger.warn("Skipping duplicate:", att.filename)
            end
        end
        attachments = unique_attachments
        logger.info("After deduplication:", #attachments, "unique attachment(s)")
        
        -- Save debug file
        if debug_lines then
            local debug_file = config.download_path .. "debug_msg_" .. msg_id .. ".txt"
            local df = io.open(debug_file, "w")
            if df then
                df:write("=== MESSAGE " .. msg_id .. " DEBUG ===\n")
                df:write("Total lines: " .. line_count .. "\n")
                df:write("Found attachments: " .. #attachments .. "\n")
                for i, att in ipairs(attachments) do
                    df:write("  Attachment " .. i .. ": " .. att.filename .. " (" .. #att.base64_chunks .. " base64 lines)\n")
                end
                df:write("\n=== FIRST 500 LINES ===\n")
                df:write(table.concat(debug_lines, "\n"))
                df:close()
                logger.info("Debug saved to:", debug_file)
            end
        end
        
        -- Process all attachments
        for _, attachment in ipairs(attachments) do
            -- Safety check
            if not attachment or not attachment.base64_chunks or #attachment.base64_chunks == 0 then
                logger.warn("Skipping invalid attachment")
                goto continue
            end
            
            local base64_data = table.concat(attachment.base64_chunks, "")
            logger.info("Processing:", attachment.filename, "Base64 size:", #base64_data)
            
            -- Clear chunks from memory
            attachment.base64_chunks = nil
            collectgarbage("collect")
            
            -- Size check
            if #base64_data > 5000000 then
                logger.warn("File too large, skipping:", attachment.filename)
            elseif #base64_data < 100 then
                logger.warn("Base64 too small, skipping:", attachment.filename)
            else
                -- Decode
                logger.info("Decoding", attachment.filename)
                local decode_ok, decoded = pcall(base64_decode, base64_data)
                base64_data = nil
                collectgarbage("collect")
                
                if decode_ok and decoded and #decoded > 0 then
                    logger.info("Decoded to", #decoded, "bytes")
                    local filepath = config.download_path .. attachment.filename
                    
                    local write_ok, write_err = pcall(writeFile, filepath, decoded)
                    decoded = nil
                    collectgarbage("collect")
                    
                    if write_ok and write_err ~= false then
                        downloaded = downloaded + 1
                        table.insert(downloaded_files, attachment.filename)
                        logger.info("✓ Saved:", attachment.filename, "to", filepath)
                    else
                        logger.err("✗ Write failed for", attachment.filename, ":", write_err or "error")
                    end
                else
                    logger.err("✗ Decode failed for", attachment.filename)
                end
            end
            
            ::continue::
        end
        
        -- Force GC after each message
        collectgarbage("collect")
    end
    
    conn:send("A999 LOGOUT\r\n")
    conn:close()
    
    -- Final cleanup
    collectgarbage("collect")
    
    return {success = true, downloaded = downloaded, files = downloaded_files}
end

return SendToKOReader

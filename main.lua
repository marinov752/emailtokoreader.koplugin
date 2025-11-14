local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local logger = require("logger")

-- Load config
local config_path = require("ffi/util").joinPath(
    require("datastorage"):getDataDir(), 
    "plugins/emailtokoreader.koplugin/config.lua"
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

-- Validate and set safe fallback path
local function validate_and_set_download_path()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok then
        logger.warn("Cannot load datastorage module, using default path")
        return
    end
    
    local ok2, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok2 then
        logger.warn("Cannot load lfs module, skipping path validation")
        return
    end
    
    -- Get user's home directory from global reader settings as fallback
    local safe_fallback_path
    
    -- Try to get home_dir from G_reader_settings (global settings)
    local ok_settings, G_reader_settings = pcall(require, "luasettings")
    if ok_settings then
        local ok_open, settings = pcall(G_reader_settings.open, G_reader_settings, 
            DataStorage:getDataDir() .. "/settings.reader.lua")
        if ok_open and settings then
            local ok_read, userHome = pcall(settings.readSetting, settings, "home_dir")
            if ok_read and userHome and userHome ~= "" then
                -- Use user's home directory
                safe_fallback_path = userHome
                if not safe_fallback_path:match("/$") then
                    safe_fallback_path = safe_fallback_path .. "/"
                end
                logger.info("Using user home directory as fallback:", safe_fallback_path)
            end
        end
    end
    
    -- If we couldn't get user home, try DocSettings as alternative
    if not safe_fallback_path then
        local ok_doc, DocSettings = pcall(require, "docsettings")
        if ok_doc then
            local ok_fm, fm_settings = pcall(DocSettings.open, DocSettings, "filemanager_settings")
            if ok_fm and fm_settings then
                local ok_read, userHome = pcall(fm_settings.readSetting, fm_settings, "home_dir")
                if ok_read and userHome and userHome ~= "" then
                    safe_fallback_path = userHome
                    if not safe_fallback_path:match("/$") then
                        safe_fallback_path = safe_fallback_path .. "/"
                    end
                    logger.info("Using file manager home directory as fallback:", safe_fallback_path)
                end
            end
        end
    end
    
    -- If we still couldn't get user home, fall back to KOReader data directory
    if not safe_fallback_path then
        local koreader_home = DataStorage:getDataDir()
        safe_fallback_path = koreader_home .. "/downloads/"
        logger.info("Using KOReader data directory as fallback:", safe_fallback_path)
    end
    
    -- Check if configured path exists and is writable
    local path_valid = false
    if config.download_path then
        -- Ensure path ends with /
        if not config.download_path:match("/$") then
            config.download_path = config.download_path .. "/"
        end
        
        -- Check if directory exists
        local ok_attr, attr = pcall(lfs.attributes, config.download_path)
        if ok_attr and attr and attr.mode == "directory" then
            -- Try to create a test file to verify write permission
            local test_file = config.download_path .. ".koreader_write_test"
            local f = io.open(test_file, "w")
            if f then
                f:close()
                os.remove(test_file)
                path_valid = true
                logger.info("Download path validated:", config.download_path)
            else
                logger.warn("Download path not writable:", config.download_path)
            end
        else
            logger.warn("Download path does not exist:", config.download_path)
        end
    end
    
    -- Use fallback if path is invalid
    if not path_valid then
        logger.warn("Configured path invalid, using fallback:", safe_fallback_path)
        
        -- Create fallback directory if it doesn't exist
        local ok_fallback, fallback_attr = pcall(lfs.attributes, safe_fallback_path)
        if not (ok_fallback and fallback_attr) then
            local ok_mkdir, result = pcall(lfs.mkdir, safe_fallback_path)
            if ok_mkdir and result then
                logger.info("Created fallback directory:", safe_fallback_path)
            else
                logger.warn("Could not create fallback directory:", safe_fallback_path)
            end
        end
        
        config.download_path = safe_fallback_path
        config.using_fallback_path = true
    else
        config.using_fallback_path = false
    end
end

-- Validate path at startup
local ok_validate = pcall(validate_and_set_download_path)
if not ok_validate then
    logger.warn("Path validation failed, using configured path as-is")
end

local emailtokoreader = WidgetContainer:extend{
    name = "Email to KOReader",
    is_doc_only = false,
}

function emailtokoreader:init()
    self.ui.menu:registerToMainMenu(self)
end

function emailtokoreader:addToMainMenu(menu_items)
    menu_items.emailtokoreader = {
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
                text = _("View Download Path"),
                callback = function()
                    local path_status = config.using_fallback_path and 
                        "⚠ FALLBACK PATH (configured path invalid)" or
                        "Configured path"
                    
                    UIManager:show(InfoMessage:new{
                        text = _(path_status .. "\n\nDownloading to:\n" .. config.download_path),
                        timeout = 4,
                    })
                end,
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Email to KOReader v1.1.1\n\nAutomatically download EPUB files from email.\n\nFeatures:\n* Multiple files per email\n* Multiple emails support\n* Large file handling (up to 3.5MB)\n* Auto-refresh file browser\n* Debug mode\n* In-app configuration\n* Cyrillic filename support\n* Auto-transliteration\n* Safe fallback path"),
                        timeout = 5,
                    })
                end,
            },
        },
    }
end

function emailtokoreader:showSettings()
    local InputDialog = require("ui/widget/inputdialog")
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local logger = require("logger")
    
    -- Create settings dialog
    local settings_dialog
    settings_dialog = MultiInputDialog:new{
        title = _("Mail to KOReader Settings"),
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
                        local fields = settings_dialog:getFields()
                        
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

function emailtokoreader:testConnection()
    -- Validate configuration first
    if not config.email or config.email == "" or config.email == "your-email@gmail.com" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] Email not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

    if not config.password or config.password == "" or config.password == "your-app-password" or config.password == "your-app-password-here" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] Password not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

    if not config.imap_server or config.imap_server == "" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] IMAP server not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

    UIManager:show(
        InfoMessage:new {
            text = _("Testing email connection...\nThis may take a few seconds."),
            timeout = 2
        }
    )

    UIManager:scheduleIn(
        0.5,
        function()
            local socket = require("socket")
            if not socket then
                UIManager:show(
                    InfoMessage:new {
                        text = _("[ERROR] Socket library not available"),
                        timeout = 4
                    }
                )
                return
            end

            -- Test connection
            local conn = socket.tcp()
            if not conn then
                UIManager:show(
                    InfoMessage:new {
                        text = _("[ERROR] Could not create socket"),
                        timeout = 4
                    }
                )
                return
            end

            conn:settimeout(10)
            local ok, err = conn:connect(config.imap_server, config.imap_port)

            if not ok then
                conn:close()
                UIManager:show(
                    InfoMessage:new {
                        text = _("[ERROR] Connection failed:\n" .. tostring(err)),
                        timeout = 5
                    }
                )
                return
            end

            -- SSL wrap if enabled
            if config.use_ssl then
                local ssl_ok, ssl = pcall(require, "ssl")
                if ssl_ok then
                    conn =
                        ssl.wrap(
                        conn,
                        {
                            mode = "client",
                            protocol = "tlsv1_2",
                            verify = "none"
                        }
                    )
                    local handshake_ok, handshake_err = conn:dohandshake()
                    if not handshake_ok then
                        conn:close()
                        UIManager:show(
                            InfoMessage:new {
                                text = _("[ERROR] SSL handshake failed:\n" .. tostring(handshake_err)),
                                timeout = 5
                            }
                        )
                        return
                    end
                else
                    conn:close()
                    UIManager:show(
                        InfoMessage:new {
                            text = _("[ERROR] SSL not available but use_ssl is enabled"),
                            timeout = 4
                        }
                    )
                    return
                end
            end

            -- Read greeting
            local greeting = conn:receive("*l")
            if not greeting then
                conn:close()
                UIManager:show(
                    InfoMessage:new {
                        text = _("[ERROR] No response from server"),
                        timeout = 4
                    }
                )
                return
            end

            logger.info("IMAP greeting:", greeting)

            -- Try to login (this will test credentials without marking emails as read)
            conn:send(string.format('A001 LOGIN "%s" "%s"\r\n', config.email, config.password))

            local login_ok = false
            local login_response = ""
            for i = 1, 5 do
                local line = conn:receive("*l")
                if line then
                    login_response = login_response .. line .. "\n"
                    if line:match("^A001 OK") then
                        login_ok = true
                        break
                    elseif line:match("^A001 NO") or line:match("^A001 BAD") then
                        break
                    end
                end
            end

            -- Logout immediately (we don't need to do anything else)
            conn:send("A002 LOGOUT\r\n")
            conn:receive("*l") -- Consume response
            conn:close()

            if login_ok then
                UIManager:show(
                    InfoMessage:new {
                        text = _(
                            "[OK] Connection successful!\n\nYour email account is properly configured and ready to use."
                        ),
                        timeout = 4
                    }
                )
                logger.info("Connection test successful")
            else
                logger.warn("Login failed:", login_response)
                UIManager:show(
                    InfoMessage:new {
                        text = _(
                            "[ERROR] Login failed!\n\nPlease check your email and password.\n\nFor Gmail, make sure you're using an App Password, not your regular password."
                        ),
                        timeout = 6
                    }
                )
            end
        end
    )
end

function emailtokoreader:checkInbox()
    -- Validate configuration before checking inbox
    if not config.email or config.email == "" or config.email == "your-email@gmail.com" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] Email not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

    if not config.password or config.password == "" or config.password == "your-app-password" or config.password == "your-app-password-here" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] Password not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

    if not config.imap_server or config.imap_server == "" then
        UIManager:show(
            InfoMessage:new {
                text = _("[ERROR] IMAP server not configured!\n\nPlease configure your settings first."),
                timeout = 4
            }
        )
        return
    end

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
                
                -- Add warning if using fallback path
                if config.using_fallback_path then
                    message = message .. "\n⚠ Using fallback path:\n" .. config.download_path
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

function emailtokoreader:fetchEmails()
												 
													 
	
								   
								   
																   
	   
    -- URL decode function (for RFC 2231 encoded filenames)
    local function url_decode(str)
        str = string.gsub(str, "+", " ")
        str = string.gsub(str, "%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        return str
    end
    
    -- Decode RFC 2047 encoded-word (=?charset?encoding?data?=)
    local function decode_rfc2047(str)
        -- Pattern: =?charset?encoding?encoded-text?=
        local decoded = str:gsub("=%?([^%?]+)%?([bBqQ])%?([^%?]+)%?=", function(charset, encoding, data)
            if encoding:lower() == "b" then
                -- Base64 encoding
                local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
                data = string.gsub(data, '[^'..b..'=]', '')
                local decoded = (data:gsub('.', function(x)
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
                return decoded
            elseif encoding:lower() == "q" then
                -- Quoted-printable encoding
                data = data:gsub("_", " ")
                data = data:gsub("=(%x%x)", function(h)
                    return string.char(tonumber(h, 16))
                end)
                return data
            end
            return data
        end)
        return decoded
    end
    
    -- Decode filename from various email encoding formats
    local function decode_filename(filename)
        if not filename then return nil end
        
        -- Remove surrounding quotes if present
        filename = filename:gsub('^"(.*)"$', '%1')
        
        -- RFC 2047: =?charset?encoding?data?=
        if filename:match("=%?") then
            -- First, remove whitespace (tabs, spaces, newlines) between adjacent encoded-words
            -- RFC 2047: whitespace between encoded-words should be ignored
            -- This handles Unix (\n), Windows (\r\n), and tabs (\t)
            filename = filename:gsub("(%?=)%s*(%=%?)", "%1%2")
            
            -- Now decode all encoded-words
            filename = decode_rfc2047(filename)
        end
        
        -- RFC 2231: charset''encoded-data (already extracted from filename*= parameter)
        -- This is handled in the extraction pattern
        
        return filename
    end
    
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
    
    -- Transliterate Cyrillic to Latin characters
    local function transliterate_filename(filename)
        -- Cyrillic to Latin transliteration table (Bulgarian/Russian)
        local cyrillic_to_latin = {
            -- Uppercase
            ['А'] = 'A', ['Б'] = 'B', ['В'] = 'V', ['Г'] = 'G', ['Д'] = 'D',
            ['Е'] = 'E', ['Ж'] = 'Zh', ['З'] = 'Z', ['И'] = 'I', ['Й'] = 'Y',
            ['К'] = 'K', ['Л'] = 'L', ['М'] = 'M', ['Н'] = 'N', ['О'] = 'O',
            ['П'] = 'P', ['Р'] = 'R', ['С'] = 'S', ['Т'] = 'T', ['У'] = 'U',
            ['Ф'] = 'F', ['Х'] = 'H', ['Ц'] = 'Ts', ['Ч'] = 'Ch', ['Ш'] = 'Sh',
            ['Щ'] = 'Sht', ['Ъ'] = 'A', ['Ь'] = 'Y', ['Ю'] = 'Yu', ['Я'] = 'Ya',
            ['Ы'] = 'Y', ['Э'] = 'E', ['Ё'] = 'Yo',
            
            -- Lowercase
            ['а'] = 'a', ['б'] = 'b', ['в'] = 'v', ['г'] = 'g', ['д'] = 'd',
            ['е'] = 'e', ['ж'] = 'zh', ['з'] = 'z', ['и'] = 'i', ['й'] = 'y',
            ['к'] = 'k', ['л'] = 'l', ['м'] = 'm', ['н'] = 'n', ['о'] = 'o',
            ['п'] = 'p', ['р'] = 'r', ['с'] = 's', ['т'] = 't', ['у'] = 'u',
            ['ф'] = 'f', ['х'] = 'h', ['ц'] = 'ts', ['ч'] = 'ch', ['ш'] = 'sh',
            ['щ'] = 'sht', ['ъ'] = 'a', ['ь'] = 'y', ['ю'] = 'yu', ['я'] = 'ya',
            ['ы'] = 'y', ['э'] = 'e', ['ё'] = 'yo',
        }
        
        -- Process each byte/character
        local result = {}
        local i = 1
        while i <= #filename do
            local byte = filename:byte(i)
            
            -- Check if this is a UTF-8 multi-byte character
            if byte >= 0xC0 and byte <= 0xDF and i + 1 <= #filename then
                -- 2-byte UTF-8 character
                local char = filename:sub(i, i + 1)
                local transliterated = cyrillic_to_latin[char]
                if transliterated then
                    table.insert(result, transliterated)
                else
                    table.insert(result, char)  -- Keep unknown characters as-is
                end
                i = i + 2
            elseif byte >= 0xE0 and byte <= 0xEF and i + 2 <= #filename then
                -- 3-byte UTF-8 character
                local char = filename:sub(i, i + 2)
                local transliterated = cyrillic_to_latin[char]
                if transliterated then
                    table.insert(result, transliterated)
                else
                    table.insert(result, char)  -- Keep unknown characters as-is
                end
                i = i + 3
            else
                -- ASCII or single byte
                table.insert(result, filename:sub(i, i))
                i = i + 1
            end
        end
        
        return table.concat(result)
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
        local previous_line = ""  -- For handling header continuation
        
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
            
            -- RFC 2822: Header continuation - lines starting with whitespace
            -- continue the previous header line
            local is_continuation = line:match("^%s") and previous_line ~= ""
            if is_continuation then
                -- Merge with previous line (remove the line break)
                previous_line = previous_line .. line
                line = previous_line
            else
                -- Process the completed previous line if it exists
                if previous_line ~= "" then
                    -- Try to extract filename from previous_line
                    local fn = nil
                    
                    -- RFC 2231: filename*=charset''encoded-data
                    if not fn then
                        local encoded = previous_line:match('filename%*=utf%-8\'\'([^%s;]+%.epub)')
                        if encoded then
                            fn = url_decode(encoded)
                            logger.info("Decoded RFC 2231 filename:", fn)
                        end
                    end
                    if not fn then
                        local encoded = previous_line:match('filename%*=utf%-8\'\'([^%s;]+%.[Ee][Pp][Uu][Bb])')
                        if encoded then
                            fn = url_decode(encoded)
                            logger.info("Decoded RFC 2231 filename:", fn)
                        end
                    end
                    if not fn then
                        local encoded = previous_line:match('name%*=utf%-8\'\'([^%s;]+%.epub)')
                        if encoded then
                            fn = url_decode(encoded)
                            logger.info("Decoded RFC 2231 filename:", fn)
                        end
                    end
                    if not fn then
                        local encoded = previous_line:match('name%*=utf%-8\'\'([^%s;]+%.[Ee][Pp][Uu][Bb])')
                        if encoded then
                            fn = url_decode(encoded)
                            logger.info("Decoded RFC 2231 filename:", fn)
                        end
                    end
                    
                    -- Standard patterns (quoted): filename="..." or name="..."
                    -- First try with .epub in pattern (fast path for non-encoded filenames)
                    if not fn then fn = previous_line:match('filename="([^"]*%.epub)"') end
                    if not fn then fn = previous_line:match('name="([^"]*%.epub)"') end
                    if not fn then fn = previous_line:match('filename="([^"]*%.[Ee][Pp][Uu][Bb])"') end
                    if not fn then fn = previous_line:match('name="([^"]*%.[Ee][Pp][Uu][Bb])"') end
                    
                    -- If not found but line has RFC 2047 encoding, try without .epub requirement
                    -- and check after decoding
                    if not fn and previous_line:match("=%?") then
                        -- Try to extract any quoted filename/name value
                        local raw_fn = previous_line:match('filename="([^"]+)"')
                        if not raw_fn then raw_fn = previous_line:match('name="([^"]+)"') end
                        
                        if raw_fn then
                            -- Decode it
                            local decoded_fn = decode_filename(raw_fn)
                            -- Check if decoded value ends with .epub
                            if decoded_fn and (decoded_fn:match("%.epub$") or decoded_fn:match("%.[Ee][Pp][Uu][Bb]$")) then
                                fn = decoded_fn
                                logger.info("Found RFC 2047 encoded EPUB filename:", fn)
                            end
                        end
                    end
                    
                    -- Unquoted patterns (less common)
                    if not fn then fn = previous_line:match("filename=([^%s;]+%.epub)") end
                    if not fn then fn = previous_line:match("name=([^%s;]+%.epub)") end
                    if not fn then fn = previous_line:match("filename=([^%s;]+%.[Ee][Pp][Uu][Bb])") end
                    if not fn then fn = previous_line:match("name=([^%s;]+%.[Ee][Pp][Uu][Bb])") end
                    
                    -- Decode filename if found (for cases caught by fast path)
                    if fn and fn:match("=%?") then
                        fn = decode_filename(fn)
                    end
                    
                    -- If we found a valid EPUB filename, create attachment
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
                end
                
                -- Save current line for potential continuation
                previous_line = line
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
                    
                    -- Transliterate Cyrillic filename to Latin for filesystem compatibility
                    local original_filename = attachment.filename
                    local transliterated_filename = transliterate_filename(original_filename)
                    
                    -- Log if filename was changed
                    if original_filename ~= transliterated_filename then
                        logger.info("Transliterated filename:", original_filename, "->", transliterated_filename)
                    end
                    
                    local filepath = config.download_path .. transliterated_filename
                    
                    -- Ensure directory exists
                    local lfs = require("libs/libkoreader-lfs")
                    local dir_path = filepath:match("^(.*/)")
                    if dir_path then
                        local attr = lfs.attributes(dir_path)
                        if not attr then
                            logger.warn("Download directory does not exist:", dir_path)
                            logger.info("Attempting to create directory:", dir_path)
                            local success = lfs.mkdir(dir_path)
                            if success then
                                logger.info("Created directory:", dir_path)
                            else
                                logger.err("Failed to create directory:", dir_path)
                            end
                        end
                    end
                    
                    local write_ok, write_result, write_err = pcall(writeFile, filepath, decoded)
                    decoded = nil
                    collectgarbage("collect")
                    
                    if write_ok and write_result == true then
                        downloaded = downloaded + 1
                        table.insert(downloaded_files, transliterated_filename)
                        logger.info("✓ Saved:", transliterated_filename, "to", filepath)
                    else
                        local error_msg = write_err or (not write_ok and tostring(write_result)) or "unknown error"
                        logger.err("✗ Write failed for", transliterated_filename, ":", error_msg)
                        logger.err("   Path:", filepath)
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

return emailtokoreader
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local DownloadMgr = require("ui/downloadmgr")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local DataStorage = require("datastorage")

-- 1. Safely load the config bypassing KOReader's internal require() paths
local config_path = require("ffi/util").joinPath(
    DataStorage:getDataDir(), 
    "plugins/emailtokoreader.koplugin/config.lua"
)

local config = {}
local config_ok, loaded_config = pcall(dofile, config_path)
if config_ok and loaded_config then
    config = loaded_config
else
    -- Safe fallbacks so the plugin doesn't crash if config.lua is missing
    config = {
        imap_server = "imap.gmail.com",
        imap_port = 993,
        use_ssl = true,
        download_path = "/mnt/us/documents/"
    }
end

-- 2. Load our local modules
local imap = require("imap")
local attachment = require("attachment")

-- Used when neither the UI settings nor config.lua provide a value
local DEFAULT_EXTENSIONS = {"epub"}
-- Extensions always offered in the menu; anything configured elsewhere is added on top
local MENU_EXTENSIONS = {"epub", "acsm", "pdf", "mobi", "cbz"}

-- 3. Writing config.lua back from the settings dialog
-- Known keys are written first in this order; any other keys follow alphabetically
local CONFIG_KEY_ORDER = {
    "email", "password", "imap_server", "imap_port", "use_ssl",
    "download_path", "allowed_extensions",
}

local LUA_KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in
    local nil not or repeat return then true until while]]):gmatch("%a+") do
    LUA_KEYWORDS[word] = true
end

local serialize_value

local function serialize_key(key, indent)
    if type(key) == "string" and key:match("^[%a_][%w_]*$") and not LUA_KEYWORDS[key] then
        return key
    end
    return "[" .. serialize_value(key, indent) .. "]"
end

local function sorted_keys(tbl, skip)
    local array_len = #tbl
    local keys = {}
    for k in pairs(tbl) do
        local is_array_index = type(k) == "number" and k >= 1 and k <= array_len and k % 1 == 0
        if not is_array_index and not (skip and skip[k]) then
            table.insert(keys, k)
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- Error messages only name the offending type, never the value (the password lives in here)
serialize_value = function(value, indent)
    local value_type = type(value)
    if value_type == "string" then
        return string.format("%q", value)
    elseif value_type == "boolean" then
        return tostring(value)
    elseif value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot save a non-finite number")
        end
        return tostring(value)
    elseif value_type == "table" then
        local inner = indent .. "    "
        local parts = {}
        for i = 1, #value do
            table.insert(parts, inner .. serialize_value(value[i], inner))
        end
        for _, k in ipairs(sorted_keys(value)) do
            table.insert(parts, inner .. serialize_key(k, inner) .. " = " .. serialize_value(value[k], inner))
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
    end
    error("cannot save a value of type " .. value_type)
end

local function serialize_config(cfg)
    local parts = {}
    local known = {}
    for _, k in ipairs(CONFIG_KEY_ORDER) do
        known[k] = true
        if cfg[k] ~= nil then
            table.insert(parts, "    " .. k .. " = " .. serialize_value(cfg[k], "    "))
        end
    end
    for _, k in ipairs(sorted_keys(cfg, known)) do
        table.insert(parts, "    " .. serialize_key(k, "    ") .. " = " .. serialize_value(cfg[k], "    "))
    end
    return "return {\n" .. table.concat(parts, ",\n") .. ",\n}\n"
end

-- Writes to a temp file first so a failed write can't leave a truncated config.lua behind
local function write_config(cfg)
    local ok, content = pcall(serialize_config, cfg)
    if not ok then return false, content end

    local tmp_path = config_path .. ".tmp"
    local file, open_err = io.open(tmp_path, "w")
    if not file then return false, open_err end

    local written, write_err = file:write(content)
    local closed, close_err = file:close()
    if not written or not closed then
        os.remove(tmp_path)
        return false, write_err or close_err
    end

    local renamed, rename_err = os.rename(tmp_path, config_path)
    if not renamed then
        os.remove(tmp_path)
        return false, rename_err
    end
    return true
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local TRUE_WORDS = { ["true"] = true, yes = true, on = true, ["1"] = true }
local FALSE_WORDS = { ["false"] = true, no = true, off = true, ["0"] = true }

local plugin = WidgetContainer:extend{
    name = "Email to KOReader",
    is_doc_only = false,
}

function plugin:init()
    -- Lives in KOReader's settings dir, so it survives plugin updates
    self.settings = LuaSettings:open(
        DataStorage:getSettingsDir() .. "/emailtokoreader.lua"
    )
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- Makes "Check Inbox" assignable to gestures, keys, profiles and the QuickMenu
function plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("emailtokoreader_check_inbox", {
        category = "none",
        event = "EmailToKOReaderCheckInbox",
        title = _("Email to KOReader: check inbox"),
        general = true,
    })
end

function plugin:onEmailToKOReaderCheckInbox()
    self:checkInbox()
    return true
end

-- Precedence for both settings: menu choice > config.lua > built-in default
function plugin:getDownloadPath()
    return self.settings:readSetting("download_path")
        or config.download_path
        or "/mnt/us/documents/"
end

function plugin:getAllowedExtensions()
    return self.settings:readSetting("allowed_extensions")
        or config.allowed_extensions
        or DEFAULT_EXTENSIONS
end

local function normalize_extension(ext)
    return tostring(ext):lower():match("^%.?(.+)$")
end

function plugin:isExtensionEnabled(ext)
    for _, e in ipairs(self:getAllowedExtensions()) do
        if normalize_extension(e) == ext then return true end
    end
    return false
end

function plugin:toggleExtension(ext)
    local updated = {}
    local was_enabled = false

    for _, e in ipairs(self:getAllowedExtensions()) do
        if normalize_extension(e) == ext then
            was_enabled = true
        else
            table.insert(updated, normalize_extension(e))
        end
    end

    if not was_enabled then
        table.insert(updated, ext)
    end

    self.settings:saveSetting("allowed_extensions", updated)
    self.settings:flush()
end

function plugin:genExtensionMenu()
    local items = {}
    local seen = {}

    local function add(raw_ext)
        local ext = normalize_extension(raw_ext)
        if ext and not seen[ext] then
            seen[ext] = true
            table.insert(items, {
                text = "." .. ext,
                keep_menu_open = true,
                checked_func = function()
                    return self:isExtensionEnabled(ext)
                end,
                callback = function()
                    self:toggleExtension(ext)
                end,
            })
        end
    end

    for _, ext in ipairs(MENU_EXTENSIONS) do add(ext) end
    -- Show extensions that only exist in config.lua so they can be switched off too
    for _, ext in ipairs(self:getAllowedExtensions()) do add(ext) end

    return items
end

function plugin:chooseDownloadFolder()
    local start_path = self:getDownloadPath()
    -- PathChooser falls back to the last used directory when given nil
    if not lfs.attributes(start_path, "mode") then
        start_path = nil
    end

    DownloadMgr:new{
        title = _("Choose download folder"),
        onConfirm = function(path)
            self.settings:saveSetting("download_path", path)
            self.settings:flush()
            UIManager:show(InfoMessage:new{
                text = _("Download folder set to:\n") .. path,
                timeout = 3,
            })
        end,
    }:chooseDir(start_path)
end

local function show_error(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 4,
    })
end

function plugin:showSettingsDialog(touchmenu_instance)
    local dialog

    local function save()
        local fields = dialog:getFields()
        local email = trim(fields[1])
        -- Passwords are kept verbatim, surrounding spaces may be intended
        local password = fields[2] or ""
        local imap_server = trim(fields[3])
        local port_text = trim(fields[4])
        local ssl_text = trim(fields[5]):lower()

        if imap_server == "" then
            return show_error(_("IMAP server must not be empty."))
        end

        local imap_port = port_text:match("^%d+$") and tonumber(port_text)
        if not imap_port or imap_port < 1 or imap_port > 65535 then
            return show_error(_("IMAP port must be a whole number between 1 and 65535."))
        end

        local use_ssl
        if TRUE_WORDS[ssl_text] then
            use_ssl = true
        elseif FALSE_WORDS[ssl_text] then
            use_ssl = false
        else
            return show_error(_("Use SSL must be \"true\" or \"false\"."))
        end

        -- Build the new config on a copy so a failed write leaves the running config untouched
        local new_config = {}
        for k, v in pairs(config) do new_config[k] = v end
        new_config.email = email
        new_config.password = password
        new_config.imap_server = imap_server
        new_config.imap_port = imap_port
        new_config.use_ssl = use_ssl

        local ok, err = write_config(new_config)
        if not ok then
            return show_error(_("Could not save config.lua:\n") .. tostring(err))
        end

        for k, v in pairs(new_config) do config[k] = v end

        UIManager:close(dialog)
        if touchmenu_instance then
            touchmenu_instance:updateItems()
        end
        UIManager:show(InfoMessage:new{
            text = _("Settings saved."),
            timeout = 2,
        })
    end

    dialog = MultiInputDialog:new{
        title = _("Email to KOReader settings"),
        fields = {
            {
                description = _("Email"),
                text = config.email or "",
                hint = "your_email@gmail.com",
            },
            {
                description = _("Password"),
                text = config.password or "",
                text_type = "password",
            },
            {
                description = _("IMAP server"),
                text = config.imap_server or "",
                hint = "imap.gmail.com",
            },
            {
                description = _("IMAP port"),
                text = config.imap_port and tostring(config.imap_port) or "",
                hint = "993",
                input_type = "number",
            },
            {
                description = _("Use SSL (true / false)"),
                text = tostring(config.use_ssl ~= false),
                hint = "true",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = save,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function plugin:addToMainMenu(menu_items)
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
                text_func = function()
                    local email = config.email
                    if not email or email == "" then
                        email = _("not set")
                    end
                    return _("Settings: ") .. email
                end,
                keep_menu_open = true,
                separator = true,
                callback = function(touchmenu_instance)
                    self:showSettingsDialog(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    return _("Download folder: ") .. self:getDownloadPath()
                end,
                keep_menu_open = true,
                callback = function()
                    self:chooseDownloadFolder()
                end,
            },
            {
                text = _("File extensions"),
                sub_item_table = self:genExtensionMenu(),
            },
        },
    }
end

function plugin:checkInbox()
    if #self:getAllowedExtensions() == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No file extensions selected."),
            timeout = 4,
        })
        return
    end

    -- Offer to turn Wi-Fi on instead of failing with a DNS error later.
    -- Returns true while still offline; we then re-enter once the device is online.
    if NetworkMgr:willRerunWhenOnline(function() self:checkInbox() end) then
        return
    end

    UIManager:show(InfoMessage:new{
        text = _("Checking inbox..."),
        timeout = 2,
    })

    UIManager:scheduleIn(0.5, function()
        local ok, result = pcall(function()
            return self:run_download()
        end)

        if not ok then
            UIManager:show(InfoMessage:new{
                text = _("Error: ") .. tostring(result),
                timeout = 5,
            })
            return
        end

        UIManager:show(InfoMessage:new{
            text = _("Downloaded ") .. tostring(result) .. _(" book(s)"),
            timeout = 4,
        })
    end)
end

function plugin:run_download()
    local conn, err = imap.connect(config)
    if not conn then
        error("Connection failed: " .. tostring(err))
    end

    local ok = imap.login(conn, config.email, config.password)
    if not ok then
        pcall(function()
            conn:close()
        end)
        error("Login failed")
    end

    local download_path = self:getDownloadPath()
    local allowed_extensions = self:getAllowedExtensions()

    local success, result = pcall(function()
        local ids = imap.search_unseen(conn)
        local total_downloaded = 0

        local function tick_callback()
            UIManager:forceRePaint()
        end

        for _, id in ipairs(ids) do
            local stream_iter = imap.fetch_stream(conn, id)
            local downloaded = attachment.process_stream(stream_iter, download_path, tick_callback,
                allowed_extensions)
            total_downloaded = total_downloaded + downloaded
        end

        return total_downloaded
    end)

    pcall(function()
        imap.logout(conn)
    end)

    if not success then
        error(result)
    end

    return result
end

return plugin
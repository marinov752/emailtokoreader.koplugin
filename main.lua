local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local DownloadMgr = require("ui/downloadmgr")
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local LuaSettings = require("luasettings")
local Device = require("device")
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
    }
end

-- 2. Load our local modules
local imap = require("imap")
local attachment = require("attachment")
local encoding = require("encoding")

-- Used when neither the UI settings nor config.lua provide a value
local DEFAULT_EXTENSIONS = {"epub"}
-- Extensions always offered in the menu; anything configured elsewhere is added on top
local MENU_EXTENSIONS = {"epub", "acsm", "pdf", "mobi", "cbz"}

-- 3. Writing config.lua back from the settings dialog
-- Known keys are written first in this order; any other keys follow alphabetically
local CONFIG_KEY_ORDER = {
    "email", "password", "imap_server", "imap_port", "use_ssl", "folder",
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
    name = "emailtokoreader",
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
    self:checkInbox(true)
    return true
end

-- Precedence for both settings: menu choice > config.lua > built-in default
-- The default is KOReader's home folder, which exists on every device (Kindle, Kobo, PocketBook, Android)
function plugin:getDownloadPath()
    return self.settings:readSetting("download_path")
        or config.download_path
        or G_reader_settings:readSetting("home_dir")
        or Device.home_dir
        or lfs.currentdir()
end

-- When on, downloaded emails stay unread so other devices checking the same mailbox get them too.
-- This device then remembers what it already fetched instead of relying on the read flag.
function plugin:isLeaveUnread()
    return self.settings:isTrue("leave_unread")
end

-- Mailbox to check; Gmail labels are mailboxes too
function plugin:getFolder()
    local folder = config.folder
    if type(folder) ~= "string" or trim(folder) == "" then
        return "INBOX"
    end
    return trim(folder)
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
        local folder = trim(fields[6])
        if folder == "" then folder = "INBOX" end

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
        new_config.folder = folder

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
            {
                description = _("Mail folder / Gmail label"),
                text = self:getFolder(),
                hint = "INBOX",
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

local function show_info(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 4,
    })
end

local function extension_set(extensions)
    local set = {}
    for _, ext in ipairs(extensions) do
        local key = normalize_extension(ext)
        if key then set[key] = true end
    end
    return set
end

-- Opens the mailbox, calls fn(conn, ctx) and always logs out again.
-- ctx.new_ids:   unread emails this device has not fetched yet
-- ctx.known_ids: unread emails already fetched while "Leave emails unread" was on
function plugin:withMailbox(fn)
    local conn, err = imap.connect(config)
    if not conn then
        error("Connection failed: " .. tostring(err), 0)
    end

    local folder = self:getFolder()

    local success, result = pcall(function()
        local ok, reason = imap.login(conn, config.email, config.password)
        if not ok then
            error("Login failed" .. (reason and (": " .. tostring(reason)) or ""), 0)
        end

        ok, reason = imap.select(conn, folder)
        if not ok then
            error("Cannot open mail folder \"" .. folder .. "\""
                .. (reason and (": " .. tostring(reason)) or ""), 0)
        end
        -- After a successful SELECT, `reason` holds the mailbox's UIDVALIDITY
        local mailbox_key = table.concat({
            tostring(config.email), tostring(config.imap_server), folder, tostring(reason or 0),
        }, "|")

        local ids, search_err = imap.search_unseen(conn)
        if not ids then
            error("Search failed: " .. tostring(search_err), 0)
        end

        -- Only UIDs that are still unread are kept, so the list cannot grow without bound
        local fetched = self.settings:readSetting("fetched_uids") or {}
        local known = {}
        for _, uid in ipairs(fetched[mailbox_key] or {}) do known[uid] = true end

        local ctx = { new_ids = {}, known_ids = {} }
        for _, id in ipairs(ids) do
            table.insert(known[id] and ctx.known_ids or ctx.new_ids, id)
        end

        local remembered = {}
        for _, id in ipairs(ctx.known_ids) do table.insert(remembered, id) end
        local function save()
            fetched[mailbox_key] = #remembered > 0 and remembered or nil
            self.settings:saveSetting("fetched_uids", fetched)
            self.settings:flush()
        end
        function ctx.remember(id)
            table.insert(remembered, id)
            save()
        end
        function ctx.forget_all()
            remembered = {}
            save()
        end
        save()

        return fn(conn, ctx)
    end)

    pcall(function()
        imap.logout(conn)
    end)

    if not success then
        error(result, 0)
    end

    return result
end

-- The books in one email, found without downloading it: { { index = 1, name = "A.epub" }, ... }.
-- index counts the attachments with an allowed extension, the same way attachment.process_stream does.
-- Returns nil when the server's description of the email could not be read.
function plugin:listBooks(conn, id, allowed_set)
    local names = imap.list_attachments(conn, id)
    if not names then return nil end

    local books = {}
    for _, raw in ipairs(names) do
        local name = raw
        local decode_ok, decoded = pcall(encoding.decode_rfc2047, raw)
        if decode_ok and decoded then name = decoded end

        local ext = name:match("%.([^%.]+)$")
        if ext and allowed_set[ext:lower()] then
            table.insert(books, { index = #books + 1, name = encoding.safe_filename(name) })
        end
    end
    return books
end

-- Lists the books waiting in the mailbox, one entry per book
function plugin:scanInbox()
    local allowed_set = extension_set(self:getAllowedExtensions())

    return self:withMailbox(function(conn, ctx)
        local entries = {}
        -- Not "_" as loop variable here: it would hide the translation function used below
        for i = 1, #ctx.new_ids do
            local id = ctx.new_ids[i]
            local books = self:listBooks(conn, id, allowed_set)
            if not books then
                -- Offer the whole email rather than hiding a book the listing could not show
                table.insert(entries, { uid = id, whole_email = true, name = _("Email with unlisted attachments") })
            else
                for _, book in ipairs(books) do
                    table.insert(entries, { uid = id, index = book.index, name = book.name })
                end
            end
        end
        return { entries = entries, unread = #ctx.new_ids }
    end)
end

-- selection: nil downloads every book; otherwise
--   selection[uid] = { indexes = set of book positions (nil = whole email), complete = all books of that email chosen }
-- Emails without a chosen book are not touched at all.
function plugin:run_download(selection)
    local download_path = self:getDownloadPath()
    local allowed_extensions = self:getAllowedExtensions()
    local allowed_set = extension_set(allowed_extensions)
    local leave_unread = self:isLeaveUnread()

    return self:withMailbox(function(conn, ctx)
        local total_downloaded = 0
        local checked = 0

        local function tick_callback()
            UIManager:forceRePaint()
        end

        -- Already on this device. With "Leave emails unread" switched off again, catch up on the read flag.
        if not leave_unread then
            for _, id in ipairs(ctx.known_ids) do imap.mark_seen(conn, id) end
            ctx.forget_all()
        end

        for _, id in ipairs(ctx.new_ids) do
            local wanted, indexes, complete = false, nil, false
            if selection then
                local choice = selection[id]
                if choice then
                    wanted, indexes, complete = true, choice.indexes, choice.complete
                end
            else
                local books = self:listBooks(conn, id, allowed_set)
                wanted = books == nil or #books > 0
                complete = true
            end

            if wanted then
                local stream_iter, fetch_err = imap.fetch_stream(conn, id)
                if not stream_iter then
                    error("Download interrupted: " .. tostring(fetch_err), 0)
                end
                local downloaded = attachment.process_stream(stream_iter, download_path, tick_callback,
                    allowed_extensions, indexes)
                total_downloaded = total_downloaded + downloaded
                checked = checked + 1

                -- Only now is the email recorded as done: one that failed halfway is offered again next time.
                -- An email with a book that was not chosen stays unread, so that book is offered again.
                if complete then
                    if leave_unread then
                        ctx.remember(id)
                    else
                        imap.mark_seen(conn, id)
                    end
                end
            end
        end

        return { downloaded = total_downloaded, checked = checked }
    end)
end

function plugin:startDownload(selection)
    show_info(_("Downloading..."), 2)

    UIManager:scheduleIn(0.5, function()
        local ok, result = pcall(function()
            return self:run_download(selection)
        end)

        if not ok then
            return show_info(_("Error: ") .. tostring(result), 5)
        end

        if result.downloaded > 0 then
            show_info(_("Downloaded ") .. tostring(result.downloaded) .. _(" book(s)"))
        else
            show_info(_("No new books in ") .. self:getFolder() .. ".\n" .. _("Check the File extensions menu."))
        end
    end)
end

-- The window shown before downloading: one line per book, ticked ones are downloaded,
-- the others stay unread in the mailbox.
function plugin:showBookDialog(entries)
    local dialog
    local leave_unread = self:isLeaveUnread()

    local function reopen()
        UIManager:close(dialog)
        self:showBookDialog(entries)
    end

    local selected_count = 0
    for _, entry in ipairs(entries) do
        if entry.selected then selected_count = selected_count + 1 end
    end

    local buttons = {}
    for _, entry in ipairs(entries) do
        table.insert(buttons, {
            {
                text = (entry.selected and "✓ " or "     ") .. entry.name,
                align = "left",
                callback = function()
                    entry.selected = not entry.selected
                    reopen()
                end,
            },
        })
    end

    if #entries > 1 then
        local function select_all(value)
            return function()
                for _, entry in ipairs(entries) do entry.selected = value end
                reopen()
            end
        end
        table.insert(buttons, {
            { text = _("Select all"), callback = select_all(true) },
            { text = _("Select none"), callback = select_all(false) },
        })
    end

    table.insert(buttons, {
        {
            text = leave_unread and _("✓ Keep downloaded emails unread")
                or _("Keep downloaded emails unread: off"),
            callback = function()
                self.settings:saveSetting("leave_unread", not leave_unread)
                self.settings:flush()
                reopen()
            end,
        },
    })

    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
        {
            text = _("Download") .. " (" .. selected_count .. ")",
            enabled = selected_count > 0,
            callback = function()
                -- Group the ticked books by email
                local selection, totals = {}, {}
                for _, entry in ipairs(entries) do
                    totals[entry.uid] = (totals[entry.uid] or 0) + 1
                    if entry.selected then
                        local choice = selection[entry.uid] or { count = 0 }
                        selection[entry.uid] = choice
                        choice.count = choice.count + 1
                        if not entry.whole_email then
                            choice.indexes = choice.indexes or {}
                            choice.indexes[entry.index] = true
                        end
                    end
                end
                for uid, choice in pairs(selection) do
                    choice.complete = choice.count == totals[uid]
                end

                UIManager:close(dialog)
                self:startDownload(selection)
            end,
        },
    })

    dialog = ButtonDialog:new{
        title = _("Tick the books to download. The others stay unread in the mailbox.") .. "\n"
            .. _("Keep downloaded emails unread: other devices checking this mailbox get them too."),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- direct = true skips the window and downloads every book (used by the gesture / profile action)
function plugin:checkInbox(direct)
    if trim(config.email) == "" or (config.password or "") == "" then
        return show_info(_("Enter your email account under Settings first."))
    end

    if #self:getAllowedExtensions() == 0 then
        return show_info(_("No file extensions selected."))
    end

    -- Offer to turn Wi-Fi on instead of failing with a DNS error later.
    -- Returns true while still offline; we then re-enter once the device is online.
    if NetworkMgr:willRerunWhenOnline(function() self:checkInbox(direct) end) then
        return
    end

    if direct then
        return self:startDownload(nil)
    end

    show_info(_("Checking inbox..."), 2)

    UIManager:scheduleIn(0.5, function()
        local ok, scan = pcall(function()
            return self:scanInbox()
        end)

        if not ok then
            return show_info(_("Error: ") .. tostring(scan), 5)
        end

        if #scan.entries == 0 then
            if scan.unread == 0 then
                return show_info(_("No new unread emails in ") .. self:getFolder() .. ".")
            end
            -- Tells "nothing arrived" apart from "arrived, but the attachment type is not ticked"
            return show_info(_("No matching attachments in ") .. tostring(scan.unread) .. _(" new email(s).")
                .. "\n" .. _("Check the File extensions menu."))
        end

        for _, entry in ipairs(scan.entries) do entry.selected = true end
        self:showBookDialog(scan.entries)
    end)
end

return plugin

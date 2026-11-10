-- The account settings below can also be edited on the device under
-- Tools > Email to KOReader > Settings. Saving there rewrites config.lua
-- and removes these comments.
local config = {
    -- Your email credentials
    email = "your_email@gmail.com",
    password = "your_app_password",
    
    -- IMAP server settings (Defaults are for Gmail)
    imap_server = "imap.gmail.com",
    imap_port = 993,
    use_ssl = true,

    -- Mail folder to check. Gmail labels are folders too: with a Gmail filter that applies
    -- the label "Books" to mail sent to you+books@gmail.com, set this to "Books".
    folder = "INBOX",

    -- Where you want the books saved. Left out, KOReader's home folder is used, which works
    -- on every device. Only used until you pick a folder in
    -- Tools > Email to KOReader > Download folder; that menu choice takes precedence from then on.
    -- download_path = "/mnt/us/books/",        -- Kindle
    -- download_path = "/mnt/onboard/Books/",   -- Kobo
    -- download_path = "/mnt/ext1/Books/",      -- PocketBook

    -- Attachment file extensions that will be downloaded.
    -- Add further extensions here (lowercase, without the dot), e.g. "pdf", "mobi".
    -- Same precedence rule: the File extensions menu overrides this once used.
    allowed_extensions = {"epub", "acsm"}
}

return config

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
    
    -- Where you want the books saved.
    -- Only used until you pick a folder in Tools > Email to KOReader > Download folder;
    -- that menu choice takes precedence from then on.
    download_path = "/mnt/us/books/",

    -- Attachment file extensions that will be downloaded.
    -- Add further extensions here (lowercase, without the dot), e.g. "pdf", "mobi".
    -- Same precedence rule: the File extensions menu overrides this once used.
    allowed_extensions = {"epub", "acsm"}
}

return config

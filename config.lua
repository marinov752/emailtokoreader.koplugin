return {
    -- Your Gmail address
    email = "your-email@gmail.com",
    
    -- Gmail app-specific password (not your regular password!)
    -- Generate at: https://myaccount.google.com/apppasswords
    password = "your-app-password-here",
    
    -- IMAP server settings (Gmail defaults)
    imap_server = "imap.gmail.com",
    imap_port = 993,
    use_ssl = true,
    
    -- Where to save downloaded EPUB files
    -- Default: /mnt/us/Books/ (Kindle)
    download_path = "/mnt/us/Books/",
    
    -- Enable debug mode to save raw email files
    debug_mode = false,
}

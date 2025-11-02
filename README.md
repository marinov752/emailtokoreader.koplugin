# Email to KOReader

Automatically download EPUB files from your email directly to your KOReader device.

## Version

**1.0.0** - Initial Release

## Features

* **Email Integration** - Fetch EPUB attachments from your email inbox
* **Multiple Files** - Download all EPUB attachments from an email
* **Multiple Emails** - Process up to 3 unread emails per check
* **Large File Support** - Handles EPUBs up to 3.5MB (most books)
* **Auto-Refresh** - File browser updates automatically after download
* **In-App Configuration** - No need to edit config files manually
* **Debug Mode** - Optional detailed logging for troubleshooting
* **Gmail Support** - Works with Gmail (and any IMAP server)

## Requirements

* KOReader version 2023.10 or later
* An email account with IMAP access
* For Gmail: An app-specific password (not your regular password)

## Installation

1. Download `sendtokoreader.koplugin` folder
2. Copy to your device's KOReader plugins directory:
   * Kindle: `/mnt/us/koreader/plugins/`
   * Kobo: `/mnt/onboard/.adds/koreader/plugins/`
   * Other: `[KOReader directory]/plugins/`
3. Restart KOReader
4. The plugin will appear under: **Tools > Email to KOReader**

## First Time Setup

### Step 1: Get Gmail App Password (Gmail users)

1. Go to your Google Account: https://myaccount.google.com/
2. Select **Security** from the left menu
3. Under "How you sign in to Google", select **2-Step Verification**
4. At the bottom, select **App passwords**
5. Select app: **Mail**
6. Select device: **Other** (name it "KOReader")
7. Click **Generate**
8. Copy the 16-character password (remove spaces)

### Step 2: Configure Plugin

1. Open KOReader
2. Go to: **Tools > Email to KOReader > Configure Settings**
3. Fill in:
   * **Email Address**: your.email@gmail.com
   * **App Password**: (paste the 16-character password)
   * **IMAP Server**: imap.gmail.com (default)
   * **IMAP Port**: 993 (default)
   * **Download Path**: /mnt/us/Books/ (or your preferred path)
4. Click **Save**
5. Done!

### Step 3: Test Connection

1. Go to: **Tools > Email to KOReader > Test Connection**
2. Wait for result
3. If successful: "[OK] Connection successful!"
4. If failed: Check your email and password

## Usage

### Download Books from Email

1. Email an EPUB file to yourself (as an attachment)
2. On your KOReader device:
   * Go to: **Tools > Email to KOReader > Check Inbox**
   * Wait 10-20 seconds (depending on file size)
3. Success message shows downloaded books
4. Books appear in your file browser automatically

### Tips

* You can attach multiple EPUBs to one email (all will download)
* Send multiple emails - up to 3 will be processed per check
* Books are marked as "read" in email after downloading
* Large books (2-3MB) take longer but work fine

## Menu Structure

```
Email to KOReader
├── Check Inbox              Download new books
├── Test Connection          Verify email settings
├── Configure Settings       Edit email, password, etc.
├── Advanced Settings
│   ├── Toggle Debug Mode   Enable/disable detailed logging
│   └── View Debug Location Show where debug files are saved
└── About                    Version and features
```

## Advanced Settings

### Debug Mode

Enable debug mode to troubleshoot issues:

1. Go to: **Tools > Email to KOReader > Advanced Settings > Toggle Debug Mode**
2. Check the box to enable
3. Debug files save to your download folder as: `debug_msg_*.txt`
4. These show email structure and help diagnose problems

### Custom IMAP Server (Non-Gmail)

For other email providers:

1. Find your provider's IMAP settings
2. Configure Settings:
   * **IMAP Server**: (e.g., imap.mail.yahoo.com)
   * **IMAP Port**: Usually 993 for SSL
   * **Email/Password**: Your credentials

Common IMAP servers:
* Yahoo: imap.mail.yahoo.com (port 993)
* Outlook: outlook.office365.com (port 993)
* ProtonMail: 127.0.0.1 (requires ProtonMail Bridge)

## Troubleshooting

### Connection Failed

**Problem**: "[ERROR] Connection failed"

**Solutions**:
1. Check internet connection on your device
2. Verify email address is correct
3. For Gmail: Ensure you're using an **app password**, not your regular password
4. Check IMAP server and port are correct
5. Verify 2-Step Verification is enabled (Gmail)

### No Books Downloaded

**Problem**: "No new EPUB files found"

**Possible Causes**:
1. No unread emails with EPUB attachments
2. Emails are already marked as "read"
3. Attachments are not .epub format

**Solutions**:
* Send a new email with an EPUB attachment
* Mark existing emails as "unread" in your email client
* Verify attachment is .epub (not .pdf, .mobi, etc.)

### Books Too Large

**Problem**: File detected but not downloaded

**Limit**: EPUBs up to 3.5MB

**Solutions**:
* Compress large EPUBs using Calibre
* Split large books into volumes
* For books >3.5MB, transfer via USB instead

### Debug Mode

If issues persist:

1. Enable Debug Mode (Advanced Settings)
2. Try downloading again
3. Check debug files in download folder
4. Look for error messages in `debug_msg_*.txt`

## Limitations

* **File Size**: Maximum 3.5MB per EPUB (most books are smaller)
* **File Type**: Only EPUB files (not PDF, MOBI, etc.)
* **Email Limit**: Processes up to 3 unread emails per check
* **IMAP Only**: Requires IMAP access (most modern email providers support this)

## Privacy & Security

* **Passwords**: Stored locally in `config.lua` on your device
* **No Cloud**: Plugin connects directly to your email server
* **No Tracking**: No data sent to third parties
* **Open Source**: Code is readable and auditable

## Technical Details

* **Protocol**: IMAP with SSL/TLS
* **Base64 Decoding**: Handles email attachment encoding
* **Memory Safe**: Streams large files, uses garbage collection
* **Message Limit**: 25,000 lines per email (handles large attachments)

## Configuration File

Settings are stored in: `plugins/sendtokoreader.koplugin/config.lua`

You can edit manually if needed:

```lua
return {
    email = "your.email@gmail.com",
    password = "your-app-password",
    imap_server = "imap.gmail.com",
    imap_port = 993,
    use_ssl = true,
    download_path = "/mnt/us/Books/",
    debug_mode = false,
}
```

## Support

For issues, questions, or feature requests:

1. Enable Debug Mode
2. Reproduce the issue
3. Check debug files for error messages
4. Report with debug information

## License

This plugin is provided as-is for personal use.

## Changelog

### Version 1.0.0 (2025-11-02)

Initial release with:
* IMAP email integration
* Multi-file download support
* Large file handling (up to 3.5MB)
* In-app configuration
* Debug mode
* Auto-refresh file browser
* Gmail app password support

## Credits

Developed for the KOReader community.

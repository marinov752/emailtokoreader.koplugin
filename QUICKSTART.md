# Quick Start Guide - Email to KOReader

## 5-Minute Setup

### 1. Get Gmail App Password (2 minutes)

1. Visit: https://myaccount.google.com/apppasswords
2. Select: Mail > Other (Custom name) > "KOReader"
3. Click "Generate"
4. Copy the 16-character password (example: `abcd efgh ijkl mnop`)
5. Remove spaces: `abcdefghijklmnop`

### 2. Install Plugin (1 minute)

1. Copy `sendtokoreader.koplugin` folder to:
   * Kindle: `/mnt/us/koreader/plugins/`
   * Kobo: `/mnt/onboard/.adds/koreader/plugins/`
2. Restart KOReader

### 3. Configure (2 minutes)

1. Open KOReader
2. Menu: **Tools > Email to KOReader > Configure Settings**
3. Fill in:
   * Email: your.email@gmail.com
   * Password: abcdefghijklmnop (the app password)
   * Server: imap.gmail.com
   * Port: 993
   * Path: /mnt/us/Books/
4. Click **Save**

### 4. Test

1. **Tools > Email to KOReader > Test Connection**
2. Should show: "[OK] Connection successful!"

### 5. Use It!

1. Email an EPUB to yourself
2. On Kindle: **Tools > Email to KOReader > Check Inbox**
3. Wait 10-20 seconds
4. Book appears in file browser!

## Common Issues

### "Connection failed"
→ Check internet connection
→ Verify you're using app password, not regular password
→ Enable 2-Step Verification in Google Account

### "No new EPUB files found"
→ Send a test email with an EPUB attachment
→ Make sure email is unread

### Books don't appear
→ Check download path is correct
→ Make sure you have space on device

## Tips

* Attach multiple EPUBs to one email = all download
* Send multiple emails = up to 3 processed per check
* Enable Debug Mode for troubleshooting
* Books are marked as "read" after downloading

That's it! Enjoy automatic book downloads!

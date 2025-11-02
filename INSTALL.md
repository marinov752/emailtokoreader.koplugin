# Installation Guide - Email to KOReader

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation Steps](#installation-steps)
3. [Gmail Setup](#gmail-setup)
4. [Plugin Configuration](#plugin-configuration)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

Before installing, ensure you have:

* **KOReader** version 2023.10 or later
* **Internet connection** on your device
* **Email account** with IMAP access
* For Gmail: **2-Step Verification** enabled

### Check KOReader Version

1. Open KOReader
2. Top menu: Gear icon > About
3. Verify version is 2023.10 or later

## Installation Steps

### Method 1: USB Connection (Recommended)

1. **Download Plugin**
   * Get `sendtokoreader.koplugin.zip`
   * Extract to get `sendtokoreader.koplugin` folder

2. **Connect Device**
   * Connect e-reader to computer via USB
   * Enable USB storage mode on device

3. **Copy Plugin**
   * Navigate to KOReader plugins directory:
     - **Kindle**: `/mnt/us/koreader/plugins/`
     - **Kobo**: `/mnt/onboard/.adds/koreader/plugins/`
     - **Cervantes**: `/mnt/onboard/koreader/plugins/`
     - **PocketBook**: `/mnt/ext1/applications/koreader/plugins/`
   
4. **Paste Folder**
   * Copy the entire `sendtokoreader.koplugin` folder
   * Final path should be: `.../plugins/sendtokoreader.koplugin/`

5. **Safely Eject**
   * Eject device from computer
   * Disconnect USB cable

6. **Restart KOReader**
   * Exit KOReader completely
   * Restart the application

### Method 2: SSH/SCP (Advanced)

For users comfortable with command line:

```bash
# Copy to Kindle via SSH
scp -r sendtokoreader.koplugin root@192.168.x.x:/mnt/us/koreader/plugins/

# Copy to Kobo via SSH  
scp -r sendtokoreader.koplugin root@192.168.x.x:/mnt/onboard/.adds/koreader/plugins/
```

Replace `192.168.x.x` with your device's IP address.

## Gmail Setup

### Enable 2-Step Verification

1. Go to: https://myaccount.google.com/security
2. Under "Signing in to Google", click **2-Step Verification**
3. Follow prompts to enable (if not already enabled)
4. Verify with phone number or authenticator app

### Generate App Password

1. Go to: https://myaccount.google.com/apppasswords
   * Or: Google Account > Security > 2-Step Verification > App passwords

2. Create new app password:
   * **Select app**: Mail
   * **Select device**: Other (Custom name)
   * **Name**: "KOReader" (or any name you prefer)
   * Click **Generate**

3. **Copy Password**
   * Shows 16 characters with spaces: `abcd efgh ijkl mnop`
   * Copy exactly as shown (can include spaces)
   * OR remove spaces: `abcdefghijklmnop`

4. **Save Password**
   * Store securely
   * You'll need it for plugin configuration
   * Can't view again after closing window

### Important Notes

* **Never use your regular Gmail password** - only app passwords
* App passwords bypass 2-Step Verification for specific apps
* Can revoke anytime from Google Account settings
* Each device should have its own app password

## Plugin Configuration

### First Time Configuration

1. **Open Plugin Menu**
   * In KOReader: Top menu > Tools > **Email to KOReader**

2. **Select Configure Settings**
   * Opens multi-field dialog

3. **Fill in Details**
   
   **Email Address:**
   ```
   your.email@gmail.com
   ```
   
   **App Password:**
   ```
   abcdefghijklmnop
   ```
   (Paste the 16-character password from Google)
   
   **IMAP Server:**
   ```
   imap.gmail.com
   ```
   (Pre-filled, don't change for Gmail)
   
   **IMAP Port:**
   ```
   993
   ```
   (Pre-filled, standard IMAP SSL port)
   
   **Download Path:**
   ```
   /mnt/us/Books/
   ```
   (Kindle default, adjust for your device)
   
   Common paths:
   - Kindle: `/mnt/us/Books/`
   - Kobo: `/mnt/onboard/Books/`
   - Cervantes: `/mnt/onboard/Books/`
   - PocketBook: `/mnt/ext1/Books/`

4. **Save Settings**
   * Click **Save** button
   * Should see: "[OK] Settings saved!"
   * Settings persist across restarts

### Download Path Notes

The download path:
* Must exist on your device
* Must be writable
* Should end with `/` (added automatically)
* Can be any folder you prefer

To create custom folder:
```bash
# Via SSH (if needed)
mkdir -p /mnt/us/EmailBooks/
```

## Verification

### Test Connection

1. **Run Connection Test**
   * Tools > Email to KOReader > **Test Connection**
   * Wait 3-5 seconds

2. **Expected Results**
   
   **Success:**
   ```
   [OK] Connection successful!
   ```
   → Configuration is correct, ready to use
   
   **Failure:**
   ```
   [ERROR] Connection failed:
   [specific error message]
   ```
   → Check troubleshooting section below

### Test Download

1. **Send Test Email**
   * From another device/computer
   * Send to your configured email address
   * Attach a small EPUB file (< 1MB)
   * Send email

2. **Check Inbox**
   * On e-reader: Tools > Email to KOReader > **Check Inbox**
   * Wait 10-20 seconds
   * Should see: "[OK] Downloaded 1 book(s)!"

3. **Verify File**
   * Press Back or Home
   * Navigate to your Books folder
   * EPUB should appear in file list
   * May need to refresh view

## Troubleshooting

### Plugin Not Appearing in Menu

**Issue**: Don't see "Email to KOReader" in Tools menu

**Solutions**:
1. Verify folder name is exactly: `sendtokoreader.koplugin`
2. Check folder is in correct plugins directory
3. Restart KOReader completely
4. Check KOReader version (need 2023.10+)

### Connection Failed

**Issue**: "[ERROR] Connection failed"

**Common Causes & Solutions**:

1. **No Internet**
   * Verify WiFi is connected
   * Try browsing to test internet

2. **Wrong Password**
   * Use app password, NOT regular Gmail password
   * Generate new app password if unsure
   * Check for typos in password

3. **2-Step Not Enabled**
   * Enable 2-Step Verification in Google Account
   * Generate app password only after 2-Step enabled

4. **Wrong Server/Port**
   * Gmail: imap.gmail.com, port 993
   * Verify server name has no typos
   * Port must be number, not text

5. **Firewall Issues**
   * Some networks block IMAP
   * Try different WiFi network
   * Check with network administrator

### LuaSocket Not Available

**Issue**: "[ERROR] LuaSocket not available"

**Solution**:
* Update KOReader to latest version
* LuaSocket is built-in to KOReader 2023.10+
* If still occurs, reinstall KOReader

### Settings Not Saving

**Issue**: Settings reset after closing

**Solutions**:
1. Check file permissions on device
2. Ensure `config.lua` is not read-only
3. Verify write permissions on plugins folder
4. Try running KOReader with elevated permissions

### Download Path Errors

**Issue**: Files not appearing after download

**Solutions**:
1. Verify path exists: check folder in file manager
2. Create folder if missing: use file manager or SSH
3. Check write permissions on folder
4. Try default path first: `/mnt/us/Books/`
5. Ensure path ends with `/`

### Email Not Marked As Read

**Issue**: Same emails download repeatedly

**Cause**: IMAP marking failed (network/permissions)

**Workaround**:
* Manually mark emails as read after downloading
* Or move downloaded emails to different folder

### Large Files Not Downloading

**Issue**: File detected but not saved

**Current Limit**: 3.5MB per EPUB

**Solutions**:
1. Compress EPUB using Calibre:
   * Open in Calibre
   * Convert EPUB to EPUB
   * Enable compression options
   
2. Split large books into volumes

3. Transfer via USB instead

### Enable Debug Mode

For persistent issues:

1. **Enable Debug**
   * Tools > Email to KOReader > Advanced Settings
   * Toggle Debug Mode **ON**

2. **Reproduce Issue**
   * Try Check Inbox again
   * Let it fail

3. **Check Debug Files**
   * Connect device to computer
   * Navigate to download path
   * Find `debug_msg_*.txt` files
   * Open in text editor

4. **Look For**
   * Error messages
   * "Found attachments: 0" (email parsing issue)
   * "Connection failed" (network issue)
   * Lua errors (plugin bugs)

## Getting Help

If issues persist:

1. Enable Debug Mode
2. Reproduce the issue
3. Collect:
   * Error message from plugin
   * Debug file content
   * KOReader version
   * Device model
   * Email provider
4. Check for similar issues in documentation
5. Report bug with collected information

## Next Steps

After successful installation:

1. Read [QUICKSTART.md](QUICKSTART.md) for daily usage
2. Explore Advanced Settings for customization
3. Check [README.md](README.md) for full documentation

---

**Installation Complete!** You're ready to download books from email.

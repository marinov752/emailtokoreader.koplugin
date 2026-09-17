# Email to KOReader (Streaming Architecture Fork)

Automatically download book attachments from your email directly to your KOReader device.

> **Note on this fork:** This version features a completely rebuilt, embedded-safe streaming IMAP parser designed specifically for low-memory e-ink devices like the Kindle Paperwhite. 

## 🚀 The Streaming Refactor
The original version of this plugin processed emails by loading the entire payload into memory and running heavy regex scans, which could cause watchdog freezes and crashes on 800MHz e-ink hardware when downloading large (5MB+) EPUBs. 

This fork introduces a **True Streaming Architecture**:
* **IMAP Literal Accounting:** Reads exact byte counts to prevent protocol strings from corrupting the EPUB ZIP structure.
* **Bounded Memory Usage:** Decodes Base64 payloads directly to disk in 8KB mathematically aligned chunks.
  Attachments sent as plain text (`7bit`/`8bit`, e.g. `.acsm` files from Apple Mail) or
  `quoted-printable` are streamed to disk line by line.
* **UI Yielding:** Cooperatively yields to the KOReader UI loop to prevent device watchdog lockups.
* **Strict RFC MIME Parsing:** Accurately isolates payloads, including attachments in nested
  multipart emails (text + HTML + attachment), and reads encoded or split filenames
  (RFC 2047 `=?UTF-8?…?=`, RFC 2231 `filename*=` / `filename*0=`).
* **Atomic Filesystem Writes:** Safely writes to `.tmp` files and renames them only upon successful verification.

## 📦 Installation
1. Download the latest version of this repository.
2. Place the `emailtokoreader.koplugin` folder into your KOReader `plugins` directory (usually `koreader/plugins/`).
3. Copy `config.example.lua` to `config.lua` and add your email credentials (use an App Password if using Gmail).
   Alternatively, skip this step and enter them on the device under
   **Tools > Email to KOReader > Settings** after the restart; saving there creates `config.lua`.
4. Restart KOReader.

`config.lua` is deliberately not tracked by git, so your credentials stay out of the repository.

## ⚙️ Configuration
Everything can be set from the device under **Tools > Email to KOReader**:

* **Settings: *your address*** — edit the email account: email, password, IMAP server, IMAP port
  and SSL.
* **Download folder** — opens KOReader's folder picker and shows the folder currently in use.
* **File extensions** — tick the attachment types to download (`.epub`, `.acsm`, `.pdf`, `.mobi`, `.cbz`).

### Account settings
The **Settings** dialog shows the current values from `config.lua`:

* The password is masked; tick **Show password** to check what you typed.
* **IMAP port** must be a whole number between 1 and 65535.
* **Use SSL** accepts `true`/`false` (also `yes`/`no`, `on`/`off`, `1`/`0`).

Invalid input shows an error and keeps the dialog open. **Save** writes the values back to
`config.lua` and they apply immediately, no restart needed. If the file cannot be written
(e.g. a read-only filesystem), an error is shown and the previous settings stay active.

> **Note:** saving rewrites `config.lua`, so comments in that file are removed. The file lives
> inside the plugin folder, so replacing the folder during a plugin update also replaces your
> account settings — keep a copy or re-enter them afterwards.

### Download folder and file extensions
Both are stored in `koreader/settings/emailtokoreader.lua`, outside the plugin folder, so they
survive plugin updates. The precedence is **menu choice → `config.lua` → built-in default**, which
means the corresponding `config.lua` entries stay in effect until you change them on the device:

```lua
download_path = "/mnt/us/books/",  -- Kindle; on PocketBook e.g. "/mnt/ext1/Books/"
allowed_extensions = {"epub", "acsm"},
```

Any extension listed in `config.lua` also shows up in the **File extensions** menu, so extra types
can be added there without editing files on the device.

> **Note on `.acsm`:** these are Adobe DRM fulfillment tokens, not books. KOReader cannot open them —
> download them into a folder your device's own Adobe-enabled reader can see, and fulfill them there.

## 📶 Wi-Fi
If the device is offline when you check the inbox, KOReader's usual "turn on Wi-Fi?" handling kicks
in instead of a name-resolution error, and the inbox check resumes by itself once the device is
online. Whether you get a prompt or Wi-Fi is enabled silently follows your setting under
**Network > Action when Wi-Fi is off**.

## ⚡ Gestures & profiles
"Check Inbox" is registered as a dispatcher action (*Email to KOReader: check inbox*), so it can be
bound to a gesture or key under **Taps and gestures**, or added to a profile or QuickMenu, instead of
going through the menu each time.

## 📖 Usage
To trigger a download, simply open KOReader's top menu, navigate to **Tools > Email to KOReader**, and tap **Check Inbox**.

## 🛠️ Troubleshooting
* **Only unread emails are checked.** Fetching an email marks it as read on the server, so each
  email is downloaded once. To fetch one again, mark it as unread.
* **Duplicates:** existing files are never overwritten. Fetching the same email again saves a copy
  such as `Book (1).epub`.
* **"Downloaded 0 book(s)":** make sure the email is unread and its attachment type is ticked under
  **File extensions**.
* **Downloaded files don't show up:** check the folder shown in the **Download folder** entry.
  KOReader's file browser hides file types it cannot open, such as `.acsm`; enable
  **Show unsupported files** in the file browser settings to see them.
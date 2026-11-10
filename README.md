# Email to KOReader

Automatically download book attachments from your email directly to your KOReader device.

## 🚀 How it works
The plugin talks to your mailbox over IMAP and streams attachments straight to disk, so even
large (5MB+) EPUBs download reliably on low-memory e-ink devices such as the Kindle Paperwhite:

* **IMAP Literal Accounting:** Reads exact byte counts to prevent protocol strings from corrupting the EPUB ZIP structure.
* **Bounded Memory Usage:** Decodes Base64 payloads directly to disk in 8KB mathematically aligned chunks.
  Attachments sent as plain text (`7bit`/`8bit`, e.g. `.acsm` files from Apple Mail) or
  `quoted-printable` are streamed to disk line by line.
* **UI Yielding:** Cooperatively yields to the KOReader UI loop to prevent device watchdog lockups.
* **Strict RFC MIME Parsing:** Accurately isolates payloads, including attachments in nested
  multipart emails (text + HTML + attachment), and reads encoded or split filenames
  (RFC 2047 `=?UTF-8?…?=`, RFC 2231 `filename*=` / `filename*0=`).
* **Atomic Filesystem Writes:** Safely writes to `.tmp` files and renames them only upon successful verification.
* **No half books:** if the connection drops or the disk fills up mid-download, the partial file is
  discarded, an error is shown and the email stays unread, so the next check fetches it again.

## 📦 Installation
1. Download the latest version of this repository.
2. Place the folder into your KOReader `plugins` directory (usually `koreader/plugins/`,
   on Kobo `.adds/koreader/plugins/`). The folder **must** be named `emailtokoreader.koplugin` —
   rename it if your download is called `emailtokoreader.koplugin-main`.
3. Copy `config.example.lua` to `config.lua` and add your email credentials (use an App Password if using Gmail).
   Alternatively, skip this step and enter them on the device under
   **Tools > Email to KOReader > Settings** after the restart; saving there creates `config.lua`.
4. Restart KOReader.

`config.lua` is deliberately not tracked by git, so your credentials stay out of the repository.

## ⚙️ Configuration
Everything can be set from the device under **Tools > Email to KOReader**:

* **Settings: *your address*** — edit the email account: email, password, IMAP server, IMAP port,
  SSL and the mail folder to check.
* **Download folder** — opens KOReader's folder picker and shows the folder currently in use.
* **File extensions** — tick the attachment types to download (`.epub`, `.acsm`, `.pdf`, `.mobi`, `.cbz`).
* **Check Inbox** — lists the books waiting in the mailbox and lets you choose what to download,
  see [Usage](#-usage).

### Account settings
The **Settings** dialog shows the current values from `config.lua`:

* The password is masked; tick **Show password** to check what you typed.
* **IMAP port** must be a whole number between 1 and 65535.
* **Use SSL** accepts `true`/`false` (also `yes`/`no`, `on`/`off`, `1`/`0`).
* **Mail folder / Gmail label** is the folder that gets checked, `INBOX` by default.

Invalid input shows an error and keeps the dialog open. **Save** writes the values back to
`config.lua` and they apply immediately, no restart needed. If the file cannot be written
(e.g. a read-only filesystem), an error is shown and the previous settings stay active.

> **Note:** saving rewrites `config.lua`, so comments in that file are removed. The file lives
> inside the plugin folder, so replacing the folder during a plugin update also replaces your
> account settings — keep a copy or re-enter them afterwards.

#### Using a dedicated folder, `+` addresses and Gmail labels
Gmail delivers `you+books@gmail.com` and `y.ou@gmail.com` to the same inbox as `you@gmail.com`,
so they work without any extra setup. To keep books out of your main inbox, create a Gmail filter
(*To: `you+books@gmail.com`* → *Apply label "Books"*, optionally *Skip the Inbox*) and enter
`Books` as the mail folder. Nested labels are written with a slash, e.g. `Reading/Books`. Other
providers work the same way with their own folder names.

Emails without a matching attachment are never downloaded or marked as read, so the plugin is safe
to point at a normal inbox; a dedicated folder just keeps the check faster.

### Download folder and file extensions
Both are stored in `koreader/settings/emailtokoreader.lua`, outside the plugin folder, so they
survive plugin updates. The precedence is **menu choice → `config.lua` → built-in default**, which
means the corresponding `config.lua` entries stay in effect until you change them on the device:

```lua
download_path = "/mnt/us/books/",  -- Kindle; Kobo "/mnt/onboard/Books/", PocketBook "/mnt/ext1/Books/"
allowed_extensions = {"epub", "acsm"},
```

Without a menu choice and without a `download_path` in `config.lua`, books go to KOReader's home
folder.

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
Open KOReader's top menu, navigate to **Tools > Email to KOReader**, and tap **Check Inbox**.
The plugin asks the mail server which books are attached to your unread emails (without downloading
them yet) and shows them in a window:

* **One line per book.** All are ticked (✓) to begin with; tap a book to untick it. Unticked books
  are not downloaded and their email stays unread, so they are offered again next time.
  **Select all** / **Select none** change every line at once.
* **Keep downloaded emails unread** — switched on (✓), the emails you download from also stay unread
  on the server, so other devices checking the same mailbox get them too. Use it on **every** device
  that shares the mailbox. Each device remembers which emails it already fetched, so nothing is
  downloaded twice. The choice is remembered.
* **Download (n)** fetches the ticked books; **Cancel** leaves everything as it is.

An email with several books is only marked as read once all of its books have been downloaded in
one go. If you download just some of them, the email stays unread and all of its books are listed
again next time.

The gesture / profile action skips the window and downloads every book.

## 🛠️ Troubleshooting
* **The plugin is missing from the Tools menu:** the folder must be named exactly
  `emailtokoreader.koplugin` and contain `_meta.lua` and `main.lua` directly (not inside a second
  nested folder). Recent KOReader versions ignore plugins without `_meta.lua`; versions of this plugin
  before 1.2.0 did not ship one.
* **Only unread emails are checked.** An email is marked as read once it has been processed
  completely, so each email is downloaded once. To fetch one again, mark it as unread.
* **Several devices on one mailbox:** by default whichever device checks first gets the book,
  because it marks the email as read. Switch on **Keep downloaded emails unread** in the Check Inbox window on all devices to have every
  device download it. The emails then stay unread until you open or delete them yourself.
* **"Login failed":** the message now includes the mail server's reason. Gmail needs an
  [app password](https://myaccount.google.com/apppasswords), not your normal password.
* **Duplicates:** existing files are never overwritten. Fetching the same email again saves a copy
  such as `Book (1).epub`.
* **"No new unread emails":** the email was already opened (by you, another device or another mail app)
  or sits in a different folder than the one set under **Settings**.
* **"No matching attachments":** the attachment type is not ticked under **File extensions**.
* **"Cannot write to the download folder":** pick an existing folder under **Download folder**; a
  Kindle path such as `/mnt/us/books/` does not exist on a Kobo.
* **Downloaded files don't show up:** check the folder shown in the **Download folder** entry.
  KOReader's file browser hides file types it cannot open, such as `.acsm`; enable
  **Show unsupported files** in the file browser settings to see them.

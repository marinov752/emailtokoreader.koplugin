local _ = require("gettext")

-- KOReader's plugin loader reads this file; without it recent versions do not list the plugin.
return {
    name = "emailtokoreader",
    fullname = _("Email to KOReader"),
    description = _("Download book attachments (EPUB, PDF, …) from an email inbox."),
    version = "1.2.0",
}

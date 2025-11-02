# Changelog

All notable changes to Email to KOReader will be documented in this file.

## [1.0.0] - 2025-11-02

### Initial Release

First stable release of Email to KOReader plugin.

### Added
- IMAP email integration for automatic EPUB downloads
- Support for multiple EPUB attachments per email
- Support for processing multiple emails (up to 3 per check)
- Large file handling (up to 3.5MB EPUBs)
- Streaming parser for memory-efficient processing
- In-app configuration dialog
- Settings editor with masked password field
- Test connection functionality
- Auto-refresh file browser after downloads
- Debug mode with detailed logging
- Duplicate detection to prevent re-downloads
- Message boundary detection for proper multi-message handling
- Gmail app password support
- SSL/TLS support for secure connections
- Base64 decoding for email attachments
- Chunked file writing for memory safety
- Garbage collection after large operations

### Configuration
- Email address
- App password (masked in UI)
- IMAP server (default: imap.gmail.com)
- IMAP port (default: 993)
- Download path (default: /mnt/us/Books/)
- Debug mode toggle
- SSL/TLS toggle

### Limitations
- Maximum file size: 3.5MB per EPUB
- File type: EPUB only (no PDF, MOBI, etc.)
- Email limit: 3 unread messages per check
- Protocol: IMAP only (no POP3)

### Technical Details
- Language: Lua
- Dependencies: LuaSocket (included in KOReader)
- Memory: Streaming processing, no full file in memory
- Security: Credentials stored locally only

### Documentation
- README.md with full documentation
- QUICKSTART.md for fast setup
- LICENSE (MIT)
- Example configuration file

### Known Issues
- None at initial release

---

## Version Format

Versions follow Semantic Versioning: MAJOR.MINOR.PATCH

- MAJOR: Breaking changes
- MINOR: New features (backwards compatible)
- PATCH: Bug fixes (backwards compatible)

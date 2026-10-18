# Security

Couch Remote can synthesize input and execute user-configured AppleScript/shell commands. Review mappings and imported backups before use. The optional phone remote is an unauthenticated plain-HTTP service intended only for a trusted local network; never port-forward or expose it to the internet, and disable it when unused.

The app requests macOS permissions for its selected features, including Input Monitoring, Accessibility, Automation, Calendar, Bluetooth/HID, or local network. Grant only what you need. Private Apple APIs are used for touch-surface and some now-playing integration.

To report a potential vulnerability, do not post exploit details publicly. Contact the repository owner using the private reporting channel listed in the GitHub repository. If none is listed, open a minimal issue asking for a secure contact method, without vulnerability details.

See the repository’s top-level `SECURITY.md` for the fuller policy. This page is documentation, not legal advice.

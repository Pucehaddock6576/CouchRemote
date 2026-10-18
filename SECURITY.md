# Security and responsible use

## Reporting a vulnerability

Please do not publish working exploits, private configuration files, or sensitive personal data in a public issue. Contact the repository maintainer privately through the contact method listed on the GitHub repository. If no private contact method is listed, open a minimal issue asking for a secure reporting channel without including exploit details.

## Security notes for users

- Couch Remote can send input, control apps, and run AppleScript or shell commands when configured by the user. Review button mappings and imported backups before use.
- The optional phone remote runs an unauthenticated, plain-HTTP server on the local network. Anyone who can reach its port may be able to send remote commands. Enable it only on a network you trust; disable it when finished; do not port-forward it or expose it to the internet.
- Apple Events, Accessibility, Input Monitoring, Calendar, Bluetooth, and local-network permissions are governed by macOS. Grant only the permissions needed for the features you use.
- Touch-surface reading uses private Apple MultitouchSupport APIs. This is an OS compatibility risk, not a supported public API contract.
- The project does not provide notarized releases or a signing identity. Inspect source and build locally if you need to verify provenance.
- Do not commit secrets, provisioning profiles, certificates, personal app data, or `~/Library/Application Support/Couch Remote/config.json`.

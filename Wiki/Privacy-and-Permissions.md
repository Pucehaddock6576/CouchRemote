# Privacy and permissions

Couch Remote runs locally and stores preferences in Application Support. Some features use operating-system permissions or contact online services. The app does not require a Couch Remote account.

## macOS permissions

| Access | Why it is used | Needed for |
| --- | --- | --- |
| Bluetooth/HID and Input Monitoring | Detect Siri Remote button input | Core remote operation |
| Accessibility | Move/click the pointer and post navigation/key input | Trackpad, simulated keys, and many actions |
| Apple Events / Automation | Send commands to Music, TV, and other scripted apps | Corresponding integrations only |
| Calendar | Read calendar events | Optional calendar widget only |
| Local network | Accept phone-remote connections | Optional phone remote only |

Bluetooth pairing is managed by macOS System Settings. The Overview panel displays connection, input, touch-surface, and Accessibility status and provides links to relevant privacy panes.

Permission prompts and pane names vary across macOS versions. If a grant does not take effect, quit/reopen Couch Remote and verify that the specific app copy you are running is allowed under **System Settings → Privacy & Security**.

## Data paths and online requests

- Local preferences: `~/Library/Application Support/Couch Remote/config.json`.
- Optional catalogue/artwork search uses Apple’s public iTunes/Music catalogue endpoints.
- Optional weather uses Open-Meteo geocoding/forecast services. When city is not supplied, the app’s location lookup can contact `ipwho.is` to infer a location from the network IP.
- Built-in YouTube loads the URL configured in Big Screen settings through WebKit.
- Optional phone remote serves a control page on the local network; it does not need an external service.

These network features can send normal request metadata (such as IP address, requested search terms, or configured location) to the relevant service. Disable optional widgets/features you do not want to use. Review source code and service privacy policies for details before use.

## High-impact capabilities

Button mappings can run AppleScript and shell commands, and the app can send input or power actions. Inspect mappings and imported backups from untrusted sources. See the [Security](Security.md) page and the top-level `SECURITY.md`.

## Private APIs

The touch surface is read using the private `MultitouchSupport` framework loaded at runtime. macOS does not promise compatibility for private APIs; changes to the OS may break this feature. Now Playing data uses private MediaRemote symbols where available, and can be restricted by macOS.

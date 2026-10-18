# Troubleshooting

## Build issues

### `xcrun` cannot find the macOS SDK

Install or repair Xcode Command Line Tools (`xcode-select --install`), then verify `xcode-select -p` and `xcrun --show-sdk-path --sdk macosx`.

### Swift compile errors

Use a supported macOS host with a current Command Line Tools toolchain, build from repository root, and run `bash build.sh`. If errors appeared after a macOS/Xcode update, include the complete first relevant diagnostic and `swiftc --version` in a report. Do not report only “does not build.”

## Remote connection and input

### App does not see the remote

Confirm the remote is paired in Bluetooth settings and awake. Press a button, then check Overview. Try Reconnect remote from the menu bar. Remove/re-pair only if normal reconnect does not work.

### Buttons are not detected

Check Input Monitoring permission for the exact running app under Privacy & Security. Reopen the app after granting it. Confirm another process is not intercepting the same input.

### Pointer and key actions do nothing

Check Accessibility permission. Some actions are unavailable or app-specific; test in a normal text editor/browser and inspect the active app profile and mappings.

### Touch surface does not respond

Check the Overview touch status and Touchpad device selection. Wake the remote and try reconnect/reattach. The glass reader uses a private framework; a macOS update can change or remove behavior. Include device dimensions/family if available and macOS version in a bug report.

## Integrations

### Music/TV asks for permission or fails

Open the relevant app once, accept macOS Automation prompts, and verify permissions in Privacy & Security → Automation. Some catalogue/library operations need the target app to be installed and available. Remote now-playing metadata depends on macOS providing it.

### Calendar/weather widget is blank

Calendar requires calendar access and an event in its search range. Weather needs network access and an optional city/units setting; IP-derived location can be inaccurate or unavailable. Check the optional service network connection.

### Phone remote cannot connect

Confirm the server is enabled, use the exact address shown by Couch Remote, put phone and Mac on the same non-isolated Wi-Fi, and allow the macOS local-network prompt/firewall access. Do not forward the port to the internet.

### YouTube page does not load or behave like a TV

YouTube may change its TV interface or user-agent handling. Check Big Screen’s URL and “Ask YouTube for its TV layout” setting; try the standard site or TV site as suggested in Settings. This integration is web-service dependent.

## Big Screen layout

Close and reopen Big Screen. Report whether the issue occurs only after music/metadata/artwork appears, on all displays, or after navigating. Include macOS version, display resolution/notch, and the app build path. See [Big Screen](Big-Screen.md).

## Safe diagnostics to include

Share the macOS version, Mac architecture, build command/result, steps, expected/actual behavior, which permissions are granted, and relevant redacted output. Never post `config.json`, unredacted backups, credentials, private personal data, or public-network addresses unnecessarily.

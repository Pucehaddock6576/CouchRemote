# Getting started

## What you need

- macOS 13 or later.
- Apple’s Xcode Command Line Tools (`swiftc` and a macOS SDK). A full Xcode install is not required by the build script.
- A paired first-generation Apple TV Siri Remote. The app may not work with other generations or third-party remotes.

## Pair the remote

1. On the remote, hold **Menu + Volume Up** for about five seconds near the Mac.
2. Open **System Settings → Bluetooth** and connect/pair the remote.
3. Press a button to wake it if it does not appear straight away.

The button combination and Bluetooth setup are also shown in the app’s Overview screen.

## Build

From the root of the cloned repository:

```sh
xcode-select --install   # only if Command Line Tools are not already installed
bash build.sh
```

The output is `build/Couch Remote.app`. The script creates a locally ad-hoc-signed app bundle; it is not notarized. On first open, macOS may ask you to confirm opening an app built locally.

## First-run permissions

Follow the in-app Overview checklist:

- **Input Monitoring:** reads remote button input.
- **Accessibility:** performs pointer movement/clicks and simulated key presses.
- **Bluetooth:** the remote must be paired/connected through macOS Bluetooth settings.

Optional integrations may request additional access. Apple Music/TV operations can prompt for Automation permission; the calendar widget needs Calendar access; the phone remote uses local networking. Features that do not need those integrations can be used without enabling them.

After changing a privacy permission, quit and reopen Couch Remote if the feature does not become available immediately. Build location/signature changes may cause macOS to treat the rebuilt app as a different permission-granting app.

## Open settings and choose a mode

Couch Remote lives in the menu bar. Open its menu-bar icon to open Settings, change touch mode, open Big Screen, or use other shortcuts. In Settings, the Overview panel shows connection status and the other panels configure buttons, app profiles, touch behavior, Big Screen, pop-ups, extras, and backups.

## Uninstall

Quit Couch Remote, remove the app bundle you built, and optionally remove its settings folder at `~/Library/Application Support/Couch Remote/`. Removing the settings folder permanently removes saved mappings and preferences; export a backup first if you might want them later.

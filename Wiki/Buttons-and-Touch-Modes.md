# Buttons and touch modes

## Modes at a glance

| Mode | Glass surface behavior | Typical use |
| --- | --- | --- |
| Trackpad | Moves/clicks the Mac pointer; optional taps, drags, and multi-finger gestures | Pointing at ordinary Mac interfaces |
| Remote | Swipe/tap zones/edge clicks can navigate directionally | Couch navigation in Big Screen, menus, and supported apps |
| Scroll | Touch movement scrolls content | Scrolling long pages and lists |

Mode names describe the default behavior; configurable actions, profile overrides, and app-specific handling may change what an input does.

## Buttons and gestures

Open **Settings → Buttons** to choose a profile and configure actions. Inputs include Menu, TV/Home, Siri/microphone, Play/Pause, volume up/down, surface select/hold, directional swipes and edge clicks, and two-finger tap. The Siri/microphone button is normally left to system Siri unless mapped/configured otherwise.

Available actions include media controls, mouse actions, touch mode changes, Big Screen/Couch Menu, Mousespot, keyboard, timers, utilities, app/window actions, desktop navigation, open URL, AppleScript, and shell command. Some potentially destructive actions can be guarded by **Hold Select to confirm risky actions**.

## Profiles

A profile can target one or more app bundle identifiers and may specify a touch mode and button mappings. The app tracks the frontmost app and selects a matching profile; use the Global profile for universal/default behavior. If a profile action is set to inherit, it uses the normal/global mapping.

## Calibration and tuning

In **Settings → Touchpad**, adjust pointer precision/speed, tap-to-click, drag behaviors, click stabilization, and other touch options. The calibration wizard helps estimate timing/travel for taps and gestures. Settings → Extras includes held swipes, repeat behavior, edge volume, and music swipe options.

## Practical troubleshooting

- If buttons are not seen, verify Input Monitoring and Bluetooth pairing.
- If the glass is inert, inspect the Overview touch status and Touchpad device settings. Private API-based touch reading may be affected by macOS changes.
- If an input performs a different action than expected, check the current mode, active app profile, per-mode overrides, and global mapping.
- Test mappings with a harmless action before assigning power, quit, shell, or AppleScript commands.

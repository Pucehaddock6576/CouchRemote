# Known limitations

This project directory does not include a formal product support matrix or a complete automated test suite. These are limitations evident from the implementation and should not be read as a promise of support.

- **Hardware scope:** the app is designed around the Apple TV Siri Remote, 1st generation. It filters known Apple HID product IDs; other remotes are not guaranteed.
- **Private APIs:** touch surface access uses the private MultitouchSupport framework; system Now Playing reading uses private MediaRemote symbols. Apple can change these without notice.
- **Permissions:** button input, pointer/key injection, Apple Events, Calendar, and local networking can require separate macOS grants. Behavior varies by macOS release and app installation/signing identity.
- **External players:** Now Playing metadata may be absent even when playback works. Media controls depend on what the player/macOS exposes.
- **Music equalizer:** the project uses AppleScript for EQ controls. On some current Music/macOS combinations those scripting properties may fail; the app’s observed behavior can vary with OS/player state.
- **Phone remote:** plain HTTP and no authentication; local-network-only intended use. Not safe to expose to the public internet.
- **YouTube:** the built-in page is a website, not an official YouTube app/API; Google can alter or block the TV interface/user-agent.
- **Third-party services:** catalogue, artwork, weather, and IP-location features rely on external endpoints and connectivity.
- **Build/distribution:** the shell build targets the current host architecture and ad-hoc signs locally. No Developer ID signature, notarization, app-store package, update mechanism, or verified universal binary is included.
- **Testing:** CI compilation does not exercise a real Siri Remote, Apple Events approval, settings migration, or visual layout on every display.

When reporting an issue, state whether it reproduces on a clean build, your macOS version, the exact integration/player, and any permissions involved.

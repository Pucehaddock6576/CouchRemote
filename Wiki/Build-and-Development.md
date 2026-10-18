# Build and development

## Repository map

```text
Sources/                  Swift source compiled as one executable
Support/MultitouchBridge.h C declarations for private MultitouchSupport types
build.sh                  Compile and package the macOS app
.github/workflows/        Build verification and artifacts
Wiki/                     Documentation source, also usable for GitHub Wiki
```

There is no `.xcodeproj` or Swift Package manifest at present. The supported local build is the repository’s shell script.

## Requirements and build command

Use macOS 13 or later and install Xcode Command Line Tools. From repository root:

```sh
xcode-select -p
swiftc --version
bash build.sh
```

The build script locates the macOS SDK with `xcrun`, targets the host architecture and macOS 13.0, imports `Support/MultitouchBridge.h`, compiles `Sources/*.swift`, links Apple frameworks, and packages `build/Couch Remote.app`. It ad-hoc signs the bundle for local use; this does not notarize it or make it suitable for distribution as a trusted release.

To launch locally:

```sh
open "build/Couch Remote.app"
```

When testing a build, check Activity Monitor or the process path so you do not accidentally test a previously installed copy.

## Continuous integration

`.github/workflows/build.yml` builds on a macOS GitHub Actions runner for pushes, pull requests, and manual dispatch. It uploads the app bundle as a workflow artifact for inspection/download. CI does not have a paired Siri Remote and cannot validate HID/touch hardware, user permissions, Music/TV Automation, sound, or real screen layout.

## Architecture overview

- `main.swift`: menu-bar application startup and settings window.
- `RemoteHID.swift`: Bluetooth HID remote buttons and battery/connection state.
- `Touchpad.swift`: loads the private MultitouchSupport framework and translates touch frames.
- `Engine.swift`, `Actions.swift`, `Gestures.swift`, `Seek.swift`: input routing and actions.
- `Config.swift`, `SettingsUI.swift`, `MappingUI.swift`: persisted settings, settings panels, and mapping UI.
- `BigScreen.swift`, `BigScreenViews.swift`, `BigScreenPages.swift`, `BigWidgets.swift`: Big Screen state/controller, layout, pages, and widgets.
- `PhoneRemote.swift`: optional local HTTP server and browser controller UI.
- `MediaLibrary.swift`, `MusicExtras.swift`, `MusicWatcher.swift`, `NowPlaying.swift`: music/catalogue/library/metadata integrations.
- `Overlays.swift`, `PresenterTools.swift`, `Widgets.swift`: overlays, presenter features, and header widgets.

The exact boundaries can evolve; use source as the authority.

## Development workflow

1. Make a focused change in `Sources/` or `Support/`.
2. Run `bash build.sh`.
3. Test on macOS with the permissions and apps relevant to the change.
4. For hardware-related changes, report the actual remote, Mac, and macOS version tested.
5. Update README/Wiki when user-visible steps, permissions, security, or feature behavior change.

There is no automated unit test suite currently. Do not interpret successful compilation as proof of runtime behavior. Private APIs and local permissions make manual testing important.

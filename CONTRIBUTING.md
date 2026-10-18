# Contributing

Thanks for your interest in improving Couch Remote. Contributions should keep the app approachable for Mac users and careful around system-level input and user data.

## Before you start

- Check existing issues and discussions for a related report.
- For a bug, include macOS version, Mac architecture, remote model, steps to reproduce, expected behavior, actual behavior, and whether the issue is consistent.
- For a larger change, open an issue or discussion first so scope and behavior can be agreed before investing in implementation.
- Do not commit personal settings, device identifiers, crash logs, screenshots with private information, signing credentials, or API secrets.

## Local development

1. Install Xcode Command Line Tools.
2. Build from the repository root with `bash build.sh`.
3. Run `build/Couch Remote.app` and test the relevant behavior on a Mac. Some features require a paired 1st-gen Siri Remote, Bluetooth, Accessibility/Input Monitoring permissions, Apple Music, a calendar, or a local network.
4. There is no Xcode project or automated test suite currently. Mention clearly which manual checks you performed and which hardware-dependent checks you could not perform.

The build script compiles `Sources/*.swift` as a single app and imports `Support/MultitouchBridge.h`. Keep this invocation working, or update the build documentation and CI together if introducing a new build system.

## Code and review expectations

- Keep changes focused and explain the behavior change in the pull request.
- Prefer existing project patterns and avoid adding dependencies without a clear reason.
- Preserve existing settings and config migration behavior. Never silently discard a user’s configuration.
- Handle AppleScript, HID, Accessibility, filesystem, and network failures explicitly; these operations can fail due to permission, app state, or OS changes.
- For features that invoke user-configured shell or AppleScript commands, preserve clear user control and document security implications.
- Do not claim a fix is verified on hardware unless it was actually tested on hardware.

## Pull requests

Include:

- What changed and why.
- How to reproduce or exercise it.
- Build result and manual test results, including macOS version/architecture where useful.
- Screenshots or short clips for visible UI changes, with private information removed.
- Known limitations and follow-up work.

Keep the README and relevant `Wiki/` pages in sync when changing setup, feature behavior, permissions, configuration, or build steps.

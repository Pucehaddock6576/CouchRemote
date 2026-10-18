# Big Screen

Big Screen is Couch Remote’s full-screen, remote-first home screen. By default the TV/Home button opens it. It can also be opened from the menu-bar menu or Settings. The button mapping can be changed.

## Navigation

- Swipe or use directional controls to move focus between rows and tiles.
- Click/select or press Return to open/activate the focused item.
- Menu/Escape goes back; the TV/Home control closes Big Screen.
- Hold/click-hold on supported tiles for contextual actions.
- In long alphabetical lists, continue past the start/end to access the A–Z jump strip.

Exact input behavior depends on the selected touch mode and mappings.

## Home rows and pages

Depending on current state and enabled options, Home can show Now Playing, widgets, Browse, favourite apps, watch shortcuts, controls, and power options. Apple Music and Apple TV integration can browse library/catalogue content and may ask macOS for Automation permission. Music, artwork, search, and remote now-playing data can be limited by permissions or Apple service changes.

The Now Playing row appears when playback metadata is available. Its placement can affect the home row layout; the current source re-anchors the home list when row structure changes.

## Full-screen Now Playing

Clicking the Now Playing card opens a larger artwork/player view by default. It can be disabled in **Settings → Big Screen → Music and search**. The app’s ability to show controls and metadata depends on the player and on whether macOS shares Now Playing information.

## Themes and content

Big Screen settings include appearance, configurable watch shortcuts, widgets, recently played/added rows, search history, and now-playing options. YouTube can open in a separate WebKit-based TV-style window.

## Layout troubleshooting

1. Close Big Screen with the TV/Home control and reopen it.
2. Wait briefly for metadata/artwork and widget content to load.
3. If testing a new source build, make sure you launched the newly built app bundle rather than another installed copy.
4. Reproduce with the same display, macOS version, playback app, and playback state. Attach screenshots without personal data when filing an issue.

Big Screen is a custom SwiftUI/AppKit interface. Screen size, display safe areas/notches, OS versions, and asynchronous rows/artwork can expose layout bugs; please include display resolution and whether there is a notch when reporting one.

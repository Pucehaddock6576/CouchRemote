# FAQ

## Does this work with every Siri Remote?

It is designed for the first-generation Apple TV Siri Remote. Other generations or Apple remotes may use different HID reports and are not promised to work.

## Do I need Xcode?

A full Xcode installation is not necessary for the supplied build script, but Apple’s Xcode Command Line Tools and macOS SDK are required.

## Why does the glass surface stop working after a macOS update?

Touch reading relies on Apple’s private MultitouchSupport framework. Private interfaces are not stable public contracts and may change between releases.

## Is the phone remote safe to use on public Wi-Fi?

It is unauthenticated plain HTTP and intended only for trusted local networks. Do not expose its port to public networks or the internet; disable it when not needed.

## Where are my settings?

`~/Library/Application Support/Couch Remote/config.json`. Use Settings → Backup to export a copy.

## Why is Big Screen not showing a song or artwork?

The source app and macOS may not share metadata/artwork. Confirm system Now Playing is enabled and check the Big Screen option and relevant player permissions. Metadata support differs by player.

## Is the EQ fix part of this version?

This package contains the project’s current source as copied from the supplied app folder. The EQ logic remains the original implementation; no experimental EQ workaround was included in this GitHub package.

## Is there an official release or license?

No release signing/notarization or license was present in the supplied project folder. See [License status](License.md); ask the repository owner before redistribution or reuse.

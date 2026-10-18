# Configuration and backups

Couch Remote stores user configuration outside the repository at:

```text
~/Library/Application Support/Couch Remote/config.json
```

The JSON includes button mappings, app profiles, touch settings, Big Screen options, widgets, and other preferences. The exact fields are part of the current app implementation and can change as the configuration version is migrated.

## Backup and restore

Open **Settings → Backup**:

- **Export backup…** saves a JSON copy to a location you choose.
- **Import backup…** restores from a JSON backup.
- **Reset everything to defaults…** replaces current preferences after a confirmation prompt.

Export a backup before testing new builds, changing many mappings, or resetting the app. Treat backups as private: user-defined shell/AppleScript mappings and preferences may reveal personal workflow information or execute commands when triggered.

## Editing JSON directly

The configuration is plain JSON, but manual edits can make it invalid or create unsupported values. Quit the app before editing to avoid racing its autosave. Keep a copy of the original. If the app cannot decode a file, the current implementation attempts to preserve a copy named `config-unreadable-<timestamp>.json` and starts with defaults.

Do not commit your real config file or backups to a public repository. `.gitignore` excludes common config filenames but cannot identify a backup saved under an arbitrary name.

## Developer note

The model and defaults live in `Sources/Config.swift`. Config migration logic is also there. When adding/removing/renaming settings, preserve backward compatibility where possible, test old JSON fixtures manually, and describe migration behavior in the pull request.

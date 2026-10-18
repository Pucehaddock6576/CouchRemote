# Couch Remote Wiki

Welcome! Couch Remote lets a first-generation Apple TV Siri Remote control a Mac. This wiki provides setup, feature, troubleshooting, and contributor guides.

## Start here

- [Getting started](Getting-Started.md) — prerequisites, pairing, building, first launch.
- [Feature guide](Features.md) — what the app can do.
- [Buttons and touch modes](Buttons-and-Touch-Modes.md) — default concepts and custom mappings.
- [Big Screen](Big-Screen.md) — the full-screen home and its navigation.

## Settings and integrations

- [Phone remote](Phone-Remote.md) — optional browser-based remote and its network exposure.
- [Configuration and backups](Configuration-and-Backups.md) — where preferences live and how to back them up.
- [Privacy and permissions](Privacy-and-Permissions.md) — macOS permissions and app data.
- [Security](Security.md) — safety notes for powerful mappings and the phone remote.

## Project contributors

- [Build and development](Build-and-Development.md) — repository layout, build command, CI, architecture.
- [Troubleshooting](Troubleshooting.md) — common setup and build problems.
- [Known limitations](Known-Limitations.md) — platform constraints and unverified behavior.
- [License status](License.md) — important reuse/redistribution information.
- [Repository publishing checklist](Repository-Checklist.md) — pre-publication tasks and legal/security review.
- [FAQ](FAQ.md).

### GitHub Wiki

These Markdown files are the documentation source and can be published in a GitHub Wiki. GitHub uses a separate wiki Git repository. After enabling the Wiki feature on GitHub, clone `https://github.com/OWNER/REPOSITORY.wiki.git`, copy the page files from this folder into that clone, then commit and push them:

```sh
git clone https://github.com/OWNER/REPOSITORY.wiki.git
cp /path/to/CouchRemote-GitHub/Wiki/*.md REPOSITORY.wiki/
cd REPOSITORY.wiki
git add '*.md'
git commit -m "Add Couch Remote wiki"
git push
```

Replace `OWNER`, `REPOSITORY`, and `/path/to/CouchRemote-GitHub` with the actual values. GitHub Wiki page links use the page name without `.md`; if a relative link from a page does not render correctly, update it to the corresponding wiki page slug. `Home.md` and `_Sidebar.md` provide the conventional home page and navigation.

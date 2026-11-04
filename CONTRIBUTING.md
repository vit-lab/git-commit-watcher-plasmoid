# Contributing

Thank you for your interest! This is a small hobby project, so keep things simple.

## Reporting bugs and ideas

Open an [issue](https://github.com/vit-lab/git-commit-watcher-plasmoid/issues) and fill in the template.
**Never paste private keys, passphrases or tokens** (or logs that contain them).
Security problems: see [SECURITY.md](SECURITY.md) and do not use public issues.

## Pull requests

- Keep a change focused; describe what it does and how you tested it.
- Follow the style of the surrounding code. QML: 4 spaces; shell: `bash`, quote variables.
- Run the checks before you push:
  - `bash -n contents/code/*.sh`
  - `qmllint contents/ui/*.qml` (from Qt; warnings about unresolved KDE modules are expected when the KDE
    QML modules are not installed)
  - `./scripts/package.sh` builds `dist/git-commit-watcher-<version>.plasmoid`; to try it, remove the installed
    version (`kpackagetool6 -t Plasma/Applet -r local.gitcommitwatcher`), install the new file
    (`kpackagetool6 -t Plasma/Applet -i dist/git-commit-watcher-*.plasmoid`) and restart the shell
    (`plasmashell --replace &`)
- The widget must stay **read-only** for repositories: no commits, pushes or working-tree changes.
- Add a line to the *Unreleased* section of [CHANGELOG.md](CHANGELOG.md).

By contributing you agree that your contribution is licensed under the project's license
(GPL-3.0-or-later).

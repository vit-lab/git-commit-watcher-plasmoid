# Git Commit Watcher

A **KDE Plasma 6** widget (plasmoid) that watches one or more git repositories, notifies you about new
commits and shows what changed — without leaving the panel.

> **Read [SECURITY.md](SECURITY.md) before you give the widget an SSH key or a token.**
> The software is provided as is and is used entirely at your own risk.

## Features

- **Several repositories** at once — local clones or remote URLs (SSH / HTTPS), each with its own branch,
  SSH key and token file. Switch between them (or "All repositories") in the popup.
- **Desktop notifications** about new commits: one summary, one per commit, or only the latest; urgency,
  timeout, author / short hash, icon and an optional sound.
- **Diff viewer**: click a commit to see its changes. The diff is colored (commit header, per-file `+/-`
  counts, added / removed lines, hunks) and its text can be selected and copied.
- **Open File** next to every changed file in the diff: opens the file as it is in that commit with your
  default application (a read-only copy; your repository is not touched).
- **Copy SHA** button, right-click menu on commits, double-click to open the commit in the browser.
- **Passphrase-protected SSH keys** are supported through a private `ssh-agent` owned by the widget
  (a KDE dialog asks for the passphrase; it is never stored).
- **HTTPS token files** for private repositories over HTTPS.
- Unread counter badge, "mark as read", optional hiding in the system tray when there is nothing new.
- Own panel icons (light and dark variants, picked from your theme), icon size *Normal* / *Big*, and an
  icon chooser if you prefer your own.
- Full settings GUI — no config files to edit.

The widget is **read-only** with respect to your repositories: it never commits, pushes or changes your
working tree (details in [SECURITY.md](SECURITY.md)).

## Requirements

- KDE Plasma **6.0** or newer
- `git`
- `notify-send` (package `libnotify`) for notifications
- SSH remotes: OpenSSH (`ssh`, `ssh-add`, `ssh-agent`, `ssh-keygen`)
- Passphrase-protected SSH keys: `kdialog` (or `ksshaskpass` / `zenity`) for the passphrase dialog
- Optional, for sounds: `canberra-gtk-play` (libcanberra) or `pw-play` (PipeWire)
- `bash` and the usual GNU tools (`timeout`, `sha1sum`, `base64`, `find`)

Developed and used on Arch Linux with KDE Plasma 6 (Wayland).

## Install

### From a release (recommended)

Download `git-commit-watcher-<version>.plasmoid` from the
[Releases](https://github.com/vit-lab/git-commit-watcher-plasmoid/releases) page, then:

```sh
kpackagetool6 -t Plasma/Applet -i git-commit-watcher-1.0.plasmoid
```

Right-click the panel or desktop → **Add or Manage Widgets…** → **Git Commit Watcher**.

### From source

```sh
git clone https://github.com/vit-lab/git-commit-watcher-plasmoid.git
cd git-commit-watcher-plasmoid
./scripts/package.sh                       # creates dist/git-commit-watcher-<version>.plasmoid
kpackagetool6 -t Plasma/Applet -i dist/git-commit-watcher-*.plasmoid
```

(Do not run `kpackagetool6 -i .` on the repository folder: it may copy the whole repository, including
`.git`, into your Plasma folder.)

### Update

Remove the old version first, then install the new package, and restart the shell:

```sh
kpackagetool6 -t Plasma/Applet -r local.gitcommitwatcher
kpackagetool6 -t Plasma/Applet -i git-commit-watcher-<new version>.plasmoid
grep Version ~/.local/share/plasma/plasmoids/local.gitcommitwatcher/metadata.json   # check the version
plasmashell --replace &
```

### Uninstall

```sh
kpackagetool6 -t Plasma/Applet -r local.gitcommitwatcher
rm -rf ~/.cache/gitcommitwatcher        # optional: the widget's cache (see "Where the data is")
```

## Quick start

1. Add the widget to a panel, open its **Settings → Repositories**.
2. **Add** a repository and enter either the path of a local clone (e.g. `~/src/project`) or a remote
   URL (`git@github.com:user/project.git`, `https://github.com/user/project.git`).
3. Set the **branch** to watch. For a local clone you may leave it empty to use the branch's upstream.
4. If the remote needs authentication, choose an **SSH key** or an **HTTPS token file** (see below), and press
   **Test connection**.
5. Adjust the check interval (default 5 minutes) and the notification style, then **OK**.

## Authentication

| Case | What to do |
| --- | --- |
| Local clone that already works with `git fetch` | Nothing — the widget uses the clone's own remote and your usual git / SSH setup. |
| SSH remote, key **without** passphrase | Pick the key file in the repository settings. |
| SSH remote, key **with** passphrase | Pick the key. The widget shows **Unlock…**; a dialog asks for the passphrase and loads the key into the widget's private `ssh-agent`. Optionally it asks automatically, and the key can expire after N hours. **Lock** removes it again. |
| HTTPS remote that needs a token | Put the token (a single line) into a file readable only by you (`chmod 600`) and pick it as the *token file*. Use a token with the smallest possible scope (read-only). |

The widget never stores passphrases or tokens in its settings: it keeps only the *paths* of the key and token
files.

## Using the popup

- Pick a repository (or "All repositories") at the top.
- **Click** a commit — show its changes. The arrow returns to the list.
- **Double-click** a commit — open it in the browser (GitHub / GitLab / Gitea-style `…/commit/<hash>` links).
- **Right-click** a commit — *Show the changes*, *Copy SHA*, *Open in the browser*.
- In the diff: select text with the mouse and copy it (Ctrl+C, right-click, or the copy button); **Copy SHA**
  copies the full hash; **Open File** (at the right of each changed file's header) opens that file as it is
  in the commit — not shown for deleted files.
- Middle-click the panel icon — check now. Right-click the icon for *Check now*, *Mark all as read*,
  *Unlock SSH keys…*.

## Where the data is

| What | Where |
| --- | --- |
| Settings (repository list, paths of key / token files, last seen commits) | your Plasma applet configuration (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) |
| Shallow copies of repositories watched **by URL**, and read-only copies made by *Open File* | `~/.cache/gitcommitwatcher/` (copies from *Open File* are deleted after a week) |
| The widget's private `ssh-agent` socket and a tiny passphrase-dialog launcher | `$XDG_RUNTIME_DIR` (`gcw-agent-<uid>.sock`, `gcw-askpass-<uid>.sh`) |

## Troubleshooting

| Problem | Cause / fix |
| --- | --- |
| `Permission denied (publickey)` | The server does not accept the chosen key. Check that the key is added to your account / repository and that you picked the right file. Try `ssh -T git@host` in a terminal. |
| "The SSH key is protected by a passphrase and is locked" | Press **Unlock…** in the popup or in the settings. If no dialog appears, install `kdialog`. |
| "The current branch has no upstream branch" | Set the branch name in the repository settings. |
| "Commit … is not available locally" | The diff needs the commit in the local copy. Wait for the next check or press *Check now*. |
| No notifications | Install `libnotify` (`notify-send`) and check *Do Not Disturb*; use **Send test notification** in the settings. |
| `kpackagetool6 -u file.plasmoid` says "Plugin is not installed" | Upgrading from an archive did not work for us: use remove (`-r`) and install (`-i`) as shown under *Update*. |
| After reinstalling, the old version is still shown | You installed the old file again; check the `Version` line (see *Update*) and restart with `plasmashell --replace &`. |
| QML errors / blank widget | `journalctl --user -b -g gitcommitwatcher` and attach the output (without secrets) to an issue. |

## Development

```
metadata.json            plugin metadata (version, author, links)
contents/config/         settings schema (main.xml) and settings pages list (config.qml)
contents/ui/             QML: main.qml (widget), config*.qml (settings), IconField.qml (icon chooser)
contents/code/           helpers.js and the shell helpers (check.sh, diff.sh, openfile.sh, agent.sh, askpass.sh)
contents/icons/          bundled panel / notification icons (SVG)
scripts/package.sh       builds dist/git-commit-watcher-<version>.plasmoid
```

- The widget runs the shell helpers through Plasma's `executable` data engine; every value is single-quoted.
- Settings that hold structured data (`repos`, `repoState`) are JSON strings.
- Useful checks: `qmllint contents/ui/*.qml` (from Qt), `bash -n contents/code/*.sh`.

See [CONTRIBUTING.md](CONTRIBUTING.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Support

- Bugs and ideas: [Issues](https://github.com/vit-lab/git-commit-watcher-plasmoid/issues)
  (never paste keys, tokens or passphrases into an issue).
- Security problems: see [SECURITY.md](SECURITY.md) — please do **not** open a public issue.
- The *About* page of the widget has a "Report an issue" link and an e-mail button for the author.

## License

[GNU General Public License v3.0 or later](LICENSE). The software is provided **without any warranty**; see
[SECURITY.md](SECURITY.md).

## Author

Vitalii Lebukhorskyi — vitalyle@protonmail.com

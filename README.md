# Git Commit Watcher

Git Commit Watcher is a KDE Plasma 6 widget for monitoring git repositories. It shows a desktop notification
when new commits appear and displays the changes of each commit in the widget popup.

Read [SECURITY.md](SECURITY.md) before using SSH keys or tokens with the widget. The software comes with no
warranty.

## Features

- Monitoring of several repositories, either local clones or remote SSH/HTTPS URLs, each with its own branch,
  SSH key and token file. One repository can be watched on several branches (`main, dev`), on all of its
  branches (`ALL`) or on those matching a pattern (`release/*`) without adding it twice.
- Notifications as a single summary, one per commit, or only for the latest commit. Urgency, timeout, icon and
  sound are configurable, and the author and short hash can be shown or hidden. The sound can be a system
  sound or your own file, with a preview button.
- Clicking a notification opens the popup with the diff of that commit.
- Diff view for every commit, with a header that separates the commit data, the message, the list of changed
  files and the diff, and with colored additions, removals and hunks. The text can be selected and copied.
- An "Open File" button next to each changed file in the diff. It opens the file as it is in that commit, from
  a read-only copy.
- A "Copy SHA" button and a context menu on commits. Double-clicking a commit opens it in the browser.
- Support for passphrase-protected SSH keys through a private `ssh-agent` used only by the widget. The
  passphrase is requested in a KDE dialog and is not stored.
- HTTPS token files for private repositories.
- An unread counter on the icon, a "mark as read" action, and optional hiding in the system tray when nothing
  is new.
- A mute switch that turns off notifications and sounds while the widget keeps checking and counting. The panel
  icon shows a red crossed-out bell badge while muted.
- A pin button that keeps the popup open. The popup size is remembered separately for the commit list and
  the diff view.
- Bundled icons (idle, new commits, muted) in light and dark variants, two icon sizes, and an icon chooser for
  custom icons.
- Configuration through the settings window.

The widget only reads from repositories. It does not commit, push or change the working tree.

## Requirements

- KDE Plasma 6.0 or newer
- git
- notify-send (package `libnotify`; version 0.8 or newer is needed for "click a notification to show the
  changes")
- OpenSSH (`ssh`, `ssh-add`, `ssh-agent`, `ssh-keygen`) for SSH remotes
- kdialog, ksshaskpass or zenity for the passphrase dialog (only for keys with a passphrase)
- canberra-gtk-play or pw-play for notification sounds (optional)
- bash and common GNU utilities (`timeout`, `sha1sum`, `base64`, `find`)

The widget has been tested on Arch Linux with KDE Plasma 6 on Wayland.

## Installation

### From the release package

Download `git-commit-watcher-1.1.plasmoid` from the
[latest release](https://github.com/vit-lab/git-commit-watcher-plasmoid/releases/latest). Use the file listed
under Assets; the automatic "Source code" archives are not installable packages.

```sh
curl -LO https://github.com/vit-lab/git-commit-watcher-plasmoid/releases/download/v1.1/git-commit-watcher-1.1.plasmoid
kpackagetool6 -t Plasma/Applet -i git-commit-watcher-1.1.plasmoid
```

The package can also be installed from the widget explorer: right-click the panel or desktop, open
"Add or Manage Widgets", then "Get New Widgets" and "Install Widget From Local File".

Afterwards, add "Git Commit Watcher" to a panel or the desktop. If the widget is not listed, restart the
shell with `systemctl --user restart plasma-plasmashell.service`. (`plasmashell --replace &` also works,
but it keeps the shell attached to the terminal, so closing the terminal ends the desktop session.)

The installed version and the checksum of the downloaded file can be checked with:

```sh
grep Version ~/.local/share/plasma/plasmoids/local.gitcommitwatcher/metadata.json
sha256sum git-commit-watcher-1.1.plasmoid
```

If the release notes list a SHA-256 checksum, it should match the output of the second command.

### From source

```sh
git clone https://github.com/vit-lab/git-commit-watcher-plasmoid.git
cd git-commit-watcher-plasmoid
./scripts/package.sh
kpackagetool6 -t Plasma/Applet -i dist/git-commit-watcher-*.plasmoid
```

`scripts/package.sh` creates `dist/git-commit-watcher-<version>.plasmoid`. Do not run `kpackagetool6 -i .` in
the repository folder, because it may copy the whole repository, including `.git`, into the Plasma directory.

### Updating

Remove the installed version, install the new package and restart the shell:

```sh
kpackagetool6 -t Plasma/Applet -r local.gitcommitwatcher
kpackagetool6 -t Plasma/Applet -i git-commit-watcher-<new version>.plasmoid
grep Version ~/.local/share/plasma/plasmoids/local.gitcommitwatcher/metadata.json
systemctl --user restart plasma-plasmashell.service
```

`kpackagetool6 -u` failed with "Plugin is not installed" when used with a `.plasmoid` file, so removal and
installation are done separately.

### Uninstalling

```sh
kpackagetool6 -t Plasma/Applet -r local.gitcommitwatcher
rm -rf ~/.cache/gitcommitwatcher
```

The second command deletes the widget's cache and is optional.

## Configuration

1. Add the widget and open its settings, page "Repositories".
2. Add a repository: the path of a local clone (for example `~/src/project`) or a remote URL
   (`git@github.com:user/project.git`, `https://github.com/user/project.git`).
3. Enter the branch to watch. For a local clone the field can stay empty, in which case the upstream branch is
   used. To watch several branches of the same repository, list them separated by commas or spaces
   (`main, dev`), tick "Watch all branches (ALL)" (or type `ALL`) to watch every branch, or use a pattern
   such as `release/*` (also together with listed branches: `main, release/*`). The branches are found
   automatically and re-checked at every check, so new branches are picked up (at most 30 branches are taken
   for ALL or a pattern); a new branch is not announced itself, only its later commits. Each branch is checked
   separately. In the popup the repository selector lists repositories, and below it a branch switcher
   ("All branches", `main`, `dev`) appears for a repository with several branches. A commit that is on more
   than one watched branch (after a merge, for example) is announced and counted once, and is listed once in
   "All repositories" with all its branches.
4. If the remote requires authentication, select an SSH key or an HTTPS token file and use "Test connection".
5. Set the check interval (5 minutes by default) and the notification options. The sound can be chosen from
   the installed system sounds or from a file ("Sound" section of the Notifications page).

### Authentication

| Situation | Setup |
| --- | --- |
| Local clone where `git fetch` already works | No setup. The clone's own remote and the existing git and SSH configuration are used. |
| SSH key without a passphrase | Select the key file in the repository settings. |
| SSH key with a passphrase | Select the key file and press "Unlock" in the popup or the settings. A dialog asks for the passphrase and the key is loaded into the widget's private `ssh-agent`. Unlocking can happen automatically, the key can expire after a set number of hours, and "Lock" removes it. |
| HTTPS with a token | Save the token on a single line in a file readable only by you (`chmod 600`) and select it as the token file. A read-only token with minimal scope is recommended. |

Passphrases and tokens are never stored by the widget. Only the paths of the key and token files are saved.

## Usage

- The drop-down at the top selects a repository or "All repositories".
- Clicking a commit shows its diff. The arrow at the top returns to the list.
- Double-clicking a commit opens it in the browser. Links of the form `<repository>/commit/<hash>` are used,
  which works for GitHub, GitLab and Gitea.
- Clicking a notification opens the popup. For a notification about one commit, the diff of that commit is
  shown; for a summary, the commit list of the repository. This can be switched off in the Notifications
  settings.
- The context menu of a commit has "Show the changes", "Copy SHA" and "Open in the browser".
- In the diff, text can be copied with Ctrl+C, the context menu or the copy button in the header. "Copy SHA"
  copies the full commit hash. "Open File" is shown on the header line of each changed file, except for
  deleted files.
- A middle click on the panel icon runs a check immediately. Its context menu has "Check now",
  "Mark all as read", "Mute notifications" and "Unlock SSH keys".
- The pin button in the popup header keeps the popup open when another window is focused.
- The bell button in the header (also in the context menu and in the Notifications settings) mutes
  notifications and sounds. Checking and the unread counter continue. Commits that arrive while muted are
  counted as unread but are not announced again after unmuting.
- The popup can be resized by dragging its edge. The size is remembered separately for the commit list and
  for the diff view.

## Stored data

| Data | Location |
| --- | --- |
| Settings: repository list, paths of key and token files, last seen commits, pin and mute state, popup sizes | Plasma configuration, `~/.config/plasma-org.kde.plasma.desktop-appletsrc` |
| Shallow copies of repositories watched by URL, and read-only copies created by "Open File" | `~/.cache/gitcommitwatcher/` (the "Open File" copies are deleted after a week) |
| Socket of the private `ssh-agent` and the passphrase dialog launcher | `$XDG_RUNTIME_DIR` (`gcw-agent-<uid>.sock`, `gcw-askpass-<uid>.sh`) |

## Troubleshooting

- `Permission denied (publickey)`: the server rejects the selected key. Check that the key is registered for
  the account or repository and that the correct file is selected. Running `ssh -T git@host` in a terminal
  shows the details.
- "The SSH key is protected by a passphrase and is locked": press "Unlock". If no dialog appears, install
  kdialog.
- "The current branch has no upstream branch": enter the branch name in the repository settings.
- "Commit ... is not available locally": the diff needs the commit in the local copy. Wait for the next check
  or use "Check now".
- Clicking a notification does nothing: `notify-send --version` must be 0.8 or newer, and the notification
  server must support actions (Plasma does). The option "Clicking a notification shows the changes" must be on.
- No notifications: check that `libnotify` is installed and Do Not Disturb is off, and use "Send test
  notification" in the settings.
- The old version still appears after reinstalling: the old package was probably installed again. Check the
  version as described under "Updating" and restart the shell.
- Blank widget or QML errors: run `journalctl --user -b -g gitcommitwatcher` and include the output in an
  issue after removing private data.

## Development

```
metadata.json        plugin metadata
contents/config/     settings schema (main.xml) and settings pages (config.qml)
contents/ui/         main.qml (widget), config*.qml (settings), IconField.qml (icon chooser)
contents/code/       helpers.js and the shell scripts (check.sh, diff.sh, openfile.sh, agent.sh, askpass.sh)
contents/icons/      bundled icons (SVG)
scripts/package.sh   builds dist/git-commit-watcher-<version>.plasmoid
```

The shell scripts are started through Plasma's `executable` data engine, and every value passed to them is
single-quoted. Structured settings (`repos`, `repoState`) are stored as JSON strings. Useful checks are
`qmllint contents/ui/*.qml` and `bash -n contents/code/*.sh`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and [CHANGELOG.md](CHANGELOG.md) for the
list of changes.

## Reporting issues

Bugs and feature requests go to the [issue tracker](https://github.com/vit-lab/git-commit-watcher-plasmoid/issues).
Do not include keys, tokens or passphrases. Security problems should be reported privately, as described in
[SECURITY.md](SECURITY.md). The About page of the widget also has a "Report an issue" link.

## License

GNU General Public License v3.0 or later, see [LICENSE](LICENSE). No warranty is provided, see
[SECURITY.md](SECURITY.md).

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1] - 2026-11-05

### Added

- Pin button in the popup header: the popup stays open when it loses focus.
- Mute switch for notifications and sounds: a bell button in the popup header, "Mute notifications" in the
  widget's context menu, and a checkbox on the Notifications page. Checking and the unread counter keep
  working; the tooltip shows when the widget is muted. Commits that arrive while muted are counted as unread
  but are not announced again after unmuting.
- Clicking a notification opens the popup and shows the changes of that commit (for a summary or a "…and N more"
  notification: the commit list of the repository). Switchable on the Notifications page ("Click"). Needs
  notify-send 0.8 or newer (libnotify); with an older version the notifications work as before and a click does
  nothing.
- Muted panel icon: while muted, the branch icon gets a red crossed-out bell badge (light and dark variants
  bundled). It can be replaced with any icon on the Behavior page ("Icon (muted)"). The unread badge is still
  shown.
- Sound chooser on the Notifications page, like the icon chooser: pick one of the sounds of the installed
  sound themes (with a filter and a play button for each), pick a sound file, or type a name or a path; a
  preview button plays the current choice.

### Changed

- The popup remembers its size, separately for the commit list and the diff view. The size no longer resets
  when a commit is opened or when going back to the list.
- Diff view: a clearer header. Colored section bars (COMMIT, MESSAGE, CHANGED FILES, DIFF) show where each part
  starts, the commit data sits on its own background, the commit message is in a highlighted panel with a
  larger, bold subject, and the hash is larger. The bars are part of the text, so they are included when the
  diff is copied.
- Notifications settings page: options are grouped into Content, Appearance and Sound, field widths are
  limited, and long labels are shortened, so the page keeps the two-column layout in a normal-sized settings
  window instead of putting the labels above the fields. The Behavior page got the same treatment.
- Sound names are also found in other sound themes than freedesktop (for example Ocean) when
  `canberra-gtk-play` is not installed and `pw-play` is used.

## [1.0] - 2026-11-04

First public release.

### Added

- Watching of one or more git repositories (local clones or remote SSH / HTTPS URLs), each with its own branch,
  SSH key and HTTPS token file; check interval setting; "Check now".
- Desktop notifications about new commits: one summary, one per commit, or only the latest; urgency, timeout,
  author and short hash options, icon and optional sound; "Send test notification" button.
- Unread counter badge on the panel icon, "Mark all as read", optional hiding in the system tray when nothing is
  new, optional mark-as-read when the popup is opened.
- Commit list with a repository switcher ("All repositories" or one repository); colored author, hash and time,
  highlighted issue references (`#123`, `ABC-123`) in subjects.
- Diff viewer (click a commit): colored commit header, per-file statistics, added / removed lines and hunks;
  text can be selected and copied.
- "Open File" button next to every changed file in the diff: opens the file as it is in that commit with the
  default application, using a read-only copy in the widget's cache folder.
- "Copy SHA" button and a right-click menu on commits; double-click opens a commit in the browser.
- Support for passphrase-protected SSH keys through a private `ssh-agent` owned by the widget, with a KDE
  passphrase dialog (the passphrase is never stored), automatic or manual unlock, key lifetime, and "Lock".
- HTTPS token files for private repositories (the token is passed to git through the environment, not on a
  command line).
- Settings GUI: repositories (add / remove / test connection), notifications, behavior (icons, icon size).
- Bundled panel and notification icons in light and dark variants, "Normal" / "Big" icon size, and an icon
  chooser (KDE "Select Icon" dialog) to pick your own.
- About page with author, e-mail button and "Report an issue" link.
- Installable package `git-commit-watcher-1.0.plasmoid` attached to the release (install with
  `kpackagetool6 -t Plasma/Applet -i` or from the widget explorer: *Get New Widgets… → Install Widget From
  Local File…*), and `scripts/package.sh` to build it from the source.
- Documentation: `README.md`, `SECURITY.md`, this changelog and issue templates.

[Unreleased]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.1...HEAD
[1.1]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.0...v1.1
[1.0]: https://github.com/vit-lab/git-commit-watcher-plasmoid/releases/tag/v1.0

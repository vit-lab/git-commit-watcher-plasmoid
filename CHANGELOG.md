# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
- Documentation: `README.md`, `SECURITY.md`, this changelog, issue templates and a packaging script.

[Unreleased]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.0...HEAD
[1.0]: https://github.com/vit-lab/git-commit-watcher-plasmoid/releases/tag/v1.0

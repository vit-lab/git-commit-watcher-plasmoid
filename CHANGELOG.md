# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.4] - 2026-11-14

### Added

- Download progress: while a check downloads, the popup shows what is happening (preparing on the server,
  downloading with the size so far, the speed and the time left, unpacking), with a progress bar in the empty
  list and a line in the footer, instead of only "Checking…".
- Stop button: while a check runs, the refresh button in the header (and "Check now" in the context menu)
  stops it, for a check that hangs. The running git, ssh and timeout processes are ended too; a repository
  without commits yet says that its check was stopped, and the button then starts a new check.

### Changed

- Repositories watched by URL download much less: one small copy per URL is shared by all its branches (it
  was one per branch), and it holds only the recent commits and folder listings. The files of a commit are
  downloaded when its changes are opened. For a big repository with many branches the first check is now
  one small download (a few MB, in seconds) instead of one large download per branch.
- In a check, the new commits of all watched branches of a repository are downloaded in one go.
- The copies made by earlier versions (one per branch, in `~/.cache/gitcommitwatcher/`) are deleted, and a
  copy that has not been used for 30 days is deleted too.
- Downloads may take up to 10 minutes (it was 90 seconds), so the first check of a big local clone no longer
  fails; questions to the server still time out after 90 seconds.

- A line separates the branch rows (and warnings) from the commit list, so the first commit no longer
  seems to belong to the rows above it.

### Fixed

- The changes of the oldest downloaded commit were shown as if it added every file of the repository. The
  widget now downloads one commit more than it lists, and for the oldest one it says that its changes cannot
  be shown.

## [1.3] - 2026-11-14

### Added

- Choosing what the popup shows: the repository drop-down lists the repositories with a check box each and
  stays open while you tick them, so any number of repositories can be shown together; its text names the
  chosen repositories. The check boxes always show what the list shows: with everything shown all of them are
  ticked, "All repositories" is partly ticked when only some are, and a click on it ticks all of them (or
  unticks all of them when all were ticked, to start a new choice).
- Choosing branches: for a repository with several branches, a line below the header has the repository's
  name (whenever the list shows more than one repository) and a "Branches" button that opens the list of its
  branches with check boxes (and a search field when there are many). The list works like the repository
  list. The chosen branches are shown next to the button in one line that scrolls sideways; a click on a
  chosen branch takes it away again. With several repositories chosen, every repository with several
  branches gets its own line. Chosen branches have the highlight color, their corners follow the system
  theme, and the lists and chips show the number of unread commits.
- The choice of repositories and branches is remembered.

### Changed

- The branch buttons are replaced by the "Branches" button; they took a lot of room with many branches and
  showed no difference for the chosen one.
- A click on a notification changes the choice of repositories and branches only when the commit is not
  already in the list. "Mark all as read" in the header marks the commits that are shown.
- "All repositories" list: every repository name has its own color (bold) instead of grey, so commits of
  different repositories are easy to tell apart; the branches after the name stay grey. The colors are handed
  out by the order of the repositories in the settings (8 colors, then they repeat) and adapt to light and
  dark themes.
- Performance with several watched branches:
  - The branches of a repository are checked in one round that talks to the remote once: one `git fetch` for a
    local clone (it was one per branch, one after another), or one `git ls-remote` for a remote URL, with a
    fetch only for the branches that have new commits (it was one fetch per branch).
  - The commit list in the popup is rebuilt once for all results that arrive together, and only when
    something that is shown has changed (it was rebuilt twice per branch in every check, which made scrolling
    and clicking stutter while a check was running).
  - The rows of the list share one context menu and one click timer, so a click on a commit is no longer lost
    when the list is rebuilt at the same moment.
- Documentation: screenshots in the README (`docs/screenshots/`).
- Documentation: the widget is listed on the KDE Store (<https://www.opendesktop.org/p/2381252>); the README
  has an installation section for it.

## [1.2] - 2026-11-06

### Added

- Several branches per repository: list them in the "Branch" field separated by commas or spaces
  (`main, dev`). Every branch is checked on its own (own unread counter, "Test connection" tests each of
  them), without adding the repository twice. A commit that is on several
  watched branches is announced once, counted once and shown once. When the chosen repository has
  several branches, a branch switcher ("All branches", "main", "dev", each with its unread count) appears under
  the header; the repository selector at the top lists repositories only. The list shows which branches a
  commit is on. Existing single-branch settings keep working unchanged. Several branches of one local clone are
  fetched one after another (`flock`).
- ALL option for the branch setting: a check box "Watch all branches (ALL)" (or `ALL` typed in the field) watches
  every branch of the repository; patterns such as `release/*` watch the branches that match, also together
  with listed ones (`main, release/*`). The branches are looked up at every check (`git ls-remote` for a
  remote URL, the fetched remote-tracking branches for a local clone) and remembered, so new branches are
  picked up and deleted ones disappear; at most 30 branches are taken. "Test connection" shows which branches
  will be watched.
- Ctrl + mouse wheel changes the text size, separately in the commit list and in the diff view (10 % per
  step, 50-300 %, remembered). A plain wheel still scrolls. The footer shows the hint, and the current size
  with a reset button when it is not 100 %.

### Changed

- The popup footer is now also shown in the diff view (with the text-size hint).
- Footer: "Watching N repositories" counted branches as repositories; it now says "Watching N branches" for
  one repository with several branches, or "Watching N repositories (M branches)".
- Repository settings: the hint in the "Path or URL" field and the text below it now also show the HTTPS form
  of a remote URL (`https://github.com/user/repo.git`).

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

[Unreleased]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.4...HEAD
[1.4]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.3...v1.4
[1.3]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.2...v1.3
[1.2]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.1...v1.2
[1.1]: https://github.com/vit-lab/git-commit-watcher-plasmoid/compare/v1.0...v1.1
[1.0]: https://github.com/vit-lab/git-commit-watcher-plasmoid/releases/tag/v1.0

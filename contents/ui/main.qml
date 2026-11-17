import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "../code/helpers.js" as Helpers

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    readonly property string scriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/check.sh"))
    readonly property string agentScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/agent.sh"))
    readonly property string diffScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/diff.sh"))
    readonly property string searchScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/search.sh"))
    readonly property string openFileScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/openfile.sh"))

    // ------------------------------------------------------------------ data
    // Enabled things to check: one entry per repository and branch (a repository with several branches in
    // its "branch" setting gives several entries, see Helpers.expandRepos):
    // {id, parentId, name, baseName, multi, path, branch, sshKey, tokenFile, enabled}
    property var repoList: []
    property var states: ({})            // id -> runtime state (see st())
    property var saved: ({})             // id -> {sig, n: last notified tip, a: last acknowledged tip}
    property var cmdMap: ({})            // running check command -> ids of the branch entries it checks
    property var discoverMap: ({})       // running branch-listing command -> repository id
    property var agentMap: ({})          // running agent command -> {id, action, key}
    property var unlockingKeys: ({})     // key path -> true while a passphrase dialog is open
    property int rev: 0                  // bumped after every change of the data above

    // What the popup shows; both are remembered in the settings (filterRepos, filterBranches).
    // selRepos: ids of repository settings; [] = all repositories, ["-"] = none.
    // selBranches: ids of branch entries; for a repository none of whose branches is in it, all its
    // branches are shown, unless it holds "<repository id>#none" (none of its branches).
    property var selRepos: []
    property var selBranches: []
    property var repoChips: []           // the repository chips: {id, text, count, color}
    property string repoChipsSig: ""
    property var branchGroups: []        // the branch rows, per shown repository with several branches:
    property string branchGroupsSig: ""  // {id, name, color, branches: [{id, text}]}
    property int viewRepoCount: 0        // repositories and branch entries in the list right now
    property int viewUnitCount: 0
    property var displayCommits: []
    property var problems: []
    property string displaySig: ""       // what displayCommits shows; the list is replaced only when it changes
    // The list shows the first cfg.listPageSize commits of displayCommits (0 = all of them); "Show more" at
    // its end adds as many again. Rows are cheap one by one, but a list of thousands scrolls less smoothly.
    property int extraShown: 0           // commits added with "Show more" since the popup was opened
    readonly property int shownLimit: cfg.listPageSize > 0 ? cfg.listPageSize + extraShown : 0
    readonly property int hiddenCount: shownLimit > 0 ? Math.max(0, matchedCommits.length - shownLimit) : 0
    readonly property var listCommits: hiddenCount > 0 ? matchedCommits.slice(0, shownLimit) : matchedCommits
    // The search (the button in the header, or Ctrl+F): the list keeps the commits of displayCommits whose
    // message, author or hash match searchText (see Helpers.filterCommits), also the ones that are not
    // shown yet. It stays when the popup closes (a search in the whole history can take a while), and ends
    // with Escape or a second click on the button.
    property bool searchOpen: false
    property string searchText: ""
    // The advanced search (the "Advanced" button next to the search field): only the commits of one author,
    // and where the words are looked for. Both apply while its row is open.
    property bool advancedOpen: false
    property string searchAuthor: ""     // "" = all authors
    property int searchField: 0          // 0 = everywhere, 1 = message, 2 = author, 3 = hash
    readonly property var searchOpts: ({ author: searchAuthor, field: searchField })
    readonly property bool searching: searchText.trim() !== "" || searchAuthor !== ""
    // What is searched for, as one text: a search in the whole history belongs to it (see deepQuery).
    readonly property string searchKey: searchText.trim() + "\n" + searchAuthor + "\n" + searchField
    // The same for the messages of the list: the text, and the author if one is chosen.
    readonly property string searchSummary: {
        var parts = [];
        if (searchText.trim() !== "") {
            parts.push("\"" + searchText.trim() + "\"");
        }
        if (searchAuthor !== "") {
            parts.push(i18n("author %1", searchAuthor));
        }
        return parts.join(", ");
    }
    // The authors to choose from: the ones of the downloaded commits of the shown branches.
    readonly property var authorChoices: {
        var names = advancedOpen ? Helpers.authorsOf(displayCommits) : [];
        if (searchAuthor !== "" && names.indexOf(searchAuthor) < 0) {
            names.unshift(searchAuthor);
        }
        return [i18n("All authors")].concat(names);
    }
    function setAdvancedOpen(open) {
        advancedOpen = open;
        if (!open) {
            searchAuthor = "";
            searchField = 0;
        }
    }
    function clearSearch() {
        searchText = "";
        searchAuthor = "";
        searchField = 0;
        searchCleared();
    }
    signal searchCleared()
    readonly property var matchedCommits: deepActive ? deepCommits
        : searching ? Helpers.filterCommits(displayCommits, searchText, searchOpts) : displayCommits
    onSearchKeyChanged: {
        extraShown = 0;
        if (deepState !== "" && searchKey !== deepQuery) {
            cancelDeepSearch();
        }
    }
    signal searchFocusWanted()

    // "All history" (or Enter in the search field): the same search in every commit of the shown branches,
    // not only in the downloaded ones (search.sh, one process per repository). Its result replaces the
    // list until the search text changes.
    readonly property int deepMax: 200   // the most commits taken per repository
    property string deepState: ""        // "" | running | done
    property string deepQuery: ""        // what is (or was) searched: the searchKey of that moment
    property var deepCommits: []         // the result, entries like the ones of displayCommits
    property bool deepMore: false        // a repository has more than deepMax matching commits
    property var deepErrors: []          // "<repository>: <message>" of the repositories that failed
    property var deepMap: ({})           // running search command -> repository id
    property var deepFound: []           // the result so far, while repositories are still searched
    readonly property bool deepRunning: deepState === "running"
    readonly property bool deepActive: deepState === "done" && searching && deepQuery === searchKey

    function cancelDeepSearch() {
        for (var cmd in deepMap) {
            searcher.disconnectSource(cmd);
        }
        deepMap = ({});
        deepFound = [];
        deepState = "";
        deepQuery = "";
        deepMore = false;
        if (deepCommits.length > 0) {
            deepCommits = [];
        }
        if (deepErrors.length > 0) {
            deepErrors = [];
        }
    }

    function startDeepSearch() {
        var query = searchText.trim();
        var key = searchKey;
        if (!searching || (deepState !== "" && deepQuery === key)) {
            return;
        }
        cancelDeepSearch();
        var ids = effectiveIds();
        var byParent = {};
        var order = [];
        for (var i = 0; i < ids.length; ++i) {
            var u = repoById(ids[i]);
            if (!u) {
                continue;
            }
            if (!byParent[u.parentId]) {
                byParent[u.parentId] = [];
                order.push(u.parentId);
            }
            byParent[u.parentId].push(u);
        }
        if (order.length === 0) {
            return;
        }
        deepQuery = key;
        deepState = "running";
        extraShown = 0;
        for (var k = 0; k < order.length; ++k) {
            var units = byParent[order[k]];
            var cmd = Helpers.searchCommand(searchScriptPath, {
                repo: units[0].path, key: units[0].sshKey, tokenFile: units[0].tokenFile,
                branches: units.map(function(x) { return x.branch; }).filter(function(b) { return b !== ""; }),
                query: query, author: searchAuthor, field: searchField, max: deepMax
            });
            deepMap[cmd] = order[k];
            searcher.connectSource(cmd);
        }
    }

    function handleDeepResult(pid, stdout, stderr, exitCode) {
        var units = parentUnits(pid);
        var res = Helpers.parseSearch(stdout, stderr, exitCode);
        if (units.length > 0 && !res.ok) {
            deepErrors = deepErrors.concat([units[0].baseName + ": " + res.msg]);
        } else if (units.length > 0) {
            deepMore = deepMore || res.more;
            var found = [];
            for (var i = 0; i < res.commits.length; ++i) {
                var c = res.commits[i];
                var u = units[0];
                for (var j = 0; j < units.length; ++j) {
                    if (units[j].branch === c.branch) {
                        u = units[j];
                        break;
                    }
                }
                var label = c.branch || u.branch;
                found.push({
                    repoId: u.id, repoName: nameOf(u.id), hash: c.hash, short: c.short, author: c.author,
                    subject: c.subject, when: c.when, ts: c.ts, unread: false, branches: [label], branchLabel: label,
                    parentId: u.parentId, repoBase: u.baseName, multi: u.multi
                });
            }
            deepFound = deepFound.concat(found);
        }
        if (Object.keys(deepMap).length === 0) {
            var all = deepFound.slice();
            all.sort(function(a, b) { return b.ts - a.ts; });
            deepCommits = all;
            deepFound = [];
            deepState = "done";
        }
    }

    function openSearch() {
        if (diffCommit !== null) {
            closeDiff();
        }
        searchOpen = true;
        searchFocusWanted();
    }
    function closeSearch() {
        searchOpen = false;
        searchText = "";
        setAdvancedOpen(false);
        cancelDeepSearch();
    }
    property string problemsSig: ""
    property string cycle: ""            // id of the current check round (see check.sh, PGW_CYCLE)
    property int cycleCount: 0

    property var diffCommit: null
    property var diffLines: []
    property string diffState: "idle"    // loading | ok | error
    property string diffError: ""
    property bool diffTruncated: false
    property string diffCmd: ""
    property string diffKey: ""
    property var diffCache: ({})
    property var openMap: ({})           // running "open file" command -> true
    property var notifyTargets: ({})     // running notify-send command -> {repoId, hash} to show on click

    // Repositories whose branch setting is ALL or a pattern: their branches are looked up (and cached).
    property var parsedRepos: []
    property var discovered: ({})        // repository id -> branch names found
    property var discoverState: ({})     // repository id -> {cmd, started, error, locked, prompted}
    readonly property bool waitingForBranches: repoList.length === 0 && parsedRepos.some(function(r) {
        return r.enabled && Helpers.hasWildcard(r.branch);
    })
    readonly property bool unconfigured: repoList.length === 0 && !waitingForBranches
    readonly property int totalUnread: { root.rev; return sumUnread(); }
    readonly property bool anyOverflow: { root.rev; return anyState("overflow"); }
    // A check runs, or the branch list of an "ALL" / pattern setting is being looked up.
    readonly property bool anyChecking: {
        root.rev;
        return anyState("checking") || Object.keys(discoverState).some(function(k) { return discoverState[k].cmd !== ""; });
    }
    // Download progress of the running checks, per repository setting: { parentId: { phase, percent,
    // size, speed, eta, name } }. Read from the progress files of check.sh while the popup is open.
    property var progress: ({})
    property var progressStart: ({})  // progress key -> { phase, percent, t }: for the time left
    property string progressCmd: ""
    // The progress to show: of a shown repository if one is downloading, else of any.
    readonly property var activeProgress: {
        var shown = shownRepoIds();
        var any = null;
        for (var pid in progress) {
            if (shown.indexOf(pid) >= 0) {
                return progress[pid];
            }
            any = any || progress[pid];
        }
        return any;
    }
    readonly property bool anyLocked: { root.rev; return anyState("locked"); }
    readonly property bool showRepoBar: { root.rev; return parentCount() > 1; }
    // The text of the repository drop-down: "All repositories", or the names of the chosen ones.
    readonly property string repoSummary: {
        if (selRepos.length === 0) {
            return totalUnread > 0 ? i18n("All repositories (%1)", totalUnread) : i18n("All repositories");
        }
        if (selRepos.indexOf("-") >= 0) {
            return i18n("No repository chosen");
        }
        var names = [];
        for (var i = 0; i < repoChips.length; ++i) {
            if (selRepos.indexOf(repoChips[i].id) >= 0) {
                names.push(repoChips[i].text);
            }
        }
        return names.join(", ");
    }
    readonly property bool showBranchBar: branchGroups.length > 0
    // With several branch rows they can be folded into one line (remembered): with many repositories they
    // take a lot of room.
    readonly property bool branchRowsFoldable: branchGroups.length > 1
    readonly property bool branchRowsFolded: branchRowsFoldable && cfg.branchRowsFolded
    // Shown next to the folded line, so that a choice of branches is not hidden by surprise.
    readonly property string branchFoldSummary: {
        root.rev;
        root.selBranches;
        var some = 0, none = 0;
        for (var i = 0; i < branchGroups.length; ++i) {
            var g = branchGroups[i];
            var k = shownUnits(g.id).length;
            if (k === 0) {
                none++;
            } else if (k < g.branches.length) {
                some++;
            }
        }
        var parts = [];
        if (some > 0) {
            parts.push(i18np("a choice of branches in %1 repository", "a choice of branches in %1 repositories", some));
        }
        if (none > 0) {
            parts.push(i18np("no branch chosen in %1 repository", "no branch chosen in %1 repositories", none));
        }
        return parts.length > 0 ? parts.join(", ") : i18n("all branches");
    }
    readonly property string headerTitle: { root.rev; return parentCount() === 1 ? repoList[0].baseName : i18n("Plasma Git Watcher"); }

    // Re-read the repository list whenever the setting changes (e.g. after "Apply").
    readonly property string reposJson: cfg.repos
    onReposJsonChanged: reloadRepos()

    // The Performance settings: another number of branches for ALL / a pattern changes what is watched,
    // another number of commits per branch is downloaded by a new check.
    property bool started: false         // set when the widget has loaded: the handlers below wait for it
    readonly property int maxAutoBranches: cfg.maxAutoBranches
    onMaxAutoBranchesChanged: if (started) reloadRepos()
    readonly property int commitLimit: Math.max(1, cfg.commitsPerBranch)
    onCommitLimitChanged: if (started) Qt.callLater(root.checkAll)
    readonly property int listPageSize: cfg.listPageSize
    onListPageSizeChanged: extraShown = 0

    // ------------------------------------------------ colors, clipboard
    function mix(c, a) {
        return Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(c, a)).toString();
    }

    function rgba(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
    }

    readonly property var diffPalette: ({
        text: Kirigami.Theme.textColor.toString(),
        muted: mix(Kirigami.Theme.textColor, 0.6),
        pos: Kirigami.Theme.positiveTextColor.toString(),
        neg: Kirigami.Theme.negativeTextColor.toString(),
        link: Kirigami.Theme.linkColor.toString(),
        warn: Kirigami.Theme.neutralTextColor.toString(),
        bgAdd: rgba(Kirigami.Theme.positiveTextColor, 0.16),
        bgDel: rgba(Kirigami.Theme.negativeTextColor, 0.16),
        bgHunk: rgba(Kirigami.Theme.highlightColor, 0.14),
        bgFile: rgba(Kirigami.Theme.textColor, 0.10),
        bgBand: rgba(Kirigami.Theme.highlightColor, 0.38),
        bgMsg: rgba(Kirigami.Theme.highlightColor, 0.10),
        buttonSpace: openButtonWidth + Kirigami.Units.smallSpacing      // room for the "Open File" buttons
    })
    readonly property int openButtonWidth: Math.max(Kirigami.Units.gridUnit * 4, Math.round(Kirigami.Units.gridUnit * 7 * cfg.diffTextScale / 100))

    // ---- text size (Ctrl + mouse wheel), in percent, separately for the list and the diff
    function fontPt(f) {
        return f.pointSize > 0 ? f.pointSize : (f.pixelSize > 0 ? f.pixelSize * 0.75 : 10);
    }

    property real wheelAcc: 0

    // One mouse-wheel notch (120) changes the size by 10 %; touchpad deltas are added up.
    function wheelScale(isDiff, angleY) {
        wheelAcc += angleY;
        var steps = Math.trunc(wheelAcc / 120);
        if (steps === 0) {
            return;
        }
        wheelAcc -= steps * 120;
        var cur = isDiff ? cfg.diffTextScale : cfg.listTextScale;
        var next = Math.max(50, Math.min(300, cur + steps * 10));
        if (isDiff) {
            cfg.diffTextScale = next;
        } else {
            cfg.listTextScale = next;
        }
    }

    function resetScale(isDiff) {
        if (isDiff) {
            cfg.diffTextScale = 100;
        } else {
            cfg.listTextScale = 100;
        }
    }
    readonly property var rowColors: ({
        hash: Kirigami.Theme.neutralTextColor.toString(),
        author: Kirigami.Theme.linkColor.toString(),
        muted: mix(Kirigami.Theme.textColor, 0.6)
    })
    // The color of each repository's name in the "All repositories" list: repository id -> "#rrggbb",
    // handed out by the position of the repository in the settings.
    readonly property var repoColors: {
        var bg = Kirigami.Theme.backgroundColor;
        var m = {};
        for (var i = 0; i < parsedRepos.length; ++i) {
            m[parsedRepos[i].id] = Helpers.repoColor(i, bg.r, bg.g, bg.b);
        }
        return m;
    }
    readonly property var diffMarks: Helpers.diffFileMarks(diffLines)      // where the "Open File" buttons go
    readonly property string diffHtml: diffLines.length > 0 ? Helpers.diffToHtml(diffLines, diffPalette) : ""

    property string flashNote: ""
    property bool flashError: false

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    Timer {
        id: flashTimer
        interval: 2000
        onTriggered: root.flashNote = ""
    }

    function copyToClipboard(text, note) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        clipboardHelper.text = "";
        flash(note, false);
    }

    function flash(note, isError) {
        flashError = isError;
        flashNote = note;
        flashTimer.restart();
    }

    function copySha(c) {
        if (c && c.hash) {
            copyToClipboard(c.hash, i18n("SHA copied"));
        }
    }

    // Bundled icons (contents/icons): "idle-*" / "new-*", in a dark and a light variant.
    // An empty icon setting means "use the bundled icon"; any other value is a theme icon
    // name or a file chosen by the user.
    readonly property bool lightText: Kirigami.Theme.textColor.hslLightness > 0.5

    function bundledIcon(kind, light) {
        return Qt.resolvedUrl("../icons/" + kind + "-" + (light ? "light" : "dark") + ".svg").toString();
    }

    function resolveIcon(name, kind, light) {
        return name ? name : bundledIcon(kind, light);
    }

    // The panel icon: "muted" while notifications are muted (the unread badge is still shown),
    // otherwise "new" or "idle".
    readonly property string panelIcon: cfg.muted ? resolveIcon(cfg.iconMuted, "muted", lightText)
                                       : totalUnread > 0 ? resolveIcon(cfg.iconNew, "new", lightText)
                                                         : resolveIcon(cfg.iconIdle, "idle", lightText)
    // One of the bundled icons (not one chosen in the settings): they all have the branch symbol, whose
    // bottom circle is empty (see the dot shown while a check runs).
    readonly property bool panelIconBundled: ["idle", "new", "muted"].some(function(k) { return panelIcon === bundledIcon(k, lightText); })

    Plasmoid.icon: panelIcon
    Plasmoid.status: (cfg.hideWhenRead && totalUnread === 0)
                     ? PlasmaCore.Types.PassiveStatus
                     : PlasmaCore.Types.ActiveStatus

    // With "pin" on, the popup stays open when another window gets the focus.
    hideOnWindowDeactivate: !cfg.pin

    toolTipMainText: parentCount() === 1 ? headerTitle : i18n("Plasma Git Watcher")
    toolTipSubText: {
        root.rev;
        var t = buildTooltip();
        return cfg.muted ? i18n("Notifications are muted") + (t !== "" ? "\n" + t : "") : t;
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.anyChecking ? i18n("Stop checking") : i18n("Check now")
            icon.name: root.anyChecking ? "process-stop" : "view-refresh"
            onTriggered: root.anyChecking ? root.stopChecks() : root.checkAll()
        },
        PlasmaCore.Action {
            text: i18n("Mark all as read")
            icon.name: "checkmark"
            enabled: root.totalUnread > 0
            onTriggered: root.markAllRead("all")
        },
        PlasmaCore.Action {
            text: i18n("Mute notifications")
            icon.name: root.cfg.muted ? "notifications-disabled" : "notifications"
            checkable: true
            checked: root.cfg.muted
            onTriggered: root.cfg.muted = !root.cfg.muted
        },
        PlasmaCore.Action {
            text: i18n("Unlock SSH keys…")
            icon.name: "object-unlocked"
            visible: root.anyLocked
            onTriggered: root.unlockAll()
        }
    ]

    // --------------------------------------------------------------- engines

    Plasma5Support.DataSource {
        id: checker
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var ids = root.cmdMap[sourceName];
            if (ids !== undefined) {
                delete root.cmdMap[sourceName];
                root.handleResults(ids, sourceName, data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    // Runs the "stop" command of check.sh (see stopChecks).
    Plasma5Support.DataSource {
        id: stopper
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    // Reads the download progress of the running checks (see check.sh, net_fetch).
    Plasma5Support.DataSource {
        id: progressSrc
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName === root.progressCmd) {
                root.progressCmd = "";
                root.handleProgress(data["stdout"]);
            }
        }
    }

    Timer {
        id: progressTimer
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.anyChecking && root.expanded
        onTriggered: root.pollProgress()
        onRunningChanged: {
            if (!running) {
                root.progress = ({});
                root.progressStart = ({});
            }
        }
    }

    Plasma5Support.DataSource {
        id: finder
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var id = root.discoverMap[sourceName];
            if (id !== undefined) {
                delete root.discoverMap[sourceName];
                root.handleDiscovered(id, sourceName, data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    Plasma5Support.DataSource {
        id: agentSrc
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var info = root.agentMap[sourceName];
            if (info) {
                delete root.agentMap[sourceName];
                root.handleAgentResult(info, data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    // Runs the searches in the whole history (see startDeepSearch).
    Plasma5Support.DataSource {
        id: searcher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var pid = root.deepMap[sourceName];
            if (pid !== undefined) {
                delete root.deepMap[sourceName];
                root.handleDeepResult(pid, data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    Plasma5Support.DataSource {
        id: differ
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName === root.diffCmd) {
                root.handleDiffResult(data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    Plasma5Support.DataSource {
        id: opener
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (root.openMap[sourceName]) {
                delete root.openMap[sourceName];
                root.handleOpenResult(data["stdout"], data["stderr"], data["exit code"]);
            }
        }
    }

    Plasma5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var target = root.notifyTargets[sourceName];
            if (target !== undefined) {
                delete root.notifyTargets[sourceName];
                // notify-send prints the name of the action when the notification was clicked.
                var action = String(data["stdout"] || "").trim();
                if (action === "default" || action === "open") {
                    root.openFromNotification(target);
                }
            }
        }
    }

    Timer {
        interval: Math.max(1, root.cfg.intervalMinutes) * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.checkAll()
    }

    // Versions before 1.2 stored the old built-in icon names as the "default"; an empty value
    // now means "bundled icon", so move those over.
    function migrateIcons() {
        if (cfg.iconIdle === "vcs-normal") {
            cfg.iconIdle = "";
        }
        if (cfg.iconNew === "vcs-update-required") {
            cfg.iconNew = "";
        }
        if (cfg.notifyIcon === "vcs-update-required") {
            cfg.notifyIcon = "";
        }
    }

    Component.onCompleted: {
        migrateIcons();
        started = true;
        reloadRepos();
    }

    // ------------------------------------------------------- state helpers

    function st(id) {
        var s = states[id];
        if (!s) {
            s = {
                commits: [], tip: "", webUrl: "", checkState: "idle", error: "", lastCheck: "",
                unread: 0, overflow: false, highlight: 0, locked: false,
                started: 0, cmd: "", prompted: false
            };
            states[id] = s;
        }
        return s;
    }

    function repoById(id) {
        for (var i = 0; i < repoList.length; ++i) {
            if (repoList[i].id === id) {
                return repoList[i];
            }
        }
        return null;
    }

    function nameOf(id) {
        return Helpers.repoDisplayName(repoById(id));
    }

    // Unread commits of all repositories. A commit that is on several watched branches of the same
    // repository (for example after a merge) is counted once.
    // The entries (repository + branch) that belong to one repository setting.
    function parentUnits(parentId) {
        return repoList.filter(function(r) { return r.parentId === parentId; });
    }

    // Number of repository settings that are being watched (a repository with several branches counts once).
    function parentCount() {
        var seen = {};
        var n = 0;
        for (var i = 0; i < repoList.length; ++i) {
            if (!seen[repoList[i].parentId]) {
                seen[repoList[i].parentId] = true;
                ++n;
            }
        }
        return n;
    }

    // onlyParent (optional): count only the branches of that repository.
    function sumUnread(onlyParent) {
        var n = 0;
        var seen = {};
        for (var i = 0; i < repoList.length; ++i) {
            var r = repoList[i];
            if (onlyParent !== undefined && r.parentId !== onlyParent) {
                continue;
            }
            var s = st(r.id);
            if (!r.multi) {
                n += s.unread;
                continue;
            }
            for (var k = 0; k < s.unread && k < s.commits.length; ++k) {
                var key = r.parentId + "|" + s.commits[k].hash;
                if (!seen[key]) {
                    seen[key] = true;
                    ++n;
                }
            }
        }
        return n;
    }

    // True if another watched branch of the same repository already lists this commit.
    function seenOnSibling(r, hash) {
        if (!r.multi) {
            return false;
        }
        for (var i = 0; i < repoList.length; ++i) {
            var o = repoList[i];
            if (o.id !== r.id && o.parentId === r.parentId) {
                var cs = st(o.id).commits;
                for (var k = 0; k < cs.length; ++k) {
                    if (cs[k].hash === hash) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    function anyState(which) {
        for (var i = 0; i < repoList.length; ++i) {
            var s = st(repoList[i].id);
            if ((which === "overflow" && s.unread > 0 && s.overflow)
                || (which === "checking" && s.checkState === "checking")
                || (which === "locked" && s.locked)) {
                return true;
            }
        }
        return false;
    }

    // Something changed. The numbers (badge, tooltip, busy indicator) follow at once. The list in the
    // popup is rebuilt a moment later, once for everything that arrives together: a check round reports
    // every watched branch on its own, and a rebuild for each of them made the popup stutter.
    function bump() {
        rev++;
        if (!displayTimer.running) {
            displayTimer.start();
        }
    }

    // The same, with the list rebuilt at once (for things the user has just done).
    function bumpNow() {
        rev++;
        displayTimer.stop();
        buildDisplay();
    }

    Timer {
        id: displayTimer
        interval: 150
        onTriggered: root.buildDisplay()
    }

    function loadSaved() {
        try {
            var o = JSON.parse(cfg.repoState || "{}");
            return (o && typeof o === "object") ? o : {};
        } catch (e) {
            return {};
        }
    }

    function saveState() {
        cfg.repoState = JSON.stringify(saved);
    }

    // Older versions watched a single repository; carry it over.
    function migrateLegacy() {
        if ((cfg.repos && cfg.repos !== "[]") || !cfg.repo) {
            return;
        }
        var r = {
            id: Helpers.newId(), name: "", path: cfg.repo, branch: cfg.branch,
            sshKey: cfg.sshKey, tokenFile: cfg.tokenFile, enabled: true
        };
        var sv = loadSaved();
        if (cfg.stateRepo === cfg.repo + "|" + cfg.branch && cfg.lastNotified) {
            sv[r.id] = { sig: r.path + "|" + r.branch, n: cfg.lastNotified, a: cfg.ackedTip || cfg.lastNotified };
        }
        cfg.repoState = JSON.stringify(sv);
        cfg.repos = JSON.stringify([r]);
        cfg.repo = "";
        cfg.stateRepo = "";
        cfg.lastNotified = "";
        cfg.ackedTip = "";
    }

    function loadDiscovered() {
        try {
            var o = JSON.parse(cfg.branchCache || "{}");
            discovered = (o && typeof o === "object") ? o : {};
        } catch (e) {
            discovered = {};
        }
    }

    function reloadRepos() {
        migrateLegacy();
        loadDiscovered();
        rebuildUnits();
        Qt.callLater(root.checkAll);
    }

    // (Re)builds the list of things to check from the settings and the branches found so far.
    function rebuildUnits() {
        parsedRepos = Helpers.parseRepos(cfg.repos, false);
        var all = Helpers.expandRepos(parsedRepos, discovered, cfg.maxAutoBranches);
        saved = loadSaved();

        var list = [];
        var keep = {};
        for (var i = 0; i < all.length; ++i) {
            if (all[i].enabled) {
                list.push(all[i]);
                keep[all[i].id] = true;
            }
        }
        for (var id in states) {
            if (!keep[id]) {
                var old = states[id];
                // A check of several branches goes on for the others.
                var running = old.cmd ? cmdMap[old.cmd] : undefined;
                if (running !== undefined) {
                    var rest = running.filter(function(x) { return x !== id; });
                    if (rest.length > 0) {
                        cmdMap[old.cmd] = rest;
                    } else {
                        checker.disconnectSource(old.cmd);
                        delete cmdMap[old.cmd];
                    }
                }
                delete states[id];
            }
        }
        repoList = list;
        // The remembered selection, without repositories and branches that are not watched (any more).
        var stored = parseIdList(cfg.filterRepos);
        var sr = stored.filter(function(x) { return parentUnits(x).length > 0; });
        selRepos = stored.indexOf("-") >= 0 ? ["-"] : (sr.length >= parentCount() ? [] : sr);
        selBranches = parseIdList(cfg.filterBranches).filter(function(x) {
            return keep[x] === true || (/#none$/.test(x) && parentUnits(x.slice(0, -5)).length > 0);
        });
        for (var j = 0; j < list.length; ++j) {
            updateUnread(list[j].id);
        }
        bumpNow();
    }

    // What stands before the hash in a list row (see Helpers.metaHtml): with several repositories in the
    // list, the name of the repository in its own color, followed by its branches; with several branches
    // of one repository, the branches; nothing when the list shows a single branch.
    function rowPrefix(c) {
        if (viewRepoCount > 1) {
            return {
                name: c.repoBase,
                rest: c.multi ? " (" + c.branchLabel + ")" : "",
                color: repoColors[c.parentId] || ""
            };
        }
        if (viewUnitCount > 1) {
            return c.branchLabel;
        }
        return "";
    }

    function buildTooltip() {
        if (repoList.length === 0) {
            return waitingForBranches ? i18n("Looking for branches…") : i18n("No repository configured");
        }
        var lines = [];
        var latest = "";
        for (var i = 0; i < repoList.length; ++i) {
            var r = repoList[i];
            var s = st(r.id);
            var name = Helpers.repoDisplayName(r);
            if (s.locked) {
                lines.push(i18n("%1: SSH key is locked", name));
            } else if (s.checkState === "error") {
                lines.push(i18n("%1: %2", name, s.error));
            } else if (s.unread > 0) {
                lines.push(s.overflow ? i18n("%1: %2+ new commits", name, s.unread)
                                      : i18n("%1: %2", name, i18np("%1 new commit", "%1 new commits", s.unread)));
            }
            if (s.lastCheck) {
                latest = s.lastCheck;
            }
        }
        if (lines.length === 0) {
            return latest ? i18n("No new commits (checked %1)", latest) : i18n("Checking…");
        }
        return lines.join("\n");
    }

    // ----------------------------------------------------- display model

    // ---------------------------------------- selection of repositories and branches

    function parseIdList(json) {
        try {
            var a = JSON.parse(json || "[]");
            return Array.isArray(a) ? a.filter(function(x) { return typeof x === "string" && x !== ""; }) : [];
        } catch (e) {
            return [];
        }
    }

    function repoShown(pid) {
        return !showRepoBar || selRepos.length === 0 || selRepos.indexOf(pid) >= 0;
    }

    // The ids of the repositories that are shown.
    function shownRepoIds() {
        var out = [];
        var seen = {};
        for (var i = 0; i < repoList.length; ++i) {
            var pid = repoList[i].parentId;
            if (!seen[pid]) {
                seen[pid] = true;
                if (repoShown(pid)) {
                    out.push(pid);
                }
            }
        }
        return out;
    }

    // The branch entries of a repository that the list shows: the chosen ones, all if none is chosen,
    // or none.
    function shownUnits(pid) {
        if (selBranches.indexOf(pid + "#none") >= 0) {
            return [];
        }
        var all = parentUnits(pid);
        var chosen = all.filter(function(u) { return selBranches.indexOf(u.id) >= 0; });
        return chosen.length > 0 ? chosen : all;
    }

    // The ids of the branch entries whose commits the list shows.
    function effectiveIds() {
        var ids = [];
        var seen = {};
        for (var i = 0; i < repoList.length; ++i) {
            var pid = repoList[i].parentId;
            if (seen[pid] || !repoShown(pid)) {
                continue;
            }
            seen[pid] = true;
            var su = shownUnits(pid);
            for (var k = 0; k < su.length; ++k) {
                ids.push(su[k].id);
            }
        }
        return ids;
    }

    function setSelection(repos, branches) {
        selRepos = repos;
        selBranches = branches;
        var r = JSON.stringify(repos);
        var b = JSON.stringify(branches);
        if (cfg.filterRepos !== r) {
            cfg.filterRepos = r;
        }
        if (cfg.filterBranches !== b) {
            cfg.filterBranches = b;
        }
        extraShown = 0;
        cancelDeepSearch();
        closeDiff();
        bumpNow();
    }

    // A click on a repository in the list (pid) shows it or hides it. A click on "All repositories" ("")
    // shows all of them, or none if all were shown. The check boxes always show what the list shows.
    function toggleRepo(pid) {
        var all = [];
        var seen = {};
        for (var i = 0; i < repoList.length; ++i) {
            if (!seen[repoList[i].parentId]) {
                seen[repoList[i].parentId] = true;
                all.push(repoList[i].parentId);
            }
        }
        var shown = shownRepoIds();
        if (pid === "") {
            shown = shown.length === all.length ? [] : all.slice();
        } else if (shown.indexOf(pid) >= 0) {
            shown = shown.filter(function(x) { return x !== pid; });
        } else {
            shown.push(pid);
        }
        // Stored: [] = all (so a repository that is added later is shown too), ["-"] = none.
        setSelection(shown.length === all.length ? [] : (shown.length === 0 ? ["-"] : shown), selBranches);
    }

    // The same for the branches of repository pid (uid: the id of a branch entry, "" = "All branches").
    function toggleBranch(pid, uid) {
        var inRepo = parentUnits(pid).map(function(u) { return u.id; });
        var others = selBranches.filter(function(x) { return inRepo.indexOf(x) < 0 && x !== pid + "#none"; });
        var shown = shownUnits(pid).map(function(u) { return u.id; });
        if (uid === "") {
            shown = shown.length === inRepo.length ? [] : inRepo.slice();
        } else if (shown.indexOf(uid) >= 0) {
            shown = shown.filter(function(x) { return x !== uid; });
        } else {
            shown.push(uid);
        }
        // Stored: nothing = all branches (so a branch found later is shown too), "<id>#none" = none.
        var mine = shown.length === inRepo.length ? [] : (shown.length === 0 ? [pid + "#none"] : shown);
        setSelection(selRepos, others.concat(mine));
    }

    function buildDisplay() {
        var ids = effectiveIds();
        var viewParents = {};
        var nParents = 0;
        for (var v = 0; v < ids.length; ++v) {
            var vu = repoById(ids[v]);
            if (vu && !viewParents[vu.parentId]) {
                viewParents[vu.parentId] = true;
                ++nParents;
            }
        }
        viewRepoCount = nParents;
        viewUnitCount = ids.length;
        var out = [];
        var probs = [];
        var merged = {};                 // parentId|hash -> entry, for commits on several watched branches
        for (var k = 0; k < ids.length; ++k) {
            var id = ids[k];
            var s = st(id);
            var u = repoById(id);
            var hl = Math.max(s.unread, s.highlight);
            for (var i = 0; i < s.commits.length; ++i) {
                var c = s.commits[i];
                if (ids.length > 1 && u && u.multi) {
                    var mk = u.parentId + "|" + c.hash;
                    var prev = merged[mk];
                    if (prev) {
                        prev.branches.push(u.branch);
                        prev.repoName = u.baseName + " (" + prev.branches.join(", ") + ")";
                        prev.branchLabel = prev.branches.join(", ");
                        prev.unread = prev.unread || i < hl;
                        continue;
                    }
                }
                var entry = {
                    repoId: id, repoName: nameOf(id), hash: c.hash, short: c.short, author: c.author,
                    subject: c.subject, when: c.when, ts: c.ts, unread: i < hl, branches: [u ? u.branch : ""], branchLabel: u ? u.branch : "",
                    parentId: u ? u.parentId : id, repoBase: u ? u.baseName : nameOf(id), multi: !!(u && u.multi)
                };
                if (ids.length > 1 && u && u.multi) {
                    merged[u.parentId + "|" + c.hash] = entry;
                }
                out.push(entry);
            }
            if (s.locked || s.checkState === "error") {
                probs.push({ id: id, name: nameOf(id), msg: s.error, locked: s.locked });
            }
        }
        if (ids.length > 1) {
            out.sort(function(a, b) { return b.ts - a.ts; });
        }
        for (var pid2 in discoverState) {
            var ds = discoverState[pid2];
            var pr = parsedRepos.filter(function(x) { return x.id === pid2 && x.enabled; })[0];
            if (pr && ds.error) {
                probs.push({ id: pid2, name: Helpers.repoDisplayName(pr), msg: ds.error, locked: ds.locked });
            }
        }
        // Replacing the model makes the list throw away and rebuild its rows, so do it only when
        // something that is shown has changed.
        var parts = [];
        for (var n = 0; n < out.length; ++n) {
            var e = out[n];
            parts.push(e.repoId + "\t" + e.hash + "\t" + (e.unread ? 1 : 0) + "\t" + e.repoName + "\t" + e.branchLabel + "\t" + e.when);
        }
        var dsig = nParents + "/" + ids.length + "\n" + parts.join("\n");
        if (dsig !== displaySig || out.length !== displayCommits.length) {
            displaySig = dsig;
            displayCommits = out;
        }
        var psig = JSON.stringify(probs);
        if (psig !== problemsSig) {
            problemsSig = psig;
            problems = probs;
        }

        // The chips of the repositories and branches; replaced only when something in them changed.
        var chips = [];
        var groups = [];
        var seenParent = {};
        for (var j = 0; j < repoList.length; ++j) {
            var pid = repoList[j].parentId;
            if (seenParent[pid]) {
                continue;
            }
            seenParent[pid] = true;
            if (showRepoBar) {
                chips.push({ id: pid, text: repoList[j].baseName, count: sumUnread(pid), color: repoColors[pid] || "" });
            }
            var pu = parentUnits(pid);
            if (pu.length > 1 && repoShown(pid)) {
                // Without the unread counts (they are read where they are shown): the rows are rebuilt only
                // when the branches change, so an open branch list is not closed by a check.
                groups.push({
                    id: pid, name: pu[0].baseName, color: repoColors[pid] || "",
                    branches: pu.map(function(u) { return { id: u.id, text: u.branch }; })
                });
            }
        }
        var csig = JSON.stringify(chips);
        if (csig !== repoChipsSig) {
            repoChipsSig = csig;
            repoChips = chips;
        }
        var gsig = JSON.stringify(groups);
        if (gsig !== branchGroupsSig) {
            branchGroupsSig = gsig;
            branchGroups = groups;
        }
    }

    // ------------------------------------------------------ download progress

    function pollProgress() {
        if (progressCmd !== "") {
            return;  // the last poll has not answered yet
        }
        progressCmd = Helpers.progressCommand();
        progressSrc.connectSource(progressCmd);
    }

    function handleProgress(stdout) {
        if (!progressTimer.running) {
            return;
        }
        var raw = Helpers.parseProgressList(stdout);
        var parents = {};  // progress key -> repository setting
        for (var i = 0; i < repoList.length; ++i) {
            parents[Helpers.progressKey(repoList[i].parentId)] = repoList[i].parentId;
        }
        var out = {};
        var starts = {};
        var now = Date.now();
        for (var k in raw) {
            var pid = parents[k];
            // Only while a check of the repository runs: a file left over by a stopped check is ignored.
            if (pid === undefined || !parentUnits(pid).some(function(u) { return st(u.id).checkState === "checking"; })) {
                continue;
            }
            var p = Helpers.parseGitProgress(raw[k]);
            var prev = progressStart[k];
            var start = (prev && prev.phase === p.phase) ? prev : { phase: p.phase, percent: Math.max(0, p.percent), t: now };
            starts[k] = start;
            p.eta = p.phase === "download" ? Helpers.etaSeconds(now - start.t, p.percent - start.percent, 100 - p.percent) : -1;
            var u = parentUnits(pid)[0];
            p.name = u ? (u.baseName || u.name) : "";
            out[pid] = p;
        }
        progressStart = starts;
        progress = out;
    }

    // The whole download as one bar: preparing on the server, downloading, unpacking. -1: not known
    // (the bar then just moves).
    function progressValue(p) {
        if (!p) {
            return -1;
        }
        switch (p.phase) {
        case "server": return p.percent < 0 ? -1 : p.percent * 0.05;
        case "download": return 5 + Math.max(0, p.percent) * 0.85;
        case "unpack": return p.percent < 0 ? 99 : 90 + p.percent * 0.1;
        }
        return -1;
    }

    function progressText(p) {
        if (!p) {
            return "";
        }
        var pct = p.percent >= 0 ? " " + i18nc("percentage", "%1%", p.percent) : "";
        switch (p.phase) {
        case "server":
            return i18n("Preparing on the server…") + pct;
        case "unpack":
            return i18n("Unpacking…") + pct;
        case "download": {
            var parts = [i18n("Downloading") + pct];
            if (p.size) {
                parts.push(p.size);
            }
            if (p.speed) {
                parts.push(p.speed);
            }
            if (p.eta >= 0) {
                parts.push(p.eta < 60 ? i18np("about %1 second left", "about %1 seconds left", Math.max(5, Math.round(p.eta / 5) * 5))
                                      : i18np("about %1 minute left", "about %1 minutes left", Math.round(p.eta / 60)));
            }
            return parts.join(" · ");
        }
        }
        return i18n("Connecting…");
    }

    // ------------------------------------------------------------- checks

    // Stops all running checks (the Stop button): their results are no longer awaited, and check.sh
    // ends their processes. A repository that has commits keeps showing them; one without says that
    // its check was stopped. The refresh button starts a new check.
    function stopChecks() {
        for (var id in states) {
            var s = states[id];
            if (s.checkState !== "checking") {
                continue;
            }
            if (s.cmd) {
                checker.disconnectSource(s.cmd);
                delete cmdMap[s.cmd];
                s.cmd = "";
            }
            if (s.commits.length > 0) {
                s.checkState = "ok";
            } else {
                s.checkState = "error";
                s.error = i18n("The check was stopped. Press the refresh button to check again.");
            }
        }
        for (var pid in discoverState) {
            var d = discoverState[pid];
            if (d.cmd) {
                finder.disconnectSource(d.cmd);
                delete discoverMap[d.cmd];
                d.cmd = "";
                if (!discovered[pid]) {
                    d.error = i18n("The check was stopped. Press the refresh button to check again.");
                }
            }
        }
        stopper.connectSource(Helpers.stopCommand(scriptPath));
        bump();
    }

    // Starts a check round. All checks of a round carry the same id, so that the branches of one
    // repository share a single fetch.
    function checkAll() {
        cycleCount++;
        cycle = "c" + Date.now().toString(36) + "-" + cycleCount;
        discoverAll();
        checkUnits();
    }

    // One check process per repository: a repository watched on several branches gets them all checked in
    // one process (see check.sh, PGW_MULTI), and its result updates the widget once. A process per branch
    // made the whole panel stall with many branches: starting the processes and handling every result on
    // its own (badge, tooltip, list) added up to a second or two.
    function checkUnits() {
        var seen = {};
        for (var i = 0; i < repoList.length; ++i) {
            var pid = repoList[i].parentId;
            if (seen[pid]) {
                continue;
            }
            seen[pid] = true;
            var units = parentUnits(pid);
            if (units.length > 1) {
                checkParent(units);
            } else {
                checkRepo(units[0]);
            }
        }
    }

    // Starts the check of a branch entry, or of several branch entries of one repository (units), with cmd.
    function startCheck(units, cmd) {
        for (var i = 0; i < units.length; ++i) {
            var s = st(units[i].id);
            if (s.cmd && s.cmd !== cmd) {
                var running = cmdMap[s.cmd];
                if (running !== undefined) {
                    var rest = running.filter(function(x) { return x !== units[i].id; });
                    if (rest.length > 0) {
                        cmdMap[s.cmd] = rest;
                    } else {
                        checker.disconnectSource(s.cmd);
                        delete cmdMap[s.cmd];
                    }
                }
            }
            s.checkState = "checking";
            s.started = Date.now();
            s.cmd = cmd;
        }
        cmdMap[cmd] = units.map(function(u) { return u.id; });
        bump();
        checker.connectSource(cmd);
    }

    function checkParent(units) {
        var r = units[0];
        for (var i = 0; i < units.length; ++i) {
            var s = st(units[i].id);
            if (s.checkState === "checking" && Date.now() - s.started < 150000) {
                return;
            }
        }
        startCheck(units, Helpers.checkCommand(scriptPath, {
            repo: r.path, branch: "", key: r.sshKey, tokenFile: r.tokenFile, limit: commitLimit, cycle: cycle, multi: true,
            branches: units.map(function(u) { return u.branch; }),
            progressId: Helpers.progressKey(r.parentId)
        }));
    }

    // ---------------------------------------------- branches for ALL / patterns

    function discoverAll() {
        for (var i = 0; i < parsedRepos.length; ++i) {
            var r = parsedRepos[i];
            if (r.enabled && Helpers.hasWildcard(r.branch)) {
                discoverRepo(r);
            }
        }
    }

    function discoverRepo(r) {
        var d = discoverState[r.id] || (discoverState[r.id] = { cmd: "", started: 0, error: "", locked: false, prompted: false });
        if (d.cmd && Date.now() - d.started < 150000) {
            return;
        }
        if (d.cmd) {
            finder.disconnectSource(d.cmd);
            delete discoverMap[d.cmd];
        }
        d.started = Date.now();
        d.cmd = Helpers.branchesCommand(scriptPath, { repo: r.path, key: r.sshKey, tokenFile: r.tokenFile, cycle: cycle });
        discoverMap[d.cmd] = r.id;
        finder.connectSource(d.cmd);
        bump();
    }

    function handleDiscovered(id, cmd, stdout, stderr, exitCode) {
        var d = discoverState[id];
        if (!d || d.cmd !== cmd) {
            return;
        }
        d.cmd = "";
        var res = Helpers.parseBranches(stdout, stderr, exitCode);
        d.locked = false;
        if (!res.ok) {
            d.error = res.msg;
            if (res.code === "locked") {
                d.locked = true;
                if (cfg.autoUnlock && !d.prompted) {
                    d.prompted = true;
                    Qt.callLater(function() { root.unlockRepo(id); });
                }
            }
            bump();
            return;
        }
        d.error = "";
        var names = res.branches.slice().sort();
        if (JSON.stringify(names) !== JSON.stringify(discovered[id] || null)) {
            var all = {};
            for (var k in discovered) {
                all[k] = discovered[k];
            }
            all[id] = names;
            discovered = all;
            cfg.branchCache = JSON.stringify(all);
            rebuildUnits();
            Qt.callLater(root.checkUnits);
        } else {
            bump();
        }
    }

    function checkRepo(r) {
        var s = st(r.id);
        if (s.checkState === "checking" && Date.now() - s.started < 150000) {
            return;
        }
        startCheck([r], Helpers.checkCommand(scriptPath, {
            repo: r.path, branch: r.branch, key: r.sshKey, tokenFile: r.tokenFile, limit: commitLimit, cycle: cycle,
            branches: parentUnits(r.parentId).map(function(u) { return u.branch; }).filter(function(b) { return b !== ""; }),
            progressId: Helpers.progressKey(r.parentId)
        }));
    }

    // The result of one check process: one branch entry, or several (each in its own part of the output).
    // Everything is applied first and the widget is updated once.
    function handleResults(ids, cmd, stdout, stderr, exitCode) {
        if (ids.length === 1 && String(cmd).indexOf("PGW_MULTI=1") < 0) {
            applyResult(ids[0], cmd, stdout, stderr, exitCode);
        } else {
            var parts = Helpers.splitBranchOutput(stdout);
            for (var i = 0; i < ids.length; ++i) {
                var u = repoById(ids[i]);
                var text = u ? parts[u.branch] : undefined;
                // No part of its own: the whole check failed (its message is before the first branch).
                applyResult(ids[i], cmd, text !== undefined ? text : (parts[""] || stdout), stderr, exitCode);
            }
        }
        bump();
    }

    function applyResult(id, cmd, stdout, stderr, exitCode) {
        var r = repoById(id);
        var s = st(id);
        if (!r || s.cmd !== cmd) {
            return;
        }
        s.cmd = "";
        s.lastCheck = Qt.formatTime(new Date(), Locale.ShortFormat);

        var res = Helpers.parseOutput(stdout, stderr, exitCode);
        s.locked = false;
        if (!res.ok) {
            s.error = res.msg;
            if (res.code === "locked") {
                s.checkState = "locked";
                s.locked = true;
                if (cfg.autoUnlock && !s.prompted) {
                    s.prompted = true;
                    Qt.callLater(function() { root.unlockRepo(id); });
                }
            } else {
                s.checkState = "error";
            }
            return;
        }
        s.checkState = "ok";
        s.error = "";
        s.commits = res.commits;
        s.tip = res.tip;
        s.webUrl = Helpers.webUrl(res.url);

        var sig = r.path + "|" + r.branch;
        var sv = saved[id];
        if (!sv || sv.sig !== sig || !sv.n) {
            // First run for this repository: remember the current tip, don't notify.
            saved[id] = { sig: sig, n: res.tip, a: res.tip };
            saveState();
        } else {
            var fresh = Helpers.commitsSince(s.commits, sv.n);
            if (fresh.list.length > 0) {
                sv.n = res.tip;
                saveState();
                if (r.multi) {
                    // Announced already by another watched branch of this repository (or merged from it).
                    fresh = {
                        list: fresh.list.filter(function(c) { return !root.seenOnSibling(r, c.hash); }),
                        overflow: fresh.overflow
                    };
                }
                if (fresh.list.length > 0) {
                    notifyNew(r, fresh);
                }
            }
        }
        updateUnread(id);
    }

    function updateUnread(id) {
        var s = st(id);
        var sv = saved[id];
        var r = Helpers.commitsSince(s.commits, sv ? sv.a : "");
        s.unread = r.list.length;
        s.overflow = r.overflow;
    }

    // which: "all", "p:<repository id>", the id of a branch entry, or a list of branch entry ids
    function markAllRead(which) {
        var ids = Array.isArray(which) ? which
            : which === "all" ? repoList.map(function(r) { return r.id; })
            : which.indexOf("p:") === 0 ? parentUnits(which.slice(2)).map(function(r) { return r.id; })
            : [which];
        var changed = false;
        for (var i = 0; i < ids.length; ++i) {
            var s = st(ids[i]);
            if (saved[ids[i]] && s.tip && saved[ids[i]].a !== s.tip) {
                saved[ids[i]].a = s.tip;
                changed = true;
            }
            updateUnread(ids[i]);
        }
        if (changed) {
            saveState();
        }
        bumpNow();
    }

    onExpandedChanged: {
        if (expanded) {
            for (var i = 0; i < repoList.length; ++i) {
                var s = st(repoList[i].id);
                s.highlight = s.unread;
            }
            if (cfg.markReadOnOpen) {
                markAllRead("all");
            } else {
                bumpNow();
            }
            if (searchOpen) {
                Qt.callLater(function() { root.searchFocusWanted(); });
            }
        } else {
            for (var j = 0; j < repoList.length; ++j) {
                st(repoList[j].id).highlight = 0;
            }
            // The search stays, also a running one in the whole history: its result is there when the
            // popup opens again.
            extraShown = 0;
            closeDiff();
            bumpNow();
        }
    }

    function openConfig() {
        var a = Plasmoid.internalAction("configure");
        if (a) {
            a.trigger();
        }
    }

    // ----------------------------------------------------------- SSH keys

    function unlockRepo(id) {
        var r = repoById(id) || parsedRepos.filter(function(x) { return x.id === id; })[0];
        if (!r || !r.sshKey || unlockingKeys[r.sshKey]) {
            return;
        }
        unlockingKeys[r.sshKey] = true;
        var cmd = Helpers.agentCommand(agentScriptPath, "unlock", {
            key: r.sshKey, lifetime: cfg.unlockHours * 3600
        });
        agentMap[cmd] = { id: id, action: "unlock", key: r.sshKey };
        agentSrc.connectSource(cmd);
    }

    function unlockAll() {
        for (var i = 0; i < repoList.length; ++i) {
            if (st(repoList[i].id).locked) {
                unlockRepo(repoList[i].id);
            }
        }
    }

    function handleAgentResult(info, stdout, stderr, exitCode) {
        delete unlockingKeys[info.key];
        var r = Helpers.parseAgent(stdout, stderr, exitCode);
        if (!r.ok) {
            var s = st(info.id);
            s.error = r.msg;
            s.checkState = "locked";
            s.locked = true;
            bump();
            return;
        }
        // Several repositories may share the key: re-check all of them.
        checkAll();
    }

    // -------------------------------------------------------------- diff

    function openDiff(c) {
        var r = repoById(c.repoId);
        if (!r) {
            return;
        }
        diffCommit = c;
        diffKey = c.repoId + ":" + c.hash;
        diffTruncated = false;
        if (diffCache[diffKey]) {
            diffLines = diffCache[diffKey].lines;
            diffTruncated = diffCache[diffKey].truncated;
            diffState = "ok";
            return;
        }
        diffLines = [];
        diffState = "loading";
        diffError = "";
        if (diffCmd) {
            differ.disconnectSource(diffCmd);
        }
        diffCmd = Helpers.diffCommand(diffScriptPath, { repo: r.path, hash: c.hash, key: r.sshKey, tokenFile: r.tokenFile });
        differ.connectSource(diffCmd);
    }

    function closeDiff() {
        if (diffCmd) {
            differ.disconnectSource(diffCmd);
            diffCmd = "";
        }
        diffCommit = null;
        diffLines = [];
        diffState = "idle";
    }

    function handleDiffResult(stdout, stderr, exitCode) {
        diffCmd = "";
        var res = Helpers.parseDiff(stdout, stderr, exitCode);
        if (!res.ok) {
            diffState = "error";
            diffError = res.msg;
            return;
        }
        if (Object.keys(diffCache).length > 30) {
            diffCache = ({});
        }
        diffCache[diffKey] = res;
        diffLines = res.lines;
        diffTruncated = res.truncated;
        diffState = "ok";
    }

    // "Open File": saves the file as it is in the shown commit to the widget's cache folder (the
    // repository itself is never touched) and opens that copy with the default application.
    function openFile(path) {
        var c = diffCommit;
        var r = c ? repoById(c.repoId) : null;
        if (!r || !path) {
            return;
        }
        var cmd = Helpers.openFileCommand(openFileScriptPath, { repo: r.path, hash: c.hash, path: path, key: r.sshKey, tokenFile: r.tokenFile });
        openMap[cmd] = true;
        flash(i18n("Opening %1…", path.replace(/^.*\//, "")), false);
        opener.connectSource(cmd);
    }

    function handleOpenResult(stdout, stderr, exitCode) {
        var res = Helpers.parseOpenFile(stdout, stderr, exitCode);
        if (!res.ok) {
            flash(res.msg, true);
            return;
        }
        Qt.openUrlExternally(Qt.resolvedUrl("file://" + res.file.split("/").map(encodeURIComponent).join("/")));
    }

    function openCommitWeb(c) {
        var u = Helpers.commitUrl(st(c.repoId).webUrl, c.hash);
        if (u) {
            Qt.openUrlExternally(u);
        }
    }

    // ----------------------------------------------------- notifications

    function fmt(c) {
        var s = "";
        if (cfg.showHash) {
            s += c.short + "  ";
        }
        if (cfg.showAuthor) {
            s += c.author + ": ";
        }
        return s + c.subject;
    }

    // target: {repoId, hash} - what a click on the notification shows (hash "" = the commit list)
    function send(title, body, target) {
        var clickable = !!target && cfg.notifyClick;
        var cmd = Helpers.notifyCommand({
            urgency: cfg.urgency,
            useDefaultTimeout: cfg.useDefaultTimeout,
            timeoutSec: cfg.timeoutSec,
            icon: Helpers.urlToPath(resolveIcon(cfg.notifyIcon, "notify", lightText)),
            clickable: clickable,
            actionLabel: target && target.hash ? i18n("Show changes") : i18n("Show commits")
        }, title, Helpers.esc(body));
        if (clickable) {
            notifyTargets[cmd] = target;
        }
        notifier.connectSource(cmd);
    }

    // A click on a notification: open the popup and show the commit (or the list of commits).
    function openFromNotification(t) {
        if (!t || !repoById(t.repoId)) {
            return;
        }
        var tu = repoById(t.repoId);
        if (effectiveIds().indexOf(tu.id) < 0) {
            setSelection(showRepoBar ? [tu.parentId] : [], tu.multi ? [tu.id] : []);
        } else {
            closeDiff();
        }
        expanded = true;
        if (!t.hash) {
            return;
        }
        var cs = st(t.repoId).commits;
        for (var i = 0; i < cs.length; ++i) {
            if (cs[i].hash === t.hash) {
                openDiff({
                    repoId: t.repoId, repoName: nameOf(t.repoId), hash: cs[i].hash, short: cs[i].short,
                    author: cs[i].author, subject: cs[i].subject, when: cs[i].when, ts: cs[i].ts, unread: false
                });
                return;
            }
        }
    }

    function notifyNew(r, fresh) {
        // Muted: no notification and no sound. The commit is still counted as unread, and it is
        // not announced afterwards when the mute is switched off.
        if (!cfg.notifyEnabled || cfg.muted) {
            return;
        }
        var list = fresh.list;                 // newest first
        var n = list.length;
        var max = Math.max(1, cfg.notifyMax);
        var count = fresh.overflow ? n + "+" : String(n);
        var name = Helpers.repoDisplayName(r);

        if (cfg.notifyMode === 1) {
            // One notification per commit, oldest first.
            var shown = list.slice(0, max).reverse();
            for (var i = 0; i < shown.length; ++i) {
                send(i18n("%1: new commit", name), fmt(shown[i]), { repoId: r.id, hash: shown[i].hash });
            }
            if (n > max) {
                send(name, i18n("…and %1 more commits", n - max), { repoId: r.id, hash: "" });
            }
        } else if (cfg.notifyMode === 2 || (n === 1 && !fresh.overflow)) {
            // Only the latest commit.
            var body = fmt(list[0]);
            if (n > 1) {
                body += "\n" + i18n("(+%1 more)", fresh.overflow ? (n - 1) + "+" : n - 1);
            }
            send(i18n("%1: new commit", name), body, { repoId: r.id, hash: list[0].hash });
        } else {
            // One summary.
            var lines = [];
            for (var j = 0; j < Math.min(n, max); ++j) {
                lines.push("• " + fmt(list[j]));
            }
            if (n > max) {
                lines.push(i18n("…and %1 more", n - max));
            }
            send(i18n("%1: %2 new commits", name, count), lines.join("\n"), { repoId: r.id, hash: "" });
        }

        if (cfg.playSound) {
            notifier.connectSource(Helpers.soundCommand(cfg.soundName));
        }
    }

    // The corner radius of buttons and windows in the system theme (Kirigami 6.2 and newer; 5 before).
    readonly property real cornerRadius: Kirigami.Units.cornerRadius ?? 5

    // A chip of the branch filter. A chosen chip has the highlight color and a check mark, so the choice
    // does not depend on color alone. Space or Enter works like a click.
    component FilterChip: Rectangle {
        id: chip
        property string label: ""
        property int count: 0                 // unread commits, shown as a small badge
        property bool selected: false
        property string iconName: ""
        property string dotColor: ""          // a dot in the color of the repository
        property bool removable: false        // shows a cross: a click takes the chip away
        signal clicked()

        readonly property real textPt: root.fontPt(Kirigami.Theme.defaultFont) * cfg.listTextScale / 100
        readonly property real glyph: Math.round(chipText.implicitHeight * 0.9)

        implicitHeight: Math.round(chipText.implicitHeight + Kirigami.Units.smallSpacing * 2)
        implicitWidth: Math.round(chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2)
        radius: root.cornerRadius
        color: selected ? Qt.alpha(Kirigami.Theme.highlightColor, chipMouse.containsMouse ? 0.5 : 0.35)
                        : (chipMouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.1) : "transparent")
        border.width: 1
        border.color: selected ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.3)

        activeFocusOnTab: true
        Keys.onSpacePressed: chip.clicked()
        Keys.onReturnPressed: chip.clicked()
        Keys.onEnterPressed: chip.clicked()
        Accessible.role: Accessible.CheckBox
        Accessible.name: (count > 0 ? label + " (" + count + ")" : label) + (removable ? " – " + i18n("remove") : "")
        Accessible.checkable: !removable
        Accessible.checked: selected
        Accessible.onPressAction: chip.clicked()

        Rectangle {
            // keyboard focus
            anchors.fill: parent
            anchors.margins: -2
            radius: root.cornerRadius + 2
            color: "transparent"
            border.width: 2
            border.color: Kirigami.Theme.focusColor
            visible: chip.activeFocus
        }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                visible: chip.selected && !chip.removable
                source: "checkmark"
                implicitWidth: chip.glyph
                implicitHeight: chip.glyph
            }
            Rectangle {
                visible: chip.dotColor !== ""
                implicitWidth: Math.round(chip.glyph * 0.6)
                implicitHeight: implicitWidth
                radius: width / 2
                color: chip.dotColor || "transparent"
            }
            Kirigami.Icon {
                visible: chip.iconName !== "" && (!chip.selected || chip.removable)
                source: chip.iconName
                implicitWidth: chip.glyph
                implicitHeight: chip.glyph
            }
            PlasmaComponents.Label {
                id: chipText
                text: chip.label
                font.pointSize: chip.textPt
                font.weight: chip.selected ? Font.DemiBold : Font.Normal
            }
            Rectangle {
                // unread commits
                visible: chip.count > 0
                implicitHeight: Math.round(chipText.implicitHeight * 0.85)
                implicitWidth: Math.max(implicitHeight, badgeText.implicitWidth + Kirigami.Units.smallSpacing * 2)
                radius: height / 2
                color: Kirigami.Theme.highlightColor
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: chip.count > 99 ? "99+" : String(chip.count)
                    color: Kirigami.Theme.highlightedTextColor
                    font.pointSize: chip.textPt * 0.8
                    font.bold: true
                }
            }
            Kirigami.Icon {
                visible: chip.removable
                source: "window-close"
                implicitWidth: Math.round(chip.glyph * 0.8)
                implicitHeight: implicitWidth
                opacity: chipMouse.containsMouse ? 1 : 0.6
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // A drop-down list (for the repositories and the branches), built like the list of Plasma's own combo
    // box: the theme's menu frame, and a height that comes straight from the content (up to maxHeight;
    // longer content scrolls). Plasma's Popup was not used: it counts the content height only when the
    // content reports a width, and with a scroll view inside it opened as a thin empty bar.
    component ListPopup: T.Popup {
        id: listPopup
        property real maxHeight: Kirigami.Units.gridUnit * 20

        implicitWidth: Kirigami.Units.gridUnit * 16
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        height: Math.min(implicitHeight, maxHeight)
        topMargin: 6
        bottomMargin: 6
        topPadding: background ? background.margins.top : undefined
        leftPadding: background ? background.margins.left : undefined
        rightPadding: background ? background.margins.right : undefined
        bottomPadding: background ? background.margins.bottom : undefined
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        background: Item {
            readonly property alias margins: popupSurface.margins
            implicitWidth: popupSurface.margins.left + popupSurface.margins.right
            implicitHeight: popupSurface.margins.top + popupSurface.margins.bottom

            KSvg.FrameSvgItem {
                anchors {
                    fill: parent
                    topMargin: -margins.top
                    leftMargin: -margins.left
                    rightMargin: -margins.right
                    bottomMargin: -margins.bottom
                }
                imagePath: "solid/widgets/tooltip"
                prefix: "shadow"
            }
            KSvg.FrameSvgItem {
                id: popupSurface
                anchors.fill: parent
                imagePath: "solid/widgets/tooltip"
            }
        }
    }

    // A row of the repository and branch lists: a check box, an optional color dot or icon, a name and
    // the number of unread commits. The whole row takes the click (the check box only shows the state), so the list
    // stays open and several rows can be ticked one after another.
    component CheckRow: Rectangle {
        id: checkRow
        property string label: ""
        property int count: 0
        property bool checked: false
        property bool partial: false          // some, not all (for the "All …" rows)
        property string dotColor: ""
        property string iconName: ""
        signal activated()

        implicitHeight: Math.round(Math.max(rowCheck.implicitHeight, rowText.implicitHeight) + Kirigami.Units.smallSpacing * 2)
        implicitWidth: rowContent.implicitWidth + Kirigami.Units.largeSpacing * 2
        radius: root.cornerRadius
        color: rowMouse.containsMouse ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25) : "transparent"

        activeFocusOnTab: true
        Keys.onSpacePressed: checkRow.activated()
        Keys.onReturnPressed: checkRow.activated()
        Keys.onEnterPressed: checkRow.activated()
        Accessible.role: Accessible.CheckBox
        Accessible.name: count > 0 ? label + " (" + count + ")" : label
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.checkStateMixed: partial
        Accessible.onPressAction: checkRow.activated()

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.CheckBox {
                id: rowCheck
                tristate: true
                checkState: checkRow.partial ? Qt.PartiallyChecked : (checkRow.checked ? Qt.Checked : Qt.Unchecked)
                focusPolicy: Qt.NoFocus
            }
            Rectangle {
                visible: checkRow.dotColor !== ""
                implicitWidth: Math.round(rowText.implicitHeight * 0.55)
                implicitHeight: implicitWidth
                radius: width / 2
                color: checkRow.dotColor || "transparent"
            }
            Kirigami.Icon {
                visible: checkRow.iconName !== ""
                source: checkRow.iconName
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
            PlasmaComponents.Label {
                id: rowText
                Layout.fillWidth: true
                text: checkRow.label
                elide: Text.ElideRight
                font.weight: checkRow.checked ? Font.DemiBold : Font.Normal
            }
            Rectangle {
                visible: checkRow.count > 0
                implicitHeight: Math.round(rowText.implicitHeight * 0.85)
                implicitWidth: Math.max(implicitHeight, rowBadge.implicitWidth + Kirigami.Units.smallSpacing * 2)
                radius: height / 2
                color: Kirigami.Theme.highlightColor
                Text {
                    id: rowBadge
                    anchors.centerIn: parent
                    text: checkRow.count > 99 ? "99+" : String(checkRow.count)
                    color: Kirigami.Theme.highlightedTextColor
                    font.pointSize: root.fontPt(Kirigami.Theme.smallFont)
                    font.bold: true
                }
            }
        }

        // Above the row content, so the check box never toggles itself.
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: checkRow.activated()
        }
    }

    // Transparent layer over a scroll area: Ctrl + mouse wheel changes the text size; a plain wheel
    // (and every click) goes on to the items below.
    component WheelZoom: MouseArea {
        signal zoom(real angleY)
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            if (wheel.modifiers & Qt.ControlModifier) {
                zoom(wheel.angleDelta.y);
                wheel.accepted = true;
            } else {
                wheel.accepted = false;
            }
        }
    }

    // ---------------------------------------------------- representations

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.checkAll();
            } else {
                root.expanded = !root.expanded;
            }
        }

        // Icon size: "Normal" (0) matches the other system tray icons, "Big" (1) fills the whole cell.
        Item {
            id: iconBox
            anchors.centerIn: parent
            width: root.cfg.iconSize === 1
                   ? Math.min(compact.width, compact.height)
                   : Math.min(Kirigami.Units.iconSizes.smallMedium, compact.width, compact.height)
            height: width

            Kirigami.Icon {
                anchors.fill: parent
                source: root.panelIcon
                active: compact.containsMouse
            }

            Rectangle {
                id: badge
                visible: root.cfg.showBadge && root.totalUnread > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(Kirigami.Units.iconSizes.small * 0.75, iconBox.height * 0.45)
                width: Math.max(height, badgeText.implicitWidth + 4)
                radius: height / 2
                color: Kirigami.Theme.highlightColor

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    font.pixelSize: Math.round(badge.height * 0.7)
                    font.bold: true
                    color: Kirigami.Theme.highlightedTextColor
                    text: (root.totalUnread > 99 ? "99+" : String(root.totalUnread)) + (root.anyOverflow && root.totalUnread <= 99 ? "+" : "")
                }
            }

            // A small blinking green dot while a check runs. With a bundled icon it sits inside the empty
            // bottom circle of the branch symbol (center 6,17 of the 22 x 22 drawing), where no badge or
            // dot of any icon state is: the corners hold the orange dot of "new", the red badge of "muted"
            // and the unread badge. With an icon chosen in the settings it sits in a corner: bottom right,
            // or top right when the unread badge is there. It blinks only when Plasma's animations are on,
            // otherwise it stays lit.
            Rectangle {
                id: checkingDot
                visible: root.anyChecking
                readonly property bool inCircle: root.panelIconBundled
                width: inCircle ? Math.max(3, iconBox.width * 3.4 / 22) : Math.max(5, Math.round(iconBox.width * 0.28))
                height: width
                radius: width / 2
                antialiasing: true
                x: inCircle ? iconBox.width * 6 / 22 - width / 2 : iconBox.width - width
                y: inCircle ? iconBox.height * 17 / 22 - height / 2 : (badge.visible ? 0 : iconBox.height - height)
                color: Kirigami.Theme.positiveTextColor
                border.width: inCircle ? 0 : 1
                border.color: Kirigami.Theme.backgroundColor

                SequentialAnimation on opacity {
                    running: checkingDot.visible && Kirigami.Units.longDuration > 0
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { from: 1; to: 0.25; duration: 550; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.25; to: 1; duration: 550; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        id: full

        // The popup remembers one size for the commit list and another for the diff view. The
        // size is the preferred size of this item; a resize by the user is saved after a short
        // pause, but not while the popup is opening or switching between the two views.
        readonly property bool inDiff: root.diffCommit !== null
        readonly property int unit: Kirigami.Units.gridUnit
        readonly property int wantedWidth: {
            var v = inDiff ? root.cfg.diffWidth : root.cfg.listWidth;
            return v > 0 ? v : unit * (inDiff ? 44 : 28);
        }
        readonly property int wantedHeight: {
            var v = inDiff ? root.cfg.diffHeight : root.cfg.listHeight;
            return v > 0 ? v : unit * (inDiff ? 32 : 22);
        }
        property bool settling: true

        Layout.minimumWidth: unit * 20
        Layout.minimumHeight: unit * 14
        Layout.preferredWidth: wantedWidth
        Layout.preferredHeight: wantedHeight
        collapseMarginsHint: true

        function settle() {
            settling = true;
            sizeSaveTimer.stop();
            settleTimer.restart();
        }

        onInDiffChanged: settle()
        Component.onCompleted: settle()
        Connections {
            target: root
            function onExpandedChanged() {
                full.settle();
            }
        }
        onWidthChanged: if (!settling) sizeSaveTimer.restart()
        onHeightChanged: if (!settling) sizeSaveTimer.restart()

        Timer {
            id: settleTimer
            interval: 800
            onTriggered: full.settling = false
        }
        Timer {
            id: sizeSaveTimer
            interval: 600
            onTriggered: {
                if (full.settling || !root.expanded || full.width < full.unit * 10 || full.height < full.unit * 8) {
                    return;
                }
                var w = Math.round(full.width);
                var h = Math.round(full.height);
                if (full.inDiff) {
                    if (root.cfg.diffWidth !== w) root.cfg.diffWidth = w;
                    if (root.cfg.diffHeight !== h) root.cfg.diffHeight = h;
                } else {
                    if (root.cfg.listWidth !== w) root.cfg.listWidth = w;
                    if (root.cfg.listHeight !== h) root.cfg.listHeight = h;
                }
            }
        }

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                // ---- diff mode
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit !== null
                    icon.name: "go-previous"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.closeDiff()
                    PlasmaComponents.ToolTip.text: i18n("Back to the list")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                Kirigami.Heading {
                    visible: root.diffCommit !== null
                    Layout.fillWidth: true
                    level: 4
                    elide: Text.ElideRight
                    text: root.diffCommit ? root.diffCommit.short + "  " + root.diffCommit.subject : ""
                }
                PlasmaComponents.Label {
                    visible: root.diffCommit !== null && root.flashNote !== ""
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                    elide: Text.ElideRight
                    color: root.flashError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                    text: root.flashNote
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit !== null
                    icon.name: "edit-copy"
                    text: i18n("Copy SHA")
                    display: PlasmaComponents.AbstractButton.TextBesideIcon
                    onClicked: root.copySha(root.diffCommit)
                    PlasmaComponents.ToolTip.text: root.diffCommit ? root.diffCommit.hash : ""
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit !== null && root.diffState === "ok"
                    icon.name: "edit-copy-path"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: {
                        if (diffText.selectedText !== "") {
                            diffText.copy();
                            root.flash(i18n("Selection copied"), false);
                        } else {
                            diffText.selectAll();
                            diffText.copy();
                            diffText.deselect();
                            root.flash(i18n("Diff copied"), false);
                        }
                    }
                    PlasmaComponents.ToolTip.text: i18n("Copy the selected text (or the whole diff if nothing is selected)")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit !== null && root.st(root.diffCommit.repoId).webUrl !== ""
                    icon.name: "internet-services"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.openCommitWeb(root.diffCommit)
                    PlasmaComponents.ToolTip.text: i18n("Open in the browser")
                    PlasmaComponents.ToolTip.visible: hovered
                }

                // ---- list mode
                Kirigami.Heading {
                    visible: root.diffCommit === null && !root.showRepoBar
                    Layout.fillWidth: true
                    level: 3
                    elide: Text.ElideRight
                    text: root.headerTitle
                }
                // Repository drop-down: its list has a check box for every repository, so several can be
                // chosen; it stays open until a click outside it or Escape.
                PlasmaComponents.ComboBox {
                    id: repoBox
                    visible: root.diffCommit === null && root.showRepoBar
                    Layout.fillWidth: true
                    model: []
                    displayText: root.repoSummary

                    popup: ListPopup {
                        y: repoBox.height
                        width: repoBox.width
                        maxHeight: Math.max(Kirigami.Units.gridUnit * 8, full.height - repoBox.height - Kirigami.Units.gridUnit)

                        contentItem: Flickable {
                            id: repoFlick
                            implicitHeight: repoRows.implicitHeight
                            contentHeight: repoRows.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            T.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

                            ColumnLayout {
                                id: repoRows
                                width: repoFlick.width
                                spacing: 0

                                CheckRow {
                                    Layout.fillWidth: true
                                    label: i18n("All repositories")
                                    count: root.totalUnread
                                    checked: { root.rev; return root.shownRepoIds().length === root.repoChips.length; }
                                    partial: { root.rev; var n = root.shownRepoIds().length; return n > 0 && n < root.repoChips.length; }
                                    onActivated: root.toggleRepo("")
                                }
                                Kirigami.Separator {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }
                                Repeater {
                                    model: root.repoChips
                                    delegate: CheckRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        label: modelData.text
                                        count: modelData.count
                                        dotColor: modelData.color
                                        checked: { root.rev; return root.selRepos.length === 0 || root.selRepos.indexOf(modelData.id) >= 0; }
                                        onActivated: root.toggleRepo(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
                PlasmaComponents.BusyIndicator {
                    visible: root.diffCommit === null && root.anyChecking
                    running: visible
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit === null && root.anyLocked
                    icon.name: "object-unlocked"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.unlockAll()
                    PlasmaComponents.ToolTip.text: i18n("Unlock SSH keys…")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    // Opens the search field above the list; a second click closes it and ends the search.
                    visible: root.diffCommit === null
                    icon.name: "search"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    enabled: root.displayCommits.length > 0 || root.searchOpen
                    // Not checkable: the search is also closed by Escape and by closing the popup, and a
                    // click on a checkable button would cut "checked" off from searchOpen.
                    checked: root.searchOpen
                    onClicked: root.searchOpen ? root.closeSearch() : root.openSearch()
                    PlasmaComponents.ToolTip.text: root.searchOpen ? i18n("Close the search")
                                                                   : i18n("Search by message, author or hash (Ctrl+F)")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    // "Check now", and while a check runs "Stop checking" (for a check that hangs).
                    visible: root.diffCommit === null
                    icon.name: root.anyChecking ? "process-stop" : "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    enabled: !root.unconfigured
                    onClicked: root.anyChecking ? root.stopChecks() : root.checkAll()
                    PlasmaComponents.ToolTip.text: root.anyChecking ? i18n("Stop checking") : i18n("Check now")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit === null
                    icon.name: "checkmark"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    enabled: root.totalUnread > 0
                    onClicked: root.markAllRead(root.effectiveIds())
                    PlasmaComponents.ToolTip.text: i18n("Mark all as read")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit === null
                    icon.name: root.cfg.muted ? "notifications-disabled" : "notifications"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    checkable: true
                    checked: root.cfg.muted
                    onToggled: root.cfg.muted = checked
                    PlasmaComponents.ToolTip.text: root.cfg.muted ? i18n("Notifications are muted. Click to unmute.")
                                                                  : i18n("Mute notifications")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit === null
                    icon.name: "configure"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.openConfig()
                    PlasmaComponents.ToolTip.text: i18n("Configure…")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "window-pin"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    checkable: true
                    checked: root.cfg.pin
                    onToggled: root.cfg.pin = checked
                    PlasmaComponents.ToolTip.text: i18n("Keep open")
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }

        // ------------------------------------------------------------ list pane
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: root.diffCommit === null

            Shortcut {
                sequences: [StandardKey.Find]
                enabled: root.expanded && root.displayCommits.length > 0
                onActivated: root.openSearch()
            }

            // The search field (see root.searchText). Escape closes it; the popup stays open.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                visible: root.searchOpen

                Kirigami.SearchField {
                    id: commitSearch
                    Layout.fillWidth: true
                    placeholderText: i18n("Search by message, author or hash…")
                    onTextChanged: root.searchText = text
                    // Enter: the same search in the whole history.
                    Keys.onReturnPressed: root.startDeepSearch()
                    Keys.onEnterPressed: root.startDeepSearch()
                    Keys.onEscapePressed: event => {
                        root.closeSearch();
                        event.accepted = true;
                    }
                    Connections {
                        target: root
                        function onSearchFocusWanted() {
                            commitSearch.forceActiveFocus();
                            commitSearch.selectAll();
                        }
                        function onSearchOpenChanged() {
                            if (!root.searchOpen && commitSearch.text !== "") {
                                commitSearch.text = "";
                            }
                        }
                        function onSearchCleared() {
                            commitSearch.text = "";
                            commitSearch.forceActiveFocus();
                        }
                    }
                }
                PlasmaComponents.Button {
                    // The search above looks through the downloaded commits; this one through all of them.
                    icon.name: "view-history"
                    text: i18n("All history")
                    enabled: root.searching && !root.deepRunning && !root.deepActive
                    onClicked: root.startDeepSearch()
                    PlasmaComponents.ToolTip.text: i18n("Search every commit of the shown branches, not only the downloaded ones (Enter).\nFor a repository watched by URL, the first search downloads the list of all its commits, which can take a minute.")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                PlasmaComponents.BusyIndicator {
                    visible: root.deepRunning
                    running: visible
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents.Label {
                    visible: root.searching
                    opacity: 0.7
                    text: root.deepRunning ? i18n("Searching all history…")
                        : root.deepActive ? (root.deepMore
                            ? i18n("%1+ in all history", root.matchedCommits.length)
                            : i18np("%1 in all history", "%1 in all history", root.matchedCommits.length))
                        : i18np("%1 commit", "%1 commits", root.matchedCommits.length)
                }
                PlasmaComponents.ToolButton {
                    // Opens the row below: the author and where to look. Closing it takes both away.
                    icon.name: "view-filter"
                    text: i18n("Advanced")
                    display: PlasmaComponents.AbstractButton.TextBesideIcon
                    checked: root.advancedOpen
                    onClicked: root.setAdvancedOpen(!root.advancedOpen)
                    PlasmaComponents.ToolTip.text: root.advancedOpen ? i18n("Close the advanced search")
                                                                     : i18n("Advanced search: choose an author and where to look")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // The advanced search: the author, where the words are looked for, and "Clear". "All history"
            // above (or Enter) searches with them too.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                visible: root.searchOpen && root.advancedOpen

                PlasmaComponents.ComboBox {
                    id: authorBox
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                    model: root.authorChoices
                    function sync() {
                        var i = root.searchAuthor === "" ? 0 : root.authorChoices.indexOf(root.searchAuthor);
                        currentIndex = Math.max(0, i);
                    }
                    onModelChanged: sync()
                    Component.onCompleted: sync()
                    onActivated: index => root.searchAuthor = index > 0 ? root.authorChoices[index] : ""
                    Connections {
                        target: root
                        function onSearchAuthorChanged() {
                            authorBox.sync();
                        }
                    }
                    PlasmaComponents.ToolTip.text: i18n("Show only the commits of one author. The list has the authors of the downloaded commits; for anyone else, type the name in the search field and choose \"In the author\".")
                    PlasmaComponents.ToolTip.visible: hovered && !popup.visible
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                PlasmaComponents.ComboBox {
                    id: fieldBox
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                    model: [i18n("Everywhere"), i18n("In the message"), i18n("In the author"), i18n("In the hash")]
                    function sync() {
                        currentIndex = root.searchField;
                    }
                    Component.onCompleted: sync()
                    onActivated: index => root.searchField = index
                    Connections {
                        target: root
                        function onSearchFieldChanged() {
                            fieldBox.sync();
                        }
                    }
                    PlasmaComponents.ToolTip.text: i18n("Where the typed words are looked for")
                    PlasmaComponents.ToolTip.visible: hovered && !popup.visible
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                PlasmaComponents.Button {
                    icon.name: "edit-clear-all"
                    text: i18n("Clear")
                    enabled: root.searchText !== "" || root.searchAuthor !== "" || root.searchField !== 0
                    onClicked: root.clearSearch()
                    PlasmaComponents.ToolTip.text: i18n("Empty the search field and take the author and the place back")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                Item {
                    Layout.fillWidth: true
                }
            }

            // What the search in the whole history could not do, or did not show.
            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.searchOpen && root.deepActive && (root.deepErrors.length > 0 || root.deepMore)
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                font.pointSize: root.fontPt(Kirigami.Theme.smallFont)
                color: root.deepErrors.length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                opacity: root.deepErrors.length > 0 ? 1 : 0.7
                text: {
                    var lines = root.deepErrors.slice();
                    if (root.deepMore) {
                        lines.push(i18n("There are more matching commits: the newest %1 of a repository are listed. Add a word to narrow the search.", root.deepMax));
                    }
                    return lines.join("\n");
                }
            }

            // With several branch rows, a line that folds them into itself and unfolds them again (remembered).
            // Folded, it says whether some branches are chosen.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.branchRowsFoldable
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.ToolButton {
                    icon.name: root.branchRowsFolded ? "arrow-right" : "arrow-down"
                    text: root.branchRowsFolded
                          ? i18np("Branches of %1 repository", "Branches of %1 repositories", root.branchGroups.length)
                          : i18n("Branches")
                    onClicked: root.cfg.branchRowsFolded = !root.cfg.branchRowsFolded
                    PlasmaComponents.ToolTip.text: root.branchRowsFolded ? i18n("Show the branch rows") : i18n("Hide the branch rows")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.branchRowsFolded
                    elide: Text.ElideRight
                    opacity: 0.7
                    text: "· " + root.branchFoldSummary
                }
            }

            // A row for every shown repository that is watched on several branches: a "Branches" button that
            // opens the list of its branches (with check boxes and a search field), and the chosen branches in
            // one line next to it (a click on one takes it away). With no branch chosen, all are shown.
            Repeater {
                model: root.branchGroups
                delegate: RowLayout {
                    id: branchRow
                    required property var modelData
                    visible: !root.branchRowsFolded
                    readonly property var groupData: modelData
                    // The ids of the branches that are shown, and the branches to put in the line.
                    readonly property var shownIds: { root.rev; root.selBranches; return root.shownUnits(groupData.id).map(function(u) { return u.id; }); }
                    readonly property bool allShown: shownIds.length === groupData.branches.length
                    readonly property var chosen: allShown ? [] : groupData.branches.filter(function(b) { return shownIds.indexOf(b.id) >= 0; })
                    readonly property var shownInList: {
                        var f = branchFilter.text.trim().toLowerCase();
                        return f === "" ? groupData.branches
                                        : groupData.branches.filter(function(b) { return b.text.toLowerCase().indexOf(f) >= 0; });
                    }
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // The name of the repository, whenever the list shows more than one repository, so that
                    // it is clear whose branches these are.
                    readonly property bool named: root.viewRepoCount > 1 || root.branchGroups.length > 1
                    PlasmaComponents.Label {
                        visible: branchRow.named
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 10
                        elide: Text.ElideRight
                        font.bold: true
                        font.pointSize: root.fontPt(Kirigami.Theme.defaultFont) * cfg.listTextScale / 100
                        color: branchRow.groupData.color || Kirigami.Theme.textColor
                        text: branchRow.groupData.name
                    }

                    PlasmaComponents.ToolButton {
                        id: branchButton
                        icon.name: "vcs-branch"
                        text: i18n("Branches")
                        down: branchPopup.visible
                        onClicked: branchPopup.visible ? branchPopup.close() : branchPopup.open()
                        PlasmaComponents.ToolTip.text: i18np("Choose the branches of %2 to show (%1 branch)", "Choose the branches of %2 to show (%1 branches)", branchRow.groupData.branches.length, branchRow.groupData.name)
                        PlasmaComponents.ToolTip.visible: hovered && !branchPopup.visible
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

                        ListPopup {
                            id: branchPopup
                            y: branchButton.height
                            width: Math.min(Kirigami.Units.gridUnit * 18, full.width - Kirigami.Units.gridUnit)
                            maxHeight: Math.max(Kirigami.Units.gridUnit * 8, full.height * 0.7)
                            onOpened: {
                                if (branchFilter.visible) {
                                    branchFilter.forceActiveFocus();
                                }
                            }
                            onClosed: branchFilter.text = ""

                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.SearchField {
                                    id: branchFilter
                                    visible: branchRow.groupData.branches.length > 8
                                    Layout.fillWidth: true
                                }

                                Flickable {
                                    id: branchFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitHeight: branchRows.implicitHeight
                                    contentHeight: branchRows.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    T.ScrollBar.vertical: PlasmaComponents.ScrollBar {}

                                    ColumnLayout {
                                        id: branchRows
                                        width: branchFlick.width
                                        spacing: 0

                                        CheckRow {
                                            Layout.fillWidth: true
                                            visible: branchFilter.text.trim() === ""
                                            label: branchRow.named ? i18n("All branches of %1", branchRow.groupData.name) : i18n("All branches")
                                            count: { root.rev; return root.sumUnread(branchRow.groupData.id); }
                                            checked: branchRow.allShown
                                            partial: !branchRow.allShown && branchRow.shownIds.length > 0
                                            onActivated: root.toggleBranch(branchRow.groupData.id, "")
                                        }
                                        Kirigami.Separator {
                                            visible: branchFilter.text.trim() === ""
                                            Layout.fillWidth: true
                                            Layout.topMargin: Kirigami.Units.smallSpacing
                                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                                        }
                                        Repeater {
                                            model: branchRow.shownInList
                                            delegate: CheckRow {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                label: modelData.text
                                                iconName: "vcs-branch"
                                                count: { root.rev; return root.st(modelData.id).unread; }
                                                checked: branchRow.shownIds.indexOf(modelData.id) >= 0
                                                onActivated: root.toggleBranch(branchRow.groupData.id, modelData.id)
                                            }
                                        }
                                        PlasmaComponents.Label {
                                            visible: branchRow.shownInList.length === 0
                                            Layout.fillWidth: true
                                            Layout.margins: Kirigami.Units.smallSpacing
                                            opacity: 0.7
                                            text: i18n("No branch matches.")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The chosen branches, in one line; it scrolls sideways when they do not fit.
                    Flickable {
                        id: chosenView
                        Layout.fillWidth: true
                        Layout.preferredHeight: chosenRow.implicitHeight
                        contentWidth: chosenRow.implicitWidth
                        contentHeight: chosenRow.implicitHeight
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        // A plain mouse wheel scrolls the line sideways.
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse
                            onWheel: event => {
                                var max = Math.max(0, chosenView.contentWidth - chosenView.width);
                                chosenView.contentX = Math.max(0, Math.min(max, chosenView.contentX - event.angleDelta.y));
                            }
                        }

                        Row {
                            id: chosenRow
                            spacing: Kirigami.Units.smallSpacing

                            FilterChip {
                                visible: branchRow.allShown
                                label: i18n("All branches")
                                count: { root.rev; return root.sumUnread(branchRow.groupData.id); }
                                selected: true
                                onClicked: branchPopup.open()
                            }
                            FilterChip {
                                visible: branchRow.shownIds.length === 0
                                label: i18n("No branch chosen")
                                onClicked: branchPopup.open()
                            }
                            Repeater {
                                model: branchRow.chosen
                                delegate: FilterChip {
                                    required property var modelData
                                    label: modelData.text
                                    iconName: "vcs-branch"
                                    count: { root.rev; return root.st(modelData.id).unread; }
                                    selected: true
                                    removable: true
                                    onClicked: root.toggleBranch(branchRow.groupData.id, modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                // a little space between the chips and the list
                visible: root.showBranchBar
                implicitHeight: Kirigami.Units.smallSpacing
            }

            Repeater {
                model: root.problems
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: modelData.locked ? "object-locked" : "dialog-warning"
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: Kirigami.Theme.neutralTextColor
                        text: modelData.name + ": " + modelData.msg
                    }
                    PlasmaComponents.Button {
                        visible: modelData.locked
                        icon.name: "object-unlocked"
                        text: i18n("Unlock…")
                        onClicked: root.unlockRepo(modelData.id)
                    }
                }
            }

            // The line between the choice of branches (and the problems) and the commit list, so that the
            // first commit does not seem to belong to the rows above it.
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.showBranchBar || root.problems.length > 0
            }

            // The ScrollView sits in a plain Item with a transparent overlay: Plasma's ScrollView handles
            // the mouse wheel itself, so Ctrl + wheel (text size) has to be caught above it.
            Item {
                id: listPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.matchedCommits.length > 0

                // One click timer and one context menu for the whole list, not one per row: the rows
                // stay light, and a click is not lost when the list is rebuilt before the timer fires.
                property var clickCommit: null
                property var menuCommit: null
                property double lastDouble: 0

                // A single click shows the diff, a double click opens the web page. The diff view
                // replaces the list, so it waits until the double-click time has passed.
                Timer {
                    id: clickTimer
                    interval: ((Qt.styleHints && Qt.styleHints.mouseDoubleClickInterval) || 400) + 30
                    onTriggered: {
                        if (listPane.clickCommit) {
                            root.openDiff(listPane.clickCommit);
                        }
                    }
                }

                PlasmaComponents.Menu {
                    id: rowMenu
                    PlasmaComponents.MenuItem {
                        text: i18n("Show the changes")
                        icon.name: "vcs-diff"
                        onTriggered: root.openDiff(listPane.menuCommit)
                    }
                    PlasmaComponents.MenuItem {
                        text: i18n("Copy SHA")
                        icon.name: "edit-copy"
                        onTriggered: root.copySha(listPane.menuCommit)
                    }
                    PlasmaComponents.MenuItem {
                        text: i18n("Open in the browser")
                        icon.name: "internet-services"
                        enabled: listPane.menuCommit !== null && root.st(listPane.menuCommit.repoId).webUrl !== ""
                        onTriggered: root.openCommitWeb(listPane.menuCommit)
                    }
                }

                PlasmaComponents.ScrollView {
                    anchors.fill: parent

                    ListView {
                        id: commitList
                        model: root.listCommits
                        clip: true
                        // Rows that scroll out of view are used again for the ones that scroll in,
                        // instead of being destroyed and created anew.
                        reuseItems: true

                        // Shows `count` more commits (0 = all the rest). The list is rebuilt for that,
                        // so the row at the top is put back where it was.
                        function showMore(count) {
                            var top = indexAt(width / 2, contentY + 1);
                            var item = top >= 0 ? itemAtIndex(top) : null;
                            var offset = item ? contentY - item.y : 0;
                            root.extraShown += count > 0 ? count : root.hiddenCount;
                            if (top >= 0) {
                                positionViewAtIndex(top, ListView.Beginning);
                                contentY += offset;
                            }
                        }

                        footer: ColumnLayout {
                            width: ListView.view ? ListView.view.width : 0
                            // No height at all when every commit is shown.
                            height: root.hiddenCount > 0 ? implicitHeight : 0
                            visible: root.hiddenCount > 0
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                opacity: 0.7
                                font.pointSize: root.fontPt(Kirigami.Theme.smallFont) * cfg.listTextScale / 100
                                text: i18n("Showing %1 of %2 commits", root.listCommits.length, root.matchedCommits.length)
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.bottomMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Button {
                                    readonly property int step: Math.min(root.hiddenCount, Math.max(1, cfg.listPageSize))
                                    icon.name: "arrow-down"
                                    text: i18np("Show %1 more", "Show %1 more", step)
                                    onClicked: commitList.showMore(step)
                                }
                                PlasmaComponents.Button {
                                    visible: root.hiddenCount > Math.max(1, cfg.listPageSize)
                                    text: i18n("Show all")
                                    onClicked: commitList.showMore(0)
                                }
                            }
                        }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            height: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                            color: rowMouse.containsMouse ? Qt.alpha(Kirigami.Theme.highlightColor, 0.15) : "transparent"

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        clickTimer.stop();
                                        listPane.menuCommit = row.modelData;
                                        rowMenu.popup();
                                    } else if (Date.now() - listPane.lastDouble > 600) {
                                        listPane.clickCommit = row.modelData;
                                        clickTimer.restart();
                                    }
                                }
                                onDoubleClicked: {
                                    clickTimer.stop();
                                    listPane.lastDouble = Date.now();
                                    root.openCommitWeb(row.modelData);
                                }
                            }

                            PlasmaComponents.ToolTip.text: i18n("Click: show the changes\nDouble-click: open in the browser\nRight-click: more actions")
                            PlasmaComponents.ToolTip.visible: rowMouse.containsMouse
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

                            RowLayout {
                                id: rowLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    implicitWidth: Kirigami.Units.smallSpacing * 2
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: Kirigami.Theme.highlightColor
                                    opacity: row.modelData.unread ? 1 : 0
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        text: Helpers.subjectHtml(row.modelData.subject, root.rowColors.author)
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        font.pointSize: root.fontPt(Kirigami.Theme.defaultFont) * cfg.listTextScale / 100
                                        font.weight: row.modelData.unread ? Font.Bold : Font.Normal
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        textFormat: Text.StyledText
                                        font.family: Kirigami.Theme.smallFont.family
                                        font.pointSize: root.fontPt(Kirigami.Theme.smallFont) * cfg.listTextScale / 100
                                        text: Helpers.metaHtml(row.modelData,
                                                               root.rowPrefix(row.modelData),
                                                               root.rowColors)
                                    }
                                }
                            }
                        }
                    }
                }

                WheelZoom { onZoom: angleY => root.wheelScale(false, angleY) }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.matchedCommits.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.PlaceholderMessage {
                        Layout.fillWidth: true
                        icon.name: root.displayCommits.length > 0 ? "search"
                            : (!root.unconfigured && root.problems.length > 0) ? "dialog-warning" : "folder-git"
                        explanation: root.displayCommits.length === 0 && root.anyChecking && root.activeProgress
                            ? i18n("The first check downloads the recent history of the repository; later checks only download what is new.")
                            : (root.displayCommits.length > 0 && !root.deepActive && !root.deepRunning)
                                ? i18n("Only the downloaded commits were searched. Press Enter or \"All history\" to search all commits of the shown branches.")
                                : ""
                        text: {
                            if (root.displayCommits.length > 0) {
                                // Only the search can empty a list that has commits.
                                if (root.deepRunning) {
                                    return i18n("Searching all history…");
                                }
                                return root.deepActive
                                    ? i18n("No commit in the whole history matches %1", root.searchSummary)
                                    : i18n("No downloaded commit matches %1", root.searchSummary);
                            }
                            if (root.unconfigured) {
                                return i18n("No repository configured");
                            }
                            if (root.waitingForBranches) {
                                return root.problems.length > 0 ? i18n("Nothing to show yet") : i18n("Looking for branches…");
                            }
                            if (root.anyChecking) {
                                return root.activeProgress ? i18n("Downloading %1…", root.activeProgress.name) : i18n("Checking…");
                            }
                            if (root.problems.length > 0) {
                                return i18n("Nothing to show yet");
                            }
                            if (root.viewUnitCount === 0) {
                                return i18n("Nothing chosen: tick a repository or a branch in the lists above");
                            }
                            return i18n("No commits found");
                        }
                        helpfulAction: root.unconfigured ? configureAction : null
                    }
                    Kirigami.Action {
                        id: configureAction
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onTriggered: root.openConfig()
                    }

                    // The download of the first check (or of a check that brings many new commits).
                    PlasmaComponents.ProgressBar {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(parent.width, Kirigami.Units.gridUnit * 16)
                        visible: root.displayCommits.length === 0 && root.anyChecking && root.activeProgress !== null
                        from: 0
                        to: 100
                        indeterminate: root.progressValue(root.activeProgress) < 0
                        value: Math.max(0, root.progressValue(root.activeProgress))
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: root.displayCommits.length === 0 && root.anyChecking && root.activeProgress !== null
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        text: root.progressText(root.activeProgress)
                    }
                }
            }
        }

        // ------------------------------------------------------------ diff pane
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: root.diffCommit !== null

            PlasmaComponents.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.gridUnit * 2
                visible: root.diffState === "loading"
                running: visible
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.diffState === "error"

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    icon.name: "dialog-error"
                    text: i18n("Could not load the changes")
                    explanation: root.diffError
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.diffState === "ok"

                PlasmaComponents.ScrollView {
                    anchors.fill: parent

                    // Read-only rich text: colored like a diff view, and the text can be selected and copied
                    // (mouse selection, Ctrl+C, Ctrl+A, or the right-click menu).
                    PlasmaComponents.TextArea {
                        id: diffText
                        readOnly: true
                        selectByMouse: true
                        persistentSelection: true
                        textFormat: TextEdit.RichText
                        wrapMode: TextEdit.WrapAnywhere
                        background: null
                        padding: 0
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.smallSpacing
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        font.pointSize: (Kirigami.Theme.fixedWidthFont.pointSize > 0
                                         ? Kirigami.Theme.fixedWidthFont.pointSize
                                         : Kirigami.Theme.defaultFont.pointSize) * cfg.diffTextScale / 100
                        text: root.diffHtml

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: diffMenu.popup()
                        }

                        // One "Open File" button at the right end of each changed file's header line.
                        // The lines are placed with positionToRectangle(), so the buttons scroll with the text.
                        Repeater {
                            model: root.diffMarks

                            delegate: MouseArea {
                                id: openBtn
                                required property var modelData

                                // The offsets belong to the text of the diff that is shown. While the text is being
                                // replaced the buttons still have the offsets of the previous diff, and a position
                                // beyond the end of the text makes Qt print "QTextCursor::setPosition: Position
                                // '...' out of range". So ask only for positions inside the text. The length is
                                // read, not the text: for rich text Qt builds the whole HTML again on every read.
                                readonly property rect lineRect: {
                                    diffText.width;
                                    diffText.contentHeight;
                                    var len = diffText.length;
                                    return openBtn.modelData.off <= len
                                        ? diffText.positionToRectangle(openBtn.modelData.off)
                                        : Qt.rect(0, 0, 0, 0);
                                }

                                visible: lineRect.height > 0
                                x: diffText.width - width
                                y: lineRect.y
                                width: root.openButtonWidth
                                height: lineRect.height
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openFile(openBtn.modelData.path)

                                PlasmaComponents.ToolTip.text: i18n("Open this file as it is in this commit (a read-only copy)")
                                PlasmaComponents.ToolTip.visible: containsMouse
                                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

                                Rectangle {
                                    anchors.fill: parent
                                    color: root.mix(Kirigami.Theme.textColor, openBtn.containsMouse ? 0.24 : 0.10)
                                }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: "document-open"
                                        width: Math.round(openBtn.height * 0.85)
                                        height: width
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: diffText.font.family
                                        font.pointSize: diffText.font.pointSize
                                        font.bold: true
                                        color: Kirigami.Theme.linkColor
                                        text: i18n("Open File")
                                    }
                                }
                            }
                        }

                        PlasmaComponents.Menu {
                            id: diffMenu
                            PlasmaComponents.MenuItem {
                                text: i18n("Copy")
                                icon.name: "edit-copy"
                                enabled: diffText.selectedText !== ""
                                onTriggered: diffText.copy()
                            }
                            PlasmaComponents.MenuItem {
                                text: i18n("Select all")
                                icon.name: "edit-select-all"
                                onTriggered: diffText.selectAll()
                            }
                        }
                    }
                }

                WheelZoom { onZoom: angleY => root.wheelScale(true, angleY) }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                visible: root.diffState === "ok" && root.diffTruncated
                wrapMode: Text.Wrap
                opacity: 0.7
                text: i18n("The diff is long: only the first 4000 lines are shown. Double-click the commit in the list to see all of it in the browser.")
            }
        }

        footer: PlasmaExtras.PlasmoidHeading {
            position: PlasmaExtras.PlasmoidHeading.Footer
            visible: root.diffCommit !== null || !root.unconfigured

            RowLayout {
                id: footerRow
                anchors.fill: parent

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.7
                    text: {
                        root.rev;
                        if (root.diffCommit !== null) {
                            return i18n("Ctrl + mouse wheel: change the text size");
                        }
                        if (root.anyChecking && root.activeProgress) {
                            return root.activeProgress.name + ": " + root.progressText(root.activeProgress);
                        }
                        var ids = root.effectiveIds();
                        if (ids.length > 1) {
                            // ids are branch entries: count repositories and branches separately
                            var parents = {};
                            var nParents = 0;
                            for (var i = 0; i < ids.length; ++i) {
                                var u = root.repoById(ids[i]);
                                if (u && !parents[u.parentId]) {
                                    parents[u.parentId] = true;
                                    ++nParents;
                                }
                            }
                            if (nParents <= 1) {
                                return i18np("Watching %1 branch", "Watching %1 branches", ids.length);
                            }
                            var base = i18np("Watching %1 repository", "Watching %1 repositories", nParents);
                            return ids.length > nParents ? i18n("%1 (%2 branches)", base, ids.length) : base;
                        }
                        var s = root.st(ids[0]);
                        if (s.locked) {
                            return i18n("SSH key is locked");
                        }
                        if (s.checkState === "error") {
                            return i18n("Last attempt: %1", s.lastCheck);
                        }
                        return s.lastCheck ? i18n("Last checked: %1", s.lastCheck) : "";
                    }
                }
                PlasmaComponents.Label {
                    // The hint of the list: hidden when the popup is too narrow for it.
                    visible: root.diffCommit === null && footerRow.width > Kirigami.Units.gridUnit * 26
                    opacity: 0.7
                    text: i18n("Ctrl + wheel: text size")
                }
                PlasmaComponents.ToolButton {
                    // Shows the current text size (when it is not 100 %); a click resets it.
                    readonly property int textScale: root.diffCommit !== null ? cfg.diffTextScale : cfg.listTextScale
                    visible: textScale !== 100
                    icon.name: "zoom-original"
                    text: textScale + " %"
                    onClicked: root.resetScale(root.diffCommit !== null)
                    PlasmaComponents.ToolTip.text: i18n("Reset the text size to 100 %")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: {
                        root.rev;
                        if (root.diffCommit !== null) {
                            return false;
                        }
                        var ids = root.effectiveIds();
                        return ids.length === 1 && root.st(ids[0]).webUrl !== "";
                    }
                    icon.name: "internet-services"
                    text: i18n("Open repository")
                    onClicked: Qt.openUrlExternally(root.st(root.effectiveIds()[0]).webUrl)
                }
            }
        }
    }
}

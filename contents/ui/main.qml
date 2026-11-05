import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "../code/helpers.js" as Helpers

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    readonly property string scriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/check.sh"))
    readonly property string agentScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/agent.sh"))
    readonly property string diffScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/diff.sh"))
    readonly property string openFileScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/openfile.sh"))

    // ------------------------------------------------------------------ data
    property var repoList: []            // enabled repositories: {id, name, path, branch, sshKey, tokenFile, enabled}
    property var states: ({})            // id -> runtime state (see st())
    property var saved: ({})             // id -> {sig, n: last notified tip, a: last acknowledged tip}
    property var cmdMap: ({})            // running check command -> repo id
    property var agentMap: ({})          // running agent command -> {id, action, key}
    property var unlockingKeys: ({})     // key path -> true while a passphrase dialog is open
    property int rev: 0                  // bumped after every change of the data above

    property string currentTab: "all"    // repo id or "all"
    property var displayCommits: []
    property var problems: []
    property var tabModel: []
    property string tabSig: ""

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

    readonly property bool unconfigured: repoList.length === 0
    readonly property int totalUnread: { root.rev; return sumUnread(); }
    readonly property bool anyOverflow: { root.rev; return anyState("overflow"); }
    readonly property bool anyChecking: { root.rev; return anyState("checking"); }
    readonly property bool anyLocked: { root.rev; return anyState("locked"); }
    readonly property bool showAllTab: repoList.length > 1
    readonly property int tabIndex: {
        var t = root.tabModel;
        for (var i = 0; i < t.length; ++i) {
            if (t[i].id === root.currentTab) {
                return i;
            }
        }
        return 0;
    }
    readonly property string headerTitle: repoList.length === 1 ? Helpers.repoDisplayName(repoList[0]) : i18n("Git Commit Watcher")

    // Re-read the repository list whenever the setting changes (e.g. after "Apply").
    readonly property string reposJson: cfg.repos
    onReposJsonChanged: reloadRepos()

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
    readonly property int openButtonWidth: Kirigami.Units.gridUnit * 7
    readonly property var rowColors: ({
        hash: Kirigami.Theme.neutralTextColor.toString(),
        author: Kirigami.Theme.linkColor.toString(),
        muted: mix(Kirigami.Theme.textColor, 0.6)
    })
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

    Plasmoid.icon: panelIcon
    Plasmoid.status: (cfg.hideWhenRead && totalUnread === 0)
                     ? PlasmaCore.Types.PassiveStatus
                     : PlasmaCore.Types.ActiveStatus

    // With "pin" on, the popup stays open when another window gets the focus.
    hideOnWindowDeactivate: !cfg.pin

    toolTipMainText: repoList.length === 1 ? headerTitle : i18n("Git Commit Watcher")
    toolTipSubText: {
        root.rev;
        var t = buildTooltip();
        return cfg.muted ? i18n("Notifications are muted") + (t !== "" ? "\n" + t : "") : t;
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Check now")
            icon.name: "view-refresh"
            onTriggered: root.checkAll()
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
            var id = root.cmdMap[sourceName];
            if (id !== undefined) {
                delete root.cmdMap[sourceName];
                root.handleResult(id, sourceName, data["stdout"], data["stderr"], data["exit code"]);
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

    function sumUnread() {
        var n = 0;
        for (var i = 0; i < repoList.length; ++i) {
            n += st(repoList[i].id).unread;
        }
        return n;
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

    function bump() {
        rev++;
        buildDisplay();
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

    function reloadRepos() {
        migrateLegacy();
        var all = Helpers.parseRepos(cfg.repos, false);
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
                if (old.cmd) {
                    checker.disconnectSource(old.cmd);
                    delete cmdMap[old.cmd];
                }
                delete states[id];
            }
        }
        repoList = list;
        if (currentTab !== "all" && !keep[currentTab]) {
            currentTab = "all";
        }
        for (var j = 0; j < list.length; ++j) {
            updateUnread(list[j].id);
        }
        bump();
        Qt.callLater(root.checkAll);
    }

    function buildTooltip() {
        if (repoList.length === 0) {
            return i18n("No repository configured");
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

    function effectiveIds() {
        var ids = [];
        if (repoList.length > 1 && currentTab !== "all") {
            ids.push(currentTab);
        } else {
            for (var i = 0; i < repoList.length; ++i) {
                ids.push(repoList[i].id);
            }
        }
        return ids;
    }

    function buildDisplay() {
        var ids = effectiveIds();
        var out = [];
        var probs = [];
        for (var k = 0; k < ids.length; ++k) {
            var id = ids[k];
            var s = st(id);
            var hl = Math.max(s.unread, s.highlight);
            for (var i = 0; i < s.commits.length; ++i) {
                var c = s.commits[i];
                out.push({
                    repoId: id, repoName: nameOf(id), hash: c.hash, short: c.short, author: c.author,
                    subject: c.subject, when: c.when, ts: c.ts, unread: i < hl
                });
            }
            if (s.locked || s.checkState === "error") {
                probs.push({ id: id, name: nameOf(id), msg: s.error, locked: s.locked });
            }
        }
        if (ids.length > 1) {
            out.sort(function(a, b) { return b.ts - a.ts; });
        }
        displayCommits = out;
        problems = probs;

        // Repository selector entries; only replaced when something changed, so an open
        // drop-down is not reset by every refresh.
        var tabs = [];
        if (repoList.length > 1) {
            tabs.push({ id: "all", text: totalUnread > 0 ? i18n("All repositories (%1)", totalUnread) : i18n("All repositories") });
            for (var j = 0; j < repoList.length; ++j) {
                var u = st(repoList[j].id).unread;
                var nm = Helpers.repoDisplayName(repoList[j]);
                tabs.push({ id: repoList[j].id, text: u > 0 ? nm + " (" + u + ")" : nm });
            }
        }
        var sig = JSON.stringify(tabs);
        if (sig !== tabSig) {
            tabSig = sig;
            tabModel = tabs;
        }
    }

    // ------------------------------------------------------------- checks

    function checkAll() {
        for (var i = 0; i < repoList.length; ++i) {
            checkRepo(repoList[i]);
        }
    }

    function checkRepo(r) {
        var s = st(r.id);
        if (s.checkState === "checking" && Date.now() - s.started < 150000) {
            return;
        }
        if (s.cmd) {
            checker.disconnectSource(s.cmd);
            delete cmdMap[s.cmd];
        }
        s.checkState = "checking";
        s.started = Date.now();
        s.cmd = Helpers.checkCommand(scriptPath, {
            repo: r.path, branch: r.branch, key: r.sshKey, tokenFile: r.tokenFile, limit: 50
        });
        cmdMap[s.cmd] = r.id;
        bump();
        checker.connectSource(s.cmd);
    }

    function handleResult(id, cmd, stdout, stderr, exitCode) {
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
            bump();
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
                notifyNew(r, fresh);
            }
        }
        updateUnread(id);
        bump();
    }

    function updateUnread(id) {
        var s = st(id);
        var sv = saved[id];
        var r = Helpers.commitsSince(s.commits, sv ? sv.a : "");
        s.unread = r.list.length;
        s.overflow = r.overflow;
    }

    // which: a repo id, or "all"
    function markAllRead(which) {
        var ids = which === "all" ? repoList.map(function(r) { return r.id; }) : [which];
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
        bump();
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
                bump();
            }
        } else {
            for (var j = 0; j < repoList.length; ++j) {
                st(repoList[j].id).highlight = 0;
            }
            closeDiff();
            bump();
        }
    }

    onCurrentTabChanged: {
        closeDiff();
        buildDisplay();
    }

    function openConfig() {
        var a = Plasmoid.internalAction("configure");
        if (a) {
            a.trigger();
        }
    }

    // ----------------------------------------------------------- SSH keys

    function unlockRepo(id) {
        var r = repoById(id);
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
        diffCmd = Helpers.diffCommand(diffScriptPath, { repo: r.path, branch: r.branch, hash: c.hash });
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
        var cmd = Helpers.openFileCommand(openFileScriptPath, { repo: r.path, branch: r.branch, hash: c.hash, path: path });
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
        currentTab = showAllTab ? t.repoId : "all";     // also closes an open diff
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
                    visible: root.diffCommit === null && !root.showAllTab
                    Layout.fillWidth: true
                    level: 3
                    elide: Text.ElideRight
                    text: root.headerTitle
                }
                PlasmaComponents.ComboBox {
                    visible: root.diffCommit === null && root.showAllTab
                    Layout.fillWidth: true
                    model: root.tabModel
                    textRole: "text"
                    currentIndex: root.tabIndex
                    onActivated: index => root.currentTab = root.tabModel[index].id
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
                    visible: root.diffCommit === null
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    enabled: !root.unconfigured && !root.anyChecking
                    onClicked: root.checkAll()
                    PlasmaComponents.ToolTip.text: i18n("Check now")
                    PlasmaComponents.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    visible: root.diffCommit === null
                    icon.name: "checkmark"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    enabled: root.totalUnread > 0
                    onClicked: root.markAllRead(root.showAllTab ? root.currentTab : "all")
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

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.displayCommits.length > 0

                ListView {
                    id: commitList
                    model: root.displayCommits
                    clip: true

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        property double lastDouble: 0

                        width: ListView.view.width
                        height: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                        color: rowMouse.containsMouse ? Qt.alpha(Kirigami.Theme.highlightColor, 0.15) : "transparent"

                        // A single click shows the diff, a double click opens the web page. The diff
                        // view replaces the list, so it waits until the double-click time has passed.
                        Timer {
                            id: clickTimer
                            interval: ((Qt.styleHints && Qt.styleHints.mouseDoubleClickInterval) || 400) + 30
                            onTriggered: root.openDiff(row.modelData)
                        }

                        PlasmaComponents.Menu {
                            id: rowMenu
                            PlasmaComponents.MenuItem {
                                text: i18n("Show the changes")
                                icon.name: "vcs-diff"
                                onTriggered: root.openDiff(row.modelData)
                            }
                            PlasmaComponents.MenuItem {
                                text: i18n("Copy SHA")
                                icon.name: "edit-copy"
                                onTriggered: root.copySha(row.modelData)
                            }
                            PlasmaComponents.MenuItem {
                                text: i18n("Open in the browser")
                                icon.name: "internet-services"
                                enabled: root.st(row.modelData.repoId).webUrl !== ""
                                onTriggered: root.openCommitWeb(row.modelData)
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    clickTimer.stop();
                                    rowMenu.popup();
                                } else if (Date.now() - row.lastDouble > 600) {
                                    clickTimer.restart();
                                }
                            }
                            onDoubleClicked: {
                                clickTimer.stop();
                                row.lastDouble = Date.now();
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
                                    font.weight: row.modelData.unread ? Font.Bold : Font.Normal
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                    font: Kirigami.Theme.smallFont
                                    text: Helpers.metaHtml(row.modelData,
                                                           root.showAllTab && root.currentTab === "all" ? row.modelData.repoName : "",
                                                           root.rowColors)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.displayCommits.length === 0

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    icon.name: (!root.unconfigured && root.problems.length > 0) ? "dialog-warning" : "folder-git"
                    text: {
                        if (root.unconfigured) {
                            return i18n("No repository configured");
                        }
                        if (root.anyChecking) {
                            return i18n("Checking…");
                        }
                        if (root.problems.length > 0) {
                            return i18n("Nothing to show yet");
                        }
                        return i18n("No commits found");
                    }
                    helpfulAction: Kirigami.Action {
                        visible: root.unconfigured
                        text: i18n("Configure…")
                        icon.name: "configure"
                        onTriggered: root.openConfig()
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

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.diffState === "ok"

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
                    font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize > 0
                                    ? Kirigami.Theme.fixedWidthFont.pointSize
                                    : Kirigami.Theme.defaultFont.pointSize
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

                            readonly property rect lineRect: {
                                diffText.width;
                                diffText.contentHeight;
                                diffText.text;
                                return diffText.positionToRectangle(openBtn.modelData.off);
                            }

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
            visible: root.diffCommit === null && !root.unconfigured

            RowLayout {
                anchors.fill: parent

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.7
                    text: {
                        root.rev;
                        var ids = root.effectiveIds();
                        if (ids.length > 1) {
                            return i18np("Watching %1 repository", "Watching %1 repositories", ids.length);
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
                PlasmaComponents.ToolButton {
                    visible: {
                        root.rev;
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

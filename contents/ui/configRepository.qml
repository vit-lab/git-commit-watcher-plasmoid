import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/helpers.js" as Helpers

KCM.SimpleKCM {
    id: page

    // The list of repositories is stored as one JSON string.
    property string cfg_repos
    property string cfg_reposDefault
    property alias cfg_intervalMinutes: intervalSpin.value
    property alias cfg_autoUnlock: autoUnlockCheck.checked
    property alias cfg_unlockHours: unlockHoursSpin.value

    property int cfg_intervalMinutesDefault
    property bool cfg_autoUnlockDefault
    property int cfg_unlockHoursDefault

    readonly property string scriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/check.sh"))
    readonly property string agentScriptPath: Helpers.urlToPath(Qt.resolvedUrl("../code/agent.sh"))

    property int cur: -1                 // index of the repository being edited
    property string curLabel: ""         // display name of the repository being edited
    property string lastWritten: ""
    property bool loaded: false

    // SSH key status of the repository being edited
    property string keyState: ""         // "" | none | missing | plain | locked | unlocked
    property bool keyOwn: false
    property bool agentBusy: false
    property string agentCmd: ""
    property string agentMsg: ""

    // Connection test
    property bool testBusy: false
    property string testCmd: ""
    property bool testOk: false
    property string testText: ""

    readonly property string keyStatusText: {
        switch (keyState) {
        case "plain":
            return i18n("No passphrase – nothing to unlock");
        case "locked":
            return i18n("Locked (passphrase required)");
        case "unlocked":
            return keyOwn ? i18n("Unlocked (in the widget's private ssh-agent)")
                          : i18n("Unlocked (in your ssh-agent)");
        case "missing":
            return i18n("Key file not found");
        default:
            return "";
        }
    }

    ListModel {
        id: repoModel
    }

    // ----------------------------------------------------------- list <-> JSON

    function serialize() {
        var out = [];
        for (var i = 0; i < repoModel.count; ++i) {
            var m = repoModel.get(i);
            out.push({
                id: m.rid, name: m.name, path: m.path, branch: m.branch,
                sshKey: m.sshKey, tokenFile: m.tokenFile, enabled: m.enabled
            });
        }
        return JSON.stringify(out);
    }

    function labelFor(name, path, enabled) {
        return (name || Helpers.repoName(path) || i18n("New repository")) + (enabled ? "" : i18n(" (disabled)"));
    }

    // Keeps the "label" role (shown in the drop-down) in sync with name/path/enabled.
    function refreshLabel(i) {
        if (i < 0 || i >= repoModel.count) {
            curLabel = "";
            return;
        }
        var m = repoModel.get(i);
        var l = labelFor(m.name, m.path, m.enabled);
        repoModel.setProperty(i, "label", l);
        if (i === cur) {
            curLabel = l;
        }
    }

    function commit() {
        lastWritten = serialize();
        cfg_repos = lastWritten;
    }

    function reload() {
        if (loaded && cfg_repos === lastWritten) {
            return;
        }
        var list = Helpers.parseRepos(cfg_repos, true);
        repoModel.clear();
        for (var i = 0; i < list.length; ++i) {
            var r = list[i];
            repoModel.append({ rid: r.id, name: r.name, path: r.path, branch: r.branch, sshKey: r.sshKey, tokenFile: r.tokenFile, enabled: r.enabled, label: "" });
            refreshLabel(i);
        }
        lastWritten = cfg_repos;
        loaded = true;
        select(list.length > 0 ? 0 : -1);
    }

    onCfg_reposChanged: reload()
    Component.onCompleted: reload()

    function select(i) {
        cur = i;
        curLabel = "";
        agentMsg = "";
        testText = "";
        keyState = "";
        if (i < 0) {
            return;
        }
        refreshLabel(i);
        var m = repoModel.get(i);
        nameField.text = m.name;
        pathField.text = m.path;
        branchField.text = m.branch;
        keyField.text = m.sshKey;
        tokenField.text = m.tokenFile;
        enabledCheck.checked = m.enabled;
        refreshKey();
    }

    function setField(name, value) {
        if (cur < 0) {
            return;
        }
        repoModel.setProperty(cur, name, value);
        refreshLabel(cur);
        commit();
    }

    function addRepo() {
        repoModel.append({ rid: Helpers.newId(), name: "", path: "", branch: "", sshKey: "", tokenFile: "", enabled: true, label: "" });
        commit();
        select(repoModel.count - 1);
        pathField.forceActiveFocus();
    }

    function removeRepo() {
        if (cur < 0) {
            return;
        }
        var i = cur;
        repoModel.remove(i);
        commit();
        select(Math.min(i, repoModel.count - 1));
    }

    // ------------------------------------------------------------- SSH key

    function runAgent(action) {
        agentBusy = true;
        agentMsg = "";
        agentCmd = Helpers.agentCommand(agentScriptPath, action, {
            key: keyField.text,
            lifetime: unlockHoursSpin.value * 3600
        });
        agentSrc.connectSource(agentCmd);
    }

    function refreshKey() {
        if (keyField.text.length === 0) {
            keyState = "";
            return;
        }
        runAgent("status");
    }

    Plasma5Support.DataSource {
        id: agentSrc
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName !== page.agentCmd) {
                return;
            }
            page.agentBusy = false;
            var r = Helpers.parseAgent(data["stdout"], data["stderr"], data["exit code"]);
            if (r.ok) {
                page.keyState = r.key;
                page.keyOwn = r.own;
            } else {
                page.refreshKey();      // resets the message, so set it afterwards
                page.agentMsg = r.msg;
            }
        }
    }

    Plasma5Support.DataSource {
        id: tester
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName !== page.testCmd) {
                return;
            }
            page.testBusy = false;
            var r = Helpers.parseOutput(data["stdout"], data["stderr"], data["exit code"]);
            page.testOk = r.ok;
            if (r.ok) {
                var c = r.commits.length > 0 ? r.commits[0] : null;
                page.testText = i18n("Success. Latest commit: %1", c ? (c.short + " – " + c.author + ": " + c.subject) : r.tip);
            } else {
                page.testText = r.msg;
            }
        }
    }

    // --------------------------------------------------------------- dialogs

    FolderDialog {
        id: folderDialog
        title: i18n("Select a local clone")
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        onAccepted: {
            pathField.text = Helpers.urlToPath(selectedFolder);
            page.setField("path", pathField.text);
        }
    }

    FileDialog {
        id: keyDialog
        title: i18n("Select the SSH private key")
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.ssh"
        onAccepted: {
            keyField.text = Helpers.urlToPath(selectedFile);
            page.setField("sshKey", keyField.text);
            page.refreshKey();
        }
    }

    FileDialog {
        id: tokenDialog
        title: i18n("Select the token file")
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        onAccepted: {
            tokenField.text = Helpers.urlToPath(selectedFile);
            page.setField("tokenFile", tokenField.text);
        }
    }

    // ------------------------------------------------------------------- UI

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        // ---- repository selector: drop-down + Add / Remove, aligned with the form below
        Kirigami.FormLayout {
            id: selectorForm
            Layout.fillWidth: true
            twinFormLayouts: [repoForm, globalForm]

            RowLayout {
                Kirigami.FormData.label: i18n("Repository:")
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: repoCombo
                    Layout.fillWidth: true
                    enabled: repoModel.count > 0
                    model: repoModel
                    textRole: "label"
                    currentIndex: page.cur
                    displayText: repoModel.count > 0 ? page.curLabel : i18n("No repositories yet")
                    onActivated: index => page.select(index)
                }
                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Add")
                    onClicked: page.addRepo()
                }
                QQC2.Button {
                    icon.name: "list-remove"
                    text: i18n("Remove")
                    enabled: page.cur >= 0
                    onClicked: page.removeRepo()
                }
            }
        }

        // ---- selected repository
        Kirigami.FormLayout {
            id: repoForm
            Layout.fillWidth: true
            enabled: page.cur >= 0
            visible: page.cur >= 0

            QQC2.CheckBox {
                id: enabledCheck
                Kirigami.FormData.label: i18n("Watch:")
                text: i18n("Check this repository")
                onToggled: page.setField("enabled", checked)
            }

            QQC2.TextField {
                id: nameField
                Kirigami.FormData.label: i18n("Name:")
                Layout.fillWidth: true
                placeholderText: i18n("optional; defaults to the repository folder name")
                onTextEdited: page.setField("name", text)
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Path or URL:")
                Layout.fillWidth: true

                QQC2.TextField {
                    id: pathField
                    Layout.fillWidth: true
                    placeholderText: i18n("/path/to/clone  or  git@github.com:user/repo.git")
                    onTextEdited: page.setField("path", text)
                }
                QQC2.Button {
                    icon.name: "folder-open"
                    text: i18n("Browse…")
                    onClicked: folderDialog.open()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("A local clone is fetched in place (nothing in your working tree is changed). A remote URL is watched through a small private cache, so no clone is needed.")
            }

            QQC2.TextField {
                id: branchField
                Kirigami.FormData.label: i18n("Branch:")
                Layout.fillWidth: true
                placeholderText: i18n("empty = upstream branch of the clone / remote HEAD")
                onTextEdited: page.setField("branch", text)
            }

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Credentials")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("SSH private key:")
                Layout.fillWidth: true

                QQC2.TextField {
                    id: keyField
                    Layout.fillWidth: true
                    placeholderText: i18n("~/.ssh/id_ed25519  (empty = default ssh config)")
                    onTextEdited: page.setField("sshKey", text)
                    onEditingFinished: page.refreshKey()
                }
                QQC2.Button {
                    icon.name: "document-open"
                    text: i18n("Browse…")
                    onClicked: keyDialog.open()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Used only for ssh:// and git@ URLs. A key with a passphrase can be unlocked below: KDE asks for the passphrase in a dialog and the key is kept in the widget's own private ssh-agent. The passphrase itself is never stored.")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Key status:")
                visible: keyField.text.length > 0
                Layout.fillWidth: true

                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: page.agentBusy ? i18n("Working… (answer the passphrase dialog)") : page.keyStatusText
                    color: page.keyState === "locked" || page.keyState === "missing"
                           ? Kirigami.Theme.neutralTextColor
                           : (page.keyState === "unlocked" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor)
                }
                QQC2.Button {
                    icon.name: "object-unlocked"
                    text: i18n("Unlock…")
                    enabled: page.keyState === "locked" && !page.agentBusy
                    onClicked: page.runAgent("unlock")
                }
                QQC2.Button {
                    icon.name: "object-locked"
                    text: i18n("Lock")
                    enabled: page.keyState === "unlocked" && page.keyOwn && !page.agentBusy
                    onClicked: page.runAgent("lock")
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                visible: page.agentMsg !== ""
                wrapMode: Text.WordWrap
                text: page.agentMsg
                color: Kirigami.Theme.negativeTextColor
            }

            RowLayout {
                Kirigami.FormData.label: i18n("HTTPS token file:")
                Layout.fillWidth: true

                QQC2.TextField {
                    id: tokenField
                    Layout.fillWidth: true
                    placeholderText: i18n("~/.config/gcw-token  (optional)")
                    onTextEdited: page.setField("tokenFile", text)
                }
                QQC2.Button {
                    icon.name: "document-open"
                    text: i18n("Browse…")
                    onClicked: tokenDialog.open()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("For private https:// repositories: a file whose first line is a personal access token (kept out of the widget config on purpose; use chmod 600).")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Connection:")

                QQC2.Button {
                    icon.name: "network-connect"
                    text: page.testBusy ? i18n("Testing…") : i18n("Test connection")
                    enabled: !page.testBusy && pathField.text.length > 0
                    onClicked: {
                        page.testBusy = true;
                        page.testText = "";
                        page.testCmd = Helpers.checkCommand(page.scriptPath, {
                            repo: pathField.text,
                            branch: branchField.text,
                            key: keyField.text,
                            tokenFile: tokenField.text,
                            limit: 1
                        });
                        tester.connectSource(page.testCmd);
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                visible: page.testText !== ""
                wrapMode: Text.WordWrap
                text: page.testText
                color: page.testOk ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
            }
        }

        // ---- settings for all repositories
        Kirigami.FormLayout {
            id: globalForm
            Layout.fillWidth: true

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("All repositories")
            }

            QQC2.SpinBox {
                id: intervalSpin
                Kirigami.FormData.label: i18n("Check every:")
                from: 1
                to: 1440
                textFromValue: function(value) { return i18np("%1 minute", "%1 minutes", value); }
                valueFromText: function(text) { return parseInt(text) || 5; }
            }

            QQC2.CheckBox {
                id: autoUnlockCheck
                Kirigami.FormData.label: i18n("SSH keys:")
                text: i18n("Ask for the passphrase automatically when a key is locked")
            }

            QQC2.SpinBox {
                id: unlockHoursSpin
                Kirigami.FormData.label: i18n("Lock again after:")
                from: 0
                to: 168
                textFromValue: function(value) {
                    return value === 0 ? i18n("Never (until logout)") : i18np("%1 hour", "%1 hours", value);
                }
                valueFromText: function(text) { return parseInt(text) || 0; }
            }
        }
    }
}

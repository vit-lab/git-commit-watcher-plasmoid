import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/helpers.js" as Helpers

KCM.SimpleKCM {
    id: page

    property alias cfg_listPageSize: pageSpin.value
    property alias cfg_commitsPerBranch: limitSpin.value
    property alias cfg_maxAutoBranches: branchSpin.value
    property alias cfg_pauseOnBattery: batteryBox.checked
    property alias cfg_pauseWhenLocked: lockedBox.checked
    property alias cfg_spreadChecks: spreadBox.checked
    property alias cfg_prepareDiffs: prepareBox.checked

    // The size of the cache (see cacheSizeCommand), read when the page opens and after "Clear cache".
    property var cacheSize: null
    property string sizeCmd: ""
    property bool clearing: false

    function readCacheSize() {
        sizeCmd = Helpers.cacheSizeCommand();
        shell.connectSource(sizeCmd);
    }

    function formatSize(bytes) {
        return Qt.locale().formattedDataSize(bytes, bytes < 1048576 ? 0 : 1);
    }

    Plasma5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName === page.sizeCmd) {
                page.cacheSize = Helpers.parseCacheSize(data["stdout"]);
            } else {
                page.clearing = false;
                page.readCacheSize();
            }
        }
    }

    Component.onCompleted: readCacheSize()

    // The defaults of contents/config/main.xml; the settings dialog sets these properties too.
    property int cfg_listPageSizeDefault: 100
    property int cfg_commitsPerBranchDefault: 50
    property int cfg_maxAutoBranchesDefault: 30

    readonly property bool isDefault: pageSpin.value === cfg_listPageSizeDefault
        && limitSpin.value === cfg_commitsPerBranchDefault
        && branchSpin.value === cfg_maxAutoBranchesDefault

    // Every field has the same, moderate width (see configNotifications.qml).
    readonly property int fieldWidth: Kirigami.Units.gridUnit * 8
    readonly property int hintWidth: Kirigami.Units.gridUnit * 22

    function resetToDefaults() {
        pageSpin.value = cfg_listPageSizeDefault;
        limitSpin.value = cfg_commitsPerBranchDefault;
        branchSpin.value = cfg_maxAutoBranchesDefault;
    }

    Kirigami.FormLayout {
        // ------------------------------------------------------------ the list
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Commit list")
        }

        QQC2.SpinBox {
            id: pageSpin
            Layout.preferredWidth: page.fieldWidth
            Kirigami.FormData.label: i18n("Commits shown at first:")
            from: 0
            to: 5000
            stepSize: 50
            editable: true
            // 0 stands for "no limit".
            textFromValue: function(value, locale) {
                return value === 0 ? i18n("All") : Number(value).toLocaleString(locale, "f", 0);
            }
            valueFromText: function(text, locale) {
                var n = parseInt(String(text).replace(/[^0-9]/g, ""), 10);
                return isNaN(n) ? 0 : n;
            }
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: pageSpin.value === 0
                ? i18n("The list shows every commit at once. With thousands of commits it scrolls less smoothly.")
                : i18n("The list shows the newest %1 commits; \"Show %1 more\" at its end adds the next ones. 0 shows all at once.", pageSpin.value)
        }

        // ------------------------------------------------------------ what is watched
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Checks")
        }

        QQC2.SpinBox {
            id: limitSpin
            Layout.preferredWidth: page.fieldWidth
            Kirigami.FormData.label: i18n("Commits per branch:")
            from: 10
            to: 500
            stepSize: 10
            editable: true
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("How many recent commits of each branch are downloaded and listed. A higher number makes the first check and the list bigger.")
        }

        QQC2.SpinBox {
            id: branchSpin
            Layout.preferredWidth: page.fieldWidth
            Kirigami.FormData.label: i18n("Branches for ALL or a pattern:")
            from: 1
            to: 200
            stepSize: 5
            editable: true
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("The most branches of one repository that are watched when its branch setting is ALL or a pattern such as release/*. Branches listed by name are always watched.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            text: i18n("With these values, a repository watched with ALL can list up to %1 commits.",
                       Number(limitSpin.value * branchSpin.value).toLocaleString(Qt.locale(), "f", 0))
        }

        QQC2.Button {
            icon.name: "edit-undo"
            text: i18n("Reset to defaults")
            enabled: !page.isDefault
            onClicked: page.resetToDefaults()
            QQC2.ToolTip.text: i18n("%1 commits shown at first, %2 commits per branch, %3 branches",
                                    page.cfg_listPageSizeDefault, page.cfg_commitsPerBranchDefault, page.cfg_maxAutoBranchesDefault)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        // ------------------------------------------------------------ the automatic checks
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Automatic checks")
        }

        QQC2.CheckBox {
            id: batteryBox
            Kirigami.FormData.label: i18n("Pause:")
            text: i18n("On battery power")
        }
        QQC2.CheckBox {
            id: lockedBox
            text: i18n("While the screen is locked")
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("No automatic checks while paused; the tooltip says why. A check missed during a pause is made as soon as the pause ends. \"Check now\" always checks.")
        }

        QQC2.CheckBox {
            id: spreadBox
            Kirigami.FormData.label: i18n("Spread:")
            text: i18n("Start the repositories one after another")
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("The repositories of an automatic check start evenly spread over the check interval instead of all at the same moment. Every repository is still checked once per interval.")
        }

        // ------------------------------------------------------------ diffs
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Diffs")
        }

        QQC2.CheckBox {
            id: prepareBox
            Kirigami.FormData.label: i18n("Prepare:")
            text: i18n("Download the changes of new commits during the check")
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("The changed files of up to 5 new commits per repository are downloaded with them, so their diffs open at once, without waiting. Uses more network and disk space. Only for repositories watched by URL: a local clone has all files already.")
        }

        // ------------------------------------------------------------ cache
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Cache")
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Size:")
            text: page.cacheSize === null ? i18n("…") : page.formatSize(page.cacheSize.total)
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            visible: page.cacheSize !== null && page.cacheSize.total > 0
            text: page.cacheSize === null ? "" : i18n("Repositories watched by URL: %1 · \"All history\" search: %2 · \"Open File\": %3",
                                                      page.formatSize(page.cacheSize.repos), page.formatSize(page.cacheSize.history),
                                                      page.formatSize(page.cacheSize.files))
        }
        QQC2.Button {
            icon.name: "edit-clear"
            text: i18n("Clear cache")
            enabled: !page.clearing && page.cacheSize !== null && page.cacheSize.total > 0
            onClicked: {
                page.clearing = true;
                shell.connectSource(Helpers.clearCacheCommand());
            }
        }
        QQC2.Label {
            Layout.maximumWidth: page.hintWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Deletes the copies of repositories watched by URL, of \"All history\" searches and of \"Open File\". The next check downloads the recent commits again; local clones are not touched.")
        }
    }
}

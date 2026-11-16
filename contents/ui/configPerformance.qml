import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_listPageSize: pageSpin.value
    property alias cfg_commitsPerBranch: limitSpin.value
    property alias cfg_maxAutoBranches: branchSpin.value

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
    }
}

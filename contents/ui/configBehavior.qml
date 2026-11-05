import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_showBadge: badgeCheck.checked
    property alias cfg_hideWhenRead: hideCheck.checked
    property alias cfg_markReadOnOpen: markCheck.checked
    property alias cfg_iconSize: sizeCombo.currentIndex
    property alias cfg_iconIdle: idleIcon.iconName
    property alias cfg_iconNew: newIcon.iconName
    property alias cfg_iconMuted: mutedIcon.iconName

    property bool cfg_showBadgeDefault
    property bool cfg_hideWhenReadDefault
    property bool cfg_markReadOnOpenDefault
    property int cfg_iconSizeDefault
    property string cfg_iconIdleDefault
    property string cfg_iconNewDefault
    property string cfg_iconMutedDefault

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: badgeCheck
            Kirigami.FormData.label: i18n("Panel icon:")
            text: i18n("Show the number of unread commits")
        }

        QQC2.CheckBox {
            id: hideCheck
            text: i18n("Hide in the system tray when nothing is new")
        }

        QQC2.CheckBox {
            id: markCheck
            Kirigami.FormData.label: i18n("Unread state:")
            text: i18n("Mark as read when the popup opens")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Icons")
        }

        QQC2.ComboBox {
            id: sizeCombo
            Layout.preferredWidth: Kirigami.Units.gridUnit * 15
            Kirigami.FormData.label: i18n("Icon size:")
            model: [
                i18n("Normal (like tray icons)"),
                i18n("Big (fills the panel)")
            ]
        }

        IconField {
            id: idleIcon
            Layout.preferredWidth: Kirigami.Units.gridUnit * 15
            Kirigami.FormData.label: i18n("Icon (nothing new):")
            bundledKind: "idle"
        }

        IconField {
            id: newIcon
            Layout.preferredWidth: Kirigami.Units.gridUnit * 15
            Kirigami.FormData.label: i18n("Icon (new commits):")
            bundledKind: "new"
        }

        IconField {
            id: mutedIcon
            Kirigami.FormData.label: i18n("Icon (muted):")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 15
            bundledKind: "muted"
        }
    }
}

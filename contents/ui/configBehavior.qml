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

    property bool cfg_showBadgeDefault
    property bool cfg_hideWhenReadDefault
    property bool cfg_markReadOnOpenDefault
    property int cfg_iconSizeDefault
    property string cfg_iconIdleDefault
    property string cfg_iconNewDefault

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: badgeCheck
            Kirigami.FormData.label: i18n("Panel icon:")
            text: i18n("Show the number of unread commits as a badge")
        }

        QQC2.CheckBox {
            id: hideCheck
            text: i18n("In the system tray, hide the widget while there is nothing new")
        }

        QQC2.CheckBox {
            id: markCheck
            Kirigami.FormData.label: i18n("Unread state:")
            text: i18n("Mark commits as read when the popup is opened")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: sizeCombo
            Kirigami.FormData.label: i18n("Icon size:")
            model: [
                i18n("Normal (like the other system tray icons)"),
                i18n("Big (fill the panel)")
            ]
        }

        IconField {
            id: idleIcon
            Kirigami.FormData.label: i18n("Icon (nothing new):")
            bundledKind: "idle"
        }

        IconField {
            id: newIcon
            Kirigami.FormData.label: i18n("Icon (new commits):")
            bundledKind: "new"
        }
    }
}

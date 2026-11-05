import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/helpers.js" as Helpers

KCM.SimpleKCM {
    id: page

    property alias cfg_muted: muteCheck.checked
    property alias cfg_notifyEnabled: enabledCheck.checked
    property alias cfg_notifyClick: clickCheck.checked
    property alias cfg_notifyMode: modeCombo.currentIndex
    property alias cfg_notifyMax: maxSpin.value
    property alias cfg_urgency: urgencyCombo.currentIndex
    property alias cfg_useDefaultTimeout: defaultTimeoutCheck.checked
    property alias cfg_timeoutSec: timeoutSpin.value
    property alias cfg_showAuthor: authorCheck.checked
    property alias cfg_showHash: hashCheck.checked
    property alias cfg_notifyIcon: notifyIconField.iconName
    property alias cfg_playSound: soundCheck.checked
    property alias cfg_soundName: soundField.soundName

    property bool cfg_mutedDefault
    property bool cfg_notifyEnabledDefault
    property bool cfg_notifyClickDefault
    property int cfg_notifyModeDefault
    property int cfg_notifyMaxDefault
    property int cfg_urgencyDefault
    property bool cfg_useDefaultTimeoutDefault
    property int cfg_timeoutSecDefault
    property bool cfg_showAuthorDefault
    property bool cfg_showHashDefault
    property string cfg_notifyIconDefault
    property bool cfg_playSoundDefault
    property string cfg_soundNameDefault

    // The options below are only editable while notifications are on and not muted.
    readonly property bool notifyActive: enabledCheck.checked && !muteCheck.checked

    // Every field has the same, moderate width. Wide fields make the form wider than a normal
    // settings window, and Kirigami.FormLayout then puts the labels above the fields.
    readonly property int fieldWidth: Kirigami.Units.gridUnit * 15

    Plasma5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    Kirigami.FormLayout {
        // ---------------------------------------------------------------- general
        QQC2.CheckBox {
            id: muteCheck
            Kirigami.FormData.label: i18n("Mute:")
            text: i18n("Turn off all notifications and sounds")
            QQC2.ToolTip.text: i18n("The widget keeps checking and counting new commits; only the desktop notifications and the sound are switched off.")
            QQC2.ToolTip.visible: hovered
        }

        QQC2.CheckBox {
            id: enabledCheck
            Kirigami.FormData.label: i18n("Notify:")
            enabled: !muteCheck.checked
            text: i18n("When new commits arrive")
        }

        QQC2.CheckBox {
            id: clickCheck
            Kirigami.FormData.label: i18n("Click:")
            enabled: page.notifyActive
            text: i18n("Clicking a notification shows the changes")
            QQC2.ToolTip.text: i18n("Opens the popup with the diff of the commit (or the commit list for a summary). Needs notify-send 0.8 or newer (libnotify); with an older version the notifications still work, but a click does nothing.")
            QQC2.ToolTip.visible: hovered
        }

        // ---------------------------------------------------------------- content
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Content")
        }

        QQC2.ComboBox {
            id: modeCombo
            Kirigami.FormData.label: i18n("Style:")
            enabled: page.notifyActive
            Layout.preferredWidth: page.fieldWidth
            model: [
                i18n("One summary"),
                i18n("One per commit"),
                i18n("Only the latest commit")
            ]
        }

        QQC2.SpinBox {
            id: maxSpin
            Kirigami.FormData.label: i18n("Max. commits listed:")
            enabled: page.notifyActive && modeCombo.currentIndex !== 2
            from: 1
            to: 20
        }

        QQC2.CheckBox {
            id: authorCheck
            Kirigami.FormData.label: i18n("Show:")
            enabled: page.notifyActive
            text: i18n("Author name")
        }

        QQC2.CheckBox {
            id: hashCheck
            enabled: page.notifyActive
            text: i18n("Short commit hash")
        }

        // ---------------------------------------------------------------- appearance
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }

        QQC2.ComboBox {
            id: urgencyCombo
            Kirigami.FormData.label: i18n("Urgency:")
            enabled: page.notifyActive
            Layout.preferredWidth: page.fieldWidth
            model: [
                i18n("Low"),
                i18n("Normal"),
                i18n("Critical (ignores Do Not Disturb)")
            ]
        }

        QQC2.CheckBox {
            id: defaultTimeoutCheck
            Kirigami.FormData.label: i18n("Timeout:")
            enabled: page.notifyActive
            text: i18n("Use the system default")
        }

        QQC2.SpinBox {
            id: timeoutSpin
            enabled: page.notifyActive && !defaultTimeoutCheck.checked
            from: 0
            to: 600
            textFromValue: function(value) {
                return value === 0 ? i18n("Until dismissed") : i18np("%1 second", "%1 seconds", value);
            }
            valueFromText: function(text) { return parseInt(text) || 0; }
        }

        IconField {
            id: notifyIconField
            Kirigami.FormData.label: i18n("Icon:")
            enabled: page.notifyActive
            Layout.preferredWidth: page.fieldWidth
            bundledKind: "new"
        }

        // ---------------------------------------------------------------- sound
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Sound")
        }

        QQC2.CheckBox {
            id: soundCheck
            Kirigami.FormData.label: i18n("Play:")
            enabled: page.notifyActive
            text: i18n("A sound with each notification")
        }

        SoundField {
            id: soundField
            Kirigami.FormData.label: i18n("Sound:")
            enabled: page.notifyActive && soundCheck.checked
            Layout.preferredWidth: page.fieldWidth
        }

        QQC2.Label {
            Layout.preferredWidth: page.fieldWidth
            Layout.maximumWidth: page.fieldWidth
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Choose a system sound or a sound file, or type a sound-theme name (for example message-new-instant) or a file path. Needs canberra-gtk-play (libcanberra) or pw-play (PipeWire).")
        }

        // ---------------------------------------------------------------- preview
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Preview:")
            icon.name: "notifications"
            text: i18n("Send test notification")
            onClicked: {
                var body = (hashCheck.checked ? "a1b2c3d  " : "")
                         + (authorCheck.checked ? "Alice: " : "")
                         + "Fix typo in README";
                notifier.connectSource(Helpers.notifyCommand({
                    urgency: urgencyCombo.currentIndex,
                    useDefaultTimeout: defaultTimeoutCheck.checked,
                    timeoutSec: timeoutSpin.value,
                    icon: Helpers.urlToPath(notifyIconField.iconName !== ""
                                            ? notifyIconField.iconName
                                            : Qt.resolvedUrl("../icons/notify-" + (notifyIconField.lightText ? "light" : "dark") + ".svg"))
                }, i18n("my-repo: new commit"), Helpers.esc(body)));
                if (soundCheck.checked) {
                    notifier.connectSource(Helpers.soundCommand(soundField.soundName));
                }
            }
        }
    }
}

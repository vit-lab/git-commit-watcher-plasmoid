import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/helpers.js" as Helpers

KCM.SimpleKCM {
    id: page

    property alias cfg_notifyEnabled: enabledCheck.checked
    property alias cfg_notifyMode: modeCombo.currentIndex
    property alias cfg_notifyMax: maxSpin.value
    property alias cfg_urgency: urgencyCombo.currentIndex
    property alias cfg_useDefaultTimeout: defaultTimeoutCheck.checked
    property alias cfg_timeoutSec: timeoutSpin.value
    property alias cfg_showAuthor: authorCheck.checked
    property alias cfg_showHash: hashCheck.checked
    property alias cfg_notifyIcon: notifyIconField.iconName
    property alias cfg_playSound: soundCheck.checked
    property alias cfg_soundName: soundField.text

    property bool cfg_notifyEnabledDefault
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

    Plasma5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledCheck
            Kirigami.FormData.label: i18n("Desktop notifications:")
            text: i18n("Show a notification when new commits arrive")
        }

        QQC2.ComboBox {
            id: modeCombo
            Kirigami.FormData.label: i18n("Style:")
            enabled: enabledCheck.checked
            model: [
                i18n("One summary notification"),
                i18n("One notification per commit"),
                i18n("Only the latest commit")
            ]
        }

        QQC2.SpinBox {
            id: maxSpin
            Kirigami.FormData.label: i18n("Max. commits listed:")
            enabled: enabledCheck.checked && modeCombo.currentIndex !== 2
            from: 1
            to: 20
        }

        QQC2.CheckBox {
            id: authorCheck
            Kirigami.FormData.label: i18n("Show:")
            enabled: enabledCheck.checked
            text: i18n("Author name")
        }

        QQC2.CheckBox {
            id: hashCheck
            enabled: enabledCheck.checked
            text: i18n("Short commit hash")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: urgencyCombo
            Kirigami.FormData.label: i18n("Urgency:")
            enabled: enabledCheck.checked
            model: [
                i18n("Low"),
                i18n("Normal"),
                i18n("Critical (also shown in Do Not Disturb mode)")
            ]
        }

        QQC2.CheckBox {
            id: defaultTimeoutCheck
            Kirigami.FormData.label: i18n("Timeout:")
            enabled: enabledCheck.checked
            text: i18n("Use the system default")
        }

        QQC2.SpinBox {
            id: timeoutSpin
            enabled: enabledCheck.checked && !defaultTimeoutCheck.checked
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
            enabled: enabledCheck.checked
            bundledKind: "new"
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: soundCheck
            Kirigami.FormData.label: i18n("Sound:")
            enabled: enabledCheck.checked
            text: i18n("Play a sound")
        }

        QQC2.TextField {
            id: soundField
            enabled: enabledCheck.checked && soundCheck.checked
            Layout.fillWidth: true
            placeholderText: "message-new-instant"
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("A freedesktop sound-theme name, e.g. message-new-instant, complete, bell. Needs libcanberra (canberra-gtk-play) or pipewire (pw-play).")
        }

        Item {
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
                    notifier.connectSource(Helpers.soundCommand(soundField.text));
                }
            }
        }
    }
}

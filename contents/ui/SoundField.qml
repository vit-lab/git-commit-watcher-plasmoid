import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/helpers.js" as Helpers

// Sound picker, in the style of IconField: a button with a menu ("System sounds…" lists the sounds
// of the installed sound themes, "Sound file…" opens a file dialog, "Reset to default sound"),
// a preview button, and an editable field. soundName is a sound-theme name such as
// "message-new-instant", or the path of a sound file.
RowLayout {
    id: root

    property string soundName: ""
    readonly property string defaultSound: "message-new-instant"

    property var sounds: []                 // names found in the sound themes (filled on first use)
    property bool soundsLoaded: false
    property var fileDialog: null
    property string note: ""

    spacing: Kirigami.Units.smallSpacing

    function play(name) {
        player.connectSource(Helpers.soundCommand(name !== undefined ? name : root.soundName));
    }

    function loadSounds() {
        if (!soundsLoaded) {
            soundsLoaded = true;
            lister.connectSource(Helpers.listSoundsCommand());
        }
    }

    function chooseFile() {
        if (!fileDialog) {
            try {
                // Created on demand, so a missing module can never break the settings page.
                fileDialog = Qt.createQmlObject(
                    'import QtQuick\nimport QtQuick.Dialogs\nFileDialog {}', root, "SoundFileDialogLoader");
                fileDialog.title = i18n("Choose a sound file");
                fileDialog.nameFilters = [i18n("Sound files (*.oga *.ogg *.wav *.flac *.mp3)"), i18n("All files (*)")];
                fileDialog.accepted.connect(function() {
                    var f = Helpers.urlToPath(fileDialog.selectedFile);
                    if (f !== "") {
                        root.soundName = f;
                    }
                });
            } catch (e) {
                fileDialog = null;
                note = i18n("The file dialog is not available here; type the path instead.");
                return;
            }
        }
        note = "";
        fileDialog.open();
    }

    Plasma5Support.DataSource {
        id: player
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    Plasma5Support.DataSource {
        id: lister
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var out = String(data["stdout"] || "").split("\n");
            var names = [];
            for (var i = 0; i < out.length; ++i) {
                if (out[i].trim() !== "") {
                    names.push(out[i].trim());
                }
            }
            root.sounds = names;
        }
    }

    QQC2.Button {
        id: chooseButton
        icon.name: "audio-volume-high"
        onClicked: menu.popup(chooseButton, 0, chooseButton.height)
        QQC2.ToolTip.text: i18n("Choose a sound")
        QQC2.ToolTip.visible: hovered
    }

    QQC2.Menu {
        id: menu

        QQC2.MenuItem {
            text: i18n("System sounds…")
            icon.name: "folder-sound"
            onTriggered: {
                root.loadSounds();
                listDialog.open();
            }
        }
        QQC2.MenuItem {
            text: i18n("Sound file…")
            icon.name: "document-open-folder"
            onTriggered: root.chooseFile()
        }
        QQC2.MenuItem {
            text: i18n("Reset to default sound")
            icon.name: "edit-reset"
            enabled: root.soundName !== root.defaultSound
            onTriggered: root.soundName = root.defaultSound
        }
    }

    QQC2.Button {
        icon.name: "media-playback-start"
        onClicked: root.play()
        QQC2.ToolTip.text: i18n("Play the sound")
        QQC2.ToolTip.visible: hovered
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        QQC2.TextField {
            Layout.fillWidth: true
            text: root.soundName
            placeholderText: root.defaultSound
            onTextEdited: root.soundName = text
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: root.note !== ""
            wrapMode: Text.WordWrap
            text: root.note
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }
    }

    QQC2.Dialog {
        id: listDialog
        title: i18n("System sounds")
        modal: true
        anchors.centerIn: QQC2.Overlay.overlay
        width: Math.min(Kirigami.Units.gridUnit * 24, QQC2.Overlay.overlay ? QQC2.Overlay.overlay.width - Kirigami.Units.gridUnit * 2 : Kirigami.Units.gridUnit * 24)
        height: Math.min(Kirigami.Units.gridUnit * 28, QQC2.Overlay.overlay ? QQC2.Overlay.overlay.height - Kirigami.Units.gridUnit * 2 : Kirigami.Units.gridUnit * 28)
        standardButtons: QQC2.Dialog.Close

        onOpened: filter.forceActiveFocus()

        readonly property var shown: {
            var f = filter.text.trim().toLowerCase();
            if (f === "") {
                return root.sounds;
            }
            return root.sounds.filter(function(n) { return n.toLowerCase().indexOf(f) >= 0; });
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: filter
                Layout.fillWidth: true
                placeholderText: i18n("Filter…")
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.sounds.length === 0
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: root.soundsLoaded ? i18n("No sounds found in /usr/share/sounds or ~/.local/share/sounds. Use \"Sound file…\" instead.") : ""
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: listDialog.shown
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: QQC2.ItemDelegate {
                    id: soundRow
                    required property string modelData
                    width: ListView.view.width
                    highlighted: modelData === root.soundName
                    onClicked: {
                        root.soundName = modelData;
                        listDialog.close();
                    }
                    contentItem: RowLayout {
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: soundRow.modelData
                        }
                        QQC2.ToolButton {
                            icon.name: "media-playback-start"
                            onClicked: root.play(soundRow.modelData)
                            QQC2.ToolTip.text: i18n("Play")
                            QQC2.ToolTip.visible: hovered
                        }
                    }
                }
            }
        }
    }
}

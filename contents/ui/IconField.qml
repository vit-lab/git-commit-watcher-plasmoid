import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Icon picker: a button showing the current icon (with a menu: "Choose…" opens KDE's
// "Select Icon" dialog, like the one of the Application Launcher), plus an editable name field.
// An empty iconName means "use the bundled default icon" (contents/icons/<bundledKind>-*.svg).
RowLayout {
    id: root

    property string iconName: ""
    property string bundledKind: "idle"      // "idle" or "new"

    readonly property bool lightText: Kirigami.Theme.textColor.hslLightness > 0.5
    readonly property string bundledSource: Qt.resolvedUrl("../icons/" + bundledKind + "-" + (lightText ? "light" : "dark") + ".svg")

    property var dialog: null
    property string dialogError: ""

    spacing: Kirigami.Units.smallSpacing

    function choose() {
        if (!dialog) {
            try {
                // Created on demand, so a missing module can never break the settings page.
                dialog = Qt.createQmlObject(
                    'import QtQuick\nimport org.kde.iconthemes as KIconThemes\nKIconThemes.IconDialog {}',
                    root, "IconDialogLoader");
                dialog.iconNameChanged.connect(function() {
                    if (root.dialog && root.dialog.iconName) {
                        root.iconName = root.dialog.iconName;
                    }
                });
            } catch (e) {
                dialog = null;
                dialogError = i18n("The icon chooser is not available here; type the icon name instead.");
                return;
            }
        }
        dialogError = "";
        dialog.open();
    }

    QQC2.Button {
        id: iconButton
        implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.gridUnit
        implicitHeight: Kirigami.Units.iconSizes.large + Kirigami.Units.smallSpacing * 2
        onClicked: menu.popup(iconButton, 0, iconButton.height)

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                Layout.alignment: Qt.AlignCenter
                source: root.iconName !== "" ? root.iconName : root.bundledSource
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
            }
            Kirigami.Icon {
                source: "arrow-down"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                opacity: 0.7
            }
        }

        QQC2.ToolTip.text: i18n("Choose an icon")
        QQC2.ToolTip.visible: hovered
    }

    QQC2.Menu {
        id: menu

        QQC2.MenuItem {
            text: i18n("Choose…")
            icon.name: "document-open-folder"
            onTriggered: root.choose()
        }
        QQC2.MenuItem {
            text: i18n("Reset to default icon")
            icon.name: "edit-reset"
            enabled: root.iconName !== ""
            onTriggered: root.iconName = ""
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        QQC2.TextField {
            Layout.fillWidth: true
            text: root.iconName
            placeholderText: i18n("Default (bundled icon)")
            onTextEdited: root.iconName = text
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: root.dialogError !== ""
            wrapMode: Text.WordWrap
            text: root.dialogError
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }
    }
}

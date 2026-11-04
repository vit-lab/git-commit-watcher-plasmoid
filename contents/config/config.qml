import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Repositories")
        icon: "folder-git"
        source: "configRepository.qml"
    }
    ConfigCategory {
        name: i18n("Notifications")
        icon: "notifications"
        source: "configNotifications.qml"
    }
    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-desktop"
        source: "configBehavior.qml"
    }
}

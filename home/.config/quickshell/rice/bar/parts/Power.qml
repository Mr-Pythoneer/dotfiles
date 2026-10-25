import QtQuick
import qs.services
import qs.components

// Opens Caelestia's power menu (lock, log out, suspend, reboot, shut down)
Item {
    implicitWidth: 34
    implicitHeight: 30

    Icon {
        anchors.centerIn: parent
        icon: "power_settings_new"
        size: 18
        color: Theme.fg
    }

    Hover {
        onClicked: Ctl.drawer("session")
    }
}

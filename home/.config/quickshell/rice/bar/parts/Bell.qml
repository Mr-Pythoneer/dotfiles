import QtQuick
import qs.services
import qs.components

// Notifications waiting in Caelestia's notification centre; click to open it
Item {
    implicitWidth: 34 + (Notifs.count > 0 ? Math.max(15, num.implicitWidth + 8) - 6 : 0)
    implicitHeight: 30

    Icon {
        id: icn

        anchors.verticalCenter: parent.verticalCenter
        x: 8
        icon: Notifs.count ? "notifications_unread" : "notifications"
        fill: Notifs.count ? 1 : 0
        size: 18
        color: Notifs.count ? Theme.tertiary : Theme.fgDim
    }

    Rectangle {
        id: badge

        visible: Notifs.count > 0
        anchors.left: icn.right
        anchors.leftMargin: -4
        anchors.top: parent.top
        anchors.topMargin: 3
        height: 15
        width: Math.max(15, num.implicitWidth + 8)
        radius: height / 2
        color: Theme.primary

        Txt {
            id: num

            anchors.centerIn: parent
            text: Notifs.count > 99 ? "99+" : Notifs.count
            font.pixelSize: 9
            font.weight: Font.Bold
            color: Theme.surface
        }
    }

    Hover {
        onClicked: Ctl.drawer("sidebar")
    }
}

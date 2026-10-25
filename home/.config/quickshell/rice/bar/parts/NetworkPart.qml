import QtQuick
import qs.services
import qs.components

// Wi-Fi signal (or Ethernet / airplane mode), with a key when a VPN is up. Click for the control centre.
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2

        Icon {
            icon: Net.icon
            size: 17
            fill: 1
            color: Net.airplane ? Theme.tertiary : (Net.active || Net.wiredUp) ? Theme.fg : Theme.fgDim
        }

        Icon {
            visible: Net.vpnUp
            icon: "vpn_key"
            size: 13
            fill: 1
            color: Theme.secondary
        }
    }

    Hover {
        onClicked: Shell.toggle("control", root.monName)
    }
}

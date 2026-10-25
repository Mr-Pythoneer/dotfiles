import QtQuick
import qs.services
import qs.components

// VPN connections from NetworkManager, each with its own switch
Column {
    spacing: 4

    Header {
        width: parent.width
        text: "VPN"
        icon: "vpn_key"
    }

    Repeater {
        model: Net.vpns

        Item {
            required property var modelData

            width: parent.width
            height: 36

            Icon {
                id: k

                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                icon: modelData.active ? "vpn_lock" : "vpn_key"
                size: 16
                color: modelData.active ? Theme.secondary : Theme.fgDim
            }

            Txt {
                anchors.left: k.right
                anchors.leftMargin: 8
                anchors.right: sw.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
            }

            Switch {
                id: sw

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.active
                accent: Theme.secondary
                onToggled: Net.setVpn(modelData.name, !modelData.active)
            }
        }
    }

    Row {
        visible: Net.vpns.length === 0
        spacing: 8
        leftPadding: 6

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: "No VPNs set up"
            font.pixelSize: 11
            color: Theme.fgDim
        }

        PillButton {
            text: "Add one"
            icon: "add"
            onClicked: Ctl.run(["nm-connection-editor"])
        }
    }
}

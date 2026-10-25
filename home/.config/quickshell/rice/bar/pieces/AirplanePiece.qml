import QtQuick
import qs.services
import qs.components

// Airplane mode turns Wi-Fi and Bluetooth off together (your airplane-mode script)
Card {
    implicitHeight: 46

    Icon {
        id: icn

        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        icon: "flight"
        size: 18
        color: Net.airplane ? Theme.tertiary : Theme.fgDim
    }

    Txt {
        anchors.left: icn.right
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "Airplane mode"
    }

    Switch {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        checked: Net.airplane
        accent: Theme.tertiary
        onToggled: Net.toggleAirplane()
    }
}

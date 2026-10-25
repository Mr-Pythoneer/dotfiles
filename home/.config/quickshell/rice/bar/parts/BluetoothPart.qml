import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.components

// Bluetooth: off / on / connected (with the device's battery if it reports one). Click for the control centre.
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: (adapter?.devices?.values ?? []).filter(d => d.connected)
    readonly property var withBattery: connected.find(d => d.batteryAvailable)

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 3

        Icon {
            icon: !root.adapter?.enabled ? "bluetooth_disabled" : root.connected.length ? "bluetooth_connected" : "bluetooth"
            size: 17
            color: !root.adapter?.enabled ? Theme.fgDim : root.connected.length ? Theme.primary : Theme.fg
        }

        Txt {
            visible: !!root.withBattery
            text: Math.round((root.withBattery?.battery ?? 0) * 100) + "%"
            font.pixelSize: 11
            color: Theme.fgDim
        }
    }

    Hover {
        onClicked: Shell.toggle("control", root.monName)
    }
}

import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.components

// Battery level, grey like the rest of the bar (red under 20%); green with a bolt while plugged in. Click for the control centre.
// A red warning mark while something drains the battery (PowerHogs); the popout lists it.
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""
    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev?.percentage ?? 0
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: dev?.state === UPowerDeviceState.FullyCharged
    readonly property color tone: charging || full ? Theme.charge : pct < 0.2 ? Theme.error : pct < 0.4 ? Theme.tertiary : Theme.secondary

    implicitWidth: (dev?.isLaptopBattery ?? false) ? row.implicitWidth + 16 : 0
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2

        Icon {
            icon: root.charging ? "battery_charging_full" : root.pct > 0.95 ? "battery_full" : "battery_" + Math.max(0, Math.min(6, Math.round(root.pct * 7) - 1)) + "_bar"
            size: 17
            fill: 1
            color: root.tone
        }

        Txt {
            text: Math.round(root.pct * 100) + "%"
            font.weight: Font.DemiBold
            color: root.tone
        }

        Icon {
            visible: PowerHogs.warn
            anchors.verticalCenter: parent.verticalCenter
            icon: "warning"
            size: 15
            fill: 1
            color: Theme.error
        }
    }

    Hover {
        onClicked: Shell.toggle("control", root.monName)
    }
}

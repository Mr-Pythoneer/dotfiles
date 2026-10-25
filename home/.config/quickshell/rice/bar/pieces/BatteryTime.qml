import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.components

// Battery %, what it's doing and for how long, how much power the laptop is drawing, and battery health.
// The times come from BatteryLife (what the laptop has really used lately), not UPower's jumpy figure.
// On battery it also lists what's draining it (PowerHogs), with Quit / Shut down for apps and VMs.
Card {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev?.percentage ?? 0
    readonly property int st: dev?.state ?? 0
    readonly property color tone: st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge || st === UPowerDeviceState.FullyCharged ? Theme.charge : pct < 0.2 && st === UPowerDeviceState.Discharging ? Theme.error : pct < 0.4 && st === UPowerDeviceState.Discharging ? Theme.tertiary : Theme.secondary

    function dur(s: real): string {
        if (!s || s <= 0)
            return "";
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return (h ? h + "h " : "") + m + "m";
    }

    readonly property string status: {
        if (st === UPowerDeviceState.Charging) {
            const t = dur(BatteryLife.secondsToFull);
            return t ? "Charging · " + (BatteryLife.limit < 100 ? BatteryLife.limit + "%" : "full") + " in " + t : "Charging";
        }
        if (st === UPowerDeviceState.Discharging) {
            const t = dur(BatteryLife.secondsLeft);
            return t ? (BatteryLife.measured ? "" : "about ") + t + " left" : "On battery";
        }
        if (st === UPowerDeviceState.FullyCharged)
            return "Fully charged";
        if (st === UPowerDeviceState.PendingCharge)
            return BatteryLife.limit < 100 ? "Plugged in · holding at " + BatteryLife.limit + "%" : "Plugged in · holding charge";
        return "Plugged in";
    }

    implicitHeight: 86 + (PowerHogs.warn ? hogList.implicitHeight + 10 : 0)

    Behavior on implicitHeight { Springy {} }

    Item {
        id: head

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 86
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 10
        spacing: 12

        Txt {
            text: Math.round(root.pct * 100) + "%"
            font.pixelSize: 30
            font.weight: Font.Bold
            color: root.tone
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Txt {
                text: root.status
                font.weight: Font.DemiBold
            }

            Txt {
                text: UPower.onBattery ? "on battery" : "on the charger"
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: info.top
        anchors.margins: 14
        anchors.bottomMargin: 6
        height: 5
        radius: 2.5
        color: Qt.alpha(Theme.fg, 0.1)

        Rectangle {
            width: parent.width * root.pct
            height: parent.height
            radius: 2.5
            color: root.tone

            Behavior on width { Springy {} }
        }
    }

    Row {
        id: info

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.bottom: head.bottom
        anchors.bottomMargin: 9
        spacing: 14

        Txt {
            visible: BatteryLife.watts > 0.05 && (BatteryLife.status === "Discharging" || BatteryLife.status === "Charging")
            text: "⚡ " + BatteryLife.watts.toFixed(1) + " W"
            font.pixelSize: 11
            color: Theme.fgDim
        }

        Txt {
            visible: root.dev?.healthSupported ?? false
            text: "♥ health " + Math.round(root.dev?.healthPercentage ?? 0) + "%"
            font.pixelSize: 11
            color: Theme.fgDim
        }
    }

    Column {
        id: hogList

        visible: PowerHogs.warn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 10
        spacing: 2

        Txt {
            text: "Draining the battery"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Theme.error
        }

        Repeater {
            model: PowerHogs.drains

            Item {
                required property var modelData

                width: hogList.width
                height: 30

                Txt {
                    anchors.left: parent.left
                    anchors.right: amount.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideRight
                }

                Txt {
                    id: amount

                    anchors.right: quit.visible ? quit.left : parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: PowerHogs.amount(modelData.cpu)
                    font.pixelSize: 11
                    color: Theme.fgDim
                }

                PillButton {
                    id: quit

                    visible: modelData.kind !== "desktop"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 24
                    text: modelData.kind === "vm" ? "Shut down" : "Quit"
                    accent: Theme.error
                    onClicked: PowerHogs.quit(modelData)
                }
            }
        }
    }
}

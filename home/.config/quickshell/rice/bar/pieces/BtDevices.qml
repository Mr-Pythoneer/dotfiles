import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.components

// Bluetooth on/off and your paired devices; click one to connect or disconnect
Column {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: (adapter?.devices?.values ?? []).filter(d => d.paired || d.connected).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))

    function iconFor(d: var): string {
        const i = d.icon ?? "";
        if (/headset|headphone|audio-head/.test(i)) return "headphones";
        if (/mouse/.test(i)) return "mouse";
        if (/keyboard/.test(i)) return "keyboard";
        if (/phone/.test(i)) return "smartphone";
        if (/speaker|audio/.test(i)) return "speaker";
        if (/gaming|joystick/.test(i)) return "sports_esports";
        if (/computer/.test(i)) return "computer";
        return "bluetooth";
    }

    spacing: 4

    Header {
        width: parent.width
        text: "Bluetooth"
        icon: "bluetooth"

        Switch {
            checked: root.adapter?.enabled ?? false
            onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }
    }

    Repeater {
        model: root.adapter?.enabled ? root.devices : []

        Item {
            id: row

            required property var modelData
            readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

            width: root.width
            height: 40

            Rectangle {
                id: bubble

                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: row.modelData.connected ? Qt.alpha(Theme.primary, 0.2) : Qt.alpha(Theme.fg, 0.06)

                Icon {
                    anchors.centerIn: parent
                    icon: root.iconFor(row.modelData)
                    size: 16
                    color: row.modelData.connected ? Theme.primary : Theme.fgDim

                    RotationAnimation on rotation {
                        running: row.busy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1200
                    }
                }
            }

            Column {
                anchors.left: bubble.right
                anchors.leftMargin: 9
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Txt {
                    width: parent.width
                    text: row.modelData.name || row.modelData.address
                    color: row.modelData.connected ? Theme.fg : Theme.fgDim
                }

                Txt {
                    visible: text !== ""
                    text: row.busy ? (row.modelData.connected ? "Disconnecting…" : "Connecting…") : row.modelData.connected ? ("Connected" + (row.modelData.batteryAvailable ? " · " + Math.round(row.modelData.battery * 100) + "%" : "")) : ""
                    font.pixelSize: 10
                    color: Theme.secondary
                }
            }

            Hover {
                radius: 12
                onClicked: row.modelData.connected ? row.modelData.disconnect() : row.modelData.connect()
            }
        }
    }

    Txt {
        visible: (root.adapter?.enabled ?? false) && root.devices.length === 0
        width: parent.width
        leftPadding: 6
        text: "No paired devices yet"
        font.pixelSize: 11
        color: Theme.fgDim
    }

    PillButton {
        text: "Bluetooth settings"
        icon: "settings_bluetooth"
        onClicked: Ctl.script("bluetooth-manager")
    }
}

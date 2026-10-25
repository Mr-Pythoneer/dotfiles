import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.components
import qs.bar.pieces

// Quick settings: toggles, sliders, power profile, what's playing, and one-tap actions.
// Opens from the Wi-Fi, Bluetooth and battery icons, or Super+A.
Column {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: (adapter?.devices?.values ?? []).filter(d => d.connected)

    spacing: 10
    Component.onCompleted: {
        CaeState.refresh();
        Brightness.refresh();
        Net.refresh();
        Audio.refreshPorts();
    }

    // who and where, plus lock / settings / power
    Item {
        width: parent.width
        height: 46

        Rectangle {
            id: avatar

            width: 42
            height: 42
            radius: 21
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Theme.tertiary, 0.2)
            border.width: 1
            border.color: Qt.alpha(Theme.tertiary, 0.5)

            Txt {
                anchors.centerIn: parent
                text: Host.user.charAt(0).toUpperCase()
                font.pixelSize: 19
                font.weight: Font.Bold
                color: Theme.tertiary
            }
        }

        Column {
            anchors.left: avatar.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Txt {
                text: Host.user
                font.weight: Font.Bold
            }

            Txt {
                text: Host.hostname + " · up " + Clock.fmtUptime(Clock.uptime)
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            IconButton {
                icon: "lock"
                size: 18
                onClicked: {
                    Shell.close();
                    Ctl.caelestia("lock", "lock");
                }
            }

            IconButton {
                icon: "settings"
                size: 18
                onClicked: {
                    Shell.close();
                    Ctl.caelestia("nexus", "open");
                }
            }

            IconButton {
                icon: "power_settings_new"
                size: 18
                color: Theme.fg
                onClicked: {
                    Shell.close();
                    Ctl.drawer("session");
                }
            }
        }
    }

    Grid {
        width: parent.width
        columns: 2
        spacing: 8

        readonly property real tileW: (width - spacing) / 2

        Tile {
            width: parent.tileW
            icon: Net.wifiOn ? "wifi" : "wifi_off"
            name: "Wi-Fi"
            status: Net.wiredUp ? "Ethernet" : Net.wifiOn ? (Net.active?.name ?? "Not connected") : "Off"
            lit: Net.wifiOn && !Net.airplane
            onClicked: Net.setWifi(!Net.wifiOn)
        }

        Tile {
            width: parent.tileW
            icon: root.btConnected.length ? "bluetooth_connected" : "bluetooth"
            name: "Bluetooth"
            status: !root.adapter?.enabled ? "Off" : root.btConnected.length ? root.btConnected[0].name : "On"
            lit: root.adapter?.enabled ?? false
            onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }

        Tile {
            width: parent.tileW
            icon: "do_not_disturb_on"
            name: "Do not disturb"
            status: CaeState.dnd ? "Notifications hidden" : "Off"
            lit: CaeState.dnd
            accent: Theme.purple
            onClicked: CaeState.toggle("notifs")
        }

        Tile {
            width: parent.tileW
            icon: "coffee"
            name: "Keep awake"
            status: CaeState.awake ? "No sleep or lock" : "Off"
            lit: CaeState.awake
            accent: Theme.tertiary
            onClicked: CaeState.toggle("idleInhibitor")
        }

        Tile {
            width: parent.tileW
            icon: "flight"
            name: "Airplane mode"
            status: Net.airplane ? "Radios off" : "Off"
            lit: Net.airplane
            accent: Theme.tertiary
            onClicked: Net.toggleAirplane()
        }

        Tile {
            width: parent.tileW
            icon: Audio.micMuted ? "mic_off" : "mic"
            name: "Microphone"
            status: Audio.micMuted ? "Muted" : "On"
            lit: !Audio.micMuted
            accent: Theme.secondary
            onClicked: Audio.toggleMic()
        }

        Tile {
            width: parent.tileW
            icon: "sports_esports"
            name: "Game mode"
            status: CaeState.gameMode ? "Effects off" : "Off"
            lit: CaeState.gameMode
            accent: Theme.primary
            onClicked: CaeState.toggle("gameMode")
        }

        Tile {
            width: parent.tileW
            icon: "battery_charging_full"
            name: "Charge to 100%"
            status: SmartCharge.mode === "full" ? "Until unplugged" : SmartCharge.mode === "limit" ? "Capped at 80%" : "Optimized"
            lit: SmartCharge.mode === "full"
            accent: Theme.secondary
            onClicked: SmartCharge.set(SmartCharge.mode === "full" ? "auto" : "full")
        }
    }

    Column {
        width: parent.width
        spacing: 7

        // the arrow beside each audio slider opens the device picker on that tab
        Row {
            width: parent.width
            spacing: 4

            Slider {
                width: parent.width - outBtn.width - parent.spacing
                value: Audio.muted ? 0 : Audio.volume
                icon: Audio.volumeIcon(Audio.volume, Audio.muted)
                label: (Audio.sink ? Audio.label(Audio.sink) + " · " : "") + (Audio.muted ? "muted" : Math.round(Audio.volume * 100) + "%")
                accent: Theme.primary
                onMoved: v => Audio.setVolume(v)
                onIconClicked: Audio.toggleMute()
            }

            IconButton {
                id: outBtn

                icon: Audio.pickerOpen && Audio.pickerTab === "out" ? "expand_less" : "expand_more"
                active: Audio.pickerOpen && Audio.pickerTab === "out"
                activeColor: Theme.fg
                onClicked: Audio.togglePicker("out")
            }
        }

        Row {
            width: parent.width
            spacing: 4

            Slider {
                width: parent.width - inBtn.width - parent.spacing
                value: Audio.micMuted ? 0 : Audio.micVolume
                icon: Audio.micMuted ? "mic_off" : "mic"
                label: (Audio.source ? Audio.label(Audio.source) + " · " : "") + (Audio.micMuted ? "muted" : Math.round(Audio.micVolume * 100) + "%")
                accent: Theme.secondary
                onMoved: v => Audio.setMic(v)
                onIconClicked: Audio.toggleMic()
            }

            IconButton {
                id: inBtn

                icon: Audio.pickerOpen && Audio.pickerTab === "in" ? "expand_less" : "expand_more"
                active: Audio.pickerOpen && Audio.pickerTab === "in"
                activeColor: Theme.fg
                onClicked: Audio.togglePicker("in")
            }
        }

        Card {
            visible: Audio.pickerOpen
            width: parent.width
            height: picker.implicitHeight + 16

            SoundDevices {
                id: picker

                x: 8
                y: 8
                width: parent.width - 16
            }
        }

        Slider {
            visible: Brightness.available
            width: parent.width
            value: Brightness.value
            icon: "brightness_6"
            label: Math.round(Brightness.value * 100) + "%"
            accent: Theme.tertiary
            onMoved: v => Brightness.set(v)
        }
    }

    ProfilesPiece {
        width: parent.width
    }

    NowPlaying {
        visible: !!Media.active
        width: parent.width
    }

    // one-tap actions; the panel gets out of the way first
    Card {
        width: parent.width
        height: 66

        Row {
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: [
                    { icon: "screenshot_region", name: "Shot", cmd: Ctl.bin + "screenshot-area", c: Theme.primary },
                    { icon: "radio_button_checked", name: "Record", cmd: "caelestia record", c: Theme.fg },
                    { icon: "content_paste", name: "Clipboard", cmd: "caelestia clipboard", c: Theme.secondary },
                    { icon: "wallpaper", name: "Wallpaper", cmd: Ctl.bin + "rice-wall next", c: Theme.purple },
                    { icon: "monitoring", name: "Monitor", cmd: Ctl.bin + "sysmon-toggle", c: Theme.cyan },
                    { icon: "checklist", name: "To-do", cmd: "", c: Theme.secondary }
                ]

                Item {
                    required property var modelData

                    width: 58
                    height: 56

                    Column {
                        anchors.centerIn: parent
                        spacing: 3

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: modelData.icon
                            size: 21
                            color: modelData.c
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }
                    }

                    Hover {
                        radius: 12
                        onClicked: {
                            if (!modelData.cmd) {
                                Shell.open("todo", "");
                                return;
                            }
                            Shell.close();
                            Ctl.run(["sh", "-c", "sleep 0.35; exec " + modelData.cmd]);
                        }
                    }
                }
            }
        }
    }
}

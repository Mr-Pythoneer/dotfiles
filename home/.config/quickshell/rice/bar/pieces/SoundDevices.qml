import QtQuick
import qs.services
import qs.components

// Where sound goes and where the mic is: Output / Input tabs, tap a device to use it,
// plus whether newly connected devices take over by themselves
Column {
    id: root

    readonly property bool input: Audio.pickerTab === "in"
    readonly property var devices: input ? Audio.inputs : Audio.outputs
    readonly property var current: input ? Audio.source : Audio.sink

    spacing: 6

    // Output | Input
    Rectangle {
        id: tabs

        width: parent.width
        height: 30
        radius: height / 2
        color: Qt.alpha(Theme.fg, 0.06)

        Rectangle {
            width: parent.width / 2 - 4
            height: parent.height - 6
            y: 3
            x: root.input ? parent.width / 2 + 1 : 3
            radius: height / 2
            color: Qt.alpha(Theme.fg, 0.14)

            Behavior on x { Springy {} }
        }

        Row {
            anchors.fill: parent

            Repeater {
                model: [
                    { tab: "out", icon: "volume_up", name: "Output" },
                    { tab: "in", icon: "mic", name: "Input" }
                ]

                Item {
                    id: tab

                    required property var modelData
                    readonly property bool on: Audio.pickerTab === modelData.tab

                    width: tabs.width / 2
                    height: tabs.height

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: tab.modelData.icon
                            size: 15
                            fill: tab.on ? 1 : 0
                            color: tab.on ? Theme.fg : Theme.fgDim
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.name
                            font.pixelSize: 12
                            font.weight: tab.on ? Font.DemiBold : Font.Normal
                            color: tab.on ? Theme.fg : Theme.fgDim
                        }
                    }

                    Hover {
                        onClicked: {
                            Audio.pickerTab = tab.modelData.tab;
                            Audio.saveSettings();
                        }
                    }
                }
            }
        }
    }

    Txt {
        visible: root.devices.length === 0
        width: parent.width
        height: 34
        horizontalAlignment: Text.AlignHCenter
        text: root.input ? "No microphones found" : "No outputs found"
        font.pixelSize: Theme.smallText
        color: Theme.fgDim
    }

    Repeater {
        model: root.devices

        Item {
            id: row

            required property var modelData
            readonly property bool current: root.current === modelData

            width: root.width
            height: 42

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSmall
                color: Qt.alpha(Theme.fg, row.current ? 0.08 : 0)

                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }

            Rectangle {
                id: bubble

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: row.current ? Theme.primary : Qt.alpha(Theme.fg, 0.06)

                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                Icon {
                    anchors.centerIn: parent
                    icon: Audio.deviceIcon(row.modelData)
                    size: 16
                    fill: row.current ? 1 : 0
                    color: row.current ? Theme.surface : Theme.fgDim
                }
            }

            Column {
                anchors.left: bubble.right
                anchors.leftMargin: 10
                anchors.right: tick.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Txt {
                    width: parent.width
                    text: Audio.label(row.modelData)
                    font.pixelSize: 12
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    color: row.current ? Theme.fg : Theme.fgDim
                }

                Txt {
                    width: parent.width
                    text: Audio.detail(row.modelData)
                    font.pixelSize: 10
                    color: Theme.fgDim
                    opacity: 0.8
                }
            }

            Icon {
                id: tick

                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                icon: "check"
                size: 17
                color: Theme.fg
                opacity: row.current ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
            }

            Hover {
                radius: Theme.radiusSmall
                onClicked: root.input ? Audio.setSource(row.modelData) : Audio.setSink(row.modelData)
            }
        }
    }

    Item {
        width: parent.width
        height: 32

        Txt {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: autoSw.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Switch to new devices automatically"
            font.pixelSize: Theme.smallText
            color: Theme.fgDim
        }

        Switch {
            id: autoSw

            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            checked: Audio.autoSwitch
            onToggled: Audio.setAutoSwitch(!Audio.autoSwitch)
        }
    }
}

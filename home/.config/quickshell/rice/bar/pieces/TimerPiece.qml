import QtQuick
import qs.services
import qs.components

// Stopwatch or countdown timer; it keeps running after the popout closes and shows next to the clock
Card {
    implicitHeight: 128

    Row {
        id: modes

        anchors.horizontalCenter: parent.horizontalCenter
        y: 9
        spacing: 4

        Repeater {
            model: [{ id: "stopwatch", name: "Stopwatch", icon: "avg_pace" }, { id: "timer", name: "Timer", icon: "timer" }]

            Rectangle {
                required property var modelData
                readonly property bool sel: Clock.mode === modelData.id

                width: 104
                height: 26
                radius: 13
                color: sel ? Qt.alpha(Theme.cyan, 0.18) : "transparent"
                border.width: sel ? 1 : 0
                border.color: Qt.alpha(Theme.cyan, 0.5)

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        icon: modelData.icon
                        size: 14
                        color: sel ? Theme.cyan : Theme.fgDim
                    }

                    Txt {
                        text: modelData.name
                        font.pixelSize: 11
                        color: sel ? Theme.cyan : Theme.fgDim
                    }
                }

                Hover {
                    onClicked: Clock.setMode(modelData.id)
                }
            }
        }
    }

    Txt {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 40
        text: Clock.fmtMs(Clock.shown)
        font.pixelSize: 30
        font.weight: Font.Bold
        color: Clock.running ? Theme.cyan : Theme.fg
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 6

        IconButton {
            visible: Clock.mode === "timer" && !Clock.active
            icon: "remove"
            size: 16
            onClicked: Clock.addTimer(-60000)
        }

        IconButton {
            icon: Clock.running ? "pause" : "play_arrow"
            size: 20
            fill: 1
            active: true
            activeColor: Theme.cyan
            onClicked: Clock.running ? Clock.pause() : Clock.start()
        }

        IconButton {
            icon: "restart_alt"
            size: 18
            disabled: !Clock.active
            onClicked: Clock.reset()
        }

        IconButton {
            visible: Clock.mode === "timer" && !Clock.active
            icon: "add"
            size: 16
            onClicked: Clock.addTimer(60000)
        }

        PillButton {
            visible: Clock.mode === "timer" && !Clock.active
            anchors.verticalCenter: parent.verticalCenter
            text: "+5m"
            accent: Theme.cyan
            onClicked: Clock.addTimer(300000)
        }
    }
}

import QtQuick
import qs.services
import qs.components

// h:mm:ss am/pm in orange; a running stopwatch or timer shows next to it. Click for the dashboard.
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            visible: Clock.active
            anchors.verticalCenter: parent.verticalCenter
            height: 20
            width: tr.implicitWidth + 12
            radius: 10
            color: Qt.alpha(Theme.cyan, 0.15)

            Row {
                id: tr

                anchors.centerIn: parent
                spacing: 3

                Icon {
                    icon: Clock.mode === "timer" ? "timer" : "avg_pace"
                    size: 13
                    color: Theme.cyan
                }

                Txt {
                    text: Clock.fmtMs(Clock.shown)
                    font.pixelSize: 11
                    color: Theme.cyan
                    opacity: Clock.running ? 1 : 0.6
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Txt {
                text: Clock.hm
                font.weight: Font.DemiBold
                color: Theme.tertiary
            }

            Txt {
                visible: !Power.eco
                text: ":" + Clock.seconds
                color: Qt.alpha(Theme.tertiary, 0.75)
            }

            Txt {
                text: " " + Clock.ampm
                font.pixelSize: 11
                color: Theme.fgDim
                anchors.baseline: parent.children[0].baseline
            }
        }
    }

    Hover {
        onClicked: Shell.toggle("dashboard", root.monName)
    }
}

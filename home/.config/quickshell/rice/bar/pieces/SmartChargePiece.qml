import QtQuick
import qs.services
import qs.components

// smart-charge: what it's doing now, and its three modes
Card {
    implicitHeight: col.implicitHeight + 22

    Column {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 11
        spacing: 9

        Row {
            width: parent.width
            spacing: 9

            Icon {
                id: bolt

                icon: "bolt"
                size: 19
                fill: 1
                color: Theme.secondary
            }

            Txt {
                width: parent.width - bolt.width - 9
                text: SmartCharge.summary || "Smart charge isn't running"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                color: SmartCharge.ready ? Theme.fg : Theme.tertiary
            }
        }

        Row {
            spacing: 5

            Repeater {
                model: [{ m: "auto", name: "Optimized" }, { m: "limit", name: "Cap 80%" }, { m: "full", name: "Full 100%" }]

                PillButton {
                    required property var modelData

                    text: modelData.name
                    accent: Theme.secondary
                    filled: SmartCharge.mode === modelData.m
                    onClicked: SmartCharge.set(modelData.m)
                }
            }
        }
    }
}

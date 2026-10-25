import QtQuick
import qs.services
import qs.components

// Running Claude Code sessions; the ones waiting for you pulse. Click to jump to one. Hidden when none are running.
Item {
    id: root

    implicitWidth: Claude.count > 0 ? row.implicitWidth + 16 : 0
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 5

        // cycles through Claude's own spinner glyphs while a session works: 4 redraws a second instead of a 60 fps spin
        Txt {
            property int frame: 0

            // the glyphs differ in width; a fixed box keeps the island from re-springing on every frame
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: "✳✶✻✽✻✶"[frame]
            font.pixelSize: 16
            color: Theme.tertiary

            Timer {
                interval: 250
                repeat: true
                running: Claude.count > Claude.waiting && !Power.eco
                onTriggered: parent.frame = (parent.frame + 1) % 6
                onRunningChanged: if (!running) parent.frame = 0
            }
        }

        Txt {
            text: Claude.count
            font.weight: Font.DemiBold
        }

        Rectangle {
            visible: Claude.waiting > 0
            anchors.verticalCenter: parent.verticalCenter
            height: 18
            width: wt.implicitWidth + 12
            radius: 9
            color: Qt.alpha(Theme.primary, 0.14)
            border.width: 1
            border.color: Qt.alpha(Theme.primary, 0.6)

            Txt {
                id: wt

                anchors.centerIn: parent
                text: Claude.waiting + " waiting"
                font.pixelSize: 10
                color: Theme.primary
            }
        }
    }

    Hover {
        onClicked: Claude.focusNext()
    }
}

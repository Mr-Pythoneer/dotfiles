import QtQuick
import qs.services
import qs.components

// Little cava bars that move with whatever's playing; flat dots when it's quiet
Item {
    implicitWidth: bars.implicitWidth + 18
    implicitHeight: 30

    Row {
        id: bars

        anchors.centerIn: parent
        spacing: 2
        height: 22

        Repeater {
            model: 10

            Rectangle {
                required property int index
                readonly property real v: Audio.playing ? Math.min(1, Audio.bars[index] ?? 0) : 0

                width: 3
                height: Math.max(3, v * 22)
                radius: 1.5
                anchors.verticalCenter: parent.verticalCenter
                color: Audio.playing ? Qt.tint(Theme.primary, Qt.alpha(Theme.secondary, index / 9)) : Qt.alpha(Theme.fgDim, 0.5)

                Behavior on height { NumberAnimation { duration: 90 } }
                Behavior on color { ColorAnimation { duration: 400 } }
            }
        }
    }
}

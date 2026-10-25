import QtQuick
import qs.services

// A thick pill slider with its icon inside; drag, click or scroll it. Clicking the icon fires iconClicked.
Item {
    id: root

    property real value: 0
    property color accent: Theme.primary
    property string icon
    property string label
    readonly property bool dragging: area.pressed

    signal moved(real value)
    signal iconClicked()

    implicitHeight: 34
    implicitWidth: 200

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Theme.fg, 0.08)
        clip: true

        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.max(height, root.value * parent.width)
            color: Qt.alpha(root.accent, 0.9)

            Behavior on width {
                enabled: !root.dragging
                Springy {}
            }
        }
    }

    Icon {
        id: icn

        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        icon: root.icon
        size: 18
        fill: 1
        color: root.value > 0.08 ? Theme.surface : Theme.fg
    }

    Txt {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.pixelSize: Theme.smallText
        color: root.value > 0.9 ? Theme.surface : Theme.fgDim
    }

    MouseArea {
        id: area

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function setFrom(x: real): void {
            root.moved(Math.max(0, Math.min(1, x / width)));
        }

        onPressed: mouse => {
            if (mouse.x < icn.x + icn.width + 6)
                return;
            setFrom(mouse.x);
        }
        onClicked: mouse => {
            if (mouse.x < icn.x + icn.width + 6)
                root.iconClicked();
        }
        onPositionChanged: mouse => {
            if (pressed && mouse.x >= icn.x + icn.width + 6)
                setFrom(mouse.x);
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}

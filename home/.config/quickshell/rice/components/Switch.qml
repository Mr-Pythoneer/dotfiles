import QtQuick
import qs.services

// An on/off switch; the knob springs across
Item {
    id: root

    property bool checked
    property color accent: Theme.primary

    signal toggled()

    implicitWidth: 40
    implicitHeight: 22

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Qt.alpha(root.accent, 0.85) : Qt.alpha(Theme.fg, 0.12)

        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.surface : Theme.fgDim

            Behavior on x { Springy {} }
        }
    }

    Hover {
        onClicked: root.toggled()
    }
}

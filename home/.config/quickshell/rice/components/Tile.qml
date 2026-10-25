import QtQuick
import qs.services

// A control-centre toggle: icon bubble, name and a status line; lit up when on
Rectangle {
    id: root

    property string icon
    property string name
    property string status
    property bool lit: false
    property color accent: Theme.primary

    signal clicked()
    signal rightClicked()

    implicitHeight: 58
    radius: Theme.radiusSmall
    color: lit ? Qt.alpha(accent, 0.16) : Theme.card
    border.width: 1
    border.color: lit ? Qt.alpha(accent, 0.5) : Qt.alpha(Theme.line, 0.35)
    scale: hover.pressed ? 0.96 : 1

    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    Behavior on scale { Springy {} }

    Rectangle {
        id: bubble

        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 18
        color: root.lit ? root.accent : Qt.alpha(Theme.fg, 0.08)

        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Icon {
            anchors.centerIn: parent
            icon: root.icon
            size: 19
            fill: root.lit ? 1 : 0
            color: root.lit ? Theme.surface : Theme.fg
        }
    }

    Column {
        anchors.left: bubble.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Txt {
            width: parent.width
            text: root.name
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Txt {
            width: parent.width
            visible: text !== ""
            text: root.status
            font.pixelSize: 10
            color: root.lit ? root.accent : Theme.fgDim
        }
    }

    Hover {
        id: hover

        radius: root.radius
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}

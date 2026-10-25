import QtQuick
import qs.services

// Fills its parent: a pointer cursor plus a soft highlight on hover and press
MouseArea {
    id: area

    property real radius: height / 2
    property color tint: Theme.fg
    property bool disabled: false

    anchors.fill: parent
    hoverEnabled: true
    enabled: !disabled
    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    Rectangle {
        anchors.fill: parent
        radius: area.radius
        color: area.tint
        opacity: area.disabled ? 0 : area.pressed ? 0.16 : area.containsMouse ? 0.08 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast }
        }
    }
}

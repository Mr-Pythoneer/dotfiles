import QtQuick
import qs.services

Item {
    id: root

    property string icon
    property color color: Theme.fg
    property int size: 18
    property real fill: 0
    property bool active: false
    property color activeColor: Theme.primary
    property bool disabled: false

    signal clicked(var mouse)

    implicitWidth: size + 16
    implicitHeight: size + 16
    opacity: disabled ? 0.4 : 1

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(root.activeColor, 0.18)
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.6

        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        Behavior on scale { Springy {} }
    }

    Icon {
        anchors.centerIn: parent
        icon: root.icon
        size: root.size
        fill: root.active ? 1 : root.fill
        color: root.active ? root.activeColor : root.color
    }

    Hover {
        disabled: root.disabled
        onClicked: mouse => root.clicked(mouse)
    }
}

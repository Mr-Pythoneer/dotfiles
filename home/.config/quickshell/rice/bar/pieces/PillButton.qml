import QtQuick
import qs.services
import qs.components

// A small rounded text button
Rectangle {
    id: root

    property string text
    property string icon
    property color accent: Theme.primary
    property bool filled: false

    signal clicked()

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 30
    radius: 15
    color: filled ? accent : Qt.alpha(accent, 0.12)
    border.width: filled ? 0 : 1
    border.color: Qt.alpha(accent, 0.4)
    scale: hover.pressed ? 0.94 : 1

    Behavior on scale { Springy {} }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 5

        Icon {
            visible: root.icon !== ""
            icon: root.icon
            size: 15
            color: root.filled ? Theme.surface : root.accent
        }

        Txt {
            text: root.text
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.filled ? Theme.surface : root.accent
        }
    }

    Hover {
        id: hover

        tint: root.filled ? Theme.surface : root.accent
        onClicked: root.clicked()
    }
}

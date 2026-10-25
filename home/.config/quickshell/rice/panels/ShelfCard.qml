import QtQuick
import qs.services
import qs.components

// A card on the shelf: an icon and a title along the top, small buttons on the right, then whatever goes inside
Card {
    id: root

    property string title
    property string icon
    property string note
    property color accent: Theme.primary
    default property alias content: body.data
    property alias tools: tools.data

    Row {
        id: head

        x: 14
        y: 11
        spacing: 7

        Icon {
            icon: root.icon
            size: 17
            color: root.accent
        }

        Txt {
            text: root.title
            font.weight: Font.Bold
        }

        Txt {
            text: root.note
            font.pixelSize: 11
            color: Theme.fgDim
        }
    }

    Row {
        id: tools

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: head.verticalCenter
    }

    Item {
        id: body

        x: 8
        y: 40
        width: parent.width - 16
        height: parent.height - y - 8
        clip: true
    }
}

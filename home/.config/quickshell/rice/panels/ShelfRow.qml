import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components

// One line in a shelf card: an icon (or a little picture), a name, an optional second line, and a hover highlight
Item {
    id: root

    property string icon
    property color accent: Theme.fgDim
    property string image       // a file to show as a thumbnail instead of the icon
    property string text
    property string sub
    property bool flash: false  // briefly shows a tick, after copying

    signal clicked(var mouse)

    width: parent?.width ?? 0
    height: sub ? 38 : 29

    Item {
        id: lead

        x: 6
        width: root.sub ? 28 : 20
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Icon {
            anchors.centerIn: parent
            visible: !root.image || thumb.status !== Image.Ready
            icon: root.flash ? "check" : root.icon
            size: root.sub ? 19 : 16
            color: root.flash ? Theme.secondary : root.accent
        }

        ClippingRectangle {
            anchors.fill: parent
            visible: root.image !== "" && thumb.status === Image.Ready
            radius: 7
            color: "transparent"

            Image {
                id: thumb

                anchors.fill: parent
                source: root.image ? "file://" + root.image.split("/").map(encodeURIComponent).join("/") : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
        }
    }

    Column {
        anchors.left: lead.right
        anchors.leftMargin: 9
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Txt {
            width: parent.width
            text: root.text
            font.pixelSize: 12
            color: root.flash ? Theme.secondary : Theme.fg
        }

        Txt {
            visible: root.sub !== ""
            width: parent.width
            text: root.sub
            font.pixelSize: 10
            color: Theme.fgDim
        }
    }

    Hover {
        radius: 9
        onClicked: mouse => root.clicked(mouse)
    }
}

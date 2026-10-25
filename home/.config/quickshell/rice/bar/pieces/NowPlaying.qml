import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components

Card {
    id: root

    readonly property var p: Media.active

    implicitHeight: 74

    ClippingRectangle {
        id: art

        anchors.left: parent.left
        anchors.leftMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 52
        radius: 10
        color: Qt.alpha(Theme.primary, 0.15)

        Image {
            anchors.fill: parent
            source: root.p?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(104, 104)
        }

        Icon {
            anchors.centerIn: parent
            visible: !(root.p?.trackArtUrl)
            icon: "music_note"
            size: 24
            color: Theme.primary
        }
    }

    Column {
        anchors.left: art.right
        anchors.leftMargin: 11
        anchors.right: swap.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Txt {
            width: parent.width
            text: root.p?.trackTitle || "Nothing playing"
            font.weight: Font.DemiBold
        }

        Txt {
            width: parent.width
            visible: !!root.p
            text: root.p?.trackArtist || root.p?.identity || ""
            color: Theme.secondary
            font.pixelSize: 12
        }

        Txt {
            width: parent.width
            visible: !!root.p
            text: root.p?.identity ?? ""
            color: Theme.fgDim
            font.pixelSize: 10
        }
    }

    IconButton {
        id: swap

        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: Media.players.length > 1
        width: visible ? implicitWidth : 0
        icon: "swap_horiz"
        size: 16
        color: Theme.fgDim
        onClicked: Media.cycle()
    }
}

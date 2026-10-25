import QtQuick
import qs.services
import qs.components

// Previous / play-pause / next, and a seek bar you can click
Card {
    id: root

    readonly property var p: Media.active

    implicitHeight: 92
    opacity: p ? 1 : 0.5

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        spacing: 14

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "skip_previous"
            size: 22
            fill: 1
            disabled: !root.p?.canGoPrevious
            onClicked: root.p?.previous()
        }

        Rectangle {
            width: 46
            height: 46
            radius: 23
            color: Theme.primary
            scale: playArea.pressed ? 0.9 : 1

            Behavior on scale { Springy {} }

            Icon {
                anchors.centerIn: parent
                icon: root.p?.isPlaying ? "pause" : "play_arrow"
                size: 26
                fill: 1
                color: Theme.surface
            }

            MouseArea {
                id: playArea

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.p?.togglePlaying()
            }
        }

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "skip_next"
            size: 22
            fill: 1
            disabled: !root.p?.canGoNext
            onClicked: root.p?.next()
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.bottomMargin: 10
        height: 18

        Txt {
            id: pos

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Media.fmt(root.p?.position ?? 0)
            font.pixelSize: 10
            color: Theme.fgDim
        }

        Txt {
            id: len

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Media.fmt(root.p?.length ?? 0)
            font.pixelSize: 10
            color: Theme.fgDim
        }

        Rectangle {
            id: bar

            anchors.left: pos.right
            anchors.right: len.left
            anchors.margins: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Qt.alpha(Theme.fg, 0.12)

            Rectangle {
                height: parent.height
                radius: 2
                width: (root.p?.length ?? 0) > 0 ? parent.width * Math.min(1, (root.p.position ?? 0) / root.p.length) : 0
                color: Theme.secondary

                Behavior on width { NumberAnimation { duration: 900 } }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: root.p?.canSeek ?? false
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => root.p.position = Math.max(0, Math.min(1, (mouse.x - 6) / bar.width)) * root.p.length
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.components

// Your apps, dock style: pinned ones first, then anything else that's open. Icons swell under the pointer.
// Click to open it or jump to it (click again for its next window), middle-click for a new one, right-click to pin or unpin.
Card {
    id: root

    readonly property var pinned: Dock.apps.filter(a => a.pinned)
    readonly property var others: Dock.apps.filter(a => !a.pinned)
    property string tagText: ""
    property real tagX: 0

    implicitHeight: 84

    HoverHandler {
        id: track
    }

    // after a launch: let the icon bounce, then get out of the way
    Timer {
        id: closeSoon

        interval: 650
        onTriggered: Shell.close()
    }

    component DockIcon: Item {
        id: cell

        required property var modelData
        readonly property real centre: row.x + x + width / 2
        readonly property real mag: track.hovered ? Math.max(0, 1 - Math.abs(track.point.position.x - centre) / 110) : 0
        readonly property bool running: modelData.windows.length > 0
        readonly property bool focused: modelData.windows.includes(Hypr.activeWindow)
        property real hop: 0

        width: 46
        height: 46

        IconImage {
            anchors.fill: parent
            source: Dock.icon(cell.modelData)
            asynchronous: true
            scale: 1 + 0.36 * cell.mag
            transformOrigin: Item.Bottom
            transform: Translate { y: -cell.hop }

            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }

        // a dot per window (up to three); the app you're in gets a longer blue one
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 6
            spacing: 3

            Repeater {
                model: Math.min(3, cell.modelData.windows.length)

                Rectangle {
                    required property int index

                    width: cell.focused && index === 0 ? 10 : 4
                    height: 4
                    radius: 2
                    color: cell.focused ? Theme.primary : Qt.alpha(Theme.fg, 0.55)

                    Behavior on width { Springy {} }
                }
            }
        }

        SequentialAnimation {
            id: bounce

            NumberAnimation { target: cell; property: "hop"; to: 16; duration: 170; easing.type: Easing.OutQuad }
            NumberAnimation { target: cell; property: "hop"; to: 0; duration: 420; easing.type: Easing.OutBounce }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse) {
                    root.tagText = Dock.name(cell.modelData) + (cell.modelData.windows.length > 1 ? ` · ${cell.modelData.windows.length} windows` : "");
                    root.tagX = cell.centre;
                } else if (root.tagX === cell.centre) {
                    root.tagText = "";
                }
            }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    Dock.togglePin(cell.modelData);
                } else if (mouse.button === Qt.MiddleButton || !cell.running) {
                    bounce.restart();
                    Dock.launch(cell.modelData);
                    closeSoon.restart();
                } else {
                    Shell.close();
                    Dock.activate(cell.modelData);
                }
            }
        }
    }

    component Divider: Rectangle {
        width: 1
        height: 34
        y: 6
        color: Qt.alpha(Theme.line, 0.8)
    }

    Row {
        id: row

        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        spacing: 12

        Repeater {
            model: root.pinned

            DockIcon {}
        }

        Divider {
            visible: root.others.length > 0
        }

        Repeater {
            model: root.others

            DockIcon {}
        }

        Divider {}

        // every app: Caelestia's launcher
        Rectangle {
            id: all

            readonly property real mag: track.hovered ? Math.max(0, 1 - Math.abs(track.point.position.x - (row.x + x + width / 2)) / 110) : 0

            width: 46
            height: 46
            radius: 14
            color: Qt.alpha(Theme.fg, 0.07)
            scale: 1 + 0.36 * mag
            transformOrigin: Item.Bottom

            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

            Icon {
                anchors.centerIn: parent
                icon: "apps"
                size: 24
                color: Theme.fgDim
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: {
                    root.tagText = containsMouse ? "All apps" : "";
                    root.tagX = row.x + all.x + all.width / 2;
                }
                onClicked: {
                    Shell.close();
                    Ctl.drawer("launcher");
                }
            }
        }
    }

    // the name of whatever's under the pointer, floating above it
    Rectangle {
        z: 10
        x: Math.max(0, Math.min(root.width - width, root.tagX - width / 2))
        y: -height - 4
        width: tag.implicitWidth + 20
        height: 24
        radius: 12
        color: Theme.containerHighest
        border.width: 1
        border.color: Theme.edge
        opacity: root.tagText && track.hovered ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        Behavior on x {
            enabled: root.tagText !== ""
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Txt {
            id: tag

            anchors.centerIn: parent
            text: root.tagText
            font.pixelSize: 12
        }
    }
}

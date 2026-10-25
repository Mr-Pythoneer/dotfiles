import QtQuick
import qs.services
import qs.components

// The shelf: rest the pointer on the bottom edge of the screen (or Super+B) and it rises above the bar.
// Things to grab: your clipboard, recent files, folders, a scratch note, and a dock of your apps.
// It drops away when the pointer leaves, unless you've clicked into it (then Esc or a click outside closes it).
Item {
    id: root

    readonly property real cardW: (width - row.spacing * 3) / 4

    implicitHeight: col.implicitHeight

    Column {
        id: col

        width: parent.width
        spacing: 12

        Row {
            id: row

            width: parent.width
            height: 250
            spacing: 12

            ShelfClipboard {
                width: root.cardW
                height: parent.height
            }

            ShelfRecent {
                width: root.cardW
                height: parent.height
            }

            ShelfPlaces {
                width: root.cardW
                height: parent.height
            }

            ShelfNote {
                width: root.cardW
                height: parent.height
            }
        }

        ShelfDock {
            width: parent.width
        }
    }

    // touching the shelf makes it stay put (so you can type in the note); this only watches, the click still lands
    Item {
        anchors.fill: parent
        z: 100

        PointHandler {
            acceptedButtons: Qt.AllButtons
            onActiveChanged: if (active) Shell.hover = false
        }
    }
}

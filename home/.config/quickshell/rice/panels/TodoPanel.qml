import QtQuick
import qs.services
import qs.components
import qs.bar.pieces

// Your to-do list. Type and press Enter to add; click the circle to tick one off. The `todo` command edits the same list.
Column {
    id: root

    spacing: 10

    Item {
        width: parent.width
        height: 32

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Icon {
                icon: "checklist"
                size: 20
                color: Theme.secondary
            }

            Txt {
                text: "To-do"
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            Txt {
                text: Todo.open ? Todo.open + " left" : "all done"
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }

        PillButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: Todo.items.some(i => i.done)
            text: "Clear done"
            icon: "done_all"
            accent: Theme.secondary
            onClicked: Todo.clearDone()
        }
    }

    Field {
        id: field

        width: parent.width
        placeholder: "Add a to-do and press Enter"
        onAccepted: {
            Todo.add(text);
            text = "";
        }
        onEscaped: Shell.close()
        Component.onCompleted: input.forceActiveFocus()
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 430)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list

            width: parent.width
            spacing: 4

            Repeater {
                model: Todo.items.slice().sort((a, b) => a.done - b.done)

                Rectangle {
                    id: item

                    required property var modelData

                    width: list.width
                    height: Math.max(40, txt.implicitHeight + 18)
                    radius: Theme.radiusSmall
                    color: rowHover.hovered ? Theme.cardHover : Theme.card

                    HoverHandler {
                        id: rowHover
                    }

                    IconButton {
                        id: check

                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        icon: item.modelData.done ? "check_circle" : "radio_button_unchecked"
                        fill: item.modelData.done ? 1 : 0
                        size: 19
                        color: item.modelData.done ? Theme.secondary : Theme.fgDim
                        onClicked: Todo.toggle(item.modelData.id)
                    }

                    Txt {
                        id: txt

                        anchors.left: check.right
                        anchors.leftMargin: 2
                        anchors.right: del.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.text
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        font.strikeout: item.modelData.done
                        color: item.modelData.done ? Theme.fgDim : Theme.fg
                    }

                    IconButton {
                        id: del

                        anchors.right: parent.right
                        anchors.rightMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        icon: "close"
                        size: 16
                        color: Theme.fgDim
                        onClicked: Todo.remove(item.modelData.id)
                    }
                }
            }
        }
    }

    Txt {
        visible: Todo.items.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        topPadding: 6
        bottomPadding: 6
        text: "Nothing on the list"
        color: Theme.fgDim
    }

    Txt {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "in a terminal:  todo add <thing>   ·   todo done 2"
        font.pixelSize: 10
        color: Qt.alpha(Theme.fgDim, 0.8)
    }
}

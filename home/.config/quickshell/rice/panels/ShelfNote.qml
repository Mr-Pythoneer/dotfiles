import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// A scratch note that saves itself (~/.local/share/rice/note.txt). Click in and type.
ShelfCard {
    id: root

    property bool armed: false   // the clear button asks once before wiping

    title: "Note"
    icon: "edit_note"
    accent: Theme.purple

    tools: [
        IconButton {
            icon: "add_task"
            size: 16
            color: Theme.fgDim
            disabled: !edit.text.trim()
            // every line of the note becomes a to-do
            onClicked: {
                for (const line of edit.text.split("\n"))
                    Todo.add(line.replace(/^\s*([-*•]|\[ ?\])\s*/, ""));
                edit.text = "";
            }
        },
        IconButton {
            icon: "content_copy"
            size: 16
            color: Theme.fgDim
            disabled: !edit.text
            onClicked: Quickshell.execDetached(["wl-copy", "--", edit.text])
        },
        IconButton {
            icon: root.armed ? "delete_forever" : "delete"
            size: 16
            color: root.armed ? Theme.error : Theme.fgDim
            disabled: !edit.text
            onClicked: {
                if (!root.armed) {
                    root.armed = true;
                    disarm.restart();
                    return;
                }
                root.armed = false;
                edit.text = "";
            }
        }
    ]

    Timer {
        id: disarm

        interval: 2500
        onTriggered: root.armed = false
    }

    FileView {
        id: file

        path: Quickshell.env("HOME") + "/.local/share/rice/note.txt"
        atomicWrites: true
        printErrors: false
        onLoaded: if (!edit.activeFocus) edit.text = text()
    }

    // saves a moment after you stop typing
    Timer {
        id: saved

        interval: 600
        onTriggered: file.setText(edit.text)
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.alpha(Theme.fg, 0.04)
        border.width: 1
        border.color: edit.activeFocus ? Qt.alpha(Theme.purple, 0.6) : "transparent"

        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.margins: 10
        contentHeight: edit.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: edit

            width: flick.width
            wrapMode: TextEdit.Wrap
            color: Theme.fg
            selectionColor: Qt.alpha(Theme.purple, 0.4)
            font.family: Theme.font
            font.pixelSize: 12
            onTextChanged: if (activeFocus || !text) saved.restart()
            // keep the line you're typing on in view
            onCursorRectangleChanged: {
                if (cursorRectangle.y < flick.contentY)
                    flick.contentY = cursorRectangle.y;
                else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                    flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height;
            }

            Txt {
                visible: !edit.text && !edit.activeFocus
                text: "Jot something down…"
                font.pixelSize: 12
                color: Theme.fgDim
            }
        }

        MouseArea {
            width: flick.width
            height: Math.max(flick.height, edit.implicitHeight)
            cursorShape: Qt.IBeamCursor
            onPressed: mouse => {
                edit.forceActiveFocus();
                mouse.accepted = false;
            }
        }
    }
}

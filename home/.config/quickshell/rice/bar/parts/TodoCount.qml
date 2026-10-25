import QtQuick
import qs.services
import qs.components

// Open to-dos; click for the to-do list
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 30

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 4

        Icon {
            icon: "checklist"
            size: 17
            color: Theme.secondary
        }

        Txt {
            text: Todo.open
            font.weight: Font.DemiBold
            color: Todo.open ? Theme.secondary : Theme.fgDim
        }
    }

    Hover {
        onClicked: Shell.toggle("todo", root.monName)
    }
}

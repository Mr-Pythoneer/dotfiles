import QtQuick
import qs.services
import qs.components

// This month, today in orange; arrows flip months, the title jumps back to today
Card {
    id: root

    property int offset: 0
    readonly property date shown: new Date(Clock.now.getFullYear(), Clock.now.getMonth() + offset, 1)
    readonly property int startDay: (shown.getDay() + 6) % 7   // weeks start on Monday
    readonly property int days: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()

    readonly property int rows: Math.ceil((startDay + days) / 7)

    implicitHeight: 38 + 24 + rows * 28 + 8

    Item {
        id: head

        anchors.left: parent.left
        anchors.right: parent.right
        height: 38

        IconButton {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            icon: "chevron_left"
            size: 18
            onClicked: root.offset--
        }

        Txt {
            anchors.centerIn: parent
            text: Qt.formatDate(root.shown, "MMMM yyyy")
            font.weight: Font.DemiBold
            color: root.offset === 0 ? Theme.fg : Theme.primary

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.offset = 0
            }
        }

        IconButton {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            icon: "chevron_right"
            size: 18
            onClicked: root.offset++
        }
    }

    Grid {
        anchors.top: head.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 7
        columnSpacing: 2
        rowSpacing: 2

        Repeater {
            model: ["M", "T", "W", "T", "F", "S", "S"]

            Txt {
                required property string modelData
                required property int index

                width: 38
                height: 22
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: index >= 5 ? Theme.purple : Theme.fgDim
            }
        }

        Repeater {
            model: 42

            Rectangle {
                required property int index
                readonly property int day: index - root.startDay + 1
                readonly property bool inMonth: day >= 1 && day <= root.days
                readonly property bool today: root.offset === 0 && day === Clock.now.getDate()

                width: 38
                height: 26
                radius: 8
                color: today ? Theme.tertiary : "transparent"
                visible: index < root.rows * 7

                Txt {
                    anchors.centerIn: parent
                    text: parent.inMonth ? parent.day : ""
                    font.pixelSize: 12
                    font.weight: parent.today ? Font.Bold : Font.Normal
                    color: parent.today ? Theme.surface : (index % 7 >= 5 ? Theme.purple : Theme.fg)
                }
            }
        }
    }
}

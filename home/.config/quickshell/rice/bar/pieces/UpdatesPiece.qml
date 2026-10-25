import QtQuick
import qs.services
import qs.components

// From update-check's last report: how many updates, any Arch news to read first, and buttons to look or update
Card {
    id: root

    implicitHeight: col.implicitHeight + 22

    Column {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 11
        spacing: 8

        Row {
            spacing: 10

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: Qt.alpha(Updates.count ? Theme.tertiary : Theme.secondary, 0.16)

                Icon {
                    anchors.centerIn: parent
                    icon: Updates.count ? "system_update_alt" : "check_circle"
                    size: 19
                    fill: 1
                    color: Updates.count ? Theme.tertiary : Theme.secondary
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Txt {
                    text: Updates.count ? Updates.count + " update" + (Updates.count === 1 ? "" : "s") + " ready" : "Up to date"
                    font.weight: Font.DemiBold
                }

                Txt {
                    text: Updates.checked ? "checked " + Updates.checked : "not checked yet"
                    font.pixelSize: 11
                    color: Theme.fgDim
                }
            }
        }

        Txt {
            visible: Updates.news > 0
            width: parent.width
            text: "⚠ " + Updates.news + " Arch news post" + (Updates.news === 1 ? "" : "s") + " to read before updating"
            font.pixelSize: 11
            color: Theme.tertiary
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }

        Row {
            spacing: 8

            PillButton {
                text: "Details"
                icon: "description"
                onClicked: Ctl.terminal(["--hold", Ctl.bin + "update-check", "--show"])
            }

            PillButton {
                visible: Updates.count > 0
                text: "Update now"
                icon: "download"
                accent: Theme.tertiary
                filled: true
                onClicked: Ctl.terminal([Ctl.bin + Updates.updater])
            }
        }
    }
}

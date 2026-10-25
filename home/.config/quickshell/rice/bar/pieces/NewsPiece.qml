import QtQuick
import qs.services
import qs.components

// The latest news brief's headlines; click to open the full edition
Card {
    implicitHeight: col.implicitHeight + 22

    Column {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 11
        spacing: 7

        Row {
            spacing: 7

            Icon {
                icon: "newspaper"
                size: 17
                color: Theme.purple
            }

            Txt {
                text: News.title || "News brief"
                font.weight: Font.DemiBold
            }

            Txt {
                visible: News.built !== ""
                text: News.built ? "· " + Qt.formatTime(new Date(News.built), "h:mm ap") : ""
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }

        Repeater {
            model: News.headlines.slice(0, 4)

            Row {
                required property string modelData
                required property int index

                width: col.width
                spacing: 7

                Rectangle {
                    y: 6
                    width: 5
                    height: 5
                    radius: 2.5
                    color: [Theme.primary, Theme.secondary, Theme.tertiary, Theme.purple][index % 4]
                }

                Txt {
                    width: parent.width - 12
                    text: modelData
                    font.pixelSize: 12
                    color: Theme.fg
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
            }
        }

        Txt {
            visible: News.headlines.length === 0
            text: "No edition yet. The next one comes at 7:30 or 20:30."
            font.pixelSize: 11
            color: Theme.fgDim
            wrapMode: Text.WordWrap
            width: col.width
        }
    }

    Hover {
        radius: Theme.radiusSmall
        disabled: News.path === ""
        onClicked: Ctl.open(News.path)
    }
}

import QtQuick
import qs.services
import qs.components

Item {
    implicitHeight: 58

    Column {
        anchors.verticalCenter: parent.verticalCenter
        x: 4
        spacing: 2

        Txt {
            text: Qt.formatDate(Clock.now, "dddd")
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Theme.tertiary
        }

        Txt {
            readonly property int day: Math.floor((Clock.now - new Date(Clock.now.getFullYear(), 0, 0)) / 86400000)
            readonly property int week: {
                const d = new Date(Date.UTC(Clock.now.getFullYear(), Clock.now.getMonth(), Clock.now.getDate()));
                d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
                return Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
            }

            text: Qt.formatDate(Clock.now, "d MMMM yyyy") + "  ·  week " + week + ", day " + day
            font.pixelSize: 12
            color: Theme.fgDim
        }
    }
}

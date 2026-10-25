import QtQuick
import qs.services
import qs.components

Row {
    spacing: 8
    leftPadding: 4

    Icon {
        icon: "history"
        size: 17
        color: Theme.primary
    }

    Txt {
        text: "Up " + Clock.fmtUptime(Clock.uptime)
        font.weight: Font.DemiBold
    }

    Txt {
        text: Clock.bootTime ? "since " + Qt.formatDateTime(new Date(Clock.bootTime * 1000), "ddd h:mm ap") : ""
        font.pixelSize: 11
        color: Theme.fgDim
    }
}

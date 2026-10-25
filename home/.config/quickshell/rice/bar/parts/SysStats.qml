import QtQuick
import qs.services
import qs.components

// CPU, GPU and RAM: usage and temperature. Icons in the data colours (CPU blue, GPU teal, RAM mauve),
// numbers white; a temperature turns red only when it's hot. Click for the dashboard's System page.
Item {
    id: root

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 30

    component Stat: Row {
        id: stat

        property string icon
        property color accent
        property real value
        property string extra
        property bool alarm: false

        spacing: 5

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            icon: stat.icon
            size: 16
            fill: 1
            color: stat.accent
        }

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            width: 27   // fixed so the bar doesn't jiggle as the numbers change
            horizontalAlignment: Text.AlignRight
            text: Math.round(stat.value * 100) + "%"
            font.weight: Font.DemiBold
        }

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: stat.extra !== ""
            text: stat.extra
            font.pixelSize: Theme.smallText
            color: stat.alarm ? Theme.error : Theme.fgDim
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 16

        Stat {
            icon: "memory"
            accent: Theme.blue
            value: SysStats.cpu
            extra: SysStats.cpuTemp ? Math.round(SysStats.cpuTemp) + "°" : ""
            alarm: SysStats.hot(SysStats.cpuTemp)
        }

        Stat {
            icon: "monitor_heart"
            accent: Theme.teal
            value: SysStats.gpu
            extra: SysStats.gpuTemp ? Math.round(SysStats.gpuTemp) + "°" : ""
            alarm: SysStats.hot(SysStats.gpuTemp)
        }

        Stat {
            icon: "developer_board"
            accent: Theme.mauve
            value: SysStats.mem
            extra: SysStats.memUsed.toFixed(1) + " GB"
        }
    }

    Hover {
        onClicked: Shell.panel === "dashboard" ? Shell.close() : Shell.open("dashboard", "system")
    }
}

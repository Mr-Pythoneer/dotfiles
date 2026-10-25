import QtQuick
import qs.services
import qs.components

// The bar's system stats in more detail: what each chip is, temperature, and the last minute of usage
Column {
    id: root

    spacing: 10

    component Block: Item {
        id: block

        property string icon
        property string name
        property string detail
        property color accent
        property real value
        property var hist: []
        property bool alarm: false

        width: root.width
        height: 72

        Icon {
            id: icn

            x: 4
            y: 2
            icon: block.icon
            size: 17
            fill: 1
            color: block.accent
        }

        Txt {
            anchors.left: icn.right
            anchors.leftMargin: 8
            anchors.right: pct.left
            anchors.rightMargin: 8
            y: 2
            text: block.name
            font.weight: Font.DemiBold
        }

        Txt {
            id: pct

            anchors.right: parent.right
            anchors.rightMargin: 4
            y: 2
            text: Math.round(block.value * 100) + "%"
            font.weight: Font.Bold
        }

        Txt {
            x: 29
            y: 21
            width: parent.width - 33
            text: block.detail
            font.pixelSize: 11
            color: block.alarm ? Theme.error : Theme.fgDim
        }

        Graph {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            height: 28
            values: block.hist
            max: 1
            accent: block.accent
        }
    }

    Header {
        width: parent.width
        text: "System"
        icon: "monitoring"
    }

    Block {
        icon: "memory"
        name: "CPU"
        accent: Theme.blue
        value: SysStats.cpu
        hist: SysStats.cpuHist
        detail: SysStats.cpuName + (SysStats.cpuTemp ? "  ·  " + Math.round(SysStats.cpuTemp) + "°C" : "")
        alarm: SysStats.hot(SysStats.cpuTemp)
    }

    Block {
        icon: "monitor_heart"
        name: "GPU"
        accent: Theme.teal
        value: SysStats.gpu
        hist: SysStats.gpuHist
        detail: SysStats.gpuName + (SysStats.gpuTemp ? "  ·  " + Math.round(SysStats.gpuTemp) + "°C" + (SysStats.gpuTempShared ? " (chip, shared with CPU)" : "") : "")
        alarm: SysStats.hot(SysStats.gpuTemp)
    }

    Block {
        icon: "developer_board"
        name: "Memory"
        accent: Theme.mauve
        value: SysStats.mem
        hist: SysStats.memHist
        detail: SysStats.memUsed.toFixed(1) + " of " + SysStats.memTotal.toFixed(0) + " GB in use"
    }

    Txt {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Click for the System page"
        font.pixelSize: 10
        color: Theme.fgDim
        opacity: 0.7
    }
}

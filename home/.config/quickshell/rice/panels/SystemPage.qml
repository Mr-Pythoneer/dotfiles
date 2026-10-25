import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Services
import qs.services
import qs.components
import qs.bar.pieces

// System: CPU, memory, GPU and network with a minute of history, your disks, battery, and the busiest processes.
// History is only collected while this page is open.
Grid {
    id: root

    property var cpuHist: []
    property var memHist: []
    property var gpuHist: []
    property var disks: []      // [{mount, used, size}]
    readonly property real cardW: (width - columnSpacing * 2) / 3
    readonly property real cardH: (height - rowSpacing) / 2

    function push(arr: var, v: real): var {
        const a = arr.concat([v]);
        return a.length > 40 ? a.slice(a.length - 40) : a;
    }

    function gb(bytes: real): string {
        return bytes >= 1e12 ? (bytes / 1e12).toFixed(2) + " TB" : (bytes / 1e9).toFixed(0) + " GB";
    }

    function speed(bps: real): string {
        return bps > 1048576 ? (bps / 1048576).toFixed(1) + " MB/s" : (bps / 1024).toFixed(0) + " KB/s";
    }

    columns: 3
    columnSpacing: 12
    rowSpacing: 12

    ServiceRef { service: Cpu }
    ServiceRef { service: Memory }
    ServiceRef { service: Gpu }
    ServiceRef { service: NetworkUsage }

    Timer {
        interval: 1500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.cpuHist = root.push(root.cpuHist, Cpu.percentage);
            root.memHist = root.push(root.memHist, Memory.percentage);
            root.gpuHist = root.push(root.gpuHist, Gpu.percentage);
            Dev.refreshProcs();
        }
    }

    Process {
        running: true
        command: ["df", "-B1", "--output=target,used,size", "/", "/mnt/data"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                root.disks = text.trim().split("\n").slice(1).map(l => l.trim().split(/\s+/)).filter(f => f.length === 3 && !seen.has(f[0]) && seen.add(f[0])).map(f => ({ mount: f[0], used: parseFloat(f[1]), size: parseFloat(f[2]) }));
            }
        }
    }

    component StatCard: Card {
        id: sc

        property string title
        property string icon
        property color accent: Theme.primary
        property real value: 0
        property string big: Math.round(value * 100) + "%"
        property string sub
        property var hist: []

        width: root.cardW
        height: root.cardH

        Row {
            x: 14
            y: 12
            spacing: 7

            Icon {
                icon: sc.icon
                size: 17
                color: sc.accent
            }

            Txt {
                text: sc.title
                font.weight: Font.Bold
            }
        }

        Txt {
            x: 14
            y: 40
            text: sc.big
            font.pixelSize: 30
            font.weight: Font.Bold
            color: sc.accent
        }

        Txt {
            x: 14
            y: 80
            width: parent.width - 28
            text: sc.sub
            font.pixelSize: 11
            color: Theme.fgDim
        }

        Graph {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: parent.height - 120
            values: sc.hist
            max: 1
            accent: sc.accent
        }
    }

    StatCard {
        title: "CPU"
        icon: "memory"
        accent: Theme.blue
        value: Cpu.percentage
        sub: Cpu.name + (Cpu.temperature ? "  ·  " + Math.round(Cpu.temperature) + "°C" : "")
        hist: root.cpuHist
    }

    StatCard {
        title: "Memory"
        icon: "developer_board"
        accent: Theme.mauve
        value: Memory.percentage
        sub: (Memory.used / 1048576).toFixed(1) + " of " + (Memory.total / 1048576).toFixed(0) + " GB in use"
        hist: root.memHist
    }

    StatCard {
        title: "GPU"
        icon: "monitor_heart"
        accent: Theme.teal
        value: Gpu.percentage
        sub: (Gpu.name || "Intel Arc") + (Gpu.temperature ? "  ·  " + Math.round(Gpu.temperature) + "°C" : "")
        hist: root.gpuHist
    }

    // network: both directions on one graph
    Card {
        width: root.cardW
        height: root.cardH

        Row {
            x: 14
            y: 12
            spacing: 7

            Icon {
                icon: "swap_vert"
                size: 17
                color: Theme.blue
            }

            Txt {
                text: "Network"
                font.weight: Font.Bold
            }
        }

        Column {
            x: 14
            y: 40
            spacing: 2

            Txt {
                text: "↓ " + root.speed(NetworkUsage.downloadSpeed)
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Theme.blue
            }

            Txt {
                text: "↑ " + root.speed(NetworkUsage.uploadSpeed)
                font.pixelSize: 13
                color: Theme.mauve
            }
        }

        Graph {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: parent.height - 120
            values: NetworkUsage.downloadBuffer ?? []
            max: 1
            accent: Theme.blue
        }

        Graph {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: parent.height - 120
            values: NetworkUsage.uploadBuffer ?? []
            max: { let m = 1; const b = NetworkUsage.downloadBuffer ?? []; for (let i = 0; i < b.length; i++) m = Math.max(m, b[i]); return m; }
            accent: Theme.mauve
        }
    }

    // disks and battery
    Card {
        width: root.cardW
        height: root.cardH

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Row {
                spacing: 7

                Icon {
                    icon: "storage"
                    size: 17
                    color: Theme.tertiary
                }

                Txt {
                    text: "Disks"
                    font.weight: Font.Bold
                }
            }

            Repeater {
                model: root.disks

                Column {
                    required property var modelData

                    width: parent.width
                    spacing: 4

                    Item {
                        width: parent.width
                        height: 14

                        Txt {
                            text: modelData.mount === "/" ? "System  /" : modelData.mount === "/mnt/data" ? "D: drive  /mnt/data" : modelData.mount
                            font.pixelSize: 11
                        }

                        Txt {
                            anchors.right: parent.right
                            text: root.gb(modelData.used) + " / " + root.gb(modelData.size)
                            font.pixelSize: 11
                            color: Theme.fgDim
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Qt.alpha(Theme.fg, 0.1)

                        Rectangle {
                            width: parent.width * (modelData.used / modelData.size)
                            height: parent.height
                            radius: 3
                            color: Theme.fill(modelData.used / modelData.size)
                        }
                    }
                }
            }

            Item { width: 1; height: 4 }

            Row {
                spacing: 7

                Icon {
                    icon: "battery_full"
                    size: 17
                    color: Theme.secondary
                }

                Txt {
                    text: "Battery " + Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "%"
                    font.weight: Font.Bold
                }
            }

            Txt {
                width: parent.width
                wrapMode: Text.WordWrap
                text: (BatteryLife.status === "Discharging" && BatteryLife.watts > 0.05 ? "Drawing " + BatteryLife.watts.toFixed(1) + " W" + (BatteryLife.secondsLeft > 0 ? "  ·  " + (BatteryLife.measured ? "" : "about ") + Math.floor(BatteryLife.secondsLeft / 3600) + "h " + Math.round(BatteryLife.secondsLeft % 3600 / 60) + "m left" : "") : "Not drawing from the battery") + ((UPower.displayDevice?.healthSupported ?? false) ? "  ·  health " + Math.round(UPower.displayDevice.healthPercentage) + "%" : "")
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }
    }

    // busiest processes right now
    Card {
        width: root.cardW
        height: root.cardH

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Item {
                width: parent.width
                height: 18

                Row {
                    spacing: 7

                    Icon {
                        icon: "list"
                        size: 17
                        color: Theme.fgDim
                    }

                    Txt {
                        text: "Busiest"
                        font.weight: Font.Bold
                    }
                }

                Txt {
                    anchors.right: parent.right
                    text: "CPU   MEM"
                    font.pixelSize: 10
                    color: Theme.fgDim
                }
            }

            Repeater {
                model: Dev.procs

                Item {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 22

                    Txt {
                        width: parent.width - 90
                        text: modelData.name
                        font.pixelSize: 12
                        color: index === 0 ? Theme.fg : Theme.fgDim
                    }

                    Txt {
                        anchors.right: parent.right
                        text: modelData.cpu.toFixed(0).padStart(3, " ") + "%  " + modelData.mem.toFixed(0).padStart(3, " ") + "%"
                        font.pixelSize: 12
                        color: modelData.cpu > 50 ? Theme.error : Theme.fgDim
                    }
                }
            }

            PillButton {
                text: "Open btop"
                icon: "monitoring"
                accent: Theme.primary
                onClicked: {
                    Shell.close();
                    Ctl.script("sysmon-toggle");
                }
            }
        }
    }
}

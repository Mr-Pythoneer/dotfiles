pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services

// CPU, GPU and memory for the middle of the bar: usage (0-1), temperatures (°C), and the last minute of
// history for its popout. Keeps Caelestia's Cpu/Gpu/Memory services polling while the bar is up.
Singleton {
    id: root

    readonly property real cpu: Cpu.percentage
    readonly property real gpu: Gpu.percentage
    readonly property real mem: Memory.percentage
    readonly property real cpuTemp: Cpu.temperature
    // Lunar Lake's graphics share the CPU's chip and have no sensor of their own (xe has no hwmon, thinkpad's
    // GPU slot reads ENXIO), so the GPU falls back to the package temperature
    readonly property real gpuTemp: Gpu.temperature || pkgTemp
    readonly property bool gpuTempShared: !Gpu.temperature && pkgTemp > 0
    property real pkgTemp: 0
    property string pkgPath: ""
    readonly property real memUsed: Memory.used / 1048576     // GB
    readonly property real memTotal: Memory.total / 1048576
    readonly property string cpuName: Cpu.name
    readonly property string gpuName: Gpu.name || "Intel Arc"
    property var cpuHist: []
    property var gpuHist: []
    property var memHist: []

    // hot enough to mention: the only time a number on the bar turns red
    function hot(temp: real): bool {
        return temp >= 85;
    }

    function push(arr: var, v: real): var {
        const a = arr.concat([v]);
        return a.length > 30 ? a.slice(a.length - 30) : a;
    }

    // coretemp's "Package id 0" sensor; hwmon numbers move between boots, so look it up by name
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = coretemp ] || continue; for l in $h/temp*_label; do grep -q '^Package' $l && echo ${l%_label}_input && exit; done; done"]
        stdout: StdioCollector {
            onStreamFinished: root.pkgPath = text.trim()
        }
    }

    FileView {
        id: pkg

        path: root.pkgPath
        printErrors: false
        onLoaded: root.pkgTemp = (parseInt(text()) || 0) / 1000
    }

    ServiceRef { service: Cpu }
    ServiceRef { service: Gpu }
    ServiceRef { service: Memory }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.pkgPath)
                pkg.reload();
            root.cpuHist = root.push(root.cpuHist, root.cpu);
            root.gpuHist = root.push(root.gpuHist, root.gpu);
            root.memHist = root.push(root.memHist, root.mem);
        }
    }
}

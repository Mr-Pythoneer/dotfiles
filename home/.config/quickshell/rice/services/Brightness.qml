pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness. The backlight's sysfs file is watched, so changes made anywhere
// (the F5/F6 keys run brightnessctl) show up straight away without polling.
Singleton {
    id: root

    property string device: ""
    property real value: 0
    property int max: 0
    readonly property bool available: device !== "" && max > 0

    function set(v: real): void {
        root.value = Math.max(0.01, Math.min(1, v));
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(root.value * 100) + "%"]);
    }

    function refresh(): void {
        nowFile.reload();
    }

    // the first backlight, same as brightnessctl picks
    Process {
        running: true
        command: ["ls", "/sys/class/backlight"]
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim().split("\n")[0] ?? ""
        }
    }

    FileView {
        id: maxFile

        path: root.device ? `/sys/class/backlight/${root.device}/max_brightness` : ""
        onLoaded: root.max = parseInt(text()) || 0
    }

    FileView {
        id: nowFile

        path: root.available ? `/sys/class/backlight/${root.device}/brightness` : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const cur = parseInt(text());
            if (!isNaN(cur))
                root.value = cur / root.max;
        }
    }
}

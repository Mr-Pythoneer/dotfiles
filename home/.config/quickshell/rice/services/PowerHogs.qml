pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Apps draining the battery (~/.local/bin/power-hogs): on battery, anything averaging 15% of a core
// or more over 30 s. Shown as a warning mark on the battery icon and a list with Quit in its popout.
// The watcher only reads the AC state while plugged in, so it costs nothing there.
Singleton {
    id: root

    property bool onBattery: false
    property var hogs: []
    readonly property var drains: onBattery ? hogs : []
    readonly property bool warn: drains.length > 0
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/power-hogs"   // not on Hyprland's PATH

    function amount(cpu: real): string {
        return cpu >= 100 ? (cpu / 100).toFixed(1) + " cores" : Math.round(cpu) + "% CPU";
    }

    function quit(hog: var): void {
        Quickshell.execDetached([root.bin, "quit", hog.kind, hog.id]);
        hogs = hogs.filter(h => h.id !== hog.id);
    }

    Process {
        id: watcher

        running: true
        command: [root.bin, "watch"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.onBattery = d.onBattery;
                    root.hogs = d.hogs;
                } catch (e) {}
            }
        }
        onExited: retry.start()
    }

    Timer {
        id: retry

        interval: 5000
        onTriggered: watcher.running = true
    }
}

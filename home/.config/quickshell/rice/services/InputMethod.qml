pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// fcitx5's state for the focused window: 2 = Chinese input on, 1 = English, 0 = no text box focused.
// Checked when the focused window changes, when Caps Lock (fcitx's switch key) changes, and every 6 s.
Singleton {
    id: root

    property int state: 0
    readonly property bool chinese: state === 2

    function refresh(): void {
        if (!proc.running)
            proc.running = true;
    }

    Process {
        id: proc

        command: ["fcitx5-remote"]
        stdout: StdioCollector {
            onStreamFinished: root.state = parseInt(text.trim()) || 0
        }
    }

    Connections {
        target: Hypr

        function onActiveWindowChanged(): void {
            root.refresh();
        }

        function onCapsLockChanged(): void {
            root.refresh();
        }
    }

    Timer {
        interval: 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}

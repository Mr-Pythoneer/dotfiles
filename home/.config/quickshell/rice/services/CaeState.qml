pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// On/off states that live in Caelestia: do not disturb, keep awake, game mode. Asked over its IPC when the control centre opens.
Singleton {
    id: root

    property bool dnd: false
    property bool awake: false
    property bool gameMode: false

    function refresh(): void {
        dndProc.running = true;
        awakeProc.running = true;
        gameProc.running = true;
    }

    function toggle(target: string): void {
        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", target, target === "notifs" ? "toggleDnd" : "toggle"]);
        if (target === "notifs")
            root.dnd = !root.dnd;
        else if (target === "idleInhibitor")
            root.awake = !root.awake;
        else
            root.gameMode = !root.gameMode;
        later.restart();
    }

    Timer {
        id: later

        interval: 700
        onTriggered: root.refresh()
    }

    Process {
        id: dndProc

        command: ["qs", "-c", "caelestia", "ipc", "call", "notifs", "isDndEnabled"]
        stdout: StdioCollector {
            onStreamFinished: root.dnd = text.trim() === "true"
        }
    }

    Process {
        id: awakeProc

        command: ["qs", "-c", "caelestia", "ipc", "call", "idleInhibitor", "isEnabled"]
        stdout: StdioCollector {
            onStreamFinished: root.awake = text.trim() === "true"
        }
    }

    Process {
        id: gameProc

        command: ["qs", "-c", "caelestia", "ipc", "call", "gameMode", "isEnabled"]
        stdout: StdioCollector {
            onStreamFinished: root.gameMode = text.trim() === "true"
        }
    }
}

pragma Singleton

import QtQuick
import Quickshell

// Runs things: Caelestia's own panels over its IPC, and the user's scripts in ~/.local/bin
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/"

    function caelestia(target: string, fn: string, args: var): void {
        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", target, fn, ...(args ?? [])]);
    }

    function drawer(name: string): void {
        caelestia("drawers", "toggle", [name]);
    }

    function run(cmd: var): void {
        Quickshell.execDetached(cmd);
    }

    function script(name: string, args: var): void {
        Quickshell.execDetached([bin + name, ...(args ?? [])]);
    }

    function terminal(cmd: var): void {
        Quickshell.execDetached(["kitty", ...cmd]);
    }

    function open(url: string): void {
        Quickshell.execDetached(["xdg-open", url]);
    }
}

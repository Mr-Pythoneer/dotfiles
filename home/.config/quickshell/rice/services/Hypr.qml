pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Services

// Windows, workspaces and monitors. Workspace numbers come from each window's own Hyprland data,
// because Quickshell's workspace objects don't get their ids on this Hyprland version.
Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels.values
    readonly property var monitors: Hyprland.monitors.values
    readonly property HyprlandToplevel activeWindow: Hyprland.activeToplevel
    readonly property bool usingLua: Hyprland.usingLua

    // keyboard state (Caps/Num Lock, layout) from Caelestia's Hyprland helper
    readonly property var keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string keymap: keyboard?.activeKeymap ?? ""

    function wsOf(t: var): int {
        return t?.lastIpcObject?.workspace?.id ?? -1;
    }

    function monitorOf(name: string): var {
        return root.monitors.find(m => m.name === name)?.lastIpcObject ?? null;
    }

    function activeWs(monName: string): int {
        return monitorOf(monName)?.activeWorkspace?.id ?? 1;
    }

    function monitorNameOfWindow(t: var): string {
        const id = t?.lastIpcObject?.monitor;
        return root.monitors.find(m => m.lastIpcObject?.id === id)?.name ?? "";
    }

    readonly property string focusedMonitor: root.monitors.find(m => m.lastIpcObject?.focused)?.name ?? (root.monitors[0]?.name ?? "")

    // windows that count: mapped, on a normal workspace
    function realWindows(): var {
        return root.toplevels.filter(t => wsOf(t) > 0 && t.lastIpcObject?.mapped !== false);
    }

    function windowsOn(ws: int): var {
        return realWindows().filter(t => wsOf(t) === ws);
    }

    function windowsOnMonitor(monName: string): var {
        return realWindows().filter(t => monitorNameOfWindow(t) === monName).sort((a, b) => wsOf(a) - wsOf(b));
    }

    // workspaces on this monitor that have windows, plus the one it's showing
    function workspacesFor(monName: string): var {
        const ids = new Set(windowsOnMonitor(monName).map(t => wsOf(t)));
        ids.add(activeWs(monName));
        return [...ids].filter(id => id > 0).sort((a, b) => a - b);
    }

    function hasFullscreen(monName: string): bool {
        const ws = activeWs(monName);
        return realWindows().some(t => wsOf(t) === ws && (t.lastIpcObject?.fullscreen ?? 0) > 0);
    }

    function dispatch(cmd: string): void {
        Hyprland.dispatch(cmd);
    }

    function focusWorkspace(id: var): void {
        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${id}" })` : `workspace ${id}`);
    }

    function focusWindow(t: var): void {
        const a = t?.lastIpcObject?.address;
        if (a)
            dispatch(usingLua ? `hl.dsp.focus({ window = "address:${a}" })` : `focuswindow address:${a}`);
    }

    function appIcon(t: var): string {
        const id = t?.wayland?.appId || t?.lastIpcObject?.class || "";
        const entry = DesktopEntries.heuristicLookup(id);
        return Quickshell.iconPath(entry?.icon || id.toLowerCase(), "application-x-executable");
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;
            if (["workspace", "moveworkspace", "focusedmon", "activespecial", "monitoradded", "monitorremoved", "renameworkspace"].includes(n))
                Hyprland.refreshMonitors();
            if (["openwindow", "closewindow", "movewindow", "fullscreen", "changefloatingmode", "activewindow", "workspace", "moveworkspace"].includes(n))
                Hyprland.refreshToplevels();
        }
    }

    HyprExtras {
        id: extras
    }

    // Caps/Num Lock have no Hyprland event, so look every 1.5 s (an in-process socket request, no new processes)
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: extras.refreshDevices()
    }

    Timer {
        interval: 600
        running: true
        onTriggered: {
            Hyprland.refreshMonitors();
            Hyprland.refreshToplevels();
            extras.refreshDevices();
        }
    }
}

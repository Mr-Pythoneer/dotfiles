pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Which panel is open, and on which screen. Panels open on the monitor that has focus.
Singleton {
    id: root

    property string panel: ""
    property string screen: ""
    property string page: ""
    property bool keyboard: false   // a text box in a popout wants typing (Wi-Fi password)
    property bool hover: false      // the panel came up because the pointer touched the bottom edge; it goes when the pointer leaves

    function toggle(name: string, onScreen: string): void {
        const s = onScreen || Hypr.focusedMonitor;
        if (root.panel === name && root.screen === s) {
            close();
            return;
        }
        root.screen = s;
        root.hover = false;
        root.panel = name;
    }

    // opened by touching the bottom edge: only when nothing else is open
    function peek(name: string, onScreen: string): void {
        if (root.panel !== "")
            return;
        root.screen = onScreen;
        root.page = "";
        root.hover = true;
        root.panel = name;
    }

    function open(name: string, page: string): void {
        root.screen = Hypr.focusedMonitor;
        root.page = page ?? "";
        root.hover = false;
        root.panel = name;
    }

    function close(): void {
        root.hover = false;
        root.panel = "";
    }
}

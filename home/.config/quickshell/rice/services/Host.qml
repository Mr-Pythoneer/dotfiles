pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string user: Quickshell.env("USER") ?? "you"
    property string hostname: ""
    readonly property string avatar: Quickshell.env("HOME") + "/.face"
    readonly property string greeting: {
        const h = Clock.now.getHours();
        return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    }

    FileView {
        path: "/etc/hostname"
        onLoaded: root.hostname = text().trim()
    }
}

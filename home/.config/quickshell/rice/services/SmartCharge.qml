pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// smart-charge's daemon writes its status here; its modes are auto (hold 80%, learn), full and limit
Singleton {
    id: root

    property string mode: "auto"
    property string summary: ""
    property bool ready: true
    property int limit: 80
    readonly property bool installed: summary !== ""

    function set(m: string): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/smart-charge", m]);
        root.mode = m;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/smart-charge/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.mode = d.mode ?? "auto";
                root.summary = d.summary ?? "";
                root.ready = d.ready ?? true;
                root.limit = d.limit ?? 80;
            } catch (e) {}
        }
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caelestia owns the notifications; it saves the ones still in its notification centre to this file
Singleton {
    id: root

    property var list: []
    readonly property int count: list.length

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/notifs.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.list = Array.isArray(d) ? d : [];
            } catch (e) {
                root.list = [];
            }
        }
        onLoadFailed: root.list = []
    }
}

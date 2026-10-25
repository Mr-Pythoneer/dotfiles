pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The bar layout from the rice builder (layout.json next to shell.qml); edits to the file apply live
Singleton {
    id: root

    property var left: []
    property var center: []
    property var right: []
    property string spacing: "normal"
    property string style: "islands"    // "islands" = three floating pills, "edge" = one full-width strip

    FileView {
        path: Quickshell.shellDir + "/layout.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.left = d.zones?.left ?? [];
                root.center = d.zones?.center ?? [];
                root.right = d.zones?.right ?? [];
                root.spacing = d.spacing ?? "normal";
                root.style = d.style ?? "islands";
            } catch (e) {
                console.warn("rice: layout.json isn't valid:", e);
            }
        }
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// A plain to-do list in ~/.local/share/rice/todo.json, shared with the `todo` command
Singleton {
    id: root

    property var items: []
    readonly property int open: items.filter(i => !i.done).length

    function save(): void {
        file.setText(JSON.stringify(root.items, null, 1));
    }

    function add(text: string): void {
        const t = text.trim();
        if (!t)
            return;
        root.items = [...root.items, { id: Date.now().toString(36), text: t, done: false, created: new Date().toISOString() }];
        save();
    }

    function toggle(id: string): void {
        root.items = root.items.map(i => i.id === id ? Object.assign({}, i, { done: !i.done }) : i);
        save();
    }

    function remove(id: string): void {
        root.items = root.items.filter(i => i.id !== id);
        save();
    }

    function clearDone(): void {
        root.items = root.items.filter(i => !i.done);
        save();
    }

    FileView {
        id: file

        path: Quickshell.env("HOME") + "/.local/share/rice/todo.json"
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.items = Array.isArray(d) ? d : [];
            } catch (e) {
                root.items = [];
            }
        }
        onLoadFailed: root.items = []
    }
}

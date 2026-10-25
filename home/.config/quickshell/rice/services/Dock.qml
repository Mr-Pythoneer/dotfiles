pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shelf's dock: pinned apps (~/.local/share/rice/dock.json) plus whatever else has a window open.
// The first pins come from what you launch most in Caelestia's launcher.
Singleton {
    id: root

    readonly property var defaults: ["zen", "google-chrome", "kitty", "superfile", "com.valvesoftware.Steam", "org.mozilla.Thunderbird", "spun", "discord", "localsend", "com.microsoft.VSCode", "libreoffice-startcenter"]
    property var pins: defaults

    // [{ key, entry, windows, pinned }], pinned first in pin order, then open apps that aren't pinned
    readonly property var apps: {
        DesktopEntries.applications.values; // re-run once the app list has loaded
        const pinned = root.pins.map(id => DesktopEntries.byId(id)).filter(e => e);
        const out = pinned.map(e => ({ key: e.id, entry: e, windows: [], pinned: true }));
        for (const t of Hypr.realWindows().sort((a, b) => Hypr.wsOf(a) - Hypr.wsOf(b))) {
            const cls = t.wayland?.appId || t.lastIpcObject?.class || "";
            if (!cls)
                continue;
            let app = out.find(a => a.entry && root.matches(a.entry, cls)) ?? out.find(a => !a.entry && a.key === cls);
            if (!app) {
                const e = DesktopEntries.heuristicLookup(cls);
                app = { key: e?.id ?? cls, entry: e, windows: [], pinned: false };
                out.push(app);
            }
            app.windows.push(t);
        }
        return out;
    }

    function matches(e: var, cls: string): bool {
        const c = cls.toLowerCase();
        const id = e.id.toLowerCase();
        return id === c || (e.startupClass ?? "").toLowerCase() === c || id.endsWith("." + c) || DesktopEntries.heuristicLookup(cls)?.id === e.id;
    }

    function icon(app: var): string {
        return Quickshell.iconPath(app.entry?.icon || app.key.toLowerCase(), "application-x-executable");
    }

    function name(app: var): string {
        return app.entry?.name || app.key;
    }

    // not running: start it. Running: jump to its window, and on the next click to its next one
    function activate(app: var): void {
        if (!app.windows.length) {
            launch(app);
            return;
        }
        const i = app.windows.indexOf(Hypr.activeWindow);
        Hypr.focusWindow(app.windows[(i + 1) % app.windows.length]);
    }

    function launch(app: var): void {
        const e = app.entry;
        if (!e)
            return;
        if (e.runInTerminal)
            Quickshell.execDetached({ command: ["kitty", "-e", ...e.command], workingDirectory: e.workingDirectory });
        else
            e.execute();
    }

    function togglePin(app: var): void {
        root.pins = root.pins.includes(app.key) ? root.pins.filter(p => p !== app.key) : [...root.pins, app.key];
        file.setText(JSON.stringify(root.pins, null, 1));
    }

    FileView {
        id: file

        path: Quickshell.env("HOME") + "/.local/share/rice/dock.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false   // no file yet = the default pins
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (Array.isArray(d))
                    root.pins = d;
            } catch (e) {}
        }
    }
}

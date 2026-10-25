pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Claude Code sessions, from their terminal titles: a spinning ◐◓◑◒ means working, ✳ means it's waiting for you
Singleton {
    id: root

    readonly property var sessions: Hypr.toplevels.filter(t => /^[◐◓◑◒✳✢✶✻✽·]\s/.test(t.title ?? "")).map(t => ({
                window: t,
                title: (t.title ?? "").replace(/^\S+\s+/, ""),
                waiting: /^✳/.test(t.title ?? "")
            }))
    readonly property int count: sessions.length
    readonly property int waiting: sessions.filter(s => s.waiting).length
    property int cycleIndex: 0

    // jump to a session that's waiting, or go round them in turn
    function focusNext(): void {
        if (!count)
            return;
        const w = sessions.find(s => s.waiting);
        const s = w ?? sessions[cycleIndex++ % count];
        Hypr.focusWindow(s.window);
    }
}

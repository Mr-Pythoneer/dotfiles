pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The player the bar talks about: whatever is playing, else the last one that played
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer manual: null
    property MprisPlayer last: null
    readonly property MprisPlayer active: (manual && players.includes(manual)) ? manual : (players.find(p => p.isPlaying) ?? (last && players.includes(last) ? last : players[0] ?? null))
    readonly property bool playing: active?.isPlaying ?? false

    onActiveChanged: if (active?.isPlaying) last = active

    function fmt(sec: real): string {
        if (!isFinite(sec) || sec < 0)
            sec = 0;
        const m = Math.floor(sec / 60), s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function cycle(): void {
        if (players.length < 2)
            return;
        manual = players[(players.indexOf(active) + 1) % players.length];
    }

    // MPRIS doesn't push position updates, so ask for them while playing
    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.active?.positionChanged()
    }
}

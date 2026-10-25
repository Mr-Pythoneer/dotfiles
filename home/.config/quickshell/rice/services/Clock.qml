pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The time, uptime, and the stopwatch/timer that lives in the clock's popout (keeps running when it closes)
Singleton {
    id: root

    property date now: new Date()
    property real bootTime: 0

    readonly property string hm: {
        const h = now.getHours() % 12 || 12;
        return h + ":" + Qt.formatTime(now, "mm");
    }
    readonly property string seconds: Qt.formatTime(now, "ss")
    readonly property string ampm: now.getHours() < 12 ? "am" : "pm"
    readonly property real uptime: bootTime ? (now.getTime() / 1000 - bootTime) : 0

    function fmtUptime(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }

    // stopwatch counts up; timer counts down from `timerSet`
    property string mode: "stopwatch"
    property bool running: false
    property real startedAt: 0
    property real banked: 0          // ms counted before the last pause
    property real timerSet: 5 * 60 * 1000
    readonly property real elapsed: banked + (running ? now.getTime() - startedAt : 0)
    readonly property real shown: mode === "timer" ? Math.max(0, timerSet - elapsed) : elapsed
    readonly property bool active: running || banked > 0

    function fmtMs(ms: real): string {
        const t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    function start(): void {
        if (running)
            return;
        startedAt = Date.now();
        running = true;
    }

    function pause(): void {
        if (!running)
            return;
        banked += Date.now() - startedAt;
        running = false;
    }

    function reset(): void {
        running = false;
        banked = 0;
    }

    function setMode(m: string): void {
        reset();
        mode = m;
    }

    function addTimer(ms: real): void {
        timerSet = Math.max(60000, timerSet + ms);
    }

    onShownChanged: {
        if (mode === "timer" && running && shown <= 0) {
            reset();
            Quickshell.execDetached(["notify-send", "-a", "Clock", "-i", "alarm", "Time's up", "Your " + fmtMs(timerSet) + " timer finished"]);
            Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]);
        }
    }

    // in efficiency mode the clock only wakes up when the minute changes (the bar hides the seconds)
    Timer {
        interval: root.running ? 250 : Power.eco ? (60 - root.now.getSeconds()) * 1000 : 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    FileView {
        path: "/proc/stat"
        onLoaded: {
            const m = text().match(/^btime (\d+)/m);
            if (m)
                root.bootTime = parseInt(m[1]);
        }
    }
}

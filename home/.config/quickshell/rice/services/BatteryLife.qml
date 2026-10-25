pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "batterylife.js" as BL

// How much battery time is left, from what the laptop has really been using lately (maths in batterylife.js).
// Replaces UPower's figure, which divides by the draw of this very second, so it jumped by hours whenever a
// page loaded or a video paused, and which counted charging up to 100% even when smart charge stops at 80%.
// Counts down to 2%, where the system shuts down (PercentageAction in /etc/UPower/UPower.conf).
Singleton {
    id: root

    readonly property string dir: "/sys/class/power_supply/BAT0"
    property var est: null
    property real energy: 0         // Wh now
    property real full: 0           // Wh at 100%
    property int limit: 100         // % where charging stops (smart charge)
    property real prior: 0          // last measured discharge rate, W (remembered across unplugs)
    property real savedAt: 0

    readonly property string status: est?.status ?? ""
    readonly property bool measured: est?.ready ?? false        // false = still a first guess
    readonly property real watts: est?.watts ?? 0                // the draw right now, smoothed
    readonly property real secondsLeft: BL.secondsLeft(est, energy, full, 2)
    readonly property real secondsToFull: BL.secondsToLimit(est, energy, full, limit)

    function num(f: FileView): int {
        f.reload();
        return parseInt(f.text()) || 0;
    }

    function sample(): void {
        const now = Date.now() / 1000;
        energy = num(energyFile) / 1e6;
        full = num(fullFile) / 1e6;
        limit = num(limitFile) || 100;
        statusFile.reload();
        const next = BL.step(est, { status: statusFile.text().trim(), e: energy, p: num(powerFile) / 1e6 }, now, prior);
        est = next;
        if (next.ready && next.status === "Discharging" && now - savedAt > 300) {
            prior = next.rate;
            savedAt = now;
            priorFile.setText(next.rate.toFixed(2) + "\n");
        }
    }

    component Sys: FileView {
        blockAllReads: true
        printErrors: false
    }

    Sys { id: energyFile; path: root.dir + "/energy_now" }
    Sys { id: powerFile; path: root.dir + "/power_now" }
    Sys { id: fullFile; path: root.dir + "/energy_full" }
    Sys { id: statusFile; path: root.dir + "/status" }
    Sys { id: limitFile; path: root.dir + "/charge_control_end_threshold" }

    FileView {
        id: priorFile

        path: Quickshell.env("HOME") + "/.local/share/rice/battery-rate"
        printErrors: false
        onLoaded: root.prior = parseFloat(text()) || 0
    }

    // every 20 s while the battery is in use, every minute while it just sits full; right away on plug/unplug
    Timer {
        interval: root.status === "Discharging" || root.status === "Charging" ? 20000 : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    Connections {
        target: UPower.displayDevice

        function onStateChanged(): void {
            root.sample();
        }
    }
}

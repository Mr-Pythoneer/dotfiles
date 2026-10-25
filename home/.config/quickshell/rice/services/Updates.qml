pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Reads update-check's last report (written at login and at 7:00)
Singleton {
    id: root

    property int count: 0
    property int news: 0
    property int problems: 0
    property string checked: ""
    property var packages: []
    // what "Update now" runs: arch-update here, fedora-update in Fedora (it also rebuilds what needs it)
    property string updater: "arch-update"

    FileView {
        path: "/etc/os-release"
        onLoaded: root.updater = /^ID="?fedora"?$/m.test(text()) ? "fedora-update" : "arch-update"
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/update-check/report.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            let n = 0;
            const pk = [];
            const re = /== (Official repos|AUR|Flatpak): (\d+) updates? ==\n((?:  .*\n?)*)/g;
            let m;
            while ((m = re.exec(t)) !== null) {
                n += parseInt(m[2]);
                for (const line of m[3].split("\n"))
                    if (line.trim())
                        pk.push(line.trim());
            }
            root.count = n;
            root.packages = pk;
            const nm = t.match(/Arch news since your last update \((\d+)\)/);
            root.news = nm ? parseInt(nm[1]) : 0;
            const pm = t.match(/== Needs attention now ==\n((?:  .*\n?)*)/);
            root.problems = pm ? pm[1].split("\n").filter(l => l.startsWith("  * ")).length : 0;
            const cm = t.match(/^Update check — (.*)$/m);
            root.checked = cm ? cm[1] : "";
        }
    }
}

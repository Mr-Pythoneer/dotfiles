import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Your folders, opened in superfile, plus how full the drives are
ShelfCard {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property var drives: []
    property int trash: 0

    title: "Places"
    icon: "folder_open"
    accent: Theme.yellow

    function gb(bytes: real): string {
        const g = bytes / 1e9;
        return g >= 1000 ? (g / 1000).toFixed(1) + " TB" : g >= 100 ? Math.round(g) + " GB" : g.toFixed(1) + " GB";
    }

    function openDir(dir: string): void {
        Shell.close();
        Ctl.run(["kitty", "-e", "spf", dir]);
    }

    Process {
        running: true
        command: ["sh", "-c", "df -B1 --output=target,size,used,avail / /mnt/data 2>/dev/null | tail -n +2; echo trash $(ls -A ~/.local/share/Trash/files 2>/dev/null | wc -l)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const seen = new Set();
                const out = [];
                for (const l of lines) {
                    const f = l.trim().split(/\s+/);
                    if (f[0] === "trash") {
                        root.trash = parseInt(f[1]) || 0;
                    } else if (f.length >= 4 && !seen.has(f[0])) {
                        seen.add(f[0]);
                        out.push({ target: f[0], name: f[0] === "/" ? "System" : "Data drive", size: +f[1], used: +f[2], avail: +f[3] });
                    }
                }
                root.drives = out;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Grid {
            width: parent.width
            columns: 2
            rowSpacing: 0
            columnSpacing: 4

            Repeater {
                model: [
                    { name: "Home", icon: "home", dir: root.home },
                    { name: "Desktop", icon: "desktop_windows", dir: root.home + "/Desktop" },
                    { name: "Documents", icon: "description", dir: root.home + "/Documents" },
                    { name: "Downloads", icon: "download", dir: root.home + "/Downloads" },
                    { name: "Pictures", icon: "photo_library", dir: root.home + "/Pictures" },
                    { name: "Videos", icon: "video_library", dir: root.home + "/Videos" },
                    { name: "Data drive", icon: "hard_drive", dir: "/mnt/data" },
                    { name: root.trash ? `Trash · ${root.trash}` : "Trash", icon: root.trash ? "delete" : "delete_outline", dir: root.home + "/.local/share/Trash/files" }
                ]

                ShelfRow {
                    required property var modelData

                    width: (parent.width - 4) / 2
                    icon: modelData.icon
                    accent: Theme.yellow
                    text: modelData.name
                    onClicked: root.openDir(modelData.dir)
                }
            }
        }

        // free space per drive
        Repeater {
            model: root.drives

            Column {
                required property var modelData

                x: 6
                width: parent.width - 12
                spacing: 4

                Item {
                    width: parent.width
                    height: 14

                    Txt {
                        text: modelData.name
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }

                    Txt {
                        anchors.right: parent.right
                        text: root.gb(modelData.avail) + " free of " + root.gb(modelData.size)
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.08)

                    Rectangle {
                        readonly property real frac: modelData.size > 0 ? modelData.used / modelData.size : 0

                        width: parent.width * frac
                        height: parent.height
                        radius: parent.radius
                        color: Theme.fill(frac)
                    }
                }
            }
        }
    }
}

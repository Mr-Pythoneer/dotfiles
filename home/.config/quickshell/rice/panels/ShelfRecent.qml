import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Files you touched lately in your home folders (screenshots, downloads, documents...).
// Click to open; right-click to open the folder it's in.
ShelfCard {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property var files: []

    title: "Recent files"
    icon: "history"
    accent: Theme.primary

    function kind(name: string): var {
        const ext = (name.match(/\.(\w+)$/)?.[1] ?? "").toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].includes(ext))
            return { icon: "image", c: Theme.mauve, pic: ext !== "svg" };
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext))
            return { icon: "movie", c: Theme.peach };
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus"].includes(ext))
            return { icon: "music_note", c: Theme.teal };
        if (ext === "pdf")
            return { icon: "picture_as_pdf", c: Theme.red };
        if (["odt", "doc", "docx", "rtf", "txt", "md", "ods", "xlsx", "odp", "pptx"].includes(ext))
            return { icon: "description", c: Theme.blue };
        if (["py", "js", "ts", "qml", "sh", "c", "cpp", "rs", "go", "lua", "html", "css", "json", "toml"].includes(ext))
            return { icon: "code", c: Theme.green };
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].includes(ext))
            return { icon: "folder_zip", c: Theme.amber };
        return { icon: "draft", c: Theme.fgDim };
    }

    function ago(t: real): string {
        const s = Date.now() / 1000 - t;
        if (s < 90)
            return "just now";
        if (s < 3600)
            return Math.round(s / 60) + " min ago";
        if (s < 86400)
            return Math.round(s / 3600) + " h ago";
        if (s < 172800)
            return "yesterday";
        return Math.round(s / 86400) + " days ago";
    }

    Process {
        id: scan

        running: true
        command: ["sh", "-c", `cd ~ && find Downloads Desktop Documents Pictures Videos Music -maxdepth 4 \\( -name '.*' -o -name node_modules -o -name __pycache__ -o -path Pictures/Wallpapers \\) -prune -o -type f -mtime -60 -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -n 7`]
        stdout: StdioCollector {
            onStreamFinished: root.files = text.split("\n").filter(l => l.includes("\t")).map(l => {
                const [t, rel] = l.split("\t");
                const name = rel.split("/").pop();
                const dir = rel.slice(0, -name.length - 1);
                return { path: root.home + "/" + rel, dir: root.home + "/" + dir, name, folder: dir.split("/").pop(), time: parseFloat(t), kind: root.kind(name) };
            })
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.files.slice(0, 5)

            ShelfRow {
                required property var modelData

                icon: modelData.kind.icon
                accent: modelData.kind.c
                image: modelData.kind.pic ? modelData.path : ""
                text: modelData.name
                sub: modelData.folder + " · " + root.ago(modelData.time)
                onClicked: mouse => {
                    Shell.close();
                    if (mouse.button === Qt.RightButton)
                        Ctl.run(["kitty", "-e", "spf", modelData.dir]);
                    else
                        Ctl.open(modelData.path);
                }
            }
        }
    }

    Txt {
        visible: !scan.running && root.files.length === 0
        anchors.centerIn: parent
        text: "Nothing new in the last two months"
        font.pixelSize: 12
        color: Theme.fgDim
    }
}

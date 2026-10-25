import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// The last few things you copied (cliphist). Click one to copy it again; pictures show as thumbnails.
ShelfCard {
    id: root

    readonly property string thumbs: Quickshell.env("XDG_RUNTIME_DIR") + "/rice-clip"
    property var entries: []
    property string copied: ""

    title: "Clipboard"
    icon: "content_paste"
    accent: Theme.secondary

    function copy(entry: var): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "sh", entry.line]);
        root.copied = entry.id;
        done.restart();
    }

    tools: IconButton {
        icon: "open_in_full"
        size: 16
        color: Theme.fgDim
        onClicked: {
            Shell.close();
            Ctl.run(["caelestia", "clipboard"]);
        }
    }

    Process {
        id: list

        running: true
        // pictures are decoded once into a thumbnail file (kept in RAM, under XDG_RUNTIME_DIR)
        command: ["sh", "-c", `d="${root.thumbs}"; mkdir -p "$d"; find "$d" -type f -mmin +1440 -delete
            cliphist list | head -n 6 | while IFS= read -r line; do
                case "$line" in *"\t[[ binary data "*)
                    id=\${line%%\t*}; ext=$(printf '%s' "$line" | awk '{ print $(NF-2) }')
                    [ -s "$d/$id.$ext" ] || printf '%s\\n' "$line" | cliphist decode > "$d/$id.$ext" 2>/dev/null ;;
                esac
                printf '%s\\n' "$line"
            done`]
        stdout: StdioCollector {
            onStreamFinished: root.entries = text.split("\n").filter(l => l.includes("\t")).map(line => {
                const tab = line.indexOf("\t");
                const id = line.slice(0, tab);
                const preview = line.slice(tab + 1);
                const bin = preview.match(/^\[\[ binary data (.+?) (\w+) (\d+x\d+) \]\]$/);
                return {
                    id, line,
                    text: bin ? `Picture · ${bin[3].replace("x", "×")}` : preview.replace(/\s+/g, " ").trim() || "(blank)",
                    sub: bin ? `${bin[2].toUpperCase()} · ${bin[1]}` : "",
                    image: bin ? `${root.thumbs}/${id}.${bin[2]}` : ""
                };
            })
        }
    }

    // a tick on the one you picked, then out of the way so you can paste
    Timer {
        id: done

        interval: 450
        onTriggered: Shell.close()
    }

    Column {
        anchors.fill: parent
        spacing: 1

        Repeater {
            model: root.entries

            ShelfRow {
                required property var modelData

                icon: modelData.image ? "image" : "notes"
                image: modelData.image
                text: modelData.text
                sub: modelData.sub
                flash: root.copied === modelData.id
                onClicked: root.copy(modelData)
            }
        }
    }

    Txt {
        visible: !list.running && root.entries.length === 0
        anchors.centerIn: parent
        text: "Nothing copied yet"
        font.pixelSize: 12
        color: Theme.fgDim
    }
}

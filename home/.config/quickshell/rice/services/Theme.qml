pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours, fonts, sizes and motion for the whole shell.
// Colours follow Caelestia's live scheme (~/.local/state/caelestia/scheme.json), like the rest of the desktop:
// right now that's the black-and-white "monochrome" one, which the defaults below match so nothing flashes at startup.
// App icons and pictures keep their own colours: greyed out they just looked muddy.
// (GitHub Dark from the 2026-10-10 rice until 2026-10-13.)
Singleton {
    id: root

    property color primary: "#ffffff"
    property color secondary: "#c6c6c6"
    property color tertiary: "#e2e2e2"
    property color error: "#ffb4ab"         // only for things that need you: low battery, a full disk, a busy CPU
    property color purple: "#dbdbdb"
    property color cyan: "#e3e3e3"
    property color yellow: "#ebebeb"
    property color surface: "#131313"
    property color container: "#1f1f1f"
    property color containerHigh: "#2a2a2a"
    property color containerHighest: "#353535"
    property color fg: "#e2e2e2"
    property color fgDim: "#c6c6c6"
    property color outline: "#919191"
    property color line: "#474747"
    property color primaryContainer: "#d4d4d4"

    // A little colour where it means something: graphs and meters, weather, file types, the battery while it
    // charges. Fixed soft tones that sit on the grey scheme; the rest of the shell stays black and white.
    // The same set colours btop (~/.config/btop/themes/mono-accent.theme) and the title bar buttons (hypr/plugins.lua).
    readonly property color green: "#a6da95"
    readonly property color amber: "#eed49f"
    readonly property color peach: "#f5a97f"
    readonly property color red: "#ed8796"
    readonly property color blue: "#8aadf4"
    readonly property color mauve: "#c6a0f6"
    readonly property color teal: "#8bd5ca"
    readonly property color charge: green

    // how full something is (disks): green, amber past 75%, red past 90%
    function fill(f) {
        return f > 0.9 ? red : f > 0.75 ? amber : green;
    }

    // Surfaces use Caelestia's recipe: the scheme background at 82%, blurred by Hyprland (layer rule "rice-bar")
    readonly property real alpha: Power.eco ? 1 : 0.82   // efficiency mode turns blur off, so go solid
    readonly property color base: Qt.alpha(surface, alpha)
    readonly property color card: Qt.alpha(containerHigh, 0.6)
    readonly property color cardHover: Qt.alpha(containerHighest, 0.85)
    readonly property color edge: Qt.alpha(line, 0.6)

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property string iconFont: "Material Symbols Rounded"

    readonly property int barHeight: 42
    readonly property int gap: 10           // between the bar and the bottom of the screen
    readonly property int islandPad: 8
    readonly property int radius: 20
    readonly property int radiusSmall: 13
    readonly property int textSize: 13
    readonly property int smallText: 11
    readonly property int popoutWidth: 320

    // springy on the way in, quick on the way out
    readonly property int durIn: 450
    readonly property int durOut: 180
    readonly property int durFast: 150

    function tint(c, amount) {
        return Qt.alpha(c, amount);
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                const c = d.colours;
                const set = (prop, key) => {
                    if (c[key])
                        root[prop] = "#" + c[key];
                };
                set("primary", "primary");
                set("secondary", "secondary");
                set("tertiary", "tertiary");
                set("error", "error");
                set("surface", "surface");
                set("container", "surfaceContainer");
                set("containerHigh", "surfaceContainerHigh");
                set("containerHighest", "surfaceContainerHighest");
                set("fg", "onSurface");
                set("fgDim", "onSurfaceVariant");
                set("outline", "outline");
                set("line", "outlineVariant");
                set("primaryContainer", "primaryContainer");
                set("purple", "term13");
                set("cyan", "term14");
                set("yellow", "term11");
            } catch (e) {
                console.warn("rice theme: couldn't read Caelestia's scheme:", e);
            }
        }
    }
}

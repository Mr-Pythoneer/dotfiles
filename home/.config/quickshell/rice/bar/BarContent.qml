import QtQuick
import Quickshell
import qs.services
import qs.components
import qs.panels

// Everything the bar draws on one screen: the three islands (or one full-width strip), the hover popout, and the panels.
// It fills a tall transparent window; only the pieces you can see take clicks (see BarWindow's mask).
Item {
    id: root

    property ShellScreen screen
    property string monName: screen?.name ?? ""
    readonly property bool hidden: Hypr.hasFullscreen(monName) && !panelOpen
    readonly property bool edge: BarLayout.style === "edge"
    readonly property int lift: edge ? 0 : Theme.gap     // space between the bar and the bottom of the screen
    readonly property int barY: height - lift - Theme.barHeight
    readonly property bool panelOpen: Shell.panel !== "" && Shell.screen === monName

    property var popEntry: null
    property Item popAnchor: null
    property bool popPinned: false

    // the shelf, when the bottom edge brought it up, stays while the pointer is on it, the bar or the edge
    property bool edgeHovered: false
    readonly property bool pointerIn: inside.hovered || edgeHovered

    readonly property alias leftIsland: left
    readonly property alias centerIsland: center
    readonly property alias rightIsland: right
    readonly property alias strip: strip
    readonly property alias popout: popout
    readonly property alias panels: panels
    readonly property alias bridge: bridge

    function hoverPart(entry: var, item: Item): void {
        if (!entry?.children?.length || (entry.opens ?? "hover") !== "hover" || panelOpen)
            return;
        closeTimer.stop();
        if (popPinned && popEntry !== entry)
            popPinned = false;
        popAnchor = item;
        popEntry = entry;
    }

    function clickPart(entry: var, item: Item): void {
        if (popEntry === entry && popPinned) {
            closePopout();
            return;
        }
        popAnchor = item;
        popEntry = entry;
        popPinned = true;
    }

    function keepPopout(): void {
        closeTimer.stop();
    }

    function leavePart(): void {
        if (!popPinned && !Shell.keyboard)
            closeTimer.restart();
    }

    function closePopout(): void {
        popEntry = null;
        popPinned = false;
        Shell.keyboard = false;
    }

    function slotFor(key: string): Item {
        return left.slotFor(key) ?? center.slotFor(key) ?? right.slotFor(key);
    }

    onPanelOpenChanged: if (panelOpen) closePopout()

    HoverHandler {
        id: inside
    }

    Timer {
        running: Shell.hover && root.panelOpen && !root.pointerIn
        interval: 400
        onTriggered: Shell.close()
    }

    // while the shelf is up, the strip from just above the bar down to the screen edge counts as part of it,
    // so the pointer can travel up from the edge (or across the gaps between islands) without it dropping away
    Item {
        id: bridge

        y: root.barY - 12
        width: root.width
        height: root.height - y

        TapHandler {
            onTapped: Shell.close()
        }
    }

    Timer {
        id: closeTimer

        interval: 320
        onTriggered: if (!popout.hovered && !root.popPinned && !Shell.keyboard) root.closePopout()
    }

    // the full-width style: one strip right along the bottom of the screen, with the three zones sitting on it
    Rectangle {
        id: strip

        visible: root.edge
        width: root.width
        height: Theme.barHeight
        y: root.hidden ? root.height + 8 : root.barY
        color: Theme.base

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.edge
        }

        Behavior on y { Springy {} }
    }

    Island {
        id: left

        bar: root
        entries: BarLayout.left
        x: root.lift
        y: root.hidden ? root.height + 8 : root.barY

        Behavior on y { Springy {} }
    }

    Island {
        id: right

        bar: root
        entries: BarLayout.right
        x: root.width - width - root.lift
        y: root.hidden ? root.height + 8 : root.barY

        Behavior on y { Springy {} }
    }

    Island {
        id: center

        bar: root
        entries: BarLayout.center
        x: Math.max(left.x + left.width + Theme.gap, Math.min(right.x - width - Theme.gap, (root.width - width) / 2))
        y: root.hidden ? root.height + 8 : root.barY

        Behavior on y { Springy {} }
    }

    // Tripwire: twice since 2026-10-18 the whole middle of the bar stopped drawing until the bar was
    // restarted, with nothing in the log. Whenever it moves, resizes or hides, check (once it has settled)
    // that it really is on screen; if not, say exactly why. No timer runs while nothing changes.
    Connections {
        target: center

        function onVisibleChanged(): void { centreCheck.restart(); }
        function onWidthChanged(): void { centreCheck.restart(); }
        function onXChanged(): void { centreCheck.restart(); }
        function onOpacityChanged(): void { centreCheck.restart(); }
    }

    Timer {
        id: centreCheck

        property string last: ""

        interval: 2000      // after an animation or a burst of title changes has settled
        running: true       // once at start
        onTriggered: {
            if (root.hidden || root.width <= 0)
                return;
            const c = center, slots = [];
            for (const s of c.children[0]?.children ?? [])
                if (s.entry)
                    slots.push(`${s.entry.id}:${s.visible ? Math.round(s.width) : "hidden"}`);
            const bad = !c.visible ? "not visible" : isNaN(c.width) || isNaN(c.x) ? "NaN geometry"
                : c.width <= Theme.islandPad * 2 ? "no width" : c.x < 0 || c.x + c.width > root.width ? "off screen"
                : c.opacity < 0.01 ? "transparent" : "";
            const state = bad ? `${bad}: x ${c.x} w ${c.width} implicitW ${c.implicitWidth} y ${c.y}/${root.height} `
                + `entries ${c.entries.length} [${slots.join(" ")}] left ${left.x}+${left.width} right ${right.x}` : "";
            if (state !== last && (bad || last))
                console.warn(bad ? `rice: bar centre isn't drawn on ${root.monName} (${state})` : `rice: bar centre is back on ${root.monName}`);
            last = state;
        }
    }

    Popout {
        id: popout

        bar: root
        entry: root.popEntry
        anchorItem: root.popAnchor
    }

    Panels {
        id: panels

        bar: root
    }
}

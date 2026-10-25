import QtQuick
import qs.services
import qs.components

// The bubble above a part showing what's stacked inside it. It springs open, and glides and resizes
// when you move from one part to the next.
Item {
    id: pop

    property var entry: null
    property Item anchorItem: null
    property var bar
    property var shown: null            // keeps the last content while it fades out
    property bool settled: false        // first open appears in place; later moves glide
    readonly property bool open: entry !== null
    readonly property bool hovered: hover.hovered
    readonly property real anchorX: {
        bar?.width;                       // re-place when the bar resizes
        if (!anchorItem || !bar)
            return 0;
        return anchorItem.mapToItem(bar, anchorItem.width / 2, 0).x;
    }

    onEntryChanged: {
        if (entry)
            shown = entry;
        else
            settled = false;
    }
    onOpenChanged: if (open) settleTimer.restart()

    width: Theme.popoutWidth
    height: content.implicitHeight + 20
    x: Math.max(Theme.gap, Math.min((bar?.width ?? 0) - width - Theme.gap, anchorX - width / 2))
    y: (bar?.barY ?? 0) - height - 10
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.9
    transformOrigin: Item.Bottom
    visible: opacity > 0.01

    Behavior on x {
        enabled: pop.settled
        Springy {}
    }
    Behavior on height {
        enabled: pop.settled
        Springy {}
    }
    Behavior on opacity {
        NumberAnimation { duration: pop.open ? 160 : Theme.durOut }
    }
    Behavior on scale {
        NumberAnimation {
            duration: pop.open ? Theme.durIn : Theme.durOut
            easing.type: pop.open ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.4
        }
    }

    Timer {
        id: settleTimer

        interval: 60
        onTriggered: pop.settled = true
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.base
        border.width: 1
        border.color: Theme.edge
    }

    Column {
        id: content

        x: 10
        y: 10
        width: pop.width - 20
        spacing: 8

        Repeater {
            model: pop.shown?.children ?? []

            Loader {
                required property var modelData
                property var entry: modelData

                width: content.width
                sourceComponent: Pieces.get(modelData.id)
            }
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: hovered ? pop.bar.keepPopout() : pop.bar.leavePart()
    }
}

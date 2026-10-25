import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// A 2px strip along the very bottom of the screen. Rest the pointer there for a moment and the shelf comes up.
// It sits on the overlay layer so it always gets the pointer first, and steps aside for fullscreen windows.
// With the full-width bar the strip runs along the bar's bottom edge, so it leaves out the three zones:
// pushing the pointer down onto a button still clicks the button, and the empty stretches of bar open the shelf.
PanelWindow {
    id: root

    required property var bar   // this screen's BarContent

    screen: bar.screen
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    implicitHeight: 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: !bar.hidden
    WlrLayershell.namespace: "rice-edge"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        width: root.width
        height: root.height

        Zone { island: root.bar.leftIsland }
        Zone { island: root.bar.centerIsland }
        Zone { island: root.bar.rightIsland }
    }

    component Zone: Region {
        required property Item island

        intersection: Intersection.Subtract
        x: island.x
        width: root.bar.edge && island.visible ? island.width : 0
        height: root.height
    }

    HoverHandler {
        id: hover

        onHoveredChanged: root.bar.edgeHovered = hovered
    }

    // a short wait, so flicking the pointer down onto the bar doesn't throw the shelf up every time
    Timer {
        running: hover.hovered && Shell.panel === "" && !root.bar.popPinned
        interval: 220
        onTriggered: Shell.peek("shelf", root.bar.monName)
    }

    TapHandler {
        onTapped: Shell.peek("shelf", root.bar.monName)
    }
}

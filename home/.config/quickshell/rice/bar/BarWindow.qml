import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// One per screen: a tall see-through layer along the bottom. The islands reserve space for themselves;
// popouts and panels draw above them in the same window, so hovering from a part into its popout never flickers.
PanelWindow {
    id: win

    required property ShellScreen modelData
    readonly property alias content: content

    screen: modelData
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    implicitHeight: screen?.height ?? 1080
    exclusiveZone: content.hidden ? 0 : Theme.barHeight + content.lift
    WlrLayershell.namespace: "rice-bar"
    WlrLayershell.layer: WlrLayer.Top
    // a shelf that only came up from the bottom edge leaves the keyboard with your window until you click into it
    WlrLayershell.keyboardFocus: (content.panelOpen && !Shell.hover) || (Shell.keyboard && content.popEntry) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        Region { item: content.edge ? content.strip : null }
        Region { item: content.leftIsland }
        Region { item: content.centerIsland }
        Region { item: content.rightIsland }
        Region { item: content.popout.visible ? content.popout : null }
        Region { item: content.panels.current }
        Region { item: content.panels.name === "shelf" ? content.bridge : null }
    }

    BarContent {
        id: content

        anchors.fill: parent
        screen: win.modelData
    }

    // clicking anywhere else closes an open panel, or a popout that was opened by clicking
    HyprlandFocusGrab {
        windows: [win]
        active: (content.panelOpen && !Shell.hover) || content.popPinned
        onCleared: {
            if (content.panelOpen)
                Shell.close();
            content.closePopout();
        }
    }
}

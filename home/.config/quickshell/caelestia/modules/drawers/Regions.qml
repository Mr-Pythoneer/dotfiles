pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.utils
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property string barPos: bar.position
    readonly property bool barOnLeft: BarPosition.isLeft(barPos)
    readonly property bool barOnRight: BarPosition.isRight(barPos)
    readonly property bool barOnTop: BarPosition.isTop(barPos)
    readonly property bool barOnBottom: BarPosition.isBottom(barPos)

    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    // local: the band along each edge that takes the pointer; none along a disabled bar's edge, so the rice bar
    // there gets every click, see ~/.config/caelestia/patches/bar-off-flush.patch
    readonly property real leftBand: barOnLeft ? (bar.disabled ? 0 : bar.clampedWidth + win.dragMaskPadding) : clampedThickness + win.dragMaskPadding
    readonly property real topBand: barOnTop ? (bar.disabled ? 0 : bar.clampedHeight + win.dragMaskPadding) : clampedThickness + win.dragMaskPadding
    readonly property real rightBand: barOnRight ? (bar.disabled ? 0 : bar.clampedWidth + win.dragMaskPadding) : clampedThickness + win.dragMaskPadding
    readonly property real bottomBand: barOnBottom ? (bar.disabled ? 0 : bar.clampedHeight + win.dragMaskPadding) : clampedThickness + win.dragMaskPadding

    x: leftBand
    y: topBand
    width: win.width - leftBand - rightBand
    height: win.height - topBand - bottomBand
    intersection: Intersection.Xor

    R {
        bounds: root.panels.dashboardRect
    }

    R {
        bounds: root.panels.launcherRect
    }

    R {
        bounds: root.panels.sessionRect
    }

    R {
        bounds: root.panels.sidebarRect
    }

    R {
        bounds: root.panels.osdRect
    }

    R {
        bounds: root.panels.notificationsRect
    }

    R {
        bounds: root.panels.utilitiesRect
    }

    R {
        bounds: root.panels.popoutsRect
    }

    component R: Region {
        required property rect bounds

        x: bounds.x
        y: bounds.y
        width: bounds.width
        height: bounds.height
        intersection: Intersection.Subtract
    }
}

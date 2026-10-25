import QtQuick
import qs.services
import qs.components

// A panel rising out of the bar: springs up when it opens, drops away when it closes. Its content loads only while open.
Item {
    id: frame

    property bool shown: false
    property var bar
    property Component body
    property bool autoHeight: true
    readonly property Item item: loader.item

    height: autoHeight ? (loader.item?.implicitHeight ?? 0) + 28 : implicitHeight
    y: (bar?.barY ?? 0) - height - 12 + (shown ? 0 : 36)
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94
    transformOrigin: Item.Bottom
    visible: opacity > 0.01
    focus: shown

    onShownChanged: if (shown) forceActiveFocus()
    Keys.onEscapePressed: Shell.close()

    Behavior on y { Springy {} }
    Behavior on opacity { NumberAnimation { duration: frame.shown ? 180 : Theme.durOut } }
    Behavior on scale {
        NumberAnimation {
            duration: frame.shown ? Theme.durIn : Theme.durOut
            easing.type: frame.shown ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.3
        }
    }
    Behavior on height {
        enabled: frame.shown
        Springy {}
    }

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Theme.base
        border.width: 1
        border.color: Theme.edge
    }

    Loader {
        id: loader

        x: 14
        y: 14
        width: frame.width - 28
        height: frame.autoHeight ? undefined : frame.height - 28
        active: frame.shown || frame.visible
        sourceComponent: frame.body
        focus: true
    }
}

import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components

// The focused window's icon and title
Item {
    id: root

    readonly property var win: Hypr.activeWindow
    // drop a leading status glyph (Claude Code animates ◐◓◑◒ there ~10x a second): the text stays put, so the bar doesn't redraw for it
    readonly property string title: (win?.title ?? "").replace(/^[◐◓◑◒✳✢✶✻✽·⠂⠐]\s+/, "")

    implicitWidth: Math.min(row.implicitWidth, 300) + 16
    implicitHeight: 30

    Behavior on implicitWidth { Springy {} }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        x: 8
        width: Math.min(implicitWidth, 300)
        spacing: 7

        IconImage {
            visible: !!root.win
            implicitSize: 16
            source: Hypr.appIcon(root.win)
            anchors.verticalCenter: parent.verticalCenter
        }

        Txt {
            width: Math.min(implicitWidth, 300 - 23)
            text: root.title || "Desktop"
            color: root.title ? Theme.primary : Theme.fgDim
        }
    }
}

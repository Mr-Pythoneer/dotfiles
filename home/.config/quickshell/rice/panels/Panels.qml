import QtQuick
import qs.services

// The panels that rise out of the bar on this screen: dashboard (centre), control centre (right), to-do (left),
// and the shelf (centre, from the bottom edge)
Item {
    id: root

    property var bar
    readonly property string name: bar?.panelOpen ? Shell.panel : ""
    readonly property Item current: name === "dashboard" ? dash : name === "control" ? control : name === "todo" ? todo : name === "shelf" ? shelf : null

    anchors.fill: parent

    PanelFrame {
        id: dash

        bar: root.bar
        shown: root.name === "dashboard"
        autoHeight: false
        width: 900
        implicitHeight: 630
        x: (root.width - width) / 2
        body: Component { Dashboard {} }
    }

    PanelFrame {
        id: control

        bar: root.bar
        shown: root.name === "control"
        width: 404
        x: root.width - width - Theme.gap
        body: Component { ControlCentre {} }
    }

    PanelFrame {
        id: todo

        bar: root.bar
        shown: root.name === "todo"
        width: 370
        x: Theme.gap + 150
        body: Component { TodoPanel {} }
    }

    PanelFrame {
        id: shelf

        bar: root.bar
        shown: root.name === "shelf"
        width: Math.min(1080, root.width - Theme.gap * 2)
        x: (root.width - width) / 2
        body: Component { Shelf {} }
    }
}

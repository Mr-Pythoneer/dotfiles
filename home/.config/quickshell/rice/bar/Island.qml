import QtQuick
import qs.services
import qs.components

// A floating pill holding one zone of the bar (in the full-width style, just the zone: the strip behind draws the bar)
Rectangle {
    id: island

    property var entries: []
    property var bar

    implicitWidth: row.implicitWidth + Theme.islandPad * 2
    width: implicitWidth
    height: Theme.barHeight
    radius: bar?.edge ? 0 : height / 2
    color: bar?.edge ? "transparent" : Theme.base
    border.width: bar?.edge ? 0 : 1
    border.color: Theme.edge
    visible: entries.length > 0

    Behavior on width { Springy {} }

    function slotFor(key: string): Item {
        for (const c of row.children)
            if (c.entry?.key === key)
                return c;
        return null;
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: BarLayout.spacing === "tight" ? 0 : BarLayout.spacing === "roomy" ? 10 : 3

        Repeater {
            model: island.entries

            PartSlot {
                required property var modelData

                entry: modelData
                bar: island.bar
            }
        }
    }
}

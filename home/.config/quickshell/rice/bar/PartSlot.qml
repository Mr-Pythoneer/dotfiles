import QtQuick
import qs.services

// One part on the bar. Hovering it opens its popout when it has parts stacked inside (or clicking, if set to click).
Loader {
    id: slot

    property var entry
    property var bar
    readonly property string monName: bar?.monName ?? ""
    readonly property bool hasStack: (entry?.children?.length ?? 0) > 0
    readonly property bool clickToOpen: hasStack && entry?.opens === "click"

    anchors.verticalCenter: parent?.verticalCenter
    sourceComponent: Parts.get(entry?.id ?? "")
    visible: (item?.implicitWidth ?? 0) > 0     // parts hide themselves by shrinking to nothing
    active: sourceComponent !== null

    HoverHandler {
        onHoveredChanged: hovered ? slot.bar.hoverPart(slot.entry, slot) : slot.bar.leavePart()
    }

    // set to open on click: take the click before the part's own action
    MouseArea {
        anchors.fill: parent
        z: 10
        visible: slot.clickToOpen
        cursorShape: Qt.PointingHandCursor
        onClicked: slot.bar.clickPart(slot.entry, slot)
    }
}

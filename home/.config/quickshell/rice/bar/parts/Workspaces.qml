import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.components

// Workspaces on this monitor, each showing the apps open on it; the highlight springs to the active one
Item {
    id: root

    readonly property string monName: parent?.monName ?? ""
    readonly property var ids: Hypr.workspacesFor(monName)
    readonly property int activeId: Hypr.activeWs(monName)
    property int version: 0

    implicitWidth: row.implicitWidth
    implicitHeight: 30

    Rectangle {
        id: highlight

        readonly property Item target: {
            root.version;
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i);
                if (it && it.wsId === root.activeId)
                    return it;
            }
            return null;
        }

        x: target?.x ?? 0
        width: target?.width ?? 0
        height: parent.height
        radius: height / 2
        color: Qt.alpha(Theme.primary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Theme.primary, 0.5)
        visible: target !== null

        Behavior on x { Springy {} }
        Behavior on width { Springy {} }
    }

    Row {
        id: row

        spacing: 2

        Repeater {
            id: rep

            model: root.ids
            onItemAdded: root.version++
            onItemRemoved: root.version++

            Item {
                id: ws

                required property int modelData
                readonly property int wsId: modelData
                readonly property var wins: Hypr.windowsOn(wsId).filter(t => Hypr.monitorNameOfWindow(t) === root.monName)
                readonly property bool active: wsId === root.activeId

                implicitWidth: Math.max(30, icons.implicitWidth + 16)
                implicitHeight: 30

                Behavior on implicitWidth { Springy {} }

                Row {
                    id: icons

                    anchors.centerIn: parent
                    spacing: 5

                    Txt {
                        visible: ws.wins.length === 0
                        text: ws.wsId
                        font.weight: Font.Bold
                        color: ws.active ? Theme.primary : Theme.fgDim
                    }

                    Repeater {
                        model: ws.wins.slice(0, 4)

                        IconImage {
                            required property var modelData

                            implicitSize: 16
                            source: Hypr.appIcon(modelData)
                            opacity: ws.active ? 1 : 0.6
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Txt {
                        visible: ws.wins.length > 4
                        text: "+" + (ws.wins.length - 4)
                        font.pixelSize: 10
                        color: Theme.fgDim
                    }
                }

                Hover {
                    onClicked: Hypr.focusWorkspace(ws.wsId)
                }
            }
        }
    }

    WheelHandler {
        onWheel: event => Hypr.focusWorkspace(event.angleDelta.y > 0 ? "m-1" : "m+1")
    }
}

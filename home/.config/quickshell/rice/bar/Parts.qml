pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.components
import qs.bar.parts

// Builder part ids -> what draws them on the bar. Ids without an entry are skipped.
Singleton {
    readonly property var map: ({
            "logo": logo,
            "workspaces-icons": workspaces,
            "workspaces-dots": workspaces,
            "workspaces-numbers": workspaces,
            "visualiser": visualiser,
            "kb-layout": kb,
            "todo": todo,
            "taskbar": taskbar,
            "window-title": title,
            "notifications": bell,
            "claude": claude,
            "sysstats": sysstats,
            "spun": spun,
            "clock": clock,
            "clock-seconds": clock,
            "bluetooth": bluetooth,
            "network": network,
            "battery": battery,
            "battery-charge": battery,
            "power-btn": power,
            "gap": gap,
            "spacer": gap,
            "separator": separator
        })

    function get(id: string): var {
        return map[id] ?? null;
    }

    property Component logo: Component { Logo {} }
    property Component workspaces: Component { Workspaces {} }
    property Component visualiser: Component { Visualiser {} }
    property Component kb: Component { KbLayout {} }
    property Component todo: Component { TodoCount {} }
    property Component taskbar: Component { Taskbar {} }
    property Component title: Component { WindowTitle {} }
    property Component bell: Component { Bell {} }
    property Component claude: Component { ClaudeSessions {} }
    property Component sysstats: Component { SysStats {} }
    property Component spun: Component { Spun {} }
    property Component clock: Component { ClockPart {} }
    property Component bluetooth: Component { BluetoothPart {} }
    property Component network: Component { NetworkPart {} }
    property Component battery: Component { BatteryPart {} }
    property Component power: Component { Power {} }
    property Component gap: Component {
        Item {
            implicitWidth: parent?.entry?.id === "spacer" ? 16 : (parent?.entry?.width ?? 16)
            implicitHeight: 30
        }
    }
    property Component separator: Component {
        Item {
            implicitWidth: 9
            implicitHeight: 30

            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: 16
                color: Theme.line
            }
        }
    }
}

import QtQuick
import qs.services
import qs.components

// The dashboard: five pages behind tabs. Super+D or click the clock. Arrow keys or 1-5 switch pages.
Item {
    id: dash

    readonly property var tabs: [
        { id: "home", name: "Home", icon: "home", c: Theme.tertiary },
        { id: "media", name: "Media", icon: "queue_music", c: Theme.secondary },
        { id: "system", name: "System", icon: "monitoring", c: Theme.primary },
        { id: "weather", name: "Weather", icon: "partly_cloudy_day", c: Theme.yellow },
        { id: "dev", name: "Dev", icon: "terminal", c: Theme.purple }
    ]
    property int current: Math.max(0, tabs.findIndex(t => t.id === Shell.page))
    property int direction: 1

    function go(i: int): void {
        i = (i + tabs.length) % tabs.length;
        if (i === current)
            return;
        direction = i > current ? 1 : -1;
        current = i;
    }

    focus: true
    Keys.onLeftPressed: go(current - 1)
    Keys.onRightPressed: go(current + 1)
    Keys.onPressed: event => {
        const n = parseInt(event.text);
        if (n >= 1 && n <= tabs.length) {
            go(n - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            go(current + (event.modifiers & Qt.ShiftModifier ? -1 : 1));
            event.accepted = true;
        }
    }

    Item {
        id: tabBar

        width: parent.width
        height: 40

        Rectangle {
            id: indicator

            readonly property Item target: tabRow.children[dash.current] ?? null

            x: tabRow.x + (target?.x ?? 0)
            width: target?.width ?? 0
            height: 36
            y: 2
            radius: 18
            color: Qt.alpha(dash.tabs[dash.current].c, 0.16)
            border.width: 1
            border.color: Qt.alpha(dash.tabs[dash.current].c, 0.5)

            Behavior on x { Springy {} }
            Behavior on width { Springy {} }
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }

        Row {
            id: tabRow

            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            spacing: 4

            Repeater {
                model: dash.tabs

                Item {
                    required property var modelData
                    required property int index
                    readonly property bool sel: dash.current === index

                    width: label.implicitWidth + 30
                    height: tabRow.height

                    Row {
                        id: label

                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            icon: modelData.icon
                            size: 18
                            fill: sel ? 1 : 0
                            color: sel ? modelData.c : Theme.fgDim
                        }

                        Txt {
                            text: modelData.name
                            font.weight: sel ? Font.Bold : Font.Normal
                            color: sel ? Theme.fg : Theme.fgDim
                        }
                    }

                    Hover {
                        onClicked: dash.go(index)
                    }
                }
            }
        }
    }

    Item {
        id: pages

        anchors.top: tabBar.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Repeater {
            model: dash.tabs

            Loader {
                required property int index
                readonly property bool sel: dash.current === index

                width: pages.width
                height: pages.height
                active: sel || opacity > 0
                opacity: sel ? 1 : 0
                x: sel ? 0 : (index < dash.current ? -40 : 40)
                source: ["HomePage.qml", "MediaPage.qml", "SystemPage.qml", "WeatherPage.qml", "DevPage.qml"][index]

                Behavior on opacity { NumberAnimation { duration: 220 } }
                Behavior on x { Springy {} }
            }
        }
    }
}

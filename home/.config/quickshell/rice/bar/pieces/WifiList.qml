import QtQuick
import Quickshell.Networking
import qs.services
import qs.components

// Wi-Fi on/off and nearby networks. Click a known network to join it; a locked new one asks for its password here.
Column {
    id: root

    property var asking: null       // the network we're typing a password for
    property var pending: null      // the network we're joining

    spacing: 4
    Component.onCompleted: Net.scan(true)
    Component.onDestruction: {
        Net.scan(false);
        Shell.keyboard = false;
    }

    function join(n: var): void {
        if (n.connected) {
            n.disconnect();
        } else if (n.known || n.security === WifiSecurityType.Open) {
            root.pending = n;
            n.connect();
        } else {
            root.asking = n;
            Shell.keyboard = true;
        }
    }

    Header {
        width: parent.width
        text: "Wi-Fi"
        icon: "wifi"

        Icon {
            visible: Net.wifi?.scannerEnabled ?? false
            anchors.verticalCenter: parent.verticalCenter
            icon: "progress_activity"
            size: 15
            color: Theme.fgDim

            RotationAnimation on rotation {
                running: true
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1100
            }
        }

        Switch {
            checked: Net.wifiOn
            onToggled: Net.setWifi(!Net.wifiOn)
        }
    }

    Flickable {
        width: parent.width
        height: Math.min(contentHeight, 250)
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: Net.wifiOn

        Column {
            id: list

            width: parent.width
            spacing: 2

            Repeater {
                model: Net.networks.slice(0, 14)

                Column {
                    id: net

                    required property var modelData
                    readonly property bool secured: modelData.security !== WifiSecurityType.Open

                    width: list.width

                    Item {
                        width: parent.width
                        height: 38

                        Icon {
                            id: sig

                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            icon: Net.wifiIcon(net.modelData.signalStrength)
                            fill: 1
                            size: 17
                            color: net.modelData.connected ? Theme.primary : Theme.fgDim
                        }

                        Txt {
                            anchors.left: sig.right
                            anchors.leftMargin: 9
                            anchors.right: right.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: net.modelData.name
                            color: net.modelData.connected ? Theme.fg : Theme.fgDim
                            font.weight: net.modelData.connected ? Font.DemiBold : Font.Normal
                        }

                        Row {
                            id: right

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Txt {
                                visible: net.modelData.connected || net.modelData.stateChanging
                                text: net.modelData.stateChanging ? "joining…" : "connected"
                                font.pixelSize: 10
                                color: Theme.secondary
                            }

                            Icon {
                                visible: net.secured
                                icon: "lock"
                                size: 13
                                color: Theme.fgDim
                            }
                        }

                        Hover {
                            radius: 12
                            onClicked: root.join(net.modelData)
                        }
                    }

                    // password box, only for the network being joined
                    Item {
                        visible: root.asking === net.modelData
                        width: parent.width
                        height: visible ? 40 : 0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: go.left
                            anchors.margins: 6
                            anchors.verticalCenter: parent.verticalCenter
                            height: 32
                            radius: 16
                            color: Qt.alpha(Theme.fg, 0.07)
                            border.width: 1
                            border.color: pw.activeFocus ? Theme.primary : Qt.alpha(Theme.line, 0.6)

                            TextInput {
                                id: pw

                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 12
                                clip: true
                                focus: root.asking === net.modelData
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: go.clicked()
                                Keys.onEscapePressed: {
                                    root.asking = null;
                                    Shell.keyboard = false;
                                }

                                Txt {
                                    visible: !pw.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Password"
                                    font.pixelSize: 12
                                    color: Theme.fgDim
                                }
                            }
                        }

                        PillButton {
                            id: go

                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Join"
                            filled: true
                            onClicked: {
                                net.modelData.connectWithPsk(pw.text);
                                root.pending = net.modelData;
                                root.asking = null;
                                Shell.keyboard = false;
                            }
                        }
                    }
                }
            }
        }
    }

    PillButton {
        text: "Network settings"
        icon: "settings"
        onClicked: Ctl.run(["nm-connection-editor"])
    }
}

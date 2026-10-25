import QtQuick
import qs.services
import qs.components
import qs.bar.pieces

// Dev: Claude Code sessions, your repos in ~/.local/src, GitHub notifications, updates and the news
Row {
    id: root

    readonly property real colW: (width - spacing * 2) / 3

    spacing: 12
    Component.onCompleted: Dev.refresh()

    component Title: Row {
        property string text
        property string icon
        property color accent: Theme.fg

        spacing: 7

        Icon {
            icon: parent.icon
            size: 17
            color: parent.accent
        }

        Txt {
            text: parent.text
            font.weight: Font.Bold
        }
    }

    // ---- Claude sessions + quick launchers ----
    Column {
        width: root.colW
        spacing: 12

        Card {
            width: parent.width
            height: 300

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Row {
                    spacing: 7

                    Txt {
                        text: "✳"
                        font.pixelSize: 17
                        color: Theme.tertiary
                    }

                    Txt {
                        text: "Claude Code"
                        font.weight: Font.Bold
                    }

                    Txt {
                        text: Claude.count ? Claude.count + " running" : ""
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }
                }

                Repeater {
                    model: Claude.sessions

                    Rectangle {
                        required property var modelData

                        width: parent.width
                        height: 46
                        radius: Theme.radiusSmall
                        color: modelData.waiting ? Qt.alpha(Theme.primary, 0.08) : Qt.alpha(Theme.fg, 0.04)
                        border.width: modelData.waiting ? 1 : 0
                        border.color: Qt.alpha(Theme.primary, 0.45)

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Txt {
                                width: parent.width
                                text: modelData.title || "Claude Code"
                                font.pixelSize: 12
                            }

                            Txt {
                                text: modelData.waiting ? "waiting for you" : "working…"
                                font.pixelSize: 10
                                color: modelData.waiting ? Theme.primary : Theme.secondary
                            }
                        }

                        Hover {
                            radius: Theme.radiusSmall
                            onClicked: {
                                Shell.close();
                                Hypr.focusWindow(modelData.window);
                            }
                        }
                    }
                }

                Txt {
                    visible: Claude.count === 0
                    text: "No sessions running"
                    font.pixelSize: 12
                    color: Theme.fgDim
                }
            }
        }

        Card {
            width: parent.width
            height: 214

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                Title {
                    text: "Open"
                    icon: "bolt"
                    accent: Theme.yellow
                }

                Repeater {
                    model: [
                        { icon: "terminal", name: "New terminal", cmd: ["kitty"] },
                        { icon: "smart_toy", name: "Claude in a new terminal", cmd: ["kitty", "-e", "claude"] },
                        { icon: "monitoring", name: "btop", cmd: [Ctl.bin + "sysmon-toggle"] },
                        { icon: "fact_check", name: "Update report", cmd: ["kitty", "--hold", Ctl.bin + "update-check", "--show"] }
                    ]

                    Item {
                        required property var modelData

                        width: parent.width
                        height: 32

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 4
                            spacing: 9

                            Icon {
                                icon: modelData.icon
                                size: 17
                                color: Theme.purple
                            }

                            Txt {
                                text: modelData.name
                                font.pixelSize: 12
                            }
                        }

                        Hover {
                            radius: 10
                            onClicked: {
                                Shell.close();
                                Ctl.run(modelData.cmd);
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- repos + GitHub ----
    Column {
        width: root.colW
        spacing: 12

        Card {
            width: parent.width
            height: 270

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Title {
                    text: "Repos"
                    icon: "commit"
                    accent: Theme.tertiary
                }

                Repeater {
                    model: Dev.repos

                    Item {
                        required property var modelData

                        width: parent.width
                        height: 34

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 4
                            spacing: 1

                            Txt {
                                text: modelData.name
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Txt {
                                text: modelData.branch
                                font.pixelSize: 10
                                color: Theme.purple
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Txt {
                                visible: modelData.ahead > 0
                                text: "↑" + modelData.ahead
                                font.pixelSize: 11
                                color: Theme.primary
                            }

                            Txt {
                                visible: modelData.behind > 0
                                text: "↓" + modelData.behind
                                font.pixelSize: 11
                                color: Theme.cyan
                            }

                            Txt {
                                text: modelData.changed ? "~" + modelData.changed : "clean"
                                font.pixelSize: 11
                                color: modelData.changed ? Theme.tertiary : Theme.secondary
                            }
                        }

                        Hover {
                            radius: 10
                            onClicked: {
                                Shell.close();
                                Ctl.run(["kitty", "--directory", Ctl.home + "/.local/src/" + modelData.name]);
                            }
                        }
                    }
                }
            }
        }

        Card {
            width: parent.width
            height: 244

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Item {
                    width: parent.width
                    height: 20

                    Title {
                        text: "GitHub"
                        icon: "notifications_active"
                        accent: Theme.purple
                    }

                    PillButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        text: "Open"
                        accent: Theme.purple
                        onClicked: {
                            Shell.close();
                            Ctl.open("https://github.com/notifications");
                        }
                    }
                }

                Repeater {
                    model: Dev.github.slice(0, 5)

                    Column {
                        required property var modelData

                        width: parent.width
                        spacing: 1

                        Txt {
                            width: parent.width
                            text: modelData.title
                            font.pixelSize: 12
                        }

                        Txt {
                            text: modelData.repo + " · " + modelData.type.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
                            font.pixelSize: 10
                            color: Theme.fgDim
                        }
                    }
                }

                Txt {
                    visible: Dev.github.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Dev.githubOk ? "No unread notifications" : "Couldn't reach GitHub (is `gh` logged in?)"
                    font.pixelSize: 12
                    color: Theme.fgDim
                }
            }
        }
    }

    // ---- updates + news ----
    Column {
        width: root.colW
        spacing: 12

        UpdatesPiece {
            width: parent.width
        }

        NewsPiece {
            width: parent.width
        }
    }
}

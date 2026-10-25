import QtQuick
import Quickshell.Widgets
import Caelestia.Services
import qs.services
import qs.components
import qs.bar.pieces

// Home: greeting and clock, weather, what's playing, how the machine's doing, your to-dos and the month
Row {
    id: root

    readonly property real colW: (width - spacing * 2) / 3

    spacing: 12

    ServiceRef { service: Cpu }
    ServiceRef { service: Memory }
    ServiceRef { service: Gpu }

    // ---- left: greeting + clock, weather ----
    Column {
        width: root.colW
        spacing: 12

        Card {
            width: parent.width
            height: 200

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 4

                Txt {
                    text: Host.greeting + ","
                    font.pixelSize: 13
                    color: Theme.fgDim
                }

                Txt {
                    text: Host.user
                    font.pixelSize: 19
                    font.weight: Font.Bold
                    color: Theme.secondary
                }

                Item { width: 1; height: 10 }

                Row {
                    spacing: 0

                    Txt {
                        id: big

                        text: Clock.hm
                        font.pixelSize: 54
                        font.weight: Font.Bold
                        color: Theme.tertiary
                    }

                    Txt {
                        anchors.baseline: big.baseline
                        text: ":" + Clock.seconds
                        font.pixelSize: 24
                        color: Qt.alpha(Theme.tertiary, 0.7)
                    }

                    Txt {
                        anchors.baseline: big.baseline
                        text: " " + Clock.ampm
                        font.pixelSize: 15
                        color: Theme.fgDim
                    }
                }

                Txt {
                    text: Qt.formatDate(Clock.now, "dddd, d MMMM")
                    color: Theme.fg
                }
            }
        }

        Card {
            width: parent.width
            height: 190

            Icon {
                id: wIcon

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 16
                icon: Weather.icon(Weather.code, Weather.isDay)
                size: 54
                fill: 1
                color: Weather.tint(Weather.code, Weather.isDay)
            }

            Column {
                anchors.left: wIcon.right
                anchors.leftMargin: 14
                anchors.verticalCenter: wIcon.verticalCenter
                spacing: 2

                Txt {
                    text: Weather.ready ? Math.round(Weather.temp) + "°" : "…"
                    font.pixelSize: 36
                    font.weight: Font.Bold
                }

                Txt {
                    text: Weather.ready ? Weather.describe(Weather.code) : "Getting the weather"
                    color: Theme.fgDim
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                spacing: 4

                Txt {
                    width: parent.width
                    visible: Weather.ready
                    text: "Feels like " + Math.round(Weather.feels) + "°  ·  " + Weather.humidity + "% humid"
                    font.pixelSize: 11
                    color: Theme.fgDim
                }

                Txt {
                    width: parent.width
                    visible: Weather.daily.length > 0
                    text: Weather.daily.length ? "Today " + Math.round(Weather.daily[0].min) + "° – " + Math.round(Weather.daily[0].max) + "°" + (Weather.daily[0].rain > 20 ? "  ·  " + Weather.daily[0].rain + "% rain" : "") : ""
                    font.pixelSize: 11
                    color: Theme.fgDim
                }

                Txt {
                    width: parent.width
                    text: Weather.city
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.primary
                }
            }
        }

        Card {
            width: parent.width
            height: 112

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                Row {
                    spacing: 8

                    Icon {
                        icon: Updates.count ? "system_update_alt" : "check_circle"
                        size: 17
                        color: Updates.count ? Theme.tertiary : Theme.secondary
                    }

                    Txt {
                        text: Updates.count ? Updates.count + " updates ready" : "System up to date"
                        font.pixelSize: 12
                    }
                }

                Row {
                    spacing: 8

                    Txt {
                        text: "✳"
                        font.pixelSize: 15
                        color: Theme.tertiary
                    }

                    Txt {
                        text: Claude.count ? Claude.count + " Claude session" + (Claude.count === 1 ? "" : "s") + (Claude.waiting ? " · " + Claude.waiting + " waiting" : "") : "No Claude sessions"
                        font.pixelSize: 12
                        color: Claude.waiting ? Theme.primary : Theme.fg
                    }
                }

                Row {
                    spacing: 8

                    Icon {
                        icon: "notifications"
                        size: 17
                        color: Theme.purple
                    }

                    Txt {
                        text: Notifs.count + " notification" + (Notifs.count === 1 ? "" : "s")
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // ---- middle: media, machine ----
    Column {
        width: root.colW
        spacing: 12

        Card {
            id: media

            readonly property var p: Media.active

            width: parent.width
            height: 300

            ClippingRectangle {
                id: cover

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 16
                width: 128
                height: 128
                radius: 16
                color: Qt.alpha(Theme.secondary, 0.12)

                Image {
                    anchors.fill: parent
                    source: media.p?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(256, 256)
                }

                Icon {
                    anchors.centerIn: parent
                    visible: !(media.p?.trackArtUrl)
                    icon: "music_note"
                    size: 44
                    color: Theme.secondary
                }
            }

            Column {
                anchors.top: cover.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                spacing: 2

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: media.p?.trackTitle || "Nothing playing"
                    font.weight: Font.Bold
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: media.p ? (media.p.trackArtist || media.p.identity) : "Play something and it shows up here"
                    font.pixelSize: 12
                    color: Theme.secondary
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 12

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_previous"
                    size: 22
                    fill: 1
                    disabled: !media.p?.canGoPrevious
                    onClicked: media.p.previous()
                }

                IconButton {
                    icon: media.p?.isPlaying ? "pause" : "play_arrow"
                    size: 28
                    fill: 1
                    active: true
                    activeColor: Theme.secondary
                    disabled: !media.p
                    onClicked: media.p.togglePlaying()
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_next"
                    size: 22
                    fill: 1
                    disabled: !media.p?.canGoNext
                    onClicked: media.p.next()
                }
            }
        }

        Card {
            width: parent.width
            height: 214

            Txt {
                x: 16
                y: 12
                text: "MACHINE"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: Theme.fgDim
            }

            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 8
                spacing: 12

                Ring {
                    value: Cpu.percentage
                    caption: Cpu.temperature ? Math.round(Cpu.temperature) + "°C" : "CPU"
                    accent: Theme.blue
                }

                Ring {
                    value: Memory.percentage
                    caption: "RAM"
                    accent: Theme.mauve
                }

                Ring {
                    value: Gpu.percentage
                    caption: "GPU"
                    accent: Theme.teal
                }
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                text: (Memory.used / 1048576).toFixed(1) + " / " + (Memory.total / 1048576).toFixed(0) + " GB memory"
                font.pixelSize: 11
                color: Theme.fgDim
            }
        }
    }

    // ---- right: to-dos, calendar ----
    Column {
        width: root.colW
        spacing: 12

        Card {
            width: parent.width
            height: 254

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    spacing: 7

                    Icon {
                        icon: "checklist"
                        size: 17
                        color: Theme.secondary
                    }

                    Txt {
                        text: "To-do"
                        font.weight: Font.Bold
                    }

                    Txt {
                        text: Todo.open ? Todo.open + " left" : ""
                        font.pixelSize: 11
                        color: Theme.fgDim
                    }
                }

                Field {
                    width: parent.width
                    height: 32
                    placeholder: "Add a to-do"
                    onAccepted: {
                        Todo.add(text);
                        text = "";
                    }
                }

                Repeater {
                    model: Todo.items.filter(i => !i.done).slice(0, 5)

                    Row {
                        required property var modelData

                        spacing: 4

                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "radio_button_unchecked"
                            size: 16
                            color: Theme.fgDim
                            onClicked: Todo.toggle(modelData.id)
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.colW - 70
                            text: modelData.text
                            font.pixelSize: 12
                        }
                    }
                }

                Txt {
                    visible: Todo.open === 0
                    text: "Nothing to do. Nice."
                    font.pixelSize: 12
                    color: Theme.fgDim
                }
            }
        }

        CalendarPiece {
            width: parent.width
        }
    }
}

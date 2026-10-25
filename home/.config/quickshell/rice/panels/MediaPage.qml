import QtQuick
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Caelestia.Services
import qs.services
import qs.components

// Media: big cover and controls, a full-width visualiser, every player, and per-app volume
Item {
    id: root

    readonly property var p: Media.active

    CavaProvider {
        id: cava

        bars: 48
    }

    ServiceRef {
        service: cava
    }

    // ---- left: the cover ----
    Card {
        id: coverCard

        width: 300
        height: parent.height

        ClippingRectangle {
            id: cover

            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            width: 264
            height: 264
            radius: 18
            color: Qt.alpha(Theme.secondary, 0.1)

            Image {
                anchors.fill: parent
                source: root.p?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(528, 528)
            }

            Icon {
                anchors.centerIn: parent
                visible: !(root.p?.trackArtUrl)
                icon: "album"
                size: 90
                color: Qt.alpha(Theme.secondary, 0.6)
            }
        }

        Column {
            anchors.top: cover.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 18
            spacing: 3

            Txt {
                width: parent.width
                text: root.p?.trackTitle || "Nothing playing"
                font.pixelSize: 17
                font.weight: Font.Bold
            }

            Txt {
                width: parent.width
                text: root.p?.trackArtist || ""
                color: Theme.secondary
            }

            Txt {
                width: parent.width
                text: root.p?.trackAlbum || ""
                font.pixelSize: 12
                color: Theme.fgDim
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 18
            spacing: 10

            Item {
                width: parent.width
                height: 16

                Rectangle {
                    id: seek

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.12)

                    Rectangle {
                        height: parent.height
                        radius: 2.5
                        width: (root.p?.length ?? 0) > 0 ? parent.width * Math.min(1, root.p.position / root.p.length) : 0
                        color: Theme.secondary

                        Behavior on width { NumberAnimation { duration: 900 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: root.p?.canSeek ?? false
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => root.p.position = Math.max(0, Math.min(1, (mouse.x - 6) / seek.width)) * root.p.length
                    }
                }
            }

            Item {
                width: parent.width
                height: 12

                Txt {
                    text: Media.fmt(root.p?.position ?? 0)
                    font.pixelSize: 10
                    color: Theme.fgDim
                }

                Txt {
                    anchors.right: parent.right
                    text: Media.fmt(root.p?.length ?? 0)
                    font.pixelSize: 10
                    color: Theme.fgDim
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "shuffle"
                    size: 18
                    active: root.p?.shuffle ?? false
                    activeColor: Theme.secondary
                    disabled: !(root.p?.shuffleSupported)
                    onClicked: root.p.shuffle = !root.p.shuffle
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_previous"
                    size: 24
                    fill: 1
                    disabled: !root.p?.canGoPrevious
                    onClicked: root.p.previous()
                }

                Rectangle {
                    width: 52
                    height: 52
                    radius: 26
                    color: Theme.secondary
                    scale: playArea.pressed ? 0.9 : 1

                    Behavior on scale { Springy {} }

                    Icon {
                        anchors.centerIn: parent
                        icon: root.p?.isPlaying ? "pause" : "play_arrow"
                        size: 30
                        fill: 1
                        color: Theme.surface
                    }

                    MouseArea {
                        id: playArea

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.p?.togglePlaying()
                    }
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_next"
                    size: 24
                    fill: 1
                    disabled: !root.p?.canGoNext
                    onClicked: root.p.next()
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: root.p?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                    size: 18
                    active: (root.p?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                    activeColor: Theme.secondary
                    disabled: !(root.p?.loopSupported)
                    onClicked: root.p.loopState = root.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist : root.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                }
            }
        }
    }

    // ---- right: visualiser, players, app volumes ----
    Column {
        anchors.left: coverCard.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        spacing: 12

        Card {
            width: parent.width
            height: 170

            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                height: 138

                Repeater {
                    model: 48

                    Rectangle {
                        required property int index
                        readonly property real v: Audio.playing ? Math.min(1, cava.values[index] ?? 0) : 0

                        anchors.bottom: parent.bottom
                        width: 7
                        radius: 3.5
                        height: Math.max(4, v * 138)
                        color: Qt.tint(Theme.secondary, Qt.alpha(Theme.primary, index / 47))

                        Behavior on height { NumberAnimation { duration: 80 } }
                    }
                }
            }
        }

        Card {
            width: parent.width
            height: playersCol.implicitHeight + 24

            Column {
                id: playersCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 4

                Txt {
                    text: "PLAYERS"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: Theme.fgDim
                }

                Repeater {
                    model: Media.players

                    Item {
                        required property var modelData
                        readonly property bool sel: Media.active === modelData

                        width: playersCol.width
                        height: 34

                        Icon {
                            id: pi

                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            icon: modelData.isPlaying ? "graphic_eq" : "pause_circle"
                            size: 17
                            color: sel ? Theme.secondary : Theme.fgDim
                        }

                        Txt {
                            anchors.left: pi.right
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.identity + (modelData.trackTitle ? "  ·  " + modelData.trackTitle : "")
                            font.pixelSize: 12
                            color: sel ? Theme.fg : Theme.fgDim
                        }

                        Hover {
                            radius: 10
                            onClicked: Media.manual = modelData
                        }
                    }
                }

                Txt {
                    visible: Media.players.length === 0
                    text: "No players open"
                    font.pixelSize: 12
                    color: Theme.fgDim
                }
            }
        }

        Card {
            width: parent.width
            height: Math.min(appsCol.implicitHeight + 24, 220)
            clip: true

            Column {
                id: appsCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 7

                Txt {
                    text: "APP VOLUME"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: Theme.fgDim
                }

                Slider {
                    width: parent.width
                    value: Audio.muted ? 0 : Audio.volume
                    icon: Audio.volumeIcon(Audio.volume, Audio.muted)
                    label: "Everything · " + Math.round(Audio.volume * 100) + "%"
                    onMoved: v => Audio.setVolume(v)
                    onIconClicked: Audio.toggleMute()
                }

                Repeater {
                    model: Audio.streams

                    Slider {
                        required property var modelData

                        width: appsCol.width
                        value: modelData.audio?.muted ? 0 : (modelData.audio?.volume ?? 0)
                        icon: "graphic_eq"
                        accent: Theme.secondary
                        label: (modelData.properties?.["application.name"] || modelData.description || modelData.name || "App") + " · " + Math.round((modelData.audio?.volume ?? 0) * 100) + "%"
                        onMoved: v => {
                            if (modelData.audio) {
                                modelData.audio.muted = false;
                                modelData.audio.volume = v;
                            }
                        }
                        onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                    }
                }
            }
        }
    }
}

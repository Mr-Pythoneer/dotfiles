pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property CachingImage current
    property bool completed

    onSourceChanged: {
        if (!source)
            current = null;
        else
            current = imgComp.createObject(this, {
                path: source
            });
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                current = imgComp.createObject(this, {
                    path: source
                });
                completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: Tr.tr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: Tr.tr("Select a wallpaper")
                            filterLabel: Tr.tr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: Tr.tr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }

            // A wallpaper named "name.live.png" plays "name.mp4" over the still while on AC power;
            // on battery it pauses and fades back to the still.
            readonly property string liveSource: /\.live\.(png|jpe?g|webp)$/i.test(path) ? path.replace(/\.live\.(png|jpe?g|webp)$/i, ".mp4") : ""
            readonly property bool livePlaying: liveSource !== "" && !UPower.onBattery && root.current === img

            Loader {
                anchors.fill: parent
                active: img.liveSource !== ""

                sourceComponent: Item {
                    id: live

                    readonly property bool shouldPlay: img.livePlaying

                    onShouldPlayChanged: shouldPlay ? player.play() : player.pause()
                    Component.onCompleted: if (shouldPlay) player.play()

                    MediaPlayer {
                        id: player

                        source: "file://" + img.liveSource
                        loops: MediaPlayer.Infinite
                        videoOutput: video
                    }

                    VideoOutput {
                        id: video

                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                        opacity: live.shouldPlay && player.playbackState === MediaPlayer.PlayingState && player.hasVideo ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.SlowEffects
                            }
                        }
                    }
                }
            }

            // A wallpaper named "name.pscircle.png" is a live process tree: ~/.local/bin/pscircle-wall redraws it
            // every 30 s on AC power and every 2 minutes on battery (not in efficiency mode), over the still.
            // The drawings go to $XDG_RUNTIME_DIR/pscircle, two per screen used in turn, and skip the image
            // cache (it keeps a copy of every distinct image, so each redraw would add one).
            readonly property bool treeLive: /\.pscircle\.png$/i.test(path) && root.current === img

            Loader {
                anchors.fill: parent
                active: img.treeLive

                sourceComponent: Item {
                    id: tree

                    readonly property QsWindow win: QsWindow.window as QsWindow
                    readonly property int w: Math.round(width * (win?.devicePixelRatio ?? 1))
                    readonly property int h: Math.round(height * (win?.devicePixelRatio ?? 1))
                    readonly property string stem: `${Quickshell.env("XDG_RUNTIME_DIR")}/pscircle/${win?.screen?.name ?? "screen"}`
                    readonly property int every: PowerProfiles.profile === PowerProfile.PowerSaver ? 0 : UPower.onBattery ? 120 : 30
                    property int drawn: 0
                    property Image shown

                    Process {
                        id: draw

                        command: [Quickshell.env("HOME") + "/.local/bin/pscircle-wall", `${tree.stem}-${(tree.drawn + 1) % 2}.png`, String(tree.w), String(tree.h)]
                        onExited: code => {
                            if (code !== 0)
                                return;
                            tree.drawn++;
                            // a new URL each time, so the file is read again
                            (tree.shown === drawingA ? drawingB : drawingA).source = `file://${tree.stem}-${tree.drawn % 2}.png?${tree.drawn}`;
                        }
                    }

                    Timer {
                        interval: Math.max(1, tree.every) * 1000
                        running: tree.every > 0 && tree.w > 0 && tree.h > 0
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: if (!draw.running) draw.running = true
                    }

                    // swap only once a new drawing has fully loaded, so there's never a blank frame
                    Image {
                        id: drawingA

                        anchors.fill: parent
                        asynchronous: true
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(tree.w, tree.h)
                        visible: tree.shown === drawingA
                        onStatusChanged: if (status === Image.Ready) tree.shown = drawingA
                    }

                    Image {
                        id: drawingB

                        anchors.fill: parent
                        asynchronous: true
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(tree.w, tree.h)
                        visible: tree.shown === drawingB
                        onStatusChanged: if (status === Image.Ready) tree.shown = drawingB
                    }
                }
            }
        }
    }
}

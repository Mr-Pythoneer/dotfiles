pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// Audio bars that slide open in the bar while any media player is playing
StyledRect {
    id: root

    property bool isHorizontal: false
    readonly property bool playing: isHorizontal && Players.list.some(p => p.isPlaying)
    readonly property int fullWidth: 180
    readonly property int barCount: 30

    implicitWidth: playing ? fullWidth : 0
    implicitHeight: Tokens.sizes.bar.innerWidth
    visible: implicitWidth > 0
    opacity: playing ? 1 : 0
    clip: true

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Loader {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small

        active: root.visible

        sourceComponent: Row {
            id: row

            readonly property real slot: width / root.barCount

            ServiceRef {
                service: Audio.cava
            }

            Repeater {
                model: root.barCount

                Item {
                    id: slot

                    required property int index
                    // cava gives more bands than fit here, so average neighbouring ones
                    readonly property real value: {
                        const vals = Audio.cava.values;
                        const per = vals.length / root.barCount;
                        const start = Math.floor(index * per);
                        const end = Math.max(start + 1, Math.floor((index + 1) * per));
                        let sum = 0;
                        for (let i = start; i < end && i < vals.length; i++)
                            sum += vals[i];
                        return Math.min(1, sum / (end - start));
                    }

                    width: row.slot
                    height: row.height

                    StyledRect {
                        anchors.centerIn: parent
                        width: Math.max(1, parent.width - 2)
                        height: Math.max(width, slot.value * parent.height)
                        radius: width / 2
                        color: Colours.palette.m3primary

                        Behavior on height {
                            Anim {
                                duration: 80
                            }
                        }
                    }
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on opacity {
        Anim {}
    }
}

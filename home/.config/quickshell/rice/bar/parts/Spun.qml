import QtQuick
import qs.services
import qs.components

// Opens Spun's cassette deck (same as Super+C); the record spins while Spun is playing
Item {
    id: root

    readonly property bool spinning: Media.players.some(p => /spun/i.test(p.identity + " " + p.dbusName) && p.isPlaying)

    implicitWidth: 34
    implicitHeight: 30

    Icon {
        anchors.centerIn: parent
        icon: "album"
        size: 19
        fill: root.spinning ? 1 : 0
        color: Theme.tertiary

        // spins while Spun plays, but holds still on battery or in efficiency mode (a 60 fps redraw of the bar)
        RotationAnimation on rotation {
            running: root.spinning && !Power.still
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2400
        }
    }

    Hover {
        onClicked: Ctl.run(["busctl", "--user", "call", "org.mpris.MediaPlayer2.spun", "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "ToggleDeck"])
    }
}

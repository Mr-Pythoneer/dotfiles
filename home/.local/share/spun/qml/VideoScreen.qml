import QtQuick
import QtQuick.Window
import QtMultimedia

// Cassette mode's TV: the cassette deck is the VCR, this window shows the picture.
// It appears when the playing track has video (local video files, or YouTube songs
// buffered as video while the cassette is selected). While it is up the deck window
// hides (Main.qml's videoMode), so the TV carries its own transport controls; the deck
// pops up on request (Super+C, Tab, or the cassette button).
Window {
    id: tv
    required property var app
    readonly property var deck: app.deckPlayer
    // Cider has no native transport to draw from
    readonly property bool canShow: !!deck && typeof deck.setVideoSink === "function"
    readonly property bool wanted: app.cassette && canShow && deck.hasVideo === true
    property var attached: null
    property bool dismissed: false
    readonly property bool fullScreen: visibility === Window.FullScreen

    // Qt adds " — Spun" itself
    title: (deck && deck.title ? deck.title + " — " : "") + "TV"
    // A normal top-level window: Hyprland tiles it beside your other windows (instead of
    // floating it over the deck) and draws its borders, so no Qt title bar
    transientParent: null
    flags: Qt.Window | Qt.FramelessWindowHint
    width: 854; height: 480
    minimumWidth: 320; minimumHeight: 180
    color: "black"
    visible: wanted && !dismissed

    function attach() {
        const target = app.cassette && canShow ? deck : null
        if (attached === target) return
        if (attached && typeof attached.setVideoSink === "function") attached.setVideoSink(null)
        attached = target
        if (target) target.setVideoSink(screen.videoSink)
    }
    function toggleFullScreen() { visibility = fullScreen ? Window.Windowed : Window.FullScreen }
    function skip(ms) { if (deck && deck.duration > 0) deck.seek(Math.max(0, Math.min(deck.duration - 500, deck.position + ms))) }
    // h:mm:ss for long videos (the deck's clock only counts minutes)
    function clock(ms) {
        const t = Math.max(0, Math.floor((ms || 0) / 1000)), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = t % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
    }
    function nudgeVolume(step) { if (deck) deck.volume = Math.max(0, Math.min(1, deck.volume + step)) }
    // Any input brings the controls back for a moment
    function wake() { idle.restart() }
    onWantedChanged: if (!wanted) dismissed = false
    Component.onCompleted: attach()
    Connections { target: tv.app; function onCassetteChanged() { tv.attach() } function onDeckPlayerChanged() { tv.attach() } }
    Connections { target: tv.deck; ignoreUnknownSignals: true; function onTrackChanged() { tv.dismissed = false } }
    // Closing the TV pauses the tape instead of playing on unseen
    onClosing: function(close) { dismissed = true; if (deck && deck.playing) deck.toggle() }

    VideoOutput {
        id: screen
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        // Click pauses, double-click goes full screen
        TapHandler { onDoubleTapped: tv.toggleFullScreen() }
        TapHandler { onSingleTapped: { tv.wake(); if (tv.deck) tv.deck.toggle() } }
    }

    // Controls stay up while paused, while the pointer moves, or while it rests on them
    readonly property bool controlsShown: idle.running || !(deck && deck.playing) || panelHover.hovered || seek.dragging || titleHover.hovered
    Timer { id: idle; interval: 2500; running: true }
    HoverHandler {
        id: hover
        onPointChanged: tv.wake()
        // Hide the pointer along with the controls
        cursorShape: tv.controlsShown ? Qt.ArrowCursor : Qt.BlankCursor
    }
    WheelHandler { onWheel: function(event) { tv.wake(); tv.nudgeVolume(event.angleDelta.y > 0 ? .05 : -.05) } }

    // Title, top left
    Rectangle {
        id: titlePill
        x: 16; y: 16
        width: Math.min(titleText.implicitWidth + 28, parent.width - 32); height: 36; radius: 18
        color: Qt.alpha(tv.app.inset, .86)
        opacity: tv.controlsShown && titleText.text.length ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        HoverHandler { id: titleHover }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Text {
            id: titleText
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: Text.AlignVCenter
            text: tv.deck ? tv.deck.title : ""
            color: tv.app.ink; elide: Text.ElideRight
            font.family: theme.fontFamily; font.pixelSize: 14
        }
    }

    // Transport panel, bottom centre: seek bar over a row of buttons
    Rectangle {
        id: panel
        readonly property bool compact: width < 560
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: tv.controlsShown ? 16 : 4 }
        width: Math.min(parent.width - 32, 820); height: 96; radius: 22
        color: Qt.alpha(tv.app.inset, .9)
        opacity: tv.controlsShown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        HoverHandler { id: panelHover }
        // Swallow clicks between buttons so they don't pause the video
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        // Seek bar with elapsed / total on either side
        Text {
            id: elapsed
            anchors { left: parent.left; leftMargin: 18; verticalCenter: seek.verticalCenter }
            width: 62
            text: tv.clock(seek.dragging ? seek.previewMs : tv.deck ? tv.deck.position : 0)
            color: tv.app.ink; font.family: theme.fontFamily; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        Text {
            id: total
            anchors { right: parent.right; rightMargin: 18; verticalCenter: seek.verticalCenter }
            width: 62; horizontalAlignment: Text.AlignRight
            text: tv.clock(tv.deck ? tv.deck.duration : 0)
            color: tv.app.mutedInk; font.family: theme.fontFamily; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        Item {
            id: seek
            anchors { left: elapsed.right; right: total.left; top: parent.top; topMargin: 10; leftMargin: 6; rightMargin: 6 }
            height: 24
            readonly property real duration: tv.deck ? tv.deck.duration : 0
            readonly property bool dragging: seekArea.pressed
            property real previewMs: 0
            readonly property real fraction: duration > 0 ? (dragging ? previewMs : tv.deck.position) / duration : 0
            function msAt(x) { return Math.max(0, Math.min(1, x / width)) * duration }
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: seekArea.containsMouse || seek.dragging ? 6 : 4; radius: height / 2
                color: Qt.alpha(tv.app.ink, .22)
                Behavior on height { NumberAnimation { duration: 120 } }
                Rectangle { width: parent.width * seek.fraction; height: parent.height; radius: parent.radius; color: tv.app.accent }
            }
            Rectangle {
                x: seek.width * seek.fraction - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: seekArea.containsMouse || seek.dragging ? 14 : 0; height: width; radius: width / 2
                color: tv.app.accent
                Behavior on width { NumberAnimation { duration: 120 } }
            }
            // Time under the pointer
            Rectangle {
                visible: (seekArea.containsMouse || seek.dragging) && seek.duration > 0
                readonly property real at: seek.dragging ? seek.width * seek.fraction : seekArea.mouseX
                x: Math.max(-elapsed.width, Math.min(seek.width - width + total.width, at - width / 2))
                y: -height - 8
                width: hoverTime.implicitWidth + 16; height: 24; radius: 12
                color: tv.app.inset; border.color: Qt.alpha(tv.app.ink, .15)
                Text {
                    id: hoverTime
                    anchors.centerIn: parent
                    text: tv.clock(seek.dragging ? seek.previewMs : seek.msAt(seekArea.mouseX))
                    color: tv.app.ink; font.family: theme.fontFamily; font.pixelSize: 12
                }
            }
            MouseArea {
                id: seekArea
                anchors.fill: parent; anchors.topMargin: -4; anchors.bottomMargin: -4
                hoverEnabled: true
                enabled: seek.duration > 0
                cursorShape: Qt.PointingHandCursor
                onPressed: function(mouse) { seek.previewMs = seek.msAt(mouse.x) }
                onPositionChanged: function(mouse) { tv.wake(); if (pressed) seek.previewMs = seek.msAt(mouse.x) }
                onReleased: if (tv.deck) tv.deck.seek(seek.previewMs)
            }
        }

        // Volume, left
        Row {
            anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 8 }
            spacing: 2
            IconButton {
                glyphName: tv.deck && tv.deck.volume > 0 ? "volume" : "mute"
                tip: tv.deck && tv.deck.volume > 0 ? "Mute · M" : "Unmute · M"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: tv.app.toggleMute()
            }
            SpunSlider {
                visible: !panel.compact
                width: 96; anchors.verticalCenter: parent.verticalCenter
                from: 0; to: 1; stepSize: .01
                value: tv.deck ? tv.deck.volume : 0
                onMoved: if (tv.deck) tv.deck.volume = value
            }
        }

        // Transport, centre
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
            spacing: 4
            IconButton {
                visible: !panel.compact
                glyphName: "previous"; tip: "Previous · P"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                enabled: !!tv.deck && tv.deck.count > 0
                onClicked: tv.deck.previous()
            }
            IconButton {
                glyphName: "rewind"; tip: "Back 10 s · J"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: tv.skip(-10000)
            }
            IconButton {
                width: 52; glyphSize: 26
                glyphName: tv.deck && tv.deck.playing ? "pause" : "play"
                tip: tv.deck && tv.deck.playing ? "Pause · Space" : "Play · Space"
                fill: tv.app.accent; ink: theme.colors.onAccent; hoverFill: Qt.lighter(tv.app.accent, 1.08)
                onClicked: if (tv.deck) tv.deck.toggle()
            }
            IconButton {
                glyphName: "forward"; tip: "Forward 10 s · L"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: tv.skip(10000)
            }
            IconButton {
                visible: !panel.compact
                glyphName: "next"; tip: "Next · N"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                enabled: !!tv.deck && tv.deck.count > 1
                onClicked: tv.deck.next()
            }
            IconButton {
                glyphName: "stop"; tip: "Stop · S"; glyphSize: 18
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: if (tv.deck) tv.deck.stop()
            }
        }

        // Deck and fullscreen, right
        Row {
            anchors { right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 8 }
            spacing: 2
            IconButton {
                glyphName: "cassette"; tip: "Show the tape deck · Tab or Super+C"
                selected: tv.app.deckPeek
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: tv.app.toggleDeckPeek()
            }
            IconButton {
                glyphName: tv.fullScreen ? "fullscreen_exit" : "fullscreen"
                tip: tv.fullScreen ? "Exit full screen · F" : "Full screen · F"
                ink: tv.app.ink; hoverFill: tv.app.hoverFill
                onClicked: tv.toggleFullScreen()
            }
        }
    }

    Shortcut { sequences: ["Space", "K"]; onActivated: { tv.wake(); if (tv.deck) tv.deck.toggle() } }
    Shortcut { sequence: "F"; onActivated: tv.toggleFullScreen() }
    Shortcut { sequence: "Escape"; onActivated: if (tv.fullScreen) tv.visibility = Window.Windowed }
    Shortcut { sequence: "Left"; onActivated: { tv.wake(); tv.skip(-5000) } }
    Shortcut { sequence: "Right"; onActivated: { tv.wake(); tv.skip(5000) } }
    Shortcut { sequence: "J"; onActivated: { tv.wake(); tv.skip(-10000) } }
    Shortcut { sequence: "L"; onActivated: { tv.wake(); tv.skip(10000) } }
    Shortcut { sequence: "Up"; onActivated: { tv.wake(); tv.nudgeVolume(.05) } }
    Shortcut { sequence: "Down"; onActivated: { tv.wake(); tv.nudgeVolume(-.05) } }
    Shortcut { sequence: "M"; onActivated: { tv.wake(); tv.app.toggleMute() } }
    Shortcut { sequence: "S"; onActivated: { tv.wake(); if (tv.deck) tv.deck.stop() } }
    Shortcut { sequence: "N"; onActivated: { tv.wake(); if (tv.deck) tv.deck.next() } }
    Shortcut { sequence: "P"; onActivated: { tv.wake(); if (tv.deck) tv.deck.previous() } }
    Shortcut { sequence: "Tab"; onActivated: tv.app.toggleDeckPeek() }
}

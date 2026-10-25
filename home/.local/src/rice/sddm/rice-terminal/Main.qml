// Rice Terminal: a getty-style login in a GitHub Dark terminal window, floating over the code rain.
// Type your password and press Enter. Tab switches user (if there's more than one), F2 the session.
// Colours, font, background still and video come from theme.conf.
import QtQuick
import QtQuick.Effects
import QtMultimedia

Rectangle {
    id: root
    width: 1920
    height: 1200
    color: config.canvas

    readonly property real s: Math.min(width / 1920, height / 1200)
    property int userIndex: Math.max(0, users.indexOf(userModel.lastUser))
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property var users: []
    property var sessions: []
    property string message: ""
    property bool failed: false
    property bool waiting: false

    // SDDM's models only expose their rows through delegates, so copy them out once
    Repeater {
        model: userModel
        delegate: Item {
            Component.onCompleted: root.users = root.users.concat([model.name])
        }
    }
    Repeater {
        model: sessionModel
        delegate: Item {
            Component.onCompleted: root.sessions = root.sessions.concat([model.name])
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.waiting = false;
            root.failed = true;
            root.message = "Login incorrect";
            password.text = "";
            password.forceActiveFocus();
            shake.start();
        }
        function onLoginSucceeded() {
            root.message = "Starting " + (root.sessions[root.sessionIndex] || "your session") + "...";
        }
    }

    function login() {
        if (root.users.length === 0 || root.waiting)
            return;
        root.failed = false;
        root.message = "";
        root.waiting = true;
        sddm.login(root.users[root.userIndex], password.text, root.sessionIndex);
    }

    function nextSession() {
        root.sessionIndex = (root.sessionIndex + 1) % Math.max(1, root.sessions.length);
    }

    // ---- background: the code rain, dimmed so the terminal stands out ----
    Image {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
    }
    MediaPlayer {
        id: player
        source: Qt.resolvedUrl(config.video)
        loops: MediaPlayer.Infinite
        videoOutput: video
        Component.onCompleted: play()
    }
    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
    Rectangle {
        anchors.fill: parent
        color: config.canvas
        opacity: 0.5
    }

    // ---- clock, top right ----
    Column {
        anchors { top: parent.top; right: parent.right; margins: 56 * root.s }
        spacing: 2 * root.s
        Row {
            anchors.right: parent.right
            spacing: 10 * root.s
            Text {
                id: clock
                font { family: config.font; pixelSize: 96 * root.s; weight: Font.Light }
                color: config.text
            }
            Text {
                id: ampm
                anchors.baseline: clock.baseline
                font { family: config.font; pixelSize: 28 * root.s }
                color: config.textDim
            }
        }
        Text {
            id: date
            anchors.right: parent.right
            font { family: config.font; pixelSize: 20 * root.s }
            color: config.accent
        }
    }

    // ---- the terminal ----
    Item {
        id: term
        anchors.centerIn: parent
        width: 780 * root.s
        height: content.implicitHeight + titleBar.height + 56 * root.s

        SequentialAnimation {
            id: shake
            loops: 2
            NumberAnimation { target: term; property: "anchors.horizontalCenterOffset"; to: -12; duration: 45 }
            NumberAnimation { target: term; property: "anchors.horizontalCenterOffset"; to: 12; duration: 90 }
            NumberAnimation { target: term; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
        }

        // the shadow is its own item, so the window still draws if the shadow effect can't
        RectangularShadow {
            anchors.fill: winBg
            radius: winBg.radius
            offset.y: 16 * root.s
            blur: 48 * root.s
            color: "#cc000000"
        }
        Rectangle {
            id: winBg
            anchors.fill: parent
            radius: 14 * root.s
            color: config.surface
            opacity: 0.94
            border { color: config.border; width: 1 }
        }

        Item {
            id: titleBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 40 * root.s
            Text {
                anchors.centerIn: parent
                text: "tty1 — " + (sddm.hostName || "arch")
                font { family: config.font; pixelSize: 14 * root.s }
                color: config.textDim
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: config.border
            }
        }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: titleBar.bottom; margins: 30 * root.s }
            spacing: 10 * root.s

            component Line: Text {
                font { family: config.font; pixelSize: 19 * root.s }
                color: config.text
                textFormat: Text.PlainText
            }

            Row {
                Line { text: "Arch Linux"; color: config.accent }
                Line { text: " (tty1)"; color: config.textDim }
            }
            Item { width: 1; height: 6 * root.s }

            // login: user, click or Tab to switch when there's more than one
            Row {
                Line { text: (sddm.hostName || "arch") + " login: "; color: config.textDim }
                Line {
                    text: root.users.length ? root.users[root.userIndex] : ""
                    color: config.green
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.users.length > 1
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.userIndex = (root.userIndex + 1) % root.users.length
                    }
                }
            }

            // password: typed characters show as dots, with a blinking block cursor
            Row {
                id: pwRow
                Line { id: pwLabel; text: "Password: "; color: config.textDim }
                TextInput {
                    id: password
                    width: term.width - pwLabel.width - 60 * root.s
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    font { family: config.font; pixelSize: 19 * root.s }
                    color: config.text
                    selectionColor: config.accent
                    clip: true
                    focus: true
                    enabled: !root.waiting
                    onAccepted: root.login()
                    onTextChanged: if (text.length && !root.waiting) { root.message = ""; root.failed = false; }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_F2) {
                            root.nextSession();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab && root.users.length > 1) {
                            root.userIndex = (root.userIndex + 1) % root.users.length;
                            event.accepted = true;
                        }
                    }
                    cursorDelegate: Rectangle {
                        width: 11 * root.s
                        color: config.accent
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: password.activeFocus && !root.waiting
                            PropertyAction { value: 1 }
                            PauseAnimation { duration: 560 }
                            PropertyAction { value: 0 }
                            PauseAnimation { duration: 440 }
                        }
                    }
                }
            }

            Line {
                text: root.message || (keyboard.capsLock ? "Caps Lock is on" : (root.waiting ? "Checking..." : " "))
                color: root.failed || keyboard.capsLock ? config.error : config.textDim
            }

            Item { width: 1; height: 10 * root.s }
            Rectangle { width: parent.width; height: 1; color: config.border }

            // footer: session on the left, power on the right
            Item {
                width: parent.width
                height: sessionText.implicitHeight
                Row {
                    spacing: 0
                    Text {
                        text: "session  "
                        font { family: config.font; pixelSize: 15 * root.s }
                        color: config.textDim
                    }
                    Text {
                        id: sessionText
                        text: root.sessions.length ? root.sessions[root.sessionIndex] : ""
                        font { family: config.font; pixelSize: 15 * root.s }
                        color: sessionArea.containsMouse ? config.text : config.purple
                        MouseArea {
                            id: sessionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextSession()
                        }
                    }
                    Text {
                        text: "  [F2]"
                        font { family: config.font; pixelSize: 15 * root.s }
                        color: config.textDim
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 22 * root.s
                    component Action: Text {
                        signal clicked
                        font { family: config.font; pixelSize: 15 * root.s }
                        color: actionArea.containsMouse ? config.text : config.textDim
                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: parent.clicked()
                        }
                    }
                    Action { text: "reboot"; visible: sddm.canReboot; onClicked: sddm.reboot() }
                    Action { text: "poweroff"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
                }
            }
        }
    }

    function tick() {
        const now = new Date();
        let h = now.getHours();
        ampm.text = h < 12 ? "am" : "pm";
        h = h % 12 || 12;
        clock.text = h + ":" + Qt.formatTime(now, "mm");
        date.text = Qt.formatDate(now, "dddd, d MMMM");
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    Component.onCompleted: password.forceActiveFocus()
}

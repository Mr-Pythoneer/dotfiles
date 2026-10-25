pragma ComponentBehavior: Bound

// macOS-style notification centre (local addition, see ~/.config/caelestia/patches).
// Notifications are grouped per app; a group with several notifications is shown as a
// stack that expands on click. Click a notification to read it in full, hover it for an
// X to delete it, and use the header button to clear everything.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property Props props
    required property ScreenState screenState

    // The notification currently opened for reading (one at a time)
    property var openNotif: null
    readonly property int notifCount: Notifs.notClosed.length
    readonly property list<string> apps: {
        const seen = new Set();
        for (const n of Notifs.notClosed)
            seen.add(n.appName);
        return [...seen];
    }

    function isExpanded(app: string): bool {
        return props.expandedNotifs.includes(app);
    }

    function setExpanded(app: string, expand: bool): void {
        if (expand && !isExpanded(app))
            props.expandedNotifs.push(app);
        else if (!expand && isExpanded(app))
            props.expandedNotifs.splice(props.expandedNotifs.indexOf(app), 1);
    }

    function closeApp(app: string): void {
        for (const n of Notifs.notClosed.filter(n => n.appName === app))
            n.close();
        setExpanded(app, false);
    }

    function clearAll(): void {
        for (const n of Notifs.list.slice())
            n.close();
        props.expandedNotifs = [];
        openNotif = null;
    }

    anchors.fill: parent
    anchors.margins: Tokens.padding.medium

    // Opening the centre counts as seeing the popups
    Component.onCompleted: Notifs.list.forEach(n => n.popup = false)

    RowLayout {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            text: root.notifCount > 0 ? qsTr("Notifications · %1").arg(root.notifCount) : qsTr("Notifications")
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.small
            elide: Text.ElideRight
        }

        // Clear all: a round X that widens into "Clear all" on hover, like macOS
        StyledRect {
            id: clearAllBtn

            readonly property bool wide: clearAllHover.hovered

            visible: root.notifCount > 0
            implicitHeight: 28
            implicitWidth: wide ? clearAllRow.implicitWidth + Tokens.padding.medium * 2 : implicitHeight
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
            clip: true

            HoverHandler {
                id: clearAllHover
            }

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: root.clearAll()
            }

            RowLayout {
                id: clearAllRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "close"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    visible: clearAllBtn.wide
                    text: qsTr("Clear all")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            Behavior on implicitWidth {
                Anim {}
            }
        }

        // Power: opens the session menu (lock, log out, sleep, restart, shut down) beside the centre
        StyledRect {
            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: root.screenState.session ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

            StateLayer {
                radius: Tokens.rounding.full
                color: Colours.palette.m3onSurface
                onClicked: root.screenState.session = !root.screenState.session
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "power_settings_new"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    // Empty state
    ColumnLayout {
        anchors.centerIn: parent
        spacing: Tokens.spacing.medium
        opacity: root.notifCount > 0 ? 0 : 1
        visible: opacity > 0

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: "notifications_off"
            color: Colours.palette.m3outlineVariant
            fontStyle: Tokens.font.icon.extraLarge
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("No notifications")
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledFlickable {
        id: view

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Tokens.spacing.medium

        clip: true
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: groupColumn.implicitHeight

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: view
        }

        Column {
            id: groupColumn

            width: view.width
            spacing: Tokens.spacing.medium

            Repeater {
                model: ScriptModel {
                    values: root.apps
                }

                delegate: Group {}
            }
        }
    }

    // One app's notifications: a stack when collapsed, a list when expanded
    component Group: Item {
        id: group

        required property string modelData
        readonly property list<var> notifs: Notifs.notClosed.filter(n => n.appName === modelData)
        readonly property int count: notifs.length
        readonly property bool stacked: count > 1 && !root.isExpanded(modelData)
        readonly property int peek: stacked ? Math.min(count - 1, 2) : 0
        readonly property real peekStep: 8

        width: groupColumn.width
        implicitHeight: stacked ? topCard.implicitHeight + peek * peekStep : expandedCol.implicitHeight
        visible: count > 0

        Behavior on implicitHeight {
            Anim {}
        }

        // --- collapsed: one card with the next two peeking out underneath ---
        Repeater {
            model: group.peek

            delegate: StyledRect {
                required property int index

                z: -1 - index
                x: (index + 1) * Tokens.padding.medium
                width: group.width - x * 2
                y: topCard.implicitHeight - 30 + (index + 1) * group.peekStep
                height: 30
                radius: Tokens.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 3)
                opacity: index === 0 ? 0.9 : 0.55
            }
        }

        Card {
            id: topCard

            visible: group.stacked
            width: group.width
            notif: group.notifs[0] ?? null
            stackCount: group.count
            onActivated: root.setExpanded(group.modelData, true)
            onDismissed: root.closeApp(group.modelData)
        }

        // --- expanded: header + every notification ---
        Column {
            id: expandedCol

            visible: !group.stacked
            width: group.width
            spacing: Tokens.spacing.small

            RowLayout {
                visible: group.count > 1
                width: parent.width
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.small
                    text: group.modelData || qsTr("Unknown app")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.large
                    elide: Text.ElideRight
                }

                Pill {
                    icon: "expand_less"
                    label: qsTr("Show less")
                    onClicked: root.setExpanded(group.modelData, false)
                }

                Pill {
                    icon: "close"
                    label: qsTr("Clear")
                    onClicked: root.closeApp(group.modelData)
                }
            }

            Repeater {
                model: group.stacked ? [] : group.notifs

                delegate: Card {
                    required property var modelData

                    width: expandedCol.width
                    notif: modelData
                    onActivated: root.openNotif = root.openNotif === modelData ? null : modelData
                    onDismissed: {
                        if (root.openNotif === modelData)
                            root.openNotif = null;
                        modelData.close();
                    }
                }
            }
        }
    }

    // A single notification card
    component Card: StyledRect {
        id: card

        property var notif: null
        property int stackCount: 1
        readonly property bool open: root.openNotif !== null && root.openNotif === notif && stackCount === 1
        readonly property bool critical: notif?.urgency === NotificationUrgency.Critical
        readonly property string bodyText: String(notif?.body ?? "")

        signal activated
        signal dismissed

        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: critical ? Colours.palette.m3errorContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        Behavior on implicitHeight {
            Anim {}
        }

        HoverHandler {
            id: cardHover
        }

        StateLayer {
            radius: card.radius
            color: card.critical ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
            onClicked: card.activated()
        }

        RowLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            // App icon / image
            StyledClippingRect {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                radius: Tokens.rounding.medium
                color: card.critical ? Colours.palette.m3error : Colours.palette.m3secondaryContainer

                Image {
                    anchors.fill: parent
                    visible: !!card.notif?.image
                    source: card.notif?.image ? Qt.resolvedUrl(card.notif.image) : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(80, 80)
                    asynchronous: true
                    cache: false
                }

                ColouredIcon {
                    anchors.centerIn: parent
                    visible: !card.notif?.image && !!card.notif?.appIcon
                    implicitSize: 24
                    source: card.notif?.appIcon ? Quickshell.iconPath(card.notif.appIcon) : ""
                    colour: card.critical ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                    layer.enabled: (card.notif?.appIcon ?? "").endsWith("symbolic")
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    visible: !card.notif?.image && !card.notif?.appIcon
                    text: Icons.getNotifIcon(card.notif?.summary ?? "", card.notif?.urgency ?? NotificationUrgency.Normal)
                    color: card.critical ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                // app name · time  (X replaces the time on hover)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: (card.notif?.appName || qsTr("Unknown app")) + (card.stackCount > 1 ? "  ·  " + qsTr("%1 notifications").arg(card.stackCount) : "")
                        color: card.critical ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }

                    Item {
                        implicitWidth: Math.max(timeText.implicitWidth, 22)
                        implicitHeight: 22

                        StyledText {
                            id: timeText

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: cardHover.hovered ? 0 : 1
                            text: card.notif?.timeStr ?? ""
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small

                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        StyledRect {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: Tokens.rounding.full
                            color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 3)
                            opacity: cardHover.hovered ? 1 : 0
                            visible: opacity > 0

                            StateLayer {
                                radius: Tokens.rounding.full
                                onClicked: card.dismissed()
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.notif?.summary ?? ""
                    color: card.critical ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    elide: Text.ElideRight
                    wrapMode: card.open ? Text.WordWrap : Text.NoWrap
                    maximumLineCount: card.open ? 100 : 1
                }

                // Preview: two lines
                StyledText {
                    Layout.fillWidth: true
                    visible: !card.open && card.bodyText.length > 0
                    text: card.bodyText.replace(/<[^>]+>/g, "").replace(/\s*\n\s*/g, " ")
                    color: card.critical ? Colours.palette.m3onErrorContainer : Colours.palette.m3outline
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }

                // Opened: the whole message plus the app's buttons
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: card.open
                    textFormat: Text.MarkdownText
                    text: card.bodyText.replace(/(.)\n(?!\n)/g, "$1\n\n") || qsTr("(no message)")
                    color: card.critical ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                    onLinkActivated: link => {
                        Qt.openUrlExternally(link);
                        root.screenState.sidebar = false;
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    active: card.open && (card.notif?.actions?.length ?? 0) > 0
                    visible: active

                    sourceComponent: NotifActionList {
                        notif: card.notif
                    }
                }
            }
        }
    }

    // Small rounded text button used in group headers
    component Pill: StyledRect {
        id: pill

        property string icon
        property string label

        signal clicked

        implicitHeight: 26
        implicitWidth: pillRow.implicitWidth + Tokens.padding.medium * 2
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StateLayer {
            radius: Tokens.rounding.full
            onClicked: pill.clicked()
        }

        RowLayout {
            id: pillRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: pill.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: pill.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }
        }
    }
}

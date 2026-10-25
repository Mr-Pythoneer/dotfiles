pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property rect dashboardHitRect

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property string position: BarPosition.resolvedPosition(Config.bar.position)
    readonly property bool isHorizontal: BarPosition.isHorizontal(position)

    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int thickness: Tokens.sizes.bar.innerWidth + padding * 2

    readonly property int contentWidth: isHorizontal ? screen.width : thickness
    readonly property int contentHeight: isHorizontal ? thickness : screen.height

    readonly property int clampedWidth: isHorizontal ? screen.width : Math.max(Config.border.minThickness, implicitWidth)
    readonly property int clampedHeight: isHorizontal ? Math.max(Config.border.minThickness, implicitHeight) : screen.height

    // local: a disabled bar (the rice bar replaced it) leaves no frame edge on its side, so the rice bar can sit flush
    // against the screen edge without Caelestia's border drawn over it, see ~/.config/caelestia/patches
    readonly property int edgeThickness: disabled ? 0 : Config.border.thickness
    // and the drawers open above the rice bar instead of under it (Theme.barHeight in ~/.config/quickshell/rice)
    readonly property int replacedBy: disabled && !fullscreen ? 42 : 0
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || screenState.bar) ? thickness : edgeThickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || screenState.bar || isHovered)
    property bool isHovered
    readonly property Item contentItem: (isHorizontal ? horizontalContent.item : verticalContent.item) as Item

    function closeTray(): void {
        (contentItem as Bar)?.closeTray();
    }

    function hasNonTitleEntryAt(along: real): bool {
        return (contentItem as Bar)?.hasNonTitleEntryAt(along) ?? false;
    }

    function checkPopout(along: real): void {
        (contentItem as Bar)?.checkPopout(along);
    }

    function handleWheel(along: real, angleDelta: point): void {
        (contentItem as Bar)?.handleWheel(along, angleDelta);
    }

    clip: true
    visible: (isHorizontal ? height : width) > Config.border.thickness

    width: isHorizontal ? screen.width : implicitWidth
    height: isHorizontal ? implicitHeight : screen.height

    implicitWidth: fullscreen ? 0 : (isHorizontal ? screen.width : edgeThickness)
    implicitHeight: fullscreen ? 0 : (isHorizontal ? edgeThickness : screen.height)

    onIsHorizontalChanged: {
        if (popouts && !popouts.isDetached)
            popouts.hasCurrent = false;
    }

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.isHorizontal ? root.screen.width : root.contentWidth
            root.implicitHeight: root.isHorizontal ? root.contentHeight : root.screen.height
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                properties: "implicitWidth,implicitHeight"
                type: Anim.Emphasized
            }
        }
    ]

    // Keep separate layout instances so an axis switch starts with fresh geometry.
    Loader {
        id: horizontalContent

        anchors.fill: parent
        active: root.shouldBeVisible && root.isHorizontal
        sourceComponent: barContent
    }

    Loader {
        id: verticalContent

        anchors.fill: parent
        active: root.shouldBeVisible && !root.isHorizontal
        sourceComponent: barContent
    }

    Component {
        id: barContent

        Bar {
            isHorizontal: root.isHorizontal
            width: root.width
            height: root.height
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
            dashboardHitRect: root.dashboardHitRect
        }
    }
}

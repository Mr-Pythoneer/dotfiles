//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

// The rice shell: a custom bar (layout from the rice builder, in layout.json) with hover popouts,
// plus a dashboard, control centre, to-do panel and the shelf that rises from the bottom edge.
// Caelestia keeps running for everything else (wallpaper, notifications, launcher, lock screen,
// power menu); its own bar is switched off.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.bar

ShellRoot {
    settings.watchFiles: false

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData

            BarWindow {
                id: barWindow

                modelData: perScreen.modelData
            }

            EdgeTrigger {
                bar: barWindow.content
            }
        }
    }

    IpcHandler {
        target: "panels"

        function toggle(name: string): void {
            Shell.toggle(name, "");
        }

        function open(name: string, page: string): void {
            Shell.open(name, page);
        }

        function close(): void {
            Shell.close();
        }
    }
}

pragma Singleton

import Quickshell
import Quickshell.Services.UPower

// Efficiency mode = the "power-saver" profile (Efficiency in the control centre, or automatic at 20% battery).
// The bar then holds still: no seconds on the clock, no spinners or visualiser, an opaque bar instead of a
// blurred one. ~/.local/bin/eco-mode cuts the rest of the system at the same time.
Singleton {
    readonly property bool eco: PowerProfiles.profile === PowerProfile.PowerSaver
    // the always-moving bits (visualiser, spinning disc) also stop on battery in any mode
    readonly property bool still: eco || UPower.onBattery
}

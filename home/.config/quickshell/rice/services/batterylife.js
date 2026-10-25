.pragma library

// The maths behind BatteryLife.qml, kept apart so it can be tested outside the shell (node).
//
// step(state, reading, now, prior) -> the next state
//   state:   { status, samples: [{ t, e }], watts, rate, ready }   (start from null)
//   reading: { status, e (Wh now), p (W now) }
//   now:     seconds
//   prior:   the discharge rate measured last time on battery (W, 0 if none): the first 3 minutes after
//            unplugging start from it instead of from whatever the draw happens to be at that second
// watts = the current draw, smoothed over ~2 minutes (what "drawing X W" shows)
// rate  = what the estimates divide by: the energy really used (or gained) over the last 10 minutes once
//         there are 3 minutes of it, and the smoothed draw before that. A single reading jumps from 4 to 15 W
//         whenever a page loads or a video pauses; the energy that actually left the battery doesn't.

var WINDOW = 600;       // s of history the rate is worked out over
var MIN_SPAN = 180;     // s of history before the rate is trusted over the smoothed reading
var SMOOTH = 120;       // s, time constant of the smoothed reading
var GAP = 90;           // s without a sample = the laptop slept, start again

function step(state, reading, now, prior) {
    var last = state && state.samples.length ? state.samples[state.samples.length - 1] : null;
    var fresh = !state || reading.status !== state.status || !last || now - last.t > GAP;

    var watts;
    if (fresh) {
        watts = reading.p;
    } else {
        var a = 1 - Math.exp(-(now - last.t) / SMOOTH);
        watts = state.watts + a * (reading.p - state.watts);
    }

    var samples = (fresh ? [] : state.samples).concat([{ t: now, e: reading.e }]).filter(function (s) {
        return now - s.t <= WINDOW;
    });

    var rate = reading.status === "Discharging" && prior > 0.3 ? prior : watts;
    var ready = false;
    var first = samples[0];
    if (now - first.t >= MIN_SPAN) {
        var used = Math.abs(first.e - reading.e) / ((now - first.t) / 3600);
        if (used > 0.2) {
            rate = used;
            ready = true;
        }
    }

    return { status: reading.status, samples: samples, watts: watts, rate: rate, ready: ready };
}

// seconds until the battery runs out (it stops at `reservePct`, where the system shuts down)
function secondsLeft(state, energy, full, reservePct) {
    if (!state || state.status !== "Discharging" || state.rate < 0.3)
        return 0;
    return Math.max(0, energy - full * reservePct / 100) / state.rate * 3600;
}

// seconds until charging stops at `limitPct` (the smart-charge limit, or 100)
function secondsToLimit(state, energy, full, limitPct) {
    if (!state || state.status !== "Charging" || state.rate < 0.3)
        return 0;
    return Math.max(0, full * limitPct / 100 - energy) / state.rate * 3600;
}

-- Hyprland config for Arch on the ThinkPad.
-- Look: dark, sharp corners, no gaps, soft grey border, no blur on windows, faint glow on the focused
--       window and slight dim on the others, springy animations. (The 2026-10-10 rice was rolled back on
--       2026-10-12 except its bar, wallpapers, panels and animations; undo: rice-snapshot restore before-unrice)
-- Shell (launcher, notifications, OSD, lock) and wallpaper: Caelestia. Wallpaper: the ASCII Arch logo
-- (Super+W / Super+Shift+W swap to the circuit board and back; the 15-min rice-wall.timer is off since 2026-10-12).
-- Bar: the rice shell, one full-width strip along the bottom (~/.config/quickshell/rice, layout.json from the rice builder, GitHub Dark colours)
-- with Caelestia's own bar off (bar.excludedScreens in ~/.config/caelestia/shell.json).
-- Changes apply when you save. Check for mistakes with: Hyprland --verify-config

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
require("displays")  -- monitor layouts (F7 to arrange) + workspaces split between monitors, left to right

local terminal    = "kitty"
local fileManager = "kitty -e spf"           -- superfile, in the terminal
local shell       = "caelestia shell "        -- sends a message to the Caelestia shell
local rice        = "qs -c rice ipc call panels "  -- opens the rice bar's panels (~/.config/quickshell/rice)
local lock        = "loginctl lock-session"  -- Caelestia lock screen: touch the fingerprint reader or type your password

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")       -- Qt apps follow qt6ct, which uses Kvantum
hl.env("QS_ICON_THEME", "Papirus-Dark")       -- icons in the Caelestia shell
hl.env("XMODIFIERS", "@im=fcitx")             -- Chinese input (fcitx5) for X11 apps
hl.env("QT_IM_MODULE", "fcitx")               -- Chinese input (fcitx5) for Qt apps

-------------------
---- AUTOSTART ----
-------------------
-- Only what's needed in the first second starts here; tray apps and the reopened apps wait
-- for the bar and start one at a time (login-later), so logging in doesn't stutter.
-- nm-applet, fcitx5 and xwaylandvideobridge also have system autostart entries; those are
-- switched off in ~/.config/autostart so they don't start twice.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("caelestia shell -d")                 -- launcher, notifications, wallpaper, lock (its own bar is off)
    hl.exec_cmd("qs -c rice -d")                      -- the bar, its popouts, dashboard, control centre, to-do
    hl.exec_cmd("fcitx5 -d --replace")                -- Chinese input: Caps Lock switches Chinese/English
    hl.exec_cmd("hypridle")                           -- lock and screen-off when idle
    hl.exec_cmd("wl-paste --watch cliphist store")    -- clipboard history
    hl.exec_cmd("~/.local/bin/mute-light")            -- speaker-mute light on F1
    hl.exec_cmd("~/.local/bin/power-mode")            -- battery: balanced profile, lighter blur, no border shine; charger: performance
    hl.exec_cmd("~/.local/bin/eco-mode watch")        -- efficiency (power-saver) profile: cuts animations, blur, backlight, background jobs, CPU/GPU
    hl.exec_cmd("~/.local/bin/smart-charge daemon")   -- learns when you unplug; holds at 80%, tops up to 100% before then
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
    hl.exec_cmd("~/.local/bin/first-login")           -- one-time theme setup
    hl.exec_cmd("~/.local/bin/session watch")         -- keep the list of open apps up to date
    hl.exec_cmd("~/.local/bin/login-later")           -- tray apps, Alt+Tab, then reopens the apps from last time
    hl.exec_cmd("~/.local/bin/update-check --login")  -- checks for updates + Arch news, one notification
end)

--------------
---- LOOK ----
--------------
hl.config({
    general = {
        gaps_in     = 0,
        gaps_out    = 0,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgb(8f949c)", "rgb(d4d8de)", "rgb(8f949c)"}, angle = 45 },   -- soft grey with a lighter streak (still: borderangle is off)
            inactive_border = "rgb(2c2e33)",
        },
        resize_on_border = true,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        -- focused window gets a faint graphite glow, the rest dim slightly
        shadow = { enabled = true, range = 14, render_power = 2, color = "rgba(8f949c55)", color_inactive = "rgba(00000000)" },
        -- blur only behind the rice bar (layer rule "rice-bar-blur"); windows stay sharp (rule "no-window-blur")
        blur = {
            enabled = true, size = 7, passes = 3,
            noise = 0.015, contrast = 1.0, brightness = 0.85,
            vibrancy = 0.22, vibrancy_darkness = 0.35,
        },
        dim_inactive = true,
        dim_strength = 0.12,
    },
    animations = { enabled = true },
    dwindle  = { preserve_split = true },
    master   = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },
    ecosystem = {
        no_update_news  = true,    -- no "Hyprland updated" popup after updates
        no_donation_nag = true,
    },
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        background_color         = "rgb(17181b)",
        focus_on_activate        = true,
        key_press_enables_dpms   = true,
        mouse_move_enables_dpms  = true,
        animate_manual_resizes        = true,   -- resizing and dragging glide too
        animate_mouse_windowdragging  = true,
    },
    input = {
        kb_layout    = "us",
        kb_file      = "/home/mrpythoneer/.config/hypr/keymap.xkb",  -- US layout, but Caps Lock = F13 (input switch), Shift+Caps = Caps Lock
        follow_mouse = 1,
        sensitivity  = 0,
        numlock_by_default = true,  -- every keyboard starts with NumLock on (login, replug, wake)
        natural_scroll = true,  -- mouse scrolls same direction as touchpad
        touchpad = { natural_scroll = true, disable_while_typing = true },
    },
})

-- Animations: springy. Hyprland 0.56 has real spring physics: windows pop in with a little bounce
-- and settle, the others slide over with a smaller overshoot, and workspaces swing in. Damping ratio = dampening / (2 * sqrt(stiffness * mass)); under 1 bounces.
hl.curve("bounce", { type = "spring", mass = 1, stiffness = 210, dampening = 15 })   -- ratio 0.52: lively
hl.curve("settle", { type = "spring", mass = 1, stiffness = 230, dampening = 21 })   -- ratio 0.69: one small overshoot
hl.curve("swing",  { type = "spring", mass = 1, stiffness = 190, dampening = 19 })   -- ratio 0.69, a bit slower
hl.curve("smooth", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.curve("glide",  { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })          -- fast start, soft landing
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("ease",   { type = "bezier", points = { {0.45, 0}, {0.55, 1} } })          -- gentle both ends

hl.animation({ leaf = "global",      enabled = true, speed = 3,   bezier = "smooth" })
-- windows
hl.animation({ leaf = "windows",     enabled = true, speed = 4.8, spring = "settle" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4.1, spring = "bounce", style = "popin 80%" })  -- pops in, overshoots a touch, settles
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2.5, bezier = "glide",  style = "popin 85%" })  -- shrinks away quickly
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.8, spring = "settle" })                       -- the others sliding over
-- fades
hl.animation({ leaf = "fadeIn",      enabled = true, speed = 3,   bezier = "glide" })
hl.animation({ leaf = "fadeOut",     enabled = true, speed = 2,   bezier = "glide" })
hl.animation({ leaf = "fadeSwitch",  enabled = true, speed = 3,   bezier = "glide" })
hl.animation({ leaf = "fadeDpms",    enabled = true, speed = 8,   bezier = "ease" })   -- screen off/on fades through black
-- border colour fades when focus moves; no moving shine around it
hl.animation({ leaf = "border",      enabled = true,  speed = 3, bezier = "glide" })
hl.animation({ leaf = "borderangle", enabled = false })
-- workspace switch: slides and fades, swinging slightly past and back
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5, spring = "swing",  style = "slidefade 20%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, spring = "bounce", style = "slidefadevert 20%" })  -- Super+S scratchpad drops in from above
-- bar, launcher, notifications, penguin (Caelestia animates its own panels; Hyprland just fades the layers)
hl.animation({ leaf = "layers",      enabled = true, speed = 3,   bezier = "glide", style = "fade" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

------------------
---- KEYBINDS ----
------------------
local mod = "SUPER"

-- Apps
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + Space",  hl.dsp.exec_cmd(shell .. "drawers toggle launcher"))
hl.bind(mod .. " + D",      hl.dsp.exec_cmd(rice .. "toggle dashboard"))    -- the rice dashboard (Home, Media, System, Weather, Dev)
hl.bind(mod .. " + A",      hl.dsp.exec_cmd(rice .. "toggle control"))      -- the rice control centre
hl.bind(mod .. " + B",      hl.dsp.exec_cmd(rice .. "toggle shelf"))        -- the rice shelf (also: rest the pointer on the bottom edge)
hl.bind(mod .. " + N",      hl.dsp.exec_cmd(shell .. "drawers toggle sidebar"))
hl.bind(mod .. " + V",      hl.dsp.exec_cmd("caelestia clipboard"))
hl.bind(mod .. " + Y",      hl.dsp.exec_cmd("~/.local/bin/sysmon-toggle"))   -- btop system monitor (toggle)
hl.bind(mod .. " + W",      hl.dsp.exec_cmd("~/.local/bin/rice-wall next"))   -- next wallpaper
hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/bin/rice-wall prev"))  -- previous wallpaper
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd(lock))                      -- lock (Super+L moves focus)
hl.bind(mod .. " + SHIFT + Escape", hl.dsp.exec_cmd("wlogout"))         -- power menu

-- Windows
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + M",         hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + T",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + O",         hl.dsp.layout("togglesplit"))            -- flip split direction
-- log out through uwsm so the login screen comes back (killing the session leaves a blank console)
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("~/.local/bin/session save; command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown -t 'Logging out...' -p 'uwsm stop' || uwsm stop"))
hl.bind("ALT + Tab",           hl.dsp.exec_cmd("snappy-switcher next"))
hl.bind("ALT + SHIFT + Tab",   hl.dsp.exec_cmd("snappy-switcher prev"))

-- Move between windows with the arrow keys or H J K L; Shift moves the window; Ctrl resizes it
local dirs = { left = "left", right = "right", up = "up", down = "down", H = "left", L = "right", K = "up", J = "down" }
for key, d in pairs(dirs) do
    hl.bind(mod .. " + " .. key,          hl.dsp.focus({ direction = d }))
    hl.bind(mod .. " + SHIFT + " .. key,  hl.dsp.window.move({ direction = d }))
end
-- In the scrolling layout, Ctrl + Left/Right moves the border between the focused column and its
-- neighbour (the one to its right, or to its left at the end of the row): whatever one gains the
-- other loses, so a side-by-side pair stays on screen instead of the neighbour being pushed off
-- the edge. Anywhere else it's a plain resize.
local function resize_pair(dx)
    local win, ws = hl.get_active_window(), hl.get_active_workspace()
    if not (dx ~= 0 and win and ws and ws.tiled_layout == "scrolling" and not win.floating and win.monitor) then
        return false
    end
    local mon = win.monitor
    local mx, mw = mon.x, mon.width / mon.scale
    local function visible(o) return o.at.x < mx + mw - 2 and o.at.x + o.size.x > mx + 2 end
    local right, left
    for _, o in ipairs(ws:get_windows()) do
        if not o.floating and o.stable_id ~= win.stable_id and visible(o) then
            if o.at.x >= win.at.x + win.size.x - 2 and (not right or o.at.x < right.at.x) then right = o end
            if o.at.x + o.size.x <= win.at.x + 2 and (not left or o.at.x > left.at.x) then left = o end
        end
    end
    local nb = right or left
    if not nb then return false end
    local step = dx / mw
    local warps = hl.get_config("cursor:no_warps")
    hl.config({ cursor = { no_warps = true } })  -- the focus hop below mustn't move the pointer
    -- neighbour first, so the pair never overflows the screen in between
    hl.dispatch(hl.dsp.focus({ window = nb }))
    hl.dispatch(hl.dsp.layout(string.format("colresize %+.4f", -step)))
    hl.dispatch(hl.dsp.focus({ window = win }))
    hl.dispatch(hl.dsp.layout(string.format("colresize %+.4f", step)))
    hl.config({ cursor = { no_warps = warps } })
    return true
end

local resize = { left = { -40, 0 }, right = { 40, 0 }, up = { 0, -40 }, down = { 0, 40 },
                 H = { -40, 0 }, L = { 40, 0 }, K = { 0, -40 }, J = { 0, 40 } }
for key, xy in pairs(resize) do
    hl.bind(mod .. " + CTRL + " .. key, function()
        if not resize_pair(xy[1]) then
            hl.dispatch(hl.dsp.window.resize({ x = xy[1], y = xy[2], relative = true }))
        end
    end, { repeating = true })
end

-- Workspaces (each one lives on a fixed monitor, see displays.lua)
-- The numpad works too, NumLock on or off
local numpadOff = { "KP_End", "KP_Down", "KP_Next", "KP_Left", "KP_Begin", "KP_Right", "KP_Home", "KP_Up", "KP_Prior", "KP_Insert" }
for i = 1, 10 do
    local key = i % 10
    for _, k in ipairs({ tostring(key), "KP_" .. key, numpadOff[i] }) do
        hl.bind(mod .. " + " .. k,           hl.dsp.focus({ workspace = i }))
        hl.bind(mod .. " + SHIFT + " .. k,   hl.dsp.window.move({ workspace = i }))
    end
end
hl.bind(mod .. " + S",          hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S",  hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind("mouse:275",            hl.dsp.focus({ workspace = "r+1" }))  -- mouse back side button: workspace to the right
hl.bind("mouse:276",            hl.dsp.focus({ workspace = "r-1" }))  -- mouse forward side button: workspace to the left
hl.bind(mod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- Screenshots (slurp + grim, hyprshot) and annotating (satty); recording (caelestia record → gpu-screen-recorder)
local shots = "~/Pictures/Screenshots"
hl.bind("Print",                   hl.dsp.exec_cmd("~/.local/bin/screenshot-area"))   -- press again to cancel
hl.bind("XF86SelectiveScreenshot", hl.dsp.exec_cmd("~/.local/bin/screenshot-area"))   -- F9, the snipping key
hl.bind("SHIFT + Print",           hl.dsp.exec_cmd("hyprshot -m output -m active -o " .. shots))
hl.bind(mod .. " + SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window -m active -o " .. shots))
hl.bind(mod .. " + SHIFT + R",     hl.dsp.exec_cmd("caelestia record"))   -- toggle start/stop

-- Volume, brightness, media
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })

-- MX Master thumb wheel (sideways scroll; rolling towards the front = right). On its own it scrolls
-- sideways; Super + roll moves focus between windows, Ctrl + roll changes the volume. Scroll binds
-- fire at most once per binds:scroll_event_delay (300 ms), so one roll is one step.
hl.bind(mod .. " + mouse_right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + mouse_left",  hl.dsp.focus({ direction = "left" }))
hl.bind("CTRL + mouse_right", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind("CTRL + mouse_left",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- ThinkPad F-row extras: F7 displays, F8 airplane mode
hl.bind("XF86Display", hl.dsp.exec_cmd("~/.local/bin/displays"))   -- arrange monitors
hl.bind("XF86RFKill",  hl.dsp.exec_cmd("~/.local/bin/airplane-mode"), { locked = true })
hl.bind("XF86WLAN",    hl.dsp.exec_cmd("~/.local/bin/airplane-mode"), { locked = true })

-- Copilot key (it sends Super+Shift+F23): a penguin shows up and does something random
hl.bind(mod .. " + SHIFT + F23", hl.dsp.exec_cmd("~/.local/bin/penguin"))
hl.bind("XF86Assistant",         hl.dsp.exec_cmd("~/.local/bin/penguin"))

-- Spun: pop the cassette deck up over a playing video (again to hide it)
hl.bind(mod .. " + C", hl.dsp.exec_cmd("busctl --user call org.mpris.MediaPlayer2.spun /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 ToggleDeck"))

---------------
---- RULES ----
---------------
hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
hl.window_rule({
    name  = "float-small-tools",
    match = { class = "^(com\\.saivert\\.pwvucontrol|io\\.github\\.kaii_lb\\.Overskride|nwg-displays|dev\\.mrpythoneer\\.displays|dev\\.mrpythoneer\\.bluetooth|dev\\.mrpythoneer\\.keybinds|nm-connection-editor|hyprsysteminfo|waypaper|io\\.github\\.seadve\\.Kooha|com\\.gabm\\.satty)$" },
    float = true,
})
-- Spun's tape deck, popped up over a playing video: float it in the middle of the screen
hl.window_rule({
    name   = "spun-deck-over-video",
    match  = { class = "^(spun)$", title = "^Deck( — Spun)?$" },
    float  = true,
    center = true,
})
-- System monitor (Super+Y): btop in a centered floating window
hl.window_rule({
    name   = "sysmon-float",
    match  = { class = "^(sysmon)$" },
    float  = true,
    size   = "monitor_w*0.7 monitor_h*0.75",
    center = true,
})
-- Screensaver opens straight into fullscreen (never briefly tiling next to the current window),
-- growing in gently from just under full size while it fades up
hl.window_rule({
    name       = "screensaver-fullscreen",
    match      = { class = "^(eyecandy-screensaver)$" },
    fullscreen = true,
    animation  = "popin 96%",
})
-- The screen-share bridge works invisibly in the background
hl.window_rule({
    name  = "hide-xwaylandvideobridge",
    match = { class = "^(xwaylandvideobridge)$" },
    float = true,
    opacity = "0.0 override",
    no_initial_focus = true,
    no_focus = true,
    no_anim = true,
    max_size = "1 1",
})

-- Windows never blur (only the rice bar does, below)
hl.window_rule({ name = "no-window-blur", match = { class = ".*" }, no_blur = true })

-- The same frosted glass behind the rice bar's islands, popouts and panels (~/.config/quickshell/rice)
hl.layer_rule({
    name         = "rice-bar-blur",
    match        = { namespace = "^rice-bar$" },
    blur         = true,
    ignore_alpha = 0.35,
})

-----------------
---- PLUGINS ----
-----------------
require("plugins")

-- Your own shortcuts, made in the Keybinds app (last, so they can replace the ones above)
require("keybinds")

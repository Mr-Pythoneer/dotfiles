-- Plugins.
--   hyprbars   thin title bars with close / maximize buttons (AUR package hyprland-plugin-hyprbars)
--   hymission  window overview, the stand-in for hyprexpo (built in ~/.local/src/hymission)
-- Scrolling layout is built into Hyprland now: Super+G switches between normal tiling and scrolling.

-- True when a plugin is actually loaded (hl.plugin.<name> can exist even when it isn't)
local function has_plugin(name)
    for _, p in pairs(hl.get_loaded_plugins() or {}) do
        if p == name or (type(p) == "table" and p.name == name) then return true end
    end
    return false
end

local overviewPath = os.getenv("HOME") .. "/.local/lib/hyprland/libhymission.so"
local function first_existing(paths)
    for _, p in ipairs(paths) do
        local f = io.open(p, "r")
        if f then f:close(); return p end
    end
end
local barsPath = first_existing({ "/usr/lib/hyprland/libhyprbars.so", "/usr/lib/hyprland/hyprbars.so", "/usr/lib/libhyprbars.so" })
hl.on("hyprland.start", function()
    -- hyprbars needs a reload after loading so its settings below apply; hymission reloads by itself
    if barsPath then hl.exec_cmd("hyprctl plugin load " .. barsPath .. " && hyprctl reload") end
    -- retry for a few seconds: right at startup Hyprland may not accept commands yet
    hl.exec_cmd("sh -c 'test -f " .. overviewPath .. " || exit 0; for i in 1 2 3 4 5 6; do hyprctl plugin list | grep -q hymission && exit 0; hyprctl plugin load " .. overviewPath .. " >/dev/null; sleep 1; done'")
end)

if has_plugin("hyprbars") then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height         = 22,
                bar_color          = "rgb(1d1e22)",
                col                = { text = "rgb(9a9da3)" },
                bar_text_font      = "Inter",
                bar_text_size      = 10,
                bar_text_align     = "left",
                bar_padding        = 10,
                bar_button_padding = 8,
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                icon_on_hover      = true,
                on_double_click    = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })']],
            },
        },
    })
    -- No buttons: the close button sat right where notifications pop up (top right), so dismissing a
    -- notification kept closing windows (removed 2026-10-14). Close with Super+Q, maximize by double-clicking the bar.
    -- No second title bar on apps that already draw their own
    hl.window_rule({
        name  = "no-hyprbars-on-csd-apps",
        match = { class = "^(com\\.saivert\\.pwvucontrol|io\\.github\\.kaii_lb\\.Overskride|xdg-desktop-portal-gtk|nwg-displays|dev\\.mrpythoneer\\.displays|xwaylandvideobridge|eyecandy-screensaver)$" },
        ["hyprbars:no_bar"] = true,
    })
end

if has_plugin("hymission") then
    hl.config({
        plugin = {
            hymission = {
                layout_engine          = "natural",
                only_active_workspace  = true,
                workspace_strip_anchor = "top",
                show_focus_indicator   = true,
                hide_hyprbars_during_overview = true,
                backdrop_color       = "rgba(0c0d0fb3)",
                focus_hover_color    = "rgba(8f949c80)",
                focus_selected_color = "rgba(dcdcd8e6)",
                focus_title_color    = "rgba(dcdcd8ff)",
            },
        },
    })
    hl.plugin.hymission.gesture({ fingers = 3, direction = "vertical", action = "toggle" })
    hl.bind("SUPER + Tab", function() hl.plugin.hymission.toggle() end)
end

-- Switch this workspace between normal tiling and the scrolling layout
hl.bind("SUPER + G", function()
    local scrolling = hl.get_config("general:layout") ~= "scrolling"
    hl.config({ general = { layout = scrolling and "scrolling" or "dwindle" } })
end)

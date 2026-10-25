-- Made by the Keybinds app (~/.local/bin/keybinds) from keybinds.json: edit shortcuts there,
-- changes to this file get overwritten. Loaded last from hyprland.lua.

local run = "~/.local/bin/keybind-run "


-- While the app records a shortcut it switches to this empty submap, so keys that already do
-- something reach the app instead. Escape (or the app) switches back.
hl.define_submap("keybinds-capture", function()
    hl.bind("Escape", hl.dsp.submap("reset"), { non_consuming = true })
end)

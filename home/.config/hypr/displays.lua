-- Displays: puts each monitor where you last arranged it, and splits workspaces 1-10 between
-- the monitors from left to right (two monitors: 1-5 on the left one, 6-10 on the right one).
--
--   Layouts live in display-profiles.lua, one per set of connected monitors, keyed by the
--   monitors' descriptions, so a screen keeps its spot whichever port it's plugged into.
--   Arrange them with F7 (~/.local/bin/displays). An unknown setup puts the externals to the
--   left of the laptop screen until you arrange them. Any arrangement change (F7, nwg-displays,
--   hyprctl) is remembered automatically, so a replugged screen goes back to the same side.
--   Check what's going on with: hyprctl repl 'return Displays.status()'

local M = {}
local profilesPath = os.getenv("HOME") .. "/.config/hypr/display-profiles.lua"
local WORKSPACES = 10

local function is_builtin(m)
    return m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI")
end

-- Connected monitors, left to right (top to bottom when stacked)
local function monitors()
    local list = {}
    for _, m in ipairs(hl.get_monitors()) do
        if not m.is_mirror then list[#list + 1] = m end
    end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return list
end

-- Same key the arranger uses: descriptions sorted and joined
function M.setup_key()
    local descs = {}
    for _, m in ipairs(monitors()) do descs[#descs + 1] = m.description end
    table.sort(descs)
    return table.concat(descs, " + ")
end

local function load_profiles()
    local chunk = loadfile(profilesPath)
    if not chunk then return {} end
    local ok, t = pcall(chunk)
    return (ok and type(t) == "table") and t or {}
end

local function place(m, x, y, mode, scale)
    hl.monitor({
        output   = "desc:" .. m.description,
        mode     = mode or "preferred",
        position = x .. "x" .. y,
        scale    = scale or m.scale,
    })
end

-- Put the monitors where the saved layout says, or externals-left-of-laptop when there's none
local warned = {}
function M.apply_layout()
    local mons = monitors()
    if #mons == 0 then return end
    local key = M.setup_key()
    local profile = load_profiles()[key]
    if profile then
        local byDesc = {}
        for _, m in ipairs(mons) do byDesc[m.description] = m end
        for _, p in ipairs(profile) do
            local m = byDesc[p.desc]
            if m then place(m, p.x, p.y, p.mode, p.scale) end
        end
    elseif #mons > 1 then
        local externals, builtin = {}, nil
        for _, m in ipairs(mons) do
            if is_builtin(m) and not builtin then builtin = m else externals[#externals + 1] = m end
        end
        table.sort(externals, function(a, b) return a.name < b.name end)
        local x = 0
        for _, m in ipairs(externals) do
            place(m, x, 0, nil, m.scale)
            x = x + math.floor(m.width / m.scale)
        end
        if builtin then place(builtin, x, 0, nil, builtin.scale) end
        if not warned[key] then
            warned[key] = true
            hl.exec_cmd("notify-send -a Displays 'New display setup' 'External screens went on the left. Press F7 to arrange them.'")
        end
    end
end

-- Which workspaces each monitor gets: 10 split as evenly as possible, extras to the left
M.ranges = {}
local rules = {}
function M.split_workspaces()
    local mons = monitors()
    local n = #mons
    if n == 0 then return end

    for _, r in ipairs(rules) do r:set_enabled(false) end
    rules, M.ranges = {}, {}

    local first = 1
    for i, m in ipairs(mons) do
        local count = math.floor(WORKSPACES / n) + ((i <= WORKSPACES % n) and 1 or 0)
        if count > 0 then
            M.ranges[m.name] = { first = first, last = first + count - 1 }
            for id = first, first + count - 1 do
                rules[#rules + 1] = hl.workspace_rule({ workspace = tostring(id), monitor = m.name, default = (id == first) })
            end
            first = first + count
        end
    end

    -- Move workspaces that are on the wrong monitor
    for _, w in ipairs(hl.get_workspaces()) do
        if not w.special and w.id >= 1 and w.id <= WORKSPACES then
            for name, r in pairs(M.ranges) do
                if w.id >= r.first and w.id <= r.last and w.monitor and w.monitor.name ~= name then
                    hl.dispatch(hl.dsp.workspace.move({ workspace = w.id, monitor = name }))
                end
            end
        end
    end

    -- Each monitor shows one of its own workspaces: the lowest one with windows, else its first.
    -- (An empty one Hyprland made up to fill a gap doesn't count.)
    local focused = hl.get_active_monitor()
    local refocus = false
    for _, m in ipairs(monitors()) do
        local r = M.ranges[m.name]
        local aw = m.active_workspace
        local inRange = r and aw and aw.id >= r.first and aw.id <= r.last
        if r and not (inRange and (aw.id == r.first or not aw.is_empty)) then
            local target
            for id = r.first, r.last do
                local w = hl.get_workspace(id)
                if w and not w.is_empty and w.monitor and w.monitor.name == m.name then target = w; break end
            end
            hl.dispatch(hl.dsp.focus({ workspace = target and target.id or r.first }))
            refocus = true
        end
    end
    if refocus and focused then hl.dispatch(hl.dsp.focus({ monitor = focused.name })) end
end

-- Remember the current arrangement for this set of monitors, however it was made (F7, nwg-displays,
-- hyprctl...), so it comes back the next time the same screens are plugged in.
local function lua_str(s) return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end

function M.remember_layout()
    local mons = monitors()
    if #mons < 2 then return end
    local key = M.setup_key()
    local profiles = load_profiles()
    local entries, changed = {}, false
    local old = {}
    for _, p in ipairs(profiles[key] or {}) do old[p.desc] = p end
    for _, m in ipairs(mons) do
        local mode = string.format("%dx%d@%s", m.width, m.height, string.format("%.2f", m.refresh_rate):gsub("%.?0+$", ""))
        local o = old[m.description]
        if not o or o.x ~= m.x or o.y ~= m.y or tonumber(o.scale) ~= tonumber(m.scale) then changed = true end
        entries[#entries + 1] = { desc = m.description, mode = (o and o.mode) or mode, x = m.x, y = m.y, scale = m.scale }
    end
    if not changed then return end
    profiles[key] = entries

    -- same format the arranger writes and parses
    local keys = {}
    for k in pairs(profiles) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = { "-- Saved display layouts, written by ~/.local/bin/displays (F7). One entry per set of connected",
                  '-- monitors; the key is their descriptions, sorted and joined with " + ".', "return {" }
    for _, k in ipairs(keys) do
        out[#out + 1] = "    [" .. lua_str(k) .. "] = {"
        for _, p in ipairs(profiles[k]) do
            out[#out + 1] = string.format("        { desc = %s, mode = %s, x = %d, y = %d, scale = %s },",
                lua_str(p.desc), lua_str(p.mode), p.x, p.y, string.format("%g", p.scale))
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    local f = io.open(profilesPath .. ".tmp", "w")
    if not f then return end
    f:write(table.concat(out, "\n") .. "\n")
    f:close()
    os.rename(profilesPath .. ".tmp", profilesPath)
end

-- Monitors arrive one at a time on plug-in, so wait for things to settle before acting.
-- A plug/unplug is always followed by a layout_changed event; the layout restore it asked for
-- must survive that, or the screen ends up wherever Hyprland's auto placement put it.
local timer, splitTimer
local pendingLayout = false
local function schedule(withLayout)
    pendingLayout = pendingLayout or withLayout
    local run = function()
        local restoring = pendingLayout
        pendingLayout = false
        if restoring then
            M.apply_layout()
        else
            M.remember_layout()  -- the user moved a screen: keep it that way
        end
        -- the layout change has to land before workspaces are split by position
        splitTimer = hl.timer(M.split_workspaces, { timeout = 300, type = "oneshot" })
    end
    if timer then timer:set_enabled(false) end
    timer = hl.timer(run, { timeout = 500, type = "oneshot" })
end
M.refresh = function() schedule(true) end

function M.status()
    local out = { "setup: " .. M.setup_key() }
    for _, m in ipairs(monitors()) do
        local r = M.ranges[m.name]
        out[#out + 1] = string.format("%s (%s) at %dx%d: workspaces %s", m.name, m.description, m.x, m.y,
            r and (r.first .. "-" .. (r.last % 10)) or "none")
    end
    return table.concat(out, "\n")
end

hl.on("monitor.added",   function() schedule(true) end)
hl.on("monitor.removed", function() schedule(true) end)
hl.on("monitor.layout_changed", function() schedule(false) end)  -- e.g. after nwg-displays: remembered
schedule(true)  -- at startup and on every config reload

Displays = M  -- reachable from hyprctl repl / the arranger
return M

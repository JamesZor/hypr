-- Port of hyprland/keybindings.conf (83 binds). Command strings kept byte-identical,
-- including the undefined $jupyter and $focusRofi.
local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "dolphin"
local menu = "rofi -show drun"
local browser = "firefox"

local function k(mods, key)
  if mods == "" then return key end
  return mods .. " + " .. key
end

-- A key that ran two dispatchers still runs both, in order
local function both(a, b)
  return function()
    hl.dispatch(a)
    hl.dispatch(b)
  end
end

-- Workspace switching/movement (relative)
hl.bind(k(mainMod .. " + SHIFT", "j"), hl.dsp.focus({ workspace = "m-1" }))
hl.bind(k(mainMod .. " + SHIFT", "k"), hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + CONTROL + Z", hl.dsp.focus({ workspace = "r-1" }))
hl.bind("SUPER + CONTROL + X", hl.dsp.focus({ workspace = "r+1" }))
hl.bind("SUPER + SHIFT + Z", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind("SUPER + SHIFT + X", hl.dsp.window.move({ workspace = "r+1" }))

-- Move focus
hl.bind(k(mainMod, "h"), hl.dsp.focus({ direction = "left" }))
hl.bind(k(mainMod, "l"), hl.dsp.focus({ direction = "right" }))
hl.bind(k(mainMod, "k"), hl.dsp.focus({ direction = "up" }))
hl.bind(k(mainMod, "j"), hl.dsp.focus({ direction = "down" }))

-- Workspace switching/movement (absolute): slot N of the focused monitor's own bank, 0 = slot 10.
-- The bank starts at the workspace of the first enabled `default = true` rule in the active profile
-- whose monitor selector matches the monitor the way Hyprland does (CMonitor::matchesStaticSelector:
-- "desc:X" = description starts with X, anything else = connector name). Monitor ids are not used.
-- The profile is read once here, at config load, so the banks always match the workspace rules
-- registered by lua/modules/workspaces.lua in the same load (a profile switch reloads the config).
local bank_rules = nil -- profile `workspaces` list, nil when the profile could not be read
do
  local ok, rules = pcall(function()
    local name = require("lua.state.active_profile")
    if type(name) ~= "string" then return nil end
    local profile = require("lua.profiles." .. name)
    if type(profile) ~= "table" or type(profile.workspaces) ~= "table" then return nil end
    local copy = {}
    for _, w in ipairs(profile.workspaces) do
      if type(w) == "table" then
        copy[#copy + 1] = { workspace = w.workspace, monitor = w.monitor, default = w.default, enabled = w.enabled }
      end
    end
    return copy
  end)
  if ok then bank_rules = rules end
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A bank start is a positive whole number (a string of digits or an integer-valued number) below 10^18
local function whole(v)
  local n
  if type(v) == "string" then
    local s = trim(v)
    if not s:match("^%d+$") then return nil end
    s = s:gsub("^0+", "")
    if s == "" or #s > 18 then return nil end
    n = math.tointeger(tonumber(s))
  elseif type(v) == "number" then
    n = math.tointeger(v)
    if n and n >= 1000000000000000000 then return nil end
  end
  if n and n >= 1 then return n end
  return nil
end

local function selector_matches(sel, name, desc)
  if type(sel) ~= "string" then return false end
  if sel:sub(1, 5) == "desc:" then
    local want = trim(sel:sub(6))
    return type(desc) == "string" and desc:sub(1, #want) == want -- plain prefix, never a pattern
  end
  return type(name) == "string" and sel == name
end

-- Bank start of the focused monitor, or nil plus a short reason
local function focused_bank()
  local ok, mon = pcall(hl.get_active_monitor)
  if not ok or mon == nil then return nil, "no focused monitor" end
  -- Monitor objects are userdata: read fields by name only
  local okf, name, desc = pcall(function() return mon.name, mon.description end)
  if not okf then return nil, "monitor unreadable" end
  if type(bank_rules) ~= "table" then return nil, "active profile not loaded" end
  for _, w in ipairs(bank_rules) do
    if w.default == true and w.enabled ~= false and selector_matches(w.monitor, name, desc) then
      local start = whole(w.workspace)
      if not start then return nil, "default workspace of " .. tostring(name) .. " is not a number" end
      return start
    end
  end
  return nil, "no workspace bank for " .. tostring(name)
end

local function notify(text)
  pcall(hl.notification.create, { text = "hypr: " .. text, duration = 3000 })
end

local function number_key(slot, make)
  return function()
    local ok, start, why = pcall(focused_bank)
    if not ok then start, why = nil, "workspace bank lookup failed" end
    if not start then
      notify(why or "no workspace bank")
      return
    end
    local okd = pcall(function() hl.dispatch(make({ workspace = start + slot - 1 })) end)
    if not okd then notify("workspace " .. (start + slot - 1) .. " dispatch failed") end
  end
end

for key = 0, 9 do
  local slot = key == 0 and 10 or key
  hl.bind("SUPER + " .. key, number_key(slot, function(t) return hl.dsp.focus(t) end))
  hl.bind("SUPER + SHIFT + " .. key, number_key(slot, function(t) return hl.dsp.window.move(t) end))
end

-- Swapping workspaces between monitors
hl.bind("SUPER + SHIFT + S", hl.dsp.workspace.swap_monitors({ monitor1 = "0", monitor2 = "1" }))

-- Monitor focus switching
hl.bind("SUPER + period", hl.dsp.focus({ monitor = "+1" }))
hl.bind("SUPER + comma", hl.dsp.focus({ monitor = "-1" }))

-- Window resizing
hl.bind("SUPER + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
hl.bind("SUPER + left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
hl.bind("SUPER + up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
hl.bind("SUPER + down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })

-- Move active window
hl.bind("CTRL + SUPER + left", hl.dsp.window.move({ direction = "left" }))
hl.bind("CTRL + SUPER + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("CTRL + SUPER + up", hl.dsp.window.move({ direction = "up" }))
hl.bind("CTRL + SUPER + down", hl.dsp.window.move({ direction = "down" }))

-- Application launching
hl.bind(k(mainMod, "W"), hl.dsp.exec_cmd(browser))
hl.bind(k(mainMod, "i"), hl.dsp.exec_cmd("$jupyter"))
hl.bind(k(mainMod, "return"), hl.dsp.exec_cmd(terminal))
hl.bind(k(mainMod, "C"), hl.dsp.window.close())
hl.bind(k(mainMod, "p"), hl.dsp.exit())
hl.bind(k(mainMod, "E"), hl.dsp.exec_cmd(fileManager))
hl.bind(k(mainMod, "V"), hl.dsp.window.float({ action = "toggle" }))
hl.bind(k(mainMod, "g"), hl.dsp.exec_cmd("/home/james/.config/hypr/scripts/remote_grab.sh"))
hl.bind(k(mainMod, "R"), hl.dsp.exec_cmd(menu .. " $focusRofi"))
hl.bind(k(mainMod, "P"), hl.dsp.window.pseudo())
hl.bind(k(mainMod .. " + SHIFT", "M"), hl.dsp.exec_cmd("~/.config/hypr/scripts/switch_monitors.sh"))
hl.bind(k(mainMod, "T"), hl.dsp.exec_cmd("~/.config/hypr/scripts/switch_layout.sh"))
hl.bind(k(mainMod, "Tab"), hl.dsp.layout("cyclenext"))
hl.bind(k(mainMod, "y"), hl.dsp.exec_cmd("~/.config/hypr/scripts/open-alacritty-here.sh"))

-- Hardware controls
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 10%-"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +10%"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl -- set-sink-volume @DEFAULT_SINK@ +5%"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl -- set-sink-volume @DEFAULT_SINK@ -5%"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"))

-- Scroll through existing workspaces
hl.bind(k(mainMod, "n"), hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB
hl.bind(k(mainMod, "mouse:272"), hl.dsp.window.drag(), { mouse = true })
hl.bind(k(mainMod, "mouse:273"), hl.dsp.window.resize(), { mouse = true })

-- tmux-style monitor move mode
hl.bind(k(mainMod, "M"), both(hl.dsp.exec_cmd("~/.config/hypr/scripts/monitor_overlay.sh"), hl.dsp.submap("movemode")))

hl.define_submap("movemode", function()
  local function leave(key, cmd)
    hl.bind(key, both(hl.dsp.exec_cmd(cmd), hl.dsp.submap("reset")))
  end
  leave("1", "~/.config/hypr/scripts/move_to_monitor.sh 1")
  leave("2", "~/.config/hypr/scripts/move_to_monitor.sh 2")
  leave("3", "~/.config/hypr/scripts/move_to_monitor.sh 3")
  leave("left", "~/.config/hypr/scripts/move_to_monitor_dir.sh l")
  leave("right", "~/.config/hypr/scripts/move_to_monitor_dir.sh r")
  leave("up", "~/.config/hypr/scripts/move_to_monitor_dir.sh u")
  leave("down", "~/.config/hypr/scripts/move_to_monitor_dir.sh d")
  leave("escape", "~/.config/hypr/scripts/kill_monitor_overlay.sh")
  leave("catchall", "~/.config/hypr/scripts/kill_monitor_overlay.sh")
end)

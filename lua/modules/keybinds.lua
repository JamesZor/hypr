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
hl.bind(k(mainMod, "O"), hl.dsp.exec_cmd("python3 ~/.config/hypr/scripts/overview.py"))
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

-- Whole-workspace transfer from move mode (D-072). Bank lookup reuses the E4/01 rule above.
local OVERLAY_CLASS = "hypr-monitor-overlay"
local KILL_OVERLAY = "~/.config/hypr/scripts/kill_monitor_overlay.sh"

local function field(obj, k)
  if obj == nil then return nil end
  local ok, v = pcall(function() return obj[k] end)
  if ok then return v end
  return nil
end

local function bank_of(name, desc)
  if type(bank_rules) ~= "table" then return nil end
  for _, w in ipairs(bank_rules) do
    if w.default == true and w.enabled ~= false and selector_matches(w.monitor, name, desc) then
      return whole(w.workspace)
    end
  end
  return nil
end

local function ws_number(ws)
  if ws == nil or field(ws, "special") == true then return nil end
  local id = field(ws, "id")
  if type(id) ~= "number" then return nil end
  id = math.tointeger(id)
  if id and id >= 1 then return id end
  return nil
end

local function mon_info(m)
  local name = field(m, "name")
  if type(name) ~= "string" then return nil end
  local num = function(v) return type(v) == "number" and v or 0 end
  local x, y = num(field(m, "x")), num(field(m, "y"))
  local w, h = num(field(m, "width")), num(field(m, "height"))
  return { name = name, desc = field(m, "description"), x = x, y = y, cx = x + w / 2, cy = y + h / 2,
    shows = ws_number(field(m, "active_workspace")) }
end

local function pick_destination(src, mons, how)
  if type(how) == "number" then
    local sorted = {}
    for i, m in ipairs(mons) do sorted[i] = m end
    table.sort(sorted, function(a, b)
      if a.x ~= b.x then return a.x < b.x end
      if a.y ~= b.y then return a.y < b.y end
      return a.name < b.name
    end)
    return sorted[how], "no screen " .. how
  end
  local best, bp, bs
  for _, m in ipairs(mons) do
    if m.name ~= src.name then
      local p, s
      if how == "left" then p, s = src.cx - m.cx, math.abs(m.cy - src.cy)
      elseif how == "right" then p, s = m.cx - src.cx, math.abs(m.cy - src.cy)
      elseif how == "up" then p, s = src.cy - m.cy, math.abs(m.cx - src.cx)
      else p, s = m.cy - src.cy, math.abs(m.cx - src.cx) end
      if p > 0 and (best == nil or p < bp or (p == bp and s < bs)) then best, bp, bs = m, p, s end
    end
  end
  return best, "no screen " .. how
end

local function transfer(how)
  local src = mon_info(hl.get_active_monitor())
  if not src then return notify("no focused monitor") end
  local wid = src.shows
  if not wid then return notify("this workspace cannot be moved (named or special)") end
  -- Snapshot every window: workspace number, screen, overlay or not
  local all = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = field(w, "workspace")
    local addr = field(w, "address")
    local fh = field(w, "focus_history_id")
    all[#all + 1] = { addr = type(addr) == "string" and addr or nil, ws = ws_number(ws),
      mon = field(field(w, "monitor"), "name") or field(field(ws, "monitor"), "name"),
      overlay = field(w, "class") == OVERLAY_CLASS, focus = type(fh) == "number" and fh or nil }
  end
  local moving = {}
  for _, w in ipairs(all) do
    if w.ws == wid and not w.overlay and w.addr then moving[#moving + 1] = w end
  end
  if #moving == 0 then return notify("workspace " .. wid .. " has no windows to move") end
  local mons = {}
  for _, m in ipairs(hl.get_monitors() or {}) do
    local i = mon_info(m)
    if i then mons[#mons + 1] = i end
  end
  local dst, why = pick_destination(src, mons, how)
  if not dst then return notify(why) end
  if dst.name == src.name then return end
  local start = bank_of(dst.name, dst.desc)
  if not start then return notify("no workspace bank for " .. dst.name) end
  local used = {}
  for _, w in ipairs(all) do if w.ws and not w.overlay then used[w.ws] = true end end
  local shown = {}
  for _, m in ipairs(mons) do if m.shows then shown[m.shows] = m.name end end
  local target
  for n = start, start + 9 do
    if not used[n] and not shown[n] then target = n break end
  end
  if not target then return notify("workspace bank of " .. dst.name .. " is full") end
  for _, w in ipairs(moving) do
    hl.dispatch(hl.dsp.window.move({ workspace = target, window = "address:" .. w.addr, follow = false }))
  end
  -- Source shows its most recently used remaining workspace, else its bank start
  local back, bf
  for _, w in ipairs(all) do
    if w.ws and w.ws ~= wid and not w.overlay and w.mon == src.name and w.focus and w.focus >= 0
      and (bf == nil or w.focus < bf) then
      back, bf = w.ws, w.focus
    end
  end
  if not back then
    local s = bank_of(src.name, src.desc)
    if s and (shown[s] == nil or shown[s] == src.name) then
      local okw, ws = pcall(hl.get_workspace, s)
      local home = okw and ws and field(field(ws, "monitor"), "name") or nil
      if home == nil or home == src.name then back = s end
    end
  end
  if back then
    hl.dispatch(hl.dsp.focus({ monitor = src.name }))
    hl.dispatch(hl.dsp.focus({ workspace = back }))
  end
  hl.dispatch(hl.dsp.focus({ monitor = dst.name }))
  hl.dispatch(hl.dsp.focus({ workspace = target }))
end

local function transfer_key(how)
  return function()
    local ok = pcall(transfer, how)
    if not ok then notify("workspace move failed") end
    pcall(hl.dispatch, hl.dsp.exec_cmd(KILL_OVERLAY))
    pcall(hl.dispatch, hl.dsp.submap("reset"))
  end
end

-- Swap window sets, not workspaces (D-075). An open special workspace also blocks a swap.
local function swap_mon_info(m)
  local info = mon_info(m)
  if info and field(m, "active_special_workspace") ~= nil then info.shows = nil end
  return info
end

local function swap(how)
  local src = swap_mon_info(hl.get_active_monitor())
  if not src then return "no focused monitor" end
  local mons = {}
  for _, m in ipairs(hl.get_monitors() or {}) do
    local i = swap_mon_info(m)
    if i then mons[#mons + 1] = i end
  end
  local dst, why = pick_destination(src, mons, how)
  if not dst then return why end
  if dst.name == src.name then return end
  local a, b = src.shows, dst.shows
  if not a or not b then return "cannot swap a named or special workspace" end

  -- Snapshot addresses in both directions before dispatching either move.
  local from_a, from_b = {}, {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = ws_number(w.workspace)
    if (ws == a or ws == b) and w.class ~= OVERLAY_CLASS then
      local addr = w.address
      if type(addr) ~= "string" or addr == "" then return "cannot read window address for swap" end
      local from = ws == a and from_a or from_b
      from[#from + 1] = addr
    end
  end
  if #from_a == 0 and #from_b == 0 then return "neither workspace has windows to swap" end

  local function move_to(addresses, workspace)
    for _, addr in ipairs(addresses) do
      hl.dispatch(hl.dsp.window.move({ workspace = workspace, window = "address:" .. addr, follow = false }))
    end
  end
  move_to(from_a, b)
  move_to(from_b, a)
end

local function swap_key(how)
  return function()
    local ok, why = pcall(swap, how)
    if not ok then why = "workspace swap failed" end
    if why then pcall(notify, why) end
    -- Protect dispatcher creation too, and still reset if the overlay command fails.
    pcall(function() hl.dispatch(hl.dsp.exec_cmd(KILL_OVERLAY)) end)
    pcall(function() hl.dispatch(hl.dsp.submap("reset")) end)
  end
end

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
  for _, how in ipairs({ 1, 2, 3, "left", "right", "up", "down" }) do
    hl.bind("SHIFT + " .. how, transfer_key(how))
    hl.bind("CTRL + " .. how, swap_key(how))
  end
  leave("escape", "~/.config/hypr/scripts/kill_monitor_overlay.sh")
  leave("catchall", "~/.config/hypr/scripts/kill_monitor_overlay.sh")
end)

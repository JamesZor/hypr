-- Validate the palettes, then build the theme bundle or prepare a merged config.
local palette_file, mode = arg[1], arg[2]
local palette = assert(loadfile(palette_file, "t", {}))()
local function plain_table(value)
  return type(value) == "table" and getmetatable(value) == nil
end

local function colour(value)
  return type(value) == "string" and value:match("^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$")
end

local keys = {
  "bg", "bg1", "bg2", "fg", "muted", "focus", "inactive", "sel_bg", "sel_fg", "on_focus",
  "red", "orange", "yellow", "green", "aqua", "blue", "purple",
}
local modes = { "dark", "light" }
assert(plain_table(palette), "expected a palette table")
for key in pairs(palette) do
  assert(key == "dark" or key == "light", "unexpected palette mode")
end
for _, name in ipairs(modes) do
  local p = palette[name]
  assert(plain_table(p), "missing " .. name .. " palette")
  local count = 0
  for _ in pairs(p) do count = count + 1 end
  assert(count == #keys + 1, "wrong number of colours in " .. name)
  for _, key in ipairs(keys) do
    assert(colour(p[key]), "invalid colour: " .. name .. "." .. key)
  end
  assert(plain_table(p.ansi), "missing ANSI colours in " .. name)
  for key in pairs(p.ansi) do
    assert(math.type(key) == "integer" and key >= 1 and key <= 16, "unexpected ANSI key in " .. name)
  end
  for i = 1, 16 do
    assert(colour(p.ansi[i]), "invalid ANSI colour in " .. name .. " at index " .. i)
  end
end

local kitty = {
  { "foreground", "fg" }, { "background", "bg" },
  { "selection_foreground", "sel_fg" }, { "selection_background", "sel_bg" },
  { "cursor", "fg" }, { "cursor_text_color", "bg" }, { "url_color", "blue" },
  { "active_tab_foreground", "sel_fg" }, { "active_tab_background", "sel_bg" },
  { "inactive_tab_foreground", "muted" }, { "inactive_tab_background", "bg1" },
  { "active_border_color", "focus" }, { "inactive_border_color", "inactive" },
}
local gtk3 = {
  { "theme_bg_color", "bg1" }, { "theme_fg_color", "fg" },
  { "theme_base_color", "bg" }, { "theme_text_color", "fg" },
  { "theme_selected_bg_color", "sel_bg" }, { "theme_selected_fg_color", "sel_fg" },
  { "insensitive_bg_color", "bg1" }, { "insensitive_fg_color", "muted" }, { "insensitive_base_color", "bg" },
  { "borders", "bg2" }, { "warning_color", "yellow" }, { "error_color", "red" }, { "success_color", "green" },
}
local gtk4 = {
  { "accent-bg-color", "focus" }, { "accent-fg-color", "on_focus" }, { "accent-color", "green" },
  { "window-bg-color", "bg1" }, { "window-fg-color", "fg" },
  { "view-bg-color", "bg" }, { "view-fg-color", "fg" },
  { "headerbar-bg-color", "bg1" }, { "headerbar-fg-color", "fg" },
  { "popover-bg-color", "bg1" }, { "popover-fg-color", "fg" },
  { "dialog-bg-color", "bg1" }, { "dialog-fg-color", "fg" },
  { "sidebar-bg-color", "bg1" }, { "sidebar-fg-color", "fg" },
  { "success-color", "green" }, { "warning-color", "yellow" }, { "error-color", "red" },
  { "destructive-color", "red" },
}

local rofi = [[
* {
    font: "IBM Plex Mono 11";
    background-color: transparent;
    text-color: %s;
}
window {
    background-color: %sf0;
    border: 2px;
    border-color: %s;
    border-radius: 4px;
}
element selected.normal {
    background-color: %s;
    text-color: %s;
}
element normal.normal {
    background-color: transparent;
    text-color: %s;
}
element alternate.normal {
    background-color: transparent;
    text-color: %s;
}
element-text {
    background-color: inherit;
    text-color: inherit;
}
prompt {
    text-color: %s;
}
entry {
    text-color: %s;
}
]]

local function render(lines, mapping, fmt, colours)
  for _, entry in ipairs(mapping) do
    lines[#lines + 1] = fmt:format(entry[1], colours[entry[2]])
  end
  return lines
end

-- QPalette::ColorRole order in Qt 6.12. Entries are role, palette key (dark or
-- both), and an optional light key.
local qt_roles = {
  { "WindowText", "fg" }, { "Button", "bg1" }, { "Light", "bg2", "bg" }, { "Midlight", "bg2", "bg" },
  { "Dark", "bg", "inactive" }, { "Mid", "bg", "bg2" }, { "Text", "fg" }, { "BrightText", "on_focus" },
  { "ButtonText", "fg" }, { "Base", "bg" }, { "Window", "bg1" }, { "Shadow", "bg", "inactive" },
  { "Highlight", "sel_bg" }, { "HighlightedText", "sel_fg" }, { "Link", "blue" }, { "LinkVisited", "purple" },
  { "AlternateBase", "bg1" }, { "NoRole", "bg" }, { "ToolTipBase", "bg1" }, { "ToolTipText", "fg" },
  { "PlaceholderText", "muted" }, { "Accent", "focus" },
}
local qt_disabled = {
  WindowText = "muted", Text = "muted", ButtonText = "muted", HighlightedText = "muted",
  PlaceholderText = "muted", Highlight = "bg2", Accent = "inactive",
}

local function mode_value(entry, name)
  return (name == "light" and entry[3]) or entry[2]
end

local function qt_colours(p)
  local active, disabled = {}, {}
  for i, role in ipairs(qt_roles) do
    local key = mode_value(role, mode)
    active[i] = "#ff" .. p[key]:sub(2)
    disabled[i] = "#ff" .. p[qt_disabled[role[1]] or key]:sub(2)
  end
  local colours = table.concat(active, ", ")
  return ("[ColorScheme]\nactive_colors=%s\ninactive_colors=%s\ndisabled_colors=%s\n")
    :format(colours, colours, table.concat(disabled, ", "))
end

-- Ordered groups and keys; each entry has a dark value and optional light value.
local function qt_settings(state)
  return {
    { "Appearance", {
      { "color_scheme_path", '"' .. state .. '/qt6ct-colors.conf"' },
      { "custom_palette", "true" }, { "icon_theme", "breeze-dark", "breeze" },
    } },
    { "Fonts", {
      { "general", '"IBM Plex Sans,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"' },
      { "fixed", '"IBM Plex Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"' },
    } },
  }
end

local kde_bg = {
  { "Window", "bg1", "bg" }, { "View", "bg", "bg1" }, { "Button", "bg1", "bg2" },
  { "Selection", "sel_bg", "sel_bg" }, { "Tooltip", "bg1", "bg" }, { "Header", "bg1", "bg2" },
  { "Complementary", "bg1", "bg" },
}
local kde_fg = {
  { "ForegroundNormal", "fg" }, { "ForegroundInactive", "muted" }, { "ForegroundActive", "aqua" },
  { "ForegroundLink", "blue" }, { "ForegroundVisited", "purple" }, { "ForegroundNegative", "red" },
  { "ForegroundNeutral", "yellow" }, { "ForegroundPositive", "green" },
  { "DecorationFocus", "focus" }, { "DecorationHover", "green" },
}

local function rgb(col)
  return ("%d,%d,%d"):format(tonumber(col:sub(2, 3), 16), tonumber(col:sub(4, 5), 16), tonumber(col:sub(6, 7), 16))
end

local function kde_settings()
  local groups = { { "Icons", { { "Theme", "breeze-dark", "breeze" } } } }
  for _, bg in ipairs(kde_bg) do
    local function entry(name, key)
      return { name, rgb(palette.dark[key]), rgb(palette.light[key]) }
    end
    local colours = { entry("BackgroundNormal", bg[2]), entry("BackgroundAlternate", bg[3]) }
    for _, fg in ipairs(kde_fg) do
      local key = fg[2]
      if bg[1] == "Selection" and (fg[1] == "ForegroundNormal" or fg[1] == "ForegroundInactive") then
        key = "sel_fg"
      end
      colours[#colours + 1] = entry(fg[1], key)
    end
    groups[#groups + 1] = { "Colors:" .. bg[1], colours }
  end
  return groups
end

local function trim(line)
  return line:match("^%s*(.-)%s*$")
end

local function merge_ini(contents, groups)
  local by_name = {}
  for _, group in ipairs(groups) do
    local keys_by_name = {}
    for _, entry in ipairs(group[2]) do keys_by_name[entry[1]] = entry end
    by_name[group[1]] = { keys = keys_by_name, seen = {} }
  end

  local lines, current = {}, nil
  local matches_dark, matches_light = true, true
  for body, eol in contents:gmatch("([^\n]*)(\n?)") do
    if body == "" and eol == "" then break end
    local raw, ending = body, eol
    if ending == "\n" and raw:sub(-1) == "\r" then
      raw, ending = raw:sub(1, -2), "\r\n"
    end
    local line = trim(raw)
    local header = line:match("^%[(.+)%]$")
    if header then current = by_name[header] end
    if current then
      -- Repeated headers are one logical group; append missing keys to its last section.
      current.last = #lines + 1
      if not header and not line:match("^[#;]") then
        local key, value = line:match("^([^=]+)=(.*)$")
        local entry = key and current.keys[trim(key)]
        if entry then
          value = trim(value)
          matches_dark = matches_dark and value == mode_value(entry, "dark")
          matches_light = matches_light and value == mode_value(entry, "light")
          current.seen[entry[1]] = true
          raw = entry[1] .. "=" .. mode_value(entry, mode)
        end
      end
    end
    lines[#lines + 1] = raw .. ending
  end

  local after, extra = {}, {}
  for _, group in ipairs(groups) do
    local info = by_name[group[1]]
    local missing = {}
    for _, entry in ipairs(group[2]) do
      if not info.seen[entry[1]] then
        matches_dark, matches_light = false, false
        missing[#missing + 1] = entry[1] .. "=" .. mode_value(entry, mode)
      end
    end
    if info.last then
      after[info.last] = missing
    else
      extra[#extra + 1] = "[" .. group[1] .. "]"
      for _, line in ipairs(missing) do extra[#extra + 1] = line end
    end
  end

  local out = {}
  local function append(line)
    -- Only add a separator to an unterminated last line when inserting after it.
    local prev = out[#out]
    if prev and prev:sub(-1) ~= "\n" then out[#out + 1] = "\n" end
    out[#out + 1] = line .. "\n"
  end
  for i, line in ipairs(lines) do
    out[#out + 1] = line
    if after[i] then
      for _, new_line in ipairs(after[i]) do append(new_line) end
    end
  end
  for _, line in ipairs(extra) do append(line) end
  return table.concat(out), not (matches_dark or matches_light)
end

local p = assert(palette[mode], "invalid mode")
local which, state, input, output = arg[3], arg[4], arg[5], arg[6]
if which then
  local groups
  if which == "qt6ct/qt6ct.conf" then
    groups = qt_settings(state)
  else
    assert(which == "kdeglobals", "invalid merged file")
    groups = kde_settings()
  end
  local contents = ""
  if input ~= "" then
    local file = assert(io.open(input, "rb"))
    contents = assert(file:read("*a"))
    assert(file:close())
  end
  local merged, needs_backup = merge_ini(contents, groups)
  local file = assert(io.open(output, "wb"))
  assert(file:write(merged))
  assert(file:close())
  if input ~= "" and needs_backup then
    assert(io.write("backup\n"))
    assert(io.flush())
  end
  return
end
local kitty_lines = render({}, kitty, "%s %s\n", p)
for i, value in ipairs(p.ansi) do
  kitty_lines[#kitty_lines + 1] = ("color%d %s\n"):format(i - 1, value)
end
kitty_lines[#kitty_lines + 1] = "background_opacity 1.0\n"
local gtk4_lines = {}
for _, name in ipairs(modes) do
  gtk4_lines[#gtk4_lines + 1] = ("@media (prefers-color-scheme: %s) {\n  :root {\n"):format(name)
  render(gtk4_lines, gtk4, "    --%s: %s;\n", palette[name])
  gtk4_lines[#gtk4_lines + 1] = "  }\n}\n"
end
local eval = ("hl.config({ general = { col = { active_border = \"rgba(%sff)\", inactive_border = \"rgba(%sff)\" } } })")
  :format(p.focus:sub(2), p.inactive:sub(2))

-- ASCII record separator cannot occur in the templates or validated colours.
assert(io.write(table.concat({
  table.concat(kitty_lines),
  rofi:format(p.fg, p.bg, p.focus, p.sel_bg, p.sel_fg, p.fg, p.fg, p.green, p.fg),
  table.concat(render({}, gtk3, "@define-color %s %s;\n", p)),
  table.concat(gtk4_lines),
  qt_colours(p),
  eval,
}, "\30")))
assert(io.flush())

-- Validate, then render the four files and the live border update for theme.sh.
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

local p = assert(palette[mode], "invalid mode")
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
  eval,
}, "\30")))
assert(io.flush())

local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home:sub(1, 1) ~= "/" then
  local home = os.getenv("HOME")
  state_home = home and home ~= "" and home .. "/.local/state" or nil
end

local mode = "dark"
local file = state_home and io.open(state_home .. "/hypr-theme/mode", "r")
if file then
  local line = file:read("l")
  file:close()
  if line and line:match("^[ \t\r]*light[ \t\r]*$") then mode = "light" end
end

local p = require("theme.palette")[mode]
hl.config({ general = { col = {
  active_border = "rgba(" .. p.focus:sub(2) .. "ff)",
  inactive_border = "rgba(" .. p.inactive:sub(2) .. "ff)",
} } })
hl.layer_rule({ match = { namespace = "^rofi$" }, blur = true })
return true

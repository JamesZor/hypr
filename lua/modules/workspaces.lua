-- Monitors + workspace rules: fallback, active profile, then its saved per-workspace layouts
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

local name = require("lua.state.active_profile")
local profile = require("lua.profiles." .. name)
for _, m in ipairs(profile.monitors or {}) do hl.monitor(m) end
for _, w in ipairs(profile.workspaces or {}) do hl.workspace_rule(w) end

local ok, layouts = pcall(require, "lua.state.layouts." .. name)
if ok and type(layouts) == "table" then
  for _, e in ipairs(layouts) do
    if type(e) == "table" and type(e.rule) == "table" then hl.workspace_rule(e.rule) end
  end
end

-- Hyprland Lua entry point (loads on 0.56.2 and 0.57.2).
-- Core first, then each feature module in isolation. Rollback on 0.56.2: delete this file.
for _, name in ipairs({ "settings", "env", "animations" }) do
  local ok, res = pcall(require, "lua.core." .. name)
  if not ok or res ~= true then
    hl.notification.create({ text = "hypr: core " .. name .. " failed to load", duration = 10000 })
  end
end

for _, name in ipairs({ "keybinds", "windowrules", "workspaces", "autostart" }) do
  local ok, res = pcall(require, "lua.modules." .. name)
  if not ok or res ~= true then
    hl.notification.create({ text = "hypr: module " .. name .. " failed to load", duration = 10000 })
  end
end

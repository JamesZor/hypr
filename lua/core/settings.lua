-- Base settings (windows.conf, layouts.conf, decorations.conf, environments.conf blocks)
hl.config({
  xwayland = { force_zero_scaling = true, use_nearest_neighbor = false },
  cursor = { no_hardware_cursors = 1 },
  input = { kb_layout = "us", follow_mouse = 1, mouse_refocus = false, sensitivity = 0 },
  general = {
    gaps_in = 1,
    gaps_out = 0,
    border_size = 2,
    col = {
      active_border = { colors = { "rgba(8ec07cff)", "rgba(b16286ff)" }, angle = 90 },
      inactive_border = "rgba(595959aa)",
    },
    resize_on_border = true,
    layout = "dwindle",
    allow_tearing = false,
  },
  master = { orientation = "center", slave_count_for_center_master = 0 },
  scrolling = { column_width = 0.333, fullscreen_on_one_column = false, focus_fit_method = 0 },
  misc = { force_default_wallpaper = 0 },
  decoration = { rounding = 4, blur = { enabled = true, size = 3, passes = 1 } },
})

-- Empty per-device block from windows.conf
hl.device({ name = "alpsps/2-alps-dualpoint-stick" })

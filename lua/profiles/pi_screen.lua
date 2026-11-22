-- Port of hyprland/profiles/pi_screen.conf
return {
  monitors = {
    { output = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001", mode = "1024x600@60", position = "-1024x0", scale = 1 },
    { output = "desc:BOE 0x091B", mode = "1920x1080@60", position = "0x0", scale = 1 },
  },
  workspaces = {
    { workspace = "1", monitor = "desc:BOE 0x091B", default = true },
    { workspace = "2", monitor = "desc:BOE 0x091B" },
    { workspace = "3", monitor = "desc:BOE 0x091B" },
    { workspace = "4", monitor = "desc:BOE 0x091B" },
    { workspace = "5", monitor = "desc:BOE 0x091B" },
    { workspace = "6", monitor = "desc:BOE 0x091B" },
    { workspace = "7", monitor = "desc:BOE 0x091B" },
    { workspace = "8", monitor = "desc:BOE 0x091B" },
    { workspace = "9", monitor = "desc:BOE 0x091B" },
    { workspace = "10", monitor = "desc:BOE 0x091B" },
    { workspace = "101", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001", default = true },
    { workspace = "102", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "103", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "104", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "105", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "106", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "107", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "108", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "109", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
    { workspace = "110", monitor = "desc:Mediatrix Peripherals Inc MPI7002 0x00000001" },
  },
}

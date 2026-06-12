# info-wallpaper

Renders live system/network info onto the desktop wallpaper. Refreshes at logon,
on RDP (re)connect, and on demand.

## Shows

Host / user / timestamp · session type · RDP client name + source IP · external
IP · local IPs (per adapter) · Tailscale state / IP / exit-node · running WSL
distros. Each probe is isolated, so a missing tool (no Tailscale, no WSL) just
drops that line rather than breaking the render.

## Install

```powershell
# Registers two scheduled tasks (logon + RDP-connect) and a manual launcher.
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Tasks run hidden, in the interactive session, only while you're logged on.
`Install.ps1` uses `$PSScriptRoot`, so the tasks point at wherever you run it
from — run it here to make this checkout the canonical install location.

## Use

```powershell
# Refresh on demand
pwsh -File .\Update-InfoWallpaper.ps1

# Draw the panel over a real photo instead of the dark gradient
pwsh -File .\Update-InfoWallpaper.ps1 -BaseWallpaper "C:\path\to\photo.jpg" -ResetBase
```

The panel is drawn onto a snapshot of the current wallpaper (`base.png`), or a
dark gradient if none is set. The image is generated at the active session's
resolution and set to **Fill**, so it scales cleanly between the console and
an RDP session at a different resolution.

## Uninstall

```powershell
pwsh -File .\Install.ps1 -Uninstall   # removes both scheduled tasks
```

Then pick any wallpaper via Settings. Generated artifacts (`base.png`,
`wallpaper.bmp`, `Update now.cmd`) are gitignored.

# SWOmphetamine

Prevents tenant-administered RDP sessions from disconnecting due to inactivity.

## Problem

Corporate/tenant-managed RDP sessions enforce an idle timeout that closes the session
even when you're actively using the remote machine — just not through the RDP window
(e.g. running something in a local terminal, reading docs, out of focus for a bit).
The timeout is set via Group Policy and cannot be overridden by the user.

## Solution

A minimal C# tray app that calls the Windows `SetThreadExecutionState` API with
`ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED` — the same mechanism screen-recording
and video-playback apps use to prevent sleep. No Chromium, no Electron, no Node.js.
Runs as a system tray icon; right-click → Exit to release the lock.

## Usage

Run `SWOmphetamine.exe` — no installation, no UAC prompt, no admin rights needed.
A pill icon appears in the system tray. Right-click it and choose **Exit** to quit
and release the wake lock.

To start automatically on login, drop a shortcut in:
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`

## Requirements

.NET Framework 4.x — present on every Windows 7+ machine by default. No install needed.

## Building from source

Requires nothing beyond what's already on Windows:

```powershell
# Generate the icon (requires Node.js)
node src\create-icon.js

# Compile (uses the .NET Framework C# compiler built into Windows)
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /win32icon:icon.ico `
       /r:System.Windows.Forms.dll /r:System.Drawing.dll `
       /out:SWOmphetamine.exe src\SWOmphetamine.cs
```

Output: `SWOmphetamine.exe` (~370 KB)

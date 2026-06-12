# wake

Prevents tenant-administered RDP sessions from disconnecting due to inactivity.

## Problem

Corporate/tenant-managed RDP sessions enforce an idle timeout that closes the session
even when you're actively using the remote machine — just not through the RDP window
(e.g. running something in a local terminal, reading docs, etc.). The timeout is
set via Group Policy and cannot be overridden by the user.

## Solution

A minimal Electron app that holds a [Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)
via Chromium's implementation of the Wake Lock API. The window is never shown
(`show: false`) — the process just runs invisibly in the background, keeping the
session alive.

## Usage

Run `wake.exe` — no installation, no UAC prompt, no admin rights needed.
Kill it via Task Manager when you're done.

Add it to `shell:startup` (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`)
to have it start automatically on login.

## Building from source

Requires Node.js.

```
cd src
npm install
npm run build
```

Output: `src/dist/wake <version>.exe`

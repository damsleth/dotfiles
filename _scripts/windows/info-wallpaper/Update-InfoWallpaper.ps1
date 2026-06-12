<#
.SYNOPSIS
    Renders live system/network info onto the desktop wallpaper.
.DESCRIPTION
    Gathers session (RDP source), network (local/external IP), Tailscale and WSL
    status, draws it as a panel on top of a base image, and sets it as the
    desktop wallpaper for the current interactive session.

    Runs at logon (via the scheduled task created by Install.ps1) and any time
    you run it manually:  pwsh -File Update-InfoWallpaper.ps1
.PARAMETER ConfigDir
    Where the base image and generated wallpaper live.
.PARAMETER BaseWallpaper
    Optional path to an image to draw the panel on top of. If omitted, the
    snapshot in ConfigDir is used, or a generated dark gradient if none exists.
.PARAMETER ResetBase
    Re-snapshot the current wallpaper / regenerate the gradient base.
#>
[CmdletBinding()]
param(
    [string]$ConfigDir     = "$env:USERPROFILE\InfoWallpaper",
    [string]$BaseWallpaper,
    [switch]$ResetBase
)

$ErrorActionPreference = 'Stop'
$ProgressPreference     = 'SilentlyContinue'
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# DPI awareness so WinForms reports real pixels, then load drawing assemblies
# ---------------------------------------------------------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeWin {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int a, int u, string p, int w);
    public static void SetWallpaper(string path) { SystemParametersInfo(20, 0, path, 0x01 | 0x02); }
}
"@
[void][NativeWin]::SetProcessDPIAware()
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ---------------------------------------------------------------------------
# Gather data  (every probe is isolated so a missing tool never breaks render)
# ---------------------------------------------------------------------------
function Try-Get($block, $fallback='n/a') {
    try { $v = & $block; if ($null -eq $v -or "$v" -eq '') { return $fallback } return $v }
    catch { return $fallback }
}

$now      = Get-Date
$hostName = $env:COMPUTERNAME
$user     = "$env:USERDOMAIN\$env:USERNAME"

# --- Session / RDP ---
$inRdp      = $env:SESSIONNAME -like 'RDP*'
$sessionType = if ($inRdp) { 'RDP' } elseif ($env:SESSIONNAME -eq 'Console') { 'Console' } else { "$env:SESSIONNAME" }
$clientName = Try-Get { $env:CLIENTNAME } '-'
$rdpClient  = Try-Get {
    (Get-NetTCPConnection -LocalPort 3389 -State Established -ErrorAction Stop |
        Select-Object -ExpandProperty RemoteAddress -First 1)
} '-'

# --- External IP ---
$extIp = Try-Get {
    (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 4 -ErrorAction Stop)
}

# --- Local IPv4 (skip loopback / APIPA / tailscale CGNAT range) ---
$localIps = Try-Get {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -notlike '100.*' -and
            $_.InterfaceAlias -notlike '*Loopback*'
        } |
        Sort-Object InterfaceIndex |
        ForEach-Object { '{0}  ({1})' -f $_.IPAddress, $_.InterfaceAlias }
} @()

# --- Tailscale ---
$tsState=''; $tsIp=''; $tsExit=''; $tsHas=$false
$tsCmd = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tsCmd -and (Test-Path 'C:\Program Files\Tailscale\tailscale.exe')) {
    $tsCmd = 'C:\Program Files\Tailscale\tailscale.exe'
} elseif ($tsCmd) { $tsCmd = $tsCmd.Source }
if ($tsCmd) {
    $tsHas = $true
    $ts = Try-Get { & $tsCmd status --json 2>$null | ConvertFrom-Json } $null
    if ($ts) {
        $tsState = "$($ts.BackendState)"
        $tsIp    = ($ts.Self.TailscaleIPs | Where-Object { $_ -like '100.*' }) -join ','
        if ($ts.ExitNodeStatus -and $ts.ExitNodeStatus.ID) {
            $exitPeer = $ts.Peer.PSObject.Properties.Value | Where-Object { $_.ExitNode } | Select-Object -First 1
            $tsExit = if ($exitPeer) { $exitPeer.DNSName.TrimEnd('.') } else { 'yes' }
        }
    } else { $tsState = 'unreachable' }
}

# --- WSL running distros ---
$wslLines = @()
$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($wslCmd) {
    $prev = $env:WSL_UTF8; $env:WSL_UTF8 = '1'
    $raw = Try-Get { & wsl.exe -l -v 2>$null } @()
    $env:WSL_UTF8 = $prev
    foreach ($line in $raw) {
        $t = ($line -replace "`0", '').Trim()
        if (-not $t -or $t -match '^\*?\s*NAME\s+STATE') { continue }
        $default = $t.StartsWith('*')
        $cols = ($t.TrimStart('*').Trim()) -split '\s{2,}|\s+'
        if ($cols.Count -ge 2) {
            $wslLines += [pscustomobject]@{ Name=$cols[0]; State=$cols[1]; Default=$default }
        }
    }
}

# ---------------------------------------------------------------------------
# Build the list of lines to render: @{ T = text; K = 'header'|'item'|'sub' }
# ---------------------------------------------------------------------------
$lines = New-Object System.Collections.Generic.List[object]
function Add-Header($t){ $lines.Add(@{ T=$t; K='header' }) }
function Add-Item($k,$v){ $lines.Add(@{ T=('{0,-13}{1}' -f ($k+':'), $v); K='item' }) }

Add-Item 'Host'    $hostName
Add-Item 'User'    $user
Add-Item 'Updated' $now.ToString('yyyy-MM-dd HH:mm')

Add-Header 'SESSION'
Add-Item 'Type' $sessionType
if ($inRdp) {
    Add-Item 'RDP client' $clientName
    Add-Item 'RDP source' $rdpClient
}

Add-Header 'NETWORK'
Add-Item 'External' $extIp
if ($localIps.Count) {
    Add-Item 'Local' $localIps[0]
    foreach ($ip in ($localIps | Select-Object -Skip 1)) { $lines.Add(@{ T=('{0,-13}{1}' -f '',$ip); K='sub' }) }
} else { Add-Item 'Local' 'n/a' }

if ($tsHas) {
    Add-Header 'TAILSCALE'
    Add-Item 'State' $tsState
    if ($tsIp)   { Add-Item 'IP'   $tsIp }
    if ($tsExit) { Add-Item 'Exit node' $tsExit }
}

if ($wslLines.Count) {
    Add-Header 'WSL'
    foreach ($d in $wslLines) {
        $tag = if ($d.Default) { '*' } else { ' ' }
        Add-Item ($tag + ' ' + $d.Name) $d.State
    }
}

# ---------------------------------------------------------------------------
# Base image (snapshot of the *pristine* wallpaper, or generated gradient)
#
# Critical: never use our own generated output as the base. After the first
# run the live wallpaper IS this script's output (panel included); snapshotting
# that would stack a new panel on the previous one every run.
# ---------------------------------------------------------------------------
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$W = [Math]::Max($screen.Width, 1280); $H = [Math]::Max($screen.Height, 720)
$basePath = Join-Path $ConfigDir 'base.png'
$outPath  = Join-Path $ConfigDir 'wallpaper.bmp'

function Resolve-FullPath($p) { try { (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { $null } }

if ($ResetBase -and (Test-Path $basePath)) { Remove-Item $basePath -Force }

if (-not $BaseWallpaper) {
    if (Test-Path $basePath) {
        $BaseWallpaper = $basePath
    } else {
        # First-time capture of a real wallpaper, but only if it isn't our output.
        $cur     = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        $curFull = if ($cur) { Resolve-FullPath $cur } else { $null }
        $outFull = Resolve-FullPath $outPath
        $isOurOutput = $curFull -and $outFull -and ($curFull -ieq $outFull)
        if ($curFull -and -not $isOurOutput) {
            try { Copy-Item -LiteralPath $curFull $basePath -Force; $BaseWallpaper = $basePath } catch {}
        }
        # else: leave unset -> fresh gradient, regenerated each run at current resolution
    }
}

$canvas = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

if ($BaseWallpaper -and (Test-Path $BaseWallpaper)) {
    try {
        $bmp = [System.Drawing.Image]::FromFile($BaseWallpaper)
        $g.DrawImage($bmp, 0, 0, $W, $H)
        $bmp.Dispose()
    } catch { $BaseWallpaper = $null }
}
if (-not $BaseWallpaper -or -not (Test-Path $BaseWallpaper)) {
    $c1 = [System.Drawing.Color]::FromArgb(255, 13, 17, 23)
    $c2 = [System.Drawing.Color]::FromArgb(255, 28, 38, 56)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 60.0)
    $g.FillRectangle($grad, $rect); $grad.Dispose()
}

# ---------------------------------------------------------------------------
# Fonts & measurement
# ---------------------------------------------------------------------------
$fontItem   = New-Object System.Drawing.Font('Consolas', 15, [System.Drawing.FontStyle]::Regular)
$fontHeader = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.FontStyle]::Bold)
$fontTitle  = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$title      = 'SYSTEM INFO'

$pad = 26; $lineGap = 8; $sectionGap = 12
$titleH = [Math]::Ceiling($g.MeasureString($title, $fontTitle).Height)
$contentW = [Math]::Ceiling($g.MeasureString($title, $fontTitle).Width)
$contentH = $titleH + $sectionGap

foreach ($l in $lines) {
    $f = if ($l.K -eq 'header') { $fontHeader } else { $fontItem }
    $sz = $g.MeasureString($l.T, $f)
    $contentW = [Math]::Max($contentW, [Math]::Ceiling($sz.Width))
    $h = [Math]::Ceiling($sz.Height)
    if ($l.K -eq 'header') { $contentH += $sectionGap + $h + 2 } else { $contentH += $h + $lineGap }
}

$panelW = $contentW + 2*$pad
$panelH = $contentH + 2*$pad
$margin = 48
$px = $margin; $py = $margin   # top-left

# ---------------------------------------------------------------------------
# Panel background (semi-transparent rounded rectangle)
# ---------------------------------------------------------------------------
function New-RoundedPath($x,$y,$w,$h,$r){
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r*2
    $p.AddArc($x,           $y,           $d,$d, 180, 90)
    $p.AddArc($x+$w-$d,     $y,           $d,$d, 270, 90)
    $p.AddArc($x+$w-$d,     $y+$h-$d,     $d,$d,   0, 90)
    $p.AddArc($x,           $y+$h-$d,     $d,$d,  90, 90)
    $p.CloseFigure(); return $p
}
$panelPath = New-RoundedPath $px $py $panelW $panelH 18
$panelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 10, 12, 18))
$borderPen  = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 90, 160, 255)), 1.5
$g.FillPath($panelBrush, $panelPath)
$g.DrawPath($borderPen, $panelPath)

# ---------------------------------------------------------------------------
# Draw text
# ---------------------------------------------------------------------------
$cWhite  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,255,255,255))
$cAccent = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,120,180,255))
$cDim    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180,200,210,225))

$tx = $px + $pad; $ty = $py + $pad
$g.DrawString($title, $fontTitle, $cAccent, $tx, $ty)
$ty += $titleH + $sectionGap

foreach ($l in $lines) {
    if ($l.K -eq 'header') {
        $ty += $sectionGap
        $g.DrawString($l.T, $fontHeader, $cAccent, $tx, $ty)
        $ty += [Math]::Ceiling($g.MeasureString($l.T, $fontHeader).Height) + 2
    } else {
        $brush = if ($l.K -eq 'sub') { $cDim } else { $cWhite }
        $g.DrawString($l.T, $fontItem, $brush, $tx, $ty)
        $ty += [Math]::Ceiling($g.MeasureString($l.T, $fontItem).Height) + $lineGap
    }
}

# ---------------------------------------------------------------------------
# Save + apply
# ---------------------------------------------------------------------------
$g.Dispose()
$canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
$canvas.Dispose()

# Fill style so it scales to whatever screen/session resolution is active
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value '0'
[NativeWin]::SetWallpaper($outPath)

Write-Host "Wallpaper updated: $outPath" -ForegroundColor Green

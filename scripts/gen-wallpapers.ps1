# Generates Banchy OS wallpapers (one per theme) using System.Drawing.
# Run: powershell -ExecutionPolicy Bypass -File scripts\gen-wallpapers.ps1
param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\wallpapers"),
    [int]$Width = 1920,
    [int]$Height = 1080
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$themes = @(
    @{ name = "midnight"; top = "#0B0F14"; bottom = "#1A2436"; accent = "#6C8CFF" },
    @{ name = "black";    top = "#0A0A0A"; bottom = "#1F1F1F"; accent = "#E2E8F0" },
    @{ name = "frost";    top = "#10161E"; bottom = "#26344A"; accent = "#88C0D0" },
    @{ name = "neon";     top = "#060A08"; bottom = "#0F2419"; accent = "#3DFF9E" },
    @{ name = "minimal";  top = "#0D0D0D"; bottom = "#1A1A1A"; accent = "#A3A3A3" }
)

function Convert-Hex([string]$h) {
    $h = $h.TrimStart("#")
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
    return @($r, $g, $b)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($t in $themes) {
    $top = Convert-Hex $t.top
    $bottom = Convert-Hex $t.bottom
    $accent = Convert-Hex $t.accent

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"

    # Vertical gradient, row by row (fast enough: 1080 fill calls).
    for ($y = 0; $y -lt $Height; $y++) {
        $f = $y / [double]($Height - 1)
        $r = [int]($top[0] + ($bottom[0] - $top[0]) * $f)
        $gg = [int]($top[1] + ($bottom[1] - $top[1]) * $f)
        $b = [int]($top[2] + ($bottom[2] - $top[2]) * $f)
        $color = [System.Drawing.Color]::FromArgb(255, $r, $gg, $b)
        $brush = New-Object System.Drawing.SolidBrush($color)
        $g.FillRectangle($brush, 0, $y, $Width, 1)
        $brush.Dispose()
    }

    # Soft accent glow in the lower-right corner.
    $glowColor = [System.Drawing.Color]::FromArgb(46, $accent[0], $accent[1], $accent[2])
    $glow = New-Object System.Drawing.SolidBrush($glowColor)
    $d = [int]($Height * 0.9)
    $g.FillEllipse($glow, $Width - [int]($d * 0.75), $Height - [int]($d * 0.55), $d, $d)
    $glow.Dispose()

    # Second, weaker glow in the upper-left for balance.
    $d2 = [int]($Height * 0.55)
    $g2c = [System.Drawing.Color]::FromArgb(22, $accent[0], $accent[1], $accent[2])
    $g2 = New-Object System.Drawing.SolidBrush($g2c)
    $g.FillEllipse($g2, [int](-$d2 * 0.35), [int](-$d2 * 0.4), $d2, $d2)
    $g2.Dispose()

    $g.Dispose()

    $out = Join-Path $OutDir "$($t.name).png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $out"
}
Write-Host "done"

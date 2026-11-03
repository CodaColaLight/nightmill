# tools/make-icon.ps1 - renders .claude-plugin/icon.png (1024 px, square): a white crescent moon
# and a white windmill on dark purple. Edit the numbers here and re-run; the PNG is derived output.
#   powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1 [-Size 1024] [-Out .claude-plugin\icon.png]
param(
  [int]$Size = 1024,
  [string]$Out = (Join-Path (Split-Path $PSScriptRoot -Parent) ".claude-plugin\icon.png")
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$s = $Size / 1024.0   # everything below is designed on a 1024 grid
function P($x, $y) { New-Object System.Drawing.PointF (($x * $s), ($y * $s)) }

$bmp = New-Object System.Drawing.Bitmap $Size, $Size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$purple = [System.Drawing.Color]::FromArgb(255, 42, 27, 61)    # #2A1B3D
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$bg = New-Object System.Drawing.SolidBrush $purple

# Background with rounded corners.
$g.Clear([System.Drawing.Color]::Transparent)
$r = 180 * $s
$card = New-Object System.Drawing.Drawing2D.GraphicsPath
$card.AddArc(0, 0, $r, $r, 180, 90)
$card.AddArc($Size - $r, 0, $r, $r, 270, 90)
$card.AddArc($Size - $r, $Size - $r, $r, $r, 0, 90)
$card.AddArc(0, $Size - $r, $r, $r, 90, 90)
$card.CloseFigure()
$g.FillPath($bg, $card)

# Crescent moon, upper right: a white disc minus an offset purple disc of nearly the same size.
$mx = 770; $my = 235; $mr = 140
$g.FillEllipse($white, ($mx - $mr) * $s, ($my - $mr) * $s, 2 * $mr * $s, 2 * $mr * $s)
$cx = $mx - 62; $cy = $my - 48; $cr = 130
$g.FillEllipse($bg, ($cx - $cr) * $s, ($cy - $cr) * $s, 2 * $cr * $s, 2 * $cr * $s)

# Windmill. The white parts overlap each other a little instead of sharing edges, so the
# anti-aliased fills leave no hairline seams. (One winding path would punch holes where
# sub-paths of opposite orientation overlap.)
$hubX = 370; $hubY = 470
# tower: tapered, below the hub
$g.FillPolygon($white, [System.Drawing.PointF[]]@((P ($hubX - 62) ($hubY + 20)), (P ($hubX + 62) ($hubY + 20)), (P ($hubX + 112) 900), (P ($hubX - 112) 900)))
# cap: a dome around the hub
$g.FillPie($white, ($hubX - 82) * $s, ($hubY - 40) * $s, 164 * $s, 150 * $s, 180, 180)
# sails: an X of four arms, each with a blade on its trailing side
$armLen = 275
foreach ($angle in 45, 135, 225, 315) {
  $m = New-Object System.Drawing.Drawing2D.Matrix
  $m.Translate($hubX * $s, $hubY * $s)
  $m.Rotate($angle)
  $arm = New-Object System.Drawing.Drawing2D.GraphicsPath
  $arm.AddPolygon([System.Drawing.PointF[]]@((P -10 0), (P 10 0), (P 10 (-$armLen)), (P -10 (-$armLen))))
  $arm.Transform($m)
  $g.FillPath($white, $arm)
  $blade = New-Object System.Drawing.Drawing2D.GraphicsPath
  $blade.AddPolygon([System.Drawing.PointF[]]@((P -2 -105), (P 72 -135), (P 64 (-$armLen + 4)), (P -2 (-$armLen + 4))))
  $blade.Transform($m)
  $g.FillPath($white, $blade)
}
# hub
$hr = 36
$g.FillEllipse($white, ($hubX - $hr) * $s, ($hubY - $hr) * $s, 2 * $hr * $s, 2 * $hr * $s)

# purple details on top: hub centre and door
$g.FillEllipse($bg, ($hubX - 13) * $s, ($hubY - 13) * $s, 26 * $s, 26 * $s)
$dw = 54; $dh = 105
$g.FillRectangle($bg, ($hubX - $dw / 2) * $s, (900 - $dh) * $s, $dw * $s, $dh * $s)
$g.FillEllipse($bg, ($hubX - $dw / 2) * $s, (900 - $dh - $dw / 2) * $s, $dw * $s, $dw * $s)

New-Item -ItemType Directory -Force (Split-Path $Out -Parent) | Out-Null
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "wrote $Out ($Size x $Size)"

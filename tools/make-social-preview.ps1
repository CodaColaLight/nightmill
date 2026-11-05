# tools/make-social-preview.ps1 - renders docs/social-preview.png (1280 x 640): the plugin icon on dark purple
# with "Nightmill" set in Creepster and one line under it. The PNG is derived output; GitHub takes it only
# through the web UI (Settings > General > Social preview), there is no API for it.
#   powershell -ExecutionPolicy Bypass -File tools\make-social-preview.ps1 [-Out docs\social-preview.png]
# Needs .claude-plugin\icon.png (run tools\make-icon.ps1 first if it changed) and tools\fonts\Creepster-Regular.ttf
# (SIL Open Font License 1.1, licence next to it).
param(
  [string]$Out = (Join-Path (Split-Path $PSScriptRoot -Parent) "docs\social-preview.png"),
  [string]$Tagline = "A lights-out development workflow for Claude Code"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$iconFile = Join-Path $root ".claude-plugin\icon.png"
$fontFile = Join-Path $PSScriptRoot "fonts\Creepster-Regular.ttf"
foreach ($f in $iconFile, $fontFile) { if (-not (Test-Path $f)) { throw "missing $f" } }

$W = 1280; $H = 640
$purple = [System.Drawing.Color]::FromArgb(255, 42, 27, 61)     # #2A1B3D, the icon's purple
$lavender = [System.Drawing.Color]::FromArgb(255, 185, 168, 214) # #B9A8D6

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear($purple)

# Icon on the left. Its corners are transparent and its purple is the card's purple, so it has no visible edge.
$icon = [System.Drawing.Image]::FromFile($iconFile)
$iconSize = 600
$g.DrawImage($icon, 20, ($H - $iconSize) / 2, $iconSize, $iconSize)
$icon.Dispose()

# Wordmark: the largest Creepster size that fits the right-hand column, left aligned, with the tagline under it.
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontFile)
$family = $fonts.Families[0]
$colX = 610; $colW = $W - $colX - 60
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$size = 220.0
do {
  $title = New-Object System.Drawing.Font $family, $size, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $tw = $g.MeasureString("Nightmill", $title, 4000, $fmt).Width
  if ($tw -gt $colW) { $size -= 4; $title.Dispose() }
} while ($tw -gt $colW)
$th = $g.MeasureString("Nightmill", $title, 4000, $fmt).Height

# The tagline shrinks from 28 px until it fits the column (a longer -Tagline stays inside the card).
$tagSize = 28.0
do {
  $tag = New-Object System.Drawing.Font "Segoe UI", $tagSize, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
  $tagW = $g.MeasureString($Tagline, $tag, 4000, $fmt).Width
  if ($tagW -gt ($colW - 6)) { $tagSize -= 1; $tag.Dispose() }
} while ($tagW -gt ($colW - 6))
$tagH = $g.MeasureString($Tagline, $tag, 4000, $fmt).Height
$gap = 24
$blockH = $th + $gap + $tagH
$y = ($H - $blockH) / 2
$g.DrawString("Nightmill", $title, [System.Drawing.Brushes]::White, $colX, $y, $fmt)
$g.DrawString($Tagline, $tag, (New-Object System.Drawing.SolidBrush $lavender), ($colX + 6), ($y + $th + $gap), $fmt)

New-Item -ItemType Directory -Force (Split-Path $Out -Parent) | Out-Null
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host ("wrote {0} ({1} x {2}, wordmark {3}px)" -f $Out, $W, $H, $size)

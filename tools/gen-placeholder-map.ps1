<#
  gen-placeholder-map.ps1 — stand-in room-map (a-slot) until a real map is drawn.
  Matches the real maps' 615x1500 portrait so layout is identical after you
  swap in the hand-drawn version at the same filename.

  Usage: ./gen-placeholder-map.ps1 -Locus 5 -Room 1 -Out ..\img\5a.png
#>
param(
  [Parameter(Mandatory=$true)][int]$Locus,
  [Parameter(Mandatory=$true)][int]$Room,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$W = 615,
  [int]$H = 1500
)
Add-Type -AssemblyName System.Drawing

$black = [System.Drawing.Color]::Black
$blue  = [System.Drawing.Color]::FromArgb(0,0,255)
$gray  = [System.Drawing.Color]::FromArgb(150,150,150)

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.Clear([System.Drawing.Color]::White)

# outer frame, like the real hand-drawn maps
$pen = New-Object System.Drawing.Pen($black, 14)
$g.DrawRectangle($pen, 10, 10, $W-20, $H-20)
$pen.Dispose()

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center

$fRoom = New-Object System.Drawing.Font('Segoe UI', 64, [System.Drawing.FontStyle]::Bold,  [System.Drawing.GraphicsUnit]::Pixel)
$fNum  = New-Object System.Drawing.Font('Segoe UI', 260,[System.Drawing.FontStyle]::Bold,  [System.Drawing.GraphicsUnit]::Pixel)
$fTodo = New-Object System.Drawing.Font('Segoe UI', 40, [System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)

$bBlue = New-Object System.Drawing.SolidBrush $blue
$bGray = New-Object System.Drawing.SolidBrush $gray

$g.DrawString("ROOM $Room", $fRoom, $bBlue, (New-Object System.Drawing.RectangleF(0, 120, $W, 90)), $sf)
$g.DrawString("$Locus",     $fNum,  $bBlue, (New-Object System.Drawing.RectangleF(0, ($H/2-200), $W, 400)), $sf)
$g.DrawString("map placeholder`n(drop real map here)", $fTodo, $bGray, (New-Object System.Drawing.RectangleF(0, ($H-260), $W, 180)), $sf)

$bBlue.Dispose(); $bGray.Dispose(); $fRoom.Dispose(); $fNum.Dispose(); $fTodo.Dispose(); $sf.Dispose(); $g.Dispose()

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "wrote $Out (ROOM $Room / locus $Locus)"

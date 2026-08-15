<#
  gen-data-image.ps1 — render a memory-palace "data image" (the b-slot) from text.

  Replaces the tedious manual screenshotting of step text. Understands a little
  markdown: a leading "N." list number is tinted, **bold** is white+bold,
  `code` is monospace on a subtle chip, *italic* is italic.

  Usage:
    ./gen-data-image.ps1 -Text '1. **Org wide interaction code on** FIRST' -Out ..\img\1b.png
    ./gen-data-image.ps1 -Text '`Widget Lab` (audience `api://widget-lab`)' -Out ..\img\7b.png
#>
param(
  [Parameter(Mandatory=$true)][string]$Text,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$FontSize = 30,
  [int]$MaxWidth = 1100,     # wrap past this pixel width
  [int]$PadX = 28,
  [int]$PadY = 20
)

Add-Type -AssemblyName System.Drawing

# --- VS Code Dark+ palette ---
$bg      = [System.Drawing.Color]::FromArgb(30,30,30)     # #1e1e1e
$fg      = [System.Drawing.Color]::FromArgb(212,212,212)  # #d4d4d4 normal
$white   = [System.Drawing.Color]::FromArgb(255,255,255)  # bold
$num     = [System.Drawing.Color]::FromArgb(206,145,120)  # #ce9178 list number
$codeCol = [System.Drawing.Color]::FromArgb(206,145,120)  # inline code text
$codeBg  = [System.Drawing.Color]::FromArgb(45,45,45)      # inline code chip

$fam     = 'Segoe UI'
$mono    = 'Consolas'

# Tokenize into styled runs: bold / italic / code / number / normal
function Get-Runs([string]$s) {
  $runs = @()
  # pull a leading "N." or "N " list marker off the front
  if ($s -match '^\s*(\d+[\.\)])\s+(.*)$') {
    $runs += [pscustomobject]@{ text = ($Matches[1] + ' '); style = 'num' }
    $s = $Matches[2]
  }
  # split on **bold**, `code`, *italic*
  $rx = '(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)'
  foreach ($part in [regex]::Split($s, $rx)) {
    if ($part -eq '') { continue }
    if ($part.StartsWith('**')) {
      $runs += [pscustomobject]@{ text = $part.Trim('*'); style = 'bold' }
    } elseif ($part.StartsWith('`')) {
      $runs += [pscustomobject]@{ text = $part.Trim('`'); style = 'code' }
    } elseif ($part.StartsWith('*')) {
      $runs += [pscustomobject]@{ text = $part.Trim('*'); style = 'italic' }
    } else {
      $runs += [pscustomobject]@{ text = $part; style = 'normal' }
    }
  }
  return $runs
}

function Get-Font([string]$style) {
  switch ($style) {
    'bold'   { New-Object System.Drawing.Font($fam,  $FontSize, [System.Drawing.FontStyle]::Bold,   [System.Drawing.GraphicsUnit]::Pixel) }
    'italic' { New-Object System.Drawing.Font($fam,  $FontSize, [System.Drawing.FontStyle]::Italic, [System.Drawing.GraphicsUnit]::Pixel) }
    'code'   { New-Object System.Drawing.Font($mono, $FontSize, [System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel) }
    'num'    { New-Object System.Drawing.Font($fam,  $FontSize, [System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel) }
    default  { New-Object System.Drawing.Font($fam,  $FontSize, [System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel) }
  }
}
function Get-Color([string]$style) {
  switch ($style) {
    'bold'   { $white }
    'code'   { $codeCol }
    'num'    { $num }
    default  { $fg }
  }
}

$runs = Get-Runs $Text

# Break runs into words so we can wrap; keep style on each word.
$words = @()
foreach ($r in $runs) {
  $pieces = $r.text -split '(?<=\s)'   # keep trailing spaces
  foreach ($p in $pieces) {
    if ($p -ne '') { $words += [pscustomobject]@{ text = $p; style = $r.style } }
  }
}

# Measure with a scratch bitmap
$scratch = New-Object System.Drawing.Bitmap 1,1
$g = [System.Drawing.Graphics]::FromImage($scratch)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$fmt = [System.Drawing.StringFormat]::GenericTypographic
$fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces

$lineH = [math]::Ceiling($FontSize * 1.45)
$spaceMax = $MaxWidth - (2 * $PadX)

# Lay out words into positioned glyphs
$lines = New-Object System.Collections.ArrayList
$cur = New-Object System.Collections.ArrayList
$curW = 0.0
foreach ($w in $words) {
  $f = Get-Font $w.style
  $sz = $g.MeasureString($w.text, $f, [int]$MaxWidth, $fmt)
  $ww = $sz.Width
  if (($curW + $ww) -gt $spaceMax -and $cur.Count -gt 0) {
    [void]$lines.Add(@($cur.ToArray())); $cur = New-Object System.Collections.ArrayList; $curW = 0.0
  }
  [void]$cur.Add([pscustomobject]@{ text=$w.text; style=$w.style; w=$ww })
  $curW += $ww
  $f.Dispose()
}
if ($cur.Count -gt 0) { [void]$lines.Add(@($cur.ToArray())) }

# Canvas size
$maxLineW = 0.0
foreach ($ln in $lines) { $lw = ($ln | Measure-Object -Property w -Sum).Sum; if ($lw -gt $maxLineW){$maxLineW=$lw} }
$W = [int]([math]::Ceiling($maxLineW) + 2*$PadX)
$H = [int]($lines.Count * $lineH + 2*$PadY)
$g.Dispose(); $scratch.Dispose()

# Render
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.Clear($bg)
$y = [single]$PadY
foreach ($ln in $lines) {
  $x = [single]$PadX
  foreach ($tok in $ln) {
    $f = Get-Font $tok.style
    if ($tok.style -eq 'code') {
      $chip = New-Object System.Drawing.SolidBrush $codeBg
      $g.FillRectangle($chip, $x, $y+2, [single]$tok.w, [single]($lineH-4))
      $chip.Dispose()
    }
    $br = New-Object System.Drawing.SolidBrush (Get-Color $tok.style)
    $g.DrawString($tok.text, $f, $br, $x, $y, $fmt)
    $br.Dispose(); $f.Dispose()
    $x += [single]$tok.w
  }
  $y += [single]$lineH
}
$g.Dispose()

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "wrote $Out  ($W x $H)"

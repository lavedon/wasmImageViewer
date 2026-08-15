<#
  gen-all-b.ps1 — batch-generate every data-image (b-slot) from steps.txt.
  Reads tools/steps.txt ("N|text" per line) and writes img/Nb.png for each,
  using gen-data-image.ps1. Run from anywhere; paths are resolved off this file.
#>
param([string]$OutDir)

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$gen     = Join-Path $here 'gen-data-image.ps1'
$steps   = Join-Path $here 'steps.txt'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $here) 'img' }

$lines = Get-Content -LiteralPath $steps -Encoding UTF8
foreach ($line in $lines) {
  if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { continue }
  $i = $line.IndexOf('|')
  if ($i -lt 1) { continue }
  $n    = $line.Substring(0, $i).Trim()
  $text = $line.Substring($i + 1)
  $out  = Join-Path $OutDir ("{0}b.png" -f $n)
  & $gen -Text ("{0}. {1}" -f $n, $text) -Out $out
}

<#
.SYNOPSIS
  Read a `uitest dumpLayout` artifact and print page path + every node that has text or an id.

.DESCRIPTION
  Why this exists: matching text against the raw layout JSON with a regex window
  ("bounds":"..."[\s\S]{0,1400}?"text":"target") spans across nodes and silently pairs
  the wrong bounds with the wrong text. This parses the JSON tree instead, so every
  printed row really belongs to one node.

  Usage:
    $hdc shell uitest dumpLayout -p /data/local/tmp/layout.json
    $hdc file recv /data/local/tmp/layout.json TemporaryCacheStorage/agent-ui-layout.json
    powershell -ExecutionPolicy Bypass -File scripts/ui-dump.ps1
    powershell -ExecutionPolicy Bypass -File scripts/ui-dump.ps1 -Match 'jiehsuan'

  ASCII-only on purpose: no BOM/ANSI decoding traps in Windows PowerShell 5.1.
#>
param(
  # Layout JSON produced by `uitest dumpLayout` (pulled from the device).
  [string]$Path = 'TemporaryCacheStorage/agent-ui-layout.json',
  # Optional case-insensitive substring filter applied to text and id.
  [string]$Match = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path)) { Write-Host "[FAIL] not found: $Path" -ForegroundColor Red; exit 1 }
$full = (Resolve-Path $Path).Path
$json = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$rows = New-Object System.Collections.ArrayList
$pages = New-Object System.Collections.ArrayList

function Walk($node) {
  $a = $node.attributes
  if ($a -ne $null) {
    $page = [string]$a.pagePath
    if ($page -ne '' -and -not $pages.Contains($page)) { [void]$pages.Add($page) }
    $text = [string]$a.text
    $id = [string]$a.id
    if ($text -ne '' -or $id -ne '') {
      [void]$rows.Add([pscustomobject]@{
        text      = $text
        id        = $id
        type      = [string]$a.type
        bounds    = [string]$a.bounds
        clickable = [string]$a.clickable
      })
    }
  }
  if ($node.children -ne $null) { foreach ($c in $node.children) { Walk $c } }
}

Walk $json

Write-Host ("[page] {0}" -f ($pages -join ' , ')) -ForegroundColor Cyan

$shown = $rows
if ($Match -ne '') {
  $shown = $rows | Where-Object { $_.text -like "*$Match*" -or $_.id -like "*$Match*" }
}

$i = 0
foreach ($r in $shown) {
  $i = $i + 1
  Write-Host ("{0,3}. {1,-14} {2,-22} {3}" -f $i, $r.bounds, ($(if ($r.id -ne '') { '#' + $r.id } else { $r.type })), $r.text)
}
Write-Host ("[nodes with text/id] {0} shown / {1} total" -f $i, $rows.Count) -ForegroundColor Cyan

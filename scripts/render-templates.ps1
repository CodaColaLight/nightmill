# scripts/render-templates.ps1 - write the project's GitHub issue forms from the nightmill templates.
#   render-templates.ps1              # from the project root; writes .github/ISSUE_TEMPLATE/*.yml
#   render-templates.ps1 -Force       # also overwrite forms that differ from the rendered text
# Reads areas, invariants, labels and verification from .claude/nightmill.json and fills the
# {{...}} placeholders in templates/ISSUE_TEMPLATE/*.yml. Without -Force an existing form that
# differs is left alone and listed, so a project can keep hand edits on purpose.
param(
  [string]$Project = (Get-Location).Path,
  [switch]$Force
)
$ErrorActionPreference = "Stop"

$cfgPath = Join-Path $Project ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { throw "no $cfgPath (run /nightmill:init)" }
# -Encoding UTF8 everywhere: Windows PowerShell 5.1 otherwise reads files in the ANSI code page.
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Yaml-Quote($s) { '"' + (([string]$s) -replace '\\', '\\' -replace '"', '\"') + '"' }
# Areas, labels and invariants are all double-quoted YAML scalars, so `,` `:` `#` and `"` keep the forms valid.
function Label($key, $default) { Yaml-Quote $(if ($cfg.labels -and $cfg.labels.$key) { $cfg.labels.$key } else { $default }) }

if (-not $cfg.areas -or @($cfg.areas).Count -eq 0) { throw "nightmill.json needs at least one entry in areas" }
$areas = "[" + ((@($cfg.areas) | ForEach-Object { Yaml-Quote $_ }) -join ", ") + "]"

# @($null) would be a one-element array; filter so a missing key means "no invariants".
$invariants = @($cfg.invariants | Where-Object { $null -ne $_ -and "$_" -ne "" })
$invBlock = ""
foreach ($i in $invariants) {
  $invBlock += "        - label: " + (Yaml-Quote $i) + "`n          required: false`n"
}
$invBlock = $invBlock.TrimEnd("`n")

$check = ""
$manual = ""
if ($cfg.verification) {
  if ($cfg.verification.check) { $check = [string]$cfg.verification.check }
  if ($cfg.verification.manualCheckText) { $manual = [string]$cfg.verification.manualCheckText }
}
if (-not $manual) { $manual = "Manual check as the story describes" }

$src = Join-Path $PSScriptRoot "..\templates\ISSUE_TEMPLATE"
$dst = Join-Path $Project ".github\ISSUE_TEMPLATE"
New-Item -ItemType Directory -Force $dst | Out-Null

$kept = @()
foreach ($f in Get-ChildItem $src -Filter *.yml) {
  $text = (Get-Content $f.FullName -Raw -Encoding UTF8) -replace "`r`n", "`n"
  if ($invariants.Count -eq 0) {
    $text = [regex]::Replace($text, "(?s)\n  # \{\{INVARIANTS_BEGIN\}\}\n.*?# \{\{INVARIANTS_END\}\}\n", "`n")
  } else {
    $text = $text.Replace("  # {{INVARIANTS_BEGIN}}`n", "").Replace("  # {{INVARIANTS_END}}`n", "")
  }
  $text = $text.Replace("{{AREAS}}", $areas).Replace("{{INVARIANTS}}", $invBlock)
  $text = $text.Replace("{{CHECK_COMMAND}}", $check).Replace("{{MANUAL_CHECK}}", $manual)
  $text = $text.Replace("{{LABEL_EPIC}}", (Label "epic" "epic")).Replace("{{LABEL_STORY}}", (Label "story" "story"))
  $text = $text.Replace("{{LABEL_BUG}}", (Label "bug" "bug")).Replace("{{LABEL_NEEDS_SPEC}}", (Label "needsSpec" "needs-spec"))

  $out = Join-Path $dst $f.Name
  if ((Test-Path $out) -and -not $Force) {
    $have = (Get-Content $out -Raw -Encoding UTF8) -replace "`r`n", "`n"
    if ($have -ne $text) { $kept += $f.Name; continue }
  }
  [System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding $false))
  Write-Host "wrote $out"
}
if ($kept.Count -gt 0) {
  Write-Host ("kept (differ from the rendered text; use -Force to overwrite): " + ($kept -join ", ")) -ForegroundColor Yellow
}

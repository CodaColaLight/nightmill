# tests/smoke-render.ps1 - render-templates.ps1 against a throwaway project: placeholders filled,
# invariants quoted, non-ASCII text intact, the no-invariants case drops the checkbox block,
# existing forms kept without -Force.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$R = Join-Path $here "scripts\render-templates.ps1"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-render-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory "$tmp\.claude" | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Render { param([Parameter(ValueFromRemainingArguments = $true)]$a)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $R -Project $tmp @a | Out-String
}

try {
  $cfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["core", "ui"],
  "invariants": ["Fog of war — nothing unseen is sent", "Quote \"this\" and `that`"],
  "labels": { "story": "feature" },
  "verification": { "check": "make check", "manualCheckText": "Open the app and click around" }
}
'@
  [System.IO.File]::WriteAllText("$tmp\.claude\nightmill.json", $cfg, $utf8)

  Write-Host "== render"
  $null = Render
  $story = [System.IO.File]::ReadAllText("$tmp\.github\ISSUE_TEMPLATE\story.yml", $utf8)
  if ($story -notmatch 'options: \[core, ui\]') { Fail "areas not filled" }
  if ($story -notmatch 'labels: \["feature", "needs-spec"\]') { Fail "labels not filled: $story" }
  if ($story -notmatch '- label: "Fog of war — nothing unseen is sent"') { Fail "non-ASCII invariant damaged or unquoted" }
  if ($story -notmatch '- label: "Quote \\"this\\" and `that`"') { Fail "quotes not escaped" }
  if ($story -match '\{\{') { Fail "placeholder left: $story" }
  if ($story -match 'INVARIANTS_BEGIN') { Fail "marker left" }
  if ($story -notmatch '`make check` green') { Fail "check command not filled" }
  if ($story -notmatch 'Open the app and click around') { Fail "manual check not filled" }
  $bug = [System.IO.File]::ReadAllText("$tmp\.github\ISSUE_TEMPLATE\bug.yml", $utf8)
  if ($bug -notmatch 'Invariants the fix must respect') { Fail "bug form lost its invariants" }
  if (-not (Test-Path "$tmp\.github\ISSUE_TEMPLATE\config.yml")) { Fail "config.yml missing" }

  Write-Host "== kept without -Force"
  [System.IO.File]::WriteAllText("$tmp\.github\ISSUE_TEMPLATE\epic.yml", "hand edited`n", $utf8)
  $out = Render
  if ($out -notmatch 'kept .*epic\.yml') { Fail "hand-edited form was not reported as kept: $out" }
  if ((Get-Content "$tmp\.github\ISSUE_TEMPLATE\epic.yml" -Raw) -notmatch 'hand edited') { Fail "hand-edited form overwritten" }
  $null = Render -Force
  if ((Get-Content "$tmp\.github\ISSUE_TEMPLATE\epic.yml" -Raw) -match 'hand edited') { Fail "-Force did not overwrite" }

  Write-Host "== no invariants drops the block"
  $cfg2 = $cfg.Replace('"invariants": ["Fog of war — nothing unseen is sent", "Quote \"this\" and `that`"],', '')
  [System.IO.File]::WriteAllText("$tmp\.claude\nightmill.json", $cfg2, $utf8)
  $null = Render -Force
  $story = [System.IO.File]::ReadAllText("$tmp\.github\ISSUE_TEMPLATE\story.yml", $utf8)
  if ($story -match 'invariants') { Fail "checkbox block not dropped: $story" }
  if ($story -match '\{\{') { Fail "placeholder left after drop" }

  Write-Host "RENDER OK" -ForegroundColor Green
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

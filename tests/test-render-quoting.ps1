# tests/test-render-quoting.ps1 - regression for bug #135: render-templates.ps1 must quote and escape
# areas and labels in the issue forms like it does invariants, for `,` `:` `#` and `"`.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$R = Join-Path $here "scripts\render-templates.ps1"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-quoting-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory "$tmp\.claude" | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Lines($f) { [System.IO.File]::ReadAllText("$tmp\.github\ISSUE_TEMPLATE\$f", $utf8) -split "`r?`n" }
try {
  $cfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "areas": ["ui, web", "api: v2", "#tag", "say \"hi\""],
  "invariants": ["Keep it simple"],
  "labels": { "story": "feat: \"new\"", "bug": "bug #1, urgent", "epic": "big \"epic\"", "needsSpec": "needs \"spec\"" },
  "verification": { "check": "make check" }
}
'@
  [System.IO.File]::WriteAllText("$tmp\.claude\nightmill.json", $cfg, $utf8)
  $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $R -Project $tmp | Out-String
  $want = 'options: ["ui, web", "api: v2", "#tag", "say \"hi\""]'
  foreach ($f in "story.yml", "bug.yml") {
    if (-not ((Lines $f) | Where-Object { $_.Contains($want) })) { Fail "$f areas not quoted and escaped" }
  }
  if ((Lines "story.yml") -cnotcontains 'labels: ["feat: \"new\"", "needs \"spec\""]') { Fail "story labels not escaped" }
  if ((Lines "bug.yml") -cnotcontains 'labels: ["bug #1, urgent"]') { Fail "bug label not quoted" }
  if ((Lines "epic.yml") -cnotcontains 'labels: ["big \"epic\""]') { Fail "epic label not escaped" }
  Write-Host "RENDER QUOTING OK"
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

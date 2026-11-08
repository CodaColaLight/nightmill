# tests/test-lintcopy-output.ps1 - regression test for #217 (PowerShell half; the bash half is test-lintcopy-output.sh):
# when the lint fails on the copy of the repository that smoke-release.ps1 makes, it must print the lint's FAIL: lines,
# not only its own failure line.
# Method: copy the repository without .git, add a JSON file that does not parse (the lint then fails on any copy of
# that tree, the smoke script's other steps do not read it), run the copy's smoke-release.ps1 and read its output.
# Not a smoke script: run it with `powershell -ExecutionPolicy Bypass -File tests/test-lintcopy-output.ps1`.
# Needs git and bash (like the lint case of smoke-release.ps1); without bash it reports the skip and passes.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-lcout-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
foreach ($v in "UPDATE_STATUS_FIXTURES", "UPDATE_DASHBOARD_FIXTURES", "UPDATE_PANEL_FIXTURES", "NIGHTMILL_CHECK_STEPS") {
  Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
try {
  $copy = Join-Path $tmp "repocopy"
  New-Item -ItemType Directory -Path $copy | Out-Null
  & robocopy $here $copy /E /XD ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "could not copy the repository (robocopy $LASTEXITCODE)" }
  [IO.File]::WriteAllText((Join-Path $copy "lintcopy-broken.json"), "{ `"broken`": `n")
  Push-Location $copy
  $ErrorActionPreference = "Continue"
  try {
    $out = (& $psExe -NoProfile -ExecutionPolicy Bypass -File "tests\smoke-release.ps1" 2>&1 | Out-String)
    $rc = $LASTEXITCODE
  }
  finally { Pop-Location; $ErrorActionPreference = "Stop" }
  if ($out -like "*bash not installed, lint check skipped*") { Write-Host "(bash not installed, test skipped)"; Write-Host "LINTCOPY OUTPUT OK"; exit 0 }
  if ($rc -eq 0) { Fail "smoke-release.ps1 passed although the lint fails on its copy" }
  if ($out -notlike "*the lint fails on an unchanged copy of the repository*") { Fail "smoke-release.ps1 did not reach the lint-on-a-copy case, so this test proves nothing: $out" }
  if ($out -notlike "*FAIL: ./lintcopy-broken.json does not parse*") { Fail "smoke-release.ps1 hides the lint's FAIL lines when the lint fails on its copy: $out" }
  Write-Host "LINTCOPY OUTPUT OK"
}
finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

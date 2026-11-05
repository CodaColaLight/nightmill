# tests/smoke-validate.ps1 - scripts/validate-config.ps1: the example is clean, every kind of mistake is reported
# on the line that names the key, unknown keys are warnings (errors with -Strict), findings print sorted, enum
# and closed objects work with a schema of their own, usage errors exit 2, this repository's own config passes,
# and the lint notices a schema keyword the validator does not support. Same cases as smoke-validate.sh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$V = Join-Path $here "scripts\validate-config.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-val-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

$ex = [IO.File]::ReadAllText((Join-Path $here "templates\nightmill.example.json"), $utf8)

# Edit: replace a piece of the example text; the piece has to exist.
function Edit([string]$text, [string]$old, [string]$new) {
  if (-not $text.Contains($old)) { Fail "fixture: '$old' is not in the example" }
  return $text.Replace($old, $new)
}

# Run-V <file> <extra arguments>: run the validator in a child powershell, return Out, Err and Code.
function Run-V([string]$file, [string[]]$extra = @()) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$V`" -Config `"$file`" " + ($extra -join " ")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $out; Err = $err; Code = $p.ExitCode }
}

$script:i = 0
# Check <name> <config text> <expected exit code> <expected lines> [extra arguments]:
# every expected line has to be in the output as a whole line.
function Check([string]$name, [string]$text, [int]$code, [string[]]$lines, [string[]]$extra = @()) {
  $script:i++
  $f = Join-Path $tmp ("case$($script:i).json")
  Write-Utf8 $f $text
  $r = Run-V $f $extra
  if ($r.Code -ne $code) { Fail "$name : expected exit code $code, got $($r.Code): $($r.Out) $($r.Err)" }
  $got = @($r.Out -split "`r?`n")
  foreach ($l in $lines) { if ($got -cnotcontains $l) { Fail "$name : missing the line '$l' in: $($r.Out)" } }
}

try {
  Write-Host "== the example is clean"
  Check "example" $ex 0 @("0 errors, 0 warnings")
  Check "example strict" $ex 0 @("0 errors, 0 warnings") @("-Strict")

  Write-Host "== errors name the key"
  Check "owner missing" (Edit $ex '"owner": "acme", ' '') 1 @("error: github.owner: required key is missing", "1 error, 0 warnings")
  Check "slots a string" (Edit $ex '"slots": 2' '"slots": "two"') 1 @("error: worktrees.slots: expected integer, got string")
  Check "project number 0" (Edit $ex '"projectNumber": 1' '"projectNumber": 0') 1 @("error: github.projectNumber: must be at least 1, got 0")
  Check "areas empty" (Edit $ex '"areas": ["core", "api", "ui", "infra", "docs"]' '"areas": []') 1 @("error: areas: needs at least 1 items, got 0")
  Check "areas item a number" (Edit $ex '["core", "api", ' '["core", 3, ') 1 @("error: areas[1]: expected string, got integer")
  Check "port a string" (Edit $ex '"server": 8100' '"server": "x"') 1 @("error: worktrees.ports.server: expected integer, got string")
  Check "maintainer missing" (Edit $ex '"maintainer": { "name": "Alex" },' '') 1 @("error: maintainer: required key is missing")
  Check "check a boolean" (Edit $ex '"check": "bash scripts/check.sh"' '"check": true') 1 @("error: verification.check: expected string, got boolean")
  Check "root an array" "[1]" 1 @("error: .: expected object, got array")
  Check "trailing comma" '{"a": 1,}' 1 @("error: .: not valid JSON", "1 error, 0 warnings")

  Write-Host "== several findings print sorted, the summary counts them"
  $multi = Edit (Edit (Edit $ex '"owner": "acme", ' '') '"slots": 2' '"slots": "two"') '"github": {' '"worktree": 1, "github": {'
  $script:i++
  $f = Join-Path $tmp "multi.json"
  Write-Utf8 $f $multi
  $r = Run-V $f
  if ($r.Code -ne 1) { Fail "several findings: expected exit code 1, got $($r.Code)" }
  $want = "error: github.owner: required key is missing`nwarning: worktree: unknown key (did you mean `"worktrees`"?)`nerror: worktrees.slots: expected integer, got string`n2 errors, 1 warning"
  $got = (@($r.Out -split "`r?`n" | Where-Object { $_ -ne "" }) | Select-Object -Skip 1) -join "`n"
  if ($got -ne $want) { Fail "several findings: wrong lines or order. Got:`n$got`nWanted:`n$want" }

  Write-Host "== unknown keys are warnings"
  $typo = Edit $ex '"github": {' '"worktree": 2, "github": {'
  Check "typo" $typo 0 @('warning: worktree: unknown key (did you mean "worktrees"?)', "0 errors, 1 warning")
  Check "typo strict" $typo 1 @('warning: worktree: unknown key (did you mean "worktrees"?)') @("-Strict")
  Check "unknown nested key" (Edit $ex '"owner": "acme",' '"owner": "acme", "org": "x",') 0 @("warning: github.org: unknown key")

  Write-Host "== roles, models and review"
  Check "new keys clean" $ex 0 @("0 errors, 0 warnings")
  Check "new keys clean strict" $ex 0 @("0 errors, 0 warnings") @("-Strict")
  Check "no new keys" '{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}}' 0 @("0 errors, 0 warnings")
  Check "model not a string" (Edit $ex '"implementer": { "model": "opus" }' '"implementer": { "model": 3 }') 1 @("error: roles.implementer.model: expected string, got integer")
  $rolesArr = [regex]::Replace($ex, '(?s)"roles": \{.*?\r?\n  \},', '"roles": [],')
  if ($rolesArr -eq $ex) { Fail "fixture: the roles block is not in the example" }
  Check "roles not an object" $rolesArr 1 @("error: roles: expected object, got array")
  Check "ranking not an array" (Edit $ex '"ranking": ["haiku", "sonnet", "opus", "fable"]' '"ranking": "opus"') 1 @("error: models.ranking: expected array, got string")
  Check "ranking empty" (Edit $ex '"ranking": ["haiku", "sonnet", "opus", "fable"]' '"ranking": []') 1 @("error: models.ranking: needs at least 1 items, got 0")
  Check "ranking entry not a string" (Edit $ex '"ranking": ["haiku", "sonnet", ' '"ranking": ["haiku", 3, ') 1 @("error: models.ranking[1]: expected string, got integer")
  Check "fix rounds negative" (Edit $ex '"maxFixRounds": 2' '"maxFixRounds": -1') 1 @("error: review.maxFixRounds: must be at least 0, got -1")
  Check "fix rounds a string" (Edit $ex '"maxFixRounds": 2' '"maxFixRounds": "two"') 1 @("error: review.maxFixRounds: expected integer, got string")
  Check "zero fix rounds" (Edit $ex '"maxFixRounds": 2' '"maxFixRounds": 0') 0 @("0 errors, 0 warnings")
  $roleCase = Edit $ex '"codeReviewer"' '"codereviewer"'
  Check "role key wrong case" $roleCase 0 @('warning: roles.codereviewer: unknown key (did you mean "codeReviewer"?)')
  Check "role key wrong case strict" $roleCase 1 @('warning: roles.codereviewer: unknown key (did you mean "codeReviewer"?)') @("-Strict")
  Check "unknown key in a role" (Edit $ex '"implementer": { "model": "opus" }' '"implementer": { "model": "opus", "effort": "high" }') 0 @("warning: roles.implementer.effort: unknown key")

  Write-Host "== enum and closed objects, with a schema of their own"
  $mini = Join-Path $tmp "mini.schema.json"
  Write-Utf8 $mini '{"type":"object","additionalProperties":false,"required":["mode"],"properties":{"mode":{"type":"string","enum":["fast","slow"]}}}'
  $script:i++
  $f = Join-Path $tmp "mini.json"
  Write-Utf8 $f '{"mode":"medium","extra":1}'
  $r = Run-V $f @("-Schema", "`"$mini`"")
  if ($r.Code -ne 1) { Fail "enum: expected exit code 1, got $($r.Code)" }
  $got = @($r.Out -split "`r?`n")
  foreach ($l in 'error: extra: unknown key is not allowed', 'error: mode: must be one of: fast, slow, got "medium"', '2 errors, 0 warnings') { if ($got -cnotcontains $l) { Fail "enum: missing the line '$l' in: $($r.Out)" } }
  Write-Utf8 $f '{"mode":"fast"}'
  $r = Run-V $f @("-Schema", "`"$mini`"")
  if ($r.Code -ne 0) { Fail "enum: a valid value was refused: $($r.Out)" }

  Write-Host "== usage errors exit 2"
  $r = Run-V (Join-Path $tmp "does-not-exist.json")
  if ($r.Code -ne 2) { Fail "missing file: expected exit code 2, got $($r.Code)" }
  if ($r.Err -notlike "*does-not-exist.json*") { Fail "missing file: the message does not name the path: $($r.Err)" }
  $r = Run-V (Join-Path $tmp "case1.json") @("-NoSuchOption")
  if ($r.Code -ne 2) { Fail "unknown option: expected exit code 2, got $($r.Code)" }

  Write-Host "== this repository's own config passes with -Strict"
  $r = Run-V (Join-Path $here ".claude\nightmill.json") @("-Strict")
  if ($r.Code -ne 0) { Fail "the repository's own config does not validate: $($r.Out)" }

  Write-Host "== the lint notices a schema keyword the validator does not support"
  $bash = $null
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    # Git for Windows keeps its own bash in <install>\bin; git.exe sits in <install>\cmd, or deeper (mingw64\bin).
    $dir = Split-Path $gitCmd.Source -Parent
    for ($up = 0; $up -lt 3 -and -not $bash; $up++) {
      $cand = Join-Path (Join-Path $dir "bin") "bash.exe"
      if (Test-Path $cand) { $bash = $cand }
      $dir = Split-Path $dir -Parent
    }
  }
  if (-not $bash) { $found = Get-Command bash -ErrorAction SilentlyContinue; if ($found) { $bash = $found.Source } }
  if (-not $bash) {
    Write-Host "(bash not installed, lint check skipped)"
  }
  else {
    $copy = Join-Path $tmp "repocopy"
    New-Item -ItemType Directory -Path $copy | Out-Null
    & robocopy $here $copy /E /XD ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "could not copy the repository (robocopy $LASTEXITCODE)" }
    $schemaPath = Join-Path $copy "schema\nightmill.schema.json"
    $s = [IO.File]::ReadAllText($schemaPath, $utf8)
    Write-Utf8 $schemaPath ($s -replace '(?m)^(\s*"title":)', ('  "pattern": "x",' + "`n" + '$1'))
    Push-Location $copy
    $ErrorActionPreference = "Continue"
    try {
      $out = (& $bash tests/lint.sh 2>&1 | Out-String)
      if ($LASTEXITCODE -eq 0) { Fail "the lint accepted a schema with a pattern keyword" }
      if ($out -notlike "*pattern*") { Fail "the lint did not name the keyword: $out" }
    }
    finally { Pop-Location }

    Write-Host "== the lint notices a role the workflow skill does not name"
    $copy2 = Join-Path $tmp "repocopy2"
    New-Item -ItemType Directory -Path $copy2 | Out-Null
    & robocopy $here $copy2 /E /XD ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "could not copy the repository (robocopy $LASTEXITCODE)" }
    $skillPath = Join-Path $copy2 "skills\workflow\SKILL.md"
    $w = [IO.File]::ReadAllText($skillPath, $utf8)
    Write-Utf8 $skillPath ($w.Replace("fixer", "fix-er"))
    Push-Location $copy2
    $ErrorActionPreference = "Continue"
    try {
      $out = (& $bash tests/lint.sh 2>&1 | Out-String)
      if ($LASTEXITCODE -eq 0) { Fail "the lint accepted a workflow skill without the fixer role" }
      if ($out -notlike "*fixer*") { Fail "the lint did not name the role: $out" }
    }
    finally { Pop-Location }
  }

  Write-Host "VALIDATE OK"
}
finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

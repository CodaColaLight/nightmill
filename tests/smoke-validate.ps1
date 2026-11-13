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
  # the Agent tool takes only the aliases, so a full model id in a role is an error the validator reports
  $fullPath = Join-Path $tmp "fullid.json"
  Write-Utf8 $fullPath ((Edit $ex '"codeReviewer": { "model": "opus" }' '"codeReviewer": { "model": "claude-opus-5-5" }') + "`n")
  $fullRun = Run-V $fullPath
  if ($fullRun.Code -ne 1) { Fail "a full model id in a role: expected exit code 1, got $($fullRun.Code): $($fullRun.Out)$($fullRun.Err)" }
  if ($fullRun.Out -notmatch '(?m)^error: roles\.codeReviewer\.model:') { Fail "a full model id in a role: no error on roles.codeReviewer.model in: $($fullRun.Out)" }
  foreach ($alias in @("sonnet", "opus", "haiku", "fable")) {
    Check "alias $alias in a role" (Edit $ex '"tester": { "model": "sonnet" }' ('"tester": { "model": "' + $alias + '" }')) 0 @("0 errors, 0 warnings")
  }

  Write-Host "== the reviewer pairing"
  $SW = '"specWriter": { "model": "opus" }'; $SR = '"specReviewer": { "model": "opus" }'
  $CR = '"codeReviewer": { "model": "opus" }'; $RK = '"ranking": ["haiku", "sonnet", "opus", "fable"]'
  $bare = '{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}'
  Check "reviewer stronger" (Edit $ex $SW '"specWriter": { "model": "sonnet" }') 0 @("0 errors, 0 warnings")
  Check "code reviewer stronger" (Edit $ex $CR '"codeReviewer": { "model": "fable" }') 0 @("0 errors, 0 warnings")
  $same = Edit (Edit $ex $RK '"ranking": ["haiku", "sonnet=opus", "fable"]') $SR '"specReviewer": { "model": "sonnet" }'
  Check "same level in one entry" $same 0 @("0 errors, 0 warnings")
  Check "spec reviewer below spec writer" (Edit $ex $SR '"specReviewer": { "model": "sonnet" }') 1 @(
    'error: roles.specReviewer.model: specReviewer on "sonnet" ranks below specWriter on "opus"', "1 error, 0 warnings")
  # two errors on one path sort by their text: fixer before implementer
  $f = Join-Path $tmp "pair2.json"
  Write-Utf8 $f (Edit $ex $CR '"codeReviewer": { "model": "haiku" }')
  $r = Run-V $f
  if ($r.Code -ne 1) { Fail "code reviewer below two producers: expected exit code 1, got $($r.Code)" }
  $want = "error: roles.codeReviewer.model: codeReviewer on `"haiku`" ranks below fixer on `"opus`"`nerror: roles.codeReviewer.model: codeReviewer on `"haiku`" ranks below implementer on `"opus`"`n2 errors, 0 warnings"
  $got = (@($r.Out -split "`r?`n" | Where-Object { $_ -ne "" }) | Select-Object -Skip 1) -join "`n"
  if ($got -ne $want) { Fail "code reviewer below two producers: wrong lines or order. Got:`n$got`nWanted:`n$want" }
  $nosonnet = '"ranking": ["haiku", "opus", "fable"]'
  $unr = Edit (Edit $ex $RK $nosonnet) $SR '"specReviewer": { "model": "sonnet" }'
  $unrLine = 'warning: roles.specReviewer.model: model "sonnet" is not in models.ranking, so specReviewer cannot be compared'
  Check "unranked reviewer" $unr 0 @($unrLine, "0 errors, 1 warning")
  Check "unranked reviewer strict" $unr 1 @($unrLine) @("-Strict")
  Check "unranked producer" (Edit (Edit $ex $RK $nosonnet) '"implementer": { "model": "opus" }' '"implementer": { "model": "sonnet" }') 0 @(
    'warning: roles.implementer.model: model "sonnet" is not in models.ranking, so implementer cannot be compared', "0 errors, 1 warning")
  Check "tester and worker are not compared" (Edit (Edit $ex $RK '"ranking": ["sonnet", "opus", "fable"]') '"tester": { "model": "sonnet" }' '"tester": { "model": "haiku" }') 0 @("0 errors, 0 warnings")
  Check "defaults fill a missing role" ($bare + ',"roles":{"specReviewer":{"model":"sonnet"}}}') 1 @(
    'error: roles.specReviewer.model: specReviewer on "sonnet" ranks below specWriter on "opus"', "1 error, 0 warnings")
  Check "an empty model takes the default" (Edit $ex $SR '"specReviewer": { "model": "" }') 0 @("0 errors, 0 warnings")
  Check "the keys are absent" ($bare + "}") 0 @("0 errors, 0 warnings")
  $f = Join-Path $tmp "norank.json"
  Write-Utf8 $f (Edit $ex $RK '"ranking": ["haiku", "fable"]')
  $r = Run-V $f
  if ($r.Code -ne 0) { Fail "a ranking without the default models: expected exit code 0, got $($r.Code)" }
  $want = (@("codeReviewer", "fixer", "implementer", "specReviewer", "specWriter") | ForEach-Object { "warning: roles.$_.model: model `"opus`" is not in models.ranking, so $_ cannot be compared" }) -join "`n"
  $want += "`n0 errors, 5 warnings"
  $got = (@($r.Out -split "`r?`n" | Where-Object { $_ -ne "" }) | Select-Object -Skip 1) -join "`n"
  if ($got -ne $want) { Fail "a ranking without the default models: wrong lines or order. Got:`n$got`nWanted:`n$want" }
  Check "a bad ranking gives only its own error" (Edit $ex $RK '"ranking": "opus"') 1 @("error: models.ranking: expected array, got string", "1 error, 0 warnings")

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

  Write-Host "== verification.platform is windows, unix or all"
  # the key is in the schema (iteration 56): a known value is clean even with -Strict, any other value is an enum error on the key
  function Plat-Cfg([string]$value) { '{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true","platform":' + $value + '}}' }
  foreach ($plat in "windows", "unix", "all") {
    Check "platform $plat" (Plat-Cfg ('"' + $plat + '"')) 0 @("0 errors, 0 warnings") @("-Strict")
  }
  Check "platform linux" (Plat-Cfg '"linux"') 1 @('error: verification.platform: must be one of: all, windows, unix, got "linux"', "1 error, 0 warnings")
  Check "platform a number" (Plat-Cfg '3') 1 @("error: verification.platform: expected string, got integer")

  Write-Host "== git.mergeFlags must contain --auto and never --admin"
  $MF = '"mergeFlags": "--auto --squash"'
  $pAuto = 'error: git.mergeFlags: must match the pattern ^(.* )?--auto( .*)?$, got '
  $pAdmin = 'error: git.mergeFlags: must not match the pattern ^(.* )?--admin(( |=).*)?$, got '
  Check "merge flags without auto" (Edit $ex $MF '"mergeFlags": "--squash"') 1 @(($pAuto + '"--squash"'))
  Check "merge flags with admin" (Edit $ex $MF '"mergeFlags": "--auto --admin --squash"') 1 @(($pAdmin + '"--auto --admin --squash"'))
  Check "merge flags admin and no auto" (Edit $ex $MF '"mergeFlags": "--admin --squash"') 1 @(($pAuto + '"--admin --squash"'), ($pAdmin + '"--admin --squash"'), "2 errors, 0 warnings")
  Check "merge flags in the other order" (Edit $ex $MF '"mergeFlags": "--squash --auto"') 0 @("0 errors, 0 warnings")
  Check "merge flags with a longer word" (Edit $ex $MF '"mergeFlags": "--auto --administrator"') 0 @("0 errors, 0 warnings")
  Check "merge flags admin with a value" (Edit $ex $MF '"mergeFlags": "--admin=true --auto"') 1 @(($pAdmin + '"--admin=true --auto"'))
  Check "merge flags an integer" (Edit $ex $MF '"mergeFlags": 3') 1 @("error: git.mergeFlags: expected string, got integer", "1 error, 0 warnings")

  Write-Host "== pattern and not, with a schema of their own"
  $pat = Join-Path $tmp "pat.schema.json"
  Write-Utf8 $pat '{"type":"object","properties":{"a":{"type":"string","pattern":"^a"},"b":{"type":"string","not":{"pattern":"b$"}}}}'
  $pf = Join-Path $tmp "pat.json"
  Write-Utf8 $pf '{"a":"b","b":"ab"}'
  $r = Run-V $pf @("-Schema", "`"$pat`"")
  if ($r.Code -ne 1) { Fail "pattern: expected exit code 1, got $($r.Code): $($r.Out) $($r.Err)" }
  $got = @($r.Out -split "`r?`n")
  foreach ($l in 'error: a: must match the pattern ^a, got "b"', 'error: b: must not match the pattern b$, got "ab"', '2 errors, 0 warnings') { if ($got -cnotcontains $l) { Fail "pattern: missing the line '$l' in: $($r.Out)" } }
  Write-Utf8 $pf '{"a":"ab","b":"ba"}'
  $r = Run-V $pf @("-Schema", "`"$pat`"")
  if ($r.Code -ne 0) { Fail "pattern: valid values were refused: $($r.Out)" }

  Write-Host "== -Base reads the configuration on origin/HEAD"
  # Run-Base <directory> <arguments>: the validator started in that directory
  function Run-Base([string]$dir, [string]$argText) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$V`" " + $argText
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ Out = $out; Err = $err; Code = $p.ExitCode }
  }
  function Bgit([string]$dir) {
    # run git in $dir with the remaining arguments; stderr is folded into the output, the exit code is not checked
    $a = @($args)
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & git -C $dir -c user.name=t -c user.email=t@example.invalid @a 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
  }
  $borigin = Join-Path $tmp "borigin.git"
  $brepo = Join-Path $tmp "brepo"
  New-Item -ItemType Directory -Path $borigin, (Join-Path $brepo ".claude") | Out-Null
  Bgit $borigin init -q --bare
  Bgit $brepo init -q -b main
  Write-Utf8 (Join-Path $brepo ".claude\nightmill.json") (Edit $ex $MF '"mergeFlags": "--squash"')
  Bgit $brepo add -A
  Bgit $brepo commit -qm base
  Bgit $brepo remote add origin $borigin
  Bgit $brepo push -q origin main
  Bgit $brepo remote set-head origin main
  Write-Utf8 (Join-Path $brepo ".claude\nightmill.json") $ex
  $r = Run-Base $brepo "-Base"
  if ($r.Code -ne 1) { Fail "-Base: expected exit code 1, got $($r.Code): $($r.Out) $($r.Err)" }
  $got = @($r.Out -split "`r?`n")
  if (-not ($got | Where-Object { $_.StartsWith("validating origin/HEAD:.claude/nightmill.json against ") })) { Fail "-Base: no header naming origin/HEAD: $($r.Out)" }
  if ($got -cnotcontains ($pAuto + '"--squash"')) { Fail "-Base: the base config was not read: $($r.Out)" }
  $r = Run-Base $brepo "-Config `".claude\nightmill.json`""
  if ($r.Code -ne 0) { Fail "the file argument reads the working tree: expected exit code 0, got $($r.Code): $($r.Out)" }
  $r = Run-Base $brepo "-Base -Config `".claude\nightmill.json`""
  if ($r.Code -ne 2) { Fail "-Base with a file: expected exit code 2, got $($r.Code): $($r.Out) $($r.Err)" }
  Bgit $brepo remote set-head origin --delete
  $r = Run-Base $brepo "-Base"
  if ($r.Code -ne 2) { Fail "-Base without origin/HEAD: expected exit code 2, got $($r.Code): $($r.Out) $($r.Err)" }
  if (($r.Out + $r.Err) -notlike "*run git remote set-head origin --auto once*") { Fail "-Base without origin/HEAD: no set-head line: $($r.Out) $($r.Err)" }

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
    Write-Utf8 $schemaPath ($s -replace '(?m)^(\s*"title":)', ('  "format": "x",' + "`n" + '$1'))
    Push-Location $copy
    $ErrorActionPreference = "Continue"
    try {
      $out = (& $bash tests/lint.sh 2>&1 | Out-String)
      if ($LASTEXITCODE -eq 0) { Fail "the lint accepted a schema with a format keyword" }
      if ($out -notlike "*format*") { Fail "the lint did not name the keyword: $out" }
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

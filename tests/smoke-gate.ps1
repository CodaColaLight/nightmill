# tests/smoke-gate.ps1 - scripts/gate.ps1 against a throwaway project and a fake gh (iteration 53, #165;
# docs/specs/iteration-53-run-limits.md, "Tests"): the same cases and the same expected lines as tests/smoke-gate.sh.
# The fake gh is a .cmd that calls a .ps1, first on the PATH. Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$G = Join-Path $here "scripts\gate.ps1"
$fx = Join-Path $PSScriptRoot "fixtures\gate"
$psExe = (Get-Command powershell).Source
# the Git helper below has the name of the program: resolve the program itself, a function would call itself
$script:gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nightmill-smoke-gate-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
if (-not (Test-Path $G)) { Fail "scripts/gate.ps1 does not exist" }
$bin = Join-Path $tmp "bin"; New-Item -ItemType Directory -Path $bin | Out-Null

# the fake gh: answers api graphql from $env:EPIC (exit 1 when GH_FAIL is set), logs every call, fails on any other
$ghPs = @'
$a = $args
Add-Content -Path $env:GH_LOG -Value ($a -join ' ')
if (($a | Select-Object -First 2) -join ' ' -eq 'api graphql') {
  if ($env:GH_FAIL) { [Console]::Error.WriteLine('fake gh: boom'); exit 1 }
  Write-Output (Get-Content $env:EPIC -Raw)
  exit 0
}
[Console]::Error.WriteLine('fake gh: unexpected call'); exit 1
'@
[IO.File]::WriteAllText((Join-Path $bin "gh.ps1"), $ghPs)
[IO.File]::WriteAllText((Join-Path $bin "gh.cmd"), "@echo off`r`n`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n")

$T0 = [long]1794297600 # the claim of the take of slot 1 in the fixture ledger, 2026-11-10T08:00:00Z
function Git { $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $script:gitExe @args 2>&1 } finally { $ErrorActionPreference = $ea } }
function Git-Quiet { $null = Git @args }

$c = Join-Path $tmp "p"; New-Item -ItemType Directory -Path $c | Out-Null
Git-Quiet init -q --bare -b main (Join-Path $c "origin.git")
Git-Quiet clone -q (Join-Path $c "origin.git") (Join-Path $c "main")
$main = Join-Path $c "main"
Git-Quiet -C $main config user.email t@example.com
Git-Quiet -C $main config user.name t
Git-Quiet -C $main checkout -q -b main
$L = Join-Path $c "wt\.slots\ledger.tsv"
$env:GH_LOG = Join-Path $c "gh.log"; $env:EPIC = Join-Path $c "epic.json"; $env:NIGHTMILL_CLOCK_FILE = Join-Path $c "clock"
Remove-Item Env:GH_FAIL, Env:NIGHTMILL_RUN_STARTED, Env:NIGHTMILL_ISSUES_LEFT -ErrorAction SilentlyContinue
Set-Content $env:GH_LOG ""
function Set-Clock([long]$v) { [IO.File]::WriteAllText($env:NIGHTMILL_CLOCK_FILE, "$v`n") }
function Clock-At([int]$minutes) { Set-Clock ($T0 + 60 * $minutes) }
Set-Clock ($T0 + 60)

function Cfg-Text([string]$limits) {
  $tail = ""; if ($limits) { $tail = ",`n  $limits" }
  "{`n  `"github`": { `"owner`": `"acme`", `"repo`": `"widgets`", `"projectNumber`": 1 },`n  `"maintainer`": { `"name`": `"Alex`" },`n  `"verification`": { `"check`": `"true`" },`n  `"worktrees`": { `"root`": `"../wt`", `"slots`": 2 }$tail`n}`n"
}
function Set-Cfg([string]$limits) {
  New-Item -ItemType Directory -Force -Path (Join-Path $main ".claude") | Out-Null
  [IO.File]::WriteAllText((Join-Path $main ".claude\nightmill.json"), (Cfg-Text $limits))
  Git-Quiet -C $main add -A
  Git-Quiet -C $main commit -q --allow-empty -m config
  Git-Quiet -C $main push -q origin main
}
Set-Cfg ""
Git-Quiet -C $main remote set-head origin main
Git-Quiet -C $main fetch -q origin
function Reset-Ledger { New-Item -ItemType Directory -Force -Path (Join-Path $c "wt\.slots") | Out-Null; Copy-Item (Join-Path $fx "ledger.tsv") $L -Force }
Reset-Ledger
function Use-Epic($name) { Copy-Item (Join-Path $fx $name) $env:EPIC -Force }
Use-Epic "epic-none.json"

function Snap {
  $s = (Git -C $main status --porcelain | Out-String) + (Git -C $main for-each-ref | Out-String) + (Git -C $main rev-parse HEAD | Out-String)
  if (Test-Path $L) { $s += ([BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([IO.File]::ReadAllBytes($L)))) }
  $s
}
# Invoke-Gate <arguments> [environment]: gate.ps1 from the main checkout in a child process; Out, Err, All, Code in script scope
function Invoke-Gate([string]$arguments = "", [hashtable]$extraEnv = @{}) {
  $before = Snap
  Set-Content $env:GH_LOG ""
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$G`" $arguments"
  $psi.WorkingDirectory = $main
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables["PATH"] = $bin + ";" + $env:PATH
  foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $script:out = ($o.Result -replace "`r`n", "`n"); $script:err = ($e.Result -replace "`r`n", "`n"); $script:code = $p.ExitCode
  $script:all = $script:out + "`n" + $script:err
  if ($before -ne (Snap)) { Fail "gate ${arguments}: the tree, the ledger or a ref changed" }
  foreach ($l in @(Get-Content $env:GH_LOG)) { if ($l -and -not $l.StartsWith("api graphql")) { Fail "gate ${arguments}: a gh call other than api graphql: $l" } }
}
function Want-Code([int]$expected, [string]$what) { if ($script:code -ne $expected) { Fail "${what}: exit $($script:code), $expected expected ($($script:all))" } }
function Has([string]$text, [string]$needle, [string]$what) { if (-not $text.Contains($needle)) { Fail "${what}: '$needle' not found in: $text" } }
function Last-Lines([string]$what, [string[]]$want) {
  $lines = @($script:out.TrimEnd("`n") -split "`n")
  $got = @($lines | Select-Object -Last $want.Count)
  if (($got -join "|") -ne ($want -join "|")) { Fail "${what}: the last $($want.Count) lines are [$($got -join '|')], [$($want -join '|')] expected" }
}
function Gh-Calls { @(Get-Content $env:GH_LOG | Where-Object { $_ }).Count }

Write-Host "== go"
Invoke-Gate
Want-Code 0 "go"
Last-Lines "go" @("gate: issues per run: 10", "gate: go")

Write-Host "== paused"
Set-Cfg '"limits": { "paused": true }'
Invoke-Gate
Want-Code 1 "paused"
Has $script:all "gate: paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" "paused"
Invoke-Gate "-Issue 21"
Want-Code 1 "paused with an issue"
Set-Cfg ""

Write-Host "== paused on a branch only"
Git-Quiet -C $main checkout -q -b feat/unpause
[IO.File]::WriteAllText((Join-Path $main ".claude\nightmill.json"), (Cfg-Text '"limits": { "paused": true }'))
Git-Quiet -C $main commit -q -am "pause on a branch"
Invoke-Gate
Want-Code 0 "paused on a branch only"
Git-Quiet -C $main checkout -q main

Write-Host "== paused, not yet fetched"
$other = Join-Path $c "other"
Git-Quiet clone -q (Join-Path $c "origin.git") $other
Git-Quiet -C $other config user.email t@example.com
Git-Quiet -C $other config user.name t
[IO.File]::WriteAllText((Join-Path $other ".claude\nightmill.json"), (Cfg-Text '"limits": { "paused": true }'))
Git-Quiet -C $other commit -q -am pause
Git-Quiet -C $other push -q origin main
Invoke-Gate
Want-Code 0 "paused, not yet fetched (the gate does not fetch)"
Git-Quiet -C $main fetch -q origin
Invoke-Gate
Want-Code 1 "paused after the fetch"
Has $script:all "gate: paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" "paused after the fetch"
Git-Quiet -C $other revert --no-edit HEAD
Git-Quiet -C $other push -q origin main
Git-Quiet -C $main pull -q --rebase origin main
Git-Quiet -C $main fetch -q origin
Invoke-Gate
Want-Code 0 "unpaused again"

Write-Host "== epic"
Use-Epic "epic-paused.json"
Invoke-Gate "-Issue 21"
Want-Code 4 "epic paused"
Has $script:all "gate: paused: epic #5 has the label paused" "epic paused"
Use-Epic "epic-open.json"
Invoke-Gate "-Issue 21"
Want-Code 0 "epic not paused (a parent without the label)"
Use-Epic "epic-none.json"
Invoke-Gate "-Issue 21"
Want-Code 0 "epic not paused (no parent)"
Invoke-Gate
if ((Gh-Calls) -ne 0) { Fail "no -Issue: gh was called" }

Write-Host "== gh fails"
$env:GH_FAIL = "1"
Invoke-Gate "-Issue 21"
Want-Code 2 "gh fails"
Has $script:all "gate: cannot check: the epic of #21 could not be read: " "gh fails"
Has $script:all "fake gh: boom" "gh fails"
Remove-Item Env:GH_FAIL

Write-Host "== cost"
Set-Cfg '"limits": { "costPerIssueUsd": 5 }'
Invoke-Gate "-Issue 21"; Want-Code 0 "cost 21 under"
Last-Lines "cost 21 under" @('gate: spent on #21: $4.00 of $5.00', "gate: go")
Set-Cfg '"limits": { "costPerIssueUsd": 4 }'
Invoke-Gate "-Issue 21"; Want-Code 3 "cost 21 at the limit"
Has $script:all 'gate: limit: #21 has spent $4.00 in headless runs; the limit is $4.00 (limits.costPerIssueUsd)' "cost 21 at the limit"
Set-Cfg '"limits": { "costPerIssueUsd": 3.01 }'
Invoke-Gate "-Issue 12"; Want-Code 0 "cost 12 under (half of the 11,12 line)"
Last-Lines "cost 12 under" @('gate: spent on #12: $3.00 of $3.01', "gate: go")
Set-Cfg '"limits": { "costPerIssueUsd": 3 }'
Invoke-Gate "-Issue 12"; Want-Code 3 "cost 12 at the limit"
Has $script:all '#12 has spent $3.00 in headless runs; the limit is $3.00' "cost 12 at the limit"
Set-Cfg ""

Write-Host "== minutes"
Clock-At 179
Invoke-Gate "-Issue 21 -Slot 1"; Want-Code 0 "minutes 179"
Clock-At 180
Invoke-Gate "-Issue 21 -Slot 1"; Want-Code 3 "minutes 180"
Has $script:all "gate: limit: #21 has been worked on for 180 minutes in this run; the limit is 180 (limits.minutesPerIssue)" "minutes 180"
Write-Host "== run started later"
Invoke-Gate "-Issue 21 -Slot 1" @{ NIGHTMILL_RUN_STARTED = ($T0 + 180 * 60 - 600) }
Want-Code 0 "run started later"
Write-Host "== not measured"
Clock-At 500
Invoke-Gate "-Issue 21"; Want-Code 0 "not measured"
Has $script:err "gate: minutes per issue not measured (no slot and no driver run)" "not measured"
Clock-At 1

Write-Host "== turns"
Invoke-Gate "-Role tester -Turns 150"; Want-Code 0 "tester 150"
Invoke-Gate "-Role tester -Turns 151"; Want-Code 3 "tester 151"
Has $script:all "gate: limit: the tester role took 151 turns; the limit is 150 (limits.turnsPerRole.tester)" "tester 151"
Invoke-Gate "-Role session -Turns 201"; Want-Code 3 "session 201"
Invoke-Gate "-Role session -Turns 200"; Want-Code 0 "session 200"
Invoke-Gate "-Role boss -Turns 1"; Want-Code 2 "unknown role"
Has $script:all "gate: cannot check: unknown role boss" "unknown role"
Set-Cfg '"limits": { "turnsPerRole": { "worker": 5 } }'
Invoke-Gate "-Role worker -Turns 6"; Want-Code 3 "a configured role limit"
Has $script:all "(limits.turnsPerRole.worker)" "a configured role limit"
Invoke-Gate "-Role tester -Turns 150"; Want-Code 0 "a role keeps its default beside a configured one"
Set-Cfg ""

Write-Host "== issues left"
foreach ($pair in "3=3", "0=0", "20=10", "10=10", "x=10") {
  $left, $want = $pair -split "="
  Invoke-Gate "" @{ NIGHTMILL_ISSUES_LEFT = $left }
  Want-Code 0 "issues left $left"
  Last-Lines "issues left $left" @("gate: issues per run: $want", "gate: go")
}

Write-Host "== bad value"
function Bad([string]$members, [string]$msg) {
  Set-Cfg "`"limits`": { $members }"
  Invoke-Gate "-Issue 21"
  Want-Code 2 "bad value ($members)"
  Has $script:all "gate: cannot check: $msg" "bad value ($members)"
  if ((Gh-Calls) -ne 0) { Fail "bad value ($members): gh was called" }
}
Bad '"paused": "yes"' 'limits.paused must be true or false, got "yes"'
Bad '"minutesPerIssue": 0' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 0'
Bad '"minutesPerIssue": 1441' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 1441'
Bad '"minutesPerIssue": 2.5' 'limits.minutesPerIssue must be a whole number from 1 to 1440, got 2.5'
Bad '"costPerIssueUsd": 0' 'limits.costPerIssueUsd must be a number from 0.01 to 10000, got 0'
Bad '"turnsPerRole": { "tester": "9" }' 'limits.turnsPerRole.tester must be a whole number from 1 to 10000, got "9"'
Bad '"issuesPerRun": 101' 'limits.issuesPerRun must be a whole number from 1 to 100, got 101'
Set-Cfg ""

Write-Host "== no ledger"
Remove-Item $L -Force
Invoke-Gate "-Issue 21"; Want-Code 0 "no ledger"
Last-Lines "no ledger" @('gate: spent on #21: $0.00 of $25.00', "gate: go")
Reset-Ledger

Write-Host "== usage"
Invoke-Gate "-Turns 3"; Want-Code 2 "turns without role"
Has $script:err "usage" "turns without role"
Invoke-Gate "-Issue x"; Want-Code 2 "issue x"
Has $script:err "usage" "issue x"
Invoke-Gate "-Role tester"; Want-Code 2 "role without turns"
Invoke-Gate "--bogus"; Want-Code 2 "unknown option"
Invoke-Gate "-h"; Want-Code 0 "help"
Has $script:out "gate.ps1" "help"

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host "smoke-gate.ps1: ok"

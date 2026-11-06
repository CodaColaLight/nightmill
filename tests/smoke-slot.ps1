# tests/smoke-slot.ps1 - slot.ps1 against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon, and the automatic release of a slot whose pull
# request has merged (-Reap and the first step of every -Take), with -Release, against a fake gh, and the
# capacity command (-Capacity: the slot count and the agent limit changed during a session).
# Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$S = Join-Path $here "scripts\slot.ps1"
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Slot { param([Parameter(ValueFromRemainingArguments = $true)]$a)
  # stdout only: redirecting a native command's stderr in Windows PowerShell 5.1 turns git's
  # progress lines into terminating errors. Failures are checked through the exit code.
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $S @a | Out-String
  $script:code = $LASTEXITCODE
  $out
}
# SlotE <arguments> [environment]: run slot.ps1 in a child process, with its standard error kept apart; Out, Err, Code
function SlotE([string]$arguments, [hashtable]$extraEnv = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$S`" $arguments"
  $psi.WorkingDirectory = "$tmp\work"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Out = ($out -replace "`r`n", "`n"); Err = ($errTask.Result -replace "`r`n", "`n"); Code = $p.ExitCode }
}

# A fake gh (a gh.cmd first on the PATH for the whole test): it answers "pr list" from $env:GH_FIX\merged.txt (rows
# of branch TAB number TAB head commit; --state merged only, an open query gives an empty list), logs every call to
# $env:GH_LOG and fails when GH_FAIL is set. With -q it prints the first number, as gh does for '.[0].number'.
$bin = Join-Path $tmp "bin"; $fix = Join-Path $tmp "fix"
New-Item -ItemType Directory $bin, $fix | Out-Null
$ghLog = Join-Path $tmp "gh.log"
[System.IO.File]::WriteAllText((Join-Path $fix "merged.txt"), "")
[System.IO.File]::WriteAllText($ghLog, "")
[System.IO.File]::WriteAllText((Join-Path $bin "gh-fake.ps1"), @'
Add-Content -Path $env:GH_LOG -Value ($args -join " ")
if ($env:GH_FAIL) { [Console]::Error.WriteLine("HTTP 401: bad credentials"); exit 1 }
if ("$($args[0]) $($args[1])" -ne "pr list") { [Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')"); exit 1 }
$state = ""; $head = ""; $jq = ""
for ($i = 2; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    "--state" { $state = $args[$i + 1]; $i++ }
    "--head" { $head = $args[$i + 1]; $i++ }
    { $_ -eq "-q" -or $_ -eq "--jq" } { $jq = $args[$i + 1]; $i++ }
  }
}
if ($state -ne "merged") { [Console]::Out.Write("[]"); exit 0 }
$rows = @()
foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $env:GH_FIX "merged.txt"))) {
  $f = $line -split "`t"
  if ($f.Count -ge 3 -and $f[0] -ceq $head) { $rows += , $f }
}
if ($jq) { if ($rows.Count -gt 0) { [Console]::Out.Write($rows[0][1]) }; exit 0 }
$items = @($rows | ForEach-Object { '{"number":' + $_[1] + ',"headRefOid":"' + $_[2] + '"}' })
[Console]::Out.Write("[" + ($items -join ",") + "]")
exit 0
'@)
[System.IO.File]::WriteAllText((Join-Path $bin "gh.cmd"), "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n")
$env:PATH = "$bin;" + $env:PATH
$env:GH_FIX = $fix
$env:GH_LOG = $ghLog

try {
  git init -q --bare "$tmp\origin.git"
  git init -q -b main "$tmp\work"
  Set-Location "$tmp\work"
  git config core.autocrlf false
  New-Item -ItemType Directory ".claude", "client" | Out-Null
  $cfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "ports": { "server": 8100 },
    "warmup": [ { "dir": "client", "command": "echo warm > warmed.txt", "lockfile": "client/lock.txt" } ],
    "runHints": [ "PORT={port.server} slot {slot}" ]
  }
}
'@
  [System.IO.File]::WriteAllText("$tmp\work\.claude\nightmill.json", $cfg)
  [System.IO.File]::WriteAllText("$tmp\work\client\lock.txt", "v1`n")
  [System.IO.File]::WriteAllText("$tmp\work\.gitignore", "warmed.txt`n")
  git add -A
  git -c user.name=t -c user.email=t@example.invalid commit -qm init
  git remote add origin "$tmp\origin.git"
  git push -q origin main

  Write-Host "== status before anything"
  $out = Slot -Status
  if ($out -notmatch "slot 1  not created yet free") { Fail "initial status: $out" }

  Write-Host "== take slot 1"
  $out = Slot -Take feat/a
  if ($code -ne 0) { Fail "take exited $code`: $out" }
  if ($out -notmatch "Slot 1 is yours") { Fail "take did not report slot 1: $out" }
  if ($out -notmatch "port server: 8101") { Fail "port hint: $out" }
  if ($out -notmatch "PORT=8101 slot 1") { Fail "run hint placeholders: $out" }
  if (-not (Test-Path "$tmp\wt\slot-1\client\warmed.txt")) { Fail "warm-up did not run" }
  if ((git -C "$tmp\wt\slot-1" branch --show-current) -ne "feat/a") { Fail "branch in slot 1" }
  if (-not (Test-Path "$tmp\wt\.slots\slot-1.json")) { Fail "marker" }

  Write-Host "== take slot 2, third take fails"
  $out = Slot -Take feat/b
  if ($out -notmatch "Slot 2 is yours") { Fail "take slot 2: $out" }
  $out = Slot -Take feat/c
  if ($code -eq 0) { Fail "third take should fail" }
  $out = Slot -Status
  if ($out -notmatch "busy: feat/a") { Fail "status shows slot 1 busy: $out" }

  Write-Host "== -Porcelain: one tab separated line per slot"
  $out = Slot -Status -Porcelain
  $lines = @($out -split "`r?`n" | Where-Object { $_ -ne "" })
  if ($lines.Count -ne 2) { Fail "porcelain line count: $out" }
  $f1 = $lines[0] -split "`t"
  $f2 = $lines[1] -split "`t"
  if ($f1[0] -ne "1" -or $f1[1] -ne "busy" -or $f1[2] -ne "feat/a" -or -not $f1[3]) { Fail "porcelain line for slot 1: $($lines[0])" }
  if ($f2[0] -ne "2" -or $f2[1] -ne "busy" -or $f2[2] -ne "feat/b") { Fail "porcelain line for slot 2: $($lines[1])" }
  $out = Slot -Status
  if ($out -notmatch "slots = 2") { Fail "status without -Porcelain changed: $out" }

  Write-Host "== warm-up skipped while the lockfile is unchanged"
  $null = Slot -Abandon 1
  Remove-Item "$tmp\wt\slot-1\client\warmed.txt"
  $null = Slot -Take feat/d
  if (Test-Path "$tmp\wt\slot-1\client\warmed.txt") { Fail "warm-up ran again although the lockfile hash is unchanged" }

  Write-Host "== WORKER_SLOTS overrides the count"
  $env:WORKER_SLOTS = "3"
  $out = Slot -Status
  Remove-Item Env:WORKER_SLOTS
  if ($out -notmatch "slot 3") { Fail "WORKER_SLOTS override: $out" }

  Write-Host "== abandon both"
  $null = Slot -Abandon 1
  $null = Slot -Abandon 2
  $out = Slot -Status
  if ($out -notmatch "slot 2  ready           free") { Fail "slot 2 free after abandon: $out" }
  $out = Slot -Status -Porcelain
  $lines = @($out -split "`r?`n" | Where-Object { $_ -ne "" })
  if ($lines.Count -ne 2 -or $lines[0] -ne "1`tfree" -or $lines[1] -ne "2`tfree") { Fail "porcelain after abandon: $out" }

  Write-Host "== automatic release"
  $work = "$tmp\work"
  # Prepare <n> <branch>: take slot n on the branch, commit one file there and push it; the tip is left in $tip
  function Prepare([int]$n, [string]$b) {
    $d = "$tmp\wt\slot-$n"
    $null = Slot -Take $b -Slot $n
    [System.IO.File]::WriteAllText("$d\work.txt", "$b`n")
    git -C $d add -A
    git -C $d -c user.name=t -c user.email=t@example.invalid commit -qm "work on $b"
    $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    git -C $d push -q origin $b 2>&1 | Out-Null
    $ErrorActionPreference = $ea
    $script:tip = ([string](git -C $d rev-parse HEAD)).Trim()
  }
  function Merged([string]$b, [int]$n, [string]$oid) { [System.IO.File]::AppendAllText("$fix\merged.txt", "$b`t$n`t$oid`n") }
  function Reset-Gh { [System.IO.File]::WriteAllText("$fix\merged.txt", ""); [System.IO.File]::WriteAllText($ghLog, "") }
  function Marker([int]$n) { "$tmp\wt\.slots\slot-$n.json" }
  function Clear-Slots { foreach ($n in 1, 2) { if (Test-Path (Marker $n)) { $null = Slot -Abandon $n } } }
  function Test-Branch([string]$repo, [string]$b) { git -C $repo show-ref --verify --quiet "refs/heads/$b"; return ($LASTEXITCODE -eq 0) }
  $none = "No slot freed."

  # 1 merged and clean is freed by -Reap
  Reset-Gh; Prepare 1 feat/m1; Merged feat/m1 12 $tip
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne "Slot 1 is free (was feat/m1, PR #12), released automatically.") { Fail "reap: wrong output: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 1)) { Fail "reap: the marker is still there" }
  if (git -C "$tmp\wt\slot-1" branch --show-current) { Fail "reap: the slot is not detached" }
  if (([string](git -C "$tmp\wt\slot-1" rev-parse HEAD)).Trim() -ne ([string](git -C $work rev-parse origin/main)).Trim()) { Fail "reap: the slot is not on origin/main" }
  if (Test-Branch $work "feat/m1") { Fail "reap: the local branch is still there" }
  if (-not (Test-Branch "$tmp\origin.git" "feat/m1")) { Fail "reap: the remote branch is gone" }
  if ((Slot -Status) -notmatch "slot 1  ready           free") { Fail "reap: status does not show slot 1 free" }

  # 2 a take frees it first; without a freeable slot the same take still fails
  # (the pull request only counts as merged after both slots are prepared: every take, preparing included, frees merged slots first)
  Reset-Gh; Prepare 1 feat/m2; $tip1 = $tip; Prepare 2 feat/live; Merged feat/m2 13 $tip1
  $r = SlotE "-Take feat/x"
  $a = $r.Out.IndexOf("released automatically"); $b = $r.Out.IndexOf("Slot 1 is yours")
  if ($a -lt 0 -or $b -lt 0 -or $a -gt $b) { Fail "take: the freed line has to come before the take's own output: $($r.Out)" }
  if (-not $r.Out.Contains("Slot 1 is free (was feat/m2, PR #13), released automatically.")) { Fail "take: wrong freed line: $($r.Out)" }
  if ((git -C "$tmp\wt\slot-1" branch --show-current) -ne "feat/x") { Fail "take: slot 1 is not on feat/x" }
  Clear-Slots
  Reset-Gh; Prepare 1 feat/n1; Prepare 2 feat/n2
  $r = SlotE "-Take feat/y"
  if ($r.Code -eq 0) { Fail "take with nothing freeable should fail" }
  if ($r.Err -notmatch "all 2 slots are busy") { Fail "take with nothing freeable: wrong message: $($r.Err)" }
  Clear-Slots

  # 3 uncommitted files keep it busy, and gh is not asked about that slot
  Reset-Gh; Prepare 1 feat/m3; Merged feat/m3 14 $tip; [System.IO.File]::WriteAllText("$tmp\wt\slot-1\untracked.txt", "x`n")
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne $none) { Fail "dirty: wrong output: $($r.Out)" }
  if (-not (Test-Path (Marker 1))) { Fail "dirty: the marker is gone" }
  if (-not (Test-Branch $work "feat/m3")) { Fail "dirty: the branch is gone" }
  if ([System.IO.File]::ReadAllText($ghLog).Contains("feat/m3")) { Fail "dirty: gh was asked about a slot with uncommitted files" }
  Remove-Item "$tmp\wt\slot-1\untracked.txt"; Clear-Slots

  # 4 no merged pull request (an open or closed-unmerged one looks the same to the merged query)
  Reset-Gh; Prepare 1 feat/m4
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne $none) { Fail "no merged PR: wrong output: $($r.Out)" }
  if (-not (Test-Path (Marker 1))) { Fail "no merged PR: the marker is gone" }
  Clear-Slots

  # 5 work after the merge keeps it busy, the newer commit is not lost
  Reset-Gh; Prepare 1 feat/m5; Merged feat/m5 15 $tip
  [System.IO.File]::WriteAllText("$tmp\wt\slot-1\more.txt", "more`n")
  git -C "$tmp\wt\slot-1" add -A
  git -C "$tmp\wt\slot-1" -c user.name=t -c user.email=t@example.invalid commit -qm "after the merge"
  $newer = ([string](git -C "$tmp\wt\slot-1" rev-parse HEAD)).Trim()
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne $none) { Fail "work after the merge: wrong output: $($r.Out)" }
  if (-not (Test-Path (Marker 1))) { Fail "work after the merge: the marker is gone" }
  if (([string](git -C $work rev-parse refs/heads/feat/m5)).Trim() -ne $newer) { Fail "work after the merge: the branch lost its newer commit" }
  Clear-Slots

  # 6 a reused branch name: the merged pull request's head is not on this branch at all
  Reset-Gh; Prepare 1 feat/m6; Merged feat/m6 16 (([string](git -C $work rev-parse origin/main)).Trim())
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne $none) { Fail "reused branch name: wrong output: $($r.Out)" }
  if (-not (Test-Path (Marker 1))) { Fail "reused branch name: the marker is gone" }
  Clear-Slots

  # 7 gh failing keeps it busy, says so on standard error and does not break a take
  Reset-Gh; Prepare 1 feat/m7; Merged feat/m7 17 $tip
  $r = SlotE "-Reap" @{ GH_FAIL = "1" }
  if ($r.Code -ne 0) { Fail "gh failing: -Reap exited $($r.Code)" }
  if ($r.Out.Trim() -ne $none) { Fail "gh failing: wrong output: $($r.Out)" }
  if ($r.Err -notmatch "(?m)^slot 1: not checked for a merged PR \(") { Fail "gh failing: no note on standard error: $($r.Err)" }
  if (-not (Test-Path (Marker 1))) { Fail "gh failing: the marker is gone" }
  $r = SlotE "-Take feat/z" @{ GH_FAIL = "1" }
  if ($r.Code -ne 0) { Fail "gh failing: a take with a free slot failed: $($r.Err)" }
  if ((git -C "$tmp\wt\slot-2" branch --show-current) -ne "feat/z") { Fail "gh failing: the take did not use slot 2" }
  Clear-Slots

  # 8 -Status is read-only: no gh call, no marker change
  Reset-Gh; Prepare 1 feat/m8; Merged feat/m8 18 $tip; [System.IO.File]::WriteAllText($ghLog, "")
  $before = [System.IO.File]::ReadAllText((Marker 1))
  $null = Slot -Status; $null = Slot -Status -Porcelain
  if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "status asked gh: $([System.IO.File]::ReadAllText($ghLog))" }
  if ([System.IO.File]::ReadAllText((Marker 1)) -ne $before) { Fail "status changed the marker" }
  Clear-Slots

  # 9 -Release and -Abandon are unchanged
  Reset-Gh; Prepare 1 feat/m9; Merged feat/m9 19 $tip
  $r = SlotE "-Release 1"
  $last = (@($r.Out -split "`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -Last 1).Trim() # the line before it is git's own "Deleted branch" message
  if ($last -ne "Slot 1 is free (was feat/m9, PR #19).") { Fail "release: wrong output: $($r.Out) / $($r.Err)" }
  Prepare 1 feat/m9b
  $r = SlotE "-Release 1"
  if ($r.Code -eq 0) { Fail "release without a merged PR should fail" }
  if ($r.Err -notmatch [regex]::Escape("no merged PR for feat/m9b. Merge it first, or free the slot with -Abandon 1.")) { Fail "release: wrong refusal: $($r.Err)" }
  $r = SlotE "-Abandon 1"
  if ($r.Out.Trim() -ne "Slot 1 is free (was feat/m9b; the local branch is kept, delete it yourself if unwanted).") { Fail "abandon: wrong output: $($r.Out)" }

  # 10 the marker format is unchanged: exactly the keys slot, branch and since (this shell has always written them
  # from a hashtable, so their order is not fixed here; slot.sh writes them in that order)
  Reset-Gh; Prepare 1 feat/m10
  $keys = ((([System.IO.File]::ReadAllText((Marker 1)) | ConvertFrom-Json).PSObject.Properties.Name) | Sort-Object) -join ","
  if ($keys -ne "branch,since,slot") { Fail "marker keys: $keys" }
  Clear-Slots

  # 11 a marker without a worktree is left alone and does not stop the run
  Reset-Gh
  [System.IO.File]::WriteAllText("$tmp\wt\.slots\slot-3.json", "{`n  `"slot`": 3,`n  `"branch`": `"feat/ghost`",`n  `"since`": `"2026-01-01T00:00:00`"`n}`n")
  $r = SlotE "-Reap" @{ WORKER_SLOTS = "3" }
  if ($r.Code -ne 0 -or $r.Out.Trim() -ne $none) { Fail "marker without a worktree: exit $($r.Code), output: $($r.Out) / $($r.Err)" }
  if (-not (Test-Path "$tmp\wt\.slots\slot-3.json")) { Fail "marker without a worktree: the marker was removed" }
  Remove-Item "$tmp\wt\.slots\slot-3.json"

  # 12 nothing to free
  Reset-Gh
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne $none) { Fail "nothing to free: wrong output: $($r.Out)" }
  if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "nothing to free: gh was asked: $([System.IO.File]::ReadAllText($ghLog))" }

  Write-Host "== capacity"
  # -Capacity (iteration 22): the slot count and the agent limit, set during a session in <root>/.slots/capacity.json
  $C = "$tmp\wt\.slots\capacity.json"
  $CFG = "$work\.claude\nightmill.json"
  $cfgBefore = [System.IO.File]::ReadAllText($CFG)
  function Cap([string]$arguments = "", [hashtable]$extraEnv = @{}) { SlotE ("-Capacity " + $arguments) $extraEnv }
  function Lines([string]$text) { @($text -split "`n" | Where-Object { $_ -ne "" }) }
  function Read-Cap { if (Test-Path $C) { [System.IO.File]::ReadAllText($C) } else { "<none>" } }
  function Porc { Lines (SlotE "-Status -Porcelain").Out }
  $T = "`t"
  Reset-Gh; if (Test-Path $C) { Remove-Item $C }

  # 1 no value prints the numbers
  $r = Cap
  if ($r.Out -ne "slots: 2 (config)`nagents: 2 (default)`n") { Fail "capacity show: $($r.Out) / $($r.Err)" }
  $r = Cap "" @{ WORKER_SLOTS = "4" }
  if ($r.Out -ne "slots: 4 (WORKER_SLOTS; config 2)`nagents: 2 (default)`n") { Fail "capacity show with WORKER_SLOTS: $($r.Out)" }
  if (Test-Path $C) { Fail "showing wrote capacity.json" }

  # 2 set prints one line and keeps the file; the tracked config is not edited
  $r = Cap "-SlotCount 3 -AgentLimit 3"
  if ($r.Out -ne "capacity: slots 2 -> 3, agents 2 -> 3`n") { Fail "capacity set: $($r.Out) / $($r.Err)" }
  $cap = [System.IO.File]::ReadAllText($C)
  if ($cap -notmatch '(?m)^  "slots": 3,$') { Fail "capacity.json has no slots 3: $cap" }
  if ($cap -notmatch '(?m)^  "maxAgents": 3,$') { Fail "capacity.json has no maxAgents 3: $cap" }
  if ($cap -notmatch '(?m)^  "since": "[0-9-]*T[0-9:]*"$') { Fail "capacity.json has no since: $cap" }
  if ($cap.Contains("`r")) { Fail "capacity.json is not LF" }
  if ([System.IO.File]::ReadAllText($CFG) -cne $cfgBefore) { Fail "the config file was edited" }
  if (git -C $work status --porcelain) { Fail "the checkout is not clean after a set" }
  $r = Cap
  if ($r.Out -ne "slots: 3 (live; config 2)`nagents: 3 (live; config 2)`n") { Fail "capacity show after set: $($r.Out)" }
  $r = Cap "-AgentLimit 4"
  if ($r.Out -ne "capacity: agents 3 -> 4`n") { Fail "capacity set agents only: $($r.Out)" }
  if ((Lines (Cap).Out)[0] -ne "slots: 3 (live; config 2)") { Fail "setting the agent limit changed the slot count" }
  $r = Cap "-SlotCount 3"
  if ($r.Out -ne "capacity: slots 3 (unchanged)`n") { Fail "capacity set unchanged: $($r.Out)" }
  $null = Cap "-AgentLimit 3"

  # 3 raising makes the new slot available; its worktree is created by the take
  if (Test-Path "$tmp\wt\slot-3") { Fail "slot 3 exists before it was taken" }
  foreach ($i in 1, 2, 3) {
    $r = SlotE "-Take feat/c$i"
    if ($r.Out -notmatch "Slot $i is yours") { Fail "raised count: take $i did not get slot $i`: $($r.Out) / $($r.Err)" }
  }
  if (-not (Test-Path "$tmp\wt\slot-3")) { Fail "the take did not create the worktree of slot 3" }

  # 4 lowering never touches a busy slot: it is retiring until released
  $m2 = [System.IO.File]::ReadAllText((Marker 2)); $m3 = [System.IO.File]::ReadAllText((Marker 3))
  $h2 = ([string](git -C "$tmp\wt\slot-2" rev-parse HEAD)).Trim(); $h3 = ([string](git -C "$tmp\wt\slot-3" rev-parse HEAD)).Trim()
  $r = Cap "-SlotCount 1"
  if ($r.Out -ne "capacity: slots 3 -> 1`n") { Fail "capacity lower: $($r.Out)" }
  if ([System.IO.File]::ReadAllText((Marker 2)) -ne $m2 -or [System.IO.File]::ReadAllText((Marker 3)) -ne $m3) { Fail "lowering changed a marker" }
  if (([string](git -C "$tmp\wt\slot-2" rev-parse HEAD)).Trim() -ne $h2 -or ([string](git -C "$tmp\wt\slot-3" rev-parse HEAD)).Trim() -ne $h3) { Fail "lowering changed a worktree" }
  if ((git -C "$tmp\wt\slot-3" branch --show-current) -ne "feat/c3") { Fail "lowering switched slot 3" }
  $st = Slot -Status
  if ($st -notmatch "(?m)^slots = 1  root = ") { Fail "status header after lowering: $st" }
  if ($st -notmatch [regex]::Escape("capacity: slots 1 (live; config 2), agents 3 (live; config 2)")) { Fail "status capacity line: $st" }
  if ($st -notmatch "(?m)^slot 2  ready           busy: feat/c2 since .* \(retiring\)\r?$") { Fail "status: slot 2 is not retiring: $st" }
  if ($st -notmatch "(?m)^slot 3  ready           busy: feat/c3 since .* \(retiring\)\r?$") { Fail "status: slot 3 is not retiring: $st" }
  if ($st -notmatch "(?m)^slot 1 .*busy: feat/c1 since [0-9T:-]*\r?$") { Fail "status: slot 1 must not be retiring: $st" }
  $p = Porc
  if ($p.Count -ne 3) { Fail "porcelain after lowering: $($p -join ' | ')" }
  $f = $p[0] -split $T; if ($f.Count -ne 10 -or $f[4] -ne "") { Fail "porcelain: slot 1 has a fifth field: $($p[0])" }
  $f = $p[1] -split $T; if ($f[0] -ne "2" -or $f[1] -ne "busy" -or $f[2] -ne "feat/c2" -or $f[4] -ne "retiring") { Fail "porcelain: slot 2: $($p[1])" }
  $f = $p[2] -split $T; if ($f[0] -ne "3" -or $f[1] -ne "busy" -or $f[2] -ne "feat/c3" -or $f[4] -ne "retiring") { Fail "porcelain: slot 3: $($p[2])" }
  $r = SlotE "-Take feat/c9"
  if ($r.Code -eq 0) { Fail "a take above the lowered count should fail" }
  if ($r.Err -notmatch "all 1 slots are busy") { Fail "take after lowering: wrong message: $($r.Err)" }
  Merged feat/c3 23 $h3; Merged feat/c2 22 $h2
  $r = SlotE "-Release 3"
  if ($r.Code -ne 0) { Fail "releasing the retiring slot 3 failed: $($r.Err)" }
  $p = Porc
  if ((@($p | ForEach-Object { ($_ -split $T)[0] }) -join " ") -ne "1 2") { Fail "after releasing slot 3: $($p -join ' | ')" }
  $r = SlotE "-Release 2"
  if ($r.Code -ne 0) { Fail "releasing the retiring slot 2 failed: $($r.Err)" }
  $p = Porc
  if ((@($p | ForEach-Object { ($_ -split $T)[0] }) -join " ") -ne "1") { Fail "after releasing slot 2: $($p -join ' | ')" }
  if ((Slot -Status) -match "(?m)^slot 2") { Fail "a free slot above the count is listed" }
  if (-not (Test-Path "$tmp\wt\slot-2") -or -not (Test-Path "$tmp\wt\slot-3")) { Fail "a worktree above the count was removed" }
  Reset-Gh

  # 5 a raised count brings a retired slot back, warm
  $null = Cap "-SlotCount 3"
  $p = Porc
  if ($p.Count -ne 3 -or $p[1] -ne "2`tfree" -or $p[2] -ne "3`tfree") { Fail "raised again: slots 2 and 3 are not free: $($p -join ' | ')" }
  if ((SlotE "-Take feat/c4").Out -notmatch "Slot 2 is yours") { Fail "raised again: slot 2 not taken" }
  if ((SlotE "-Take feat/c5").Out -notmatch "Slot 3 is yours") { Fail "raised again: slot 3 not taken" }
  foreach ($n in 1, 2, 3) { $null = Slot -Abandon $n }

  # 6 -Reap frees a retiring slot whose pull request has merged
  Reset-Gh; Prepare 3 feat/r3; Merged feat/r3 24 $tip
  $null = Cap "-SlotCount 1"
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne "Slot 3 is free (was feat/r3, PR #24), released automatically.") { Fail "reap of a retiring slot: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 3)) { Fail "reap of a retiring slot: the marker is still there" }
  Reset-Gh

  # 7 invalid values change nothing and say why
  $capBefore = Read-Cap
  foreach ($opt in "SlotCount", "AgentLimit") {
    $name = if ($opt -eq "SlotCount") { "-SlotCount" } else { "-AgentLimit" }
    foreach ($v in "0", "-1", "2.5", "x", "", "100") {
      $r = Cap "-$opt `"$v`""
      if ($r.Code -ne 1) { Fail "invalid $name '$v': exit $($r.Code) / $($r.Err)" }
      if ($r.Err.Trim() -cne "capacity: $name must be a whole number from 1 to 99, got `"$v`"") { Fail "invalid $name '$v': message: $($r.Err)" }
      if ($r.Out) { Fail "invalid $name '$v': printed $($r.Out)" }
      if ((Read-Cap) -cne $capBefore) { Fail "invalid $name '$v' changed capacity.json" }
    }
  }
  $r = Cap "-SlotCount 2 -AgentLimit x"
  if ($r.Code -eq 0) { Fail "a valid value with an invalid one was accepted" }
  if ((Read-Cap) -cne $capBefore) { Fail "a valid value given with an invalid one was written" }
  Remove-Item $C
  $r = Cap "-SlotCount 0"
  if ($r.Code -eq 0) { Fail "invalid value without a file was accepted" }
  if (Test-Path $C) { Fail "an invalid value created capacity.json" }

  # 8 -Clear
  $null = Cap "-SlotCount 3 -AgentLimit 3"
  $r = Cap "-Clear"
  if ($r.Out -ne "capacity: cleared (slots 3 -> 2, agents 3 -> 2)`n") { Fail "clear: $($r.Out)" }
  if (Test-Path $C) { Fail "clear left capacity.json" }
  $r = Cap "-Clear"
  if ($r.Out -ne "capacity: nothing to clear`n") { Fail "second clear: $($r.Out)" }
  $r = Cap "-Clear -SlotCount 2"
  if ($r.Code -eq 0) { Fail "-Clear with a value is not a usage error" }
  if ($r.Err -notmatch "(?m)^usage: ") { Fail "-Clear with a value: no usage line: $($r.Err)" }
  $r = Cap "-SlotCount 2 -SlotCount 3"
  if ($r.Code -eq 0) { Fail "a value given twice is not a usage error" }
  if (Test-Path $C) { Fail "a usage error wrote capacity.json" }

  # 9 and 10 precedence, shown and in porcelain
  $r = Cap "-Porcelain"
  if ($r.Out -ne "slots`t2`tconfig`t2`nagents`t2`tdefault`t2`n") { Fail "porcelain config/default: $($r.Out)" }
  $r = Cap "-Porcelain" @{ WORKER_SLOTS = "4" }
  if ($r.Out -ne "slots`t4`tWORKER_SLOTS`t2`nagents`t2`tdefault`t2`n") { Fail "porcelain WORKER_SLOTS: $($r.Out)" }
  $r = Cap "-Porcelain -SlotCount 3 -AgentLimit 3"
  if ($r.Out -ne "slots`t3`tlive`t2`nagents`t3`tlive`t2`n") { Fail "porcelain set: $($r.Out)" }
  if ((Lines (Cap "" @{ WORKER_SLOTS = "4" }).Out)[0] -ne "slots: 3 (live; config 2)") { Fail "live does not win over WORKER_SLOTS" }
  if ((Lines (SlotE "-Status -Porcelain" @{ WORKER_SLOTS = "4" }).Out).Count -ne 3) { Fail "-Status does not use the live count over WORKER_SLOTS" }
  $null = Cap "-Clear"
  [System.IO.File]::WriteAllText($CFG, $cfgBefore.Replace('"git": { "baseBranch": "main" },', '"git": { "baseBranch": "main" }, "parallel": { "maxAgents": 5 },'))
  if (-not [System.IO.File]::ReadAllText($CFG).Contains('"maxAgents": 5')) { Fail "the config copy has no maxAgents" }
  if ((Lines (Cap).Out)[1] -ne "agents: 5 (config)") { Fail "config does not win over the default: $((Cap).Out)" }
  if ((Lines (Cap "-Porcelain").Out)[1] -ne "agents`t5`tconfig`t5") { Fail "porcelain config agents" }
  $null = Cap "-AgentLimit 3"
  if ((Lines (Cap).Out)[1] -ne "agents: 3 (live; config 5)") { Fail "live does not win over the config: $((Cap).Out)" }
  if ((Lines (Cap "-Porcelain").Out)[1] -ne "agents`t3`tlive`t5") { Fail "porcelain live agents over config" }
  $null = Cap "-Clear"
  [System.IO.File]::WriteAllText($CFG, $cfgBefore)

  # 11 an unusable capacity.json is ignored with a note
  function Test-Unusable([string]$content, [string]$want, [string]$reason) {
    [System.IO.File]::WriteAllText($C, "$content`n")
    $r = Cap
    if ($r.Out -ne $want) { Fail "unusable capacity.json '$content': $($r.Out)" }
    if ($r.Err.Trim() -cne "slot: capacity.json: $reason; using the configuration") { Fail "unusable capacity.json '$content': note: $($r.Err)" }
  }
  Test-Unusable 'not json' "slots: 2 (config)`nagents: 2 (default)`n" "not valid JSON"
  Test-Unusable '[1, 2]' "slots: 2 (config)`nagents: 2 (default)`n" "not an object"
  Test-Unusable '{ "slots": "x" }' "slots: 2 (config)`nagents: 2 (default)`n" "slots is not a whole number from 1 to 99"
  Test-Unusable '{ "slots": 0, "maxAgents": 3 }' "slots: 2 (config)`nagents: 3 (live; config 2)`n" "slots is not a whole number from 1 to 99"
  [System.IO.File]::WriteAllText($C, "not json`n")
  $r = SlotE "-Take feat/u"
  if ($r.Out -notmatch "Slot 1 is yours") { Fail "a take with an unusable capacity.json failed: $($r.Err)" }
  if ((SlotE "-Status").Code -ne 0) { Fail "a status with an unusable capacity.json failed" }
  $null = Slot -Abandon 1
  Remove-Item $C

  # 12 nothing else changed: the marker keys, and no capacity.json without -Capacity
  Reset-Gh; Prepare 1 feat/m12
  $keys = ((([System.IO.File]::ReadAllText((Marker 1)) | ConvertFrom-Json).PSObject.Properties.Name) | Sort-Object) -join ","
  if ($keys -ne "branch,since,slot") { Fail "marker keys after capacity: $keys" }
  if (Test-Path $C) { Fail "a take wrote capacity.json" }
  Clear-Slots
  if ((SlotE "-SlotCount 3").Code -eq 0) { Fail "-SlotCount without -Capacity is not a usage error" }

  Write-Host "== reports"
  # -Report (iteration 23): the skill, the role, the step and the time of the last report in the slot's marker, and
  # -Status -Porcelain with the agent state (running, stalled, unknown) and the reported fields
  Reset-Gh
  $S1 = "$tmp\wt\.slots"
  function MText([int]$n) { [System.IO.File]::ReadAllText((Marker $n)) }
  function MGet([int]$n, [string]$key) {
    $v = (MText $n | ConvertFrom-Json).PSObject.Properties[$key]
    if (-not $v -or $null -eq $v.Value) { return "" }
    if ($v.Value -is [datetime]) { return $v.Value.ToString("s") }
    return [string]$v.Value
  }
  $stampRe = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
  $null = Slot -Take feat/r1 -Slot 1
  $tBranch = MGet 1 "branch"; $tSince = MGet 1 "since"

  # 1 a report writes the fields
  $r = SlotE "-Report tests -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 0) { Fail "report: exit $($r.Code): $($r.Err)" }
  if ($r.Out -or $r.Err) { Fail "report printed something: $($r.Out) / $($r.Err)" }
  $keys = ([regex]::Matches((MText 1), '"([a-z]+)":') | ForEach-Object { $_.Groups[1].Value }) -join ","
  if ($keys -ne "slot,branch,since,skill,role,step,reported") { Fail "report: marker keys: $(MText 1)" }
  if ($tBranch -ne "feat/r1" -or (MGet 1 "branch") -ne $tBranch -or (MGet 1 "since") -ne $tSince -or (MGet 1 "slot") -ne "1") { Fail "report: slot, branch or since changed: $(MText 1)" }
  if ("$(MGet 1 'skill')/$(MGet 1 'role')/$(MGet 1 'step')" -ne "next/implementer/tests") { Fail "report: skill, role, step: $(MText 1)" }
  $r1 = MGet 1 "reported"
  if ($r1 -notmatch $stampRe) { Fail "report: reported has not the form YYYY-MM-DDTHH:MM:SS: $r1" }
  $want = "{`n  `"slot`": 1,`n  `"branch`": `"feat/r1`",`n  `"since`": `"$tSince`",`n  `"skill`": `"next`",`n  `"role`": `"implementer`",`n  `"step`": `"tests`",`n  `"reported`": `"$r1`"`n}`n"
  if ((MText 1) -cne $want) { Fail "report: the marker text (the bytes of slot.sh): $(MText 1)" }
  if (Test-Path "$S1\slot-1.report.tmp") { Fail "report: the temporary file is left" }

  # 2 a second report replaces the step and the time and keeps since
  [System.IO.File]::WriteAllText((Marker 1), $want.Replace("`"reported`": `"$r1`"", "`"reported`": `"2020-01-01T00:00:00`""))
  $r = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 0) { Fail "second report: exit $($r.Code): $($r.Err)" }
  if ((MGet 1 "step") -ne "check") { Fail "second report: step: $(MText 1)" }
  if ((MGet 1 "reported") -eq "2020-01-01T00:00:00" -or (MGet 1 "reported") -notmatch $stampRe) { Fail "second report: reported: $(MText 1)" }
  if ((MGet 1 "since") -ne $tSince) { Fail "second report: since changed: $(MText 1)" }

  # 3 refusals change nothing
  $before = MText 1
  function Test-Refused([string]$want, [string]$arguments) {
    $r = SlotE $arguments
    if ($r.Code -ne 1) { Fail "refusal ($arguments): exit $($r.Code) / $($r.Err)" }
    if ($want -eq "usage") { if ($r.Err -notmatch "^usage: ") { Fail "refusal ($arguments): no usage line: $($r.Err)" } }
    elseif ($r.Err -cne "$want`n") { Fail "refusal ($arguments): message: $($r.Err)" }
    if ($r.Out) { Fail "refusal ($arguments): printed $($r.Out)" }
    if ((MText 1) -cne $before) { Fail "refusal ($arguments): the marker changed: $(MText 1)" }
    if ((Test-Path "$S1\slot-1.report.tmp") -or (Test-Path "$S1\slot-2.report.tmp")) { Fail "refusal ($arguments): a temporary file is left" }
    if (Test-Path (Marker 2)) { Fail "refusal ($arguments): a marker of slot 2 was written" }
  }
  $long41 = "a" * 41; $long40 = "b" * 40
  Test-Refused "report needs a slot number" "-Report tests -Skill next -Role implementer"
  Test-Refused "report needs a slot number" "-Report tests -Slot 0 -Skill next -Role implementer"
  Test-Refused "slot 2 is not in use" "-Report tests -Slot 2 -Skill next -Role implementer"
  foreach ($v in "", "a b", "a.b", $long41, "a`tb") {
    Test-Refused "report: the step must be 1 to 40 letters, digits or -, got `"$v`"" "-Report `"$v`" -Slot 1 -Skill next -Role implementer"
  }
  Test-Refused 'report: the skill must be 1 to 40 letters, digits or -, got ""' "-Report tests -Slot 1 -Role implementer"
  Test-Refused 'report: the role must be 1 to 40 letters, digits or -, got ""' "-Report tests -Slot 1 -Skill next"
  Test-Refused 'report: the skill must be 1 to 40 letters, digits or -, got "n/x"' "-Report tests -Slot 1 -Skill n/x -Role implementer"
  Test-Refused "usage" "-Report tests -Slot 1 -Skill next -Role implementer -Status"
  Test-Refused "usage" "-Status -Skill next"
  Test-Refused "usage" "-Role implementer -Slot 1"
  Test-Refused "usage" "-Report tests -Slot 1 -Skill next -Role implementer -Capacity"
  # -Report with no value is refused by PowerShell's parameter binding (its own message, exit code not 0)
  $r = SlotE "-Report"
  if ($r.Code -eq 0) { Fail "-Report without a value was accepted" }
  if ((MText 1) -cne $before) { Fail "-Report without a value changed the marker" }
  $good = MText 1
  [System.IO.File]::WriteAllText((Marker 1), "not json`n"); $before = MText 1
  Test-Refused "slot 1: the marker is not valid JSON" "-Report tests -Slot 1 -Skill next -Role implementer"
  [System.IO.File]::WriteAllText((Marker 1), $good)
  $r = SlotE "-Report $long40 -Slot 1 -Skill fix -Role fixer"
  if ($r.Code -ne 0 -or (MGet 1 "step") -ne $long40 -or "$(MGet 1 'skill')/$(MGet 1 'role')" -ne "fix/fixer") { Fail "a step of 40 characters was refused: $($r.Err)" }

  # 4 porcelain carries the fields
  $null = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
  $r1 = MGet 1 "reported"
  $p = Porc
  if ($p[0] -cne "1${T}busy${T}feat/r1${T}${tSince}${T}${T}running${T}next${T}implementer${T}check${T}$r1") { Fail "porcelain with a report: $($p -join ' | ')" }
  if (($p[0] -split $T).Count -ne 10) { Fail "porcelain: not ten fields: $($p[0])" }
  if ($p[1] -cne "2${T}free") { Fail "porcelain: the free line changed: $($p[1])" }

  # 5 running and stalled by the default threshold (30 minutes); 2026-11-05T11:30:00 is 1793878200 on the clock of the
  # scripts (local time read as UTC)
  function Hand([int]$n, [string]$step, [string]$reported, [string]$file = "") {
    if (-not $file) { $file = Marker $n }
    [System.IO.File]::WriteAllText($file, "{`n  `"slot`": $n,`n  `"branch`": `"feat/r$n`",`n  `"since`": `"2026-11-05T09:00:00`",`n  `"skill`": `"next`",`n  `"role`": `"implementer`",`n  `"step`": `"$step`",`n  `"reported`": `"$reported`"`n}`n")
  }
  # Agent <now> [n]: field 6 of slot n (1) in -Status -Porcelain with NIGHTMILL_NOW=<now>; the run in $script:last
  function Agent([long]$now, [int]$n = 1) {
    $script:last = SlotE "-Status -Porcelain" @{ NIGHTMILL_NOW = "$now" }
    foreach ($l in (Lines $script:last.Out)) { $f = $l -split $T; if ($f[0] -eq "$n") { return $f[5] } }
    return "<none>"
  }
  $B = [long]1793878200
  Hand 1 "check" "2026-11-05T11:30:00"
  if ((Agent ($B + 1800)) -ne "running") { Fail "1800 seconds after the report is not running" }
  if ((Agent ($B + 1801)) -ne "stalled") { Fail "1801 seconds after the report is not stalled" }
  if ((Agent ($B - 600)) -ne "running") { Fail "a report in the future is not running" }
  if ($last.Err) { Fail "the default threshold printed: $($last.Err)" }

  # 6 the threshold comes from the config
  function Set-Cfg([string]$v) { [System.IO.File]::WriteAllText($CFG, $cfgBefore.Replace('"slots": 2,', "`"slots`": 2, `"stalledAfterMinutes`": $v,")) }
  Set-Cfg "5"
  if (-not [System.IO.File]::ReadAllText($CFG).Contains('"stalledAfterMinutes": 5,')) { Fail "the config copy has no stalledAfterMinutes" }
  if ((Agent ($B + 300)) -ne "running") { Fail "threshold 5: 300 seconds is not running" }
  if ((Agent ($B + 301)) -ne "stalled") { Fail "threshold 5: 301 seconds is not stalled" }

  # 7 an unusable threshold falls back to 30
  $warn = "slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30"
  foreach ($v in "0", "-5", "2.5", "30.0", '"30"', '"x"', "true") {
    Set-Cfg $v
    $a = Agent ($B + 1800)
    if ($last.Code -ne 0) { Fail "threshold $v`: exit $($last.Code)" }
    if ($last.Err -cne "$warn`n") { Fail "threshold $v`: standard error: $($last.Err)" }
    if ($a -ne "running") { Fail "threshold $v`: 1800 seconds is not running" }
    if ((Agent ($B + 1801)) -ne "stalled") { Fail "threshold $v`: 1801 seconds is not stalled" }
  }
  function Test-Default([string]$what) {
    if ((Agent ($B + 1800)) -ne "running" -or $last.Err) { Fail "$what`: 1800 seconds: $($last.Err)" }
    if ((Agent ($B + 1801)) -ne "stalled" -or $last.Err) { Fail "$what`: 1801 seconds: $($last.Err)" }
  }
  Set-Cfg "null"; Test-Default "threshold null"
  [System.IO.File]::WriteAllText($CFG, $cfgBefore); Test-Default "no threshold key"
  # without worktrees the root is ../<checkout>-wt and there are two slots
  $noWt = [regex]::Replace($cfgBefore, '(?s),\s*"worktrees": \{.*?\r?\n  \}', '')
  if ($noWt.Contains("worktrees")) { Fail "the config copy still has worktrees" }
  [System.IO.File]::WriteAllText($CFG, $noWt)
  New-Item -ItemType Directory -Force "$tmp\work-wt\.slots" | Out-Null
  Hand 1 "check" "2026-11-05T11:30:00" "$tmp\work-wt\.slots\slot-1.json"
  Test-Default "no worktrees"
  Remove-Item -Recurse -Force "$tmp\work-wt"
  [System.IO.File]::WriteAllText($CFG, $cfgBefore)

  # 8 the step plays no part
  foreach ($stepName in "done", "stopped") {
    Hand 1 $stepName "2026-11-05T11:30:00"
    if ((Agent ($B + 1800)) -ne "running" -or (Agent ($B + 1801)) -ne "stalled") { Fail "the step $stepName changes the agent state" }
  }

  # 9 a marker of the previous version is busy with an unknown step
  [System.IO.File]::WriteAllText((Marker 1), "{`n  `"slot`": 1,`n  `"branch`": `"feat/r1`",`n  `"since`": `"2026-11-05T09:00:00`"`n}`n")
  $line = (Lines (SlotE "-Status -Porcelain" @{ NIGHTMILL_NOW = "$B" }).Out)[0]
  if ($line -cne "1${T}busy${T}feat/r1${T}2026-11-05T09:00:00${T}${T}unknown${T}${T}${T}${T}") { Fail "a three-key marker: $line" }
  Hand 1 "check" "yesterday"
  if ((Agent $B) -ne "unknown") { Fail "a reported that is not of the form is not unknown" }
  # a retiring slot (above the count) takes a report too
  [System.IO.File]::WriteAllText((Marker 3), "{`n  `"slot`": 3,`n  `"branch`": `"feat/r3`",`n  `"since`": `"2026-11-05T09:00:00`"`n}`n")
  $r = SlotE "-Report check -Slot 3 -Skill fix -Role fixer"
  if ($r.Code -ne 0) { Fail "report on a retiring slot: $($r.Err)" }
  $f = (Porc)[2] -split $T
  if ((@($f[0], $f[1], $f[4], $f[5], $f[6], $f[7], $f[8]) -join "|") -ne "3|busy|retiring|running|fix|fixer|check") { Fail "a retiring slot with a report: $($f -join '|')" }
  Remove-Item (Marker 3)

  # 11 the take and the human -Status are unchanged
  Hand 1 "code" "2026-11-05T11:30:00"
  $st = Slot -Status
  if ($st -notmatch "(?m)^slot 1  ready           busy: feat/r1 since 2026-11-05T09:00:00\r?$") { Fail "status without -Porcelain changed: $st" }

  # 12 -Status stays read-only
  Hand 2 "check" "2026-11-05T11:00:00"
  [System.IO.File]::WriteAllText($ghLog, ""); $m1 = MText 1; $m2 = MText 2
  $null = Porc; $null = Slot -Status
  if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "status with reports asked gh: $([System.IO.File]::ReadAllText($ghLog))" }
  if ((MText 1) -cne $m1 -or (MText 2) -cne $m2) { Fail "status changed a marker with a report" }
  Remove-Item (Marker 2)

  # 10 a reported slot is abandoned, reaped and released as before
  $r = SlotE "-Abandon 1"
  if ($r.Out.Trim() -ne "Slot 1 is free (was feat/r1; the local branch is kept, delete it yourself if unwanted).") { Fail "abandon of a reported slot: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 1)) { Fail "abandon left the marker of a reported slot" }
  Reset-Gh; Prepare 1 feat/rm
  $r = SlotE "-Report done -Slot 1 -Skill next -Role session"
  if ($r.Code -ne 0 -or (MGet 1 "step") -ne "done") { Fail "the report before the reap: $($r.Err)" }
  Merged feat/rm 31 $tip
  $r = SlotE "-Reap"
  if ($r.Out.Trim() -ne "Slot 1 is free (was feat/rm, PR #31), released automatically.") { Fail "reap of a reported slot: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 1)) { Fail "reap left the marker of a reported slot" }
  Reset-Gh; Prepare 1 feat/rl
  $null = SlotE "-Report done -Slot 1 -Skill fix -Role session"
  Merged feat/rl 32 $tip
  $r = SlotE "-Release 1"
  $last = (@($r.Out -split "`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -Last 1).Trim()
  if ($last -ne "Slot 1 is free (was feat/rl, PR #32).") { Fail "release of a reported slot: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 1)) { Fail "release left the marker of a reported slot" }
  $r = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 1 -or $r.Err -cne "slot 1 is not in use`n" -or (Test-Path (Marker 1))) { Fail "a report after the release brought the marker back: $($r.Err)" }
  Reset-Gh

  Write-Host "SMOKE OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

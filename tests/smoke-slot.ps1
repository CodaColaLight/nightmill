# tests/smoke-slot.ps1 - slot.ps1 against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon, and the automatic release of a slot whose pull
# request has merged (-Reap and the first step of every -Take), with -Release, against a fake gh, and the
# capacity command (-Capacity: the slot count and the agent limit changed during a session), the reports
# (-Report) and the claim of a take (iteration 34: a take claims its slot with a marker in the state "taking"
# before it fetches, switches or warms up; two takes get different slots; a failed take puts its slot back; a
# dead claim is freed only by -Abandon), and the interruption of a take (iteration 36: a stop after the claim puts the
# slot back and says so; a killed take leaves a dead claim).
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
# of branch TAB number TAB head commit, then (iteration 41) TAB createdAt TAB mergedAt TAB the closing issue numbers
# joined by commas, all three optional; --state merged only, an open query gives an empty list), logs every call to
# $env:GH_LOG and fails when GH_FAIL is set. With -q it prints the first number, as gh does for '.[0].number'. With
# --json it prints the requested fields among number, headRefOid, createdAt, mergedAt and closingIssuesReferences.
$bin = Join-Path $tmp "bin"; $fix = Join-Path $tmp "fix"
New-Item -ItemType Directory $bin, $fix | Out-Null
$ghLog = Join-Path $tmp "gh.log"
[System.IO.File]::WriteAllText((Join-Path $fix "merged.txt"), "")
[System.IO.File]::WriteAllText($ghLog, "")
[System.IO.File]::WriteAllText((Join-Path $bin "gh-fake.ps1"), @'
Add-Content -Path $env:GH_LOG -Value ($args -join " ")
if ($env:GH_FAIL) { [Console]::Error.WriteLine("HTTP 401: bad credentials"); exit 1 }
if ("$($args[0]) $($args[1])" -ne "pr list") { [Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')"); exit 1 }
$state = ""; $head = ""; $jq = ""; $fields = "number,headRefOid"
for ($i = 2; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    "--state" { $state = $args[$i + 1]; $i++ }
    "--head" { $head = $args[$i + 1]; $i++ }
    "--json" { $fields = $args[$i + 1]; $i++ }
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
$items = @($rows | ForEach-Object {
  $f = $_
  $parts = @()
  foreach ($fld in ($fields -split ",")) {
    switch ($fld) {
      "number" { $parts += '"number":' + $f[1] }
      "headRefOid" { $parts += '"headRefOid":"' + $f[2] + '"' }
      "createdAt" { $parts += '"createdAt":"' + $(if ($f.Count -gt 3) { $f[3] } else { "" }) + '"' }
      "mergedAt" { $parts += '"mergedAt":"' + $(if ($f.Count -gt 4) { $f[4] } else { "" }) + '"' }
      "closingIssuesReferences" {
        $refs = @()
        if ($f.Count -gt 5 -and $f[5]) { foreach ($k in ($f[5] -split ",")) { $refs += '{"id":"I_' + $k + '","number":' + $k + ',"repository":{"name":"widgets","owner":{"login":"acme"}},"url":"https://example.invalid/issues/' + $k + '"}' } }
        $parts += '"closingIssuesReferences":[' + ($refs -join ",") + ']'
      }
    }
  }
  '{' + ($parts -join ",") + '}'
})
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
  # iteration 48: the config comes from the base branch (origin/HEAD, then git.baseBranch)
  git remote set-head origin main

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
  # Pub-Cfg: commit the config file in the main checkout and push it to origin main, so the slot script reads it from the base
  function Pub-Cfg {
    $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try {
      & git -C $work diff --quiet -- .claude/nightmill.json 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) {
        & git -C $work add .claude/nightmill.json 2>&1 | Out-Null
        & git -C $work -c user.name=t -c user.email=t@example.invalid commit -qm config 2>&1 | Out-Null
        & git -C $work fetch -q origin main 2>&1 | Out-Null
        & git -C $work -c user.name=t -c user.email=t@example.invalid rebase -q origin/main 2>&1 | Out-Null
        & git -C $work push -q origin main 2>&1 | Out-Null
      }
    } finally { $ErrorActionPreference = $ea }
  }
  function Put-Cfg([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text); Pub-Cfg }
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
  Put-Cfg $CFG ($cfgBefore.Replace('"git": { "baseBranch": "main" },', '"git": { "baseBranch": "main" }, "parallel": { "maxAgents": 5 },'))
  if (-not [System.IO.File]::ReadAllText($CFG).Contains('"maxAgents": 5')) { Fail "the config copy has no maxAgents" }
  if ((Lines (Cap).Out)[1] -ne "agents: 5 (config)") { Fail "config does not win over the default: $((Cap).Out)" }
  if ((Lines (Cap "-Porcelain").Out)[1] -ne "agents`t5`tconfig`t5") { Fail "porcelain config agents" }
  $null = Cap "-AgentLimit 3"
  if ((Lines (Cap).Out)[1] -ne "agents: 3 (live; config 5)") { Fail "live does not win over the config: $((Cap).Out)" }
  if ((Lines (Cap "-Porcelain").Out)[1] -ne "agents`t3`tlive`t5") { Fail "porcelain live agents over config" }
  $null = Cap "-Clear"
  Put-Cfg $CFG ($cfgBefore)

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
  function Set-Cfg([string]$v) { Put-Cfg $CFG ($cfgBefore.Replace('"slots": 2,', "`"slots`": 2, `"stalledAfterMinutes`": $v,")) }
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
  Put-Cfg $CFG ($cfgBefore); Test-Default "no threshold key"
  # without worktrees the root is ../<checkout>-wt and there are two slots
  $noWt = [regex]::Replace($cfgBefore, '(?s),\s*"worktrees": \{.*?\r?\n  \}', '')
  if ($noWt.Contains("worktrees")) { Fail "the config copy still has worktrees" }
  Put-Cfg $CFG ($noWt)
  New-Item -ItemType Directory -Force "$tmp\work-wt\.slots" | Out-Null
  Hand 1 "check" "2026-11-05T11:30:00" "$tmp\work-wt\.slots\slot-1.json"
  Test-Default "no worktrees"
  Remove-Item -Recurse -Force "$tmp\work-wt"
  Put-Cfg $CFG ($cfgBefore)

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

  Write-Host "== claim (iteration 34)"
  # claim (iteration 34): a take claims its slot, a marker with "state": "taking" and its process id, before it fetches,
  # switches or warms up. Seven cases: (1) two takes at the same time get different slots, also when origin has moved;
  # (2) a take still working is shown as taken and kept; (3) a failed fetch, switch or warm-up puts the slot back and
  # frees the claim; (4) a dead claim is freed only by -Abandon; (5) markers across versions; (6) git itself sees the
  # claim at the fetch, the worktree add and the switch; (7) the publish is exclusive, in one shell and across the two.
  # A gate warm-up holds a take at its warm-up until <tmp>\go exists, and NIGHTMILL_CLAIM_GATE holds it at the publish.
  Reset-Gh
  $script:bgs = New-Object System.Collections.ArrayList
  $tf = $tmp -replace '\\', '/'
  $hereFwd = $here -replace '\\', '/'
  $origWarm = '"warmup": [ { "dir": "client", "command": "echo warm > warmed.txt", "lockfile": "client/lock.txt" } ],'
  if (-not $cfgBefore.Contains($origWarm)) { Fail "claim: the config has no warm-up line to replace" }
  $gateJson = "[ { `"command`": `"`$gi = 0; while (-not (Test-Path '$tf/go')) { `$gi++; if (`$gi -ge 1200) { throw 'no go' }; Start-Sleep -Milliseconds 100 }`" } ]"
  $exit7Json = '[ { "command": "cmd /c exit 7" } ]'
  function Stop-Claim { # opens both gates and waits for the background takes, so that none outlives the test
    [System.IO.File]::WriteAllText("$tmp\go", ""); [System.IO.File]::WriteAllText("$tmp\claim-go", "")
    foreach ($h in $script:bgs) { if (-not $h.P.WaitForExit(120000)) { try { $h.P.Kill() } catch { } } }
    $script:bgs.Clear()
  }
  function Fail($msg) { Stop-Claim; Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
  $claimRoot = ((Lines (SlotE "-Status").Out)[0]) -replace '^slots = [0-9]+  root = ', ''
  if (-not $claimRoot) { Fail "claim: no root in the status header" }
  function Write-Cfg([string]$warm) { Put-Cfg $CFG ($cfgBefore.Replace($origWarm, '"warmup": ' + $warm + ',')) }
  # Start-Proc <file> <arguments> [environment]: a child process with its output read in the background
  function Start-Proc([string]$file, [string]$arguments, [hashtable]$extraEnv = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = "$tmp\work"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $h = [pscustomobject]@{ P = $p; OutTask = $p.StandardOutput.ReadToEndAsync(); ErrTask = $p.StandardError.ReadToEndAsync() }
    [void]$script:bgs.Add($h)
    $h
  }
  function Start-Take([string]$arguments, [hashtable]$extraEnv = @{}) { Start-Proc $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$S`" $arguments" $extraEnv }
  function Wait-Take($h) {
    $h.P.WaitForExit()
    [pscustomobject]@{ Out = ($h.OutTask.Result -replace "`r`n", "`n"); Err = ($h.ErrTask.Result -replace "`r`n", "`n"); Code = $h.P.ExitCode }
  }
  function Test-BgAlive { foreach ($h in $script:bgs) { if (-not $h.P.HasExited) { return $true } }; return $false }
  function Get-Porc9([int]$n, [hashtable]$e = @{}) {
    foreach ($l in (Lines (SlotE "-Status -Porcelain" $e).Out)) { $f = $l -split $T; if ($f[0] -eq "$n") { return $f[8] } }
    return "<none>"
  }
  function Wait-For([int]$n, [string]$state) { # until field 9 of slot n in -Status -Porcelain is <state> (60 s at most)
    $end = (Get-Date).AddSeconds(60)
    while ($true) {
      $got = Get-Porc9 $n
      if ($got -eq $state) { return }
      if ((Get-Date) -gt $end) { Fail "Wait-For: slot $n did not show the step '$state' within 60 s (field 9: '$got'): $((SlotE '-Status -Porcelain').Out)" }
      if (-not (Test-BgAlive)) { Fail "Wait-For: every background take ended and slot $n never showed the step '$state' (field 9: '$got')" }
      Start-Sleep -Milliseconds 100
    }
  }
  function Get-ClaimFiles([int]$n) { @(Get-ChildItem -LiteralPath $S1 -Filter "slot-$n.claim.*.tmp" -File -ErrorAction SilentlyContinue) }
  function Wait-Claims([int]$n, [int]$count) { # until .slots holds that many slot-<n>.claim.*.tmp files (60 s at most)
    $end = (Get-Date).AddSeconds(60)
    while ($true) {
      $c = (Get-ClaimFiles $n).Count
      if ($c -ge $count) { return }
      if ((Get-Date) -gt $end) { Fail "Wait-Claims: slot $n has $c claim files, not $count, after 60 s" }
      if (-not (Test-BgAlive)) { Fail "Wait-Claims: every background take ended with $c claim files of slot $n, not $count" }
      Start-Sleep -Milliseconds 100
    }
  }
  # Taking-Text <slot> <branch> <since> [pid]: the text of a taking marker (without the pid line when no pid is given)
  function Taking-Text([int]$n, [string]$branch, [string]$since, [string]$procId = "") {
    if ($procId) { return "{`n  `"slot`": $n,`n  `"branch`": `"$branch`",`n  `"since`": `"$since`",`n  `"state`": `"taking`",`n  `"pid`": $procId`n}`n" }
    return "{`n  `"slot`": $n,`n  `"branch`": `"$branch`",`n  `"since`": `"$since`",`n  `"state`": `"taking`"`n}`n"
  }
  function Write-Text([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text) }
  function Get-Keys([int]$n) { ([regex]::Matches((MText $n), '"([a-z]+)":') | ForEach-Object { $_.Groups[1].Value }) -join "," }
  function Test-Finished([int]$n) {
    $t = MText $n
    return ((((($t | ConvertFrom-Json).PSObject.Properties.Name) | Sort-Object) -join ",") -ceq "branch,since,slot") -and -not $t.Contains('"state"') -and -not $t.Contains('"pid"')
  }
  function Get-Leftovers([int]$n) { @(Get-ChildItem -LiteralPath $S1 -Name -ErrorAction SilentlyContinue | Where-Object { $_ -match "^slot-$n\.(claim\..*\.tmp|left\..*\.tmp|take\.tmp)$" }) }
  function Get-Head([int]$n) { ([string](git -C "$tmp\wt\slot-$n" rev-parse HEAD)).Trim() }
  function Get-Current([int]$n) { $x = git -C "$tmp\wt\slot-$n" branch --show-current; if ($null -eq $x) { "" } else { ([string]$x).Trim() } }
  function Get-Ref([string]$b) { $x = git -C $work rev-parse --verify -q "refs/heads/$b"; if ($LASTEXITCODE -eq 0) { ([string]$x).Trim() } else { "" } }
  function Gq { $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & git @args 2>&1 | Out-Null } finally { $ErrorActionPreference = $ea } }
  function Ensure-Other { if (-not (Test-Path "$tmp\other\.git")) { Gq clone -q -b main "$tmp\origin.git" "$tmp\other" } }
  function New-Branch([string]$b, [string]$file) { # a branch with one commit that adds the file, checked out nowhere
    Ensure-Other
    Gq -C "$tmp\other" fetch -q origin
    Gq -C "$tmp\other" switch -q -C $b origin/main
    [System.IO.File]::WriteAllText("$tmp\other\$file", "$b`n")
    Gq -C "$tmp\other" add -A
    Gq -C "$tmp\other" -c user.name=t -c user.email=t@example.invalid commit -qm $b
    Gq -C "$tmp\other" push -q -f origin $b
    Gq -C $work fetch -q origin "+${b}:refs/heads/$b"
  }
  function Test-EndsWithLine([string]$err, [string]$line) {
    $parts = $err -split "`n"
    return ($parts.Count -ge 2 -and $parts[-1] -eq "" -and $parts[-2] -ceq $line)
  }
  function Test-EndsWithLines([string]$err, [string[]]$lines) {
    $parts = $err -split "`n"
    if ($parts.Count -lt $lines.Count + 1 -or $parts[-1] -ne "") { return $false }
    for ($k = 0; $k -lt $lines.Count; $k++) { if ($parts[$parts.Count - 1 - $lines.Count + $k] -cne $lines[$k]) { return $false } }
    return $true
  }
  function Claim-Reset { # every slot free and detached at origin/main, the original config, both gates open, nothing left over
    Stop-Claim
    Remove-Item "$tmp\go", "$tmp\claim-go", "$tmp\barrier", "$S1\capacity.json" -Force -ErrorAction SilentlyContinue
    Put-Cfg $CFG ($cfgBefore)
    Gq -C $work config --unset remote.origin.uploadpack
    Gq -C $work config --unset core.hooksPath
    Gq -C $work remote set-url origin "$tmp\origin.git"
    foreach ($n in 1, 2, 3, 4) {
      $d = "$tmp\wt\slot-$n"
      if ($n -eq 4 -and (Test-Path $d)) {
        Gq -C $work worktree remove --force $d
        if (Test-Path $d) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue; Gq -C $work worktree prune }
      } elseif (Test-Path $d) {
        Gq -C $d switch -q -f --detach origin/main
        Gq -C $d clean -fdq
      }
      Remove-Item (Marker $n) -Force -ErrorAction SilentlyContinue
      foreach ($f in @(Get-Leftovers $n)) { Remove-Item "$S1\$f" -Force -ErrorAction SilentlyContinue }
      if (Test-Path -LiteralPath "$S1\slot-$n.warmup-1" -PathType Container) { Remove-Item -Recurse -Force "$S1\slot-$n.warmup-1" }
    }
    Reset-Gh
  }
  function Test-Same([string]$want, [int]$n, [string]$what) { if ((MText $n) -cne $want) { Fail "$what`: the marker changed: $(MText $n)" } }
  # Test-RefusedClaim <n> <expected marker text> <expected standard error line> <arguments>: exit 1, that line only, marker unchanged
  function Test-RefusedClaim([int]$n, [string]$want, [string]$line, [string]$arguments) {
    $r = SlotE $arguments
    if ($r.Code -ne 1) { Fail "claim refusal ($arguments): exit $($r.Code), wanted 1: $($r.Out) / $($r.Err)" }
    if ($r.Err -cne "$line`n") { Fail "claim refusal ($arguments): standard error [$($r.Err)], wanted [$line]" }
    if ($r.Out) { Fail "claim refusal ($arguments): printed $($r.Out)" }
    Test-Same $want $n "claim refusal ($arguments)"
  }

  # 1 two takes at the same time get different slots, also when origin has moved
  function Claim-Case1 {
    Claim-Reset
    Write-Cfg $gateJson
    Ensure-Other
    [System.IO.File]::WriteAllText("$tmp\other\moved.txt", "moved $(Get-Random)`n")
    Gq -C "$tmp\other" add -A
    Gq -C "$tmp\other" -c user.name=t -c user.email=t@example.invalid commit -qm "origin moves"
    Gq -C "$tmp\other" push -q origin main
    $movedCommit = ([string](git -C "$tmp\other" rev-parse HEAD)).Trim()
    if (([string](git -C $work rev-parse origin/main)).Trim() -eq $movedCommit) { Fail "claim 1: setup: origin/main of the main checkout is already at the moved commit" }
    New-Item -ItemType Directory -Force "$tmp\hooks" | Out-Null
    $barrierText = @'
echo x >> '@TMP@/barrier'; i=0; while [ "$(wc -l < '@TMP@/barrier')" -lt 2 ]; do i=$((i+1)); [ $i -lt 300 ] || break; sleep 0.1; done; exec git upload-pack "$@"
'@
    [System.IO.File]::WriteAllText("$tmp\hooks\upload-pack-barrier", $barrierText.Replace('@TMP@', $tf) + "`n")
    git -C $work config remote.origin.uploadpack "sh '$tf/hooks/upload-pack-barrier'"
    $h1 = Start-Take "-Take feat/p1"
    $h2 = Start-Take "-Take feat/p2"
    Wait-For 1 "taking"
    Wait-For 2 "taking"
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $r1 = Wait-Take $h1; $r2 = Wait-Take $h2
    $script:bgs.Clear()
    if (-not (Test-Path "$tmp\barrier") -or @(Get-Content "$tmp\barrier").Count -lt 2) { Fail "claim 1: the two fetches did not overlap" }
    if ($r1.Code -ne 0) { Fail "claim 1: take feat/p1 exited $($r1.Code): $($r1.Out) / $($r1.Err)" }
    if ($r2.Code -ne 0) { Fail "claim 1: take feat/p2 exited $($r2.Code): $($r2.Out) / $($r2.Err)" }
    $n1 = [regex]::Match($r1.Out, '(?m)^Slot ([0-9]+) is yours').Groups[1].Value
    $n2 = [regex]::Match($r2.Out, '(?m)^Slot ([0-9]+) is yours').Groups[1].Value
    if (("$n1,$n2" -ne "1,2") -and ("$n1,$n2" -ne "2,1")) { Fail "claim 1: the takes were given slots '$n1' and '$n2', not one each of 1 and 2: $($r1.Out) / $($r2.Out)" }
    foreach ($pair in @(@($n1, "feat/p1"), @($n2, "feat/p2"))) {
      $n = [int]$pair[0]; $b = $pair[1]
      if ((Get-Current $n) -ne $b) { Fail "claim 1: slot $n is on '$(Get-Current $n)', not on $b" }
      if ((MGet $n "branch") -ne $b) { Fail "claim 1: the marker of slot $n names '$(MGet $n 'branch')', not $b" }
      git -C $work merge-base --is-ancestor $movedCommit $b
      if ($LASTEXITCODE -ne 0) { Fail "claim 1: $b does not start at the moved origin commit $movedCommit" }
      $keys = ((((MText $n) | ConvertFrom-Json).PSObject.Properties.Name) | Sort-Object) -join ","
      if ($keys -ne "branch,since,slot") { Fail "claim 1: the marker of slot $n is not a finished marker: $(MText $n)" }
    }
    Gq -C $work config --unset remote.origin.uploadpack
    Remove-Item "$tmp\go", "$tmp\barrier" -Force -ErrorAction SilentlyContinue
    $null = Slot -Abandon 1; $null = Slot -Abandon 2
  }

  # 2 a take still working is shown as taken and kept
  function Claim-Case2 {
    Claim-Reset
    Write-Cfg $gateJson
    $h = Start-Take "-Take feat/s2 -Slot 2"
    Wait-For 2 "taking"
    $procId = $h.P.Id
    $since = MGet 2 "since"
    $want = Taking-Text 2 "feat/s2" $since "$procId"
    Test-Same $want 2 "claim 2: the marker of a take that is working"
    $takingCopy = MText 2
    $st = (SlotE "-Status").Out
    if (-not (@(Lines $st) -ccontains "slot 2  ready           taking: feat/s2 since $since (process $procId)")) { Fail "claim 2: status does not show slot 2 as taking: $st" }
    if ($st -match "(?m)^slot 2 .*free") { Fail "claim 2: status shows slot 2 free: $st" }
    $p = Porc
    if ($p[1] -cne "2${T}busy${T}feat/s2${T}${since}${T}${T}unknown${T}${T}${T}taking${T}") { Fail "claim 2: porcelain line of slot 2: $($p -join ' | ')" }
    Test-Same $want 2 "claim 2 after the status"
    $r = SlotE "-Take feat/s1 -SkipWarmup"
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 1 is yours") { Fail "claim 2: a second take did not get slot 1 (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $null = Slot -Abandon 1
    Test-Same $want 2 "claim 2 after a second take"
    $r = SlotE "-Take feat/s9 -Slot 2 -SkipWarmup"
    if ($r.Code -ne 1 -or -not (Test-EndsWithLine $r.Err "slot 2 is busy")) { Fail "claim 2: a take on slot 2 was not refused as busy (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Test-Same $want 2 "claim 2 after -Take -Slot 2"
    $live = "slot 2 is being taken (process $procId is still running); wait for the take to end"
    Reset-Gh
    Test-RefusedClaim 2 $want $live "-Release 2"
    if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "claim 2: -Release asked gh about a slot that is being taken: $([System.IO.File]::ReadAllText($ghLog))" }
    Test-RefusedClaim 2 $want $live "-Abandon 2"
    Test-RefusedClaim 2 $want $live "-Report check -Slot 2 -Skill next -Role implementer"
    Reset-Gh; Merged feat/s2 41 (([string](git -C $work rev-parse origin/main)).Trim())
    $r = SlotE "-Reap"
    if ($r.Code -ne 0 -or $r.Out.Trim() -ne "No slot freed.") { Fail "claim 2: -Reap of a slot that is being taken (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "claim 2: -Reap asked gh about a slot that is being taken: $([System.IO.File]::ReadAllText($ghLog))" }
    Test-Same $want 2 "claim 2 after -Reap"
    Reset-Gh
    $null = SlotE "-Capacity -SlotCount 1"
    $st = (SlotE "-Status").Out
    if ($st -notmatch ("(?m)^slot 2  ready           taking: feat/s2 since " + [regex]::Escape($since) + " \(process $procId\) \(retiring\)")) { Fail "claim 2: a retiring slot that is being taken: $st" }
    if ((((Porc)[1]) -split $T)[4] -ne "retiring") { Fail "claim 2: porcelain field 5 of the retiring slot: $((Porc) -join ' | ')" }
    Test-Same $want 2 "claim 2 after -Capacity"
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $r = Wait-Take $h
    $script:bgs.Clear()
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "claim 2: the take did not finish (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if (((((MText 2) | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object) -join ",") -ne "branch,since,slot" -or (MText 2).Contains('"state"') -or (MText 2).Contains('"pid"')) { Fail "claim 2: the finished marker has other keys: $(MText 2)" }
    if ((MGet 2 "branch") -ne "feat/s2") { Fail "claim 2: the finished marker names '$(MGet 2 'branch')'" }
    $f = ((Porc)[1] -split $T)
    if ((@($f[0], $f[1], $f[2], $f[4]) -join "|") -ne "2|busy|feat/s2|retiring") { Fail "claim 2: slot 2 after the take is not a retiring busy slot: $((Porc) -join ' | ')" }
    $null = SlotE "-Capacity -Clear"
    Reset-Gh
    $null = Slot -Abandon 2
    Remove-Item "$tmp\go" -Force -ErrorAction SilentlyContinue
  }

  # 3 a failed step puts the slot back and frees the claim
  function Test-Restored($r, [int]$n, [int]$cnt, [string]$want, [string]$where = "ready") {
    if ($r.Code -ne 1) { Fail "claim 3 ($want): exit $($r.Code), wanted 1: $($r.Out) / $($r.Err)" }
    if (-not (Test-EndsWithLine $r.Err $want)) { Fail "claim 3: standard error does not end with [$want]: $($r.Err)" }
    if (Test-Path (Marker $n)) { Fail "claim 3 ($want): the marker of slot $n is still there: $(MText $n)" }
    if ((Get-Leftovers $n).Count -ne 0) { Fail "claim 3 ($want): temporary files are left: $((Get-Leftovers $n) -join ', ')" }
    $e = @{ WORKER_SLOTS = "$cnt" }
    $st = (SlotE "-Status" $e).Out
    if (-not (@(Lines $st) -ccontains ("slot {0}  {1,-15} free" -f $n, $where))) { Fail "claim 3 ($want): status does not show slot $n free: $st" }
    $line = @(Lines (SlotE "-Status -Porcelain" $e).Out | Where-Object { ($_ -split $T)[0] -eq "$n" })
    if ($line.Count -ne 1 -or $line[0] -cne "$n${T}free") { Fail "claim 3 ($want): porcelain does not show slot $n free: $($line -join ' | ')" }
  }
  function Claim-Case3 {
    Claim-Reset
    $dir = "$claimRoot\slot-1"
    $X = Get-Head 1
    if (Get-Current 1) { Fail "claim 3: setup: slot 1 is not detached" }
    $left2 = "slot 1 has uncommitted files: $dir (commit, stash or discard them first)"
    # warm-up, existing slot, new branch
    Write-Cfg $exit7Json
    $r = SlotE "-Take feat/f1"
    Test-Restored $r 1 2 "warm-up 1 failed (exit 7); slot 1 is free again"
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed warm-up (branch '$(Get-Current 1)', head $(Get-Head 1))" }
    if (Get-Ref "feat/f1") { Fail "claim 3: the new branch feat/f1 was left behind" }
    # warm-up, existing branch
    New-Branch "feat/f2" "f2.txt"
    $Y = Get-Ref "feat/f2"
    $r = SlotE "-Take feat/f2 -Slot 1"
    Test-Restored $r 1 2 "warm-up 1 failed (exit 7); slot 1 is free again"
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed warm-up on an existing branch" }
    if ((Get-Ref "feat/f2") -ne $Y) { Fail "claim 3: feat/f2 is not at $Y any more: $(Get-Ref 'feat/f2')" }
    # warm-up, slot not created yet
    if (Test-Path "$tmp\wt\slot-4") { Fail "claim 3: setup: slot-4 exists" }
    $r = SlotE "-Take feat/f4 -Slot 4" @{ WORKER_SLOTS = "4" }
    Test-Restored $r 4 4 "warm-up 1 failed (exit 7); slot 4 is free again" "not created yet"
    if (Test-Path "$tmp\wt\slot-4") { Fail "claim 3: the directory slot-4 is left" }
    if ((git -C $work worktree list) -match "slot-4") { Fail "claim 3: git still lists the worktree slot-4" }
    if (Get-Ref "feat/f4") { Fail "claim 3: the branch feat/f4 was left behind" }
    # switch
    Put-Cfg $CFG ($cfgBefore)
    $r = SlotE "-Take feat/f5 -Slot 1 -Base origin/nope"
    Test-Restored $r 1 2 "git switch failed (exit 128); slot 1 is free again"
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed switch" }
    if (Get-Ref "feat/f5") { Fail "claim 3: the branch feat/f5 was left behind" }
    # switch, step 5: the branch exists and is checked out in slot 2, so step 4 passes and the real git switch fails
    if (-not (Test-Path "$tmp\wt\slot-2")) { Fail "claim 3: setup: slot-2 does not exist" }
    New-Branch "feat/f12" "f12.txt"
    $Y = Get-Ref "feat/f12"
    Gq -C "$tmp\wt\slot-2" switch -q feat/f12
    $r = SlotE "-Take feat/f12 -Slot 1"
    Test-Restored $r 1 2 "git switch failed (exit 128); slot 1 is free again"
    if ($r.Err -notmatch "already (used by worktree|checked out) at") { Fail "claim 3: the take did not reach the real git switch (no git refusal on standard error): $($r.Err)" }
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed git switch (branch '$(Get-Current 1)', head $(Get-Head 1))" }
    if ((Get-Ref "feat/f12") -ne $Y) { Fail "claim 3: feat/f12 is not at $Y any more: $(Get-Ref 'feat/f12')" }
    if ((Get-Current 2) -ne "feat/f12") { Fail "claim 3: slot 2 left feat/f12 (branch '$(Get-Current 2)')" }
    Gq -C "$tmp\wt\slot-2" switch -q --detach origin/main
    Gq -C $work branch -D feat/f12
    # fetch
    Gq -C $work remote set-url origin "$tmp\no-such.git"
    $r = SlotE "-Take feat/f6"
    Test-Restored $r 1 2 "git fetch failed (exit 128); slot 1 is free again"
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed fetch" }
    if ([regex]::Matches($r.Err, "Could not read from remote repository").Count -ne 3) { Fail "claim 3: git's fetch error is not on standard error three times (three attempts): $($r.Err)" }
    Gq -C $work remote set-url origin "$tmp\origin.git"
    # the stamp cannot be written
    Remove-Item -Recurse -Force "$S1\slot-1.warmup-1" -ErrorAction SilentlyContinue
    New-Item -ItemType Directory "$S1\slot-1.warmup-1" | Out-Null
    $r = SlotE "-Take feat/f11 -Slot 1"
    Test-Restored $r 1 2 "warm-up 1 failed (exit 1); slot 1 is free again"
    if ((Get-Current 1) -or (Get-Head 1) -ne $X) { Fail "claim 3: slot 1 is not detached at $X after the failed stamp write" }
    if (Get-Ref "feat/f11") { Fail "claim 3: the branch feat/f11 was left behind" }
    Remove-Item -Recurse -Force "$S1\slot-1.warmup-1"
    # uncommitted files
    [System.IO.File]::WriteAllText("$tmp\wt\slot-1\untracked.txt", "x`n")
    $r = SlotE "-Take feat/f7 -Slot 1"
    if ($r.Code -ne 1 -or -not (Test-EndsWithLine $r.Err "slot 1 has uncommitted files; deal with them first: $dir")) { Fail "claim 3: a take on a slot with uncommitted files (exit $($r.Code)): $($r.Err)" }
    if (Test-Path (Marker 1)) { Fail "claim 3: a take refused for uncommitted files left a marker: $(MText 1)" }
    if ((Get-Leftovers 1).Count -ne 0) { Fail "claim 3: a refused take left temporary files: $((Get-Leftovers 1) -join ', ')" }
    Remove-Item "$tmp\wt\slot-1\untracked.txt"
    # a changed file keeps a dead claim
    New-Branch "feat/f8" "f8.txt"
    Write-Cfg '[ { "command": "Set-Content f8.txt changed; cmd /c exit 7" } ]'
    $r = SlotE "-Take feat/f8 -Slot 1"
    if ($r.Code -ne 1) { Fail "claim 3: a failed warm-up that changed a file exited $($r.Code): $($r.Out) / $($r.Err)" }
    if (-not (Test-EndsWithLines $r.Err @($left2, "warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with -Abandon 1"))) { Fail "claim 3: the last two lines of standard error: $($r.Err)" }
    if ((Get-Current 1) -ne "feat/f8" -or ((Get-Content "$tmp\wt\slot-1\f8.txt") -join "") -ne "changed") { Fail "claim 3: slot 1 was switched back or lost the changed file (branch '$(Get-Current 1)')" }
    $since = MGet 1 "since"
    $want = Taking-Text 1 "feat/f8" $since
    Test-Same $want 1 "claim 3: the claim left behind"
    if ((Get-Leftovers 1).Count -ne 0) { Fail "claim 3: temporary files are left: $((Get-Leftovers 1) -join ', ')" }
    if ((Get-Porc9 1) -ne "take-died") { Fail "claim 3: porcelain field 9 of the claim left behind is '$(Get-Porc9 1)'" }
    $st = (SlotE "-Status").Out
    if (-not $st.Contains("slot 1  ready           taking: feat/f8 since $since (no process recorded; free it with -Abandon 1)")) { Fail "claim 3: status of the claim left behind: $st" }
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 1 -or $r.Err -notmatch "slot 1 has uncommitted files:") { Fail "claim 3: -Abandon on a changed file (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Test-Same $want 1 "claim 3: -Abandon on a changed file"
    git -C "$tmp\wt\slot-1" checkout -q -- f8.txt
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 1 is free (was feat/f8, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "claim 3: -Abandon after the file was restored (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Gq -C $work branch -D feat/f8
    # an untracked file keeps a dead claim
    Write-Cfg '[ { "command": "Set-Content junk.txt x; cmd /c exit 7" } ]'
    $r = SlotE "-Take feat/f9 -Slot 1"
    if ($r.Code -ne 1) { Fail "claim 3: a failed warm-up that created a file exited $($r.Code): $($r.Out) / $($r.Err)" }
    if (-not (Test-EndsWithLines $r.Err @($left2, "warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with -Abandon 1"))) { Fail "claim 3: the last two lines of standard error (untracked file): $($r.Err)" }
    if ((Get-Current 1) -ne "feat/f9" -or -not (Test-Path "$tmp\wt\slot-1\junk.txt")) { Fail "claim 3: slot 1 was switched back or lost junk.txt (branch '$(Get-Current 1)')" }
    $since = MGet 1 "since"
    Test-Same (Taking-Text 1 "feat/f9" $since) 1 "claim 3: the claim left behind (untracked file)"
    if ((Get-Porc9 1) -ne "take-died") { Fail "claim 3: porcelain field 9 of the claim left behind (untracked file) is '$(Get-Porc9 1)'" }
    $r = SlotE "-Take feat/f10 -Slot 1 -SkipWarmup"
    if ($r.Code -ne 1 -or -not (Test-EndsWithLine $r.Err "slot 1 is busy")) { Fail "claim 3: a take on the claim left behind (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 1 -or $r.Err -notmatch "slot 1 has uncommitted files:") { Fail "claim 3: -Abandon with junk.txt (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Remove-Item "$tmp\wt\slot-1\junk.txt"
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 1 is free (was feat/f9, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "claim 3: -Abandon after junk.txt was removed (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if ((Get-Current 1) -or (git -C "$tmp\wt\slot-1" status --porcelain)) { Fail "claim 3: slot 1 is not detached and clean after -Abandon" }
    Gq -C $work branch -D feat/f9
    Put-Cfg $CFG ($cfgBefore)
  }

  # 4 a dead claim is recognised and freed only by -Abandon, without losing work
  function Claim-Case4 {
    Claim-Reset
    $dp = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-Command", "exit" -PassThru -WindowStyle Hidden
    $dp.WaitForExit()
    $dead = $dp.Id
    $live = $PID
    $r = SlotE "-Take feat/d1 -Slot 1 -SkipWarmup"
    if ($r.Code -ne 0) { Fail "claim 4: setup: take feat/d1 failed: $($r.Out) / $($r.Err)" }
    $since = MGet 1 "since"
    $want = Taking-Text 1 "feat/d1" $since "$dead"
    Write-Text (Marker 1) $want
    $st = (SlotE "-Status").Out
    if (-not $st.Contains("taking: feat/d1 since $since (process $dead has ended; free it with -Abandon 1)")) { Fail "claim 4: status of a dead claim: $st" }
    if ((Get-Porc9 1) -ne "take-died") { Fail "claim 4: porcelain field 9 of a dead claim is '$(Get-Porc9 1)'" }
    if ((((Porc)[0]) -split $T)[5] -ne "unknown") { Fail "claim 4: porcelain field 6 of a dead claim: $((Porc) -join ' | ')" }
    $r = SlotE "-Take feat/d2 -SkipWarmup"
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "claim 4: a take did not get slot 2 beside a dead claim (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $null = Slot -Abandon 2
    $dline = "slot 1 has a take that did not finish (process $dead has ended); free it with -Abandon 1"
    Test-RefusedClaim 1 $want $dline "-Release 1"
    Test-RefusedClaim 1 $want $dline "-Report check -Slot 1 -Skill next -Role implementer"
    $tip = Get-Ref "feat/d1"
    Reset-Gh; Merged feat/d1 42 $tip
    $r = SlotE "-Reap"
    if ($r.Code -ne 0 -or $r.Out.Trim() -ne "No slot freed.") { Fail "claim 4: -Reap of a dead claim (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if ([System.IO.File]::ReadAllText($ghLog).Length -ne 0) { Fail "claim 4: -Reap asked gh about a dead claim: $([System.IO.File]::ReadAllText($ghLog))" }
    Test-Same $want 1 "claim 4 after -Reap"
    Reset-Gh
    [System.IO.File]::WriteAllText("$tmp\wt\slot-1\untracked.txt", "x`n")
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 1 -or $r.Err -notmatch "slot 1 has uncommitted files:") { Fail "claim 4: -Abandon with an untracked file (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Test-Same $want 1 "claim 4: -Abandon with an untracked file"
    if (-not (Test-Path "$tmp\wt\slot-1\untracked.txt")) { Fail "claim 4: -Abandon removed the untracked file" }
    Remove-Item "$tmp\wt\slot-1\untracked.txt"
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 1 is free (was feat/d1, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "claim 4: -Abandon of a dead claim (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if (Test-Path (Marker 1)) { Fail "claim 4: the marker of the dead claim is still there" }
    if ((Get-Head 1) -ne ([string](git -C $work rev-parse origin/main)).Trim() -or (Get-Current 1)) { Fail "claim 4: slot 1 is not detached at origin/main after -Abandon" }
    if ((Get-Ref "feat/d1") -ne $tip) { Fail "claim 4: feat/d1 is not at its tip any more: $(Get-Ref 'feat/d1')" }
    # a live pid, then no pid, then a pid out of range
    $want = Taking-Text 1 "feat/d1" $since "$live"
    Write-Text (Marker 1) $want
    Test-RefusedClaim 1 $want "slot 1 is being taken (process $live is still running); wait for the take to end" "-Abandon 1"
    $nline = "slot 1 has a take that did not finish (no process recorded); free it with -Abandon 1"
    foreach ($v in "", "2147483648", "0") {
      $want = Taking-Text 1 "feat/d1" $since $v
      Write-Text (Marker 1) $want
      if ((Get-Porc9 1) -ne "take-died") { Fail "claim 4: porcelain field 9 of a claim with pid '$v' is '$(Get-Porc9 1)'" }
      if (-not (SlotE "-Status").Out.Contains("taking: feat/d1 since $since (no process recorded; free it with -Abandon 1)")) { Fail "claim 4: status of a claim with pid '$v'" }
      Test-RefusedClaim 1 $want $nline "-Release 1"
    }
    Remove-Item (Marker 1)
    # a dead claim on a slot that was never created
    if (Test-Path "$tmp\wt\slot-4") { Fail "claim 4: setup: slot-4 exists" }
    Write-Text (Marker 4) (Taking-Text 4 "feat/d4" $since "$dead")
    $r = SlotE "-Abandon 4" @{ WORKER_SLOTS = "4" }
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 4 is free (was feat/d4, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "claim 4: -Abandon of a dead claim without a directory (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if (Test-Path (Marker 4)) { Fail "claim 4: the marker of slot 4 is still there" }
  }

  # 5 markers across versions
  function Claim-Case5 {
    Claim-Reset
    # the taking marker of a take that works, read the way the previous version reads it
    Write-Cfg $gateJson
    $h = Start-Take "-Take feat/s2 -Slot 2"
    Wait-For 2 "taking"
    $m = (MText 2) | ConvertFrom-Json
    if ([string]$m.slot -ne "2" -or [string]$m.branch -ne "feat/s2" -or -not (MGet 2 "since")) { Fail "claim 5: the taking marker is not read by key as slot 2, feat/s2 and a since: $(MText 2)" }
    if ((((Porc)[1]) -split $T)[1] -ne "busy") { Fail "claim 5: the taking marker is not a busy line: $((Porc) -join ' | ')" }
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $r = Wait-Take $h; $script:bgs.Clear()
    if ($r.Code -ne 0) { Fail "claim 5: the take did not finish (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Claim-Reset
    # markers of the previous version are not claims (their branches exist, so that the reap can look at them)
    Gq -C $work branch -f feat/v1 origin/main
    Gq -C $work branch -f feat/r1 origin/main
    $abandoned = "Slot 1 is free (was feat/v1; the local branch is kept, delete it yourself if unwanted)."
    [System.IO.File]::WriteAllText((Marker 1), "{`n  `"slot`": 1,`n  `"branch`": `"feat/v1`",`n  `"since`": `"2026-11-05T09:00:00`"`n}`n")
    if ((Get-Porc9 1) -ne "") { Fail "claim 5: a three-key marker has the step '$(Get-Porc9 1)'" }
    $r = SlotE "-Take feat/v3 -SkipWarmup"
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "claim 5: a take did not skip a three-key marker (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $null = Slot -Abandon 2
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne $abandoned) { Fail "claim 5: -Abandon of a three-key marker (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Hand 1 "check" "2026-11-05T11:30:00"
    if ((Get-Porc9 1) -ne "check") { Fail "claim 5: a seven-key marker has the step '$(Get-Porc9 1)'" }
    $r = SlotE "-Take feat/v3 -SkipWarmup"
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "claim 5: a take did not skip a seven-key marker (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $null = Slot -Abandon 2
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 1 is free (was feat/r1; the local branch is kept, delete it yourself if unwanted).") { Fail "claim 5: -Abandon of a seven-key marker (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    [System.IO.File]::WriteAllText((Marker 1), "{`n  `"slot`": 1,`n  `"branch`": `"feat/v1`",`n  `"since`": `"2026-11-05T09:00:00`",`n  `"state`": `"done`"`n}`n")
    if ((Get-Porc9 1) -ne "") { Fail "claim 5: a marker with the state done has the step '$(Get-Porc9 1)'" }
    if ((SlotE "-Status").Out -notmatch "(?m)^slot 1  ready           busy: feat/v1 since 2026-11-05T09:00:00") { Fail "claim 5: a marker with the state done is not a finished busy slot: $((SlotE '-Status').Out)" }
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne $abandoned) { Fail "claim 5: -Abandon of a marker with the state done (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    # the previous version against a take that is working
    $tag = @(git -C $here tag --list 'v*' --sort=-v:refname | Select-Object -First 1)[0]
    if (-not $tag) {
      Write-Host "skipped: no release tag to run the previous version"
    } else {
      New-Item -ItemType Directory -Force "$tmp\prev" | Out-Null
      # a complete copy of the scripts\ folder at the tag, whatever library files it sources
      git -C $here archive --format=tar -o "$tmp\prev.tar" $tag scripts
      # Windows' own tar by its path: a GNU tar first on the PATH (Git Bash) reads "C:\..." as a host (#304)
      $tarExe = 'tar'
      if ($env:SystemRoot -and (Test-Path (Join-Path $env:SystemRoot 'System32\tar.exe'))) { $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe' }
      & $tarExe -xf "$tmp\prev.tar" -C "$tmp\prev" --strip-components=1
      Write-Cfg $gateJson
      $h = Start-Take "-Take feat/v1 -Slot 1"
      Wait-For 1 "taking"
      $r = Wait-Take (Start-Proc $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$tmp\prev\slot.ps1`" -Status")
      if ($r.Code -ne 0 -or $r.Out -notmatch "(busy|taking): feat/v1 since") { Fail "claim 5: the previous version ($tag) does not show the taking slot as busy (exit $($r.Code)): $($r.Out) / $($r.Err)" }
      $r = Wait-Take (Start-Proc $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$tmp\prev\slot.ps1`" -Take feat/v2 -SkipWarmup")
      if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "claim 5: the previous version ($tag) did not skip the taking slot (exit $($r.Code)): $($r.Out) / $($r.Err)" }
      $null = Slot -Abandon 2
      [System.IO.File]::WriteAllText("$tmp\go", "")
      $r = Wait-Take $h; $script:bgs.Clear()
      if ($r.Code -ne 0) { Fail "claim 5: the take did not finish (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    }
    Claim-Reset
  }

  # 6 the claim exists before the fetch, the worktree add and the switch
  function Claim-Case6 {
    Claim-Reset
    if (Test-Path "$tmp\wt\slot-4") { Fail "claim 6: setup: slot-4 exists" }
    New-Item -ItemType Directory -Force "$tmp\hooks" | Out-Null
    $recText = @'
m='@M@'; if [ -e "$m" ] && grep -q '"state": "taking"' "$m"; then c=claimed; else c=unclaimed; fi; echo "$1 $c" >> '@TMP@/spy.log'
'@
    $rootFwd = $claimRoot -replace '\\', '/'
    [System.IO.File]::WriteAllText("$tmp\hooks\record", $recText.Replace('@M@', "$rootFwd/.slots/slot-4.json").Replace('@TMP@', $tf) + "`n")
    [System.IO.File]::WriteAllText("$tmp\hooks\post-checkout", "#!/bin/sh`nsh '$tf/hooks/record' checkout`n")
    [System.IO.File]::WriteAllText("$tmp\hooks\upload-pack", "#!/bin/sh`nsh '$tf/hooks/record' fetch`nexec git upload-pack `"`$@`"`n")
    git -C $work config core.hooksPath "$tf/hooks"
    git -C $work config remote.origin.uploadpack "sh '$tf/hooks/upload-pack'"
    [System.IO.File]::WriteAllText("$tmp\spy.log", "")
    $r = SlotE "-Take feat/c6 -Slot 4 -SkipWarmup" @{ WORKER_SLOTS = "4" }
    if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 4 is yours") { Fail "claim 6: the take failed (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    $spy = [System.IO.File]::ReadAllText("$tmp\spy.log") -replace "`r`n", "`n"
    if ($spy -cne "fetch claimed`ncheckout claimed`ncheckout claimed`n") { Fail "claim 6: git did not see the claim at the fetch, the worktree add and the switch; the log is: $($spy -replace "`n", '|')" }
    # control: with a finished marker the same probe says unclaimed
    if (-not (Test-Finished 4)) { Fail "claim 6: the marker of slot 4 is not finished: $(MText 4)" }
    Gq -C $work fetch -q origin
    Gq -C "$tmp\wt\slot-4" switch -q -c feat/c6b
    $spy = [System.IO.File]::ReadAllText("$tmp\spy.log") -replace "`r`n", "`n"
    if ($spy -cne "fetch claimed`ncheckout claimed`ncheckout claimed`nfetch unclaimed`ncheckout unclaimed`n") { Fail "claim 6: the probe cannot tell a claim from a finished marker; the log is: $($spy -replace "`n", '|')" }
    Gq -C $work config --unset core.hooksPath
    Gq -C $work config --unset remote.origin.uploadpack
    $null = SlotE "-Abandon 4" @{ WORKER_SLOTS = "4" }
    Gq -C $work branch -D feat/c6 feat/c6b
  }

  # 7 the publish is exclusive, in one shell and across the two
  function Test-Race($r1, $r2, [string]$b1, [string]$b2) { # checks the results of the two takes; the winner's branch is left in $script:winner
    if (-not (($r1.Code -eq 0 -and $r2.Code -eq 1) -or ($r1.Code -eq 1 -and $r2.Code -eq 0))) { Fail "claim 7: the exits of the two takes are $($r1.Code) and $($r2.Code), not one 0 and one 1: $($r1.Out) / $($r1.Err) / $($r2.Out) / $($r2.Err)" }
    if ($r1.Code -eq 0) { $w = $r1; $l = $r2; $wb = $b1; $lb = $b2 } else { $w = $r2; $l = $r1; $wb = $b2; $lb = $b1 }
    if ($w.Out -notmatch "Slot 1 is yours") { Fail "claim 7: the winner did not print Slot 1 is yours: $($w.Out)" }
    if (-not (Test-EndsWithLine $l.Err "slot 1 is busy")) { Fail "claim 7: the loser's standard error does not end with 'slot 1 is busy': $($l.Err)" }
    if ((MGet 1 "branch") -ne $wb) { Fail "claim 7: the marker of slot 1 names '$(MGet 1 'branch')', not the winner $wb" }
    if ((MText 1).Contains('"state"') -or (MText 1).Contains('"pid"')) { Fail "claim 7: the marker of slot 1 is not finished: $(MText 1)" }
    if ((Get-Current 1) -ne $wb) { Fail "claim 7: slot 1 is on '$(Get-Current 1)', not on the winner $wb" }
    if (Get-Ref $lb) { Fail "claim 7: the loser's branch $lb exists (it fetched or switched)" }
    if ((Get-Leftovers 1).Count -ne 0) { Fail "claim 7: temporary files are left: $((Get-Leftovers 1) -join ', ')" }
    $script:winner = $wb
  }
  function Claim-Case7 {
    Claim-Reset
    $gate = @{ NIGHTMILL_CLAIM_GATE = "$tf/claim-go" }
    # same shell
    $h1 = Start-Take "-Take feat/x1 -Slot 1 -SkipWarmup" $gate
    $h2 = Start-Take "-Take feat/x2 -Slot 1 -SkipWarmup" $gate
    Wait-Claims 1 2
    [System.IO.File]::WriteAllText("$tmp\claim-go", "")
    $r1 = Wait-Take $h1; $r2 = Wait-Take $h2
    $script:bgs.Clear()
    Test-Race $r1 $r2 "feat/x1" "feat/x2"
    if (((((MText 1) | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object) -join ",") -ne "branch,since,slot") { Fail "claim 7: the winner's marker has other keys than branch, since, slot: $(MText 1)" }
    Claim-Reset
    Gq -C $work branch -D $script:winner
    # across the shells
    $execPath = (([string](git --exec-path)) -replace '/', '\').Trim()
    $gitRoot = Split-Path (Split-Path (Split-Path $execPath -Parent) -Parent) -Parent
    $bashExe = Join-Path $gitRoot "bin\bash.exe"
    if (-not (Test-Path $bashExe)) {
      Write-Host "skipped: no bash for the cross-shell claim"
    } else {
      Remove-Item "$tmp\claim-go" -Force -ErrorAction SilentlyContinue
      $h1 = Start-Proc $bashExe "`"$hereFwd/scripts/slot.sh`" --take feat/y1 --slot 1 --skip-warmup" $gate
      $h2 = Start-Take "-Take feat/y2 -Slot 1 -SkipWarmup" $gate
      Wait-Claims 1 2
      [System.IO.File]::WriteAllText("$tmp\claim-go", "")
      $r1 = Wait-Take $h1; $r2 = Wait-Take $h2
      $script:bgs.Clear()
      Test-Race $r1 $r2 "feat/y1" "feat/y2"
      if ($script:winner -eq "feat/y1") {
        if ((Get-Keys 1) -cne "slot,branch,since") { Fail "claim 7: the bash winner's marker has other keys than slot, branch, since in that order: $(MText 1)" }
      } elseif (((((MText 1) | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object) -join ",") -ne "branch,since,slot") {
        Fail "claim 7: the PowerShell winner's marker has other keys than branch, since, slot: $(MText 1)"
      }
      Claim-Reset
      Gq -C $work branch -D $script:winner
    }
  }

  Claim-Case1
  Claim-Case2
  Claim-Case3
  Claim-Case4
  Claim-Case5
  Claim-Case6
  Claim-Case7
  Claim-Reset

  Write-Host "== marker retries (iteration 35)"
  # marker retries (iteration 35): a take tries its own marker changes (the move of the finished marker over its claim,
  # the rewrite of a claim it leaves behind without pid, the removal of its claim) up to 21 times, 0.25 s apart, while a
  # reader holds the marker open; the publish of the claim is tried once. Cases 1 to 4 hold the marker open from this
  # process ([System.IO.File]::Open with FileShare.Read, no delete sharing) and need Windows; elsewhere they print a skip
  # line. Case 5 (the publish is tried once) runs everywhere.
  $script:held = $null
  $script:retryL = 0
  function Hold-Marker([string]$path) {
    $script:held = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
  }
  function Let-Go { if ($null -ne $script:held) { $script:held.Dispose(); $script:held = $null } }
  function Fail($msg) { Let-Go; Stop-Claim; Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
  function Wait-Until([string]$what, [scriptblock]$cond) { # until the condition holds (60 s at most)
    $end = (Get-Date).AddSeconds(60)
    while (-not (& $cond)) {
      if ((Get-Date) -gt $end) { Fail "retries: $what did not happen within 60 s" }
      Start-Sleep -Milliseconds 100
    }
  }
  function Test-AtMove($h, [string]$what, [scriptblock]$sign) { # the sign, then 1 s: the take still runs and the marker is as before
    Wait-Until $what $sign
    Start-Sleep -Seconds 1
    if ($h.P.HasExited) { Fail "retries: the take ended within 1 s of $what`: it tried once, not again" }
    if ((MText 1) -cne $script:before) { Fail "retries: the marker changed within 1 s of $what`: $(MText 1)" }
  }
  function Get-LineCount([string]$err) { @($err -split "`n" | Where-Object { $_ -ne "" }).Count }
  function Get-LastLine([string]$err) { $p = @($err -split "`n" | Where-Object { $_ -ne "" }); if ($p.Count -eq 0) { "" } else { $p[-1] } }
  function Test-SameAsRef([string]$case, $r, $ref) {
    if ($r.Code -ne $ref.Code) { Fail "retries $case`: exit $($r.Code), the reference run gave $($ref.Code)" }
    if ((Get-LastLine $r.Err) -cne (Get-LastLine $ref.Err)) { Fail "retries $case`: last line of standard error [$(Get-LastLine $r.Err)], the reference run gave [$(Get-LastLine $ref.Err)]" }
    if ((Get-LineCount $r.Err) -ne (Get-LineCount $ref.Err)) { Fail "retries $case`: $(Get-LineCount $r.Err) lines of standard error, the reference run gave $(Get-LineCount $ref.Err) (nothing may be printed for a failed try): $($r.Err)" }
  }
  $gateBody = "`$gi = 0; while (-not (Test-Path '$tf/go')) { `$gi++; if (`$gi -ge 1200) { throw 'no go' }; Start-Sleep -Milliseconds 100 }"
  function Get-GateJson([string]$after) { "[ { `"command`": `"$gateBody$after`" } ]" }
  $canHold = ($env:OS -eq "Windows_NT")

  # 1 the finishing move
  function Retry-Case1 {
    Claim-Reset
    Gq -C $work branch -D feat/r1   # both runs start without the branch (an earlier case may have left it)
    Write-Cfg $gateJson
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $ref = SlotE "-Take feat/r1 -Slot 1"
    $script:retryL = Get-LineCount $ref.Err
    Claim-Reset; Gq -C $work branch -D feat/r1
    Write-Cfg $gateJson
    $h = Start-Take "-Take feat/r1 -Slot 1"
    Wait-For 1 "taking"
    $script:before = MText 1
    Hold-Marker (Marker 1)
    [System.IO.File]::WriteAllText("$tmp\go", "")
    Test-AtMove $h "the finishing move" { Test-Path -LiteralPath "$S1\slot-1.take.tmp" }
    Let-Go
    $r = Wait-Take $h
    $script:bgs.Clear()
    if ($r.Code -ne 0 -or $r.Out -notmatch '(?m)^Slot 1 is yours') { Fail "retries 1: the take did not finish after the reader let go (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Test-SameAsRef "1" $r $ref
    if (-not (Test-Finished 1)) { Fail "retries 1: the marker is not a finished marker: $(MText 1)" }
    if ((MGet 1 "branch") -ne "feat/r1" -or (Get-Current 1) -ne "feat/r1") { Fail "retries 1: slot 1 is not on feat/r1" }
    if (@(Get-Leftovers 1).Count -gt 0) { Fail "retries 1: temporary files are left: $(Get-Leftovers 1)" }
    $line1 = ((SlotE "-Status -Porcelain").Out -split "`n")[0]
    if (-not $line1.StartsWith("1${T}busy${T}feat/r1${T}")) { Fail "retries 1: porcelain line 1: $line1" }
    $x = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
    if ($x.Code -ne 0) { Fail "retries 1: -Report on the finished slot exited $($x.Code): $($x.Err)" }
    $x = SlotE "-Abandon 1"
    if ($x.Code -ne 0) { Fail "retries 1: -Abandon exited $($x.Code): $($x.Err)" }
    Gq -C $work branch -D feat/r1
  }

  # 2 the removal of the claim (restore item 5)
  function Retry-Case2 {
    Claim-Reset
    Write-Cfg (Get-GateJson "; cmd /c exit 7")
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $ref = SlotE "-Take feat/r2 -Slot 1"
    $want = "warm-up 1 failed (exit 7); slot 1 is free again"
    if ($ref.Code -ne 1 -or (Get-LastLine $ref.Err) -cne $want) { Fail "retries 2: the reference run (exit $($ref.Code)): $($ref.Err)" }
    Claim-Reset
    Write-Cfg (Get-GateJson "; cmd /c exit 7")
    $h = Start-Take "-Take feat/r2 -Slot 1"
    Wait-For 1 "taking"
    Wait-Until "the switch to feat/r2" { [bool](Get-Ref "feat/r2") }
    $script:before = MText 1
    Hold-Marker (Marker 1)
    [System.IO.File]::WriteAllText("$tmp\go", "")
    Test-AtMove $h "the removal of the claim" { -not (Get-Ref "feat/r2") }
    Let-Go
    $r = Wait-Take $h
    $script:bgs.Clear()
    if ($r.Code -ne 1 -or (Get-LastLine $r.Err) -cne $want) { Fail "retries 2: the take (exit $($r.Code)): $($r.Err)" }
    Test-SameAsRef "2" $r $ref
    if (Test-Path -LiteralPath (Marker 1)) { Fail "retries 2: the marker is still there: $(MText 1)" }
    if (Get-Current 1) { Fail "retries 2: slot 1 is not detached" }
    $line1 = ((SlotE "-Status -Porcelain").Out -split "`n")[0]
    if ($line1 -ne "1${T}free") { Fail "retries 2: porcelain line 1: $line1" }
  }

  # 3 the rewrite without pid
  function Retry-Case3 {
    Claim-Reset
    New-Branch "feat/rw" "rw.txt"
    $json = Get-GateJson "; Set-Content rw.txt changed; cmd /c exit 7"
    Write-Cfg $json
    [System.IO.File]::WriteAllText("$tmp\go", "")
    $ref = SlotE "-Take feat/rw -Slot 1"
    $want = "warm-up 1 failed (exit 7); slot 1 could not be put back and stays claimed: free it with -Abandon 1"
    if ($ref.Code -ne 1 -or (Get-LastLine $ref.Err) -cne $want) { Fail "retries 3: the reference run (exit $($ref.Code)): $($ref.Err)" }
    Claim-Reset
    Write-Cfg $json
    $h = Start-Take "-Take feat/rw -Slot 1"
    Wait-For 1 "taking"
    $since = MGet 1 "since"
    $script:before = MText 1
    Hold-Marker (Marker 1)
    [System.IO.File]::WriteAllText("$tmp\go", "")
    Test-AtMove $h "the rewrite of the claim" { @(Get-ChildItem -LiteralPath $S1 -Filter "slot-1.left.*.tmp" -File -ErrorAction SilentlyContinue).Count -gt 0 }
    Let-Go
    $r = Wait-Take $h
    $script:bgs.Clear()
    if ($r.Code -ne 1 -or (Get-LastLine $r.Err) -cne $want) { Fail "retries 3: the take (exit $($r.Code)): $($r.Err)" }
    Test-SameAsRef "3" $r $ref
    $m = (MText 1) | ConvertFrom-Json
    $names = ($m.PSObject.Properties.Name | Sort-Object) -join ","
    if ($names -ne "branch,since,slot,state" -or [string]$m.branch -ne "feat/rw" -or [string]$m.since -ne $since -or [string]$m.state -ne "taking") { Fail "retries 3: the claim left behind is not the claim without pid: $(MText 1)" }
    if (@(Get-Leftovers 1).Count -gt 0) { Fail "retries 3: temporary files are left: $(Get-Leftovers 1)" }
    if ((Get-Porc9 1) -ne "take-died") { Fail "retries 3: porcelain field 9 is '$(Get-Porc9 1)'" }
    Gq -C "$tmp\wt\slot-1" checkout -- rw.txt
    $x = SlotE "-Abandon 1"
    if ($x.Code -ne 0) { Fail "retries 3: -Abandon exited $($x.Code): $($x.Err)" }
    Gq -C $work branch -D feat/rw
  }

  # 4 a reader that never lets go
  function Retry-Case4 {
    Claim-Reset
    Write-Cfg $gateJson
    $h = Start-Take "-Take feat/r4 -Slot 1"
    Wait-For 1 "taking"
    $since = MGet 1 "since"
    $script:before = MText 1
    $mj = $script:before | ConvertFrom-Json
    $procId = [string]$mj.pid
    Hold-Marker (Marker 1)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.File]::WriteAllText("$tmp\go", "")
    if (-not $h.P.WaitForExit(60000)) { Fail "retries 4: the take did not end within 60 s" }
    $sw.Stop()
    $r = Wait-Take $h
    $script:bgs.Clear()
    Let-Go
    if ($r.Code -ne 1) { Fail "retries 4: the take exited $($r.Code): $($r.Out) / $($r.Err)" }
    if ($sw.Elapsed.TotalSeconds -lt 9) { Fail "retries 4: the take ended after $($sw.Elapsed.TotalSeconds) s, not after at least 9 s (it did not retry)" }
    if ((Get-LastLine $r.Err) -cne "write marker failed (exit 1); slot 1 stays claimed: free it with -Abandon 1") { Fail "retries 4: the last line of standard error: $($r.Err)" }
    if ((Get-LineCount $r.Err) -gt $script:retryL + 3) { Fail "retries 4: more than $($script:retryL + 3) lines of standard error: $($r.Err)" }
    if ((MText 1) -cne $script:before) { Fail "retries 4: the claim changed: $(MText 1)" }
    if (@(Get-Leftovers 1).Count -gt 0) { Fail "retries 4: temporary files are left: $(Get-Leftovers 1)" }
    if ((Get-Current 1) -ne "feat/r4") { Fail "retries 4: slot 1 is on '$(Get-Current 1)'" }
    $st = (SlotE "-Status").Out
    if (-not $st.Contains("taking: feat/r4 since $since (process $procId has ended; free it with -Abandon 1)")) { Fail "retries 4: status: $st" }
    $x = SlotE "-Abandon 1"
    if ($x.Code -ne 0 -or $x.Out.Trim() -cne "Slot 1 is free (was feat/r4, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "retries 4: -Abandon (exit $($x.Code)): $($x.Out) / $($x.Err)" }
    Gq -C $work branch -D feat/r4
  }

  # 5 the publish is tried once
  function Retry-Case5 {
    Claim-Reset
    $gate = @{ NIGHTMILL_CLAIM_GATE = "$tf/claim-go" }
    $h1 = Start-Take "-Take feat/p5a -Slot 1 -SkipWarmup" $gate
    $h2 = Start-Take "-Take feat/p5b -Slot 1 -SkipWarmup" $gate
    Wait-Claims 1 2
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.File]::WriteAllText("$tmp\claim-go", "")
    $t1 = $null; $t2 = $null
    $end = (Get-Date).AddSeconds(60)
    while ($null -eq $t1 -or $null -eq $t2) {
      if ((Get-Date) -gt $end) { Fail "retries 5: the takes did not end within 60 s" }
      if ($null -eq $t1 -and $h1.P.HasExited) { $t1 = $sw.Elapsed.TotalSeconds }
      if ($null -eq $t2 -and $h2.P.HasExited) { $t2 = $sw.Elapsed.TotalSeconds }
      Start-Sleep -Milliseconds 100
    }
    $r1 = Wait-Take $h1; $r2 = Wait-Take $h2
    $script:bgs.Clear()
    if (-not ((($r1.Code -eq 0) -and ($r2.Code -eq 1)) -or (($r1.Code -eq 1) -and ($r2.Code -eq 0)))) { Fail "retries 5: the exits are $($r1.Code) and $($r2.Code), not one 0 and one 1: $($r1.Err) / $($r2.Err)" }
    if ($r1.Code -eq 0) { $loser = $r2; $tl = $t2 } else { $loser = $r1; $tl = $t1 }
    if ((Get-LastLine $loser.Err) -cne "slot 1 is busy") { Fail "retries 5: the loser's standard error: $($loser.Err)" }
    if ($tl -gt 4) { Fail "retries 5: the loser ended $tl s after the gate opened: the publish was retried" }
    Claim-Reset
    Gq -C $work branch -D feat/p5a
    Gq -C $work branch -D feat/p5b
  }

  if ($canHold) {
    Retry-Case1
    Retry-Case2
    Retry-Case3
    Retry-Case4
  } else {
    1..4 | ForEach-Object { Write-Host "skipped: no reader that holds the marker open (needs Windows)" }
  }
  Retry-Case5
  Claim-Reset
  Put-Cfg $CFG ($cfgBefore)

  Write-Host "== interruption (iteration 36)"
  # interruption (iteration 36): a take that is stopped after it has claimed its slot runs, in a finally block, the same
  # restore as a failed take and says "<step> stopped" with the outcome (the exit code is PowerShell's own and is not
  # asserted). The take runs in a runspace of this process and is stopped with BeginStop(), the same pipeline stop as
  # Ctrl+C in a console; its lines go to a StringWriter that stands in for [Console]::Error. Seven cases: (1) in the
  # warm-up the slot is free and unswitched; (2) after the warm-up changed a file the slot cannot be put back and a
  # claim without pid stays that -Abandon frees (the claim's process, this one, still runs); (3) while the finished
  # marker is written the claim stays (needs Windows, as the reader of iteration 35); (4) Stop-Process leaves a dead
  # claim, as in iteration 34; (5) in the fetch and (6) in the switch, held by a hook, the slot is free; (7) at the
  # publish nothing was claimed. Every wait is bounded.
  $script:intr = $null
  $script:intrErrOld = $null
  function Restore-Err { if ($null -ne $script:intrErrOld) { [Console]::SetError($script:intrErrOld); $script:intrErrOld = $null } }
  function Remove-IntrGate { Remove-Item Env:\NIGHTMILL_CLAIM_GATE -ErrorAction SilentlyContinue }
  function Kill-Intr { # at a failure: stop the runspace, give back the console error, open the hook's gate, end the hook
    Restore-Err
    Remove-IntrGate
    if ($null -ne $script:intr) { try { [void]$script:intr.Ps.BeginStop($null, $null) } catch { } }
    try { [System.IO.File]::WriteAllText("$tmp\hold-go", "") } catch { }
    if (Test-Path -LiteralPath "$tmp\hold.winpid") {
      foreach ($x in @(Get-Content -LiteralPath "$tmp\hold.winpid")) { if ("$x".Trim() -match '^[0-9]+$') { Stop-Process -Id ([int]"$x".Trim()) -Force -ErrorAction SilentlyContinue } }
    }
  }
  function Fail($msg) { Kill-Intr; Let-Go; Stop-Claim; Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
  $pidGate = "Set-Content '$tf/gate.pid' x; $gateBody"
  function Start-Intr([string]$arguments, [string]$gate = "") {
    $sw = New-Object System.IO.StringWriter
    $script:intrErrOld = [Console]::Error
    [Console]::SetError($sw)
    if ($gate) { $env:NIGHTMILL_CLAIM_GATE = $gate }
    $p = [powershell]::Create()
    [void]$p.AddScript("Set-Location -LiteralPath '$work'; & '$S' $arguments")
    $ar = $p.BeginInvoke()
    $script:intr = [pscustomobject]@{ Ps = $p; Ar = $ar; Sw = $sw; Stop = $null; State = ""; Err = "" }
  }
  function Wait-IntrSign([string]$what, [scriptblock]$cond) { # until the condition holds (60 s at most; the take must still run)
    $end = (Get-Date).AddSeconds(60)
    while (-not (& $cond)) {
      if ((Get-Date) -gt $end) { Fail "interruption: $what did not happen within 60 s" }
      if ($script:intr.Ar.IsCompleted -and -not (& $cond)) { Fail "interruption: the take ended before $what`: $($script:intr.Sw.ToString())" }
      Start-Sleep -Milliseconds 100
    }
  }
  function Begin-StopIntr { $script:intr.Stop = $script:intr.Ps.BeginStop($null, $null) }
  function End-StopIntr { # waits for the stop (60 s at most); leaves State and Err (the take's lines, LF) in $script:intr
    if (-not $script:intr.Stop.AsyncWaitHandle.WaitOne(60000)) { Fail "interruption: the take did not end within 60 s after the stop" }
    try { $script:intr.Ps.EndStop($script:intr.Stop) } catch { }
    Restore-Err
    Remove-IntrGate
    $script:intr.State = [string]$script:intr.Ps.InvocationStateInfo.State
    $script:intr.Err = ($script:intr.Sw.ToString() -replace "`r`n", "`n")
    $script:intr.Ps.Dispose()
  }
  function Stop-Intr { Begin-StopIntr; End-StopIntr }
  function Intr-Clean([string[]]$branches) { # a clean start for a case: slots free, no pid files, the branches gone
    Claim-Reset
    Remove-Item "$tmp\gate.pid", "$tmp\hold.pid", "$tmp\hold.winpid", "$tmp\hold-go" -Force -ErrorAction SilentlyContinue
    foreach ($b in $branches) { Gq -C $work branch -D $b }
  }
  function Test-IntrFree([string]$case, [string]$branch, [string]$x) { # the slot is free and unswitched
    if (Test-Path (Marker 1)) { Fail "interruption $case`: the marker of slot 1 is still there: $(MText 1)" }
    if (@(Get-Leftovers 1).Count -gt 0) { Fail "interruption $case`: temporary files are left: $(Get-Leftovers 1)" }
    if ((Get-Current 1) -or (Get-Head 1) -ne $x) { Fail "interruption $case`: slot 1 is not detached at $x (branch '$(Get-Current 1)', head $(Get-Head 1))" }
    if (Get-Ref $branch) { Fail "interruption $case`: the branch $branch was left behind" }
    $line1 = ((SlotE "-Status -Porcelain").Out -split "`n")[0]
    if ($line1 -ne "1${T}free") { Fail "interruption $case`: porcelain line 1: $line1" }
  }
  function Test-IntrLast([string]$case, [string]$want) {
    if ($script:intr.State -ne "Stopped") { Fail "interruption $case`: the runspace state is $($script:intr.State), not Stopped: $($script:intr.Err)" }
    if ((Get-LastLine $script:intr.Err) -cne $want) { Fail "interruption $case`: the last line of standard error is [$(Get-LastLine $script:intr.Err)], wanted [$want]: $($script:intr.Err)" }
  }
  function Wait-IntrTaking {
    $end = (Get-Date).AddSeconds(60)
    while ((Get-Porc9 1) -ne "taking") {
      if ((Get-Date) -gt $end) { Fail "interruption: slot 1 did not show the step 'taking' within 60 s" }
      if ($script:intr.Ar.IsCompleted) { Fail "interruption: the take ended before it showed the step 'taking': $($script:intr.Sw.ToString())" }
      Start-Sleep -Milliseconds 100
    }
  }
  function Test-IntrGone([string]$case) { # every hook process of hold.winpid has ended within 5 s (where Windows ids are recorded)
    if (-not (Test-Path -LiteralPath "$tmp\hold.winpid")) { return }
    $end = (Get-Date).AddSeconds(5)
    while ($true) {
      $alive = @(Get-Content -LiteralPath "$tmp\hold.winpid" | Where-Object { "$_".Trim() -match '^[0-9]+$' } | Where-Object { Get-Process -Id ([int]"$_".Trim()) -ErrorAction SilentlyContinue })
      if ($alive.Count -eq 0) { return }
      if ((Get-Date) -gt $end) { Fail "interruption $case`: a hook process is still running 5 s after the stop: $($alive -join ', ')" }
      Start-Sleep -Milliseconds 100
    }
  }

  # 1 stopped in the warm-up: the slot is free and unswitched
  function Intr-Case1 {
    Intr-Clean @("feat/i1")
    Write-Cfg "[ { `"command`": `"$pidGate`" } ]"
    $x = Get-Head 1
    Start-Intr "-Take feat/i1 -Slot 1"
    Wait-IntrTaking
    Wait-IntrSign "the warm-up's pid file" { Test-Path -LiteralPath "$tmp\gate.pid" }
    Stop-Intr
    Test-IntrLast "1" "warm-up 1 stopped; slot 1 is free again"
    Test-IntrFree "1" "feat/i1" $x
  }

  # 2 stopped after the warm-up changed a file: a claim without pid that -Abandon frees
  function Intr-Case2 {
    Intr-Clean @("feat/i3")
    New-Branch "feat/i3" "i3.txt"
    Write-Cfg "[ { `"command`": `"Set-Content i3.txt changed; $pidGate`" } ]"
    Start-Intr "-Take feat/i3 -Slot 1"
    Wait-IntrTaking
    Wait-IntrSign "the warm-up's pid file" { Test-Path -LiteralPath "$tmp\gate.pid" }
    Stop-Intr
    if ($script:intr.State -ne "Stopped") { Fail "interruption 2: the runspace state is $($script:intr.State): $($script:intr.Err)" }
    $left = "slot 1 has uncommitted files: $claimRoot\slot-1 (commit, stash or discard them first)"
    if (-not (Test-EndsWithLines $script:intr.Err @($left, "warm-up 1 stopped; slot 1 could not be put back and stays claimed: free it with -Abandon 1"))) { Fail "interruption 2: the last two lines of standard error: $($script:intr.Err)" }
    if ((Get-Current 1) -ne "feat/i3") { Fail "interruption 2: slot 1 is not on feat/i3 (branch '$(Get-Current 1)')" }
    if (((Get-Content "$tmp\wt\slot-1\i3.txt") -join "") -ne "changed") { Fail "interruption 2: the changed file was not kept" }
    $since = MGet 1 "since"
    Test-Same (Taking-Text 1 "feat/i3" $since) 1 "interruption 2"
    if ((Get-Porc9 1) -ne "take-died") { Fail "interruption 2: porcelain field 9 is '$(Get-Porc9 1)', not take-died (the claim's process, this one, still runs)" }
    if (-not (SlotE "-Status").Out.Contains("taking: feat/i3 since $since (no process recorded; free it with -Abandon 1)")) { Fail "interruption 2: status: $((SlotE '-Status').Out)" }
    Gq -C "$tmp\wt\slot-1" checkout -- i3.txt
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or $r.Out.Trim() -cne "Slot 1 is free (was feat/i3, a take that did not finish; the local branch is kept, delete it yourself if unwanted).") { Fail "interruption 2: -Abandon (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if (Test-Path (Marker 1)) { Fail "interruption 2: the marker is still there after -Abandon" }
    Gq -C $work branch -D feat/i3
  }

  # 3 stopped while writing the finished marker: the claim stays without pid
  function Intr-Case3 {
    Intr-Clean @("feat/i4")
    Write-Cfg $gateJson
    Start-Intr "-Take feat/i4 -Slot 1"
    Wait-IntrTaking
    Hold-Marker (Marker 1)
    [System.IO.File]::WriteAllText("$tmp\go", "")
    Wait-IntrSign "the finishing move" { Test-Path -LiteralPath "$S1\slot-1.take.tmp" }
    Begin-StopIntr
    Start-Sleep -Seconds 1
    Let-Go
    End-StopIntr
    Test-IntrLast "3" "write marker stopped; slot 1 stays claimed: free it with -Abandon 1"
    Test-Same (Taking-Text 1 "feat/i4" (MGet 1 "since")) 1 "interruption 3"
    if (@(Get-Leftovers 1).Count -gt 0) { Fail "interruption 3: temporary files are left: $(Get-Leftovers 1)" }
    if ((Get-Current 1) -ne "feat/i4") { Fail "interruption 3: slot 1 is not on feat/i4" }
    if (-not (SlotE "-Status").Out.Contains("(no process recorded; free it with -Abandon 1)")) { Fail "interruption 3: status: $((SlotE '-Status').Out)" }
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or -not $r.Out.StartsWith("Slot 1 is free (was feat/i4, a take that did not finish; ")) { Fail "interruption 3: -Abandon (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    Gq -C $work branch -D feat/i4
    Remove-Item "$tmp\go" -Force -ErrorAction SilentlyContinue
  }

  # 4 Stop-Process, no chance to clean up: a dead claim, as in iteration 34
  function Intr-Case4 {
    Intr-Clean @("feat/i5")
    Write-Cfg "[ { `"command`": `"$pidGate`" } ]"
    $h = Start-Take "-Take feat/i5 -Slot 1"
    Wait-For 1 "taking"
    $end = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath "$tmp\gate.pid")) {
      if ((Get-Date) -gt $end) { Fail "interruption 4: the warm-up's pid file did not appear within 60 s" }
      Start-Sleep -Milliseconds 100
    }
    $id = $h.P.Id
    Stop-Process -Id $id -Force
    if (-not $h.P.WaitForExit(60000)) { Fail "interruption 4: the stopped take did not end within 60 s" }
    $r = Wait-Take $h; $script:bgs.Clear()
    if ($r.Err -match 'stopped|interrupted|free again') { Fail "interruption 4: the killed take wrote a line: $($r.Err)" }
    $since = MGet 1 "since"
    Test-Same (Taking-Text 1 "feat/i5" $since "$id") 1 "interruption 4"
    if (-not (SlotE "-Status").Out.Contains("taking: feat/i5 since $since (process $id has ended; free it with -Abandon 1)")) { Fail "interruption 4: status: $((SlotE '-Status').Out)" }
    if ((Get-Porc9 1) -ne "take-died") { Fail "interruption 4: porcelain field 9 is '$(Get-Porc9 1)'" }
    $r = SlotE "-Abandon 1"
    if ($r.Code -ne 0 -or -not $r.Out.StartsWith("Slot 1 is free (was feat/i5, a take that did not finish; ")) { Fail "interruption 4: -Abandon (exit $($r.Code)): $($r.Out) / $($r.Err)" }
    if (Test-Path (Marker 1)) { Fail "interruption 4: the marker is still there after -Abandon" }
    if (-not (Get-Ref "feat/i5")) { Fail "interruption 4: the branch feat/i5 is gone" }
    Gq -C $work branch -D feat/i5
  }

  # the hold hook of cases 5 and 6
  New-Item -ItemType Directory -Force "$tmp\hooks" | Out-Null
  $holdText = 'echo $$ >> ''@T@/hold.pid''; if [ -r /proc/$$/winpid ]; then cat /proc/$$/winpid >> ''@T@/hold.winpid''; fi; i=0; while [ ! -e ''@T@/hold-go'' ] && [ $i -lt 300 ]; do i=$((i+1)); sleep 0.1; done'
  [System.IO.File]::WriteAllText("$tmp\hooks\hold", $holdText.Replace('@T@', $tf) + "`n")
  [System.IO.File]::WriteAllText("$tmp\hooks\upload-pack-hold", "#!/bin/sh`nsh '$tf/hooks/hold'`nexec git upload-pack `"`$@`"`n")
  [System.IO.File]::WriteAllText("$tmp\hooks\post-checkout", "#!/bin/sh`nsh '$tf/hooks/hold'`n")

  # 5 stopped in the fetch: the slot is free
  function Intr-Case5 {
    Intr-Clean @("feat/i6")
    $x = Get-Head 1
    git -C $work config remote.origin.uploadpack "sh '$tf/hooks/upload-pack-hold'"
    Start-Intr "-Take feat/i6 -Slot 1 -SkipWarmup"
    Wait-IntrSign "the hold hook" { Test-Path -LiteralPath "$tmp\hold.pid" }
    Begin-StopIntr
    [System.IO.File]::WriteAllText("$tmp\hold-go", "")
    End-StopIntr
    Gq -C $work config --unset remote.origin.uploadpack
    Test-IntrLast "5" "git fetch stopped; slot 1 is free again"
    Test-IntrFree "5" "feat/i6" $x
    Test-IntrGone "5"
  }

  # 6 stopped in the switch: the slot is unswitched and the new branch gone
  function Intr-Case6 {
    Intr-Clean @("feat/i7")
    $x = Get-Head 1
    git -C $work config core.hooksPath "$tf/hooks"
    Start-Intr "-Take feat/i7 -Slot 1 -SkipWarmup"
    Wait-IntrSign "the hold hook" { Test-Path -LiteralPath "$tmp\hold.pid" }
    Begin-StopIntr
    [System.IO.File]::WriteAllText("$tmp\hold-go", "")
    End-StopIntr
    Gq -C $work config --unset core.hooksPath
    Test-IntrLast "6" "git switch stopped; slot 1 is free again"
    Test-IntrFree "6" "feat/i7" $x
    Test-IntrGone "6"
  }

  # 7 stopped at the publish: no claim and nothing left
  function Intr-Case7 {
    Intr-Clean @("feat/i8")
    Remove-Item "$tmp\claim-go" -Force -ErrorAction SilentlyContinue
    $x = Get-Head 1
    Start-Intr "-Take feat/i8 -Slot 1 -SkipWarmup" "$tmp\claim-go"
    Wait-IntrSign "the claim's temporary file" { (Get-ClaimFiles 1).Count -ge 1 }
    if (Test-Path (Marker 1)) { Fail "interruption 7: a marker exists before the publish: $(MText 1)" }
    Stop-Intr
    Test-IntrLast "7" "claim stopped; no slot was claimed"
    Test-IntrFree "7" "feat/i8" $x
  }

  Intr-Case1
  Intr-Case2
  if ($canHold) { Intr-Case3 } else { Write-Host "skipped: no reader that holds the marker open (needs Windows)" }
  Intr-Case4
  Intr-Case5
  Intr-Case6
  Intr-Case7
  Intr-Clean @()
  Put-Cfg $CFG ($cfgBefore)

  Write-Host "== 13 a slot is freed once its branch is pushed, and a dirty slot is held"
  # 13 (iteration 33, /fix all): the skill frees a bug's slot with -Abandon once the bug's branch is on its open pull
  # request, and holds a slot with uncommitted files. The slot scripts already do both, and this case pins it: takes run
  # one after the other get different slots; -Abandon frees a clean slot at once, keeps the local branch and the pushed
  # commits, and asks gh for nothing; a freed slot is reused by the next take; -Abandon refuses a slot with an untracked
  # file and changes nothing; no gh call but the reap's merged query is made.
  function Get-RefOf([string]$repo, [string]$ref) { $x = git -C $repo rev-parse --verify -q $ref; if ($LASTEXITCODE -eq 0) { ([string]$x).Trim() } else { "" } }
  function Drop-P13Branches { foreach ($pb in "feat/p1", "feat/p2", "feat/p3") { Gq -C $work branch -D $pb; Gq -C "$tmp\origin.git" update-ref -d "refs/heads/$pb" } }
  function Get-GhLog { [System.IO.File]::ReadAllText($ghLog) }
  Claim-Reset
  Drop-P13Branches
  Reset-Gh
  $d1 = "$tmp\wt\slot-1"
  # 1 two takes one after the other get slots 1 and 2; a third fails and changes no marker
  $r = SlotE "-Take feat/p1"
  if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 1 is yours") { Fail "13.1: take feat/p1 did not get slot 1 (exit $($r.Code)): $($r.Out) / $($r.Err)" }
  $r = SlotE "-Take feat/p2"
  if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 2 is yours") { Fail "13.1: take feat/p2 did not get slot 2 (exit $($r.Code)): $($r.Out) / $($r.Err)" }
  $m1 = MText 1; $m2 = MText 2
  $r = SlotE "-Take feat/p3"
  if ($r.Code -eq 0) { Fail "13.1: a third take with two slots should fail: $($r.Out)" }
  if ($r.Err -notmatch "all 2 slots are busy") { Fail "13.1: the third take did not say 'all 2 slots are busy': $($r.Err)" }
  Test-Same $m1 1 "13.1 the third take"
  Test-Same $m2 2 "13.1 the third take"
  # 2 slot 1 commits one file and pushes; -Abandon frees it, keeps the branch and the pushed tip, and asks gh for nothing
  [System.IO.File]::WriteAllText("$d1\p1.txt", "p1`n")
  Gq -C $d1 add -A
  Gq -C $d1 -c user.name=t -c user.email=t@example.invalid commit -qm "work on feat/p1"
  Gq -C $d1 push -q origin feat/p1
  $p13tip = Get-RefOf $d1 "HEAD"
  $ghBefore = Get-GhLog
  $r = SlotE "-Abandon 1"
  if ($r.Code -ne 0) { Fail "13.2: -Abandon 1 exited $($r.Code): $($r.Out) / $($r.Err)" }
  if ($r.Out.Trim() -ne "Slot 1 is free (was feat/p1; the local branch is kept, delete it yourself if unwanted).") { Fail "13.2: wrong -Abandon output: $($r.Out)" }
  if ((Get-GhLog) -cne $ghBefore) { Fail "13.2: -Abandon asked gh: $(Get-GhLog)" }
  if (Test-Path (Marker 1)) { Fail "13.2: the marker of slot 1 is still there" }
  if (-not $p13tip -or (Get-RefOf $work "refs/heads/feat/p1") -ne $p13tip) { Fail "13.2: the local branch feat/p1 is not the tip $p13tip" }
  if ((Get-RefOf "$tmp\origin.git" "refs/heads/feat/p1") -ne $p13tip) { Fail "13.2: the origin branch feat/p1 is not the tip $p13tip" }
  if (Get-Current 1) { Fail "13.2: slot 1 is not detached: $(Get-Current 1)" }
  # 3 the freed slot is reused
  $r = SlotE "-Take feat/p3"
  if ($r.Code -ne 0 -or $r.Out -notmatch "Slot 1 is yours") { Fail "13.3: take feat/p3 did not reuse slot 1 (exit $($r.Code)): $($r.Out) / $($r.Err)" }
  # 4 an untracked file holds the slot: -Abandon refuses and changes nothing
  [System.IO.File]::WriteAllText("$d1\untracked.txt", "x`n")
  $m1 = MText 1
  $ghBefore = Get-GhLog
  $r = SlotE "-Abandon 1"
  if ($r.Code -eq 0) { Fail "13.4: -Abandon of a slot with an untracked file should fail: $($r.Out)" }
  if (-not $r.Err.Contains("slot 1 has uncommitted files:")) { Fail "13.4: wrong refusal on standard error: $($r.Err)" }
  Test-Same $m1 1 "13.4 the refused -Abandon"
  if (-not (Test-Path "$d1\untracked.txt")) { Fail "13.4: the untracked file is gone" }
  if ((Get-Current 1) -ne "feat/p3") { Fail "13.4: slot 1 is not on feat/p3 any more: $(Get-Current 1)" }
  if ((Get-GhLog) -cne $ghBefore) { Fail "13.4: the refused -Abandon asked gh: $(Get-GhLog)" }
  # 5 no gh call but the reap's merged query (the takes ask it for slots with a clean tree; it finds nothing)
  $otherCalls = @((Get-GhLog) -split "`r?`n" | Where-Object { $_ -ne "" -and $_ -cnotmatch '^pr list --state merged --head feat/p[0-9] --json number,headRefOid,createdAt,mergedAt,closingIssuesReferences$' })
  if ($otherCalls.Count -ne 0) { Fail "13.5: gh was asked something but the reap's merged query: $($otherCalls -join ' | ')" }
  # clean up: every slot free, the local and the remote branches gone, the fake gh as it was
  Remove-Item "$d1\untracked.txt" -Force
  $r = SlotE "-Abandon 1"
  if ($r.Code -ne 0) { Fail "13.5: clean-up: -Abandon 1 failed: $($r.Err)" }
  $r = SlotE "-Abandon 2"
  if ($r.Code -ne 0) { Fail "13.5: clean-up: -Abandon 2 failed: $($r.Err)" }
  Drop-P13Branches
  Claim-Reset

  Write-Host "== the record (iteration 41)"
  # The take, every report and every freeing append one line to <root>\.slots\ledger.tsv (eleven tab-separated fields:
  # kind, UTC stamp, slot, branch, name, skill, role, pr, from, to, issues); scripts\stages.ps1 prints the table from it.
  # The clock is the file NIGHTMILL_CLOCK_FILE (test only): seconds since 1970, UTC; T0 = 2026-11-07T08:00:00Z = 1794038400.
  # The warm-up of the test config copies <tmp>\warm-clock over the clock, so that a take lasts as long as the test says.
  Reset-Gh; Claim-Reset
  $RL = "$S1\ledger.tsv"
  $RT0 = [long]1794038400
  $RC = "$tmp\clock"; $RW = "$tmp\warm-clock"
  $env:NIGHTMILL_CLOCK_FILE = $RC
  Remove-Item $RL -Force -ErrorAction SilentlyContinue
  Write-Cfg "[ { `"command`": `"[System.IO.File]::WriteAllText('$tf/clock', [System.IO.File]::ReadAllText('$tf/warm-clock'))`" } ]"
  function RClock([long]$secs) { [System.IO.File]::WriteAllText($RC, "$($RT0 + $secs)`n") }
  function RTake([long]$start, [long]$finish, [string]$arguments) { # a take that starts at T0+s and ends at T0+f
    RClock $start; [System.IO.File]::WriteAllText($RW, "$($RT0 + $finish)`n")
    $r = SlotE $arguments
    if ($r.Code -ne 0) { Fail "record: the take '$arguments' failed: $($r.Out) / $($r.Err)" }
  }
  function RLines { if (Test-Path -LiteralPath $RL -PathType Leaf) { @([System.IO.File]::ReadAllLines($RL)).Count } else { 0 } }
  function RText { if (Test-Path -LiteralPath $RL -PathType Leaf) { [System.IO.File]::ReadAllText($RL) } else { "<no record>" } }
  function RLine([int]$n) { if (Test-Path -LiteralPath $RL -PathType Leaf) { @([System.IO.File]::ReadAllLines($RL))[$n - 1] } else { "<no record>" } }
  function RMerged([string]$b, [int]$n, [string]$oid, [string]$created, [string]$mergedAt, [string]$issues) { [System.IO.File]::AppendAllText("$fix\merged.txt", "$b`t$n`t$oid`t$created`t$mergedAt`t$issues`n") }
  function RStages([string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$here\scripts\stages.ps1`" $arguments"
    $psi.WorkingDirectory = "$tmp\work"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $o = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    ($o -replace "`r`n", "`n").TrimEnd("`n") + ($errTask.Result -replace "`r`n", "`n").TrimEnd("`n")
  }
  function RRow([string]$a, [string]$b, [string]$c, [string]$d) { "  {0,-20} {1,4} {2,8} {3,6}" -f $a, $b, $c, $d }

  # 1 a take appends one take line: from the claim to the finish of the take (the warm-up moved the clock by 30 s)
  RTake 0 30 "-Take feat/st1 -Slot 1"
  if ((RLines) -ne 1) { Fail "record: a take wrote $(RLines) lines: $(RText)" }
  if ((RLine 1) -cne "take${T}2026-11-07T08:00:30Z${T}1${T}feat/st1${T}take${T}${T}${T}${T}2026-11-07T08:00:00Z${T}2026-11-07T08:00:30Z${T}") { Fail "record: the take line: $(RLine 1)" }

  # 2 every report appends one step line with its stamp; the marker keeps the seven keys of iteration 23
  RClock 35; $r = SlotE "-Report slot-taken -Slot 1 -Skill next -Role session"
  if ($r.Code -ne 0 -or $r.Out -or $r.Err) { Fail "record: report 1: exit $($r.Code): $($r.Out) / $($r.Err)" }
  RClock 100; $r = SlotE "-Report implement -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 0 -or $r.Out -or $r.Err) { Fail "record: report 2: exit $($r.Code): $($r.Out) / $($r.Err)" }
  if ((RLines) -ne 3) { Fail "record: two reports gave $(RLines) lines in all: $(RText)" }
  if ((RLine 2) -cne "step${T}2026-11-07T08:00:35Z${T}1${T}feat/st1${T}slot-taken${T}next${T}session${T}${T}${T}${T}") { Fail "record: the step line of the first report: $(RLine 2)" }
  if ((RLine 3) -cne "step${T}2026-11-07T08:01:40Z${T}1${T}feat/st1${T}implement${T}next${T}implementer${T}${T}${T}${T}") { Fail "record: the step line of the second report: $(RLine 3)" }
  if ((Get-Keys 1) -cne "slot,branch,since,skill,role,step,reported") { Fail "record: marker keys: $(MText 1)" }
  if ("$(MGet 1 'step')/$(MGet 1 'skill')/$(MGet 1 'role')/$(MGet 1 'branch')" -cne "implement/next/implementer/feat/st1") { Fail "record: the marker is read by key: $(MText 1)" }

  # 3 a refused report appends nothing
  $r = SlotE "-Report check -Slot 2 -Skill next -Role implementer"
  if ($r.Code -ne 1 -or $r.Err -cne "slot 2 is not in use`n") { Fail "record: the refused report: exit $($r.Code): $($r.Err)" }
  $r = SlotE "-Report `"bad name`" -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 1) { Fail "record: a report with a bad step name: exit $($r.Code)" }
  if ((RLines) -ne 3) { Fail "record: a refused report appended a line: $(RText)" }

  # 4 -Release with a merged PR appends the free line with the PR's times and issue; the branch is gone, the table is not
  Reset-Gh; RMerged feat/st1 7 (Get-Head 1) "2026-11-07T08:02:40Z" "2026-11-07T08:06:40Z" "41"
  RClock 500
  $r = SlotE "-Release 1"
  if ($r.Code -ne 0 -or (($r.Out.Trim() -split "`n")[-1]).Trim() -cne "Slot 1 is free (was feat/st1, PR #7).") { Fail "record: release: wrong output: $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 1)) { Fail "record: release left the marker" }
  if (Test-Branch $work "feat/st1") { Fail "record: release left the branch" }
  if ((RLines) -ne 4) { Fail "record: the release wrote $(RLines) lines in all: $(RText)" }
  if ((RLine 4) -cne "free${T}2026-11-07T08:08:20Z${T}1${T}feat/st1${T}released${T}${T}${T}7${T}2026-11-07T08:02:40Z${T}2026-11-07T08:06:40Z${T}41") { Fail "record: the free line of the release: $(RLine 4)" }
  $want = (@(
      "#41  feat/st1  slot 1  merged 2026-11-07T08:06:40Z",
      (RRow "stage" "runs" "time" "share"),
      (RRow "take" "1" "30s" "8%"),
      (RRow "not-reported" "1" "5s" "1%"),
      (RRow "slot-taken" "1" "1m05s" "16%"),
      (RRow "implement" "1" "1m00s" "15%"),
      (RRow "ci-and-merge" "1" "4m00s" "60%"),
      (RRow "total" "" "6m40s" "100%")
    ) -join "`n")
  $got = RStages "-Issue 41"
  if ($got -cne $want) { Fail "record: stages -Issue 41 after the release; got: [$got] wanted: [$want]" }
  # a report after the slot is freed appends nothing and does not bring the marker back
  $r = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 1 -or $r.Err -cne "slot 1 is not in use`n" -or (Test-Path (Marker 1))) { Fail "record: a report after the release: exit $($r.Code): $($r.Err)" }
  if ((RLines) -ne 4) { Fail "record: a report after the release appended a line: $(RText)" }

  # 5 -Abandon of a finished take appends a take line and a free line with empty PR fields
  Reset-Gh
  RTake 1000 1020 "-Take feat/st2 -Slot 1"
  RClock 1100
  $r = SlotE "-Abandon 1"
  if ($r.Code -ne 0) { Fail "record: -Abandon failed: $($r.Out) / $($r.Err)" }
  if ((RLines) -ne 6) { Fail "record: a take and an abandon gave $(RLines) lines in all: $(RText)" }
  if ((RLine 5) -cne "take${T}2026-11-07T08:17:00Z${T}1${T}feat/st2${T}take${T}${T}${T}${T}2026-11-07T08:16:40Z${T}2026-11-07T08:17:00Z${T}") { Fail "record: the take line before the abandon: $(RLine 5)" }
  if ((RLine 6) -cne "free${T}2026-11-07T08:18:20Z${T}1${T}feat/st2${T}abandoned${T}${T}${T}${T}${T}${T}") { Fail "record: the free line of the abandon: $(RLine 6)" }
  Gq -C $work branch -D feat/st2

  # 6 a take, a merged PR and a second take: the reap appends a free line with the name reaped
  RTake 2000 2020 "-Take feat/st3 -Slot 1"
  RMerged feat/st3 9 (Get-Ref "feat/st3") "2026-11-07T08:35:00Z" "2026-11-07T08:40:00Z" "55"
  RTake 3000 3030 "-Take feat/st4"
  if ((RLines) -ne 9) { Fail "record: take, reap and take gave $(RLines) lines in all: $(RText)" }
  if ((RLine 8) -cne "free${T}2026-11-07T08:50:00Z${T}1${T}feat/st3${T}reaped${T}${T}${T}9${T}2026-11-07T08:35:00Z${T}2026-11-07T08:40:00Z${T}55") { Fail "record: the free line of the reap: $(RLine 8)" }
  if ((RLine 9) -cne "take${T}2026-11-07T08:50:30Z${T}1${T}feat/st4${T}take${T}${T}${T}${T}2026-11-07T08:50:00Z${T}2026-11-07T08:50:30Z${T}") { Fail "record: the take line after the reap: $(RLine 9)" }
  Reset-Gh
  RClock 3100
  $r = SlotE "-Abandon 1"
  if ($r.Code -ne 0) { Fail "record: -Abandon of the second take failed: $($r.Out) / $($r.Err)" }
  Gq -C $work branch -D feat/st3 feat/st4
  if ((RLines) -ne 10) { Fail "record: the abandon of the second take gave $(RLines) lines in all" }

  # 7 a dead claim freed with -Abandon appends nothing, because that take wrote no line
  $dp = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-Command", "exit" -PassThru -WindowStyle Hidden
  $dp.WaitForExit()
  Write-Text (Marker 1) (Taking-Text 1 "feat/st6" "2026-11-05T09:00:00" "$($dp.Id)")
  $r = SlotE "-Abandon 1"
  if ($r.Code -ne 0 -or -not $r.Out.Contains("a take that did not finish")) { Fail "record: -Abandon of a dead claim: exit $($r.Code): $($r.Out) / $($r.Err)" }
  if ((RLines) -ne 10) { Fail "record: the abandon of a dead claim appended a line: $(RLine (RLines))" }

  # 8 a record that cannot be written changes nothing else: one note on standard error, after the retries
  $saved = [System.IO.File]::ReadAllText($RL)
  Remove-Item $RL -Force; New-Item -ItemType Directory $RL | Out-Null
  Write-Text (Marker 1) "{`n  `"slot`": 1,`n  `"branch`": `"feat/st5`",`n  `"since`": `"2026-11-05T09:00:00`"`n}`n"
  $r = SlotE "-Report check -Slot 1 -Skill next -Role implementer"
  if ($r.Code -ne 0) { Fail "record: a report with an unwritable record exited $($r.Code): $($r.Err)" }
  if ("$(MGet 1 'step')/$(MGet 1 'skill')/$(MGet 1 'role')" -cne "check/next/implementer") { Fail "record: the marker was not updated: $(MText 1)" }
  if ($r.Out) { Fail "record: a report with an unwritable record printed $($r.Out)" }
  $errLines = @($r.Err -split "`n" | Where-Object { $_ -ne "" })
  if ($errLines.Count -ne 1 -or -not ($errLines[0].StartsWith("slot: the record was not written (") -and $errLines[0].EndsWith(")"))) { Fail "record: the note about the unwritable record: [$($r.Err)]" }
  Remove-Item $RL -Recurse -Force; [System.IO.File]::WriteAllText($RL, $saved)
  Remove-Item (Marker 1) -Force

  # 9 an unusable clock file gives one note and a stamp from the system clock
  Write-Text (Marker 1) "{`n  `"slot`": 1,`n  `"branch`": `"feat/st7`",`n  `"since`": `"2026-11-05T09:00:00`"`n}`n"
  $note = "ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock"
  foreach ($bad in "missing", "text") {
    if ($bad -eq "text") { [System.IO.File]::WriteAllText("$tmp\badclock", "later`n") } else { Remove-Item "$tmp\badclock" -Force -ErrorAction SilentlyContinue }
    $n0 = RLines
    $r = SlotE "-Report check -Slot 1 -Skill next -Role implementer" @{ NIGHTMILL_CLOCK_FILE = "$tmp\badclock" }
    if ($r.Code -ne 0) { Fail "record: unusable clock ($bad): exit $($r.Code): $($r.Err)" }
    if (-not (@($r.Err -split "`n") -ccontains $note)) { Fail "record: unusable clock ($bad): no note: [$($r.Err)]" }
    if ((RLines) -ne $n0 + 1) { Fail "record: unusable clock ($bad): the report wrote $((RLines) - $n0) lines" }
    $stamp = ((RLine (RLines)) -split $T)[1]
    if ($stamp -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { Fail "record: unusable clock ($bad): the stamp is not UTC YYYY-MM-DDTHH:MM:SSZ: $stamp" }
    $at = [DateTimeOffset]::Parse($stamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $d = [Math]::Abs(([DateTimeOffset]::UtcNow - $at).TotalSeconds)
    if ($d -gt 300) { Fail "record: unusable clock ($bad): the stamp $stamp is $d s from the system clock" }
  }
  Remove-Item (Marker 1) -Force

  # 10 every line has exactly eleven tab-separated fields
  $badLines = @([System.IO.File]::ReadAllLines($RL) | Where-Object { ($_ -split "`t", -1).Count -ne 11 })
  if ($badLines.Count -gt 0) { Fail "record: lines without eleven fields: $($badLines -join ' | ')" }
  if ((RLines) -eq 0) { Fail "record: the record is empty" }
  if ([System.IO.File]::ReadAllText($RL).Contains("`r")) { Fail "record: the record has carriage returns" }
  # the record is no marker: the slot status does not see it
  $p = Porc
  if (($p -join "|") -cne "1${T}free|2${T}free") { Fail "record: the status changed with a record: $($p -join ' | ')" }
  Remove-Item Env:NIGHTMILL_CLOCK_FILE
  Claim-Reset

  Write-Host "== slot numbers take only digits (bug 128)"
  # -Slot, -Release and -Abandon accept only digits and normalise them (02 is slot 2); anything else prints the usage
  # line, exits 1 and changes nothing
  Reset-Gh
  $r = SlotE '-Take feat/n1 -Slot 02'
  if ($r.Code -ne 0 -or -not $r.Out.Contains('Slot 2 is yours')) { Fail "number: -Take -Slot 02: exit $($r.Code): $($r.Out) / $($r.Err)" }
  if ((Test-Path "$tmp\wt\slot-02") -or (Test-Path "$S1\slot-02.json")) { Fail 'number: -Take -Slot 02 made slot-02' }
  if ((MGet 2 'slot') -ne '2') { Fail "number: the marker of -Slot 02: $(MText 2)" }
  $r = SlotE '-Abandon 02'
  if ($r.Code -ne 0 -or (Test-Path (Marker 2))) { Fail "number: -Abandon 02: exit $($r.Code): $($r.Out) / $($r.Err)" }
  Reset-Gh
  $null = Slot -Take feat/n2 -Slot 2
  [System.IO.File]::WriteAllText("$tmp\wt\slot-2\number-n2.txt", "n2`n")
  git -C "$tmp\wt\slot-2" add -A
  git -C "$tmp\wt\slot-2" -c user.name=t -c user.email=t@example.invalid commit -qm 'work on feat/n2'
  Gq -C "$tmp\wt\slot-2" push -q origin feat/n2
  Merged feat/n2 28 (Get-Head 2)
  $r = SlotE '-Release 02'
  if ($r.Code -ne 0 -or -not $r.Out.Contains('Slot 2 is free (was feat/n2, PR #28).')) { Fail "number: -Release 02: exit $($r.Code): $($r.Out) / $($r.Err)" }
  if (Test-Path (Marker 2)) { Fail 'number: -Release 02 left the marker' }
  Reset-Gh
  $null = Slot -Take feat/n3 -Slot 2
  function Get-MList { (@(Get-ChildItem -LiteralPath $S1 -Name | Where-Object { $_ -notlike 'ledger*' }) | Sort-Object) -join ' ' }
  $before = Get-MList; $m2 = MText 2
  foreach ($v in '1x', '-1', '""') {
    foreach ($a in '-Take feat/n4 -Slot', '-Release', '-Abandon') {
      $r = SlotE "$a $v"
      if ($r.Code -ne 1) { Fail "number: $a $v`: exit $($r.Code): $($r.Err)" }
      if ($r.Err -notmatch '^usage: ') { Fail "number: $a $v`: no usage line: $($r.Err)" }
      if ($r.Out) { Fail "number: $a $v`: printed $($r.Out)" }
      if ((Get-MList) -cne $before -or (MText 2) -cne $m2) { Fail "number: $a $v changed the markers: $(Get-MList)" }
    }
  }
  if (Test-Path "$tmp\wt\slot-1x") { Fail 'number: a slot directory was made for 1x' }
  $null = Slot -Abandon 2
  Gq -C $work branch -D feat/n1 feat/n3

  Write-Host "== a broken slot directory is reported and refused (bug 129)"
  # A slot directory that is no git worktree (here: slot 2 and slot 3 replaced by plain directories) is reported as
  # broken by -Status, which lists every slot and exits 0, and refused with a message that says so by -Release,
  # -Abandon and -Take; nothing is fetched, queried, switched or removed.
  Reset-Gh
  $null = Slot -Take feat/b1 -Slot 1
  $null = Slot -Take feat/b2 -Slot 2
  $originMain = ([string](git -C $work rev-parse origin/main)).Trim()
  Merged feat/b2 41 $originMain
  foreach ($n in 2, 3) {
    Remove-Item -Recurse -Force "$tmp\wt\slot-$n" -ErrorAction SilentlyContinue
    New-Item -ItemType Directory "$tmp\wt\slot-$n" | Out-Null
    [System.IO.File]::WriteAllText("$tmp\wt\slot-$n\keep.txt", "keep`n")
  }
  $brokenRe = 'broken|not a git worktree'

  # -Status reports slot 2 as broken and goes on to slot 3
  $r = SlotE '-Status' @{ WORKER_SLOTS = 3 }
  if ($r.Code -ne 0) { Fail "broken: -Status exit $($r.Code), not 0: $($r.Out) / $($r.Err)" }
  if ($r.Out -notmatch '(?m)^slot 1 .*busy: feat/b1') { Fail "broken: -Status lost slot 1: $($r.Out)" }
  if ($r.Out -notmatch "(?m)^slot 2 .*($brokenRe)") { Fail "broken: -Status does not report slot 2 as broken: $($r.Out) / $($r.Err)" }
  if ($r.Out -notmatch "(?m)^slot 3 .*($brokenRe)") { Fail "broken: -Status stopped before slot 3 or does not report it as broken: $($r.Out) / $($r.Err)" }

  # -Release refuses before it fetches or asks gh
  Reset-Gh; Merged feat/b2 41 $originMain
  $r = SlotE '-Release 2'
  if ($r.Code -ne 1) { Fail "broken: -Release exit $($r.Code), not 1: $($r.Out) / $($r.Err)" }
  if ($r.Err -notmatch "(?i)slot 2.*($brokenRe)|($brokenRe).*slot 2") { Fail "broken: -Release gave no clear message: $($r.Err)" }
  if ((Get-Item $ghLog).Length -gt 0) { Fail "broken: -Release asked gh before refusing: $([System.IO.File]::ReadAllText($ghLog))" }
  if (-not (Test-Path (Marker 2))) { Fail 'broken: -Release removed the marker' }
  if (-not (Test-Path "$tmp\wt\slot-2\keep.txt")) { Fail 'broken: -Release touched the directory' }

  # -Abandon refuses, the marker stays
  $r = SlotE '-Abandon 2'
  if ($r.Code -ne 1) { Fail "broken: -Abandon exit $($r.Code), not 1: $($r.Out) / $($r.Err)" }
  if ($r.Err -notmatch "(?i)slot 2.*($brokenRe)|($brokenRe).*slot 2") { Fail "broken: -Abandon gave no clear message: $($r.Err)" }
  if (-not (Test-Path (Marker 2))) { Fail 'broken: -Abandon removed the marker' }
  if (-not (Test-Path "$tmp\wt\slot-2\keep.txt")) { Fail 'broken: -Abandon touched the directory' }

  # -Take refuses with the message, not with a failed switch, and leaves the slot free
  $r = SlotE '-Take feat/b3 -Slot 3' @{ WORKER_SLOTS = 3 }
  if ($r.Code -ne 1) { Fail "broken: -Take exit $($r.Code), not 1: $($r.Out) / $($r.Err)" }
  if ($r.Err -notmatch "(?i)slot 3.*($brokenRe)|($brokenRe).*slot 3") { Fail "broken: -Take gave no clear message: $($r.Err)" }
  if ($r.Err -match 'failed \(exit') { Fail "broken: -Take failed at a git step instead of refusing: $($r.Err)" }
  if (Test-Path (Marker 3)) { Fail 'broken: -Take left a marker for slot 3' }
  if (-not (Test-Path "$tmp\wt\slot-3\keep.txt")) { Fail 'broken: -Take touched the directory' }
  if (Test-Branch $work 'feat/b3') { Fail 'broken: -Take made the branch' }

  $null = Slot -Abandon 1
  Remove-Item (Marker 2) -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force "$tmp\wt\slot-2", "$tmp\wt\slot-3" -ErrorAction SilentlyContinue
  Gq -C $work worktree prune
  Gq -C $work branch -D feat/b1 feat/b2
  Reset-Gh

  Write-Host "== the config comes from the base branch (iteration 48)"
  $utf8n = New-Object System.Text.UTF8Encoding $false
  function Cfg-Text([string]$base, [string]$warm, [string]$inv) {
    @"
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "invariants": [ "$inv" ],
  "git": { "baseBranch": "$base" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "warmup": [ { "dir": "client", "command": "$warm", "lockfile": "client/lock.txt" } ]
  }
}
"@
  }
  function Mk-Base([string]$name, [string]$base, [string]$warm, [string]$inv = "plain") {
    $d = "$tmp\$name"
    New-Item -ItemType Directory "$d\work\.claude", "$d\work\client", "$d\origin.git" | Out-Null
    Gq -C "$d\origin.git" init -q --bare
    Gq -C "$d\work" init -q -b main
    Gq -C "$d\work" config core.autocrlf false
    [System.IO.File]::WriteAllText("$d\work\.claude\nightmill.json", (Cfg-Text $base $warm $inv), $utf8n)
    [System.IO.File]::WriteAllText("$d\work\client\lock.txt", "v1`n")
    Gq -C "$d\work" add -A
    Gq -C "$d\work" -c user.name=t -c user.email=t@example.invalid commit -qm init
    Gq -C "$d\work" remote add origin "$d\origin.git"
    Gq -C "$d\work" push -q origin main
    Gq -C "$d\work" remote set-head origin main
  }
  # SlotIn <name> <arguments>: slot.ps1 started in the main checkout of that repository; Out, Err, Code
  function SlotIn([string]$name, [string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$S`" $arguments"
    $psi.WorkingDirectory = "$tmp\$name\work"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Out = ($out -replace "`r`n", "`n"); Err = ($errTask.Result -replace "`r`n", "`n"); Code = $p.ExitCode }
  }

  Write-Host "-- the warm-up comes from the base, not from the working tree"
  Mk-Base "cb1" "main" "Set-Content warmed.txt warm"
  [System.IO.File]::WriteAllText("$tmp\cb1\work\.claude\nightmill.json", (Cfg-Text "main" "Set-Content evil.txt evil" "plain"), $utf8n)
  $r = SlotIn "cb1" "-Take feat/a"
  if ($r.Code -ne 0) { Fail "base config: the take exited $($r.Code): $($r.Out) / $($r.Err)" }
  if (-not (Test-Path "$tmp\cb1\wt\slot-1\client\warmed.txt")) { Fail "base config: the warm-up of the pushed config did not run" }
  if (@(Get-ChildItem "$tmp\cb1\wt" -Recurse -Filter evil.txt -ErrorAction SilentlyContinue).Count -ne 0) { Fail "base config: the warm-up of the uncommitted working-tree config ran" }

  Write-Host "-- the base branch hop: git.baseBranch of origin/HEAD names the branch whose config is read"
  Mk-Base "cb2" "trunk" "Set-Content warmed.txt warm"
  Gq -C "$tmp\cb2\work" switch -q -c trunk
  [System.IO.File]::WriteAllText("$tmp\cb2\work\.claude\nightmill.json", (Cfg-Text "trunk" "Set-Content trunk.txt hop" "plain"), $utf8n)
  Gq -C "$tmp\cb2\work" -c user.name=t -c user.email=t@example.invalid commit -qam "trunk config"
  Gq -C "$tmp\cb2\work" push -q origin trunk
  Gq -C "$tmp\cb2\work" switch -q main
  $r = SlotIn "cb2" "-Take feat/a"
  if ($r.Code -ne 0) { Fail "base hop: the take exited $($r.Code): $($r.Out) / $($r.Err)" }
  if (-not (Test-Path "$tmp\cb2\wt\slot-1\client\trunk.txt")) { Fail "base hop: the warm-up of origin/trunk did not run" }
  if (Test-Path "$tmp\cb2\wt\slot-1\client\warmed.txt") { Fail "base hop: the warm-up of origin/HEAD's config ran" }
  Mk-Base "cb2b" "nope" "Set-Content warmed.txt warm"
  $r = SlotIn "cb2b" "-Take feat/a"
  if ($r.Code -ne 1) { Fail "base hop: a base branch with no config: exit $($r.Code), not 1: $($r.Out) / $($r.Err)" }
  if (-not $r.Err.Contains("origin/nope has no .claude/nightmill.json (git.baseBranch of the configuration on origin/HEAD)")) { Fail "base hop: wrong stop line: $($r.Err)" }

  Write-Host "-- no origin/HEAD stops with the set-head line"
  Mk-Base "cb3" "main" "Set-Content warmed.txt warm"
  Gq -C "$tmp\cb3\work" remote set-head origin --delete
  $r = SlotIn "cb3" "-Status"
  if ($r.Code -ne 1) { Fail "no origin/HEAD: -Status exit $($r.Code), not 1: $($r.Out) / $($r.Err)" }
  if (-not $r.Err.Contains("origin/HEAD is not set, so the base branch's configuration cannot be found; run git remote set-head origin --auto once")) { Fail "no origin/HEAD: wrong line: $($r.Err)" }

  Write-Host "-- offline: no remote branch, the working-tree file is read"
  New-Item -ItemType Directory "$tmp\cb4\work\.claude" | Out-Null
  Gq -C "$tmp\cb4\work" init -q -b main
  [System.IO.File]::WriteAllText("$tmp\cb4\work\.claude\nightmill.json", (Cfg-Text "main" "Set-Content warmed.txt warm" "plain"), $utf8n)
  $r = SlotIn "cb4" "-Status"
  if ($r.Code -ne 0) { Fail "offline: -Status exit $($r.Code): $($r.Out) / $($r.Err)" }
  if (-not $r.Err.Contains("nightmill: no branch of origin is known; the configuration is read from the working tree.")) { Fail "offline: wrong line: $($r.Err)" }
  if (-not $r.Out.StartsWith("slots = 2")) { Fail "offline: the working-tree config was not used: $($r.Out)" }

  Write-Host "-- no file on the base: the working-tree file, with the line"
  Mk-Base "cb5" "main" "Set-Content warmed.txt warm"
  Gq -C "$tmp\cb5\work" rm -q --cached .claude/nightmill.json
  Gq -C "$tmp\cb5\work" -c user.name=t -c user.email=t@example.invalid commit -qm "no config"
  Gq -C "$tmp\cb5\work" push -q origin main
  $r = SlotIn "cb5" "-Status"
  if ($r.Code -ne 0) { Fail "no file on the base: -Status exit $($r.Code): $($r.Out) / $($r.Err)" }
  if (-not $r.Err.Contains("nightmill: origin/HEAD has no .claude/nightmill.json; the configuration is read from the working tree.")) { Fail "no file on the base: wrong line: $($r.Err)" }
  if (-not $r.Out.StartsWith("slots = 2")) { Fail "no file on the base: the working-tree config was not used: $($r.Out)" }

  Write-Host "-- a base config with a non-ASCII value works"
  Mk-Base "cb6" "main" "Set-Content warmed.txt warm" ("Generic " + [char]0x2014 + " no private words")
  $r = SlotIn "cb6" "-Status"
  if ($r.Code -ne 0) { Fail "UTF-8: -Status exit $($r.Code): $($r.Out) / $($r.Err)" }
  if (-not $r.Out.StartsWith("slots = 2")) { Fail "UTF-8: unexpected status: $($r.Out)" }

  Write-Host "SMOKE OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

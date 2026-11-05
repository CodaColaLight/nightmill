# tests/smoke-slot.ps1 - slot.ps1 against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon, and the automatic release of a slot whose pull
# request has merged (-Reap and the first step of every -Take), with -Release, against a fake gh.
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

  Write-Host "SMOKE OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

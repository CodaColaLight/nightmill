# tests/test-slot-low-defects.ps1 - bug 322 (split from 140), PowerShell twin of test-slot-low-defects.sh: the
# low-severity defects of slot.ps1 and new-worktree.ps1.
#   1 -Release trusts any merged PR with the head name: it compares headRefOid with the branch tip (as -Reap does)
#   2 -Release and -Abandon refuse a slot whose branch is not the marker's branch
#   3 slot.sh --status creates the worktree root (bash only; slot.ps1 -Status must keep not creating it)
#   4 git older than 2.31 gets a message that names the version, not "run from inside a git checkout"
#   5 gh never prompts: GH_PROMPT_DISABLED is set for -Reap and -Release
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$S = Join-Path $here "scripts\slot.ps1"
$N = Join-Path $here "scripts\new-worktree.ps1"
$psExe = (Get-Command powershell).Source
$realGit = (Get-Command git).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-slotlow-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null
$script:bad = 0
function Bad($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:bad++ }

# Run <script> <arguments> <workdir> [environment]: a child process with standard error kept apart; Out, Err, Code
function Run([string]$script, [string]$arguments, [string]$dir, [hashtable]$extraEnv = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $arguments"
  $psi.WorkingDirectory = $dir
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
function Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false)) }

# A fake gh: "pr list" answers from $env:GH_FIX\merged.txt (branch TAB number TAB head commit), prints only the
# requested --json fields, and logs every call with the value of GH_PROMPT_DISABLED it saw.
$bin = Join-Path $tmp "bin"; $fix = Join-Path $tmp "fix"
New-Item -ItemType Directory $bin, $fix | Out-Null
$ghLog = Join-Path $tmp "gh.log"
Utf8 (Join-Path $fix "merged.txt") ""
Utf8 $ghLog ""
Utf8 (Join-Path $bin "gh-fake.ps1") @'
Add-Content -Path $env:GH_LOG -Value ("prompt=[" + $env:GH_PROMPT_DISABLED + "] " + ($args -join " "))
if ("$($args[0]) $($args[1])" -ne "pr list") { [Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')"); exit 1 }
$state = ""; $head = ""; $fields = "number"
for ($i = 2; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    "--state" { $state = $args[$i + 1]; $i++ }
    "--head" { $head = $args[$i + 1]; $i++ }
    "--json" { $fields = $args[$i + 1]; $i++ }
  }
}
if ($state -ne "merged") { [Console]::Out.Write("[]"); exit 0 }
$f = $null
foreach ($line in [IO.File]::ReadAllLines((Join-Path $env:GH_FIX "merged.txt"))) {
  $c = $line -split "`t"
  if ($c.Count -ge 3 -and $c[0] -ceq $head -and -not $f) { $f = $c }
}
if (-not $f) { [Console]::Out.Write("[]"); exit 0 }
$parts = @()
foreach ($fld in ($fields -split ",")) {
  switch ($fld) {
    "number" { $parts += '"number":' + $f[1] }
    "headRefOid" { $parts += '"headRefOid":"' + $f[2] + '"' }
    "createdAt" { $parts += '"createdAt":""' }
    "mergedAt" { $parts += '"mergedAt":""' }
    "closingIssuesReferences" { $parts += '"closingIssuesReferences":[]' }
  }
}
[Console]::Out.Write("[{" + ($parts -join ",") + "}]")
exit 0
'@
Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n"
$env:PATH = "$bin;" + $env:PATH
$env:GH_FIX = $fix
$env:GH_LOG = $ghLog
Remove-Item Env:GH_PROMPT_DISABLED -ErrorAction SilentlyContinue

# MkRepo <name> <worktree root>: a repository with an origin, the configuration on main and origin/HEAD set
function MkRepo([string]$name, [string]$root) {
  git init -q --bare "$tmp\$name-origin.git"
  git init -q -b main "$tmp\$name"
  New-Item -ItemType Directory "$tmp\$name\.claude" | Out-Null
  Utf8 "$tmp\$name\.claude\nightmill.json" ('{ "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 }, "maintainer": { "name": "Alex" }, "verification": { "check": "true" }, "git": { "baseBranch": "main" }, "worktrees": { "root": "' + $root + '", "slots": 3 } }')
  git -C "$tmp\$name" config core.autocrlf false
  git -C "$tmp\$name" add -A
  git -C "$tmp\$name" -c user.name=t -c user.email=t@example.invalid commit -qm init
  git -C "$tmp\$name" remote add origin "$tmp\$name-origin.git"
  git -C "$tmp\$name" push -q origin main 2>$null
  git -C "$tmp\$name" remote set-head origin main
}
# WorkCommit <slot dir> <branch>: a commit on the branch, pushed
function WorkCommit([string]$dir, [string]$branch) {
  Utf8 "$dir\work.txt" $branch
  git -C $dir add -A
  git -C $dir -c user.name=t -c user.email=t@example.invalid commit -qm work
  git -C $dir push -q origin $branch 2>$null
}
function Merged([string]$branch, [int]$num, [string]$oid) { Utf8 (Join-Path $fix "merged.txt") "$branch`t$num`t$oid`n" }
function Tip([string]$dir) { ((git -C $dir rev-parse HEAD) | Out-String).Trim() }

try {
  MkRepo "work" "../wt"
  $work = "$tmp\work"; $wt = "$tmp\wt"; $slots = "$wt\.slots"

  Write-Host "== -Release does not trust a merged PR whose head commit is not the branch tip"
  $r = Run $S "-Take feat/a -Slot 1" $work
  if ($r.Code -ne 0) { Bad "take feat/a: exit $($r.Code): $($r.Err)" }
  WorkCommit "$wt\slot-1" "feat/a"
  Merged "feat/a" 9 "0000000000000000000000000000000000000000"
  $r = Run $S "-Release 1" $work
  if ($r.Code -eq 0) { Bad "release freed the slot for a merged PR with another head commit: $($r.Out)" }
  if (-not (Test-Path "$slots\slot-1.json")) { Bad "release removed the marker for a merged PR with another head commit" }
  if (Test-Path "$slots\slot-1.json") {
    Merged "feat/a" 9 (Tip "$wt\slot-1")
    $r = Run $S "-Release 1" $work
    if ($r.Code -ne 0) { Bad "release refused a merged PR whose head commit is the branch tip: $($r.Err)" }
    if (Test-Path "$slots\slot-1.json") { Bad "release left the marker of a matching merged PR" }
  }

  Write-Host "== -Release and -Abandon refuse a slot on another branch than the marker's"
  $r = Run $S "-Take feat/b -Slot 2" $work
  if ($r.Code -ne 0) { Bad "take feat/b: exit $($r.Code): $($r.Err)" }
  WorkCommit "$wt\slot-2" "feat/b"
  # every take reaps first: the merged PR of feat/b is written only after the last take, or the reap would free slot 2
  $r = Run $S "-Take feat/c -Slot 3" $work
  if ($r.Code -ne 0) { Bad "take feat/c: exit $($r.Code): $($r.Err)" }
  WorkCommit "$wt\slot-3" "feat/c"
  git -C "$wt\slot-2" switch -q -c feat/other
  git -C "$wt\slot-3" switch -q -c feat/other3
  Merged "feat/b" 10 (Tip "$wt\slot-2")
  $r = Run $S "-Release 2" $work
  if ($r.Code -eq 0) { Bad "release freed a slot whose branch is not the marker's: $($r.Out)" }
  if (-not (Test-Path "$slots\slot-2.json")) { Bad "release removed the marker of a slot on another branch" }
  $r = Run $S "-Abandon 3" $work
  if ($r.Code -eq 0) { Bad "abandon freed a slot whose branch is not the marker's: $($r.Out)" }
  if (-not (Test-Path "$slots\slot-3.json")) { Bad "abandon removed the marker of a slot on another branch" }

  Write-Host "== -Status does not create the worktree root (slot.sh used to)"
  MkRepo "ro" "../ro-wt"
  $r = Run $S "-Status" "$tmp\ro"
  if ($r.Code -ne 0) { Bad "status: exit $($r.Code): $($r.Err)" }
  if (Test-Path "$tmp\ro-wt") { Bad "-Status created the worktree root $tmp\ro-wt" }

  Write-Host "== git older than 2.31 is named in the message"
  $old = Join-Path $tmp "oldgit"
  New-Item -ItemType Directory $old | Out-Null
  Utf8 (Join-Path $old "git.cmd") ("@echo off`r`nif `"%1`"==`"--version`" (echo git version 2.30.1& exit /b 0)`r`necho %* | findstr /c:`"--path-format`" >nul && (echo fatal: unknown option: --path-format=absolute 1>&2& exit /b 129)`r`n`"$realGit`" %*`r`nexit /b %errorlevel%`r`n")
  foreach ($case in @(@("slot.ps1", $S, "-Status"), @("new-worktree.ps1", $N, "-Branch feat/x"))) {
    $r = Run $case[1] $case[2] $work @{ PATH = "$old;$env:PATH" }
    if ($r.Code -eq 0) { Bad "$($case[0]): old git was accepted" }
    if (($r.Err + $r.Out) -notmatch "2\.30\.1") { Bad "$($case[0]): the message does not name the git version: $($r.Err)" }
  }

  Write-Host "== gh is called with GH_PROMPT_DISABLED set (-Reap and -Release)"
  MkRepo "gp" "../gp-wt"
  $gp = "$tmp\gp"; $gpw = "$tmp\gp-wt"
  $null = Run $S "-Take feat/p -Slot 1" $gp
  WorkCommit "$gpw\slot-1" "feat/p"
  Merged "feat/p" 11 (Tip "$gpw\slot-1")
  Utf8 $ghLog ""
  $null = Run $S "-Reap" $gp
  $log = [IO.File]::ReadAllText($ghLog)
  if ($log -notmatch "pr list") { Bad "-Reap did not call gh" }
  if ($log -match "prompt=\[\]") { Bad "-Reap called gh without GH_PROMPT_DISABLED: $log" }
  $null = Run $S "-Take feat/q -Slot 1" $gp
  WorkCommit "$gpw\slot-1" "feat/q"
  Merged "feat/q" 12 (Tip "$gpw\slot-1")
  Utf8 $ghLog ""
  $null = Run $S "-Release 1" $gp
  $log = [IO.File]::ReadAllText($ghLog)
  if ($log -notmatch "pr list") { Bad "-Release did not call gh" }
  if ($log -match "prompt=\[\]") { Bad "-Release called gh without GH_PROMPT_DISABLED: $log" }
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:bad -gt 0) { exit 1 }
Write-Host "ok"

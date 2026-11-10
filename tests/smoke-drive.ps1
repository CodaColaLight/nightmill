# tests/smoke-drive.ps1 - scripts/drive.ps1 against a fake claude, a fake gh and throwaway slots (iteration 52, #164;
# docs/specs/iteration-52-unattended-driver.md, "Tests"): the same cases as tests/smoke-drive.sh, except `signal`
# (bash only). The fakes are .cmd files that call a .ps1, first on the PATH. Each case runs the driver in a child
# powershell process in the main checkout.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$D = Join-Path $here "scripts\drive.ps1"
$psExe = (Get-Command powershell).Source
# the Git helper below has the name of the program: resolve the program itself, a function would call itself
$script:gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nightmill-smoke-drive-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$fx = Join-Path $PSScriptRoot "fixtures\drive"
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
if (-not (Test-Path $D)) { Fail "scripts/drive.ps1 does not exist" }
$bin = Join-Path $tmp "bin"; New-Item -ItemType Directory -Path $bin | Out-Null
$runs = Join-Path $tmp "runs"; New-Item -ItemType Directory -Path $runs | Out-Null

# --- the fake gh ---
$ghPs = @'
$a = $args
Add-Content -Path $env:GH_LOG -Value ($a -join ' ')
$k = ($a | Select-Object -First 2) -join ' '
if ($k -eq 'auth status') { if ($env:GH_AUTH_FAIL) { [Console]::Error.WriteLine('fake gh: not logged in'); exit 1 }; exit 0 }
if ($k -eq 'project item-list') {
  $items = @()
  foreach ($l in (Get-Content $env:BOARD)) {
    if (-not $l) { continue }
    $f = $l -split "`t"
    $o = [ordered]@{ id = "PVTI_$($f[0])"; content = @{ number = [int]$f[0]; title = $f[4]; type = 'Issue' }; labels = @($f[3]); status = $f[1]; title = $f[4] }
    if ($f[2]) { $o['priority'] = $f[2] }
    $items += $o
  }
  @{ items = $items; totalCount = $items.Count } | ConvertTo-Json -Depth 6 -Compress
  exit 0
}
if ($k -eq 'pr list') {
  $prs = @()
  foreach ($l in (Get-Content $env:PRS)) {
    if (-not $l) { continue }
    $f = $l -split "`t"
    $prs += [ordered]@{ number = [int]$f[0]; state = $f[1]; headRefName = "b$($f[0])"; closingIssuesReferences = @(@{ number = [int]$f[2] }) }
  }
  if ($prs.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $prs -Depth 6 -Compress }
  exit 0
}
if ($k -eq 'issue comment') {
  if ($env:GH_COMMENT_FAIL) { [Console]::Error.WriteLine('fake gh: comment refused'); exit 1 }
  for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -eq '--body-file') { Copy-Item $a[$i + 1] $env:COMMENT -Force } }
  exit 0
}
[Console]::Error.WriteLine('fake gh: unexpected call'); exit 1
'@
[IO.File]::WriteAllText((Join-Path $bin "gh.ps1"), $ghPs)
[IO.File]::WriteAllText((Join-Path $bin "gh.cmd"), "@echo off`r`n`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n")

# --- the fake claude: one line of $SCRIPT per step ---
$clPs = @'
$a = $args
Add-Content -Path $env:CLAUDE_LOG -Value ($a -join ' ')
$k = 0
if (Test-Path $env:STEPFILE) { $k = [int](Get-Content $env:STEPFILE | Select-Object -First 1) }
$k++
Set-Content -Path $env:STEPFILE -Value $k
$line = @(Get-Content $env:SCRIPT)[$k - 1]
$cost = '0.10'; $turns = 3; $code = 0; $stopped = ''; $long = $false
foreach ($x in ($line -split ' ')) {
  if ($x -like 'status:*') {
    $p = $x -split ':'
    $rows = foreach ($l in (Get-Content $env:BOARD)) { $f = $l -split "`t"; if ($f[0] -eq $p[1]) { $f[1] = ($p[2] -replace '_', ' ') }; $f -join "`t" }
    Set-Content -Path $env:BOARD -Value $rows
  }
  elseif ($x -like 'pr:*') { $p = $x -split ':'; Add-Content -Path $env:PRS -Value ("{0}`t{1}`t{2}" -f $p[1], $p[2], $p[3]) }
  elseif ($x -eq 'stop') { New-Item -ItemType File -Path $env:STOPFILE -Force | Out-Null }
  elseif ($x -like 'clock:*') { $v = [long](Get-Content $env:NIGHTMILL_CLOCK_FILE | Select-Object -First 1); Set-Content -Path $env:NIGHTMILL_CLOCK_FILE -Value ($v + [long]($x.Substring(7))) }
  elseif ($x -eq 'bg') { $bp = Start-Process -FilePath powershell -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 300' -WindowStyle Hidden -PassThru; Set-Content -Path $env:BGPID -Value $bp.Id }
  elseif ($x -like 'exit:*') { $code = [int]$x.Substring(5) }
  elseif ($x -like 'stopped:*') { $stopped = ($x.Substring(8) -replace '_', ' ') }
  elseif ($x -like 'cost:*') { $cost = $x.Substring(5) }
  elseif ($x -like 'turns:*') { $turns = [int]$x.Substring(6) }
  elseif ($x -eq 'long') { $long = $true }
}
if ($long) { $msg = 'x' * 70000 }
else { $msg = "Done with step $k."; if ($stopped) { $msg += "\nStopped: $stopped" } else { $msg += "\nAll good." } }
Write-Output ('{"type":"result","result":"' + $msg + '","total_cost_usd":' + $cost + ',"num_turns":' + $turns + '}')
exit $code
'@
[IO.File]::WriteAllText((Join-Path $bin "claude.ps1"), $clPs)
[IO.File]::WriteAllText((Join-Path $bin "claude.cmd"), "@echo off`r`n`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0claude.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n")

function Git { $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $script:gitExe @args 2>&1 | Out-Null } finally { $ErrorActionPreference = $ea } }
$script:n = 0
$script:c = ""; $script:main = ""
# New-Case <extra json member or $null> [slots] [roomCheck]
function New-Case($extra = '"unattended": { "summaryIssue": 9, "maxMinutes": 60 }', [int]$slots = 2, [string]$room = "false") {
  $script:n++
  $c = Join-Path $tmp "case$($script:n)"; $script:c = $c
  New-Item -ItemType Directory -Path $c | Out-Null
  Git init -q --bare -b main (Join-Path $c "origin.git")
  Git clone -q (Join-Path $c "origin.git") (Join-Path $c "main")
  $m = Join-Path $c "main"; $script:main = $m
  Git -C $m config user.email t@example.com; Git -C $m config user.name t
  Git -C $m checkout -q -b main
  New-Item -ItemType Directory -Path (Join-Path $m ".claude") | Out-Null
  $tail = ""; if ($extra) { $tail = ",`n  $extra" }
  $cfg = "{`n  `"github`": { `"owner`": `"acme`", `"repo`": `"widgets`", `"projectNumber`": 1 },`n  `"maintainer`": { `"name`": `"Alex`" },`n  `"verification`": { `"check`": `"true`" },`n  `"worktrees`": { `"root`": `"../wt`", `"slots`": $slots },`n  `"parallel`": { `"roomCheck`": $room }$tail`n}`n"
  [IO.File]::WriteAllText((Join-Path $m ".claude\nightmill.json"), $cfg)
  Git -C $m add -A; Git -C $m commit -q -m init; Git -C $m push -q origin main
  Git -C $m remote set-head origin main; Git -C $m fetch -q origin
  $env:BOARD = Join-Path $c "board.tsv"; $env:PRS = Join-Path $c "prs.tsv"; $env:SCRIPT = Join-Path $c "script.txt"
  $env:GH_LOG = Join-Path $c "gh.log"; $env:CLAUDE_LOG = Join-Path $c "claude.log"; $env:COMMENT = Join-Path $c "comment.md"
  $env:STEPFILE = Join-Path $c "step.n"; $env:BGPID = Join-Path $c "bg.pid"
  $env:NIGHTMILL_CLOCK_FILE = Join-Path $c "clock"; $env:STOPFILE = Join-Path $m ".git\nightmill-stop"
  Set-Content $env:PRS ""; Set-Content $env:SCRIPT ""; Set-Content $env:NIGHTMILL_CLOCK_FILE "1800000000"
  Remove-Item Env:GH_AUTH_FAIL, Env:GH_COMMENT_FAIL -ErrorAction SilentlyContinue
}
function Use-Board($name) { Copy-Item (Join-Path $fx $name) $env:BOARD -Force }
function Set-Script([string[]]$lines) { Set-Content -Path $env:SCRIPT -Value $lines }
function Invoke-Drive([string]$driver = $D) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$driver`""
  $psi.WorkingDirectory = $script:main
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables["PATH"] = $bin + ";" + $env:PATH
  $psi.EnvironmentVariables["TMP"] = $runs; $psi.EnvironmentVariables["TEMP"] = $runs
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $script:out = $o.Result; $script:err = $e.Result; $script:code = $p.ExitCode
}
function Calls { if (Test-Path $env:CLAUDE_LOG) { @(Get-Content $env:CLAUDE_LOG).Count } else { 0 } }
function Has($text, [string]$needle, [string]$what) { if (-not $text.Contains($needle)) { Fail "${what}: '$needle' not found" } }
function Hasnt($text, [string]$needle, [string]$what) { if ($text -and $text.Contains($needle)) { Fail "${what}: '$needle' found" } }
function Want-Code([int]$expected, [string]$what) { if ($script:code -ne $expected) { Fail "${what}: exit $($script:code), $expected expected ($($script:err))" } }
function Comment { if (Test-Path $env:COMMENT) { [IO.File]::ReadAllText($env:COMMENT) } else { "" } }
function Need-Comment([string]$what) { if (-not (Test-Path $env:COMMENT)) { Fail "${what}: no comment was posted" } }
function Audit([string]$what) {
  if (Test-Path $env:GH_LOG) {
    foreach ($l in (Get-Content $env:GH_LOG)) {
      if (-not ($l.StartsWith("auth status") -or $l.StartsWith("project item-list") -or $l.StartsWith("pr list") -or $l.StartsWith("issue comment"))) { Fail "${what}: a gh call the driver may not make: $l" }
    }
  }
  if (Test-Path (Join-Path $script:main ".git\nightmill-drive.lock")) { Fail "${what}: the lock is left" }
}
$FIX = '-p /nightmill:fix all --permission-mode manual --output-format json'

# nothing
New-Case; Use-Board "board-nothing.tsv"; Invoke-Drive
Want-Code 0 "nothing"; if ((Calls) -ne 0) { Fail "nothing: claude was called" }
Need-Comment "nothing"; $cm = Comment
Has $cm "Ended: nothing Ready or Approved." "nothing"; Has $cm "Ready stories wait for /spec: #31" "nothing"; Audit "nothing"

# loop
New-Case; Use-Board "board-loop.tsv"
Set-Script "status:11:Review pr:101:OPEN:11 cost:0.50 turns:4", "status:21:Done pr:121:MERGED:21 cost:1.25", "status:22:Done pr:122:MERGED:22 cost:1.25"
Invoke-Drive
Want-Code 0 "loop"
$cl = @(Get-Content $env:CLAUDE_LOG)
if ($cl.Count -ne 3) { Fail "loop: $($cl.Count) claude calls, 3 expected" }
if ($cl[0] -ne $FIX) { Fail "loop: first call: $($cl[0])" }
if ($cl[1] -ne '-p /nightmill:next 21 --permission-mode manual --output-format json') { Fail "loop: second call: $($cl[1])" }
if ($cl[2] -ne '-p /nightmill:next 22 --permission-mode manual --output-format json') { Fail "loop: third call: $($cl[2])" }
Need-Comment "loop"; $cm = Comment
Has $cm "| #11 Crash on start | /fix all | Ready | Review | pull request open | #101 |" "loop"
Has $cm "| #21 Add export | /next | Approved | Done | merged | #121 |" "loop"
Has $cm "| #22 Add import | /next | Approved | Done | merged | #122 |" "loop"
Has $cm "Picked 3, merged 2, pull request open 1, blocked 0, not started 0." "loop"
Has $cm 'Cost: $3.00 in all' "loop"
Has $cm '1. /nightmill:fix all: exit 0, ' "loop"
Has $cm '$0.50, 4 turns.' "loop"
$nd = ([regex]::Matches($cm, '<details><summary>Final message of ')).Count
if ($nd -ne 3) { Fail "loop: $nd details blocks, 3 expected" }
Has $cm "Processes: none left running." "loop"
Has $script:out "drive: summary posted to #9" "loop"
Has $script:out "drive: run files in " "loop"
Hasnt $cm $tmp "loop: the comment names a local path"
Audit "loop"

# blocked
New-Case; Use-Board "board-loop.tsv"
Set-Script "status:11:Review pr:101:OPEN:11", "status:21:In_progress stopped:the_check_is_red", "status:22:Done pr:122:MERGED:22"
Invoke-Drive
Want-Code 0 "blocked"; $cm = Comment
Has $cm "| #21 Add export | /next | Approved | In progress | blocked: Stopped: the check is red | - |" "blocked"
if ((@(Get-Content $env:CLAUDE_LOG))[2] -ne '-p /nightmill:next 22 --permission-mode manual --output-format json') { Fail "blocked: #22 was not tried" }
Audit "blocked"

# tie
New-Case; Use-Board "board-tie.tsv"; Invoke-Drive
Want-Code 0 "tie"
if ((Test-Path $env:CLAUDE_LOG) -and ((Get-Content $env:CLAUDE_LOG | Out-String).Contains('nightmill:next'))) { Fail "tie: /next was called" }
$line = "a tie of priorities among the Approved stories #21, #23 (High); the maintainer sets one higher"
Has $script:out $line "tie"; Has (Comment) $line "tie"; Audit "tie"

# tried once
New-Case; Use-Board "board-loop.tsv"; Set-Script "cost:0.10"; Invoke-Drive
Want-Code 0 "tried once"
$nf = @(Get-Content $env:CLAUDE_LOG | Where-Object { $_.Contains('nightmill:fix all') }).Count
if ($nf -ne 1) { Fail "tried once: /fix all ran $nf times" }
$cm = Comment
Has $cm "nothing new to pick: every Ready bug and Approved story left was tried in this run" "tried once"
Has $cm "| /fix all | Ready | Ready | not started" "tried once"; Audit "tried once"

# time limit
New-Case '"unattended": { "summaryIssue": 9, "maxMinutes": 1 }'; Use-Board "board-loop.tsv"; Set-Script "clock:+61"; Invoke-Drive
Want-Code 0 "time limit"; if ((Calls) -ne 1) { Fail "time limit: $(Calls) claude calls, 1 expected" }
Has (Comment) "the time limit of 1 minutes (unattended.maxMinutes) is reached" "time limit"; Audit "time limit"

# kill switch
New-Case; Use-Board "board-loop.tsv"; New-Item -ItemType File -Path $env:STOPFILE | Out-Null; Invoke-Drive
Want-Code 1 "kill switch"; if ((Calls) -ne 0) { Fail "kill switch: claude was called" }
Has $script:err "drive: cannot start: the kill switch is set (.git/nightmill-stop)" "kill switch"
Has (Comment) "Did not start: " "kill switch"; Audit "kill switch"

# kill switch later
New-Case; Use-Board "board-loop.tsv"; Set-Script "stop"; Invoke-Drive
Want-Code 0 "kill switch later"; if ((Calls) -ne 1) { Fail "kill switch later: $(Calls) claude calls, 1 expected" }
Has (Comment) "the kill switch is set (.git/nightmill-stop)" "kill switch later"
Remove-Item $env:STOPFILE -Force; Audit "kill switch later"

# no slot
New-Case $null 1; Use-Board "board-loop.tsv"
Push-Location $script:main
$oldPath = $env:PATH; $oldLog = $env:GH_LOG
$env:PATH = $bin + ";" + $env:PATH; $env:GH_LOG = Join-Path $tmp "setup.log"
$ea0 = $ErrorActionPreference; $ErrorActionPreference = "Continue"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "scripts\slot.ps1") -Take feat/held -SkipWarmup 2>&1 | Out-Null
$ErrorActionPreference = $ea0
$env:PATH = $oldPath; $env:GH_LOG = $oldLog
Pop-Location
Invoke-Drive
Want-Code 1 "no slot"; if ((Calls) -ne 0) { Fail "no slot: claude was called" }
Has $script:err "drive: cannot start: no free slot: all 1 slots are busy (1: " "no slot"; Audit "no slot"

# no room: a copy of scripts\ whose room.ps1 exits 3
New-Case $null 2 "true"; Use-Board "board-loop.tsv"
Copy-Item (Join-Path $here "scripts") (Join-Path $script:c "scripts") -Recurse
Set-Content (Join-Path $script:c "scripts\room.ps1") @('Write-Output "room: gave up after 1 minutes (stub)"', 'exit 3')
Invoke-Drive (Join-Path $script:c "scripts\drive.ps1")
Want-Code 1 "no room"; if ((Calls) -ne 0) { Fail "no room: claude was called" }
Has $script:err "drive: cannot start: no room on this machine: " "no room"; Audit "no room"

# lock
New-Case; Use-Board "board-loop.tsv"
$lock = Join-Path $script:main ".git\nightmill-drive.lock"
Set-Content $lock @("$PID", "2026-11-10T00:00:00Z")
Invoke-Drive
Want-Code 1 "lock"; if ((Calls) -ne 0) { Fail "lock: claude was called" }
Has $script:err "drive: cannot start: another driver runs for this repository (pid $PID, since " "lock"
if (-not (Test-Path $lock)) { Fail "lock: the other driver's lock was removed" }
Remove-Item $lock -Force

# stale lock
New-Case; Use-Board "board-nothing.tsv"
$sp = Start-Process -FilePath powershell -ArgumentList '-NoProfile', '-Command', 'exit 0' -WindowStyle Hidden -PassThru; $sp.WaitForExit()
Set-Content (Join-Path $script:main ".git\nightmill-drive.lock") @("$($sp.Id)", "2026-11-10T00:00:00Z")
Invoke-Drive
Want-Code 0 "stale lock"; Has $script:out "drive: removed a stale lock of pid $($sp.Id)" "stale lock"; Audit "stale lock"

# bad limit
function Bad-Limit([string]$members, [string]$msg) {
  New-Case "`"unattended`": { $members }"; Use-Board "board-loop.tsv"; Invoke-Drive
  Want-Code 2 "bad limit ($members)"; Has $script:err $msg "bad limit ($members)"
  if ((Test-Path $env:GH_LOG) -and ((Get-Item $env:GH_LOG).Length -gt 0)) { Fail "bad limit ($members): gh was called" }
  if (Test-Path $env:COMMENT) { Fail "bad limit ($members): a comment was posted" }
}
Bad-Limit '"maxMinutes": 0' "drive: unattended.maxMinutes must be a whole number from 1 to 1440, got 0"
Bad-Limit '"maxMinutes": "60"' 'drive: unattended.maxMinutes must be a whole number from 1 to 1440, got "60"'
Bad-Limit '"summaryIssue": 0' "drive: unattended.summaryIssue must be a whole number of at least 1, got 0"

# dirty
New-Case; Use-Board "board-loop.tsv"; Set-Content (Join-Path $script:main "stray.txt") "x"; Invoke-Drive
Want-Code 1 "dirty"; if ((Calls) -ne 0) { Fail "dirty: claude was called" }
Has $script:err "drive: cannot start: the main checkout is not on main with a clean tree" "dirty"

# gh
New-Case; Use-Board "board-loop.tsv"; $env:GH_AUTH_FAIL = "1"; Invoke-Drive
Want-Code 1 "gh"; if ((Calls) -ne 0) { Fail "gh: claude was called" }
Has $script:out "drive: summary not posted: gh is not signed in" "gh"
if ((Test-Path $env:GH_LOG) -and ((Get-Content $env:GH_LOG | Out-String).Contains("issue comment"))) { Fail "gh: an issue comment was made" }

# claude fails
New-Case; Use-Board "board-loop.tsv"; Set-Script "exit:3"; Invoke-Drive
Want-Code 1 "claude fails"; Has $script:out "claude exited 3 in /nightmill:fix all" "claude fails"
Has (Comment) "claude exited 3 in /nightmill:fix all" "claude fails"; Audit "claude fails"

# no issue
New-Case '"unattended": { "maxMinutes": 60 }'; Use-Board "board-nothing.tsv"; Invoke-Drive
Want-Code 0 "no issue"
Has $script:out "drive: summary not posted: unattended.summaryIssue is not set" "no issue"
Has $script:out "nightmill driver run" "no issue"
if ((Test-Path $env:GH_LOG) -and ((Get-Content $env:GH_LOG | Out-String).Contains("issue comment"))) { Fail "no issue: an issue comment was made" }

# comment fails
New-Case; Use-Board "board-nothing.tsv"; $env:GH_COMMENT_FAIL = "1"; Invoke-Drive
Want-Code 1 "comment fails"; Has $script:out "drive: summary not posted: fake gh: comment refused" "comment fails"

# left behind
New-Case; Use-Board "board-loop.tsv"; Set-Script "bg status:11:Review pr:101:OPEN:11"; Invoke-Drive
Want-Code 0 "left behind"
$bgpid = [int](Get-Content $env:BGPID | Select-Object -First 1)
for ($i = 0; $i -lt 10; $i++) { if (-not (Get-Process -Id $bgpid -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 500 }
if (Get-Process -Id $bgpid -ErrorAction SilentlyContinue) { Stop-Process -Id $bgpid -Force; Fail "left behind: the step's background process is still alive" }
Has (Comment) "Processes: 1 left behind by a step were ended; none left running." "left behind"; Audit "left behind"

# long
New-Case; Use-Board "board-loop.tsv"; Set-Script "long status:11:Review pr:101:OPEN:11"; Invoke-Drive
Want-Code 0 "long"; $cm = Comment
if ($cm.Length -gt 60000) { Fail "long: the comment has $($cm.Length) characters, 60000 at most" }
Has $cm "[cut: " "long"

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host "smoke-drive.ps1: ok"

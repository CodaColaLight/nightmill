# tests/smoke-drive.ps1 - scripts/drive.ps1 against a fake claude, a fake gh and throwaway slots (iteration 52, #164;
# docs/specs/iteration-52-unattended-driver.md, "Tests"): the same cases as tests/smoke-drive.sh, except `signal`
# (bash only), and the cases of iteration 53 (#165, docs/specs/iteration-53-run-limits.md). The fakes are .cmd files that call a .ps1, first on the PATH. Each case runs the driver in a child
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
  for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -eq '--body-file') { Copy-Item $a[$i + 1] $env:COMMENT -Force; Copy-Item $a[$i + 1] ($env:COMMENT + '.' + $a[2]) -Force } }
  exit 0
}
if ($k -eq 'issue edit') { exit 0 }
if ($k -eq 'issue view') {
  if ($env:ISSUE_COMMENTS -and (Test-Path $env:ISSUE_COMMENTS)) { Write-Output (Get-Content $env:ISSUE_COMMENTS -Raw) } else { Write-Output '{"comments":[]}' }
  exit 0
}
if ($k -eq 'api user') { Write-Output 'agent'; exit 0 }
if ($k -eq 'api graphql') {
  $q = $a -join ' '
  # the history of the run (iteration 54, #166): its board query holds repositoryOwner; the board is empty, or the call
  # fails with a message that names a path (HIST_GH_FAIL)
  if ($q.Contains('repositoryOwner')) {
    if ($env:HIST_GH_FAIL) { [Console]::Error.WriteLine('fake gh: cannot read /nowhere/board-cache/page.json'); exit 1 }
    Write-Output '{"data":{"repositoryOwner":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'
    exit 0
  }
  if ($env:EPIC_FOR -and $q.Contains("issue(number: $($env:EPIC_FOR))")) { Write-Output (Get-Content $env:EPIC_FILE -Raw) }
  else { Write-Output '{"data":{"repository":{"issue":{"parent":null}}}}' }
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
Add-Content -Path $env:ENV_LOG -Value ("left=" + $env:NIGHTMILL_ISSUES_LEFT + " started=" + $env:NIGHTMILL_RUN_STARTED)
$k = 0
if (Test-Path $env:STEPFILE) { $k = [int](Get-Content $env:STEPFILE | Select-Object -First 1) }
$k++
Set-Content -Path $env:STEPFILE -Value $k
$line = @(Get-Content $env:SCRIPT)[$k - 1]
$cost = '0.10'; $turns = 3; $code = 0; $stopped = ''; $long = $false; $dur = 1500; $subtype = 'success'
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
  elseif ($x -like 'dur:*') { $dur = [int]$x.Substring(4) }
  elseif ($x -like 'subtype:*') { $subtype = $x.Substring(8) }
  elseif ($x -eq 'pause') {
    $cfgPath = Join-Path $env:MAIN ".claude\nightmill.json"
    $ls = @(Get-Content $cfgPath)
    $outl = @($ls[0..($ls.Count - 2)]) + '  ,"limits": { "paused": true }' + $ls[$ls.Count - 1]
    Set-Content -Path $cfgPath -Value $outl
    $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git -C $env:MAIN commit -q -am pause 2>&1 | Out-Null
    & git -C $env:MAIN push -q origin main 2>&1 | Out-Null
    $ErrorActionPreference = $ea
  }
}
if ($long) { $msg = 'x' * 70000 }
else { $msg = "Done with step $k."; if ($stopped) { $msg += "\nStopped: $stopped" } else { $msg += "\nAll good." } }
Write-Output ('{"type":"result","subtype":"' + $subtype + '","result":"' + $msg + '","duration_ms":' + $dur + ',"total_cost_usd":' + $cost + ',"num_turns":' + $turns + '}')
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
  $env:ENV_LOG = Join-Path $c "env.log"; $env:MAIN = $m; $env:EPIC_FILE = Join-Path $fx "..\gate\epic-paused.json"; $env:LEDGER = Join-Path $c "wt\.slots\ledger.tsv"
  $env:NIGHTMILL_CLOCK_FILE = Join-Path $c "clock"; $env:STOPFILE = Join-Path $m ".git\nightmill-stop"
  Set-Content $env:PRS ""; Set-Content $env:SCRIPT ""; Set-Content $env:NIGHTMILL_CLOCK_FILE "1800000000"
  Remove-Item Env:GH_AUTH_FAIL, Env:GH_COMMENT_FAIL, Env:EPIC_FOR, Env:ISSUE_COMMENTS, Env:HIST_GH_FAIL -ErrorAction SilentlyContinue
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
      if ($l.StartsWith("issue edit ")) {
        if ($l -notmatch '^issue edit [0-9]+ --add-label blocked$') { Fail "${what}: an issue edit other than the label blocked: $l" }
      }
      elseif (-not ($l.StartsWith("auth status") -or $l.StartsWith("project item-list") -or $l.StartsWith("pr list") -or $l.StartsWith("issue comment") -or $l.StartsWith("api graphql") -or $l.StartsWith("api user") -or $l.StartsWith("issue view"))) { Fail "${what}: a gh call the driver may not make: $l" }
    }
  }
  if (Test-Path (Join-Path $script:main ".git\nightmill-drive.lock")) { Fail "${what}: the lock is left" }
}
$FLAGS = '--permission-mode manual --output-format json --max-turns 200 --max-budget-usd 25.00'
$FIX = "-p /nightmill:fix all $FLAGS"

# nothing
New-Case; Use-Board "board-nothing.tsv"; Invoke-Drive
Want-Code 0 "nothing"; if ((Calls) -ne 0) { Fail "nothing: claude was called" }
Need-Comment "nothing"; $cm = Comment
Has $cm "Ended: nothing Ready or Approved." "nothing"; Has $cm "Ready stories wait for /spec: #31" "nothing"; Audit "nothing"

# loop
New-Case; Use-Board "board-loop.tsv"
Set-Script "status:11:Review pr:101:OPEN:11 cost:0.50 turns:4 dur:1234", "status:21:Done pr:121:MERGED:21 cost:1.25 turns:5 dur:2345", "status:22:Done pr:122:MERGED:22 cost:1.25 turns:6 dur:3456"
Invoke-Drive
Want-Code 0 "loop"
$cl = @(Get-Content $env:CLAUDE_LOG)
if ($cl.Count -ne 3) { Fail "loop: $($cl.Count) claude calls, 3 expected" }
if ($cl[0] -ne $FIX) { Fail "loop: first call: $($cl[0])" }
if ($cl[1] -ne "-p /nightmill:next 21 $FLAGS") { Fail "loop: second call: $($cl[1])" }
if ($cl[2] -ne "-p /nightmill:next 22 $FLAGS") { Fail "loop: third call: $($cl[2])" }
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
if ((@(Get-Content $env:CLAUDE_LOG))[2] -ne "-p /nightmill:next 22 $FLAGS") { Fail "blocked: #22 was not tried" }
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

# ---------- iteration 53 (#165): the flags, the run ledger, the pause flag and the limits ----------
function Run-Lines { if (Test-Path $env:LEDGER) { @(Get-Content $env:LEDGER | Where-Object { $_ -and $_.StartsWith("run`t") }) } else { @() } }
function Loop-Script { Set-Script "status:11:Review pr:101:OPEN:11 cost:0.50 turns:4 dur:1234", "status:21:Done pr:121:MERGED:21 cost:1.25 turns:5 dur:2345", "status:22:Done pr:122:MERGED:22 cost:1.25 turns:6 dur:3456" }
function Call-Line([int]$n) { @(Get-Content $env:CLAUDE_LOG)[$n - 1] }

# flags
New-Case; Use-Board "board-loop.tsv"; Loop-Script; Invoke-Drive
Want-Code 0 "flags"
if ((Call-Line 1) -ne "-p /nightmill:fix all $FLAGS") { Fail "flags: first call: $(Call-Line 1)" }
if ((Call-Line 2) -ne "-p /nightmill:next 21 $FLAGS") { Fail "flags: second call: $(Call-Line 2)" }
if ((Call-Line 3) -ne "-p /nightmill:next 22 $FLAGS") { Fail "flags: third call: $(Call-Line 3)" }
$el = @(Get-Content $env:ENV_LOG)
$wantLeft = 10, 9, 8
for ($i = 0; $i -lt 3; $i++) {
  if (-not $el[$i].StartsWith("left=$($wantLeft[$i]) ")) { Fail "flags: step $($i + 1) env: $($el[$i])" }
  if ($el[$i] -notmatch ' started=[0-9]+$') { Fail "flags: NIGHTMILL_RUN_STARTED is not set in seconds: $($el[$i])" }
}
Audit "flags"

# ledger
New-Case; Use-Board "board-loop.tsv"; Loop-Script; Invoke-Drive
Want-Code 0 "ledger"
if (-not (Test-Path $env:LEDGER)) { Fail "ledger: $($env:LEDGER) was not written" }
$rl = @(Run-Lines)
if ($rl.Count -ne 3) { Fail "ledger: $($rl.Count) run lines, 3 expected" }
$wants = @(@("1", "/nightmill:fix all", "11", "1234", 0.5, "4"), @("2", "/nightmill:next 21", "21", "2345", 1.25, "5"), @("3", "/nightmill:next 22", "22", "3456", 1.25, "6"))
for ($i = 0; $i -lt 3; $i++) {
  $f = $rl[$i] -split "`t"
  $w = $wants[$i]; $ln = $i + 1
  if ($f.Count -ne 11) { Fail "ledger: line $ln has $($f.Count) fields, 11 expected: $($rl[$i])" }
  if ($f[3] -ne $w[0]) { Fail "ledger: line $ln field 4: $($f[3]), $($w[0]) expected" }
  if ($f[4] -ne $w[1]) { Fail "ledger: line $ln field 5: $($f[4]), $($w[1]) expected" }
  if ($f[5] -ne $w[2]) { Fail "ledger: line $ln field 6: $($f[5]), $($w[2]) expected" }
  if ($f[6] -ne "ok") { Fail "ledger: line $ln field 7: $($f[6]), ok expected" }
  if ($f[8] -ne $w[3]) { Fail "ledger: line $ln field 9: $($f[8]), $($w[3]) expected" }
  if (-not $f[9] -or [math]::Abs([double]::Parse($f[9], [Globalization.CultureInfo]::InvariantCulture) - $w[4]) -gt 0.0001) { Fail "ledger: line $ln field 10: $($f[9]), $($w[4]) expected" }
  if ($f[10] -ne $w[5]) { Fail "ledger: line $ln field 11: $($f[10]), $($w[5]) expected" }
  foreach ($ix in 1, 2, 7) { if ($f[$ix] -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { Fail "ledger: line $ln field $($ix + 1) is not a UTC stamp: $($f[$ix])" } }
}
if ((@($rl | ForEach-Object { ($_ -split "`t")[2] } | Select-Object -Unique)).Count -ne 1) { Fail "ledger: field 3 differs between the lines of one driver run" }
Audit "ledger"

# ledger when claude fails
New-Case; Use-Board "board-loop.tsv"; Set-Script "exit:3"; Invoke-Drive
Want-Code 1 "ledger on failure"
$rl = @(Run-Lines)
if ($rl.Count -ne 1) { Fail "ledger on failure: $($rl.Count) run lines, 1 expected" }
if ((($rl[0] -split "`t")[6]) -ne "exit 3") { Fail "ledger on failure: field 7 is $((($rl[0] -split "`t")[6])), 'exit 3' expected" }

# paused: the first step commits and pushes the pause
New-Case; Use-Board "board-loop.tsv"; Set-Script "pause"; Invoke-Drive
Want-Code 0 "paused"
if ((Calls) -ne 1) { Fail "paused: $(Calls) claude calls, 1 expected" }
Has (Comment) "paused: limits.paused is true on origin/HEAD:.claude/nightmill.json" "paused"
Audit "paused"

# paused at start
New-Case '"unattended": { "summaryIssue": 9, "maxMinutes": 60 }, "limits": { "paused": true }'; Use-Board "board-loop.tsv"; Invoke-Drive
Want-Code 1 "paused at start"; if ((Calls) -ne 0) { Fail "paused at start: claude was called" }
Has $script:err "drive: cannot start: paused: " "paused at start"
Audit "paused at start"

# issue limit
New-Case '"unattended": { "summaryIssue": 9, "maxMinutes": 60 }, "limits": { "issuesPerRun": 2 }'; Use-Board "board-loop.tsv"; Loop-Script; Invoke-Drive
Want-Code 0 "issue limit"; if ((Calls) -ne 2) { Fail "issue limit: $(Calls) claude calls, 2 expected" }
Has (Comment) "the issue limit of 2 per run (limits.issuesPerRun) is reached" "issue limit"
Audit "issue limit"

function Comment-Of([int]$n) { $f = "$($env:COMMENT).$n"; if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { "" } }
function Gh-Log { if (Test-Path $env:GH_LOG) { (Get-Content $env:GH_LOG | Out-String) } else { "" } }
function Breach-Check([string]$what, [string]$reason, [string]$ended) {
  Want-Code 0 $what
  Has (Comment-Of 21) "Stopped by a limit: $reason" $what
  Has (Gh-Log) "issue edit 21 --add-label blocked" $what
  Has (Comment) "| #21 Add export | /next | Approved | In progress | blocked: $reason" $what
  if ((Call-Line 3) -ne "-p /nightmill:next 22 $FLAGS") { Fail "${what}: #22 was not tried" }
  Hasnt (Comment) "claude exited" $what
  $f = (Run-Lines)[1] -split "`t"
  if ($f[6] -ne $ended) { Fail "${what}: ledger field 7 of step 2 is $($f[6]), $ended expected" }
  Audit $what
}
foreach ($ec in 0, 1) {
  New-Case; Use-Board "board-loop.tsv"
  Set-Script "status:11:Review pr:101:OPEN:11", "status:21:In_progress subtype:error_max_turns exit:$ec", "status:22:Done pr:122:MERGED:22"
  Invoke-Drive
  Breach-Check "max turns (exit $ec)" "the headless run reached its turn limit of 200" "max-turns"
  Has (Comment) "(limits.turnsPerRole.session" "max turns (exit $ec)"
  Has (Comment) "2. /nightmill:next 21: exit $ec, " "max turns (exit $ec): the step line shows the exit code"
  Has (Comment) "Picked 3, merged 1, pull request open 1, blocked 1" "max turns (exit $ec)"
}
foreach ($ec in 0, 1) {
  New-Case; Use-Board "board-loop.tsv"
  Set-Script "status:11:Review pr:101:OPEN:11", "status:21:In_progress subtype:error_max_budget_usd exit:$ec", "status:22:Done pr:122:MERGED:22"
  Invoke-Drive
  Breach-Check "budget (exit $ec)" 'the headless run reached its budget of $25.00' "max-budget"
  Has (Comment) "(limits.costPerIssueUsd" "budget (exit $ec)"
}

# limit at Review
New-Case; Use-Board "board-loop.tsv"
Set-Script "status:11:Review pr:101:OPEN:11 subtype:error_max_budget_usd exit:1", "status:21:Review pr:121:OPEN:21 subtype:error_max_turns exit:1", "status:22:Done pr:122:MERGED:22"
Invoke-Drive
Want-Code 0 "limit at Review"
Has (Comment-Of 11) "Stopped by a limit: the headless run reached its budget of" "limit at Review"
Has (Gh-Log) "issue edit 11 --add-label blocked" "limit at Review"
Has (Comment-Of 21) "Stopped by a limit: the headless run reached its turn limit of 200" "limit at Review"
Has (Gh-Log) "issue edit 21 --add-label blocked" "limit at Review"
Has (Comment) "| #11 Crash on start | /fix all | Ready | Review | blocked: " "limit at Review"
Has (Comment) "| #21 Add export | /next | Approved | Review | blocked: " "limit at Review"
Audit "limit at Review"

# spent: the ledger already holds $25.00 for #21 (20.00, and half of 10.00)
function Spent-Ledger {
  New-Item -ItemType Directory -Force -Path (Split-Path $env:LEDGER -Parent) | Out-Null
  $l1 = "run`t2026-11-09T06:30:00Z`t2026-11-09T06:00:00Z`t1`t/nightmill:next 21`t21`tok`t2026-11-09T06:00:10Z`t1800000`t20.00`t30"
  $l2 = "run`t2026-11-09T06:50:00Z`t2026-11-09T06:00:00Z`t2`t/nightmill:fix all`t21,22`tok`t2026-11-09T06:31:00Z`t1200000`t10.00`t45"
  [IO.File]::WriteAllText($env:LEDGER, "$l1`n$l2`n")
}
New-Case; Use-Board "board-loop.tsv"; Spent-Ledger
Set-Script "status:11:Review pr:101:OPEN:11", "status:22:Done pr:122:MERGED:22"
Invoke-Drive
Want-Code 0 "spent"
if ((Get-Content $env:CLAUDE_LOG | Out-String).Contains('nightmill:next 21')) { Fail "spent: /next 21 was called" }
Has (Comment-Of 21) 'Stopped by a limit: #21 has spent $25.00' "spent"
Has (Gh-Log) "issue edit 21 --add-label blocked" "spent"
Has (Comment) '| blocked: limit: #21 has spent $25.00' "spent"
if ((Call-Line 2) -ne "-p /nightmill:next 22 --permission-mode manual --output-format json --max-turns 200 --max-budget-usd 20.00") { Fail "spent: the call of #22: $(Call-Line 2)" }
Audit "spent"

# comment once
New-Case; Use-Board "board-loop.tsv"; Spent-Ledger
$cj = Join-Path $script:c "comments.json"
[IO.File]::WriteAllText($cj, '{"comments":[{"author":{"login":"agent"},"body":"Stopped by a limit: #21 has spent $25.00 in headless runs; the limit is $25.00 (limits.costPerIssueUsd). Labelled blocked; the board status (Approved) and the work (nothing) are left as they are for the maintainer."}]}' + "`n")
$env:ISSUE_COMMENTS = $cj
Set-Script "status:11:Review pr:101:OPEN:11", "status:22:Done pr:122:MERGED:22"
Invoke-Drive
Want-Code 0 "comment once"
if (Test-Path "$($env:COMMENT).21") { Fail "comment once: a second comment was posted on #21" }
Has (Gh-Log) "issue edit 21 --add-label blocked" "comment once"
Audit "comment once"

# epic paused
New-Case; Use-Board "board-loop.tsv"; $env:EPIC_FOR = "21"
Set-Script "status:11:Review pr:101:OPEN:11", "status:22:Done pr:122:MERGED:22"
Invoke-Drive
Want-Code 0 "epic paused"
if ((Get-Content $env:CLAUDE_LOG | Out-String).Contains('nightmill:next 21')) { Fail "epic paused: /next 21 was called" }
if (Test-Path "$($env:COMMENT).21") { Fail "epic paused: a comment was posted on #21" }
Hasnt (Gh-Log) "issue edit" "epic paused"
Has (Comment) "not started: paused: epic #5 has the label paused" "epic paused"
Audit "epic paused"
Remove-Item Env:EPIC_FOR

# ---------- iteration 54 (#166): the summary carries the history of the run ----------

# Hist-Block <comment>: the lines of the fenced text block that follows the heading of the history item
function Hist-Block([string]$comment) {
  $lines = @($comment -replace "`r`n", "`n" -split "`n")
  $h = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith("History of this run (scripts/history.sh --run ")) { $h = $i; break } }
  if ($h -lt 0) { return $null }
  $i = $h + 1
  while ($i -lt $lines.Count -and $lines[$i] -ne '```text') { $i++ }
  $block = New-Object System.Collections.Generic.List[string]
  for ($i = $i + 1; $i -lt $lines.Count -and $lines[$i] -ne '```'; $i++) { $block.Add($lines[$i]) }
  return ($block -join "`n")
}
# In-Order <text> <what> <regex>...: the first line that matches each pattern is after the one of the previous pattern
function In-Order([string]$text, [string]$what, [string[]]$patterns) {
  $prev = -1
  foreach ($p in $patterns) {
    $m = [regex]::Match($text, "(?m)$p")
    if (-not $m.Success) { Fail "${what}: no line matches $p" }
    if ($m.Index -le $prev) { Fail "${what}: the line of $p (at $($m.Index)) is not after the previous one (at $prev)" }
    $prev = $m.Index
  }
}
function Run-Dir { $m = [regex]::Matches($script:out, '(?m)^drive: run files in (.+?)\r?$'); if ($m.Count -gt 0) { return $m[$m.Count - 1].Groups[1].Value } else { return "" } }
function Read-Lf([string]$path) { ([IO.File]::ReadAllText($path)) -replace "`r`n", "`n" }

# history
New-Case; Use-Board "board-loop.tsv"; Loop-Script; Invoke-Drive
Want-Code 0 "history"
$stamp = ((Run-Lines)[0] -split "`t")[2]
if ($stamp -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { Fail "history: the run's start stamp is [$stamp]" }
Need-Comment "history"; $cm = (Comment) -replace "`r`n", "`n"
Has $cm "History of this run (scripts/history.sh --run ${stamp}):" "history"
$block = Hist-Block $cm
$first = ($block -split "`n")[0]
if (-not ($first.StartsWith("history ") -and $first.Contains("driver run $stamp"))) { Fail "history: the first line of the block is [$first]" }
In-Order $cm "history" @('^Cost: ', '^History of this run \(scripts/history\.sh --run ', '^Not run by the driver', '<details>')
Has $cm 'Cost: $3.00 in all' "history"
Has $block 'cost: $3.00 in 3 headless runs' "history"
$rd = Run-Dir
if (-not $rd -or -not (Test-Path (Join-Path $rd "history.txt")) -or -not (Test-Path (Join-Path $rd "history.err"))) { Fail "history: history.txt or history.err is missing in the run files ($rd)" }
if ($block.TrimEnd("`n") -cne (Read-Lf (Join-Path $rd "history.txt")).TrimEnd("`n")) { Fail "history: the block is not history.txt: [$block]" }
Hasnt $cm $tmp "history: the comment names a local path"
Audit "history"

# history no path
New-Case; Use-Board "board-loop.tsv"; Loop-Script
Copy-Item (Join-Path $here "scripts") (Join-Path $script:c "scripts") -Recurse
$wrapper = "Remove-Item -Force -ErrorAction SilentlyContinue '$($env:LEDGER)'`r`n& powershell -NoProfile -ExecutionPolicy Bypass -File '$(Join-Path $here 'scripts\history.ps1')' @args`r`nexit `$LASTEXITCODE`r`n"
[IO.File]::WriteAllText((Join-Path $script:c "scripts\history.ps1"), $wrapper)
$env:HIST_GH_FAIL = "1"
Invoke-Drive (Join-Path $script:c "scripts\drive.ps1")
Remove-Item Env:HIST_GH_FAIL
Want-Code 0 "history no path"
Need-Comment "history no path"; $cm = (Comment) -replace "`r`n", "`n"
if (-not (@($cm -split "`n") -ccontains 'note: no record yet')) { Fail "history no path: the block has no line 'note: no record yet'" }
if (-not (@($cm -split "`n") -ccontains 'note: the board was not read (the reason is in history.txt in the run files)')) { Fail "history no path: the block has no shortened board note" }
Hasnt $cm $tmp "history no path: the comment names a local path (the run files, the checkout or the ledger)"
Hasnt $cm "nowhere" "history no path: the comment holds text of the fake gh"
Hasnt $cm "fake gh: cannot read" "history no path: the comment holds the stderr of the fake gh"
$rd = Run-Dir
if (-not $rd -or -not (Test-Path (Join-Path $rd "history.txt"))) { Fail "history no path: history.txt is missing in the run files ($rd)" }
$ht = Read-Lf (Join-Path $rd "history.txt")
if (-not [regex]::IsMatch($ht, '(?m)^note: no record yet: .*ledger\.tsv$')) { Fail "history no path: history.txt does not keep the note as printed: $ht" }
if (-not (@($ht -split "`n") -ccontains 'note: the board was not read: fake gh: cannot read /nowhere/board-cache/page.json')) { Fail "history no path: history.txt does not keep the board note as printed: $ht" }
Audit "history no path"

# history fails: a copy of scripts\ whose history.ps1 prints boom on standard error and exits 1
New-Case; Use-Board "board-loop.tsv"; Loop-Script
Copy-Item (Join-Path $here "scripts") (Join-Path $script:c "scripts") -Recurse
[IO.File]::WriteAllText((Join-Path $script:c "scripts\history.ps1"), "[Console]::Error.WriteLine('boom')`r`nexit 1`r`n")
Invoke-Drive (Join-Path $script:c "scripts\drive.ps1")
Want-Code 0 "history fails"
Need-Comment "history fails"; $cm = (Comment) -replace "`r`n", "`n"
Has $cm "History: not computed: boom." "history fails"
Hasnt $cm "History of this run" "history fails"
In-Order $cm "history fails" @('^Cost: ', '^History: not computed: boom\.$', '^Not run by the driver', '<details>')
# every other line as in the loop case
if ((Calls) -ne 3 -or (Call-Line 1) -ne $FIX) { Fail "history fails: the calls are not those of the loop" }
Has $cm "| #11 Crash on start | /fix all | Ready | Review | pull request open | #101 |" "history fails"
Has $cm "| #21 Add export | /next | Approved | Done | merged | #121 |" "history fails"
Has $cm "| #22 Add import | /next | Approved | Done | merged | #122 |" "history fails"
Has $cm "Picked 3, merged 2, pull request open 1, blocked 0, not started 0." "history fails"
Has $cm 'Cost: $3.00 in all' "history fails"
$nd = ([regex]::Matches($cm, '<details><summary>Final message of ')).Count
if ($nd -ne 3) { Fail "history fails: $nd details blocks, 3 expected" }
Has $cm "Processes: none left running." "history fails"
Has $script:out "drive: summary posted to #9" "history fails"
Audit "history fails"

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host "smoke-drive.ps1: ok"

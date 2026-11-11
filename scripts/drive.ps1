# scripts/drive.ps1 - the unattended driver (nightmill): runs /nightmill:fix all and /nightmill:next <N> headless, round
# after round, until no Ready bug and no Approved story is left, its time limit is reached or its kill switch is set,
# then prints and posts one summary. PowerShell twin of drive.sh; the rules and the texts are in
# docs/specs/iteration-52-unattended-driver.md, and for the pause flag, the limits and the run ledger
# docs/specs/iteration-53-run-limits.md (decisions 7 to 9).
#
#   drive.ps1           # no arguments; -h or --help prints the usage line
#
# Run it from inside any checkout of the project. It reads the base branch's .claude/nightmill.json
# (scripts/lib/baseconfig.ps1; github, board, labels, git.baseBranch, worktrees, unattended.maxMinutes,
# unattended.summaryIssue, parallel.fixAllMaxBugs and limits), and calls only: gh auth status, gh project item-list,
# gh pr list, gh issue comment (the summary, and the comment of a breached limit), gh api user, gh issue view (the
# comments of an issue whose limit is breached), gh issue edit <n> --add-label blocked (a breached limit), git rev-parse /
# fetch origin / symbolic-ref / status, slot.ps1 -Reap, slot.ps1 -Status -Porcelain, room.ps1, gate.ps1 (the pause
# flag and the limits, before every step; its gh api graphql query) and claude -p "<prompt>" --permission-mode manual
# --output-format json --max-turns <T> --max-budget-usd <B> with NIGHTMILL_RUN_STARTED and NIGHTMILL_ISSUES_LEFT in
# its environment, in the main checkout. After every step it appends one run line to
# <worktrees.root>\.slots\ledger.tsv (Add-LedgerLine of lib\ledger.ps1). It sets no board status and adds none. The lock is <git common dir>/nightmill-drive.lock (one driver per repository), the kill
# switch <git common dir>/nightmill-stop (only its existence counts; the driver never creates or removes it).
# Each step's processes are followed (Windows: its process tree by ParentProcessId, and the job object the driver
# puts itself into, which also holds a descendant whose parent ended unseen; macOS and Linux: its process group,
# started through /bin/sh with job control); whatever is left after the step is ended (Windows: Stop-Process -Force;
# elsewhere TERM, after 5 seconds KILL). The run's files (each step's .json and .err, summary.md) are kept in a folder
# named on the last line.
# Exit code 0 the run ended for a reason of the loop (nothing to pick, a tie, the time limit, the kill switch after
# the start, no slot or no room after a step), 1 it could not start, a step's claude exited non-zero, a board read
# failed, the summary could not be posted, or after Ctrl+C (PowerShell cannot set the signal's exit code), 2 a usage
# error or an unusable configuration.
$ErrorActionPreference = "Stop"

$usageLine = "usage: drive.ps1"
if ($args.Count -gt 0) {
  $a0 = [string]$args[0]
  if ($args.Count -eq 1 -and ($a0 -eq "-h" -or $a0 -eq "--help" -or $a0 -eq "-Help")) { [Console]::Out.Write($usageLine + "`n"); exit 0 }
  [Console]::Error.WriteLine($usageLine); exit 2
}

. (Join-Path $PSScriptRoot "lib\baseconfig.ps1")
. (Join-Path $PSScriptRoot "lib\ledger.ps1")

$onWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$utf8 = New-Object System.Text.UTF8Encoding $false
function Out-Line([string]$line) { [Console]::Out.Write($line + "`n") }
function Stop-Two([string]$msg) { [Console]::Error.WriteLine("drive: $msg"); exit 2 }
function One-Line([string]$s) {
  if ($null -eq $s) { return "" }
  return (($s -replace "[`r`n]+", " ") -replace " +", " ").Trim()
}
function Resolve-Exe([string]$name) {
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return [string]$c.Path }
  return $null
}
function Quote-Arg([string]$a) {
  if ($a -match '^[A-Za-z0-9_./:=@,+-]+$') { return $a }
  $s = $a -replace '(\\*)"', '$1$1\"'
  $s = $s -replace '(\\+)$', '$1$1'
  return '"' + $s + '"'
}
# Invoke-Exe <exe> <arguments> [cwd] [environment: name = value, $null removes it]: Out, Err, Code (a program that
# cannot start: Code -1 and the reason in Err)
function Invoke-Exe([string]$exe, [string[]]$argv, [string]$cwd = "", [hashtable]$envs = $null) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = (@($argv | ForEach-Object { Quote-Arg ([string]$_) }) -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  if ($cwd) { $psi.WorkingDirectory = $cwd }
  if ($null -ne $envs) {
    foreach ($ek in $envs.Keys) {
      if ($null -eq $envs[$ek]) { if ($psi.EnvironmentVariables.ContainsKey($ek)) { $psi.EnvironmentVariables.Remove($ek) } }
      else { $psi.EnvironmentVariables[$ek] = [string]$envs[$ek] }
    }
  }
  try {
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $res = [pscustomobject]@{ Out = $out; Err = $errTask.Result; Code = $p.ExitCode }
    $p.Dispose()
    return $res
  } catch {
    return [pscustomobject]@{ Out = ""; Err = (One-Line $_.Exception.Message); Code = -1 }
  }
}

# --- the configuration (a failure here: stderr only, exit 2, no summary) ---
$gitExe = Resolve-Exe "git"
if (-not $gitExe) { Stop-Two "git is not on the PATH" }
$r = Invoke-Exe $gitExe @("rev-parse", "--path-format=absolute", "--git-common-dir")
if ($r.Code -ne 0 -or -not $r.Out.Trim()) { Stop-Two "run drive.ps1 from inside a git checkout of the project" }
$gitDir = $r.Out.Trim()
$main = Split-Path $gitDir -Parent
$bc = Get-BaseConfig $main
if ($bc.Stop) { Stop-Two $bc.Stop }
if ($bc.Note) { [Console]::Error.WriteLine($bc.Note) }
$cfgText = $bc.Text
if ($null -eq $cfgText) {
  if (-not (Test-Path -LiteralPath $bc.Path -PathType Leaf)) { Stop-Two "no $($bc.Path) (run /nightmill:init)" }
  $cfgText = [IO.File]::ReadAllText($bc.Path).TrimStart([char]0xFEFF)
}
try { $cfg = ConvertFrom-Json -InputObject $cfgText } catch { Stop-Two "$($bc.From) is not valid JSON: $(One-Line $_.Exception.Message)" }

function Cfg($obj, [string[]]$path, $default) {
  foreach ($k in $path) {
    if ($null -eq $obj) { return $default }
    $p = $obj.PSObject.Properties[$k]
    if (-not $p) { return $default }
    $obj = $p.Value
  }
  if ($null -eq $obj -or "$obj" -eq "") { return $default }
  return $obj
}
function Has-Key($obj, [string]$k) { return ($null -ne $obj -and $null -ne $obj.PSObject.Properties[$k]) }

# Get-Whole <key> <lo> <hi or 0> <default>: the value of unattended.<key>, or the stop of decision 6
function Get-Whole([string]$key, [long]$lo, [long]$hi, $default) {
  $u = $null
  if (Has-Key $cfg "unattended") { $u = $cfg.unattended }
  if (-not (Has-Key $u $key)) { return $default }
  $v = $u.PSObject.Properties[$key].Value
  if (($v -is [int] -or $v -is [long]) -and [long]$v -ge $lo -and ($hi -eq 0 -or [long]$v -le $hi)) { return [long]$v }
  if ($null -eq $v) { $shown = "null" }
  elseif ($v -is [string]) { $shown = ConvertTo-Json -InputObject $v -Compress }
  elseif ($v -is [bool]) { if ($v) { $shown = "true" } else { $shown = "false" } }
  elseif ($v -is [array]) { $shown = "[...]" }
  elseif ($v -is [System.Management.Automation.PSCustomObject]) { $shown = "{...}" }
  else { $shown = [Convert]::ToString($v, [Globalization.CultureInfo]::InvariantCulture) }
  if ($hi -ne 0) { $range = "from $lo to $hi" } else { $range = "of at least $lo" }
  [Console]::Error.WriteLine("drive: unattended.$key must be a whole number $range, got $shown")
  exit 2
}
$maxMinutes = Get-Whole "maxMinutes" 1 1440 ([long]240)
$summaryIssue = Get-Whole "summaryIssue" 1 0 $null

$owner = [string](Cfg $cfg @("github", "owner") "")
$repo = [string](Cfg $cfg @("github", "repo") "")
$project = [string](Cfg $cfg @("github", "projectNumber") "")
if (-not $owner -or -not $repo -or -not $project) { Stop-Two "github.owner, github.repo and github.projectNumber are needed in $($bc.From)" }
$base = [string](Cfg $cfg @("git", "baseBranch") "main")
$statusKey = ([string](Cfg $cfg @("board", "statusField") "Status")).ToLowerInvariant()
$prioKey = ([string](Cfg $cfg @("board", "priorityField") "Priority")).ToLowerInvariant()
$stReady = [string](Cfg $cfg @("board", "statuses", "ready") "Ready")
$stApproved = [string](Cfg $cfg @("board", "statuses", "approved") "Approved")
$lbBug = [string](Cfg $cfg @("labels", "bug") "bug")
$lbEpic = [string](Cfg $cfg @("labels", "epic") "epic")
$prios = @("Critical", "High", "Medium", "Low")
if ((Has-Key $cfg "board") -and (Has-Key $cfg.board "priorities")) { $prios = @($cfg.board.priorities | ForEach-Object { [string]$_ }) }
$hasSlots = Has-Key $cfg "worktrees"
$stDone = [string](Cfg $cfg @("board", "statuses", "done") "Done")
$stProgress = [string](Cfg $cfg @("board", "statuses", "inProgress") "In progress")
$stReview = [string](Cfg $cfg @("board", "statuses", "review") "Review")
# the limits (iteration 53): the gate checks their values before every step and stops on a bad one; a value the gate
# would refuse is taken as its default here, as the run does not get that far
function Get-IntOr($v, [long]$default) { if (($v -is [int] -or $v -is [long]) -and [long]$v -ge 1) { return [long]$v }; return $default }
function Get-NumOr($v, [double]$default) {
  if (($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) -and [double]$v -gt 0) { return [double]$v }
  return $default
}
$limTurns = Get-IntOr (Cfg $cfg @("limits", "turnsPerRole", "session") $null) 200
$limCost = Get-NumOr (Cfg $cfg @("limits", "costPerIssueUsd") $null) 25
$limIssues = Get-IntOr (Cfg $cfg @("limits", "issuesPerRun") $null) 10
$fixMax = (Cfg $cfg @("parallel", "fixAllMaxBugs") 0)
if (-not ($fixMax -is [int] -or $fixMax -is [long]) -or $fixMax -lt 0) { $fixMax = 0 }
$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
$rr = Cfg $cfg @("worktrees", "root") ""
if ($rr) { $rootRel = [string]$rr }
$ledgerPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $main $rootRel))) ".slots\ledger.tsv"
if ($hasSlots) { $workText = "the slot and branch" } else { $workText = "the branch" }
$times = [string][char]0x00D7

# --- the run ---
$lock = Join-Path $gitDir "nightmill-drive.lock"
$stopFile = Join-Path $gitDir "nightmill-stop"
$startS = Get-LedgerClock
$run = Join-Path ([IO.Path]::GetTempPath()) ("nightmill-drive." + [guid]::NewGuid().ToString("N").Substring(0, 6))
try { New-Item -ItemType Directory -Path $run | Out-Null } catch { Stop-Two "cannot make the run folder" }
$psExe = (Get-Process -Id $PID).Path
$ghExe = Resolve-Exe "gh"
$script:ownLock = $false
$script:finished = $false
$script:ghOk = ""
$script:ghWhy = ""
$script:leftTotal = 0
$script:notEnded = New-Object System.Collections.Generic.List[string]
$script:boardFull = $false
$script:steps = New-Object System.Collections.Generic.List[object]
$script:tried = New-Object System.Collections.Generic.List[object]
$script:triedSet = @{}
$script:lastBoard = @()
$script:cur = $null   # the running step: Process, Known (Windows), PgFile (elsewhere), T0
$script:started = 0    # the items of this run whose board status after their step differs from before it
$script:outcome = @{}  # number -> Kind (blocked | not started), Text: a breach or a pause of the item
$script:login = ""
$script:loginRead = $false

function Invoke-Gh([string[]]$argv) {
  if (-not $ghExe) { return [pscustomobject]@{ Out = ""; Err = "gh is not on the PATH"; Code = -1 } }
  return Invoke-Exe $ghExe $argv
}
function Test-GhAuth {
  if ($script:ghOk) { return }
  $a = Invoke-Gh @("auth", "status")
  if ($a.Code -eq 0) { $script:ghOk = "yes" } else {
    $script:ghOk = "no"
    $script:ghWhy = One-Line $a.Err
    if (-not $script:ghWhy) { $script:ghWhy = One-Line $a.Out }
  }
}

# --- the processes of a step ---
function Get-ProcTable {
  try { return @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate, Name -ErrorAction Stop) } catch { return @() }
}
# Windows: the driver puts itself into a job object once, so every process a step starts (and theirs, through a .cmd
# shim or a parent that ended before a poll saw it) is in the job; the polled tree stays as the fallback
$script:jobOk = $false
$script:jobTried = $false
function Enter-Job {
  if ($script:jobOk -or $script:jobTried) { return }
  $script:jobTried = $true
  try {
    if (-not ("NightmillDriveJob" -as [type])) {
      Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NightmillDriveJob {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, int length, IntPtr returned);
  [DllImport("kernel32.dll")]
  static extern IntPtr GetCurrentProcess();
  static IntPtr job = IntPtr.Zero;
  public static bool Enter() {
    IntPtr j = CreateJobObject(IntPtr.Zero, null);
    if (j == IntPtr.Zero) { return false; }
    if (!AssignProcessToJobObject(j, GetCurrentProcess())) { return false; }
    job = j;
    return true;
  }
  public static int[] Pids() {
    if (job == IntPtr.Zero) { return null; }
    int max = 8192;
    int size = 8 + IntPtr.Size * max;
    IntPtr buf = Marshal.AllocHGlobal(size);
    try {
      if (!QueryInformationJobObject(job, 3, buf, size, IntPtr.Zero)) { return null; }
      int n = Marshal.ReadInt32(buf, 4);
      int[] ids = new int[n];
      for (int i = 0; i < n; i++) { ids[i] = (int)Marshal.ReadIntPtr(buf, 8 + i * IntPtr.Size).ToInt64(); }
      return ids;
    } finally { Marshal.FreeHGlobal(buf); }
  }
}
'@
    }
    $script:jobOk = [NightmillDriveJob]::Enter()
  } catch { $script:jobOk = $false }
}
# Get-JobPids: the live processes of the job, $null without one
function Get-JobPids {
  if (-not $script:jobOk) { return $null }
  try { $ids = [NightmillDriveJob]::Pids() } catch { return $null }
  if ($null -eq $ids) { return $null }
  return , @($ids | ForEach-Object { [int]$_ })
}
# Update-Tree <known pids> <since>: adds every process started since <since> whose parent is known; returns the table
function Update-Tree($known, [datetime]$since) {
  $all = Get-ProcTable
  do {
    $added = $false
    foreach ($p in $all) {
      $id = [int]$p.ProcessId
      if ($known.Contains($id)) { continue }
      if ($p.Name -eq "conhost.exe") { continue }
      if ($known.Contains([int]$p.ParentProcessId) -and $null -ne $p.CreationDate -and $p.CreationDate -ge $since) {
        [void]$known.Add($id); $added = $true
      }
    }
  } while ($added)
  return , $all
}
function Get-GroupPids([string]$pg) {
  $res = Invoke-Exe "/bin/ps" @("-A", "-o", "pid=", "-o", "pgid=")
  $ids = @()
  foreach ($l in ($res.Out -split "`n")) {
    $f = @($l.Trim() -split " +")
    if ($f.Count -ge 2 -and $f[1] -eq $pg) { $ids += $f[0] }
  }
  return $ids
}
# End-Step: ends whatever is left of the running step; adds to leftTotal and notEnded
function End-Step {
  $c = $script:cur
  if ($null -eq $c) { return }
  if ($onWindows) {
    $all = Update-Tree $c.Known $c.Since
    # only processes of the tree that still run and were started since the step began (a reused pid is not one)
    $left = @($all | Where-Object { $c.Known.Contains([int]$_.ProcessId) -and $null -ne $_.CreationDate -and $_.CreationDate -ge $c.Since } | ForEach-Object { [int]$_.ProcessId })
    # and every process of the job that was not there before the step (the driver itself and a console host aside)
    $inJob = Get-JobPids
    if ($null -ne $inJob) {
      foreach ($id in $inJob) {
        if ($id -eq $PID -or $c.Before.Contains($id) -or $left -contains $id) { continue }
        $gp = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -eq $gp -or $gp.ProcessName -eq "conhost") { continue }
        $left += $id
      }
    }
    $script:leftTotal += $left.Count
    foreach ($id in $left) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    if ($left.Count -gt 0) {
      Start-Sleep -Milliseconds 500
      foreach ($id in $left) { if (Get-Process -Id $id -ErrorAction SilentlyContinue) { $script:notEnded.Add([string]$id) } }
    }
  } else {
    $pg = ""
    if (Test-Path -LiteralPath $c.PgFile) { $pg = ([IO.File]::ReadAllText($c.PgFile)).Trim() }
    if ($pg -match '^[0-9]+$') {
      $ids = @(Get-GroupPids $pg)
      if ($ids.Count -gt 0) {
        $script:leftTotal += $ids.Count
        $null = Invoke-Exe "/bin/kill" @("-TERM", "--", "-$pg")
        for ($i = 0; $i -lt 25; $i++) { if (@(Get-GroupPids $pg).Count -eq 0) { break }; Start-Sleep -Milliseconds 200 }
        if (@(Get-GroupPids $pg).Count -gt 0) {
          $null = Invoke-Exe "/bin/kill" @("-KILL", "--", "-$pg")
          Start-Sleep -Milliseconds 200
          foreach ($id in @(Get-GroupPids $pg)) { $script:notEnded.Add([string]$id) }
        }
      }
    }
  }
  $script:cur = $null
}

# --- the board ---
# Read-Board: the items (Num, Type, Status, Prio, Labels, Title), or $null with $script:boardWhy
function Read-Board {
  $b = Invoke-Gh @("project", "item-list", $project, "--owner", $owner, "--limit", "200", "--format", "json")
  if ($b.Code -ne 0) { $script:boardWhy = One-Line $b.Err; return $null }
  try { $doc = ConvertFrom-Json -InputObject $b.Out } catch { $script:boardWhy = "gh project item-list gave no valid JSON"; return $null }
  $items = New-Object System.Collections.Generic.List[object]
  $n = 0
  foreach ($it in @($doc.items)) {
    if ($null -eq $it) { continue }
    $n++
    $ct = $it.content
    if ($null -eq $ct -or $null -eq $ct.number) { continue }
    $title = [string]$ct.title
    if (-not $title) { $title = [string]$it.title }
    $st = ""; $sp = $it.PSObject.Properties[$statusKey]; if ($sp) { $st = [string]$sp.Value }
    $pr = ""; $pp = $it.PSObject.Properties[$prioKey]; if ($pp) { $pr = [string]$pp.Value }
    $labels = @(); if ($it.labels) { $labels = @($it.labels | ForEach-Object { [string]$_ }) }
    $items.Add([pscustomobject]@{ Num = [string]$ct.number; Type = [string]$ct.type; Status = $st; Prio = $pr; Labels = $labels; Title = $title })
  }
  if ($n -ge 200) {
    $script:boardFull = $true
    Out-Line "drive: the board listing returned 200 items, its limit; items past it may be missing"
  }
  return , $items.ToArray()
}

# --- the summary ---
function Format-Title([string]$t) {
  if ($t.StartsWith("[Bug] ")) { $t = $t.Substring(6) } elseif ($t.StartsWith("[Story] ")) { $t = $t.Substring(8) }
  $t = $t -replace "[`r`n`t]", " "
  $t = $t.Replace("|", "\|")
  if ($t.Length -gt 80) { $t = $t.Substring(0, 80) }
  return $t
}
function Format-Money([double]$x) { return [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:0.00}", $x) }
function Get-ProcessesLine {
  if ($script:notEnded.Count -gt 0) { return "Processes: $($script:notEnded -join ' ') could not be ended." }
  if ($script:leftTotal -gt 0) { return "Processes: $($script:leftTotal) left behind by a step were ended; none left running." }
  return "Processes: none left running."
}
function Build-Summary([string]$kind, [string]$reason) {
  $endS = Get-LedgerClock
  $sb = New-Object System.Text.StringBuilder
  $head = "**nightmill driver run** $(Get-LedgerStamp $startS) to $(Get-LedgerStamp $endS) UTC ($(Format-LedgerDuration ($endS - $startS)))."
  if ($kind -eq "start") { $head += " Did not start: $reason." } else { $head += " Ended: $reason." }
  [void]$sb.Append($head + "`n")
  if ($kind -ne "start") {
    $after = @{}
    $prOf = @{}
    $prsOk = $false
    if ($script:steps.Count -gt 0) {
      $ab = Read-Board
      if ($null -ne $ab) { foreach ($i in $ab) { $after[$i.Num] = $i.Status } }
      $pl = Invoke-Gh @("pr", "list", "--repo", "$owner/$repo", "--state", "all", "--limit", "100", "--json", "number,state,closingIssuesReferences")
      if ($pl.Code -eq 0) {
        try {
          $prs = ConvertFrom-Json -InputObject $pl.Out
          foreach ($p in @($prs)) {
            if ($null -eq $p) { continue }
            foreach ($ref in @($p.closingIssuesReferences)) {
              if ($null -eq $ref) { continue }
              $k = [string]$ref.number
              if (-not $prOf.ContainsKey($k) -or [long]$p.number -gt [long]$prOf[$k].Number) {
                $prOf[$k] = [pscustomobject]@{ Number = [string]$p.number; State = [string]$p.state }
              }
            }
          }
          $prsOk = $true
        } catch { $prsOk = $false }
      }
    }
    [void]$sb.Append("`n| Item | Step | Before | After | Outcome | PR |`n|---|---|---|---|---|---|`n")
    $cp = 0; $cm = 0; $co = 0; $cb = 0; $cs = 0
    foreach ($t in $script:tried) {
      $cp++
      $af = "?"; if ($after.ContainsKey($t.Num)) { $af = $after[$t.Num] }
      $prn = ""; $state = ""
      if ($prsOk -and $prOf.ContainsKey($t.Num)) { $prn = $prOf[$t.Num].Number; $state = $prOf[$t.Num].State }
      $why = "-"
      $res = ""
      if ($t.K -ge 1) { $res = $script:steps[$t.K - 1].Result }
      if ($res) {
        foreach ($l in ($res -split "`r?`n")) {
          if ($t.Step -eq "/next") {
            if ($l.StartsWith("Stopped:")) { $why = $l; if ($why.Length -gt 200) { $why = $why.Substring(0, 200) }; break }
          } elseif ($l.StartsWith("| #$($t.Num) ")) {
            $cells = $l -split "\|"
            if ($cells.Count -gt 5 -and $cells[5].Trim()) { $why = $cells[5].Trim() }
            break
          }
        }
      }
      if ($script:outcome.ContainsKey($t.Num)) {
        $ov = $script:outcome[$t.Num]
        $outcome = "$($ov.Kind): $($ov.Text)"
        if ($ov.Kind -eq "blocked") { $cb++ } else { $cs++ }
      }
      elseif ($state -eq "MERGED") { $outcome = "merged"; $cm++ }
      elseif ($state -eq "OPEN") { $outcome = "pull request open"; $co++ }
      elseif ($af -eq $t.Before) { $outcome = "not started: $why"; $cs++ }
      else { $outcome = "blocked: $why"; $cb++ }
      if ($prn -and ($state -eq "MERGED" -or $state -eq "OPEN")) { $prCell = "#$prn" } else { $prCell = "-" }
      [void]$sb.Append("| #$($t.Num) $(Format-Title $t.Title) | $($t.Step) | $($t.Before) | $af | $outcome | $prCell |`n")
    }
    [void]$sb.Append("`nPicked $cp, merged $cm, pull request open $co, blocked $cb, not started $cs.`n`n")
    $sum = [double]0; $noCost = 0; $k = 0
    foreach ($s in $script:steps) {
      $k++
      if ($null -eq $s.Cost) { $noCost++; $c = "?" } else { $sum += [double]$s.Cost; $c = '$' + (Format-Money ([double]$s.Cost)) }
      [void]$sb.Append("$k. $($s.Prompt): exit $($s.Rc), $($s.Dur), $c, $($s.Turns) turns.`n")
    }
    if ($noCost -eq 0) { [void]$sb.Append('Cost: $' + (Format-Money $sum) + " in all, as Claude Code reports it (total_cost_usd).`n") }
    else { [void]$sb.Append('Cost: at least $' + (Format-Money $sum) + " ($noCost steps without a cost).`n") }
    $rs = @($script:lastBoard | Where-Object { $_.Type -eq "Issue" -and $_.Status -eq $stReady -and ($_.Labels -notcontains $lbBug) -and ($_.Labels -notcontains $lbEpic) } | ForEach-Object { "#" + $_.Num })
    if ($rs.Count -gt 0) { [void]$sb.Append("`nNot run by the driver: Ready stories wait for /spec: $($rs -join ', ').`n") }
    else { [void]$sb.Append("`nNot run by the driver: none.`n") }
    if ($script:boardFull) { [void]$sb.Append("The board listing returned 200 items, its limit; items past it may be missing.`n") }
  }
  [void]$sb.Append("`n" + (Get-ProcessesLine) + "`n")
  $more = $false
  for ($k = 0; $k -lt $script:steps.Count; $k++) {
    $res = [string]$script:steps[$k].Result
    if ($more) { [void]$sb.Append("`n[cut: $($res.Length) more characters in the run files]`n"); continue }
    $block = "`n<details><summary>Final message of $($script:steps[$k].Prompt)</summary>`n`n"
    $avail = 60000 - $sb.Length - $block.Length - 16 - 64 * ($script:steps.Count - $k - 1)
    if ($res.Length -le $avail) {
      [void]$sb.Append($block + $res + "`n`n</details>`n")
    } else {
      $cut = $avail - 80; if ($cut -lt 0) { $cut = 0 }
      [void]$sb.Append($block + $res.Substring(0, $cut) + "`n[cut: $($res.Length - $cut) more characters in the run files]`n`n</details>`n")
      $more = $true
    }
  }
  return $sb.ToString()
}

# Finish <start|end> <reason> <exit code>: the summary, printed and posted; the exit
function Finish([string]$kind, [string]$reason, [int]$code) {
  $script:finished = $true
  End-Step
  $text = Build-Summary $kind $reason
  $sumPath = Join-Path $run "summary.md"
  [IO.File]::WriteAllText($sumPath, $text, $utf8)
  [Console]::Out.Write($text + "`n")
  if ($null -eq $summaryIssue) {
    Out-Line "drive: summary not posted: unattended.summaryIssue is not set"
  } else {
    Test-GhAuth
    if ($script:ghOk -ne "yes") {
      Out-Line "drive: summary not posted: gh is not signed in"
      if ($code -eq 0) { $code = 1 }
    } else {
      $cr = Invoke-Gh @("issue", "comment", [string]$summaryIssue, "--repo", "$owner/$repo", "--body-file", $sumPath)
      if ($cr.Code -eq 0) { Out-Line "drive: summary posted to #$summaryIssue" }
      else {
        $e = One-Line $cr.Err; if (-not $e) { $e = "gh issue comment failed" }
        Out-Line "drive: summary not posted: $e"
        if ($code -eq 0) { $code = 1 }
      }
    }
  }
  if ($script:notEnded.Count -gt 0) { $code = 1 }
  Out-Line "drive: run files in $run"
  if ($script:ownLock) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue; $script:ownLock = $false }
  exit $code
}
function Cannot([string]$reason) { [Console]::Error.WriteLine("drive: cannot start: $reason"); Finish "start" $reason 1 }
function Ended([string]$reason, [int]$code) { Out-Line "drive: ended: $reason"; Finish "end" $reason $code }
function Stop-At([string]$reason, [int]$code) { if ($script:steps.Count -eq 0) { Cannot $reason } else { Ended $reason $code } }

function Test-CleanMain {
  $h = Invoke-Exe $gitExe @("-C", $main, "symbolic-ref", "-q", "--short", "HEAD")
  if ($h.Code -ne 0 -or $h.Out.Trim() -ne $base) { return $false }
  $s = Invoke-Exe $gitExe @("-C", $main, "status", "--porcelain", "--untracked-files=all")
  if ($s.Code -ne 0 -or $s.Out.Trim()) { return $false }
  return $true
}

function Invoke-Sibling([string]$name, [string[]]$argv) {
  return Invoke-Exe $psExe (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot $name)) + $argv) $main
}

function Test-SlotRoom {
  if ($hasSlots) {
    $rp = Invoke-Sibling "slot.ps1" @("-Reap")
    if ($rp.Code -ne 0) { [Console]::Error.WriteLine("drive: slot -Reap failed: $(One-Line $rp.Err)") }
    $ss = Invoke-Sibling "slot.ps1" @("-Status", "-Porcelain")
    if ($ss.Code -ne 0) { [Console]::Error.WriteLine("drive: slot -Status failed: $(One-Line $ss.Err)") }
    else {
      $free = $false; $busy = @()
      foreach ($l in ($ss.Out -split "`r?`n")) {
        $f = @($l -split "`t")
        if ($f.Count -ge 2 -and $f[1] -eq "free") { $free = $true }
        elseif ($f.Count -ge 3 -and $f[1] -eq "busy") { $busy += "$($f[0]): $($f[2])" }
      }
      if (-not $free) { Stop-At "no free slot: all $($busy.Count) slots are busy ($($busy -join ', '))" 0 }
    }
  }
  $since = ""
  while ($true) {
    if ($since) { $rm = Invoke-Sibling "room.ps1" @("-Since", $since) } else { $rm = Invoke-Sibling "room.ps1" @() }
    $lines = @($rm.Out -split "`r?`n")
    if ($rm.Code -eq 0) { return }
    if ($rm.Code -eq 1) {
      foreach ($l in $lines) { if ($l.StartsWith("room: waiting")) { Out-Line "drive: $l" } }
      $since = ""
      foreach ($l in $lines) { if ($l -match '^room: call again with -Since ([0-9]+)') { $since = $Matches[1]; break } }
      if (-not $since) { foreach ($l in $lines) { if ($l -match '^room: call again with --since ([0-9]+)') { $since = $Matches[1]; break } } }
      if (-not $since) { [Console]::Error.WriteLine("drive: room: no -Since value; the step starts"); return }
      continue
    }
    if ($rm.Code -eq 3) {
      $line = ""
      foreach ($l in $lines) { if ($l.StartsWith("room: gave up")) { $line = $l; break } }
      if (-not $line) { $nonEmpty = @($lines | Where-Object { $_.Trim() }); if ($nonEmpty.Count -gt 0) { $line = $nonEmpty[-1] } }
      if ($line.StartsWith("room: ")) { $line = $line.Substring(6) }
      Stop-At "no room on this machine: $line" 0
    }
    [Console]::Error.WriteLine("drive: room: not checked ($(One-Line $rm.Err)); the step starts")
    return
  }
}

# Invoke-Gate [arguments]: gate.ps1 in the main checkout (iteration 53 decision 3); $script:gateRc, $script:gateOut and
# $script:gateReason: its line without "gate: " (exit 1, 3, 4) or without "gate: cannot check: " (exit 2 and any other)
function Invoke-Gate([string[]]$argv = @()) {
  $g = Invoke-Exe $psExe (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "gate.ps1")) + $argv) $main @{ NIGHTMILL_RUN_STARTED = $null; NIGHTMILL_ISSUES_LEFT = $null }
  $script:gateRc = $g.Code
  $script:gateOut = [string]$g.Out
  $script:gateReason = ""
  $outLines = @($g.Out -split "`r?`n")
  $errLines = @($g.Err -split "`r?`n")
  if ($g.Code -eq 0) { return }
  if ($g.Code -eq 1 -or $g.Code -eq 4) { $want = "gate: paused: "; $from = $outLines; $cut = 6 }
  elseif ($g.Code -eq 3) { $want = "gate: limit: "; $from = $outLines; $cut = 6 }
  else { $want = "gate: cannot check: "; $from = $errLines; $cut = 20 }
  foreach ($l in $from) { if ($l.StartsWith($want)) { $script:gateReason = $l.Substring($cut); break } }
  if (-not $script:gateReason) { $script:gateReason = One-Line ($g.Out + " " + $g.Err) }
  if (-not $script:gateReason) { $script:gateReason = "gate.ps1 exited $($g.Code)" }
}
# Stop-Gate: the end of the run for a gate exit of 1 or 2 (or a gate that could not run)
function Stop-Gate {
  if ($script:gateRc -eq 1) { Stop-At $script:gateReason 0 }
  Stop-At "the gate could not check the pause and the limits: $($script:gateReason)" 1
}

# Write-RunLine <k> <ended> <issues> <duration> <cost> <turns>: the run line of step k in the ledger (decision 7)
function Write-RunLine([int]$k, [string]$how, [string]$issues, [string]$dur, [string]$cost, [string]$turns) {
  $rec = $script:steps[$k - 1]
  try { New-Item -ItemType Directory -Force -Path (Split-Path $ledgerPath -Parent) | Out-Null } catch { }
  $fields = @("run", (Get-LedgerStamp (Get-LedgerClock)), (Get-LedgerStamp $startS), [string]$k, $rec.Prompt, $issues, $how, (Get-LedgerStamp $rec.T0), $dur, $cost, $turns)
  $sw = New-Object System.IO.StringWriter
  $old = [Console]::Error
  [Console]::SetError($sw)
  try { Add-LedgerLine $ledgerPath $fields } finally { [Console]::SetError($old) }
  $e = $sw.ToString().Trim()
  if ($e) {
    $e = $e -replace '^slot: the record was not written \(', '' -replace '\)$', ''
    [Console]::Error.WriteLine("drive: the run ledger was not written ($e)")
  }
}

# Get-StatusOf <board> <number>: the item's status on that board read ("" when it is not there)
function Get-StatusOf($board, [string]$n) {
  foreach ($i in @($board)) { if ($null -ne $i -and $i.Num -eq $n) { return $i.Status } }
  return ""
}

# Invoke-Breach <n> <reason> <status> <work>: iteration 53 decision 9 by the driver: one comment, the label blocked, no status
function Invoke-Breach([string]$n, [string]$reason, [string]$status, [string]$work) {
  $key = ""
  $km = [regex]::Matches($reason, 'limits\.[A-Za-z.]*[A-Za-z]')
  if ($km.Count -gt 0) { $key = $km[$km.Count - 1].Value }
  if (-not $script:loginRead) {
    $script:loginRead = $true
    $u = Invoke-Gh @("api", "user", "-q", ".login")
    if ($u.Code -eq 0) { $script:login = $u.Out.Trim() }
  }
  $found = $false
  if ($script:login) {
    $v = Invoke-Gh @("issue", "view", $n, "--repo", "$owner/$repo", "--json", "comments")
    if ($v.Code -eq 0) {
      try {
        $doc = ConvertFrom-Json -InputObject $v.Out
        foreach ($cm in @($doc.comments)) {
          if ($null -eq $cm -or $null -eq $cm.author) { continue }
          $b = [string]$cm.body
          if ([string]$cm.author.login -eq $script:login -and $b.StartsWith("Stopped by a limit: ") -and (-not $key -or $b.Contains($key))) { $found = $true; break }
        }
      } catch { $found = $false }
    }
  }
  if (-not $found) {
    $bodyPath = Join-Path $run "breach-$n.md"
    [IO.File]::WriteAllText($bodyPath, "Stopped by a limit: $reason. Labelled blocked; the board status ($status) and the work ($work) are left as they are for the maintainer.`n", $utf8)
    $cr = Invoke-Gh @("issue", "comment", $n, "--repo", "$owner/$repo", "--body-file", $bodyPath)
    if ($cr.Code -ne 0) { [Console]::Error.WriteLine("drive: the comment on #$n could not be posted: $(One-Line $cr.Err)") }
  }
  if ($ghExe) { $lr = Invoke-Exe $ghExe @("issue", "edit", $n, "--add-label", "blocked") $main }
  else { $lr = [pscustomobject]@{ Out = ""; Err = "gh is not on the PATH"; Code = -1 } }
  if ($lr.Code -ne 0) {
    $first = @(([string]$lr.Err) -split "`r?`n")[0]
    Out-Line "The label blocked could not be added: $first; /init creates it."
  }
  Out-Line "drive: #${n}: Stopped: limit: $reason. Labelled blocked."
}

# Invoke-Step <prompt> <issues> <T> <B> <k of the limits>: one headless step in the main checkout; then its run line,
# and the breach of every item it left undone when a limit inside it ended it
function Invoke-Step([string]$prompt, [string]$issues, [long]$maxTurns, [string]$budget, [long]$kq) {
  $k = $script:steps.Count + 1
  $t0 = Get-LedgerClock
  $rec = [pscustomobject]@{ Prompt = $prompt; Rc = "?"; Dur = "0s"; Cost = $null; Turns = "?"; Result = ""; T0 = $t0; Issues = $issues }
  $script:steps.Add($rec)
  $jsonPath = Join-Path $run "step-$k.json"
  $errPath = Join-Path $run "step-$k.err"
  $claudeArgs = @("-p", $prompt, "--permission-mode", "manual", "--output-format", "json", "--max-turns", [string]$maxTurns, "--max-budget-usd", $budget)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $pgFile = Join-Path $run "step-$k.pgid"
  if ($onWindows) {
    $psi.FileName = $claudeExe
    $psi.Arguments = (@($claudeArgs | ForEach-Object { Quote-Arg $_ }) -join " ")
  } else {
    $psi.FileName = "/bin/sh"
    $sh = 'set -m; "$0" "$@" </dev/null & echo $! > "$NIGHTMILL_DRIVE_PG"; wait $!'
    $psi.Arguments = (@(@("-c", $sh, $claudeExe) + $claudeArgs | ForEach-Object { Quote-Arg $_ }) -join " ")
    $psi.EnvironmentVariables["NIGHTMILL_DRIVE_PG"] = $pgFile
  }
  $psi.WorkingDirectory = $main
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $psi.EnvironmentVariables["NIGHTMILL_RUN_STARTED"] = [string]$t0
  $psi.EnvironmentVariables["NIGHTMILL_ISSUES_LEFT"] = [string]($limIssues - $script:started)
  $before = New-Object 'System.Collections.Generic.HashSet[int]'
  if ($onWindows) {
    Enter-Job
    $inJob = Get-JobPids
    if ($null -ne $inJob) { foreach ($id in $inJob) { [void]$before.Add($id) } }
  }
  $since = (Get-Date).AddSeconds(-2)
  $p = [System.Diagnostics.Process]::Start($psi)
  $known = New-Object 'System.Collections.Generic.HashSet[int]'
  [void]$known.Add($p.Id)
  $script:cur = [pscustomobject]@{ Process = $p; Root = $p.Id; Known = $known; Before = $before; Since = $since; PgFile = $pgFile; T0 = $t0; Rec = $rec }
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  while (-not $p.WaitForExit(500)) {
    if ($onWindows) { $null = Update-Tree $known $since }
  }
  $p.WaitForExit()
  $rc = $p.ExitCode
  # leftovers first: one that holds the step's stdout or stderr would keep the reads below open
  End-Step
  $out = $outTask.Result
  [IO.File]::WriteAllText($jsonPath, $out, $utf8)
  [IO.File]::WriteAllText($errPath, $errTask.Result, $utf8)
  $rec.Rc = [string]$rc
  $rec.Dur = Format-LedgerDuration ((Get-LedgerClock) - $t0)
  $how = "no-result"; $fDur = ""; $fCost = ""; $fTurns = ""
  try {
    $j = ConvertFrom-Json -InputObject $out
    if ($null -ne $j -and $j -is [System.Management.Automation.PSCustomObject] -and [string]$j.type -eq "result") {
      if ($null -ne $j.result) { $rec.Result = [string]$j.result }
      $cv = $j.total_cost_usd
      if ($null -ne $cv -and ($cv -is [int] -or $cv -is [long] -or $cv -is [double] -or $cv -is [decimal])) { $rec.Cost = [double]$cv; $fCost = [Convert]::ToString($cv, [Globalization.CultureInfo]::InvariantCulture) }
      $tv = $j.num_turns
      if ($null -ne $tv -and ($tv -is [int] -or $tv -is [long])) { $rec.Turns = [string]$tv; $fTurns = [string]$tv }
      $dv = $j.duration_ms
      if ($null -ne $dv -and ($dv -is [int] -or $dv -is [long] -or $dv -is [double] -or $dv -is [decimal])) { $fDur = [Convert]::ToString($dv, [Globalization.CultureInfo]::InvariantCulture) }
      $sub = [string]$j.subtype
      if ($sub -eq "error_max_turns") { $how = "max-turns" }
      elseif ($sub -eq "error_max_budget_usd") { $how = "max-budget" }
      elseif (($sub -eq "success" -or -not $sub) -and $rc -eq 0) { $how = "ok" }
      else { $how = "exit $rc" }
    }
  } catch { $how = "no-result" }
  [IO.File]::WriteAllText((Join-Path $run "step-$k.result"), $rec.Result, $utf8)
  # the items whose board status the step changed (field 6 for /fix all, and the count of started items)
  $post = Read-Board
  $changed = @()
  if ($null -ne $post) {
    foreach ($t in $script:tried) {
      if ($t.K -ne $k) { continue }
      $now = Get-StatusOf $post $t.Num
      if ($now -and $now -ne $t.Before) { $changed += $t.Num; $script:started++ }
    }
  }
  if ($prompt -eq "/nightmill:fix all") { $issues = $changed -join "," }
  Write-RunLine $k $how $issues $fDur $fCost $fTurns
  $reason = ""
  if ($how -eq "max-turns") { $reason = "the headless run reached its turn limit of $maxTurns (limits.turnsPerRole.session $times $kq)" }
  elseif ($how -eq "max-budget") { $reason = "the headless run reached its budget of `$$budget (limits.costPerIssueUsd $times $kq)" }
  if ($reason) {
    # every item of the step that is not done gets the breach, whatever status the run left it at
    foreach ($n in @($issues -split "," | Where-Object { $_ })) {
      $now = Get-StatusOf $post $n
      if ($prompt.StartsWith("/nightmill:next")) { if ($now -eq $stDone) { continue } }
      elseif (-not ($now -eq $stProgress -or $now -eq $stReview)) { continue }
      if (-not $now) { $now = "?" }
      Invoke-Breach $n $reason $now $workText
      $script:outcome[$n] = [pscustomobject]@{ Kind = "blocked"; Text = $reason }
    }
    return
  }
  if ($rc -ne 0) { Ended "claude exited $rc in $prompt" 1 }
}

try {
  # --- start checks ---
  $stamp = Get-LedgerStamp $startS
  $taken = $false
  for ($attempt = 0; $attempt -lt 2 -and -not $taken; $attempt++) {
    try {
      $fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      $bytes = $utf8.GetBytes("$PID`n$stamp`n")
      $fs.Write($bytes, 0, $bytes.Length)
      $fs.Dispose()
      $taken = $true
    } catch {
      if ($attempt -gt 0) { Cannot "another driver runs for this repository (the lock $lock could not be taken)" }
      $lines = @()
      try { $lines = @([IO.File]::ReadAllText($lock) -split "`r?`n") } catch { $lines = @() }
      $lpid = ""; $lstamp = "?"
      if ($lines.Count -ge 1) { $lpid = $lines[0].Trim() }
      if ($lines.Count -ge 2 -and $lines[1].Trim()) { $lstamp = $lines[1].Trim() }
      if ($lpid -match '^[0-9]+$' -and (Get-Process -Id ([int]$lpid) -ErrorAction SilentlyContinue)) {
        Cannot "another driver runs for this repository (pid $lpid, since $lstamp)"
      }
      Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
      if (-not $lpid) { $lpid = "?" }
      Out-Line "drive: removed a stale lock of pid $lpid"
    }
  }
  $script:ownLock = $true

  if (Test-Path -LiteralPath $stopFile) { Cannot "the kill switch is set (.git/nightmill-stop)" }
  Test-GhAuth
  if ($script:ghOk -ne "yes") { Cannot "gh is not signed in: $($script:ghWhy)" }
  $claudeExe = Resolve-Exe "claude"
  if (-not $claudeExe) { Cannot "claude is not on the PATH" }
  $fe = Invoke-Exe $gitExe @("-C", $main, "fetch", "origin")
  if ($fe.Code -ne 0) { Cannot "git fetch origin failed: $(One-Line $fe.Err)" }
  if (-not (Test-CleanMain)) { Cannot "the main checkout is not on $base with a clean tree" }

  # --- the loop ---
  while ($true) {
    if (Test-Path -LiteralPath $stopFile) { Stop-At "the kill switch is set (.git/nightmill-stop)" 0 }
    if (((Get-LedgerClock) - $startS) -ge ($maxMinutes * 60)) { Stop-At "the time limit of $maxMinutes minutes (unattended.maxMinutes) is reached" 0 }
    Invoke-Gate
    if ($script:gateRc -ne 0) { Stop-Gate }
    if ($script:started -ge $limIssues) { Stop-At "the issue limit of $limIssues per run (limits.issuesPerRun) is reached" 0 }
    if (-not (Test-CleanMain)) { Stop-At "the main checkout is not on $base with a clean tree" 0 }
    $board = Read-Board
    if ($null -eq $board) { Stop-At "the board could not be read: $($script:boardWhy)" 1 }
    $script:lastBoard = $board
    $R = @(); $A = @(); $x = 0
    foreach ($i in $board) {
      if ($i.Type -ne "Issue" -or ($i.Labels -contains $lbEpic)) { continue }
      $isBug = $i.Labels -contains $lbBug
      if ($isBug -and $i.Status -eq $stReady) { $x++; if (-not $script:triedSet.ContainsKey($i.Num)) { $R += $i } }
      if (-not $isBug -and $i.Status -eq $stApproved) { $x++; if (-not $script:triedSet.ContainsKey($i.Num)) { $A += $i } }
    }
    if ($R.Count -gt 0) {
      Test-SlotRoom
      foreach ($i in $R) {
        $script:tried.Add([pscustomobject]@{ Num = $i.Num; Step = "/fix all"; K = $script:steps.Count + 1; Before = $i.Status; Title = $i.Title })
        $script:triedSet[$i.Num] = $true
      }
      # k: the smallest of the Ready bugs, the issues left and parallel.fixAllMaxBugs (when not 0)
      $kf = [long]$R.Count
      $leftNow = $limIssues - $script:started
      if ($leftNow -lt $kf) { $kf = $leftNow }
      if ($fixMax -gt 0 -and $fixMax -lt $kf) { $kf = [long]$fixMax }
      if ($kf -lt 1) { $kf = 1 }
      Invoke-Step "/nightmill:fix all" "" ($limTurns * $kf) (Format-Money ($limCost * $kf)) $kf
      continue
    }
    if ($A.Count -gt 0) {
      $best = [int]::MaxValue; $top = @()
      foreach ($i in $A) {
        $rk = [array]::IndexOf($prios, $i.Prio)
        if ($rk -lt 0) { $rk = 999999 }
        if ($rk -lt $best) { $best = $rk; $top = @($i) } elseif ($rk -eq $best) { $top += $i }
      }
      if ($top.Count -gt 1) {
        $nums = @($top | ForEach-Object { [long]$_.Num } | Sort-Object | ForEach-Object { "#$_" })
        if ($best -eq 999999) { $pn = "no priority" } else { $pn = $top[0].Prio }
        Ended "a tie of priorities among the Approved stories $($nums -join ', ') ($pn); the maintainer sets one higher" 0
      }
      $pick = $top[0]
      # the pause of its epic and its limits (iteration 53 decision 8): a skip counts as tried, the step is not run
      Invoke-Gate @("-Issue", $pick.Num)
      if ($script:gateRc -eq 4 -or $script:gateRc -eq 3) {
        $script:tried.Add([pscustomobject]@{ Num = $pick.Num; Step = "/next"; K = 0; Before = $pick.Status; Title = $pick.Title })
        $script:triedSet[$pick.Num] = $true
        if ($script:gateRc -eq 4) {
          $script:outcome[$pick.Num] = [pscustomobject]@{ Kind = "not started"; Text = $script:gateReason }
          Out-Line "drive: #$($pick.Num) not started: $($script:gateReason)"
        } else {
          $why = $script:gateReason
          if ($why.StartsWith("limit: ")) { $why = $why.Substring(7) }
          Invoke-Breach $pick.Num $why $pick.Status "nothing"
          $script:outcome[$pick.Num] = [pscustomobject]@{ Kind = "blocked"; Text = $script:gateReason }
        }
        continue
      }
      if ($script:gateRc -ne 0) { Stop-Gate }
      $spent = [double]0
      foreach ($l in ($script:gateOut -split "`r?`n")) {
        if ($l -match ('^gate: spent on #' + $pick.Num + ': \$([0-9.]+) of ')) { $spent = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
      }
      $bud = $limCost - $spent
      if ($bud -lt 0.01) { $bud = 0.01 }
      Test-SlotRoom
      $script:tried.Add([pscustomobject]@{ Num = $pick.Num; Step = "/next"; K = $script:steps.Count + 1; Before = $pick.Status; Title = $pick.Title })
      $script:triedSet[$pick.Num] = $true
      Invoke-Step "/nightmill:next $($pick.Num)" $pick.Num $limTurns (Format-Money $bud) 1
      continue
    }
    if ($x -eq 0) { Ended "nothing Ready or Approved" 0 }
    Ended "nothing new to pick: every Ready bug and Approved story left was tried in this run" 0
  }
} catch {
  if (-not $script:finished) {
    $msg = One-Line $_.Exception.Message
    Out-Line "drive: ended: the driver failed: $msg"
    Finish "end" "the driver failed: $msg" 1
  }
  throw
} finally {
  if (-not $script:finished) {
    # Ctrl+C: the running step is ended, the summary is posted; PowerShell cannot set the signal's exit code
    if ($null -ne $script:cur) {
      $script:cur.Rec.Rc = "stopped"
      $script:cur.Rec.Dur = Format-LedgerDuration ((Get-LedgerClock) - $script:cur.T0)
      try { Write-RunLine $script:steps.Count "signal" ([string]$script:cur.Rec.Issues) "" "" "" } catch { }
    }
    Out-Line "drive: ended: stopped by SIGINT"
    Finish "end" "stopped by SIGINT" 1
  }
  if ($script:ownLock) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
}

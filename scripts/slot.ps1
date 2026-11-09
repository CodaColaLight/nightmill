# scripts/slot.ps1 - permanent worktrees, one per worker slot (nightmill).
#   slot.ps1 -Status [-Porcelain]        # -Porcelain: one tab separated line per slot, for scripts
#   slot.ps1 -Take feat/foo              # first free slot
#   slot.ps1 -Take fix/1-x -Slot 2       # a given slot
#   slot.ps1 -Release 1                  # after the PR merged
#   slot.ps1 -Abandon 1                  # free a slot whose task was dropped (no merged PR)
#   slot.ps1 -Reap                       # free every busy slot whose PR has merged (-Take does this first)
#   slot.ps1 -Capacity [-SlotCount N] [-AgentLimit M] [-Porcelain]   # show or set the numbers for the session
#   slot.ps1 -Capacity -Clear            # back to the configuration's numbers
# Run it from inside the project: any checkout or worktree of it. Configuration comes from
# .claude/nightmill.json in the main checkout, keys under "worktrees" (see schema/nightmill.schema.json);
# $env:WORKER_SLOTS overrides worktrees.slots. A slot is never removed: a new task only switches it
# to a new branch from the base branch, so build output stays warm. A slot is busy from -Take to
# -Release, -Abandon or an automatic release (a marker file in <root>/.slots, outside any repo) (a take's claim
# counts as busy). Slot N gets port base + N.
# Automatic release (-Reap, and the first step of every -Take; iteration 17): a busy slot is freed when its
# worktree is clean and gh lists a merged PR for its branch whose last commit is the tip of the local branch
# (so a reused branch name or work after the merge keeps the slot busy and nothing is deleted). A slot that
# cannot be judged (gh missing or failing, no fetch) stays busy and a note goes to standard error; the freeing
# never makes a take fail. Same behaviour as slot.sh (--reap).
# Capacity (-Capacity; iteration 22): the slot count and the agent limit can be set during a session. The set
# values are kept in <root>/.slots/capacity.json (untracked, shared by every worktree) until -Capacity -Clear
# or until set again; the tracked config is never edited. Slot count: the live value, then WORKER_SLOTS, then
# worktrees.slots, then 2. Agent limit: the live value, then parallel.maxAgents, then 2. A busy slot above a
# lowered count is retiring: it is no longer handed out, is never touched, and is no longer listed once released.
# Same behaviour as slot.sh (--capacity).
#   slot.ps1 -Report <step> -Slot N -Skill <skill> -Role <role>   # record what the slot's agent is doing
# Reports (-Report; iteration 23): a skill that works in a slot writes its skill, its role, the current step and the
# time of the report into the slot's marker (the keys skill, role, step, reported after slot, branch, since).
# -Status -Porcelain prints them with the agent state: running while the last report is at most
# worktrees.stalledAfterMinutes (default 30) old, stalled after that, unknown without a report. The take does not
# report. Same behaviour as slot.sh (--report).
# Claim (iteration 34): a take claims its slot before it fetches, switches or warms up: it writes a marker with
# "state": "taking" and its process id ("pid") and gives it the marker's name only if no marker exists (bash ln,
# PowerShell File.Move), so two takes never get the same slot; the finished take replaces it with the marker above.
# A failed fetch, switch or warm-up puts the slot back, removes the claim and prints "<step> failed (exit N)". A
# claim whose process has ended is dead: --status shows take-died, and only -Abandon frees it. Same behaviour as
# slot.sh.
# Record (iteration 41): the take, every report and every freeing append one line to <root>/.slots/ledger.tsv (see
# scripts/stages.ps1); a failed append prints one note and changes nothing else. Same behaviour as slot.sh.
param(
  [string]$Take,
  [string]$Release = "0",
  [string]$Abandon = "0",
  [switch]$Reap,
  [switch]$Status,
  [switch]$Porcelain,
  [string]$Slot = "0",
  [string]$Base = "",
  [switch]$SkipWarmup,
  [switch]$Capacity,
  [string]$SlotCount,
  [string]$AgentLimit,
  [switch]$Clear,
  [string]$Report,
  [string]$Skill,
  [string]$Role
)
$ErrorActionPreference = "Stop"
$usageText = "usage: slot.ps1 -Status | -Take <branch> [-Slot N] [-Base <ref>] [-SkipWarmup] | -Release N | -Abandon N | -Reap | -Capacity [-SlotCount N] [-AgentLimit M] [-Clear] [-Porcelain] | -Report <step> -Slot N -Skill <s> -Role <r>"
$hasSlots = $PSBoundParameters.ContainsKey("SlotCount")
$hasAgents = $PSBoundParameters.ContainsKey("AgentLimit")
$hasReport = $PSBoundParameters.ContainsKey("Report")
function Exit-Usage { [Console]::Error.WriteLine($usageText); exit 1 }
# -Slot, -Release and -Abandon take only digits and are normalised to their number (02 is 2); 0 means not given
function ConvertTo-SlotNumber([string]$v) {
  if ($v -notmatch '^[0-9]+\z') { Exit-Usage }
  $n = [long]0
  if (-not [long]::TryParse($v, [ref]$n)) { Exit-Usage }
  return $n
}
[long]$Slot = ConvertTo-SlotNumber $Slot
[long]$Release = ConvertTo-SlotNumber $Release
[long]$Abandon = ConvertTo-SlotNumber $Abandon
if ($hasReport) {
  if ($Take -or $Release -gt 0 -or $Abandon -gt 0 -or $Reap -or $Status -or $Capacity) { Exit-Usage }
} elseif ($PSBoundParameters.ContainsKey("Skill") -or $PSBoundParameters.ContainsKey("Role")) { Exit-Usage }

# The main checkout, wherever this is run from (it may itself be a worktree).
$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { throw "run slot.ps1 from inside a git checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent

$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { throw "no $cfgPath (run /nightmill:init)" }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$wt = $cfg.worktrees

$baseBranch = "main"
if ($cfg.git -and $cfg.git.baseBranch) { $baseBranch = $cfg.git.baseBranch }
if (-not $Base) { $Base = "origin/$baseBranch" }

$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
if ($wt -and $wt.root) { $rootRel = $wt.root }
$root = [System.IO.Path]::GetFullPath((Join-Path $main $rootRel))
$state = Join-Path $root ".slots"
. (Join-Path $PSScriptRoot "lib\ledger.ps1")
$ledger = Join-Path $state "ledger.tsv"
# Write-Record <kind> <slot> <branch> <name> [skill role pr from to issues]: one line of the record, stamped now
function Write-Record([string]$kind, $n, [string]$branch, [string]$name, [string]$sk = "", [string]$ro = "", [string]$pr = "", [string]$from = "", [string]$to = "", [string]$issues = "") {
  Add-LedgerLine $ledger @($kind, (Get-LedgerStamp (Get-LedgerClock)), "$n", $branch, $name, $sk, $ro, $pr, $from, $to, $issues)
}
# Get-PrTimes <pr>: the createdAt, mergedAt and closing issue numbers (joined by ,) of a PR object of gh's JSON;
# PowerShell 7 reads a date-like string as a date, which is written back as gh gives it (UTC, Z)
function Get-PrTimes($p) {
  $vals = @()
  foreach ($k in "createdAt", "mergedAt") {
    $v = $null
    if ($null -ne $p -and $p.PSObject.Properties[$k]) { $v = $p.PSObject.Properties[$k].Value }
    if ($v -is [datetime]) { $v = $v.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + "Z" }
    $vals += $(if ($null -eq $v) { "" } else { [string]$v })
  }
  $nums = @()
  if ($null -ne $p -and $p.PSObject.Properties["closingIssuesReferences"]) {
    foreach ($ref in @($p.closingIssuesReferences)) { if ($null -ne $ref -and $null -ne $ref.number) { $nums += "$($ref.number)" } }
  }
  return [pscustomobject]@{ From = $vals[0]; To = $vals[1]; Issues = ($nums -join ",") }
}

if ($env:WORKER_SLOTS) {
  if ($env:WORKER_SLOTS -notmatch '^[1-9][0-9]?$') { throw "WORKER_SLOTS must be a number from 1 to 99" }
}

# The numbers: what the configuration alone gives, and the effective ones (see the header)
$capPath = Join-Path $state "capacity.json"
$cfgSlots = 2; $cfgSlotsFrom = "default"
if ($wt -and $null -ne $wt.slots -and "$($wt.slots)" -ne "") { $cfgSlots = [int]$wt.slots; $cfgSlotsFrom = "config" }
$cfgAgents = 2; $cfgAgentsFrom = "default"
if ($cfg.parallel -and $null -ne $cfg.parallel.maxAgents -and "$($cfg.parallel.maxAgents)" -ne "") { $cfgAgents = [int]$cfg.parallel.maxAgents; $cfgAgentsFrom = "config" }
function Test-Count([string]$v) { return ($v -cmatch '^[1-9][0-9]?\z') }

# Read-Capacity: the usable values of capacity.json in $liveSlots and $liveAgents ($null when not set); an unusable
# file or value is ignored, with one note on standard error
function Read-Capacity {
  $script:liveSlots = $null; $script:liveAgents = $null
  if (-not (Test-Path -LiteralPath $capPath)) { return }
  $text = [System.IO.File]::ReadAllText($capPath)
  $invalid = $false
  try { $doc = ConvertFrom-Json -InputObject $text } catch { $doc = $null; $invalid = $true }
  if ($invalid -or ($null -eq $doc -and $text.Trim() -ne "null")) {
    [Console]::Error.WriteLine("slot: capacity.json: not valid JSON; using the configuration"); return
  }
  if (-not ($doc -is [System.Management.Automation.PSCustomObject])) {
    [Console]::Error.WriteLine("slot: capacity.json: not an object; using the configuration"); return
  }
  $reasons = @()
  foreach ($k in "slots", "maxAgents") {
    $p = $doc.PSObject.Properties[$k]
    if (-not $p) { continue }
    $v = $p.Value
    if (($v -is [int] -or $v -is [long]) -and (Test-Count "$v")) {
      if ($k -eq "slots") { $script:liveSlots = [int]$v } else { $script:liveAgents = [int]$v }
    } else {
      $reasons += "$k is not a whole number from 1 to 99"
    }
  }
  if ($reasons.Count -gt 0) { [Console]::Error.WriteLine("slot: capacity.json: $($reasons -join ', '); using the configuration") }
}

# Resolve-Capacity: $count and $slotsFrom, $agents and $agentsFrom, from the live values, WORKER_SLOTS and the configuration
function Resolve-Capacity {
  if ($null -ne $script:liveSlots) { $script:count = $script:liveSlots; $script:slotsFrom = "live" }
  elseif ($env:WORKER_SLOTS) { $script:count = [int]$env:WORKER_SLOTS; $script:slotsFrom = "WORKER_SLOTS" }
  else { $script:count = $cfgSlots; $script:slotsFrom = $cfgSlotsFrom }
  if ($null -ne $script:liveAgents) { $script:agents = $script:liveAgents; $script:agentsFrom = "live" }
  else { $script:agents = $cfgAgents; $script:agentsFrom = $cfgAgentsFrom }
}
# Get-From <source> <value of the configuration alone>: the text in brackets
function Get-From([string]$src, $c) { if ($src -eq "live" -or $src -eq "WORKER_SLOTS") { "$src; config $c" } else { $src } }

Read-Capacity
Resolve-Capacity

# Get-LastSlot: the last slot to list or reap: the count, or a higher slot that is busy (retiring)
function Get-LastSlot {
  $top = $count
  if (Test-Path -LiteralPath $state) {
    foreach ($f in @(Get-ChildItem -LiteralPath $state -Filter "slot-*.json" -File)) {
      if ($f.Name -match '^slot-([1-9][0-9]*)\.json$' -and [int]$Matches[1] -gt $top) { $top = [int]$Matches[1] }
    }
  }
  return $top
}

function Get-SlotDir($n) { Join-Path $root "slot-$n" }
function Get-Marker($n) { Join-Path $state "slot-$n.json" }
function Read-Marker($n) {
  $p = Get-Marker $n
  if (Test-Path $p) { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
}
function Write-Lf($path, $text) { [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false)) }
# Get-Text <marker> <key>: the value as the text in the file ("" when absent or null); PowerShell 7 reads a date-like
# string as a date, which is formatted back with ToString("s")
function Get-Text($m, [string]$key) {
  if ($null -eq $m) { return "" }
  $p = $m.PSObject.Properties[$key]
  if (-not $p -or $null -eq $p.Value) { return "" }
  if ($p.Value -is [datetime]) { return $p.Value.ToString("s") }
  return [string]$p.Value
}
# ConvertTo-JsonString <text>: the text as a JSON string literal, escaped as json_quote of lib/json.sh does
function ConvertTo-JsonString([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    $c = [int]$ch
    if ($ch -eq '"') { [void]$sb.Append('\"') }
    elseif ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ($c -eq 10) { [void]$sb.Append('\n') }
    elseif ($c -eq 9) { [void]$sb.Append('\t') }
    elseif ($c -eq 13) { [void]$sb.Append('\r') }
    elseif ($c -eq 8) { [void]$sb.Append('\b') }
    elseif ($c -eq 12) { [void]$sb.Append('\f') }
    elseif ($c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $c)) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function Test-Stamp([string]$s) { return ($s -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\z') }
# Get-Stamp YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC, the arithmetic of stamp in lib/status.awk
function Get-Stamp([string]$s) {
  $yr = [long]$s.Substring(0, 4); $mon = [long]$s.Substring(5, 2); $day = [long]$s.Substring(8, 2)
  if ($mon -le 2) { $yr-- }
  $yy = if ($yr -ge 0) { $yr } else { $yr - 399 }
  $era = [long][math]::Truncate($yy / 400)
  $yoe = $yr - $era * 400
  $shift = if ($mon -gt 2) { -3 } else { 9 }
  $doy = [long][math]::Truncate((153 * ($mon + $shift) + 2) / 5) + $day - 1
  $doe = $yoe * 365 + [long][math]::Truncate($yoe / 4) - [long][math]::Truncate($yoe / 100) + $doy
  return [long](($era * 146097 + $doe - 719468) * 86400 + [long]$s.Substring(11, 2) * 3600 + [long]$s.Substring(14, 2) * 60 + [long]$s.Substring(17, 2))
}
# Get-StalledAfter: the threshold in minutes, worktrees.stalledAfterMinutes or 30 (an unusable value with one note)
function Get-StalledAfter {
  if (-not $wt) { return 30 }
  $p = $wt.PSObject.Properties["stalledAfterMinutes"]
  if (-not $p -or $null -eq $p.Value) { return 30 }
  $v = $p.Value
  if (($v -is [int] -or $v -is [long]) -and $v -ge 1 -and $v -le 999999) { return [long]$v }
  [Console]::Error.WriteLine("slot: worktrees.stalledAfterMinutes must be a whole number of at least 1; using 30")
  return 30
}

# Run a native command and keep its output and its error text apart (redirecting a native command's stderr in
# Windows PowerShell 5.1 turns its progress lines into errors); returns Out, Err and Code.
function Invoke-Native([string]$file, [string[]]$arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file
  $psi.Arguments = (@($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " ")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Out = $out; Err = $errTask.Result; Code = $p.ExitCode }
}
function Get-FirstLine([string]$text) { (@($text -split "`r?`n" | Where-Object { $_ -ne "" }) | Select-Object -First 1) }
# Exit-Line <text>: one plain line on standard error, then exit 1 (no error record)
function Exit-Line([string]$text) { [Console]::Error.WriteLine($text); exit 1 }

# Get-Claim <n> [marker]: State none (no marker, or a finished one), live or dead, and Pid (the usable pid, 1 to
# 2147483647, or ""); a taking marker is live while a process with its pid runs on this machine
function Get-Claim($n, $m = $null) {
  if ($null -eq $m) { $m = Read-Marker $n }
  if ($null -eq $m -or (Get-Text $m "state") -cne "taking") { return [pscustomobject]@{ State = "none"; Pid = "" } }
  $t = Get-Text $m "pid"
  $p = ""
  if ($t -cmatch '^[1-9][0-9]{0,9}\z' -and [long]$t -le 2147483647) { $p = $t }
  $st = "dead"
  if ($p -and (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)) { $st = "live" }
  return [pscustomobject]@{ State = $st; Pid = $p }
}
# Get-ClaimLine <n> <claim>: the refusal of a command on a taking slot (decision 7 of iteration 34)
function Get-ClaimLine($n, $c) {
  if ($c.State -eq "live") { return "slot $n is being taken (process $($c.Pid) is still running); wait for the take to end" }
  if ($c.Pid) { return "slot $n has a take that did not finish (process $($c.Pid) has ended); free it with -Abandon $n" }
  return "slot $n has a take that did not finish (no process recorded); free it with -Abandon $n"
}
# Get-TakingText <n> <branch> <since> [pid]: the text of a taking marker, as json_marker_taking of lib/json.sh
function Get-TakingText($n, [string]$branch, [string]$since, [string]$procId = "") {
  $lines = @("{", "  `"slot`": $n,", "  `"branch`": $(ConvertTo-JsonString $branch),", "  `"since`": $(ConvertTo-JsonString $since),")
  if ($procId) { $lines += @("  `"state`": `"taking`",", "  `"pid`": $procId") } else { $lines += "  `"state`": `"taking`"" }
  $lines += "}"
  return (($lines -join "`n") + "`n")
}

$script:freed = 0
# Invoke-Reap: free every busy slot whose PR has merged (see the header); one line per freed slot
function Invoke-Reap {
  $fetched = 0
  $freason = ""
  $gc = Get-Command gh -ErrorAction SilentlyContinue
  $top = Get-LastSlot
  for ($n = 1; $n -le $top; $n++) {
    $m = Read-Marker $n
    if (-not $m) { continue }
    # a take's claim (live or dead) is never judged, freed or switched
    if ((Get-Text $m "state") -ceq "taking") { continue }
    $dir = Get-SlotDir $n
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    if (@(git -C $dir status --porcelain).Count -gt 0) { continue }
    $branch = [string]$m.branch
    if (-not $branch) { continue }
    $tip = git -C $dir rev-parse "refs/heads/$branch" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tip) { continue }
    $tip = ([string]$tip).Trim()
    if (-not $gc) {
      [Console]::Error.WriteLine("slot ${n}: not checked for a merged PR (gh is not on the PATH)")
      continue
    }
    $r = Invoke-Native $gc.Source @("pr", "list", "--state", "merged", "--head", $branch, "--json", "number,headRefOid,createdAt,mergedAt,closingIssuesReferences")
    if ($r.Code -ne 0) {
      [Console]::Error.WriteLine("slot ${n}: not checked for a merged PR ($(Get-FirstLine $r.Err))")
      continue
    }
    $prs = @()
    try { $prs = @(ConvertFrom-Json -InputObject $r.Out) }
    catch {
      [Console]::Error.WriteLine("slot ${n}: not checked for a merged PR (gh did not answer with JSON)")
      continue
    }
    # the first merged PR, in the order gh printed them, whose head commit is the tip of the local branch
    $pr = $null; $prObj = $null
    # Windows PowerShell passes a JSON array on as one item; the pipe unrolls it to one object per PR
    foreach ($p in @($prs | ForEach-Object { $_ })) { if ([string]$p.headRefOid -ceq $tip) { $pr = $p.number; $prObj = $p; break } }
    if ($null -eq $pr) { continue }
    if ($fetched -eq 0) {
      $f = Invoke-Native "git" @("fetch", "origin", $baseBranch)
      if ($f.Code -eq 0) { $fetched = 1 } else { $fetched = -1; $freason = Get-FirstLine $f.Err }
    }
    if ($fetched -ne 1) {
      [Console]::Error.WriteLine("slot ${n}: not checked for a merged PR (git fetch origin $baseBranch failed: $freason)")
      continue
    }
    $s = Invoke-Native "git" @("-C", $dir, "switch", "--detach", "origin/$baseBranch")
    if ($s.Code -ne 0) { continue }
    $null = Invoke-Native "git" @("branch", "-D", $branch)
    Remove-Item (Get-Marker $n)
    $pt = Get-PrTimes $prObj
    Write-Record "free" $n $branch "reaped" "" "" "$pr" $pt.From $pt.To $pt.Issues
    Write-Host "Slot $n is free (was $branch, PR #$pr), released automatically." -ForegroundColor Green
    $script:freed++
  }
}

# Invoke-Warmup <n> <dir>: runs the warm-up commands; on a failure it stops and leaves the failing command's number
# and exit code in $script:warmFail (Index, Code), else $null. The hash of the lockfile, the read and the write of
# the stamp belong to the command (code 1 when they throw).
function Invoke-Warmup($n, $dir) {
  $script:warmFail = $null
  if ($SkipWarmup -or -not $wt -or -not $wt.warmup) { return }
  $i = 0
  foreach ($w in @($wt.warmup)) {
    $i++
    $where = $dir
    if ($w.dir) { $where = Join-Path $dir $w.dir }
    $stamp = Join-Path $state "slot-$n.warmup-$i"
    $hash = ""
    $same = $false
    if ($w.lockfile) {
      $lf = Join-Path $dir $w.lockfile
      if (Test-Path $lf) {
        try {
          $hash = (Get-FileHash $lf -Algorithm SHA256).Hash
          $have = ""
          if (Test-Path -LiteralPath $stamp -PathType Leaf) { $have = (Get-Content -LiteralPath $stamp -Raw).Trim() }
          $same = ($have -eq $hash)
        } catch {
          [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message))
          $script:warmFail = [pscustomobject]@{ Index = $i; Code = 1 }; return
        }
      }
    }
    if ($same) { continue }
    Write-Host "warm-up $i in $where`: $($w.command)" -ForegroundColor Cyan
    Push-Location $where
    $global:LASTEXITCODE = 0
    $code = 0
    try { Invoke-Expression $w.command; $code = $LASTEXITCODE }
    catch { [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message)); $code = 1 }
    finally { Pop-Location }
    if ($code -ne 0) { $script:warmFail = [pscustomobject]@{ Index = $i; Code = $code }; return }
    if ($hash) {
      try { Write-Lf $stamp $hash }
      catch {
        [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message))
        $script:warmFail = [pscustomobject]@{ Index = $i; Code = 1 }; return
      }
    }
  }
}

function Show-Hints($n, $dir, $branch) {
  Write-Host ""
  Write-Host "Slot $n is yours: $dir  (branch $branch)" -ForegroundColor Green
  Write-Host "  cd '$dir'"
  $ports = @()
  if ($wt -and $wt.ports) { $ports = @($wt.ports.PSObject.Properties) }
  foreach ($p in $ports) { Write-Host ("  port {0}: {1}" -f $p.Name, ([int]$p.Value + $n)) }
  if ($wt -and $wt.runHints) {
    Write-Host "Run it next to other slots:"
    foreach ($h in @($wt.runHints)) {
      $line = ([string]$h).Replace("{slot}", "$n")
      foreach ($p in $ports) { $line = $line.Replace("{port.$($p.Name)}", "$([int]$p.Value + $n)") }
      Write-Host "  $line"
    }
  }
}

if ($Capacity) {
  if ($Take -or $Release -gt 0 -or $Abandon -gt 0 -or $Status -or $Reap) { Exit-Usage }
  if ($Clear -and ($hasSlots -or $hasAgents)) { Exit-Usage }
  $bad = $false
  if ($hasSlots -and -not (Test-Count $SlotCount)) {
    [Console]::Error.WriteLine("capacity: -SlotCount must be a whole number from 1 to 99, got `"$SlotCount`""); $bad = $true
  }
  if ($hasAgents -and -not (Test-Count $AgentLimit)) {
    [Console]::Error.WriteLine("capacity: -AgentLimit must be a whole number from 1 to 99, got `"$AgentLimit`""); $bad = $true
  }
  if ($bad) { exit 1 }
  $wasSlots = $count; $wasAgents = $agents; $msg = ""
  if ($Clear) {
    if (Test-Path -LiteralPath $capPath) {
      Remove-Item -LiteralPath $capPath
      $liveSlots = $null; $liveAgents = $null; Resolve-Capacity
      $msg = "capacity: cleared (slots $wasSlots -> $count, agents $wasAgents -> $agents)"
    } else {
      $msg = "capacity: nothing to clear"
    }
  } elseif ($hasSlots -or $hasAgents) {
    if ($hasSlots) { $liveSlots = [int]$SlotCount }
    if ($hasAgents) { $liveAgents = [int]$AgentLimit }
    $text = "{`n"
    if ($null -ne $liveSlots) { $text += "  `"slots`": $liveSlots,`n" }
    if ($null -ne $liveAgents) { $text += "  `"maxAgents`": $liveAgents,`n" }
    $text += "  `"since`": `"$((Get-Date).ToString('s'))`"`n}`n"
    # written to a temporary file in the same folder and moved over the old one: a reader never sees half a file
    New-Item -ItemType Directory -Force $state | Out-Null
    $tmpCap = Join-Path $state ("capacity.json." + [guid]::NewGuid().ToString("N").Substring(0, 8))
    Write-Lf $tmpCap $text
    if (Test-Path -LiteralPath $capPath) { [System.IO.File]::Replace($tmpCap, $capPath, [NullString]::Value) } else { [System.IO.File]::Move($tmpCap, $capPath) }
    Resolve-Capacity
    function Change([string]$what, $was, $now) { if ("$was" -eq "$now") { "$what $now (unchanged)" } else { "$what $was -> $now" } }
    $parts = @()
    if ($hasSlots) { $parts += (Change "slots" $wasSlots $count) }
    if ($hasAgents) { $parts += (Change "agents" $wasAgents $agents) }
    $msg = "capacity: " + ($parts -join ", ")
  }
  if ($Porcelain) {
    Write-Output ("slots`t{0}`t{1}`t{2}" -f $count, $slotsFrom, $cfgSlots)
    Write-Output ("agents`t{0}`t{1}`t{2}" -f $agents, $agentsFrom, $cfgAgents)
  } elseif ($msg) {
    Write-Output $msg
  } else {
    Write-Output "slots: $count ($(Get-From $slotsFrom $cfgSlots))"
    Write-Output "agents: $agents ($(Get-From $agentsFrom $cfgAgents))"
  }
  exit 0
}
if ($Clear -or $hasSlots -or $hasAgents) { Exit-Usage }

if ($hasReport) {
  # -Report <step> -Slot N -Skill <skill> -Role <role>: rewrite the marker of slot N with the report
  if ($Slot -le 0) { [Console]::Error.WriteLine("report needs a slot number"); exit 1 }
  $mp = Get-Marker $Slot
  if (-not (Test-Path -LiteralPath $mp)) { [Console]::Error.WriteLine("slot $Slot is not in use"); exit 1 }
  $c = $null
  try { $c = Get-Claim $Slot } catch { }
  if ($c -and $c.State -ne "none") { Exit-Line (Get-ClaimLine $Slot $c) }
  foreach ($pair in @(@("step", $Report), @("skill", $Skill), @("role", $Role))) {
    if ([string]$pair[1] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,39}\z') {
      [Console]::Error.WriteLine("report: the $($pair[0]) must be 1 to 40 letters, digits or -, got `"$($pair[1])`""); exit 1
    }
  }
  $text = [System.IO.File]::ReadAllText($mp)
  $invalid = $false
  try { $m = ConvertFrom-Json -InputObject $text } catch { $m = $null; $invalid = $true }
  if ($invalid -or ($null -eq $m -and $text.Trim() -ne "null")) { [Console]::Error.WriteLine("slot ${Slot}: the marker is not valid JSON"); exit 1 }
  $lines = @(
    "{",
    "  `"slot`": $Slot,",
    "  `"branch`": $(ConvertTo-JsonString (Get-Text $m 'branch')),",
    "  `"since`": $(ConvertTo-JsonString (Get-Text $m 'since')),",
    "  `"skill`": $(ConvertTo-JsonString $Skill),",
    "  `"role`": $(ConvertTo-JsonString $Role),",
    "  `"step`": $(ConvertTo-JsonString $Report),",
    "  `"reported`": $(ConvertTo-JsonString (Get-Date).ToString('s'))",
    "}"
  )
  $tmpReport = Join-Path $state "slot-$Slot.report.tmp"
  Write-Lf $tmpReport (($lines -join "`n") + "`n")
  # moved over the marker only while it still exists: a report never brings back a released slot
  if (Test-Path -LiteralPath $mp) {
    [System.IO.File]::Replace($tmpReport, $mp, [NullString]::Value)
    Write-Record "step" $Slot (Get-Text $m 'branch') $Report $Skill $Role
  }
  else { Remove-Item -LiteralPath $tmpReport }
  exit 0
}

if ($Status -and $Porcelain) {
  # A free slot: <n> TAB free. A busy slot, ten fields: <n> TAB busy TAB <branch> TAB <since> TAB <retiring> TAB
  # <agent> TAB <skill> TAB <role> TAB <step> TAB <reported>; retiring for a busy slot above the count, else empty;
  # agent: running, stalled or unknown (see the header). A take's claim (iteration 34) is a busy line with the agent
  # unknown, empty skill, role and reported, and the step taking while its take runs or take-died once it has ended
  $threshold = (Get-StalledAfter) * 60
  if ($env:NIGHTMILL_NOW) { $now = [long]$env:NIGHTMILL_NOW } else { $now = Get-Stamp ((Get-Date).ToString("s")) }
  $top = Get-LastSlot
  for ($i = 1; $i -le $top; $i++) {
    $m = Read-Marker $i
    if ($m) {
      $retiring = ""
      if ($i -gt $count) { $retiring = "retiring" }
      $c = Get-Claim $i $m
      if ($c.State -ne "none") {
        $stepText = if ($c.State -eq "live") { "taking" } else { "take-died" }
        Write-Output ((@("$i", "busy", (Get-Text $m "branch"), (Get-Text $m "since"), $retiring, "unknown", "", "", $stepText, "")) -join "`t")
        continue
      }
      $reported = Get-Text $m "reported"
      $agent = "unknown"
      if (Test-Stamp $reported) {
        $age = $now - (Get-Stamp $reported)
        if ($age -lt 0) { $age = 0 }
        if ($age -le $threshold) { $agent = "running" } else { $agent = "stalled" }
      }
      Write-Output ((@("$i", "busy", (Get-Text $m "branch"), (Get-Text $m "since"), $retiring, $agent, (Get-Text $m "skill"), (Get-Text $m "role"), (Get-Text $m "step"), $reported)) -join "`t")
    } elseif ($i -le $count) { Write-Output ("{0}`tfree" -f $i) }
  }
  exit 0
}

if ($Status) {
  Write-Host "slots = $count  root = $root"
  Write-Host "capacity: slots $count ($(Get-From $slotsFrom $cfgSlots)), agents $agents ($(Get-From $agentsFrom $cfgAgents))"
  $top = Get-LastSlot
  for ($i = 1; $i -le $top; $i++) {
    $dir = Get-SlotDir $i
    $m = Read-Marker $i
    if ($i -gt $count -and -not $m) { continue }
    $where = if (Test-Path $dir) { "ready" } else { "not created yet" }
    $busy = "free"
    if ($m) {
      $c = Get-Claim $i $m
      $busy = "busy: $(Get-Text $m 'branch') since $(Get-Text $m 'since')"
      if ($c.State -eq "live") { $busy = "taking: $(Get-Text $m 'branch') since $(Get-Text $m 'since') (process $($c.Pid))" }
      elseif ($c.State -eq "dead") {
        $what = if ($c.Pid) { "process $($c.Pid) has ended" } else { "no process recorded" }
        $busy = "taking: $(Get-Text $m 'branch') since $(Get-Text $m 'since') ($what; free it with -Abandon $i)"
      }
    }
    if ($i -gt $count) { $busy += " (retiring)" }
    $dirty = ""
    if (Test-Path $dir) {
      $n = @(git -C $dir status --porcelain).Count
      if ($n -gt 0) { $dirty = "  ($n uncommitted files)" }
    }
    Write-Host ("slot {0}  {1,-15} {2}{3}" -f $i, $where, $busy, $dirty)
  }
  exit 0
}

if ($Reap) {
  New-Item -ItemType Directory -Force $state | Out-Null
  Invoke-Reap
  if ($script:freed -eq 0) { Write-Host "No slot freed." }
  exit 0
}

# Invoke-Claim <n>: claims slot n for the take (see Claim in the header): the complete taking marker is written to a
# temporary file and given the marker's name only if no marker exists. $false when another take has the slot;
# exits 1 when the claim cannot be written or published.
function Invoke-Claim([int]$n) {
  $tmpc = Join-Path $state "slot-$n.claim.$PID.tmp"
  $mk = Get-Marker $n
  $script:claimSince = (Get-Date).ToString("s")
  $script:claimAt = Get-LedgerClock
  try { Write-Lf $tmpc (Get-TakingText $n $Take $script:claimSince "$PID") }
  catch {
    [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message))
    Remove-Item -LiteralPath $tmpc -Force -ErrorAction SilentlyContinue
    Exit-Line "claim failed (exit 1); slot $n was not claimed"
  }
  # for the tests only: hold every take here until the file exists (60 s at most)
  if ($env:NIGHTMILL_CLAIM_GATE) {
    $g = 0
    while (-not (Test-Path -LiteralPath $env:NIGHTMILL_CLAIM_GATE) -and $g -lt 600) { $g++; Start-Sleep -Milliseconds 100 }
  }
  try { [System.IO.File]::Move($tmpc, $mk); return $true }
  catch {
    $why = Get-FirstLine $_.Exception.Message
    Remove-Item -LiteralPath $tmpc -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $mk) { return $false }
    Exit-Line "slot ${n}: could not claim ($why)"
  }
}
# Set-LeftClaim: the claim stays, rewritten without its pid, so that it is dead at once and -Abandon frees it
function Set-LeftClaim {
  $tmpl = Join-Path $state "slot-$n.left.$PID.tmp"
  try {
    Write-Lf $tmpl (Get-TakingText $n $Take $script:claimSince)
    [System.IO.File]::Replace($tmpl, $mk, [NullString]::Value)
  } catch {
    Remove-Item -LiteralPath $tmpl -Force -ErrorAction SilentlyContinue
  }
}
# Invoke-Git <arguments>: git with its output and error text passed through; returns the exit code
function Invoke-Git { & git @args | Out-Host; return $LASTEXITCODE }
# Undo-Take <step> <code>: after a failed step, put the slot back as it was and remove the claim; exits 1
function Undo-Take([string]$step, $code) {
  $ok = $true
  if ($script:created) {
    if ((Invoke-Git worktree remove --force $dir) -ne 0) { $ok = $false }
  } elseif ($script:recorded) {
    if (@(git -C $dir status --porcelain).Count -gt 0) {
      [Console]::Error.WriteLine("slot $n has uncommitted files: $dir (commit, stash or discard them first)"); $ok = $false
    } else {
      $curHead = git -C $dir rev-parse HEAD
      if ($LASTEXITCODE -ne 0 -or $null -eq $curHead) { $curHead = "" } else { $curHead = ([string]$curHead).Trim() }
      $curBranch = git -C $dir symbolic-ref -q --short HEAD
      if ($LASTEXITCODE -ne 0 -or $null -eq $curBranch) { $curBranch = "" } else { $curBranch = ([string]$curBranch).Trim() }
      if ($curHead -ne $script:oldHead -or $curBranch -cne $script:oldBranch) {
        if ($script:oldBranch) { $sc = Invoke-Git -C $dir switch $script:oldBranch } else { $sc = Invoke-Git -C $dir switch --detach $script:oldHead }
        if ($sc -ne 0) { $ok = $false }
      }
    }
  }
  if ($ok -and $script:recorded -and -not $script:hadBranch) {
    $tip = git -C $main rev-parse --verify -q "refs/heads/$Take"
    if ($LASTEXITCODE -eq 0 -and $tip -and ([string]$tip).Trim() -eq $script:baseCommit) {
      if ((Invoke-Git -C $main branch -D $Take) -ne 0) { $ok = $false }
    }
  }
  if ($ok) {
    try { Remove-Item -LiteralPath $mk -Force } catch { [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message)); $ok = $false }
  }
  if ($ok) { Exit-Line "$step failed (exit $code); slot $n is free again" }
  Set-LeftClaim
  Exit-Line "$step failed (exit $code); slot $n could not be put back and stays claimed: free it with -Abandon $n"
}
# Complete-Take: the finished marker over the claim, then the hints
function Complete-Take {
  $tmpt = Join-Path $state "slot-$n.take.tmp"
  try {
    $marker = @{ slot = $n; branch = $Take; since = (Get-Date).ToString("s") } | ConvertTo-Json
    Write-Lf $tmpt $marker
    [System.IO.File]::Replace($tmpt, $mk, [NullString]::Value)
  } catch {
    [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message))
    Remove-Item -LiteralPath $tmpt -Force -ErrorAction SilentlyContinue
    Set-LeftClaim
    Exit-Line "write marker failed (exit 1); slot $n stays claimed: free it with -Abandon $n"
  }
  $doneAt = Get-LedgerStamp (Get-LedgerClock)
  Add-LedgerLine $ledger @("take", $doneAt, "$n", $Take, "take", "", "", "", (Get-LedgerStamp $script:claimAt), $doneAt, "")
  Show-Hints $n $dir $Take
}

if ($Take) {
  New-Item -ItemType Directory -Force $state | Out-Null
  Invoke-Reap
  $script:claimSince = ""
  $n = $Slot
  # 1 pick and claim
  if ($n -eq 0) {
    for ($i = 1; $i -le $count; $i++) {
      if (Read-Marker $i) { continue }
      if (Invoke-Claim $i) { $n = $i; break }
    }
    if ($n -eq 0) { Exit-Line "all $count slots are busy; see slot.ps1 -Status" }
  } else {
    if ($n -lt 1 -or $n -gt $count) { Exit-Line "slot must be 1..$count" }
    if (Read-Marker $n) { Exit-Line "slot $n is busy" }
    if (-not (Invoke-Claim $n)) { Exit-Line "slot $n is busy" }
  }
  $mk = Get-Marker $n
  $dir = Get-SlotDir $n
  $script:created = $false; $script:recorded = $false; $script:oldHead = ""; $script:oldBranch = ""
  $script:hadBranch = $true; $script:baseCommit = ""

  # 2 fetch, at most 3 attempts, 1 s apart
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    git fetch origin $baseBranch
    $fc = $LASTEXITCODE
    if ($fc -eq 0) { break }
    if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
  }
  if ($fc -ne 0) { Undo-Take "git fetch" $fc }

  # 3 the worktree
  if (-not (Test-Path $dir)) {
    git worktree add --detach $dir $Base
    if ($LASTEXITCODE -ne 0) { Undo-Take "git worktree add" $LASTEXITCODE }
    $script:created = $true
  } elseif (@(git -C $dir status --porcelain).Count -gt 0) {
    try { Remove-Item -LiteralPath $mk -Force } catch { [Console]::Error.WriteLine((Get-FirstLine $_.Exception.Message)); Set-LeftClaim }
    Exit-Line "slot $n has uncommitted files; deal with them first: $dir"
  }

  # 4 what the restore puts back
  $h = git -C $dir rev-parse HEAD
  if ($LASTEXITCODE -ne 0) { Undo-Take "git switch" $LASTEXITCODE }
  $script:oldHead = ([string]$h).Trim()
  $h = git -C $dir symbolic-ref -q --short HEAD
  $sc = $LASTEXITCODE
  if ($sc -eq 0) { $script:oldBranch = ([string]$h).Trim() } elseif ($sc -ne 1) { Undo-Take "git switch" $sc }
  git -C $dir show-ref --verify --quiet "refs/heads/$Take"
  $sc = $LASTEXITCODE
  if ($sc -eq 0) { $script:hadBranch = $true } elseif ($sc -eq 1) { $script:hadBranch = $false } else { Undo-Take "git switch" $sc }
  if (-not $script:hadBranch) {
    $h = git -C $dir rev-parse "$Base^{commit}"
    if ($LASTEXITCODE -ne 0) { Undo-Take "git switch" $LASTEXITCODE }
    $script:baseCommit = ([string]$h).Trim()
  }
  $script:recorded = $true

  # 5 switch
  if ($script:hadBranch) { git -C $dir switch $Take } else { git -C $dir switch -c $Take --no-track $Base }
  if ($LASTEXITCODE -ne 0) { Undo-Take "git switch" $LASTEXITCODE }

  # 6 warm-up
  Invoke-Warmup $n $dir
  if ($script:warmFail) { Undo-Take "warm-up $($script:warmFail.Index)" $script:warmFail.Code }

  # 7 finish
  Complete-Take
  exit 0
}

if ($Release -gt 0) {
  $n = $Release
  $m = Read-Marker $n
  if (-not $m) { throw "slot $n is not in use" }
  $c = Get-Claim $n $m
  if ($c.State -ne "none") { Exit-Line (Get-ClaimLine $n $c) }
  $dir = Get-SlotDir $n
  if (@(git -C $dir status --porcelain).Count -gt 0) { throw "slot $n has uncommitted files: $dir" }
  git fetch origin $baseBranch
  if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }
  $prOut = gh pr list --state merged --head $m.branch --json number,createdAt,mergedAt,closingIssuesReferences
  $pr0 = $null
  try { $pr0 = ConvertFrom-Json -InputObject ((@($prOut) -join "`n")) | ForEach-Object { $_ } | Select-Object -First 1 } catch { $pr0 = $null }
  $merged = ""
  if ($null -ne $pr0 -and $null -ne $pr0.PSObject.Properties["number"]) { $merged = "$($pr0.number)" }
  if (-not $merged) {
    throw "no merged PR for $($m.branch). Merge it first, or free the slot with -Abandon $n."
  }
  git -C $dir switch --detach "origin/$baseBranch"
  if ($LASTEXITCODE -ne 0) { throw "git switch failed" }
  git branch -D $m.branch
  Remove-Item (Get-Marker $n)
  $pt = Get-PrTimes $pr0
  Write-Record "free" $n ([string]$m.branch) "released" "" "" $merged $pt.From $pt.To $pt.Issues
  Write-Host "Slot $n is free (was $($m.branch), PR #$merged)." -ForegroundColor Green
  exit 0
}

if ($Abandon -gt 0) {
  $n = $Abandon
  $m = Read-Marker $n
  if (-not $m) { throw "slot $n is not in use" }
  $c = Get-Claim $n $m
  if ($c.State -eq "live") { Exit-Line (Get-ClaimLine $n $c) }
  $dir = Get-SlotDir $n
  if ($c.State -eq "dead") {
    # a take that did not finish: freed after the same checks, the local branch is kept
    $branch = Get-Text $m "branch"
    if (Test-Path -LiteralPath $dir) {
      if (@(git -C $dir status --porcelain).Count -gt 0) { throw "slot $n has uncommitted files: $dir (commit, stash or discard them first)" }
      git -C $dir switch --detach $Base
      if ($LASTEXITCODE -ne 0) { throw "git switch failed" }
    }
    Remove-Item (Get-Marker $n)
    Write-Host "Slot $n is free (was $branch, a take that did not finish; the local branch is kept, delete it yourself if unwanted)." -ForegroundColor Yellow
    exit 0
  }
  if (@(git -C $dir status --porcelain).Count -gt 0) { throw "slot $n has uncommitted files: $dir (commit, stash or discard them first)" }
  git -C $dir switch --detach $Base
  if ($LASTEXITCODE -ne 0) { throw "git switch failed" }
  Remove-Item (Get-Marker $n)
  Write-Record "free" $n ([string]$m.branch) "abandoned"
  Write-Host "Slot $n is free (was $($m.branch); the local branch is kept, delete it yourself if unwanted)." -ForegroundColor Yellow
  exit 0
}

Write-Host $usageText
exit 1

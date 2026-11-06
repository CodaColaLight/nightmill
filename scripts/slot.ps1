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
# -Release, -Abandon or an automatic release (a marker file in <root>/.slots, outside any repo). Slot N gets
# port base + N.
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
param(
  [string]$Take,
  [int]$Release = 0,
  [int]$Abandon = 0,
  [switch]$Reap,
  [switch]$Status,
  [switch]$Porcelain,
  [int]$Slot = 0,
  [string]$Base = "",
  [switch]$SkipWarmup,
  [switch]$Capacity,
  [string]$SlotCount,
  [string]$AgentLimit,
  [switch]$Clear
)
$ErrorActionPreference = "Stop"
$usageText = "usage: slot.ps1 -Status | -Take <branch> [-Slot N] [-Base <ref>] [-SkipWarmup] | -Release N | -Abandon N | -Reap | -Capacity [-SlotCount N] [-AgentLimit M] [-Clear] [-Porcelain]"
$hasSlots = $PSBoundParameters.ContainsKey("SlotCount")
$hasAgents = $PSBoundParameters.ContainsKey("AgentLimit")
function Exit-Usage { [Console]::Error.WriteLine($usageText); exit 1 }

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
    $r = Invoke-Native $gc.Source @("pr", "list", "--state", "merged", "--head", $branch, "--json", "number,headRefOid")
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
    $pr = $null
    foreach ($p in $prs) { if ([string]$p.headRefOid -ceq $tip) { $pr = $p.number; break } }
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
    Write-Host "Slot $n is free (was $branch, PR #$pr), released automatically." -ForegroundColor Green
    $script:freed++
  }
}

function Invoke-Warmup($n, $dir) {
  if ($SkipWarmup -or -not $wt -or -not $wt.warmup) { return }
  $i = 0
  foreach ($w in @($wt.warmup)) {
    $i++
    $where = $dir
    if ($w.dir) { $where = Join-Path $dir $w.dir }
    $stamp = Join-Path $state "slot-$n.warmup-$i"
    $hash = ""
    if ($w.lockfile) {
      $lf = Join-Path $dir $w.lockfile
      if (Test-Path $lf) {
        $hash = (Get-FileHash $lf -Algorithm SHA256).Hash
        $have = ""
        if (Test-Path $stamp) { $have = (Get-Content $stamp -Raw).Trim() }
        if ($have -eq $hash) { continue }
      }
    }
    Write-Host "warm-up $i in $where`: $($w.command)" -ForegroundColor Cyan
    Push-Location $where
    try { Invoke-Expression $w.command; $code = $LASTEXITCODE } finally { Pop-Location }
    if ($code -ne 0) { throw "warm-up '$($w.command)' failed" }
    if ($hash) { Write-Lf $stamp $hash }
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

if ($Status -and $Porcelain) {
  # <n> TAB busy TAB <branch> TAB <since>, or <n> TAB free; a busy slot above the count gets a fifth field, retiring
  $top = Get-LastSlot
  for ($i = 1; $i -le $top; $i++) {
    $m = Read-Marker $i
    if ($m) {
      if ($i -gt $count) { Write-Output ("{0}`tbusy`t{1}`t{2}`tretiring" -f $i, $m.branch, $m.since) }
      else { Write-Output ("{0}`tbusy`t{1}`t{2}" -f $i, $m.branch, $m.since) }
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
    $busy = if ($m) { "busy: $($m.branch) since $($m.since)" } else { "free" }
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

if ($Take) {
  New-Item -ItemType Directory -Force $state | Out-Null
  Invoke-Reap
  $n = $Slot
  if ($n -eq 0) {
    for ($i = 1; $i -le $count; $i++) { if (-not (Read-Marker $i)) { $n = $i; break } }
    if ($n -eq 0) { throw "all $count slots are busy; see slot.ps1 -Status" }
  }
  if ($n -lt 1 -or $n -gt $count) { throw "slot must be 1..$count" }
  if (Read-Marker $n) { throw "slot $n is busy" }

  git fetch origin $baseBranch
  if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }
  $dir = Get-SlotDir $n
  if (-not (Test-Path $dir)) {
    git worktree add --detach $dir $Base
    if ($LASTEXITCODE -ne 0) { throw "git worktree add failed" }
  } elseif (@(git -C $dir status --porcelain).Count -gt 0) {
    throw "slot $n has uncommitted files; deal with them first: $dir"
  }

  git -C $dir show-ref --verify --quiet "refs/heads/$Take"
  if ($LASTEXITCODE -eq 0) { git -C $dir switch $Take } else { git -C $dir switch -c $Take --no-track $Base }
  if ($LASTEXITCODE -ne 0) { throw "git switch failed" }

  Invoke-Warmup $n $dir

  $marker = @{ slot = $n; branch = $Take; since = (Get-Date).ToString("s") } | ConvertTo-Json
  Write-Lf (Get-Marker $n) $marker
  Show-Hints $n $dir $Take
  exit 0
}

if ($Release -gt 0) {
  $n = $Release
  $m = Read-Marker $n
  if (-not $m) { throw "slot $n is not in use" }
  $dir = Get-SlotDir $n
  if (@(git -C $dir status --porcelain).Count -gt 0) { throw "slot $n has uncommitted files: $dir" }
  git fetch origin $baseBranch
  if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }
  $merged = gh pr list --state merged --head $m.branch --json number -q '.[0].number'
  if (-not $merged) {
    throw "no merged PR for $($m.branch). Merge it first, or free the slot with -Abandon $n."
  }
  git -C $dir switch --detach "origin/$baseBranch"
  if ($LASTEXITCODE -ne 0) { throw "git switch failed" }
  git branch -D $m.branch
  Remove-Item (Get-Marker $n)
  Write-Host "Slot $n is free (was $($m.branch), PR #$merged)." -ForegroundColor Green
  exit 0
}

if ($Abandon -gt 0) {
  $n = $Abandon
  $m = Read-Marker $n
  if (-not $m) { throw "slot $n is not in use" }
  $dir = Get-SlotDir $n
  if (@(git -C $dir status --porcelain).Count -gt 0) { throw "slot $n has uncommitted files: $dir (commit, stash or discard them first)" }
  git -C $dir switch --detach $Base
  if ($LASTEXITCODE -ne 0) { throw "git switch failed" }
  Remove-Item (Get-Marker $n)
  Write-Host "Slot $n is free (was $($m.branch); the local branch is kept, delete it yourself if unwanted)." -ForegroundColor Yellow
  exit 0
}

Write-Host $usageText
exit 1

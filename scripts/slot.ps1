# scripts/slot.ps1 - permanent worktrees, one per worker slot (nightmill).
#   slot.ps1 -Status
#   slot.ps1 -Take feat/foo              # first free slot
#   slot.ps1 -Take fix/1-x -Slot 2       # a given slot
#   slot.ps1 -Release 1                  # after the PR merged
#   slot.ps1 -Abandon 1                  # free a slot whose task was dropped (no merged PR)
# Run it from inside the project: any checkout or worktree of it. Configuration comes from
# .claude/nightmill.json in the main checkout, keys under "worktrees" (see schema/nightmill.schema.json);
# $env:WORKER_SLOTS overrides worktrees.slots. A slot is never removed: a new task only switches it
# to a new branch from the base branch, so build output stays warm. A slot is busy from -Take to
# -Release or -Abandon (a marker file in <root>/.slots, outside any repo). Slot N gets port base + N.
param(
  [string]$Take,
  [int]$Release = 0,
  [int]$Abandon = 0,
  [switch]$Status,
  [int]$Slot = 0,
  [string]$Base = "",
  [switch]$SkipWarmup
)
$ErrorActionPreference = "Stop"

# The main checkout, wherever this is run from (it may itself be a worktree).
$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { throw "run slot.ps1 from inside a git checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent

$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { throw "no $cfgPath (run /nightmill:init)" }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$wt = $cfg.worktrees

$baseBranch = "main"
if ($cfg.git -and $cfg.git.baseBranch) { $baseBranch = $cfg.git.baseBranch }
if (-not $Base) { $Base = "origin/$baseBranch" }

$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
if ($wt -and $wt.root) { $rootRel = $wt.root }
$root = [System.IO.Path]::GetFullPath((Join-Path $main $rootRel))
$state = Join-Path $root ".slots"

$count = 2
if ($wt -and $wt.slots) { $count = [int]$wt.slots }
if ($env:WORKER_SLOTS) {
  if ($env:WORKER_SLOTS -notmatch '^[1-9][0-9]?$') { throw "WORKER_SLOTS must be a number from 1 to 99" }
  $count = [int]$env:WORKER_SLOTS
}

function Get-SlotDir($n) { Join-Path $root "slot-$n" }
function Get-Marker($n) { Join-Path $state "slot-$n.json" }
function Read-Marker($n) {
  $p = Get-Marker $n
  if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json } else { $null }
}
function Write-Lf($path, $text) { [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false)) }

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

if ($Status) {
  Write-Host "slots = $count  root = $root"
  for ($i = 1; $i -le $count; $i++) {
    $dir = Get-SlotDir $i
    $m = Read-Marker $i
    $where = if (Test-Path $dir) { "ready" } else { "not created yet" }
    $busy = if ($m) { "busy: $($m.branch) since $($m.since)" } else { "free" }
    $dirty = ""
    if (Test-Path $dir) {
      $n = @(git -C $dir status --porcelain).Count
      if ($n -gt 0) { $dirty = "  ($n uncommitted files)" }
    }
    Write-Host ("slot {0}  {1,-15} {2}{3}" -f $i, $where, $busy, $dirty)
  }
  exit 0
}

if ($Take) {
  New-Item -ItemType Directory -Force $state | Out-Null
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

Write-Host "usage: slot.ps1 -Status | -Take <branch> [-Slot N] [-Base <ref>] [-SkipWarmup] | -Release N | -Abandon N"
exit 1

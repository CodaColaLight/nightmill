# scripts/slot.ps1 - permanent worktrees, one per worker slot (nightmill).
#   slot.ps1 -Status [-Porcelain]        # -Porcelain: one tab separated line per slot, for scripts
#   slot.ps1 -Take feat/foo              # first free slot
#   slot.ps1 -Take fix/1-x -Slot 2       # a given slot
#   slot.ps1 -Release 1                  # after the PR merged
#   slot.ps1 -Abandon 1                  # free a slot whose task was dropped (no merged PR)
#   slot.ps1 -Reap                       # free every busy slot whose PR has merged (-Take does this first)
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
param(
  [string]$Take,
  [int]$Release = 0,
  [int]$Abandon = 0,
  [switch]$Reap,
  [switch]$Status,
  [switch]$Porcelain,
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
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
  for ($n = 1; $n -le $count; $n++) {
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

if ($Status -and $Porcelain) {
  # <n> TAB busy TAB <branch> TAB <since>, or <n> TAB free
  for ($i = 1; $i -le $count; $i++) {
    $m = Read-Marker $i
    if ($m) { Write-Output ("{0}`tbusy`t{1}`t{2}" -f $i, $m.branch, $m.since) } else { Write-Output ("{0}`tfree" -f $i) }
  }
  exit 0
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

Write-Host "usage: slot.ps1 -Status | -Take <branch> [-Slot N] [-Base <ref>] [-SkipWarmup] | -Release N | -Abandon N | -Reap"
exit 1

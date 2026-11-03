# scripts/new-worktree.ps1 - an ad-hoc extra checkout, outside the slot system (nightmill).
#   new-worktree.ps1 fix/123-short-name
#   new-worktree.ps1 feat/foo -Base main -SkipWarmup
# Creates <worktrees.root>/<branch with / as -> as a new branch from the base branch (or the branch
# itself if it already exists) and runs the configured warm-up commands. Each worktree has its own
# build output, so builds and test runs never lock or rebuild another. For day-to-day tasks use
# slot.ps1 instead: a slot keeps its build output warm across tasks. Remove this one when done:
#   git worktree remove <dir>   (then git branch -d <branch>)
param(
  [Parameter(Mandatory = $true)][string]$Branch,
  [string]$Base = "",
  [switch]$SkipWarmup
)
$ErrorActionPreference = "Stop"

$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { throw "run new-worktree.ps1 from inside a git checkout of the project" }
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

$slug = ($Branch -replace '[\\/]', '-')
$dir = Join-Path $root $slug
if (Test-Path $dir) { throw "$dir already exists" }

git fetch origin $baseBranch
if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

git show-ref --verify --quiet "refs/heads/$Branch"
if ($LASTEXITCODE -eq 0) {
  git worktree add $dir $Branch
} else {
  git worktree add --no-track -b $Branch $dir $Base
}
if ($LASTEXITCODE -ne 0) { throw "git worktree add failed" }

if (-not $SkipWarmup -and $wt -and $wt.warmup) {
  foreach ($w in @($wt.warmup)) {
    $where = $dir
    if ($w.dir) { $where = Join-Path $dir $w.dir }
    Write-Host "warm-up in $where`: $($w.command)" -ForegroundColor Cyan
    Push-Location $where
    try { Invoke-Expression $w.command; $code = $LASTEXITCODE } finally { Pop-Location }
    if ($code -ne 0) { throw "warm-up '$($w.command)' failed" }
  }
}

# A port offset per worktree, from the name, so two servers can run at once.
$sum = 0
foreach ($c in $slug.ToCharArray()) { $sum += [int]$c }
$offset = $sum % 100

Write-Host ""
Write-Host "Worktree ready: $dir" -ForegroundColor Green
Write-Host "  cd '$dir'"
$ports = @()
if ($wt -and $wt.ports) { $ports = @($wt.ports.PSObject.Properties) }
foreach ($p in $ports) { Write-Host ("  port {0}: {1}" -f $p.Name, ([int]$p.Value + $offset)) }
if ($wt -and $wt.runHints) {
  Write-Host "Run it next to other checkouts:"
  foreach ($h in @($wt.runHints)) {
    $line = ([string]$h).Replace("{slot}", "$offset")
    foreach ($p in $ports) { $line = $line.Replace("{port.$($p.Name)}", "$([int]$p.Value + $offset)") }
    Write-Host "  $line"
  }
}

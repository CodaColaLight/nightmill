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

# Continue for this call: Windows PowerShell 5.1 turns git's error text into a terminating error under Stop
$ErrorActionPreference = "Continue"
$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
$gitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($gitCode -ne 0 -or -not $gitDir) {
  # --path-format came with git 2.31: an older git is named, not taken for a missing checkout (bug 322)
  $gv = [string](git --version 2>$null)
  if ($gv -match '([0-9]+)\.([0-9]+)' -and ([int]$Matches[1] -lt 2 -or ([int]$Matches[1] -eq 2 -and [int]$Matches[2] -lt 31))) {
    throw "new-worktree.ps1 needs git 2.31 or newer; this is $($gv.Trim() -replace '^git version ', '')"
  }
  throw "run new-worktree.ps1 from inside a git checkout of the project"
}
$main = Split-Path ([string]$gitDir).Trim() -Parent

$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { throw "no $cfgPath (run /nightmill:init)" }
. (Join-Path $PSScriptRoot "lib\exactkeys.ps1")
$cfg = Select-ExactKeys (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json)
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

# Invoke-Bash <command>: runs one warm-up command in bash, as new-worktree.sh does with bash -c, and leaves its exit code in
# $LASTEXITCODE (bug 133: one interpreter in both shells). bash is Git for Windows' bin\bash.exe beside git,
# else the first bash on the PATH that is not WSL's (Windows\System32, Sysnative or SysWOW64\bash.exe gets no
# NIGHTMILL_WARMUP and would run nothing); without one it throws "bash not found" (no other interpreter is tried).
# The command goes to bash in the environment, not as an argument (Windows PowerShell 5.1 loses the double quotes
# of an argument to a native program); IFS= and set -f keep $NIGHTMILL_WARMUP one unchanged word, and eval runs it as bash -c would. bash
# shares this console; the wait is a loop that a stop (Ctrl+C, a stopped runspace) ends, and then bash's process tree
# is killed, since a stop does not end a native program PowerShell waits for.
function Invoke-Bash([string]$command) {
  $bash = $null
  try { $exec = [string](git --exec-path 2>$null) } catch { $exec = "" }
  if ($exec) {
    $root = Split-Path (Split-Path (Split-Path ($exec.Trim() -replace '/', '\') -Parent) -Parent) -Parent
    $cand = Join-Path $root "bin\bash.exe"
    if (Test-Path -LiteralPath $cand -PathType Leaf) { $bash = $cand }
  }
  if (-not $bash) {
    $wsl = @()
    $win = [Environment]::GetFolderPath("Windows")
    if ($win) { $wsl = @("System32", "Sysnative", "SysWOW64") | ForEach-Object { Join-Path $win "$_\bash.exe" } }
    $bash = Get-Command bash -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source } |
      Where-Object { $wsl -notcontains $_ } | Select-Object -First 1
  }
  if (-not $bash) { throw "bash not found: a warm-up command runs in bash (Git for Windows has it)" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $bash
  $psi.Arguments = "-c `"NIGHTMILL_IFS=`$IFS; IFS=; set -f; eval 'set +f; IFS=`$NIGHTMILL_IFS; unset NIGHTMILL_IFS;' `$NIGHTMILL_WARMUP`""
  $psi.WorkingDirectory = (Get-Location).ProviderPath
  $psi.UseShellExecute = $false
  $psi.EnvironmentVariables["NIGHTMILL_WARMUP"] = $command
  $p = [System.Diagnostics.Process]::Start($psi)
  try {
    while (-not $p.WaitForExit(100)) { }
    $global:LASTEXITCODE = $p.ExitCode
  } finally {
    if (-not $p.HasExited) {
      if ($env:OS -eq "Windows_NT") { try { & taskkill.exe /T /F /PID $p.Id 2>$null | Out-Null } catch { } } else { try { $p.Kill() } catch { } }
    }
  }
}

if (-not $SkipWarmup -and $wt -and $wt.warmup) {
  foreach ($w in @($wt.warmup)) {
    $where = $dir
    if ($w.dir) { $where = Join-Path $dir $w.dir }
    Write-Host "warm-up in $where`: $($w.command)" -ForegroundColor Cyan
    Push-Location $where
    try { Invoke-Bash $w.command; $code = $LASTEXITCODE } finally { Pop-Location }
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

# tests/smoke-release.ps1 - scripts/release.ps1 against throwaway repositories with a bare origin: every
# refusal leaves the repository untouched, the dry run changes nothing, prepare makes one commit on a
# release branch, publish tags the release commit and not what came after. Needs git only (no gh:
# -NoPr and -NoRelease). Also checks that the lint notices versions that disagree (when bash is installed).
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-rel-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }

# G <dir> <args>: run git in a directory (not named Git: a function would shadow the git command), return its output, fail on a non-zero exit code.
function G([string]$dir, [string[]]$a) {
  $o = & git -C $dir @a
  if ($LASTEXITCODE -ne 0) { Fail "git $($a -join ' ') failed in $dir" }
  return $o
}
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

$script:n = 0
$script:O = ""
$script:W = ""

# The template: a bare origin and a working clone on main holding plugin.json, CHANGELOG.md, README.md and the
# script. Built once; every case gets a copy (building a repository per case is slow on Windows).
$tplO = Join-Path $tmp "template-origin.git"
$tplW = Join-Path $tmp "template-work"
$null = G $tmp @("init", "-q", "--bare", "-b", "main", $tplO)
$null = G $tmp @("init", "-q", "-b", "main", $tplW)
foreach ($kv in @(@("user.name", "t"), @("user.email", "t@example.invalid"), @("core.autocrlf", "false"))) { $null = G $tplW @("config", $kv[0], $kv[1]) }
New-Item -ItemType Directory -Path (Join-Path $tplW ".claude-plugin"), (Join-Path $tplW "scripts") | Out-Null
Write-Utf8 (Join-Path $tplW ".claude-plugin\plugin.json") "{`n  `"name`": `"demo`",`n  `"version`": `"0.1.1`",`n  `"description`": `"A demo`"`n}`n"
Write-Utf8 (Join-Path $tplW "CHANGELOG.md") "# Changelog`n`n## Unreleased`n`n- A new thing.`n- Another thing.`n`n## 0.1.1 (2026-11-03)`n`n- Older.`n"
Write-Utf8 (Join-Path $tplW "README.md") "# Demo`n`nVersion 0.1.1. Apache License 2.0, see ``LICENSE``.`n"
Copy-Item (Join-Path $here "scripts\release.ps1") (Join-Path $tplW "scripts\release.ps1")
$null = G $tplW @("add", "-A")
$null = G $tplW @("commit", "-q", "-m", "init")
$null = G $tplW @("remote", "add", "origin", $tplO)
$null = G $tplW @("push", "-q", "origin", "main")

# Setup: copy the template into a fresh origin and working clone
function Setup {
  $script:n++
  $script:O = Join-Path $tmp "origin$($script:n).git"
  $script:W = Join-Path $tmp "work$($script:n)"
  Copy-Item -Recurse $tplO $script:O
  Copy-Item -Recurse $tplW $script:W
  $null = G $script:W @("remote", "set-url", "origin", $script:O)
}

# CommitIn <message> <scriptblock>: run the block with the working clone as the current directory, commit, push main.
function CommitIn([string]$msg, [scriptblock]$block) {
  Push-Location $script:W
  try { & $block } finally { Pop-Location }
  $null = G $script:W @("add", "-A")
  $null = G $script:W @("commit", "-q", "-m", $msg)
  $null = G $script:W @("push", "-q", "origin", "main")
}

function Snap {
  $s = @(G $script:W @("status", "--porcelain"))
  $b = @(G $script:W @("branch", "--list"))
  $t = @(G $script:W @("tag", "--list"))
  $h = G $script:W @("rev-parse", "HEAD")
  return (($s + "--" + $b + "--" + $t + "--" + $h) -join "`n")
}

# Run-Release <arguments>: run release.ps1 from the working clone in a child powershell.
function Run-Release([string[]]$a) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $script:W 'scripts\release.ps1')`" " + ($a -join " ")
  $psi.WorkingDirectory = $script:W
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $out; Err = $err; Code = $p.ExitCode }
}

# Refuses <name> <reason fragment> <arguments>: exit 1, "refused: ...<fragment>..." on stderr, nothing changed.
function Refuses([string]$name, [string]$want, [string[]]$a) {
  $before = Snap
  $r = Run-Release $a
  $after = Snap
  if ($r.Code -ne 1) { Fail "$name : expected exit code 1, got $($r.Code): $($r.Err)" }
  if ($r.Err -notlike "*refused: *$want*") { Fail "$name : wrong reason (wanted '$want'): $($r.Err)" }
  if ($before -ne $after) { Fail "$name : the repository changed" }
}

# Note: PowerShell variable names are case-insensitive: never use $w, $o or $n as a loop variable here.
$today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")

try {
  Write-Host "== refusals leave the repository untouched"
  Setup; Refuses "invalid version" "X.Y.Z" @("-Version", "1.2")
  Setup; Write-Utf8 (Join-Path $script:W "junk.txt") "junk"; Refuses "dirty tree" "uncommitted" @("-Version", "0.2.0")
  Setup; $null = G $script:W @("switch", "-q", "-c", "other"); Refuses "not on main" "not on main" @("-Version", "0.2.0")
  Setup
  $other = Join-Path $tmp "other$($script:n)"
  $null = G $tmp @("clone", "-q", $script:O, $other)
  foreach ($kv in @(@("user.name", "t"), @("user.email", "t@example.invalid"))) { $null = G $other @("config", $kv[0], $kv[1]) }
  $null = G $other @("commit", "-q", "--allow-empty", "-m", "ahead")
  $null = G $other @("push", "-q", "origin", "main")
  Refuses "main behind origin" "origin/main" @("-Version", "0.2.0")
  Setup; Refuses "equal version" "not greater" @("-Version", "0.1.1")
  Setup; Refuses "lower version" "not greater" @("-Version", "0.1.0")
  Setup; Refuses "lower major" "not greater" @("-Version", "0.0.9")
  Setup
  CommitIn "empty" { $t = [IO.File]::ReadAllText((Join-Path $script:W "CHANGELOG.md")) -replace "(?m)^- .*\r?\n", ""; Write-Utf8 (Join-Path $script:W "CHANGELOG.md") $t }
  Refuses "empty Unreleased" "Unreleased" @("-Version", "0.2.0")
  Setup
  CommitIn "no heading" { $t = [IO.File]::ReadAllText((Join-Path $script:W "CHANGELOG.md")).Replace("## Unreleased", "## Next"); Write-Utf8 (Join-Path $script:W "CHANGELOG.md") $t }
  Refuses "missing Unreleased heading" "Unreleased" @("-Version", "0.2.0")
  Setup; $null = G $script:W @("tag", "v0.2.0"); Refuses "tag exists locally" "tag v0.2.0 already exists" @("-Version", "0.2.0")
  Setup; $null = G $script:W @("tag", "v0.2.0"); $null = G $script:W @("push", "-q", "origin", "v0.2.0"); $null = G $script:W @("tag", "-d", "v0.2.0")
  Refuses "tag exists on origin only" "tag v0.2.0 already exists" @("-Version", "0.2.0")
  Setup; $null = G $script:W @("branch", "release/v0.2.0"); Refuses "release branch exists" "release/v0.2.0 already exists" @("-Version", "0.2.0")
  Setup
  CommitIn "no version line" { $t = [IO.File]::ReadAllText((Join-Path $script:W "README.md")) -replace "(?m)^Version .*\r?\n", ""; Write-Utf8 (Join-Path $script:W "README.md") $t }
  Refuses "README without a Version line" "README.md" @("-Version", "0.2.0")

  Write-Host "== dry run prints the plan and changes nothing"
  Setup
  $before = Snap
  $r = Run-Release @("-Version", "0.2.0", "-DryRun")
  if ($r.Code -ne 0) { Fail "dry run exited with $($r.Code): $($r.Err)" }
  foreach ($needle in "release/v0.2.0", "0.1.1", "0.2.0", $today) { if ($r.Out -notlike "*$needle*") { Fail "dry run output lacks '$needle': $($r.Out)" } }
  if ($before -ne (Snap)) { Fail "dry run changed the repository" }

  Write-Host "== prepare: one commit on release/v0.2.0, three files, main untouched"
  Setup
  $r = Run-Release @("-Version", "0.2.0", "-NoPr")
  if ($r.Code -ne 0) { Fail "prepare exited with $($r.Code): $($r.Err)" }
  $W = $script:W
  if ((G $W @("branch", "--show-current")) -ne "main") { Fail "prepare did not switch back to main" }
  if (@(G $W @("status", "--porcelain")).Count -ne 0) { Fail "working tree not clean after prepare" }
  if ((G $W @("rev-list", "--count", "main..release/v0.2.0")) -ne "1") { Fail "expected exactly one commit on the release branch" }
  if ((G $W @("log", "-1", "--format=%s", "release/v0.2.0")) -ne "Release 0.2.0") { Fail "wrong commit subject" }
  $changed = (@(G $W @("diff", "--name-only", "main", "release/v0.2.0")) | Sort-Object) -join " "
  if ($changed -ne ".claude-plugin/plugin.json CHANGELOG.md README.md") { Fail "unexpected files changed: $changed" }
  $pj = (G $W @("show", "release/v0.2.0:.claude-plugin/plugin.json")) -join "`n"
  if ($pj -notlike '*"version": "0.2.0",*') { Fail "plugin.json lacks the new version" }
  $diff = @(G $W @("diff", "-U0", "main", "release/v0.2.0", "--", ".claude-plugin/plugin.json") | Where-Object { $_ -match '^[+-][^+-]' })
  if ($diff.Count -ne 2) { Fail "plugin.json changed by more than the version line" }
  $cl = (G $W @("show", "release/v0.2.0:CHANGELOG.md")) -join "`n"
  $expect = "## Unreleased`n`n## 0.2.0 ($today)`n`n- A new thing.`n- Another thing.`n`n## 0.1.1 (2026-11-03)`n`n- Older."
  if (-not $cl.Contains($expect)) { Fail "CHANGELOG not cut as expected: $cl" }
  $rd = (G $W @("show", "release/v0.2.0:README.md")) -join "`n"
  if (-not $rd.Contains('Version 0.2.0. Apache License 2.0, see `LICENSE`.')) { Fail "README line not updated: $rd" }

  Write-Host "== publish: tags the release commit, not what came after"
  Setup
  $r = Run-Release @("-Version", "0.2.0", "-NoPr")
  if ($r.Code -ne 0) { Fail "prepare exited with $($r.Code): $($r.Err)" }
  Refuses "publish before the merge" "origin/main" @("-Version", "0.2.0", "-Publish")
  $null = G $script:W @("merge", "-q", "--ff-only", "release/v0.2.0")
  $null = G $script:W @("push", "-q", "origin", "main")
  $releaseCommit = G $script:W @("rev-parse", "HEAD")
  CommitIn "later work" { Add-Content -Path (Join-Path $script:W "README.md") -Value "later" }
  $r = Run-Release @("-Version", "0.2.0", "-Publish", "-NoRelease")
  if ($r.Code -ne 0) { Fail "publish exited with $($r.Code): $($r.Err)" }
  if ((G $script:W @("cat-file", "-t", "v0.2.0")) -ne "tag") { Fail "v0.2.0 is not an annotated tag" }
  if ((G $script:W @("rev-parse", "v0.2.0^{commit}")) -ne $releaseCommit) { Fail "v0.2.0 does not point at the release commit" }
  if ((G $script:O @("rev-parse", "v0.2.0^{commit}")) -ne $releaseCommit) { Fail "v0.2.0 is not on origin at the release commit" }
  $r = Run-Release @("-Version", "0.2.0", "-Publish", "-NoRelease")
  if ($r.Code -ne 0) { Fail "publish twice exited with $($r.Code): $($r.Err)" }
  if ((G $script:O @("rev-parse", "v0.2.0^{commit}")) -ne $releaseCommit) { Fail "publish twice moved v0.2.0" }

  Write-Host "== publish: a failed tag push is finished by a rerun; a tag at another commit is refused (#130)"
  Setup
  $r = Run-Release @("-Version", "0.2.0", "-NoPr")
  if ($r.Code -ne 0) { Fail "prepare exited with $($r.Code): $($r.Err)" }
  $null = G $script:W @("merge", "-q", "--ff-only", "release/v0.2.0")
  $null = G $script:W @("push", "-q", "origin", "main")
  $releaseCommit = G $script:W @("rev-parse", "HEAD")
  $hook = Join-Path $script:O "hooks\pre-receive"
  Write-Utf8 $hook "#!/bin/sh`nwhile read old new ref; do case `"`$ref`" in refs/tags/*) exit 1;; esac; done`nexit 0`n"
  $r = Run-Release @("-Version", "0.2.0", "-Publish", "-NoRelease")
  if ($r.Code -eq 0) { Fail "publish succeeded although origin rejects tags" }
  Remove-Item $hook
  $r = Run-Release @("-Version", "0.2.0", "-Publish", "-NoRelease")
  if ($r.Code -ne 0) { Fail "the rerun after a failed push exited with $($r.Code): $($r.Err)" }
  if ((G $script:O @("rev-parse", "v0.2.0^{commit}")) -ne $releaseCommit) { Fail "the rerun did not push v0.2.0 at the release commit" }
  $null = G $script:W @("tag", "-d", "v0.2.0")
  $null = G $script:W @("tag", "-a", "v0.2.0", "-m", "x", "$releaseCommit^")
  Refuses "tag at another commit" "tag v0.2.0 already exists at another commit" @("-Version", "0.2.0", "-Publish", "-NoRelease")

  Write-Host "== the lint notices versions that disagree"
  $bash = $null
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    # Git for Windows keeps its own bash in <install>\bin; git.exe sits in <install>\cmd, or deeper (mingw64\bin).
    $dir = Split-Path $gitCmd.Source -Parent
    for ($up = 0; $up -lt 3 -and -not $bash; $up++) {
      $cand = Join-Path (Join-Path $dir "bin") "bash.exe"
      if (Test-Path $cand) { $bash = $cand }
      $dir = Split-Path $dir -Parent
    }
  }
  if (-not $bash) { $found = Get-Command bash -ErrorAction SilentlyContinue; if ($found) { $bash = $found.Source } }
  if (-not $bash) {
    Write-Host "(bash not installed, lint check skipped)"
  }
  else {
    $copy = Join-Path $tmp "repocopy"
    New-Item -ItemType Directory -Path $copy | Out-Null
    & robocopy $here $copy /E /XD ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
    # robocopy exit codes below 8 mean success
    if ($LASTEXITCODE -ge 8) { Fail "could not copy the repository (robocopy $LASTEXITCODE)" }
    $pjPath = Join-Path $copy ".claude-plugin\plugin.json"
    Push-Location $copy
    $ErrorActionPreference = "Continue"
    try {
      # On a failure the lint's FAIL: lines (else its whole output) follow, so a CI log names the rule (#217).
      $out = (& $bash tests/lint.sh 2>&1 | Out-String)
      if ($LASTEXITCODE -ne 0) {
        $lintFails = @(($out -split "`r?`n") | Where-Object { $_ -like "*FAIL:*" })
        if ($lintFails.Count -eq 0) { $lintFails = @($out) }
        Fail ("the lint fails on an unchanged copy of the repository`n" + ($lintFails -join "`n"))
      }
      $t = [IO.File]::ReadAllText($pjPath) -replace '(?m)^(\s*"version":\s*")[0-9.]+"', '${1}9.9.9"'
      Write-Utf8 $pjPath $t
      $out = (& $bash tests/lint.sh 2>&1 | Out-String)
      if ($LASTEXITCODE -eq 0) { Fail "the lint accepted a plugin.json version that disagrees" }
      if ($out -notlike "*FAIL: versions disagree*9.9.9*") { Fail "the lint did not report the disagreement: $out" }
    }
    finally { Pop-Location }
  }

  Write-Host "RELEASE OK"
}
finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

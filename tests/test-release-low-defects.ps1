# tests/test-release-low-defects.ps1 - the low-severity defects in scripts/release.ps1 (#321, split from #140):
# the exit codes of the header, a rollback after a failed push or gh pr create, versions with leading zeros,
# temporary files removed when a step fails, -DryRun (no fetch, gh auth checked), GH_PROMPT_DISABLED set for
# gh, and an exported CDPATH. gh is a fake (gh.cmd) first on PATH: it logs, and fails when told to.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-lowdef-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { throw "FAIL: $msg" }
function G([string]$dir, [string[]]$a) {
  $o = & git -C $dir @a
  if ($LASTEXITCODE -ne 0) { Fail "git $($a -join ' ') failed in $dir" }
  return $o
}
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

$bin = Join-Path $tmp "bin"
New-Item -ItemType Directory -Path $bin | Out-Null
Write-Utf8 (Join-Path $bin "gh.cmd") ("@echo off`r`necho %* >> `"%GH_LOG%`"`r`n" +
  "if defined GH_PROMPT_DISABLED (echo prompt=%GH_PROMPT_DISABLED% >> `"%GH_ENV%`") else (echo prompt= >> `"%GH_ENV%`")`r`n" +
  "if `"%1 %2`"==`"auth status`" (if exist `"%GH_AUTH_FAIL%`" (exit /b 1) else (exit /b 0))`r`n" +
  "if `"%1 %2`"==`"pr create`" (if exist `"%GH_FAIL%`" (exit /b 1) else (exit /b 0))`r`n" +
  "exit /b 0`r`n")
$GhLog = Join-Path $tmp "gh.log"; $GhEnv = Join-Path $tmp "gh.env"
$GhFail = Join-Path $tmp "gh.fail"; $GhAuthFail = Join-Path $tmp "gh.authfail"
$env:GH_LOG = $GhLog; $env:GH_ENV = $GhEnv; $env:GH_FAIL = $GhFail; $env:GH_AUTH_FAIL = $GhAuthFail
Remove-Item Env:GH_PROMPT_DISABLED, Env:CDPATH -ErrorAction SilentlyContinue
$env:PATH = "$bin;$env:PATH"

$script:n = 0; $script:O = ""; $script:W = ""
# main holds 0.2.0 with an entry under Unreleased: 0.3.0 can be prepared
function Setup {
  $script:n++
  $script:O = Join-Path $tmp "origin$($script:n).git"
  $script:W = Join-Path $tmp "work$($script:n)"
  foreach ($f in @($GhLog, $GhEnv, $GhFail, $GhAuthFail)) { Remove-Item $f -ErrorAction SilentlyContinue }
  $null = G $tmp @("init", "-q", "--bare", "-b", "main", $script:O)
  $null = G $tmp @("init", "-q", "-b", "main", $script:W)
  foreach ($kv in @(@("user.name", "t"), @("user.email", "t@example.invalid"), @("core.autocrlf", "false"))) { $null = G $script:W @("config", $kv[0], $kv[1]) }
  New-Item -ItemType Directory -Path (Join-Path $script:W ".claude-plugin"), (Join-Path $script:W "scripts") | Out-Null
  Write-Utf8 (Join-Path $script:W ".claude-plugin\plugin.json") "{`n  `"name`": `"demo`",`n  `"version`": `"0.2.0`",`n  `"description`": `"A demo`"`n}`n"
  Write-Utf8 (Join-Path $script:W "CHANGELOG.md") "# Changelog`n`n## Unreleased`n`n- A new thing.`n`n## 0.2.0 (2026-11-03)`n`n- A thing.`n"
  Write-Utf8 (Join-Path $script:W "README.md") "# Demo`n`nVersion 0.2.0. Apache License 2.0.`n"
  Copy-Item (Join-Path $here "scripts\release.ps1") (Join-Path $script:W "scripts\release.ps1")
  $null = G $script:W @("add", "-A")
  $null = G $script:W @("commit", "-q", "-m", "Release 0.2.0")
  $null = G $script:W @("remote", "add", "origin", $script:O)
  $null = G $script:W @("push", "-q", "origin", "HEAD:refs/heads/main")
}

# Rel: runs release.ps1 in the work repo; $extraEnv sets variables in the child only
function Rel([string[]]$extra, [string]$ver = "0.3.0", [hashtable]$extraEnv = @{}) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $script:W 'scripts\release.ps1')`" -Version $ver " + ($extra -join " ")
  $psi.WorkingDirectory = $script:W
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = $extraEnv[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $out; Err = $errTask.Result; Code = $p.ExitCode }
}
function Reject-Branches {
  $hook = Join-Path $script:O "hooks\pre-receive"
  [IO.File]::WriteAllText($hook, "#!/bin/sh`nwhile read old new ref; do case `"`$ref`" in refs/heads/release/*) echo `"branch rejected`" >&2; exit 1;; esac; done`nexit 0`n", $utf8)
}
# a state a rerun can start from: on main, no release branch here or on origin
function Assert-RolledBack([string]$what) {
  $b = "$(& git -C $script:W branch --show-current)"
  if ($b -ne "main") { Fail "${what}: not back on main (on '$b')" }
  if ("$(& git -C $script:W branch --list 'release/v0.3.0')".Trim() -ne "") { Fail "${what}: the local branch release/v0.3.0 is still there" }
  if ("$(& git -C $script:O branch --list 'release/v0.3.0')".Trim() -ne "") { Fail "${what}: the branch release/v0.3.0 is still on origin" }
  if ("$(& git -C $script:W status --porcelain)".Trim() -ne "") { Fail "${what}: the working tree is not clean" }
}

$bad = 0
function Case([string]$name, [scriptblock]$body) {
  Write-Host "== $name"
  try { & $body } catch { Write-Host ($_.Exception.Message); $script:bad = 1 }
}

try {
  Case "an unexpected failure exits 2, as the header says" {
    Setup
    [IO.File]::WriteAllText((Join-Path $script:W ".git\hooks\pre-commit"), "#!/bin/sh`necho `"hook says no`" >&2`nexit 1`n", $utf8)
    $r = Rel @()
    if ($r.Code -ne 2) { Fail "a failed commit exited $($r.Code), expected 2: $($r.Err)" }
  }

  Case "a failed push after the release commit is rolled back; a rerun works" {
    Setup; Reject-Branches
    $r = Rel @()
    if ($r.Code -eq 0) { Fail "the push was expected to fail while origin rejects branches" }
    Assert-RolledBack "failed push"
    Remove-Item (Join-Path $script:O "hooks\pre-receive")
    $r = Rel @()
    if ($r.Code -ne 0) { Fail "rerun after a failed push exited $($r.Code): $($r.Err)" }
  }

  Case "a failed gh pr create after the push is rolled back; a rerun works" {
    Setup; Write-Utf8 $GhFail "x"
    $r = Rel @()
    if ($r.Code -eq 0) { Fail "the run was expected to fail while gh pr create fails" }
    Assert-RolledBack "failed gh pr create"
    Remove-Item $GhFail
    $r = Rel @()
    if ($r.Code -ne 0) { Fail "rerun after a failed gh pr create exited $($r.Code): $($r.Err)" }
  }

  Case "versions with leading zeros are refused" {
    Setup
    foreach ($v in @("0.03.0", "1.0.01", "00.3.0")) {
      $r = Rel @("-DryRun") $v
      if ($r.Code -ne 1) { Fail "version $v exited $($r.Code), expected 1: $($r.Out)" }
      if ($r.Err -notlike "*refused: *") { Fail "version $v : no refused line: $($r.Err)" }
    }
  }

  Case "temporary files are removed when a step fails" {
    Setup; Reject-Branches
    $td = Join-Path $tmp "tmpdir$($script:n)"
    New-Item -ItemType Directory -Path $td | Out-Null
    $r = Rel @() "0.3.0" @{ TMP = $td; TEMP = $td }
    if ($r.Code -eq 0) { Fail "the push was expected to fail while origin rejects branches" }
    $left = @(Get-ChildItem $td -Force)
    if ($left.Count -ne 0) { Fail "$($left.Count) temporary file(s) left behind: $($left.Name -join ', ')" }
  }

  Case "-DryRun does not fetch and checks gh auth" {
    Setup
    $r = Rel @("-DryRun") "0.3.0" @{ GIT_TRACE = "1" }
    if ($r.Code -ne 0) { Fail "dry run exited $($r.Code): $($r.Err)" }
    if (($r.Out + $r.Err) -match "git fetch") { Fail "-DryRun ran git fetch" }
    if (-not ((Test-Path $GhLog) -and ((Get-Content $GhLog -Raw) -match "(?m)^auth status"))) { Fail "-DryRun did not run gh auth status" }
    Write-Utf8 $GhAuthFail "x"
    $r = Rel @("-DryRun")
    if ($r.Code -eq 0) { Fail "-DryRun succeeded although gh is not authenticated: $($r.Out)" }
  }

  Case "gh is called with GH_PROMPT_DISABLED set" {
    Setup
    $r = Rel @()
    if ($r.Code -ne 0) { Fail "prepare exited $($r.Code): $($r.Err)" }
    if (-not ((Test-Path $GhLog) -and ((Get-Content $GhLog -Raw) -match "(?m)^pr create"))) { Fail "gh pr create was not called" }
    foreach ($l in @(Get-Content $GhEnv)) {
      if ("$l".Trim() -eq "prompt=") { Fail "a gh call ran without GH_PROMPT_DISABLED" }
    }
  }

  Case "an exported CDPATH does not break the script" {
    Setup
    New-Item -ItemType Directory -Path (Join-Path $tmp "decoy\scripts") -Force | Out-Null
    $r = Rel @("-DryRun", "-NoPr") "0.3.0" @{ CDPATH = (Join-Path $tmp "decoy") }
    if ($r.Code -ne 0) { Fail "dry run with CDPATH exited $($r.Code): $($r.Err)" }
    if ($r.Out -notlike "*release 0.2.0 -> 0.3.0*") { Fail "dry run with CDPATH did not plan the release: $($r.Out)" }
  }

  if ($bad -ne 0) { exit 1 }
  Write-Host "RELEASE LOW DEFECTS OK"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

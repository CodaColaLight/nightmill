# tests/test-release-resume.ps1 - scripts/release.ps1 -Publish can be resumed after a partial failure (#130):
# a failed tag push, a failed GitHub Release creation, a tag already on origin; it refuses only when the tag
# points at a different commit. gh is a fake (gh.cmd) first on PATH: it logs, and fails when told to.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-resume-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function G([string]$dir, [string[]]$a) {
  $o = & git -C $dir @a
  if ($LASTEXITCODE -ne 0) { Fail "git $($a -join ' ') failed in $dir" }
  return $o
}
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

$bin = Join-Path $tmp "bin"
New-Item -ItemType Directory -Path $bin | Out-Null
Write-Utf8 (Join-Path $bin "gh.cmd") ("@echo off`r`necho %* >> `"%GH_LOG%`"`r`n" +
  "if `"%1 %2`"==`"release view`" (if exist `"%GH_STATE%`" (exit /b 0) else (exit /b 1))`r`n" +
  "if `"%1 %2`"==`"release create`" (if exist `"%GH_FAIL%`" (exit /b 1) else (type nul > `"%GH_STATE%`" & exit /b 0))`r`n" +
  "exit /b 0`r`n")
$GhLog = Join-Path $tmp "gh.log"; $GhState = Join-Path $tmp "gh.state"; $GhFail = Join-Path $tmp "gh.fail"
$env:GH_LOG = $GhLog; $env:GH_STATE = $GhState; $env:GH_FAIL = $GhFail
$env:PATH = "$bin;$env:PATH"

$script:n = 0; $script:O = ""; $script:W = ""; $script:cand = ""
function Setup {
  $script:n++
  $script:O = Join-Path $tmp "origin$($script:n).git"
  $script:W = Join-Path $tmp "work$($script:n)"
  foreach ($f in @($GhLog, $GhState, $GhFail)) { Remove-Item $f -ErrorAction SilentlyContinue }
  $null = G $tmp @("init", "-q", "--bare", "-b", "main", $script:O)
  $null = G $tmp @("init", "-q", "-b", "main", $script:W)
  foreach ($kv in @(@("user.name", "t"), @("user.email", "t@example.invalid"), @("core.autocrlf", "false"))) { $null = G $script:W @("config", $kv[0], $kv[1]) }
  New-Item -ItemType Directory -Path (Join-Path $script:W ".claude-plugin"), (Join-Path $script:W "scripts") | Out-Null
  Write-Utf8 (Join-Path $script:W ".claude-plugin\plugin.json") "{`n  `"name`": `"demo`",`n  `"version`": `"0.2.0`",`n  `"description`": `"A demo`"`n}`n"
  Write-Utf8 (Join-Path $script:W "CHANGELOG.md") "# Changelog`n`n## Unreleased`n`n## 0.2.0 (2026-11-03)`n`n- A thing.`n"
  Write-Utf8 (Join-Path $script:W "README.md") "# Demo`n`nVersion 0.2.0. Apache License 2.0.`n"
  Copy-Item (Join-Path $here "scripts\release.ps1") (Join-Path $script:W "scripts\release.ps1")
  $null = G $script:W @("add", "-A")
  $null = G $script:W @("commit", "-q", "-m", "Release 0.2.0")
  $null = G $script:W @("remote", "add", "origin", $script:O)
  $null = G $script:W @("push", "-q", "origin", "main")
  $script:cand = "$(G $script:W @('rev-parse', 'HEAD'))"
}

function Publish([string[]]$extra) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $script:W 'scripts\release.ps1')`" -Version 0.2.0 -Publish " + ($extra -join " ")
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
function Reject-Tags {
  $hook = Join-Path $script:O "hooks\pre-receive"
  [IO.File]::WriteAllText($hook, "#!/bin/sh`nwhile read old new ref; do case `"`$ref`" in refs/tags/*) echo `"tags rejected`" >&2; exit 1;; esac; done`nexit 0`n", $utf8)
}
function Origin-Tag { $t = & git -C $script:O rev-parse "v0.2.0^{commit}" 2>$null; if ($LASTEXITCODE -eq 0) { return "$t" } else { return "" } }

try {
  Write-Host "== a failed tag push can be rerun: the local tag is pushed"
  Setup; Reject-Tags
  $r = Publish @("-NoRelease")
  if ($r.Code -eq 0) { Fail "the push was expected to fail while origin rejects tags" }
  Remove-Item (Join-Path $script:O "hooks\pre-receive")
  $r = Publish @("-NoRelease")
  if ($r.Code -ne 0) { Fail "rerun after a failed push exited $($r.Code): $($r.Err)" }
  if ((Origin-Tag) -ne $script:cand) { Fail "v0.2.0 is not on origin at the release commit after the rerun" }

  Write-Host "== a failed Release creation can be rerun: the Release is created"
  Setup; Write-Utf8 $GhFail "x"
  $r = Publish @()
  if ($r.Code -eq 0) { Fail "the run was expected to fail while gh release create fails" }
  if ((Origin-Tag) -ne $script:cand) { Fail "the tag did not reach origin before gh failed" }
  Remove-Item $GhFail
  $r = Publish @()
  if ($r.Code -ne 0) { Fail "rerun after a failed Release exited $($r.Code): $($r.Err)" }
  if (-not (Test-Path $GhState)) { Fail "the rerun did not create the GitHub Release" }

  Write-Host "== a tag on origin at the candidate commit, no local tag, no Release: the Release is created"
  Setup
  $null = G $script:W @("tag", "-a", "v0.2.0", "-m", "x", $script:cand)
  $null = G $script:W @("push", "-q", "origin", "v0.2.0")
  $null = G $script:W @("tag", "-d", "v0.2.0")
  $r = Publish @()
  if ($r.Code -ne 0) { Fail "publish with the tag already on origin exited $($r.Code): $($r.Err)" }
  if (-not (Test-Path $GhState)) { Fail "the GitHub Release was not created" }

  Write-Host "== a complete release is not made twice"
  Setup; Write-Utf8 $GhState "x"
  $null = G $script:W @("tag", "-a", "v0.2.0", "-m", "x", $script:cand)
  $null = G $script:W @("push", "-q", "origin", "v0.2.0")
  $r = Publish @()
  if ($r.Code -ne 0) { Fail "publish of a complete release exited $($r.Code): $($r.Err)" }
  if ((Test-Path $GhLog) -and ((Get-Content $GhLog -Raw) -match "(?m)^release create")) { Fail "gh release create ran although the Release exists" }

  Write-Host "== a tag at a different commit is refused"
  Setup
  $null = G $script:W @("commit", "-q", "--allow-empty", "-m", "other")
  $null = G $script:W @("tag", "-a", "v0.2.0", "-m", "x", "HEAD")
  $r = Publish @("-NoRelease")
  if ($r.Code -ne 1) { Fail "expected exit code 1, got $($r.Code): $($r.Err)" }
  if ($r.Err -notlike "*refused: *v0.2.0*") { Fail "wrong refusal: $($r.Err)" }
  if (@(& git -C $script:O tag --list).Count -ne 0) { Fail "the wrong tag was pushed" }

  Write-Host "== a tag on origin at a different commit, no local tag: refused, no Release"
  Setup
  $null = G $script:W @("commit", "-q", "--allow-empty", "-m", "other")
  $null = G $script:W @("tag", "-a", "v0.2.0", "-m", "x", "HEAD")
  $null = G $script:W @("push", "-q", "origin", "v0.2.0")
  $null = G $script:W @("tag", "-d", "v0.2.0")
  $null = G $script:W @("reset", "-q", "--hard", $script:cand)
  $r = Publish @()
  if ($r.Code -ne 1) { Fail "expected exit code 1, got $($r.Code): $($r.Err)" }
  if ($r.Err -notlike "*refused: *v0.2.0*") { Fail "wrong refusal: $($r.Err)" }
  if (Test-Path $GhState) { Fail "a GitHub Release was created for a tag at a different commit" }
  if ((Test-Path $GhLog) -and ((Get-Content $GhLog -Raw) -match "(?m)^release create")) { Fail "gh release create ran for a tag at a different commit" }
  if ((Origin-Tag) -eq $script:cand) { Fail "the origin tag was moved to the candidate" }

  Write-Host "RELEASE RESUME OK"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

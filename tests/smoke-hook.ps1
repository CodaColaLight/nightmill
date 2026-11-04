# tests/smoke-hook.ps1 - scripts/session-start.ps1 (the SessionStart hook for PowerShell): one line when the
# project has no .claude/nightmill.json, nothing when it has one, nothing when NIGHTMILL_HINT=off, and
# exit code 0 always. Also: the command hooks/hooks.json wires, run by PowerShell on a PATH without bash
# (a machine that runs hooks through PowerShell only), must exit 0 and print nothing. Each case runs in a
# child powershell process with its own environment and PATH.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$S = Join-Path $here "scripts\session-start.ps1"
$psExe = (Get-Command powershell).Source
$psDir = Split-Path $psExe -Parent
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-hook-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }

$bare = Join-Path $tmp "bare"; New-Item -ItemType Directory -Path $bare | Out-Null
$cfg = Join-Path $tmp "cfg"; New-Item -ItemType Directory -Path (Join-Path $cfg ".claude") -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $cfg ".claude\nightmill.json"), "{}")

# Invoke-Hook <cwd> <vars to set> <vars to clear> <PATH>; returns Out (string) and Code (int).
# The default PATH holds only the PowerShell directory, so no bash is found.
function Invoke-Hook([string]$cwd, [hashtable]$set, [string[]]$clear, [string]$path = $psDir) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$S`""
  $psi.WorkingDirectory = $cwd
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $clear) { [void]$psi.EnvironmentVariables.Remove($k) }
  foreach ($k in $set.Keys) { $psi.EnvironmentVariables[$k] = [string]$set[$k] }
  $psi.EnvironmentVariables["PATH"] = $path
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $out; Code = $p.ExitCode }
}

function Expect-Hint($name, $r) {
  if ($r.Code -ne 0) { Fail "$name : exit code $($r.Code)" }
  $lines = @($r.Out -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
  if ($lines.Count -ne 1) { Fail "$name : expected one line, got $($lines.Count): $($r.Out)" }
  if ($lines[0] -notlike "*/nightmill:init*") { Fail "$name : the line does not name /nightmill:init: $($r.Out)" }
}
function Expect-Silent($name, $r) {
  if ($r.Code -ne 0) { Fail "$name : exit code $($r.Code)" }
  if ($r.Out.Trim() -ne "") { Fail "$name : expected no output, got: $($r.Out)" }
}

try {
  Write-Host "== no config: one line"
  Expect-Hint "no config" (Invoke-Hook $tmp @{ CLAUDE_PROJECT_DIR = $bare } @())

  Write-Host "== config present: silent"
  Expect-Silent "config present" (Invoke-Hook $tmp @{ CLAUDE_PROJECT_DIR = $cfg } @())

  Write-Host "== NIGHTMILL_HINT=off (any case): silent"
  foreach ($v in "off", "Off", "OFF") {
    Expect-Silent "NIGHTMILL_HINT=$v" (Invoke-Hook $tmp @{ CLAUDE_PROJECT_DIR = $bare; NIGHTMILL_HINT = $v } @())
  }
  Expect-Hint "NIGHTMILL_HINT=on" (Invoke-Hook $tmp @{ CLAUDE_PROJECT_DIR = $bare; NIGHTMILL_HINT = "on" } @())

  Write-Host "== CLAUDE_PROJECT_DIR unset: the current directory is used"
  Expect-Hint "cwd without config" (Invoke-Hook $bare @{} @("CLAUDE_PROJECT_DIR"))
  Expect-Silent "cwd with config" (Invoke-Hook $cfg @{} @("CLAUDE_PROJECT_DIR"))

  Write-Host "== a directory that does not exist: exit 0, no output"
  Expect-Silent "missing directory" (Invoke-Hook $tmp @{ CLAUDE_PROJECT_DIR = (Join-Path $tmp "does-not-exist") } @())

  Write-Host "== hooks.json command in PowerShell without bash: exit 0, no output"
  $hooks = Get-Content -Raw -Encoding UTF8 (Join-Path $here "hooks\hooks.json") | ConvertFrom-Json
  $cmd = $hooks.hooks.SessionStart[0].hooks[0].command.Replace('${CLAUDE_PLUGIN_ROOT}', ($here.Replace([string][char]92, '/')))
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -Command `"$($cmd -replace '"', '\"')`""
  $psi.WorkingDirectory = $tmp
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables["PATH"] = $psDir
  $psi.EnvironmentVariables["CLAUDE_PROJECT_DIR"] = $bare
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { Fail "hooks.json command in PowerShell: exit code $($p.ExitCode)" }
  if ($out.Trim() -ne "") { Fail "hooks.json command in PowerShell: expected no output, got: $out" }

  Write-Host "HOOK OK"
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

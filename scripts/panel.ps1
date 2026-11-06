# scripts/panel.ps1 - the slot lines the slots pane beside the Claude chat draws (nightmill).
#
#   panel.ps1               print the records once and exit
#
# Read-only. It runs slot.ps1 -Status -Porcelain once in a child PowerShell (no gh, no network) and prints, one per
# line, tab separated, LF: time (HH:MM:SS of the read), every (worktrees.panelRefreshSeconds, default 15), then
# noslots (no worktrees section), or one slot record per slot (<n>, free or busy, agent, branch, skill, step and
# report cells as /status shows them), or one unknown record with the reason the slots could not be read; then the
# notes. The pane of hooks/panel.tsx (/nightmill-slots) calls it on every read on Windows; panel.sh prints the same
# bytes. The rules are in docs/specs/iteration-32-panel.md. Run it from inside the project: any checkout or worktree.
# Exit code 0 when the records were printed (also with an unknown record), 2 for a usage error, no checkout, no or
# invalid config.
# $env:NIGHTMILL_NOW (seconds since 1970, local time taken as UTC) fixes the clock here and in slot.ps1.
param(
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"

function Die([string]$msg) { [Console]::Error.WriteLine("panel: $msg"); exit 2 }
if ($Rest) { [Console]::Error.WriteLine("usage: panel.ps1"); exit 2 }

$utf8 = New-Object System.Text.UTF8Encoding $false
$gitDir = $null
try { $gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { Die "run panel.ps1 from inside a checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Die "no $cfgPath (run /nightmill:init)" }
$cfg = $null
try { $cfg = [IO.File]::ReadAllText($cfgPath, $utf8) | ConvertFrom-Json } catch { Die "$cfgPath is not valid JSON" }
if ($null -eq $cfg) { Die "$cfgPath is not valid JSON" }

# the interval: worktrees.panelRefreshSeconds, a whole number from 5 to 3600, else 15 (with a note unless absent or null)
$hasWt = [bool]($cfg -is [System.Management.Automation.PSCustomObject] -and $cfg.PSObject.Properties["worktrees"])
$every = 15
$noteEvery = ""
if ($hasWt -and $cfg.worktrees -is [System.Management.Automation.PSCustomObject]) {
  $p = $cfg.worktrees.PSObject.Properties["panelRefreshSeconds"]
  if ($p -and $null -ne $p.Value) {
    $v = $p.Value
    if (($v -is [int] -or $v -is [long]) -and $v -ge 5 -and $v -le 3600) { $every = [int]$v }
    else { $noteEvery = "worktrees.panelRefreshSeconds must be a whole number from 5 to 3600; using 15" }
  }
}

# StampOf YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC, by the arithmetic of stamp in
# lib/status.awk (not a date parser)
function StampOf([string]$s) {
  $yr = [long]$s.Substring(0, 4); $mon = [long]$s.Substring(5, 2); $day = [long]$s.Substring(8, 2)
  if ($mon -le 2) { $yr-- }
  $yy = $yr
  if ($yr -lt 0) { $yy = $yr - 399 }
  $era = [long][math]::Truncate($yy / 400)
  $yoe = $yr - $era * 400
  $shift = 9
  if ($mon -gt 2) { $shift = -3 }
  $doy = [long][math]::Truncate((153 * ($mon + $shift) + 2) / 5) + $day - 1
  $doe = $yoe * 365 + [long][math]::Truncate($yoe / 4) - [long][math]::Truncate($yoe / 100) + $doy
  return [long](($era * 146097 + $doe - 719468) * 86400 + [long]$s.Substring(11, 2) * 3600 + [long]$s.Substring(14, 2) * 60 + [long]$s.Substring(17, 2))
}
function Span([long]$sec) {
  if ($sec -lt 0) { $sec = 0 }
  if ($sec -lt 3600) { return "$([math]::Floor($sec / 60))m" }
  if ($sec -lt 86400) { return "$([math]::Floor($sec / 3600))h" }
  return "$([math]::Floor($sec / 86400))d"
}
function Clean([string]$s) { return ($s -replace "[`t`r`n]", " ") }

# the clock: NIGHTMILL_NOW, else the local clock read as UTC
if ($env:NIGHTMILL_NOW) {
  $epoch = [long]0
  if ($env:NIGHTMILL_NOW -match '^[0-9]+$') { $epoch = [long]$env:NIGHTMILL_NOW }
  $sod = $epoch % 86400
  $clock = "{0:D2}:{1:D2}:{2:D2}" -f [long][math]::Floor($sod / 3600), [long][math]::Floor(($sod % 3600) / 60), [long]($sod % 60)
  $now = $epoch
} else {
  $clock = (Get-Date).ToString("HH:mm:ss")
  $now = StampOf ((Get-Date).ToString("s"))
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("time`t$clock")
$lines.Add("every`t$every")
$notes = New-Object System.Collections.Generic.List[string]
if ($noteEvery) { $notes.Add($noteEvery) }

# the lines of a stream: split at LF, one trailing CR removed from every line; a last empty piece is dropped
function Split-Lines([string]$s) {
  if (-not $s) { return @() }
  $a = @($s -split "`n")
  if ($a[$a.Count - 1] -eq "") { if ($a.Count -eq 1) { return @() }; $a = $a[0..($a.Count - 2)] }
  return @($a | ForEach-Object { if ($_.EndsWith("`r")) { $_.Substring(0, $_.Length - 1) } else { $_ } })
}

if (-not $hasWt) {
  $lines.Add("noslots")
} else {
  $slotPs = Join-Path $PSScriptRoot "slot.ps1"
  $why = ""
  $code = 0
  $out = ""
  $err = ""
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = (Get-Process -Id $PID).Path
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$slotPs`" -Status -Porcelain"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = (Get-Location).ProviderPath
  try {
    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $err = $errTask.Result
    $code = $proc.ExitCode
    $proc.Dispose()
  } catch { $why = ($_.Exception.Message -replace "[`r`n]+", " ").Trim() }

  if ($why -or $code -ne 0) {
    $reason = $why
    if (-not $reason) {
      foreach ($l in @(Split-Lines $err)) {
        $t = $l.TrimEnd(' ')
        if ($t) { $reason = $t; break }
      }
    }
    if (-not $reason) { $reason = "slot.ps1 exited with code $code" }
    $lines.Add("unknown`t" + (Clean $reason))
  } else {
    $rows = New-Object System.Collections.Generic.List[string]
    $bad = $false
    foreach ($l in @(Split-Lines $out)) {
      $f = @($l -split "`t")
      if ($f.Count -eq 2 -and $f[0] -cmatch '^[0-9]+$' -and $f[1] -ceq "free") {
        $rows.Add("slot`t$($f[0])`tfree`t`t`t`t`t")
      } elseif ($f.Count -eq 10 -and $f[0] -cmatch '^[0-9]+$' -and $f[1] -ceq "busy") {
        if ($f[6] -eq "" -and $f[7] -eq "") { $who = "?" }
        else {
          $sk = $f[6]; if ($sk -eq "") { $sk = "?" }
          $ro = $f[7]; if ($ro -eq "") { $ro = "?" }
          $who = "$sk/$ro"
        }
        $step = $f[8]; if ($step -eq "") { $step = "?" }
        $rep = "-"
        if ($f[9] -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\z') { $rep = Span ($now - (StampOf $f[9])) }
        $rows.Add("slot`t$($f[0])`tbusy`t" + (Clean $f[5]) + "`t" + (Clean $f[2]) + "`t" + (Clean $who) + "`t" + (Clean $step) + "`t$rep")
      } else { $bad = $true }
    }
    if ($bad) { $lines.Add("unknown`tslot.ps1 printed a line the panel cannot read") }
    else { foreach ($r in $rows) { $lines.Add($r) } }
    foreach ($l in @(Split-Lines $err)) { if ($l -ne "") { $notes.Add($l) } }
  }
}
foreach ($n in $notes) { $lines.Add("note`t" + (Clean $n)) }

# the records as UTF-8 without a byte order mark, LF after every line
$bytes = $utf8.GetBytes((($lines -join "`n") + "`n"))
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
exit 0

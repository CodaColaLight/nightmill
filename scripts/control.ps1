# scripts/control.ps1 - one pass of the opt-in load controller (nightmill). PowerShell twin of control.sh; the rules
# and the texts are in docs/specs/iteration-30-load-controller.md.
#
#   control.ps1                # no arguments: the mode comes from parallel.controlMode (off, report or apply)
#
# Run it from inside the project: any checkout or worktree of it. When the mode is off it prints one line and ends.
# Otherwise it reads the agent limit, the slot count and the busy slots from the slot script of the same plugin, the
# time of the last change from "since" of <worktrees root>/.slots/capacity.json, measures like scripts/load.ps1
# (parallel.loadWindowSeconds samples, scripts/lib/load.ps1), takes the suggested agent limit as its target and applies
# its rules: the bounds parallel.controlMinAgents and controlMaxAgents, one step up per parallel.controlCooldownMinutes,
# straight down when memory is short, one step down per cooldown for the CPU or the ceiling. In apply mode it changes
# the live agent limit (and raises the slot count when the new limit is above it) only with slot.ps1 -Capacity; in
# report mode it only says what it would change. It makes no file, never lowers the slot count, and never stops an
# agent. One pass is one call: nothing waits or keeps running.
# Exit code 0 a pass that decided or the controller is off, 1 the CPU load or the free memory is unavailable (nothing
# changed), 2 a usage error, no checkout, no or invalid config, an unusable NIGHTMILL_LOAD_FIXTURE or a failed slot
# script.
$ErrorActionPreference = "Stop"

function Stop-Control([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }
if ($args.Count -gt 0) { Stop-Control "usage: control.ps1" }

. (Join-Path $PSScriptRoot "lib\load.ps1")

# The main checkout, wherever this is run from (it may itself be a worktree)
$gitDir = $null
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { $gitDir = & git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
$gitCode = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($gitCode -ne 0 -or -not $gitDir) { Stop-Control "control: run control.ps1 from inside a checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Stop-Control "control: no $cfgPath (run /nightmill:init)" }
try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Stop-Control "control: $cfgPath is not valid JSON: $($_.Exception.Message)" }

$control = Get-ControlSettings $cfg

if ($control.Mode -ceq "off") {
  [Console]::Out.Write("control: off (parallel.controlMode is off); nothing measured or changed`n")
  exit 0
}

$settings = Get-LoadSettings $cfg

# The numbers, from the slot script of the same plugin (its standard error passes through)
$slotScript = Join-Path $PSScriptRoot "slot.ps1"
# The slot script writes its messages with [Console]::Error or throws; both are caught here: its standard error into a
# StringWriter while it runs (passed on when it succeeds), a thrown message after it. On a failure both are folded onto
# one line as control.sh does (line ends to spaces, trailing spaces dropped).
function Invoke-Slot([hashtable]$slotArgs) {
  $global:LASTEXITCODE = 0
  $realErr = [Console]::Error
  $errText = New-Object System.IO.StringWriter
  $thrown = $null
  [Console]::SetError($errText)
  try { $out = @(& $slotScript @slotArgs) } catch { $thrown = $_.Exception.Message } finally { [Console]::SetError($realErr) }
  $code = $LASTEXITCODE
  $text = $errText.ToString()
  if ($null -ne $thrown -or $code -ne 0) {
    if ($null -ne $thrown) { $text += $thrown + "`n" }
    Stop-Control "control: slot.ps1 failed: $(($text -replace '\r?\n', ' ').TrimEnd(' '))"
  }
  if ($text) { [Console]::Error.Write($text) }
  return $out
}
$capLines = Invoke-Slot @{ Capacity = $true; Porcelain = $true }
$statusLines = Invoke-Slot @{ Status = $true; Porcelain = $true }
$limit = $null; $slotCount = $null
foreach ($l in $capLines) {
  $f = @(([string]$l) -split "`t")
  if ($f[0] -eq "agents") { $limit = [int]$f[1] }
  if ($f[0] -eq "slots") { $slotCount = [int]$f[1] }
}
$busy = @($statusLines | Where-Object { @(([string]$_) -split "`t")[1] -eq "busy" }).Count

# The last change: "since" of capacity.json, where the slot scripts keep the live numbers
# Get-Stamp YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC (Get-Stamp of slot.ps1)
function Get-Stamp([string]$s) {
  $yr = [long]$s.Substring(0, 4); $mon = [long]$s.Substring(5, 2); $day = [long]$s.Substring(8, 2)
  if ($mon -le 2) { $yr-- }
  $yy = if ($yr -ge 0) { $yr } else { $yr - 399 }
  $era = [long][math]::Truncate($yy / 400)
  $yoe = $yr - $era * 400
  $shift = if ($mon -gt 2) { -3 } else { 9 }
  $doy = [long][math]::Truncate((153 * ($mon + $shift) + 2) / 5) + $day - 1
  $doe = $yoe * 365 + [long][math]::Truncate($yoe / 4) - [long][math]::Truncate($yoe / 100) + $doy
  return [long](($era * 146097 + $doe - 719468) * 86400 + [long]$s.Substring(11, 2) * 3600 + [long]$s.Substring(14, 2) * 60 + [long]$s.Substring(17, 2))
}
$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
if ($cfg.worktrees -and $cfg.worktrees.root) { $rootRel = $cfg.worktrees.root }
$capPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $main $rootRel))) ".slots\capacity.json"
$since = ""
if (Test-Path -LiteralPath $capPath -PathType Leaf) {
  try {
    $doc = Get-Content -LiteralPath $capPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($doc -is [System.Management.Automation.PSCustomObject]) {
      $sp = $doc.PSObject.Properties["since"]
      if ($sp -and $null -ne $sp.Value) {
        if ($sp.Value -is [datetime]) { $since = $sp.Value.ToString("s") } elseif ($sp.Value -is [string]) { $since = $sp.Value }
      }
    }
  } catch { $since = "" }
}
if ("$env:NIGHTMILL_NOW" -cmatch '^[0-9]{1,12}\z') { $now = [long]$env:NIGHTMILL_NOW } else { $now = Get-Stamp ((Get-Date).ToString("s")) }
$age = $null
if ($since -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\z') {
  $age = $now - (Get-Stamp $since)
  if ($age -lt 0) { $age = 0 }
}

# The measurement and the suggestion
try { $load = Measure-Load -Samples $settings.Window } catch { Stop-Control $_.Exception.Message }
$sug = Get-LoadSuggestion -Load $load -Settings $settings -Busy $busy

if ($control.Mode -ceq "apply") { $pre = "control: " } else { $pre = "control (report only, nothing changed): " }
$next = "control: next pass in $($control.Interval) min (parallel.controlIntervalMinutes)"
function Write-Lines([string[]]$lines) { foreach ($x in $lines) { [Console]::Out.Write($x + "`n") } }

if ($null -eq $sug.Suggest) {
  if ($null -eq $load.Cpu -and $null -eq $load.Free) {
    $what = "the CPU load ($($load.CpuWhy)) and the free memory ($($load.MemWhy)) are unavailable"
  } elseif ($null -eq $load.Cpu) {
    $what = "the CPU load is unavailable ($($load.CpuWhy))"
  } else {
    $what = "the free memory is unavailable ($($load.MemWhy))"
  }
  Write-Lines @("${pre}agent limit $limit kept (unavailable; $what)", $next)
  exit 1
}

# The rule (the first row that applies)
$lo = [long]$control.Min; $hi = [long]$control.Max; $p = [long]$sug.Suggest; $cur = [long]$limit
$target = [math]::Min($hi, [math]::Max($lo, $p))
$memory = @("memory-short", "memory-total", "memory-free") -ccontains $sug.Reason
$cooling = ($null -ne $age -and $age -lt $control.Cooldown * 60)

if ($cur -lt $lo) { $new = $lo; $rule = "minimum" }
elseif ($memory -and $target -lt $cur) { $new = $target; $rule = "memory" }
elseif ($cur -gt $hi) { $new = $hi; $rule = "maximum" }
elseif ($target -eq $cur) {
  $new = $cur
  if ($cur -eq $hi -and $p -gt $hi) { $rule = "at the maximum" }
  elseif ($cur -eq $lo -and $p -lt $lo) { $rule = "at the minimum" }
  else { $rule = "steady" }
}
elseif ($cooling) {
  $new = $cur
  $left = [long][math]::Floor(($control.Cooldown * 60 - $age + 59) / 60)
  $rule = "cooldown $left of $($control.Cooldown) min left"
}
elseif ($target -gt $cur) { $new = $cur + 1; $rule = "room" }
else {
  $new = $cur - 1
  if ($sug.Reason -ceq "ceiling") { $rule = "ceiling" } else { $rule = "cpu" }
}

$measure = "CPU $($load.Cpu)%, free memory $($load.Free) of $($load.Total) MB, busy slots $busy, suggested $p`: $($sug.Why)"

if ($new -eq $cur) {
  Write-Lines @("${pre}agent limit $cur kept ($rule; $measure)", $next)
  exit 0
}

$slotsPart = ""
$setArgs = @{ Capacity = $true; AgentLimit = "$new" }
if ($new -gt $slotCount) {
  $slotsPart = ", slots $slotCount -> $new"
  $setArgs["SlotCount"] = "$new"
}
if ($control.Mode -ceq "apply") { $null = Invoke-Slot $setArgs }
Write-Lines @("${pre}agent limit $cur -> $new$slotsPart ($rule; $measure)", $next)
exit 0

# scripts/load.ps1 - the machine's CPU load and free memory, the agent limit, the slots in use and a suggested agent
# limit with the reason (nightmill). PowerShell twin of load.sh; the rules and the texts are in
# docs/specs/iteration-24-machine-load.md.
#
#   load.ps1 [-Porcelain]      # -Porcelain: one tab separated line per value, by name, for scripts
#
# Run it from inside the project: any checkout or worktree of it. It measures for parallel.loadWindowSeconds seconds
# (default 10), one sample a second (scripts/lib/load.ps1), reads the agent limit and the slots from slot.ps1 -Capacity
# -Porcelain and slot.ps1 -Status -Porcelain, and prints. It only reads: it never changes the agent limit or the slot
# count (slot.ps1 -Capacity -AgentLimit N does that).
# Exit code 0 with a suggestion, 1 when the CPU load or the free memory is unavailable (no suggestion), 2 for a usage
# error, no checkout, no or invalid config, a failed slot script or an unusable NIGHTMILL_LOAD_FIXTURE.
param([switch]$Porcelain)
$ErrorActionPreference = "Stop"

function Stop-Load([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }
if ($args.Count -gt 0) { Stop-Load "usage: load.ps1 [-Porcelain]" }

. (Join-Path $PSScriptRoot "lib\load.ps1")

# The main checkout, wherever this is run from (it may itself be a worktree)
$gitDir = $null
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { $gitDir = & git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
$gitCode = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($gitCode -ne 0 -or -not $gitDir) { Stop-Load "load: run load.ps1 from inside a checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Stop-Load "load: no $cfgPath (run /nightmill:init)" }
try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Stop-Load "load: $cfgPath is not valid JSON: $($_.Exception.Message)" }

$settings = Get-LoadSettings $cfg

# The slot numbers, from the slot script of the same plugin (its standard error passes through)
$slotScript = Join-Path $PSScriptRoot "slot.ps1"
# The slot script writes its messages with [Console]::Error or throws; both are caught here: its standard error into a
# StringWriter while it runs (passed on when it succeeds), a thrown message after it. On a failure both are folded onto
# one line as load.sh does (line ends to spaces, trailing spaces dropped).
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
    Stop-Load "load: slot.ps1 failed: $(($text -replace '\r?\n', ' ').TrimEnd(' '))"
  }
  if ($text) { [Console]::Error.Write($text) }
  return $out
}
$capLines = Invoke-Slot @{ Capacity = $true; Porcelain = $true }
$statusLines = Invoke-Slot @{ Status = $true; Porcelain = $true }
$limit = $null; $limitFrom = $null; $limitCfg = $null; $slotCount = $null
foreach ($l in $capLines) {
  $f = @(([string]$l) -split "`t")
  if ($f[0] -eq "agents") { $limit = [int]$f[1]; $limitFrom = $f[2]; $limitCfg = $f[3] }
  if ($f[0] -eq "slots") { $slotCount = [int]$f[1] }
}
$busy = @($statusLines | Where-Object { @(([string]$_) -split "`t")[1] -eq "busy" }).Count

# The measurement and the suggestion
try { $load = Measure-Load -Samples $settings.Window } catch { Stop-Load $_.Exception.Message }
$sug = Get-LoadSuggestion -Load $load -Settings $settings -Busy $busy

$direction = $null
if ($null -ne $sug.Suggest) {
  if ($sug.Suggest -gt $limit) { $direction = "raise" } elseif ($sug.Suggest -lt $limit) { $direction = "lower" } else { $direction = "keep" }
}
$none = $null
if ($null -eq $load.Cpu -and $null -eq $load.Free) { $none = "the CPU load and the free memory are unavailable" }
elseif ($null -eq $load.Cpu) { $none = "the CPU load is unavailable" }
elseif ($null -eq $load.Free) { $none = "the free memory is unavailable" }

$lines = @()
if ($Porcelain) {
  if ($null -ne $load.Cpu) { $lines += "cpu`t$($load.Cpu)" } else { $lines += "cpu`tunavailable`t$($load.CpuWhy)" }
  if ($null -ne $load.Free) {
    $lines += "memory-free`t$($load.Free)"; $lines += "memory-total`t$($load.Total)"
  } else {
    $lines += "memory-free`tunavailable`t$($load.MemWhy)"; $lines += "memory-total`tunavailable`t$($load.MemWhy)"
  }
  $lines += "window`t$($load.Samples)`t$($load.From)"
  $lines += "agent-limit`t$limit`t$limitFrom"
  $lines += "slot-count`t$slotCount"
  $lines += "slots-busy`t$busy"
  $lines += "agents-running`t$busy"
  $lines += "memory-per-agent`t$($settings.GB)"
  $lines += "ceiling`t$($settings.Ceiling)"
  if ($null -ne $sug.Suggest) { $lines += "suggested`t$($sug.Suggest)`t$direction`t$($sug.Reason)" } else { $lines += "suggested`tnone`tunavailable" }
} else {
  $how = if ($load.From -eq "fixture") { " from NIGHTMILL_LOAD_FIXTURE" } else { ", 1 s apart" }
  if ($null -ne $load.Cpu) { $lines += "cpu: $($load.Cpu)% busy (mean of $($load.Samples) samples$how)" } else { $lines += "cpu: unavailable ($($load.CpuWhy))" }
  if ($null -ne $load.Free) { $lines += "memory: $($load.Free) MB free of $($load.Total) MB (lowest of $($load.Samples) samples)" } else { $lines += "memory: unavailable ($($load.MemWhy))" }
  if ($limitFrom -eq "live") { $lines += "agent limit: $limit (live; config $limitCfg)" } else { $lines += "agent limit: $limit ($limitFrom)" }
  $lines += "slots: $busy of $slotCount in use"
  $lines += "agents running: $busy (counted from the busy slots)"
  if ($null -ne $sug.Suggest) {
    $lines += "suggested agent limit: $($sug.Suggest) (now $limit`: $direction)"
    $lines += "why: $($sug.Why)"
  } else {
    $lines += "suggested agent limit: none ($none)"
  }
}
foreach ($l in $lines) { [Console]::Out.Write($l + "`n") }

if ($null -ne $sug.Suggest) { exit 0 }
exit 1

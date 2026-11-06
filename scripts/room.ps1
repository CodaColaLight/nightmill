# scripts/room.ps1 - does the machine have room for one more agent? Free memory and CPU load over 3 one-second samples,
# against parallel.roomMinFreeMB and parallel.roomMaxCpuPercent (nightmill). PowerShell twin of room.sh; the rules and
# the texts are in docs/specs/iteration-28-machine-room.md.
#
#   room.ps1                    # the first check
#   room.ps1 -Since <seconds>   # a check while waiting: the value of the "room: call again with" line
#
# Run it from inside the project: any checkout or worktree of it. It measures with scripts/lib/load.ps1 and only reads:
# it writes nothing, calls no slot script and never changes the agent limit. When there is no room it prints why,
# pauses parallel.roomPauseSeconds and exits 1; the skill calls it again with -Since, and the script ends the wait
# itself after parallel.roomMaxWaitMinutes.
# Exit code 0 start (room, switched off, or nothing that could be checked holds it), 1 no room yet (paused; call again
# with -Since), 2 for a usage error, no checkout, no or invalid config or an unusable NIGHTMILL_LOAD_FIXTURE, 3 the
# longest wait ran out (start nothing).
# The arguments are parsed here (no typed param binding), so -Since without a value is a usage error too.
$ErrorActionPreference = "Stop"

function Stop-Room([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }
function Write-Line([string]$line) { [Console]::Out.Write($line + "`n") }

$usage = "usage: room.ps1 [-Since <seconds>]"
$sinceArg = $null
$rest = @($args)
for ($i = 0; $i -lt $rest.Count; $i++) {
  $a = [string]$rest[$i]
  if ($a -eq "-Since") {
    if ($null -ne $sinceArg) { Stop-Room $usage }
    if ($i + 1 -ge $rest.Count) { Stop-Room $usage }
    $v = [string]$rest[$i + 1]
    if ($v -cnotmatch '^[1-9][0-9]{0,11}$') { Stop-Room $usage }
    $sinceArg = [long]$v
    $i++
  } else {
    Stop-Room $usage
  }
}

. (Join-Path $PSScriptRoot "lib\load.ps1")

# The main checkout, wherever this is run from (it may itself be a worktree)
$gitDir = $null
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { $gitDir = & git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
$gitCode = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($gitCode -ne 0 -or -not $gitDir) { Stop-Room "room: run room.ps1 from inside a checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Stop-Room "room: no $cfgPath (run /nightmill:init)" }
try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Stop-Room "room: $cfgPath is not valid JSON: $($_.Exception.Message)" }

$room = Get-RoomSettings $cfg

if (-not $room.On) {
  Write-Line "room: not checked (parallel.roomCheck is false)"
  exit 0
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($null -ne $sinceArg) { $since = $sinceArg } else { $since = $now }
$waited = $now - $since
if ($waited -lt 0) { $waited = 0 }

try { $load = Measure-Load -Samples 3 } catch { Stop-Room $_.Exception.Message }

$short = $false; $high = $false; $memPart = ""; $cpuPart = ""; $details = ""
if ($null -eq $load.Free) {
  Write-Line "room: free memory not checked: unavailable ($($load.MemWhy))"
  $memPart = "free memory not checked"
} elseif ($load.Free -ge $room.MinFree) {
  $memPart = "free memory $($load.Free) MB (at least $($room.MinFree))"
} else {
  $short = $true
  $details = "free memory $($load.Free) MB, limit at least $($room.MinFree) MB"
}
if ($null -eq $load.Cpu) {
  Write-Line "room: CPU load not checked: unavailable ($($load.CpuWhy))"
  $cpuPart = "CPU not checked"
} elseif ($load.Cpu -le $room.MaxCpu) {
  $cpuPart = "CPU $($load.Cpu)% (at most $($room.MaxCpu)%)"
} else {
  $high = $true
  if ($details) { $details += "; " }
  $details += "CPU $($load.Cpu)%, limit at most $($room.MaxCpu)%"
}

# room is judged before the clock: a check that finds room starts however long the wait was
if (-not $short -and -not $high) {
  Write-Line "room: yes: $memPart, $cpuPart"
  exit 0
}

if ($short -and $high) { $what = "memory and CPU" } elseif ($short) { $what = "memory" } else { $what = "CPU" }
$w = [long][math]::Floor($waited / 60)

if ($waited -ge [long]$room.MaxWait * 60) {
  Write-Line "room: gave up after $w min: $details"
  exit 3
}

Write-Line "room: waiting for ${what}: $details (waited $w of $($room.MaxWait) min; next check in $($room.Pause) s)"
Write-Line "room: call again with -Since $since"
Start-Sleep -Seconds $room.Pause
exit 1

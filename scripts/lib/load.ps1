# scripts/lib/load.ps1 - the machine's CPU load and free memory over a short window, and a suggested agent limit
# (nightmill). PowerShell twin of scripts/lib/load.sh; the rules and the texts are in
# docs/specs/iteration-24-machine-load.md. Dot-source it; loading it runs nothing.
#
#   Get-LoadSettings $Config            an object with Ceiling, GB, Window from parallel.maxSuggestedAgents,
#                                       memoryPerAgentGB and loadWindowSeconds (a wrong value: one warning on standard
#                                       error and the default)
#   Measure-Load -Samples <n>           an object with Cpu, CpuWhy, Free, Total, MemWhy, Samples, From (measured or
#                                       fixture); a value is $null when unavailable and its Why holds the reason. Throws
#                                       the message of an unusable NIGHTMILL_LOAD_FIXTURE
#   Get-LoadSuggestion -Load -Settings -Busy   an object with Suggest, Reason (the key), Why (the text), all $null when a
#                                       value is unavailable
#   Get-RoomSettings $Config            an object with On ([bool]), MinFree, MaxCpu, Pause, MaxWait from
#                                       parallel.roomCheck, roomMinFreeMB, roomMaxCpuPercent, roomPauseSeconds and
#                                       roomMaxWaitMinutes (warnings on standard error with the prefix room;
#                                       docs/specs/iteration-28-machine-room.md)
#
# Readers: Windows reads Win32_PerfRawData_PerfOS_Processor (the raw counters, not a load percentage) and
# Win32_OperatingSystem; pwsh on Linux reads /proc/stat and /proc/meminfo (MemAvailable); pwsh on macOS top, vm_stat
# and sysctl hw.memsize. $env:NIGHTMILL_LOAD_FIXTURE names a file of samples "<cpu percent> <free MB> <total MB>" read
# instead (no sleep).

function Get-LoadSetting($Config, [string]$Key, [int]$Low, [int]$High, [int]$Default, [string]$Prefix = "load") {
  if ($null -eq $Config -or -not ($Config -is [System.Management.Automation.PSCustomObject])) { return $Default }
  $pp = $Config.PSObject.Properties["parallel"]
  if (-not $pp -or -not ($pp.Value -is [System.Management.Automation.PSCustomObject])) { return $Default }
  $p = $pp.Value.PSObject.Properties[$Key]
  if (-not $p -or $null -eq $p.Value) { return $Default }
  $v = $p.Value
  if (($v -is [int] -or $v -is [long]) -and $v -ge $Low -and $v -le $High) { return [int]$v }
  [Console]::Error.WriteLine("${Prefix}: parallel.$Key must be a whole number from $Low to $High; using $Default")
  return $Default
}

function Get-LoadSettings($Config) {
  $ceiling = Get-LoadSetting $Config "maxSuggestedAgents" 1 99 4
  $gb = Get-LoadSetting $Config "memoryPerAgentGB" 1 1024 8
  $window = Get-LoadSetting $Config "loadWindowSeconds" 2 60 10
  return [pscustomobject]@{ Ceiling = $ceiling; GB = $gb; Window = $window }
}

function Get-RoomSettings($Config) {
  $on = $true
  if ($null -ne $Config -and $Config -is [System.Management.Automation.PSCustomObject]) {
    $pp = $Config.PSObject.Properties["parallel"]
    if ($pp -and $pp.Value -is [System.Management.Automation.PSCustomObject]) {
      $p = $pp.Value.PSObject.Properties["roomCheck"]
      if ($p -and $null -ne $p.Value) {
        if ($p.Value -is [bool]) { $on = [bool]$p.Value }
        else { [Console]::Error.WriteLine("room: parallel.roomCheck must be true or false; using true") }
      }
    }
  }
  $minFree = Get-LoadSetting $Config "roomMinFreeMB" 1 999999 2000 "room"
  $maxCpu = Get-LoadSetting $Config "roomMaxCpuPercent" 1 100 90 "room"
  $pause = Get-LoadSetting $Config "roomPauseSeconds" 1 90 60 "room"
  $maxWait = Get-LoadSetting $Config "roomMaxWaitMinutes" 1 1440 30 "room"
  return [pscustomobject]@{ On = $on; MinFree = $minFree; MaxCpu = $maxCpu; Pause = $pause; MaxWait = $maxWait }
}

# Get-LoadReader: linux, macos or windows ($IsLinux and $IsMacOS do not exist in Windows PowerShell 5.1)
function Get-LoadReader {
  $lin = Get-Variable -Name IsLinux -ValueOnly -ErrorAction SilentlyContinue
  $mac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
  if ($lin) { return "linux" }
  if ($mac) { return "macos" }
  return "windows"
}

# Read-LoadStat: @(total, idle) of the first line of /proc/stat (the first eight counters; idle + iowait), or $null
function Read-LoadStat {
  try { $line = @([IO.File]::ReadAllLines("/proc/stat"))[0] } catch { return $null }
  if ($null -eq $line) { return $null }
  $f = @(([string]$line).Trim() -split '\s+')
  if ($f[0] -cne "cpu") { return $null }
  $n = 0; $t = [double]0; $vals = @()
  for ($i = 1; $i -lt $f.Count -and $n -lt 8; $i++) {
    if ($f[$i] -notmatch '^[0-9]+$') { break }
    $vals += [double]$f[$i]; $t += [double]$f[$i]; $n++
  }
  if ($n -lt 4) { return $null }
  $idle = $vals[3]
  if ($n -ge 5) { $idle += $vals[4] }
  return @($t, $idle)
}

# Read-LoadMeminfo: @(free MB, total MB) from /proc/meminfo, or the reason as a string
function Read-LoadMeminfo {
  try { $lines = [IO.File]::ReadAllLines("/proc/meminfo") } catch { return "/proc/meminfo cannot be read" }
  $total = $null; $free = $null
  foreach ($l in $lines) {
    $f = @(([string]$l).Trim() -split '\s+')
    if ($f.Count -lt 2 -or $f[1] -notmatch '^[0-9]+$') { continue }
    if ($f[0] -ceq "MemTotal:") { $total = [double]$f[1] }
    if ($f[0] -ceq "MemAvailable:") { $free = [double]$f[1] }
  }
  if ($null -eq $total) { return "/proc/meminfo cannot be read" }
  if ($null -eq $free) { return "/proc/meminfo has no MemAvailable" }
  return @([long][math]::Floor($free * 1024 / 1000000), [long][math]::Floor($total * 1024 / 1000000))
}

# Read-LoadTop: the busy percentage of one top sample (top -l 2 -s 1 -n 0, the second CPU usage line), or $null
function Read-LoadTop {
  try { $out = @(& top -l 2 -s 1 -n 0 2>$null) } catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  $c = 0
  foreach ($l in $out) {
    if ("$l" -match 'CPU usage:') {
      $c++
      if ($c -eq 2 -and "$l" -match '([0-9]+(\.[0-9]+)?)% idle') {
        $u = 100 - [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        return [math]::Min(100, [math]::Max(0, $u))
      }
    }
  }
  return $null
}

# Read-LoadVm: @(free MB, total MB) from vm_stat and sysctl -n hw.memsize, or $null
function Read-LoadVm {
  try {
    $vm = @(& vm_stat 2>$null); if ($LASTEXITCODE -ne 0) { return $null }
    $mem = "$(& sysctl -n hw.memsize 2>$null)".Trim(); if ($LASTEXITCODE -ne 0) { return $null }
  } catch { return $null }
  if ($mem -notmatch '^[0-9]+$' -or $vm.Count -lt 1) { return $null }
  if ("$($vm[0])" -notmatch 'page size of ([0-9]+) bytes') { return $null }
  $page = [double]$Matches[1]
  $pages = [double]0; $n = 0
  foreach ($l in $vm) {
    if ("$l" -match '^Pages (free|inactive|speculative):\s+([0-9]+)\.?\s*$') { $pages += [double]$Matches[2]; $n++ }
  }
  if ($page -le 0 -or $n -lt 3) { return $null }
  return @([long][math]::Floor($pages * $page / 1000000), [long][math]::Floor([double]$mem / 1000000))
}

# Read-LoadWinCpu: @(PercentProcessorTime, Timestamp_Sys100NS) of the _Total processor, or $null
function Read-LoadWinCpu {
  try {
    $c = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop | Select-Object -First 1
  } catch { return $null }
  if ($null -eq $c -or $null -eq $c.PercentProcessorTime -or $null -eq $c.Timestamp_Sys100NS) { return $null }
  return @([double]$c.PercentProcessorTime, [double]$c.Timestamp_Sys100NS)
}

# Read-LoadWinMem: @(free MB, total MB) from Win32_OperatingSystem, or $null
function Read-LoadWinMem {
  try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1 } catch { return $null }
  if ($null -eq $os -or $null -eq $os.FreePhysicalMemory -or $null -eq $os.TotalVisibleMemorySize) { return $null }
  return @([long][math]::Floor([double]$os.FreePhysicalMemory * 1024 / 1000000), [long][math]::Floor([double]$os.TotalVisibleMemorySize * 1024 / 1000000))
}

# Read-LoadFixture <path>: the samples of the fixture file as objects with Cpu, Free, Total ($null for "-"); throws the
# message of an unusable fixture
function Read-LoadFixture([string]$Path) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing" }
    $text = [IO.File]::ReadAllText($Path)
  } catch { throw "load: cannot read NIGHTMILL_LOAD_FIXTURE: $Path" }
  $lines = $text -split "`n"
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
  $samples = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].TrimEnd("`r")
    if ($line.Trim(" `t") -eq "" -or $line.StartsWith("#")) { continue }
    $bad = "load: NIGHTMILL_LOAD_FIXTURE line $($i + 1) is not `"<cpu> <free MB> <total MB>`""
    $f = @($line.Trim(" `t") -split '[ \t]+')
    if ($f.Count -ne 3) { throw $bad }
    $cpu = $null; $free = $null; $total = $null
    if ($f[0] -ne "-") {
      if ($f[0] -notmatch '^[0-9]+(\.[0-9]+)?$') { throw $bad }
      $cpu = [double]::Parse($f[0], $inv)
      if ($cpu -gt 100) { throw $bad }
    }
    if ($f[1] -ne "-") {
      if ($f[1] -notmatch '^[0-9]+$') { throw $bad }
      $free = [double]::Parse($f[1], $inv)
    }
    if ($f[2] -ne "-") {
      if ($f[2] -notmatch '^[0-9]+$') { throw $bad }
      $total = [double]::Parse($f[2], $inv)
      if ($total -lt 1) { throw $bad }
    }
    $samples += [pscustomobject]@{ Cpu = $cpu; Free = $free; Total = $total }
  }
  if ($samples.Count -lt 2) { throw "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples" }
  return $samples
}

function Measure-Load([int]$Samples) {
  $from = "measured"; $cpuWhy = $null; $memWhy = $null
  $list = @()
  if ($env:NIGHTMILL_LOAD_FIXTURE) {
    $from = "fixture"
    $list = @(Read-LoadFixture $env:NIGHTMILL_LOAD_FIXTURE)
  } else {
    $reader = Get-LoadReader
    if ($reader -eq "macos") {
      for ($i = 1; $i -le $Samples; $i++) {
        $cpu = $null; $free = $null; $total = $null
        if (-not $cpuWhy) {
          # top takes the second of the sample itself
          $cpu = Read-LoadTop
          if ($null -eq $cpu) { $cpuWhy = "top gave no CPU usage" }
        } elseif (-not $memWhy) { Start-Sleep -Seconds 1 }
        if (-not $memWhy) {
          $m = Read-LoadVm
          if ($null -eq $m) { $memWhy = "vm_stat or sysctl hw.memsize gave no reading" } else { $free = $m[0]; $total = $m[1] }
        }
        $list += [pscustomobject]@{ Cpu = $cpu; Free = $free; Total = $total }
      }
    } else {
      $cpuRead = if ($reader -eq "linux") { "/proc/stat cannot be read" } else { "Win32_PerfRawData_PerfOS_Processor cannot be read" }
      $prev = if ($reader -eq "linux") { Read-LoadStat } else { Read-LoadWinCpu }
      if ($null -eq $prev) { $cpuWhy = $cpuRead }
      for ($i = 1; $i -le $Samples; $i++) {
        if (-not $cpuWhy -or -not $memWhy) { Start-Sleep -Seconds 1 }
        $cpu = $null; $free = $null; $total = $null
        if (-not $cpuWhy) {
          $cur = if ($reader -eq "linux") { Read-LoadStat } else { Read-LoadWinCpu }
          if ($null -eq $cur) { $cpuWhy = $cpuRead }
          else {
            # linux: @(total, idle), busy = (d total - d idle) / d total; windows: @(PercentProcessorTime,
            # Timestamp_Sys100NS), busy = 1 - d PercentProcessorTime / d Timestamp_Sys100NS
            if ($reader -eq "linux") { $dt = $cur[0] - $prev[0] } else { $dt = $cur[1] - $prev[1] }
            if ($dt -le 0) { $cpuWhy = "the CPU counters did not move" }
            else {
              if ($reader -eq "linux") { $v = 100 * ($dt - ($cur[1] - $prev[1])) / $dt }
              else { $v = 100 * (1 - ($cur[0] - $prev[0]) / $dt) }
              $cpu = [math]::Min(100, [math]::Max(0, $v)); $prev = $cur
            }
          }
        }
        if (-not $memWhy) {
          if ($reader -eq "linux") {
            $m = Read-LoadMeminfo
            if ($m -is [string]) { $memWhy = $m } else { $free = $m[0]; $total = $m[1] }
          } else {
            $m = Read-LoadWinMem
            if ($null -eq $m) { $memWhy = "Win32_OperatingSystem cannot be read" } else { $free = $m[0]; $total = $m[1] }
          }
        }
        $list += [pscustomobject]@{ Cpu = $cpu; Free = $free; Total = $total }
      }
    }
  }
  # the window: the mean CPU, the lowest free memory, the total of the first sample; one failed sample makes that
  # measurement unavailable, with the reason of the first failed sample
  $sum = [double]0; $cpuFail = 0; $memFail = 0; $minFree = $null; $firstTotal = $null
  for ($i = 0; $i -lt $list.Count; $i++) {
    $s = $list[$i]
    if ($null -eq $s.Cpu) { if (-not $cpuFail) { $cpuFail = $i + 1 } }
    else { $sum += [math]::Min(100, [math]::Max(0, [double]$s.Cpu)) }
    if ($null -eq $s.Free -or $null -eq $s.Total) { if (-not $memFail) { $memFail = $i + 1 } }
    else {
      if ($null -eq $minFree -or [double]$s.Free -lt $minFree) { $minFree = [double]$s.Free }
      if ($null -eq $firstTotal) { $firstTotal = [double]$s.Total }
    }
  }
  $cpuOut = $null; $freeOut = $null; $totalOut = $null
  if ($cpuFail) {
    if ($from -eq "fixture") { $cpuWhy = "sample $cpuFail has no CPU reading" }
  } else {
    $cpuOut = [long][math]::Floor($sum / $list.Count + 0.5); $cpuWhy = $null
  }
  if ($memFail) {
    if ($from -eq "fixture") { $memWhy = "sample $memFail has no memory reading" }
  } else {
    $freeOut = [long]$minFree; $totalOut = [long]$firstTotal; $memWhy = $null
  }
  return [pscustomobject]@{ Cpu = $cpuOut; CpuWhy = $cpuWhy; Free = $freeOut; Total = $totalOut; MemWhy = $memWhy; Samples = $list.Count; From = $from }
}

function Get-LoadSuggestion($Load, $Settings, [int]$Busy) {
  if ($null -eq $Load.Cpu -or $null -eq $Load.Free -or $null -eq $Load.Total) {
    return [pscustomobject]@{ Suggest = $null; Reason = $null; Why = $null }
  }
  $a = [long]$Busy; $c = [long]$Load.Cpu; $f = [long]$Load.Free; $t = [long]$Load.Total
  $k = [long]$Settings.Ceiling; $gb = [long]$Settings.GB
  $m = $gb * 1000
  $short = ($f * 10 -lt $t)
  $byTotal = [long][math]::Floor($t / $m)
  $more = [long][math]::Floor($f / $m)
  $byFree = $a + $more
  if ($short) { $mem = $a - 1 } elseif ($byTotal -le $byFree) { $mem = $byTotal } else { $mem = $byFree }
  if ($a -eq 0) { if ($c -lt 80) { $cpu = $k } else { $cpu = 1 } }
  elseif ($c -eq 0) { $cpu = $k }
  else { $cpu = [long][math]::Floor($a * 80 / $c) }
  $raw = [math]::Min($mem, $cpu)
  $p = [math]::Max(1, [math]::Min($k, $raw))
  if ($raw -gt $k) {
    $reason = "ceiling"; $why = "the ceiling is the limit (parallel.maxSuggestedAgents = $k); CPU and memory have room for more"
  } elseif ($mem -le $cpu) {
    if ($short) {
      $reason = "memory-short"; $why = "memory is short: $f MB free is under 10% of $t MB, one agent fewer than the $a in the slots"
    } elseif ($byTotal -le $byFree) {
      $reason = "memory-total"; $why = "memory is the limit: $t MB in all holds $byTotal agents at $gb GB each"
    } else {
      $reason = "memory-free"; $why = "memory is the limit: $f MB free holds $more more agents at $gb GB each beside the $a in the slots"
    }
  } elseif ($a -eq 0) {
    $reason = "cpu-other"; $why = "CPU is the limit: $c% busy with no slot in use"
  } else {
    $reason = "cpu"; $why = "CPU is the limit: $c% busy with $a agents in the slots, aiming at 80%"
  }
  return [pscustomobject]@{ Suggest = [long]$p; Reason = $reason; Why = $why }
}

# tests/smoke-room.ps1 - room.ps1 against fixtures of readings ($env:NIGHTMILL_LOAD_FIXTURE is set in every call that
# measures, so the real measurement never runs and the result does not depend on this machine), in a throwaway
# repository. The cases 1 to 11 are those of "Tests" in docs/specs/iteration-28-machine-room.md; smoke-room.sh runs the
# same cases. The pause is parallel.roomPauseSeconds 1 unless a case says otherwise, so nothing sleeps long.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$R = Join-Path $here "scripts\room.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-room-" + [guid]::NewGuid().ToString("N"))
[void][IO.Directory]::CreateDirectory($tmp)

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

try {
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  [void][IO.Directory]::CreateDirectory((Join-Path $work ".claude"))
  $fx = Join-Path $tmp "fx"
  [void][IO.Directory]::CreateDirectory($fx)
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain
  $outside = Join-Path $tmp "outside"
  [void][IO.Directory]::CreateDirectory($outside)
  $cfg = Join-Path $work ".claude\nightmill.json"
  $script:Written = ""
  # Set-Parallel <json members>: the config with exactly these members in parallel
  function Set-Parallel([string]$members) {
    $script:Written = "{`n  `"github`": { `"owner`": `"acme`", `"repo`": `"widgets`", `"projectNumber`": 1 },`n  `"maintainer`": { `"name`": `"Alex`" },`n  `"verification`": { `"check`": `"true`" },`n  `"parallel`": { $members }`n}`n"
    Write-Utf8 $cfg $script:Written
  }
  # Set-Par <json members>: roomPauseSeconds 1 and the members given
  function Set-Par([string]$members = "") {
    if ($members) { Set-Parallel "`"roomPauseSeconds`": 1, $members" } else { Set-Parallel '"roomPauseSeconds": 1' }
  }
  Set-Par

  function Set-Fixture([string]$name, [string[]]$lines) { Write-Utf8 (Join-Path $fx $name) (($lines -join "`n") + "`n") }
  Set-Fixture "ok" @("30 6000 16000", "40 6500 16000", "50 7000 16000")
  Set-Fixture "short" @("40 2500 16000", "40 1500 16000", "40 3000 16000")
  Set-Fixture "high" @("95 6000 16000", "95 6000 16000", "95 6000 16000")
  Set-Fixture "both" @("95 1500 16000", "95 1500 16000", "95 1500 16000")
  Set-Fixture "cpu-gone" @("30 6000 16000", "- 6500 16000", "50 7000 16000")
  Set-Fixture "mem-gone" @("30 - 16000", "40 6500 16000", "50 7000 16000")
  Set-Fixture "mem-gone-high" @("95 - 16000", "95 6000 16000", "95 6000 16000")
  Set-Fixture "all-gone" @("30 - 16000", "- 6500 16000", "50 7000 16000")
  Set-Fixture "one" @("30 6000 16000")

  function Get-Status { (@(& git -C $work status --porcelain --untracked-files=all) -join "`n") }
  $statusBefore = Get-Status

  # Run-R <dir> <fixture path> [arguments] [extra environment]: run room.ps1 in a child powershell; Out, Err, Code, Took
  function Run-R([string]$dir, [string]$fxPath, [string]$extra = "", [hashtable]$envs = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$R`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["NIGHTMILL_LOAD_FIXTURE"] = $fxPath
    foreach ($k in $envs.Keys) { $psi.EnvironmentVariables[$k] = $envs[$k] }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $sw.Stop()
    $script:Out = $out -replace "`r`n", "`n"
    $script:Err = $errTask.Result -replace "`r`n", "`n"
    $script:Code = $p.ExitCode
    $script:Took = $sw.Elapsed.TotalSeconds
  }
  function Run([string]$name, [string]$extra = "") { Run-R $work (Join-Path $fx $name) $extra }

  function Expect-Out([string]$what, [string[]]$want) {
    $w = ($want -join "`n") + "`n"
    if ($script:Out -ne $w) { Write-Host "--- expected"; Write-Host $w; Write-Host "--- got"; Write-Host $script:Out; Write-Host "--- stderr"; Write-Host $script:Err; Fail "$what`: the output differs" }
  }
  function Has-Line([string]$what, [string]$line) {
    if (@($script:Out -split "`n") -notcontains $line) { Write-Host $script:Out; Write-Host $script:Err; Fail "$what`: no line '$line'" }
  }
  function Has-Err([string]$what, [string]$line) {
    if (@($script:Err -split "`n") -notcontains $line) { Write-Host $script:Err; Fail "$what`: standard error has no line '$line'" }
  }
  function Code-Is([string]$what, [int]$want) {
    if ($script:Code -ne $want) { Write-Host $script:Out; Write-Host $script:Err; Fail "$what`: exit code $($script:Code), expected $want" }
  }
  function No-Err([string]$what) { if ($script:Err) { Write-Host $script:Err; Fail "$what`: something on standard error" } }
  function No-Out([string]$what) { if ($script:Out) { Write-Host $script:Out; Fail "$what`: something on standard output" } }
  function Quick([string]$what) { if ($script:Took -ge 30) { Fail "$what`: took $($script:Took) s (it paused)" } }
  # Get-SinceOf: the <n> of the line "room: call again with -Since <n>", or $null
  function Get-SinceOf {
    foreach ($l in @($script:Out -split "`n")) { if ($l -match '^room: call again with -Since ([0-9]+)$') { return [long]$Matches[1] } }
    return $null
  }

  $roomOk = "room: yes: free memory 6000 MB (at least 2000), CPU 40% (at most 90%)"

  Write-Host "== 1. room"
  Run "ok"
  Code-Is "room" 0
  No-Err "room"
  Expect-Out "room" @($roomOk)

  Write-Host "== 2. no room, memory"
  $before = Get-Now
  Run "short"
  Code-Is "no room, memory" 1
  Has-Line "no room, memory" "room: waiting for memory: free memory 1500 MB, limit at least 2000 MB (waited 0 of 30 min; next check in 1 s)"
  $n = Get-SinceOf
  if ($null -eq $n) { Write-Host $Out; Fail "no room, memory: no line 'room: call again with -Since <n>'" }
  if ($n -lt $before -or $n -gt $before + 5) { Fail "no room, memory: -Since $n is not within 5 of the clock $before" }
  if (@($Out -split "`n" | Where-Object { $_ -ne "" }).Count -ne 2) { Write-Host $Out; Fail "no room, memory: not two lines" }
  if ($Took -lt 1) { Fail "no room, memory: the call did not pause ($Took s)" }

  Write-Host "== 3. no room, CPU and both"
  Run "high"
  Code-Is "no room, CPU" 1
  Has-Line "no room, CPU" "room: waiting for CPU: CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"
  Run "both"
  Code-Is "no room, both" 1
  Has-Line "no room, both" "room: waiting for memory and CPU: free memory 1500 MB, limit at least 2000 MB; CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"

  Write-Host "== 4. the limits are config values"
  Set-Par '"roomMinFreeMB": 1000'
  Run "short"
  Code-Is "roomMinFreeMB 1000" 0
  Expect-Out "roomMinFreeMB 1000" @("room: yes: free memory 1500 MB (at least 1000), CPU 40% (at most 90%)")
  Set-Par '"roomMaxCpuPercent": 100'
  Run "high"
  Code-Is "roomMaxCpuPercent 100" 0
  Expect-Out "roomMaxCpuPercent 100" @("room: yes: free memory 6000 MB (at least 2000), CPU 95% (at most 100%)")
  Set-Par '"roomMinFreeMB": 999999'
  Run "ok"
  Code-Is "roomMinFreeMB 999999" 1
  Has-Line "roomMinFreeMB 999999" "room: waiting for memory: free memory 6000 MB, limit at least 999999 MB (waited 0 of 30 min; next check in 1 s)"
  Set-Par

  Write-Host "== 5. wait, then room"
  Run "short"
  Code-Is "wait" 1
  $n = Get-SinceOf
  if ($null -eq $n) { Fail "wait: no -Since line" }
  Run "ok" "-Since $n"
  Code-Is "then room" 0
  Expect-Out "then room" @($roomOk)

  Write-Host "== 6. the longest wait"
  $now = Get-Now
  Run "short" "-Since $($now - 1700)"
  Code-Is "waited 28" 1
  if (-not $Out.Contains("(waited 28 of 30 min; next check in 1 s)")) { Write-Host $Out; Fail "waited 28: no 'waited 28 of 30 min'" }
  Has-Line "waited 28" "room: call again with -Since $($now - 1700)"
  Set-Parallel '"roomPauseSeconds": 90'
  $now = Get-Now
  Run "short" "-Since $($now - 1800)"
  Code-Is "gave up" 3
  Expect-Out "gave up" @("room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB")
  Quick "gave up"
  Set-Par '"roomMaxWaitMinutes": 1'
  $now = Get-Now
  Run "short" "-Since $($now - 60)"
  Code-Is "gave up after 1 min" 3
  Expect-Out "gave up after 1 min" @("room: gave up after 1 min: free memory 1500 MB, limit at least 2000 MB")
  Set-Par
  $now = Get-Now
  Run "ok" "-Since $($now - 3600)"
  Code-Is "room comes first" 0
  Expect-Out "room comes first" @($roomOk)
  $now = Get-Now
  Run "short" "-Since $($now + 1000)"
  Code-Is "since in the future" 1
  if (-not $Out.Contains("(waited 0 of 30 min;")) { Write-Host $Out; Fail "since in the future: not waited 0" }

  Write-Host "== 7. unavailable is not checked and said"
  Run "cpu-gone"
  Code-Is "cpu-gone" 0
  No-Err "cpu-gone"
  Expect-Out "cpu-gone" @("room: CPU load not checked: unavailable (sample 2 has no CPU reading)",
    "room: yes: free memory 6000 MB (at least 2000), CPU not checked")
  Run "mem-gone"
  Code-Is "mem-gone" 0
  Expect-Out "mem-gone" @("room: free memory not checked: unavailable (sample 1 has no memory reading)",
    "room: yes: free memory not checked, CPU 40% (at most 90%)")
  Run "mem-gone-high"
  Code-Is "mem-gone, CPU high" 1
  Has-Line "mem-gone, CPU high" "room: free memory not checked: unavailable (sample 1 has no memory reading)"
  Has-Line "mem-gone, CPU high" "room: waiting for CPU: CPU 95%, limit at most 90% (waited 0 of 30 min; next check in 1 s)"
  Run "all-gone"
  Code-Is "all-gone" 0
  Expect-Out "all-gone" @("room: free memory not checked: unavailable (sample 1 has no memory reading)",
    "room: CPU load not checked: unavailable (sample 2 has no CPU reading)",
    "room: yes: free memory not checked, CPU not checked")

  Write-Host "== 8. switched off"
  Set-Parallel '"roomCheck": false, "roomPauseSeconds": 90'
  Run "short"
  Code-Is "off" 0
  No-Err "off"
  Expect-Out "off" @("room: not checked (parallel.roomCheck is false)")
  Quick "off"
  Run "missing"
  Code-Is "off, missing fixture" 0
  Expect-Out "off, missing fixture" @("room: not checked (parallel.roomCheck is false)")
  Quick "off, missing fixture"
  Set-Parallel '"roomCheck": true, "roomPauseSeconds": 1'
  Run "ok"
  Code-Is "on" 0
  No-Err "on"
  Expect-Out "on" @($roomOk)

  Write-Host "== 9. unusable config values fall back"
  # Test-BadValue <key> <value> <warning>: on ok, the warning alone on standard error, exit 0, the room line with the defaults
  function Test-BadValue([string]$key, [string]$value, [string]$warning) {
    Set-Parallel "`"$key`": $value"
    Run "ok"
    Code-Is "$key = $value" 0
    Has-Err "$key = $value" $warning
    if (@($script:Err -split "`n" | Where-Object { $_ -ne "" }).Count -ne 1) { Fail "$key = $value`: not one line on standard error: $($script:Err)" }
    Expect-Out "$key = $value" @($roomOk)
  }
  foreach ($v in @("0", "-1", "8.5", '"60"', "true", "91")) {
    Test-BadValue "roomPauseSeconds" $v "room: parallel.roomPauseSeconds must be a whole number from 1 to 90; using 60"
  }
  foreach ($v in @("0", "101")) {
    Test-BadValue "roomMaxCpuPercent" $v "room: parallel.roomMaxCpuPercent must be a whole number from 1 to 100; using 90"
  }
  foreach ($v in @("0", "1000000")) {
    Test-BadValue "roomMinFreeMB" $v "room: parallel.roomMinFreeMB must be a whole number from 1 to 999999; using 2000"
  }
  foreach ($v in @("0", "1441")) {
    Test-BadValue "roomMaxWaitMinutes" $v "room: parallel.roomMaxWaitMinutes must be a whole number from 1 to 1440; using 30"
    Set-Parallel "`"roomMaxWaitMinutes`": $v"
    $now = Get-Now
    Run "short" "-Since $($now - 1800)"
    Code-Is "roomMaxWaitMinutes = $v, gave up" 3
    Expect-Out "roomMaxWaitMinutes = $v, gave up" @("room: gave up after 30 min: free memory 1500 MB, limit at least 2000 MB")
    Quick "roomMaxWaitMinutes = $v, gave up"
  }
  foreach ($v in @('"false"', "0", "1")) {
    Test-BadValue "roomCheck" $v "room: parallel.roomCheck must be true or false; using true"
  }
  Set-Parallel '"roomCheck": null, "roomMinFreeMB": null, "roomMaxCpuPercent": null, "roomPauseSeconds": null, "roomMaxWaitMinutes": null'
  Run "ok"
  Code-Is "null values" 0
  No-Err "null values"
  Expect-Out "null values" @($roomOk)
  Set-Parallel '"maxAgents": 2'
  Run "ok"
  Code-Is "absent keys" 0
  No-Err "absent keys"
  Expect-Out "absent keys" @($roomOk)
  Set-Par

  Write-Host "== 10. errors"
  function Test-Usage([string]$what, [string]$extra) {
    Run "ok" $extra
    Code-Is $what 2
    Has-Err $what "usage: room.ps1 [-Since <seconds>]"
    No-Out $what
  }
  Test-Usage "unknown option" "--nope"
  Test-Usage "-h" "-h"
  Test-Usage "-Since x" "-Since x"
  Test-Usage "-Since 0" "-Since 0"
  Test-Usage "-Since 0123" "-Since 0123"
  Test-Usage "13 digits" "-Since 1234567890123"
  Test-Usage "-Since without a value" "-Since"
  Test-Usage "-Since twice" "-Since 1 -Since 2"
  Run-R $outside (Join-Path $fx "ok") "" @{ GIT_CEILING_DIRECTORIES = $tmp }
  Code-Is "outside a checkout" 2
  Has-Err "outside a checkout" "room: run room.ps1 from inside a checkout of the project"
  Run-R $plain (Join-Path $fx "ok")
  Code-Is "no config" 2
  if (-not $Err.Contains("run /nightmill:init")) { Fail "no config: the message does not say run /nightmill:init: $Err" }
  Run "missing"
  Code-Is "missing fixture" 2
  No-Out "missing fixture"
  Has-Err "missing fixture" "load: cannot read NIGHTMILL_LOAD_FIXTURE: $(Join-Path $fx 'missing')"
  Run "one"
  Code-Is "one sample" 2
  No-Out "one sample"
  Has-Err "one sample" "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"

  Write-Host "== 11. nothing is changed"
  if ([IO.File]::ReadAllText($cfg) -ne $script:Written) { Fail "the config changed" }
  if ((Get-Status) -ne $statusBefore) { Write-Host (Get-Status); Fail "the repository changed" }
  if (@(Get-ChildItem -LiteralPath $tmp -Recurse -Force -Directory -Filter ".slots").Count -ne 0) { Fail "a .slots folder was created" }

  Write-Host "ROOM OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

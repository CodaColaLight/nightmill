# tests/smoke-control.ps1 - control.ps1 against fixtures of readings ($env:NIGHTMILL_LOAD_FIXTURE is set in every call
# that measures, so the real measurement never runs) and a fixed clock ($env:NIGHTMILL_NOW), in a throwaway repository
# whose slot markers and capacity.json are written by hand. The cases 1 to 14 are those of "Tests" in
# docs/specs/iteration-30-load-controller.md; smoke-control.sh runs the same cases.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$C = Join-Path $here "scripts\control.ps1"
$slotPs = Join-Path $here "scripts\slot.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-control-" + [guid]::NewGuid().ToString("N"))
[void][IO.Directory]::CreateDirectory($tmp)
$T = "`t"
$B = 1793966400 # 2026-11-06T12:00:00 read as UTC

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

try {
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  [void][IO.Directory]::CreateDirectory((Join-Path $work ".claude"))
  $slots = Join-Path $tmp "wt\.slots"
  [void][IO.Directory]::CreateDirectory($slots)
  $fx = Join-Path $tmp "fx"
  [void][IO.Directory]::CreateDirectory($fx)
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain
  $outside = Join-Path $tmp "outside"
  [void][IO.Directory]::CreateDirectory($outside)
  $cfg = Join-Path $work ".claude\nightmill.json"
  $capFile = Join-Path $slots "capacity.json"
  $baseCfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "worktrees": { "root": "../wt", "slots": 2 }
}
'@
  $baseCfg = $baseCfg -replace "`r`n", "`n"
  # Set-Parallel <json members>: the config with a parallel object
  function Set-Parallel([string]$members) { Write-Utf8 $cfg $baseCfg.Replace('"worktrees"', "`"parallel`": { $members }, `"worktrees`"") }
  function Set-Apply([string]$extra = "") { if ($extra) { Set-Parallel "`"controlMode`": `"apply`", $extra" } else { Set-Parallel '"controlMode": "apply"' } }
  function Set-ReportOnly([string]$extra = "") { if ($extra) { Set-Parallel "`"controlMode`": `"report`", $extra" } else { Set-Parallel '"controlMode": "report"' } }
  Set-Apply
  function Get-Status { (@(& git -C $work status --porcelain --untracked-files=all) -join "`n") }
  $gitBefore = Get-Status

  $script:MarkersSnap = ""
  function Get-Markers { (@(Get-ChildItem -LiteralPath $slots -Filter "slot-*.json" | Sort-Object Name | ForEach-Object { "== $($_.Name)`n" + [IO.File]::ReadAllText($_.FullName) }) -join "") }
  function Set-Busy([int]$n) {
    Get-ChildItem -LiteralPath $slots -Filter "slot-*.json" | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    for ($i = 1; $i -le $n; $i++) {
      Write-Utf8 (Join-Path $slots "slot-$i.json") "{`n  `"slot`": $i,`n  `"branch`": `"feat/s$i`",`n  `"since`": `"2026-11-05T10:00:00`"`n}`n"
    }
    $script:MarkersSnap = Get-Markers
  }
  # Set-Cap <agents> <slots> [since, or - for none]: capacity.json written by hand
  function Set-Cap([int]$agents, [int]$count, [string]$since = "2026-11-06T12:00:00") {
    if ($since -eq "-") { Write-Utf8 $capFile "{`n  `"slots`": $count,`n  `"maxAgents`": $agents`n}`n" }
    else { Write-Utf8 $capFile "{`n  `"slots`": $count,`n  `"maxAgents`": $agents,`n  `"since`": `"$since`"`n}`n" }
  }
  function Remove-Cap { if (Test-Path -LiteralPath $capFile) { Remove-Item -LiteralPath $capFile } }
  function Get-CapText { if (Test-Path -LiteralPath $capFile) { [IO.File]::ReadAllText($capFile) } else { "absent" } }
  function Save-Cap { $script:CapSnap = Get-CapText }
  function Cap-Same([string]$what) { if ((Get-CapText) -ne $script:CapSnap) { Write-Host (Get-CapText); Fail "$what`: capacity.json changed" } }
  function Cap-Has([string]$what, [string]$key, [int]$value) {
    if (-not (Get-CapText).Contains("`"$key`": $value,")) { Write-Host (Get-CapText); Fail "$what`: capacity.json has no $key $value" }
  }
  function Set-Fixture([string]$name, [string[]]$lines) { Write-Utf8 (Join-Path $fx $name) (($lines -join "`n") + "`n") }
  function Set-Same([string]$name, [string]$line) { Set-Fixture $name @($line, $line, $line) }

  # the slot markers and the files under .slots are what the test wrote
  function Test-Slots([string]$what) {
    if ((Get-Markers) -ne $script:MarkersSnap) { Fail "$what`: a slot marker changed" }
    foreach ($f in @(Get-ChildItem -LiteralPath $slots -Force)) {
      if ($f.Name -ne "capacity.json" -and $f.Name -notmatch '^slot-[0-9]+\.json$') { Fail "$what`: .slots holds another file: $($f.Name)" }
    }
  }

  # Run-Ps <script> <dir> <now or -> <fixture name> [arguments] [extra environment]: a child powershell; Out, Err, Code
  function Run-Ps([string]$script, [string]$dir, [string]$now, [string]$name, [string]$extra = "", [hashtable]$envs = @{}) {
    $before = [IO.File]::ReadAllText($cfg)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables.Remove("WORKER_SLOTS")
    $psi.EnvironmentVariables.Remove("NIGHTMILL_NOW")
    $psi.EnvironmentVariables["NIGHTMILL_LOAD_FIXTURE"] = (Join-Path $fx $name)
    if ($now -ne "-") { $psi.EnvironmentVariables["NIGHTMILL_NOW"] = $now }
    foreach ($k in $envs.Keys) { $psi.EnvironmentVariables[$k] = $envs[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $script:Out = $out -replace "`r`n", "`n"
    $script:Err = $errTask.Result -replace "`r`n", "`n"
    $script:Code = $p.ExitCode
    if ([IO.File]::ReadAllText($cfg) -ne $before) { Fail "the config changed" }
    Test-Slots "run"
  }
  function Run-C([string]$dir, [string]$now, [string]$name, [string]$extra = "", [hashtable]$envs = @{}) { Run-Ps $C $dir $now $name $extra $envs }
  function Run([string]$now, [string]$name, [string]$extra = "") { Run-C $work $now $name $extra }
  function At([long]$n) { return [string]($B + $n) }

  function Expect-Out([string]$what, [string[]]$want) {
    $w = ($want -join "`n") + "`n"
    if ($script:Out -ne $w) { Write-Host "--- expected"; Write-Host $w; Write-Host "--- got"; Write-Host $script:Out; Write-Host "--- stderr"; Write-Host $script:Err; Fail "$what`: the output differs" }
  }
  function First-Is([string]$what, [string]$line) {
    $first = @($script:Out -split "`n")[0]
    if ($first -ne $line) { Write-Host "--- expected"; Write-Host $line; Write-Host "--- got"; Write-Host $script:Out; Write-Host "--- stderr"; Write-Host $script:Err; Fail "$what`: the first line differs" }
  }
  function Has-Err([string]$what, [string]$line) {
    if (@($script:Err -split "`n") -notcontains $line) { Write-Host $script:Err; Fail "$what`: standard error has no line '$line'" }
  }
  function Code-Is([string]$what, [int]$want) {
    if ($script:Code -ne $want) { Write-Host $script:Out; Write-Host $script:Err; Fail "$what`: exit code $($script:Code), expected $want" }
  }
  function No-Err([string]$what) { if ($script:Err) { Write-Host $script:Err; Fail "$what`: something on standard error" } }
  function No-Out([string]$what) { if ($script:Out) { Write-Host $script:Out; Fail "$what`: something on standard output" } }
  function Err-Lines([string]$what, [int]$n) {
    if (@($script:Err -split "`n" | Where-Object { $_ -ne "" }).Count -ne $n) { Write-Host $script:Err; Fail "$what`: not $n line(s) on standard error" }
  }

  Set-Fixture "roomy" @("5 61000 64000", "10 60000 64000", "15 62000 64000")
  Set-Same "steady" "20 9000 16000"
  Set-Same "short" "30 1000 16000"
  Set-Same "cpu-high" "90 50000 64000"
  Set-Fixture "cpu-gone" @("5 61000 64000", "- 60000 64000", "15 62000 64000")
  Set-Fixture "mem-gone" @("5 - 64000", "10 60000 64000", "15 62000 64000")
  Set-Fixture "all-gone" @("5 - 64000", "- 60000 64000", "15 62000 64000")
  Set-Fixture "one" @("10 60000 64000")

  $NEXT = "control: next pass in 5 min (parallel.controlIntervalMinutes)"
  $OFF = "control: off (parallel.controlMode is off); nothing measured or changed"
  $M_ROOMY = "CPU 10%, free memory 60000 of 64000 MB, busy slots 1, suggested 4: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more"
  $M_STEADY = "CPU 20%, free memory 9000 of 16000 MB, busy slots 1, suggested 2: memory is the limit: 16000 MB in all holds 2 agents at 8 GB each"
  $M_SHORT = "CPU 30%, free memory 1000 of 16000 MB, busy slots 2, suggested 1: memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots"
  $M_CPU = "CPU 90%, free memory 50000 of 64000 MB, busy slots 2, suggested 1: CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%"

  Write-Host "== 1. off by default"
  Set-Busy 0
  Write-Utf8 $cfg $baseCfg
  Run "-" "missing"
  Code-Is "no parallel" 0
  Expect-Out "no parallel" @($OFF)
  No-Err "no parallel"
  Set-Parallel '"maxAgents": 2'
  Run "-" "missing"
  Code-Is "no controlMode" 0
  Expect-Out "no controlMode" @($OFF)
  No-Err "no controlMode"
  Set-Parallel '"controlMode": "off"'
  Run "-" "missing"
  Code-Is "off" 0
  Expect-Out "off" @($OFF)
  No-Err "off"
  # no slot script ran: a worktrees root that does not exist is still not there
  $offRepo = Join-Path $tmp "offrepo"
  git init -q -b main $offRepo
  [void][IO.Directory]::CreateDirectory((Join-Path $offRepo ".claude"))
  Write-Utf8 (Join-Path $offRepo ".claude\nightmill.json") $baseCfg.Replace('"../wt"', '"../offwt"')
  Run-C $offRepo "-" "missing"
  Code-Is "off, no root" 0
  Expect-Out "off, no root" @($OFF)
  if (Test-Path -LiteralPath (Join-Path $tmp "offwt")) { Fail "off: the worktrees root was created" }
  Set-Apply

  Write-Host "== 2. raise one step, the slot count keeps up"
  Set-Busy 1
  Remove-Cap
  Run "-" "roomy"
  Code-Is "raise" 0
  Expect-Out "raise" @("control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)", $NEXT)
  Run-Ps $slotPs $work "-" "roomy" "-Capacity -Porcelain"
  $capLines = @($script:Out -split "`n")
  if ($capLines -notcontains "slots${T}3${T}live${T}2") { Write-Host $script:Out; Fail "raise: slots not 3 live" }
  if ($capLines -notcontains "agents${T}3${T}live${T}2") { Write-Host $script:Out; Fail "raise: agents not 3 live" }

  Write-Host "== 3. hold in the cooldown"
  Save-Cap
  Run "-" "roomy"
  Code-Is "right after" 0
  Expect-Out "right after" @("control: agent limit 3 kept (cooldown 15 of 15 min left; $M_ROOMY)", $NEXT)
  Cap-Same "right after"
  Set-Cap 2 2
  Save-Cap
  Run (At 60) "roomy"
  First-Is "B+60" "control: agent limit 2 kept (cooldown 14 of 15 min left; $M_ROOMY)"
  Cap-Same "B+60"
  Run (At 899) "roomy"
  First-Is "B+899" "control: agent limit 2 kept (cooldown 1 of 15 min left; $M_ROOMY)"
  Run (At -60) "roomy"
  First-Is "since in the future" "control: agent limit 2 kept (cooldown 15 of 15 min left; $M_ROOMY)"
  Cap-Same "since in the future"
  Run (At 900) "roomy"
  Code-Is "B+900" 0
  First-Is "B+900" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Set-Cap 2 2
  Run (At 3600) "roomy"
  First-Is "one step per pass" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Cap-Has "one step per pass" "maxAgents" 3
  Set-Apply '"controlCooldownMinutes": 1'
  Set-Cap 2 2
  Run (At 60) "roomy"
  First-Is "cooldown 1 min" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Set-Apply

  Write-Host "== 4. lower at once when memory is short"
  Set-Busy 2
  Set-Cap 3 3
  Run (At 60) "short"
  Code-Is "memory short" 0
  Expect-Out "memory short" @("control: agent limit 3 -> 1 (memory; $M_SHORT)", $NEXT)
  Cap-Has "memory short" "slots" 3
  Cap-Has "memory short" "maxAgents" 1
  Set-Busy 1
  Set-Cap 3 3
  Run (At 60) "steady"
  First-Is "memory total" "control: agent limit 3 -> 2 (memory; $M_STEADY)"

  Write-Host "== 5. lower slowly for the CPU"
  Set-Busy 2
  Set-Cap 3 3
  Save-Cap
  Run (At 60) "cpu-high"
  Code-Is "cpu in the cooldown" 0
  First-Is "cpu in the cooldown" "control: agent limit 3 kept (cooldown 14 of 15 min left; $M_CPU)"
  Cap-Same "cpu in the cooldown"
  Run (At 900) "cpu-high"
  First-Is "cpu after the cooldown" "control: agent limit 3 -> 2 (cpu; $M_CPU)"
  Cap-Has "cpu after the cooldown" "maxAgents" 2
  Set-Busy 1
  Set-Apply '"controlMaxAgents": 6'
  Set-Cap 5 5
  Run (At 3600) "roomy"
  First-Is "ceiling" "control: agent limit 5 -> 4 (ceiling; $M_ROOMY)"
  Set-Apply

  Write-Host "== 6. bounds"
  Set-Apply '"controlMaxAgents": 3'
  Set-Cap 3 3
  Save-Cap
  Run (At 3600) "roomy"
  First-Is "at the maximum" "control: agent limit 3 kept (at the maximum; $M_ROOMY)"
  Cap-Same "at the maximum"
  Set-Apply
  Set-Cap 5 5
  Run (At 60) "steady"
  First-Is "above the maximum, memory" "control: agent limit 5 -> 2 (memory; $M_STEADY)"
  Set-Cap 5 5
  Run (At 60) "roomy"
  First-Is "above the maximum" "control: agent limit 5 -> 4 (maximum; $M_ROOMY)"
  Cap-Has "above the maximum" "slots" 5
  Set-Apply '"controlMinAgents": 2'
  Set-Busy 2
  Set-Cap 3 3
  Run (At 60) "short"
  First-Is "memory to the minimum" "control: agent limit 3 -> 2 (memory; $M_SHORT)"
  Set-Cap 2 3
  Save-Cap
  Run (At 60) "short"
  First-Is "at the minimum" "control: agent limit 2 kept (at the minimum; $M_SHORT)"
  Cap-Same "at the minimum"
  Set-Busy 1
  Set-Cap 1 1
  Run (At 60) "steady"
  First-Is "below the minimum" "control: agent limit 1 -> 2, slots 1 -> 2 (minimum; $M_STEADY)"
  Set-Apply '"controlMinAgents": 5, "controlMaxAgents": 3'
  Remove-Cap
  Run "-" "roomy"
  Code-Is "minimum above maximum" 0
  Has-Err "minimum above maximum" "control: parallel.controlMinAgents 5 is above parallel.controlMaxAgents 3; using 3 for both"
  First-Is "minimum above maximum" "control: agent limit 2 -> 3, slots 2 -> 3 (minimum; $M_ROOMY)"
  Set-Apply

  Write-Host "== 7. steady, and the slot count is raised only by a new limit above it"
  Set-Busy 1
  Remove-Cap
  Run "-" "steady"
  Code-Is "steady" 0
  Expect-Out "steady" @("control: agent limit 2 kept (steady; $M_STEADY)", $NEXT)
  if (Test-Path -LiteralPath $capFile) { Fail "steady: capacity.json was created" }
  Set-Cap 2 1
  Save-Cap
  Run (At 3600) "steady"
  First-Is "kept with L > S" "control: agent limit 2 kept (steady; $M_STEADY)"
  Cap-Same "kept with L > S"
  Set-Cap 3 2
  Save-Cap
  Run (At 60) "roomy"
  First-Is "cooldown with L > S" "control: agent limit 3 kept (cooldown 14 of 15 min left; $M_ROOMY)"
  Cap-Same "cooldown with L > S"
  Set-Cap 2 1
  Run (At 3600) "roomy"
  First-Is "raise above S" "control: agent limit 2 -> 3, slots 1 -> 3 (room; $M_ROOMY)"
  Cap-Has "raise above S" "slots" 3
  Cap-Has "raise above S" "maxAgents" 3
  Set-Cap 2 3
  Run (At 3600) "roomy"
  First-Is "raise within S" "control: agent limit 2 -> 3 (room; $M_ROOMY)"
  Cap-Has "raise within S" "slots" 3
  Set-Busy 2
  Set-Cap 3 2
  Run (At 60) "short"
  First-Is "lower below S" "control: agent limit 3 -> 1 (memory; $M_SHORT)"
  Cap-Has "lower below S" "slots" 2
  Set-Busy 4
  Set-Cap 5 2
  Run (At 60) "short"
  First-Is "lower, still above S" "control: agent limit 5 -> 3, slots 2 -> 3 (memory; CPU 30%, free memory 1000 of 16000 MB, busy slots 4, suggested 3: memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 4 in the slots)"
  Cap-Has "lower, still above S" "slots" 3
  Cap-Has "lower, still above S" "maxAgents" 3

  Write-Host "== 8. a pass that cannot measure changes nothing and says so"
  Set-Busy 1
  Remove-Cap
  Run "-" "cpu-gone"
  Code-Is "cpu gone" 1
  Expect-Out "cpu gone" @("control: agent limit 2 kept (unavailable; the CPU load is unavailable (sample 2 has no CPU reading))", $NEXT)
  if (Test-Path -LiteralPath $capFile) { Fail "cpu gone: capacity.json was created" }
  Run "-" "mem-gone"
  Code-Is "memory gone" 1
  First-Is "memory gone" "control: agent limit 2 kept (unavailable; the free memory is unavailable (sample 1 has no memory reading))"
  Run "-" "all-gone"
  Code-Is "both gone" 1
  First-Is "both gone" "control: agent limit 2 kept (unavailable; the CPU load (sample 2 has no CPU reading) and the free memory (sample 1 has no memory reading) are unavailable)"
  Set-Cap 6 6
  Save-Cap
  Run (At 60) "cpu-gone"
  Code-Is "above the maximum, unavailable" 1
  First-Is "above the maximum, unavailable" "control: agent limit 6 kept (unavailable; the CPU load is unavailable (sample 2 has no CPU reading))"
  Cap-Same "above the maximum, unavailable"

  Write-Host "== 9. report only decides the same and changes nothing"
  # Test-ReportSame: the apply pass and the report pass from the same state give the same exit code and the same lines
  # but the prefix; the report pass leaves capacity.json as it was
  function Set-State([int]$nb, [int]$ca, [int]$cs) { Set-Busy $nb; if ($ca -eq 0) { Remove-Cap } else { Set-Cap $ca $cs } }
  function Test-ReportSame([string]$what, [string]$extra, [int]$nb, [int]$ca, [int]$cs, [string]$now, [string]$name) {
    Set-Apply $extra
    Set-State $nb $ca $cs
    Run $now $name
    $aCode = $script:Code; $aOut = @($script:Out -split "`n")
    Set-State $nb $ca $cs
    Save-Cap
    Set-ReportOnly $extra
    Run $now $name
    Code-Is "report $what" $aCode
    $want = @(("control (report only, nothing changed): " + $aOut[0].Substring("control: ".Length)), $aOut[1])
    Expect-Out "report $what" $want
    if ($aOut[1] -ne $NEXT) { Fail "report $what`: no next-pass line" }
    Cap-Same "report $what"
    Set-Apply
  }
  Test-ReportSame "raise" "" 1 0 0 "-" "roomy"
  Test-ReportSame "memory" "" 2 3 3 (At 60) "short"
  Test-ReportSame "cpu" "" 2 3 3 (At 900) "cpu-high"
  Test-ReportSame "maximum" "" 1 5 5 (At 60) "roomy"
  Test-ReportSame "minimum" '"controlMinAgents": 2' 1 1 1 (At 60) "steady"
  Test-ReportSame "unavailable" "" 1 0 0 "-" "cpu-gone"
  Set-ReportOnly
  Set-Busy 1
  Remove-Cap
  Run "-" "roomy"
  First-Is "report line" "control (report only, nothing changed): agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Set-Apply

  Write-Host "== 10. the last change unknown"
  Set-Busy 1
  Set-Cap 2 2 "-"
  Run (At 60) "roomy"
  First-Is "no since" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Set-Cap 2 2 "yesterday"
  Run (At 60) "roomy"
  First-Is "since yesterday" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"
  Write-Utf8 $capFile "not json`n"
  Run (At 60) "roomy"
  Code-Is "not JSON" 0
  Has-Err "not JSON" "slot: capacity.json: not valid JSON; using the configuration"
  First-Is "not JSON" "control: agent limit 2 -> 3, slots 2 -> 3 (room; $M_ROOMY)"

  Write-Host "== 11. the interval"
  Set-Apply '"controlIntervalMinutes": 10'
  Remove-Cap
  Run "-" "steady"
  Expect-Out "interval" @("control: agent limit 2 kept (steady; $M_STEADY)", "control: next pass in 10 min (parallel.controlIntervalMinutes)")
  Set-Apply

  Write-Host "== 12. unusable config values fall back"
  Set-Busy 1
  Remove-Cap
  foreach ($v in @('"Apply"', '"on"', "1", "true")) {
    Set-Parallel "`"controlMode`": $v"
    Run "-" "steady"
    Code-Is "controlMode $v" 0
    Has-Err "controlMode $v" 'control: parallel.controlMode must be "off", "report" or "apply"; using "off"'
    Err-Lines "controlMode $v" 1
    Expect-Out "controlMode $v" @($OFF)
  }
  function Test-BadValue([string]$key, [string]$value, [int]$def, [int]$high) {
    Set-Apply "`"$key`": $value"
    Run "-" "steady"
    Code-Is "$key = $value" 0
    Has-Err "$key = $value" "control: parallel.$key must be a whole number from 1 to $high; using $def"
    Err-Lines "$key = $value" 1
    Expect-Out "$key = $value" @("control: agent limit 2 kept (steady; $M_STEADY)", $NEXT)
  }
  foreach ($v in @("0", "100")) {
    Test-BadValue "controlMinAgents" $v 1 99
    Test-BadValue "controlMaxAgents" $v 4 99
  }
  foreach ($v in @("0", "1441", "1.5", '"15"')) { Test-BadValue "controlCooldownMinutes" $v 15 1440 }
  foreach ($v in @("0", "1441", '"5"')) { Test-BadValue "controlIntervalMinutes" $v 5 1440 }
  Set-Apply '"controlCooldownMinutes": 0'
  Set-Cap 2 2
  Run (At 60) "roomy"
  First-Is "cooldown default" "control: agent limit 2 kept (cooldown 14 of 15 min left; $M_ROOMY)"
  Remove-Cap
  Set-Apply '"controlMinAgents": null, "controlMaxAgents": null, "controlCooldownMinutes": null, "controlIntervalMinutes": null'
  Run "-" "steady"
  Code-Is "null values" 0
  No-Err "null values"
  Set-Parallel '"controlMode": null'
  Run "-" "steady"
  No-Err "null mode"
  Expect-Out "null mode" @($OFF)
  Set-Apply
  Run "-" "steady"
  No-Err "absent keys"

  Write-Host "== 13. errors"
  Set-Cap 2 2
  Save-Cap
  Run "-" "roomy" "--apply"
  Code-Is "--apply" 2
  Has-Err "--apply" "usage: control.ps1"
  Run "-" "roomy" "-h"
  Code-Is "-h" 2
  Has-Err "-h" "usage: control.ps1"
  Run-C $outside "-" "roomy" "" @{ GIT_CEILING_DIRECTORIES = $tmp }
  Code-Is "outside a checkout" 2
  Has-Err "outside a checkout" "control: run control.ps1 from inside a checkout of the project"
  Run-C $plain "-" "roomy"
  Code-Is "no config" 2
  if (-not $Err.Contains("run /nightmill:init")) { Fail "no config: the message does not say run /nightmill:init: $Err" }
  Run "-" "missing"
  Code-Is "missing fixture" 2
  No-Out "missing fixture"
  Has-Err "missing fixture" "load: cannot read NIGHTMILL_LOAD_FIXTURE: $(Join-Path $fx 'missing')"
  Run "-" "one"
  Code-Is "one sample" 2
  No-Out "one sample"
  Has-Err "one sample" "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"
  Run-C $work "-" "roomy" "" @{ WORKER_SLOTS = "x" }
  Code-Is "WORKER_SLOTS" 2
  No-Out "WORKER_SLOTS"
  Has-Err "WORKER_SLOTS" "control: slot.ps1 failed: WORKER_SLOTS must be a number from 1 to 99"
  Cap-Same "errors"

  Write-Host "== 14. nothing else is changed"
  Test-Slots "at the end"
  if ((Get-Status) -ne $gitBefore) { Fail "the throwaway repository's git status changed" }

  Write-Host "CONTROL OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

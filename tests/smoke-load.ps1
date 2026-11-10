# tests/smoke-load.ps1 - load.ps1 against fixtures of readings ($env:NIGHTMILL_LOAD_FIXTURE is set in every call, so
# the real measurement never runs and the result does not depend on this machine), in a throwaway repository whose slot
# markers and capacity.json are written by hand. The scenarios a to i are those of "The suggestion" in
# docs/specs/iteration-24-machine-load.md; smoke-load.sh runs the same cases.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$L = Join-Path $here "scripts\load.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-load-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$T = "`t"

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

try {
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  New-Item -ItemType Directory (Join-Path $work ".claude") | Out-Null
  $slots = Join-Path $tmp "wt\.slots"
  New-Item -ItemType Directory $slots | Out-Null
  $fx = Join-Path $tmp "fx"
  New-Item -ItemType Directory $fx | Out-Null
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain
  $outside = Join-Path $tmp "outside"
  New-Item -ItemType Directory $outside | Out-Null
  $cfg = Join-Path $work ".claude\nightmill.json"
  $baseCfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "worktrees": { "root": "../wt", "slots": 2 }
}
'@
  $baseCfg = $baseCfg -replace "`r`n", "`n"
  Write-Utf8 $cfg $baseCfg
  function Set-Parallel([string]$members) { Write-Utf8 $cfg $baseCfg.Replace('"worktrees"', "`"parallel`": { $members }, `"worktrees`"") }

  function Set-Busy([int]$n) {
    Get-ChildItem -LiteralPath $slots -Filter "slot-*.json" | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    for ($i = 1; $i -le $n; $i++) {
      Write-Utf8 (Join-Path $slots "slot-$i.json") "{`n  `"slot`": $i,`n  `"branch`": `"feat/s$i`",`n  `"since`": `"2026-11-05T10:00:00`"`n}`n"
    }
  }
  function Set-Fixture([string]$name, [string[]]$lines) { Write-Utf8 (Join-Path $fx $name) (($lines -join "`n") + "`n") }
  function Set-Same([string]$name, [string]$line) { Set-Fixture $name @($line, $line, $line) }

  # Base-Sync <dir> (iteration 48): slot.ps1 reads the config on origin/HEAD, not the working tree's file, so before a
  # run origin/HEAD of the test repository is made to hold the working tree's config: a commit of that one file, built
  # with a temporary index and no remote (refs/remotes/origin/main and origin/HEAD are set directly). Without the file
  # nothing changes.
  function Base-Sync([string]$dir) {
    $f = Join-Path $dir ".claude\nightmill.json"
    if (-not (Test-Path -LiteralPath $f)) { return }
    $idx = Join-Path $dir ".git\nightmill-base-sync.index"
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $prevIdx = $env:GIT_INDEX_FILE
    try {
      Remove-Item -LiteralPath $idx -Force -ErrorAction SilentlyContinue
      $blob = ((& git -C $dir hash-object -w -- $f 2>$null) | Out-String).Trim()
      $env:GIT_INDEX_FILE = $idx
      & git -C $dir update-index --add --cacheinfo "100644,$blob,.claude/nightmill.json" 2>$null | Out-Null
      $tree = ((& git -C $dir write-tree 2>$null) | Out-String).Trim()
      $env:GIT_INDEX_FILE = $prevIdx
      $commit = ((& git -C $dir -c user.name=t -c user.email=t@example.invalid commit-tree -m base $tree 2>$null) | Out-String).Trim()
      & git -C $dir update-ref refs/remotes/origin/main $commit 2>$null | Out-Null
      & git -C $dir symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>$null | Out-Null
    } finally {
      $env:GIT_INDEX_FILE = $prevIdx
      Remove-Item -LiteralPath $idx -Force -ErrorAction SilentlyContinue
      $ErrorActionPreference = $eap
    }
  }
  # Run-L <dir> <fixture name> [arguments] [extra environment]: run load.ps1 in a child powershell; Out, Err, Code
  function Run-L([string]$dir, [string]$name, [string]$extra = "", [hashtable]$envs = @{}) {
    Base-Sync $dir
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$L`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["NIGHTMILL_LOAD_FIXTURE"] = (Join-Path $fx $name)
    $psi.EnvironmentVariables.Remove("WORKER_SLOTS")
    foreach ($k in $envs.Keys) { $psi.EnvironmentVariables[$k] = $envs[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $script:Out = $out -replace "`r`n", "`n"
    $script:Err = $errTask.Result -replace "`r`n", "`n"
    $script:Code = $p.ExitCode
  }
  function Run([string]$name, [string]$extra = "") { Run-L $work $name $extra }

  function Expect-Out([string]$what, [string[]]$want) {
    $w = ($want -join "`n") + "`n"
    if ($script:Out -ne $w) { Write-Host "--- expected"; Write-Host $w; Write-Host "--- got"; Write-Host $script:Out; Write-Host "--- stderr"; Write-Host $script:Err; Fail "$what`: the output differs" }
  }
  function Has-Line([string]$what, [string]$line) {
    if (@($script:Out -split "`n") -notcontains $line) { Write-Host $script:Out; Fail "$what`: no line '$line'" }
  }
  function Has-Err([string]$what, [string]$line) {
    if (@($script:Err -split "`n") -notcontains $line) { Write-Host $script:Err; Fail "$what`: standard error has no line '$line'" }
  }
  function Code-Is([string]$what, [int]$want) {
    if ($script:Code -ne $want) { Write-Host $script:Out; Write-Host $script:Err; Fail "$what`: exit code $($script:Code), expected $want" }
  }
  function No-Err([string]$what) { if ($script:Err) { Write-Host $script:Err; Fail "$what`: something on standard error" } }

  Set-Fixture "a" @("5 61000 64000", "10 60000 64000", "15 62000 64000")
  Set-Same "b" "20 9000 16000"
  Set-Same "c" "20 9000 32000"
  Set-Same "d" "30 1000 16000"
  Set-Same "e" "90 50000 64000"
  Set-Same "f" "85 50000 64000"
  Set-Same "g" "100 50000 64000"
  Set-Same "i" "5 12000 16000"

  Write-Host "== every value is printed (scenario a)"
  Set-Busy 1
  Run "a"
  Code-Is "human form" 0
  Expect-Out "human form" @(
    "cpu: 10% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)",
    "memory: 60000 MB free of 64000 MB (lowest of 3 samples)",
    "agent limit: 2 (default)",
    "slots: 1 of 2 in use",
    "agents running: 1 (counted from the busy slots)",
    "suggested agent limit: 4 (now 2: raise)",
    "why: the ceiling is the limit (parallel.maxSuggestedAgents = 4); CPU and memory have room for more")

  Write-Host "== porcelain (scenario a)"
  Run "a" "-Porcelain"
  Code-Is "porcelain" 0
  No-Err "porcelain"
  Expect-Out "porcelain" @("cpu${T}10", "memory-free${T}60000", "memory-total${T}64000", "window${T}3${T}fixture",
    "agent-limit${T}2${T}default", "slot-count${T}2", "slots-busy${T}1", "agents-running${T}1", "memory-per-agent${T}8",
    "ceiling${T}4", "suggested${T}4${T}raise${T}ceiling")

  Write-Host "== the window is used, not one reading"
  # the last sample alone (CPU 100) would give 1; the mean of the window (40) gives 2
  Set-Fixture "window" @("10 61000 64000", "10 60000 64000", "100 62000 64000")
  Run "window"
  Code-Is "window" 0
  Has-Line "window" "cpu: 40% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)"
  Has-Line "window" "memory: 60000 MB free of 64000 MB (lowest of 3 samples)"
  Has-Line "window" "suggested agent limit: 2 (now 2: keep)"
  Has-Line "window" "why: CPU is the limit: 40% busy with 1 agents in the slots, aiming at 80%"
  Set-Fixture "half" @("10 61000 64000", "11 60000 64000")
  Run "half" "-Porcelain"
  Has-Line "rounding" "cpu${T}11"

  Write-Host "== the suggestion and its reason (scenarios b to g and i)"
  function Test-Scenario([string]$name, [int]$busy, [string]$p, [string]$dir, [string]$key, [string]$why) {
    Set-Busy $busy
    Run $name
    Code-Is "scenario $name" 0
    Has-Line "scenario $name" "suggested agent limit: $p (now 2: $dir)"
    Has-Line "scenario $name" "why: $why"
    Run $name "-Porcelain"
    Code-Is "scenario $name porcelain" 0
    Has-Line "scenario $name porcelain" "suggested${T}$p${T}$dir${T}$key"
  }
  Test-Scenario "b" 1 2 "keep" "memory-total" "memory is the limit: 16000 MB in all holds 2 agents at 8 GB each"
  Test-Scenario "c" 1 2 "keep" "memory-free" "memory is the limit: 9000 MB free holds 1 more agents at 8 GB each beside the 1 in the slots"
  Test-Scenario "d" 2 1 "lower" "memory-short" "memory is short: 1000 MB free is under 10% of 16000 MB, one agent fewer than the 2 in the slots"
  Test-Scenario "e" 2 1 "lower" "cpu" "CPU is the limit: 90% busy with 2 agents in the slots, aiming at 80%"
  Test-Scenario "f" 0 1 "lower" "cpu-other" "CPU is the limit: 85% busy with no slot in use"
  Test-Scenario "g" 1 1 "lower" "cpu" "CPU is the limit: 100% busy with 1 agents in the slots, aiming at 80%"
  Test-Scenario "i" 0 1 "lower" "memory-free" "memory is the limit: 12000 MB free holds 1 more agents at 8 GB each beside the 0 in the slots"

  Write-Host "== floor and ceiling"
  Set-Busy 1
  Set-Parallel '"memoryPerAgentGB": 4, "maxSuggestedAgents": 6'
  Run "a"
  Code-Is "scenario h" 0
  No-Err "scenario h"
  Has-Line "scenario h" "suggested agent limit: 6 (now 2: raise)"
  Has-Line "scenario h" "why: the ceiling is the limit (parallel.maxSuggestedAgents = 6); CPU and memory have room for more"
  Run "a" "-Porcelain"
  Has-Line "scenario h porcelain" "memory-per-agent${T}4"
  Has-Line "scenario h porcelain" "ceiling${T}6"
  Has-Line "scenario h porcelain" "suggested${T}6${T}raise${T}ceiling"

  Write-Host "== unusable config values fall back to the default"
  function Test-BadValue([string]$key, [string]$value, [int]$def, [int]$low, [int]$high) {
    Set-Parallel "`"$key`": $value"
    Run "a" "-Porcelain"
    Code-Is "$key = $value" 0
    Has-Err "$key = $value" "load: parallel.$key must be a whole number from $low to $high; using $def"
    if (@($script:Err -split "`n" | Where-Object { $_ -ne "" }).Count -ne 1) { Fail "$key = $value`: more than one line on standard error: $($script:Err)" }
  }
  foreach ($v in @("0", "-1", "8.5", "8.0", '"8"', "true")) {
    Test-BadValue "memoryPerAgentGB" $v 8 1 1024
    Has-Line "memoryPerAgentGB = $v" "memory-per-agent${T}8"
  }
  foreach ($v in @("0", "100")) {
    Test-BadValue "maxSuggestedAgents" $v 4 1 99
    Has-Line "maxSuggestedAgents = $v" "ceiling${T}4"
  }
  foreach ($v in @("1", "61")) { Test-BadValue "loadWindowSeconds" $v 10 2 60 }
  Set-Parallel '"memoryPerAgentGB": null, "maxSuggestedAgents": null, "loadWindowSeconds": null'
  Run "a" "-Porcelain"
  Code-Is "null values" 0
  No-Err "null values"
  Has-Line "null values" "memory-per-agent${T}8"
  Set-Parallel '"maxAgents": 2'
  Run "a" "-Porcelain"
  No-Err "absent keys"
  Write-Utf8 $cfg $baseCfg

  Write-Host "== the agent limit and the slots come from the slot script"
  Set-Busy 1
  $capFile = Join-Path $slots "capacity.json"
  Write-Utf8 $capFile "{`n  `"maxAgents`": 3,`n  `"since`": `"2026-11-05T11:00:00`"`n}`n"
  Run "a"
  Has-Line "live limit" "agent limit: 3 (live; config 2)"
  Has-Line "live limit" "suggested agent limit: 4 (now 3: raise)"
  Run "a" "-Porcelain"
  Has-Line "live limit porcelain" "agent-limit${T}3${T}live"
  Remove-Item -LiteralPath $capFile
  Set-Parallel '"maxAgents": 5'
  Run "a"
  Has-Line "config limit" "agent limit: 5 (config)"
  Has-Line "config limit" "suggested agent limit: 4 (now 5: lower)"
  Write-Utf8 $cfg $baseCfg
  Set-Busy 2
  Write-Utf8 $capFile "{`n  `"slots`": 1,`n  `"since`": `"2026-11-05T11:00:00`"`n}`n"
  Run "a"
  Has-Line "retiring slot" "slots: 2 of 1 in use"
  Has-Line "retiring slot" "agents running: 2 (counted from the busy slots)"
  Run "a" "-Porcelain"
  Has-Line "retiring slot porcelain" "slot-count${T}1"
  Has-Line "retiring slot porcelain" "slots-busy${T}2"
  Has-Line "retiring slot porcelain" "agents-running${T}2"

  Write-Host "== nothing is changed"
  function Get-State { ([IO.File]::ReadAllText($cfg)) + (@(Get-ChildItem -LiteralPath $slots -Force | Sort-Object Name | ForEach-Object { "== $($_.Name)`n" + [IO.File]::ReadAllText($_.FullName) }) -join "") }
  $before = Get-State
  Run "a"
  Run "a" "-Porcelain"
  Run "nope"
  if ((Get-State) -ne $before) { Fail "a file of the project changed" }
  $names = (@(Get-ChildItem -LiteralPath $slots -Force | Sort-Object Name | ForEach-Object { $_.Name }) -join " ")
  if ($names -ne "capacity.json slot-1.json slot-2.json") { Fail ".slots holds other files: $names" }
  Remove-Item -LiteralPath $capFile

  Write-Host "== an unavailable CPU is reported, never guessed"
  Set-Busy 1
  Set-Fixture "nocpu" @("10 61000 64000", "- 60000 64000", "15 62000 64000")
  Run "nocpu"
  Code-Is "no CPU" 1
  Expect-Out "no CPU" @(
    "cpu: unavailable (sample 2 has no CPU reading)",
    "memory: 60000 MB free of 64000 MB (lowest of 3 samples)",
    "agent limit: 2 (default)",
    "slots: 1 of 2 in use",
    "agents running: 1 (counted from the busy slots)",
    "suggested agent limit: none (the CPU load is unavailable)")
  Run "nocpu" "-Porcelain"
  Code-Is "no CPU porcelain" 1
  Expect-Out "no CPU porcelain" @("cpu${T}unavailable${T}sample 2 has no CPU reading", "memory-free${T}60000", "memory-total${T}64000",
    "window${T}3${T}fixture", "agent-limit${T}2${T}default", "slot-count${T}2", "slots-busy${T}1", "agents-running${T}1",
    "memory-per-agent${T}8", "ceiling${T}4", "suggested${T}none${T}unavailable")

  Write-Host "== an unavailable memory reading, and both"
  Set-Fixture "nomem" @("10 - 64000", "10 60000 64000", "15 62000 -")
  Run "nomem"
  Code-Is "no memory" 1
  Has-Line "no memory" "cpu: 12% busy (mean of 3 samples from NIGHTMILL_LOAD_FIXTURE)"
  Has-Line "no memory" "memory: unavailable (sample 1 has no memory reading)"
  Has-Line "no memory" "suggested agent limit: none (the free memory is unavailable)"
  if ($Out -match "(?m)^why:") { Fail "no memory: a why line without a suggestion" }
  Run "nomem" "-Porcelain"
  Code-Is "no memory porcelain" 1
  Has-Line "no memory porcelain" "memory-free${T}unavailable${T}sample 1 has no memory reading"
  Has-Line "no memory porcelain" "memory-total${T}unavailable${T}sample 1 has no memory reading"
  Has-Line "no memory porcelain" "suggested${T}none${T}unavailable"
  if (@($Out -split "`n" | Where-Object { $_ -ne "" }).Count -ne 11) { Fail "no memory porcelain: not eleven lines" }
  Set-Fixture "neither" @("10 60000 64000", "- 60000 -", "- - 64000")
  Run "neither"
  Code-Is "neither" 1
  Has-Line "neither" "cpu: unavailable (sample 2 has no CPU reading)"
  Has-Line "neither" "memory: unavailable (sample 2 has no memory reading)"
  Has-Line "neither" "suggested agent limit: none (the CPU load and the free memory are unavailable)"

  Write-Host "== an unusable fixture stops the command"
  function Test-Unusable([string]$name, [string]$msg) {
    Run $name
    Code-Is "fixture $name" 2
    if ($script:Out) { Write-Host $script:Out; Fail "fixture $name`: something on standard output" }
    Has-Err "fixture $name" $msg
  }
  Test-Unusable "missing" "load: cannot read NIGHTMILL_LOAD_FIXTURE: $(Join-Path $fx 'missing')"
  Set-Fixture "one" @("10 60000 64000")
  Test-Unusable "one" "load: NIGHTMILL_LOAD_FIXTURE needs at least 2 samples"
  Set-Fixture "two" @("# a comment", "", "10 60000 64000", "10 60000")
  Test-Unusable "two" 'load: NIGHTMILL_LOAD_FIXTURE line 4 is not "<cpu> <free MB> <total MB>"'
  Set-Fixture "cpux" @("10 60000 64000", "x 60000 64000")
  Test-Unusable "cpux" 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'
  Set-Fixture "cpu101" @("101 60000 64000", "10 60000 64000")
  Test-Unusable "cpu101" 'load: NIGHTMILL_LOAD_FIXTURE line 1 is not "<cpu> <free MB> <total MB>"'
  Set-Fixture "freeneg" @("10 60000 64000", "10 -5 64000")
  Test-Unusable "freeneg" 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'
  Set-Fixture "total0" @("10 60000 64000", "10 60000 0")
  Test-Unusable "total0" 'load: NIGHTMILL_LOAD_FIXTURE line 2 is not "<cpu> <free MB> <total MB>"'
  Set-Fixture "comments" @("# readings", "", "5 61000 64000", "# between", "10 60000 64000", "15 62000 64000")
  Run "comments" "-Porcelain"
  Code-Is "comment and empty lines" 0
  Has-Line "comment and empty lines" "window${T}3${T}fixture"

  Write-Host "== usage and project errors"
  Run "a" "--nope"
  Code-Is "unknown option" 2
  Has-Err "unknown option" "usage: load.ps1 [-Porcelain]"
  Run "a" "-h"
  Code-Is "-h" 2
  Run-L $outside "a" "" @{ GIT_CEILING_DIRECTORIES = $tmp }
  Code-Is "outside a checkout" 2
  Has-Err "outside a checkout" "load: run load.ps1 from inside a checkout of the project"
  Run-L $plain "a"
  Code-Is "no config" 2
  if (-not $Err.Contains("run /nightmill:init")) { Fail "no config: the message does not say run /nightmill:init: $Err" }

  Write-Host "== a failed slot script stops the command with its standard error on one line"
  # a copy of load.ps1 and its lib beside a stub slot.ps1 that writes two lines to standard error and exits 3
  $stub = Join-Path $tmp "stub"
  New-Item -ItemType Directory $stub | Out-Null
  Copy-Item -LiteralPath $L -Destination $stub
  Copy-Item -LiteralPath (Join-Path $here "scripts\lib") -Destination $stub -Recurse
  Write-Utf8 (Join-Path $stub "slot.ps1") "[Console]::Error.WriteLine('stub: the slots are unreadable')`n[Console]::Error.WriteLine('stub: second line')`nexit 3`n"
  $realL = $L
  $L = Join-Path $stub "load.ps1"
  Run "a"
  $L = $realL
  Code-Is "failed slot script" 2
  if ($Out) { Write-Host $Out; Fail "failed slot script: something on standard output" }
  if ($Err -ne "load: slot.ps1 failed: stub: the slots are unreadable stub: second line`n") { Fail "failed slot script: standard error is '$Err'" }

  Write-Host "LOAD OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

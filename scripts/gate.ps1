# scripts/gate.ps1 - may the next step start? The pause flag and the limits of a run (nightmill, iteration 53, #165).
# PowerShell twin of gate.sh; the rules and the texts are in docs/specs/iteration-53-run-limits.md (decision 3).
#
#   gate.ps1 [-Issue <n>] [-Slot <s>] [-Role <role> -Turns <t>]
#   gate.ps1 -h | --help
#
# Run it from inside any checkout of the project. It reads the base branch's .claude/nightmill.json
# (scripts/lib/baseconfig.ps1; limits, github.owner, github.repo, worktrees.root), the record
# <worktrees.root>\.slots\ledger.tsv, the clock (lib/ledger.ps1; NIGHTMILL_CLOCK_FILE moves it in the tests), the
# environment variables NIGHTMILL_RUN_STARTED (seconds since 1970: the start of the driver's step) and
# NIGHTMILL_ISSUES_LEFT (the issues the driver run may still start), and with -Issue one gh api graphql query (the
# issue's epic and its labels). It writes nothing, fetches nothing and changes nothing on GitHub.
# The checks, in this order; the first that holds prints its line and exits:
#   the config and its limits values (exit 2), limits.paused (exit 1), with -Issue the label paused on the epic
#   (exit 4), the cost of the issue over the run lines of the ledger, its minutes in this run (exit 3), with -Role
#   the turns of the role (exit 3); else the lines "gate: issues per run: <k>", with -Issue
#   "gate: spent on #<n>: $<x> of $<l>", and "gate: go".
# Exit code 0 go, 1 the project is paused, 2 cannot check (also a usage error), 3 a limit is breached, 4 the issue's
# epic is paused.
# The arguments are parsed here (no typed param binding), so -Issue x is a usage error with the usage line too.
$ErrorActionPreference = "Stop"

$usage = "usage: gate.ps1 [-Issue <n>] [-Slot <s>] [-Role <role> -Turns <t>]"
function Write-Line([string]$line) { [Console]::Out.Write($line + "`n") }
function Stop-Usage { [Console]::Error.WriteLine($usage); exit 2 }
function Stop-Cannot([string]$msg) { [Console]::Error.WriteLine("gate: cannot check: $msg"); exit 2 }

$issue = ""; $slot = ""; $role = ""; $turns = ""
$rest = @($args)
for ($i = 0; $i -lt $rest.Count; $i++) {
  $a = [string]$rest[$i]
  if ($a -eq "-h" -or $a -eq "--help" -or $a -eq "-Help") { Write-Line $usage; exit 0 }
  if ($a -eq "-Issue" -or $a -eq "-Slot" -or $a -eq "-Turns") {
    if ($i + 1 -ge $rest.Count) { Stop-Usage }
    $v = [string]$rest[$i + 1]
    if ($v -cnotmatch '^[1-9][0-9]{0,9}$') { Stop-Usage }
    if ($a -eq "-Issue") { if ($issue) { Stop-Usage }; $issue = $v }
    elseif ($a -eq "-Slot") { if ($slot) { Stop-Usage }; $slot = $v }
    else { if ($turns) { Stop-Usage }; $turns = $v }
    $i++
  } elseif ($a -eq "-Role") {
    if ($i + 1 -ge $rest.Count) { Stop-Usage }
    $v = [string]$rest[$i + 1]
    if ($v -cnotmatch '^[A-Za-z][A-Za-z0-9]{0,39}$' -or $role) { Stop-Usage }
    $role = $v
    $i++
  } else {
    Stop-Usage
  }
}
if (($role -and -not $turns) -or ($turns -and -not $role)) { Stop-Usage }

. (Join-Path $PSScriptRoot "lib\baseconfig.ps1")
. (Join-Path $PSScriptRoot "lib\ledger.ps1")

$inv = [Globalization.CultureInfo]::InvariantCulture
function One-Line([string]$s) {
  if ($null -eq $s) { return "" }
  return (($s -replace "[`r`n]+", " ") -replace " +", " ").Trim()
}
function Format-Money([double]$x) { return [string]::Format($inv, "{0:0.00}", $x) }

# --- 1. the config ---
$gitDir = $null
$eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { $gitDir = & git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
$gitCode = $LASTEXITCODE
$ErrorActionPreference = $eap
if ($gitCode -ne 0 -or -not $gitDir) { Stop-Cannot "run gate.ps1 from inside a git checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$bc = Get-BaseConfig $main
if ($bc.Stop) { Stop-Cannot $bc.Stop }
if ($bc.Note) { [Console]::Error.WriteLine($bc.Note) }
$cfgText = $bc.Text
if ($null -eq $cfgText) {
  if (-not (Test-Path -LiteralPath $bc.Path -PathType Leaf)) { Stop-Cannot "no $($bc.Path) (run /nightmill:init)" }
  $cfgText = [IO.File]::ReadAllText($bc.Path).TrimStart([char]0xFEFF)
}
try { $cfg = ConvertFrom-Json -InputObject $cfgText } catch { Stop-Cannot "$($bc.From) is not valid JSON: $(One-Line $_.Exception.Message)" }

function Has-Key($obj, [string]$k) {
  return ($null -ne $obj -and $obj -is [System.Management.Automation.PSCustomObject] -and $null -ne $obj.PSObject.Properties[$k])
}
function Get-Shown($v) {
  if ($null -eq $v) { return "null" }
  if ($v -is [string]) { return (ConvertTo-Json -InputObject $v -Compress) }
  if ($v -is [bool]) { if ($v) { return "true" } else { return "false" } }
  if ($v -is [array]) { return "[...]" }
  if ($v -is [System.Management.Automation.PSCustomObject]) { return "{...}" }
  return [Convert]::ToString($v, $inv)
}
function Test-Number($v) {
  return ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or $v -is [single])
}
$lim = $null
if (Has-Key $cfg "limits") { $lim = $cfg.limits }
# Get-Whole <object> <key> <shown key> <lo> <hi> <default>: a whole number in range, or the stop of decision 2
function Get-Whole($obj, [string]$key, [string]$name, [long]$lo, [long]$hi, [long]$default) {
  if (-not (Has-Key $obj $key)) { return $default }
  $v = $obj.PSObject.Properties[$key].Value
  if (($v -is [int] -or $v -is [long]) -and [long]$v -ge $lo -and [long]$v -le $hi) { return [long]$v }
  Stop-Cannot "limits.$name must be a whole number from $lo to $hi, got $(Get-Shown $v)"
}

# --- 2. the values ---
$paused = $false
if (Has-Key $lim "paused") {
  $v = $lim.paused
  if (-not ($v -is [bool])) { Stop-Cannot "limits.paused must be true or false, got $(Get-Shown $v)" }
  $paused = $v
}
$minutes = Get-Whole $lim "minutesPerIssue" "minutesPerIssue" 1 1440 180
$defaults = [ordered]@{ session = 200; specWriter = 150; specReviewer = 80; tester = 150; implementer = 300; codeReviewer = 80; fixer = 200; worker = 40 }
$tpr = $null
if (Has-Key $lim "turnsPerRole") { $tpr = $lim.turnsPerRole }
$roleLimit = $null
foreach ($rl in $defaults.Keys) {
  $v = Get-Whole $tpr $rl "turnsPerRole.$rl" 1 10000 $defaults[$rl]
  if ($rl -ceq $role) { $roleLimit = $v }
}
$perRun = Get-Whole $lim "issuesPerRun" "issuesPerRun" 1 100 10
$cost = [double]25
if (Has-Key $lim "costPerIssueUsd") {
  $v = $lim.costPerIssueUsd
  if ((Test-Number $v) -and [double]$v -ge 0.01 -and [double]$v -le 10000) { $cost = [double]$v }
  else { Stop-Cannot "limits.costPerIssueUsd must be a number from 0.01 to 10000, got $(Get-Shown $v)" }
}

# --- 3. the project pause ---
if ($paused) { Write-Line "gate: paused: limits.paused is true on $($bc.From)"; exit 1 }

$owner = ""; $repo = ""
if (Has-Key $cfg "github") {
  if (Has-Key $cfg.github "owner") { $owner = [string]$cfg.github.owner }
  if (Has-Key $cfg.github "repo") { $repo = [string]$cfg.github.repo }
}
$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
if ((Has-Key $cfg "worktrees") -and (Has-Key $cfg.worktrees "root") -and $cfg.worktrees.root) { $rootRel = [string]$cfg.worktrees.root }
$root = [System.IO.Path]::GetFullPath((Join-Path $main $rootRel))
$record = Join-Path $root ".slots\ledger.tsv"
$lines = @()
if (Test-Path -LiteralPath $record -PathType Leaf) {
  try { $lines = @(([IO.File]::ReadAllText($record)) -split "`n") } catch { $lines = @() }
}
$spent = [double]0

if ($issue) {
  # --- 4. the epic pause ---
  if (-not $owner -or -not $repo) { Stop-Cannot "the epic of #$issue could not be read: github.owner and github.repo are needed in $($bc.From)" }
  $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $gh) { Stop-Cannot "the epic of #${issue} could not be read: gh is not on the PATH" }
  $q = "query { repository(owner: \`"$owner\`", name: \`"$repo\`") { issue(number: $issue) { parent { number labels(first: 100) { nodes { name } } } } } }"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = [string]$gh.Path
  $psi.Arguments = "api graphql -f `"query=$q`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  try {
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $gout = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $gerr = $errTask.Result
    $gcode = $p.ExitCode
  } catch { $gout = ""; $gerr = $_.Exception.Message; $gcode = -1 }
  if ($gcode -ne 0) {
    $why = One-Line $gerr
    if (-not $why) { $why = "gh api graphql failed" }
    Stop-Cannot "the epic of #$issue could not be read: $why"
  }
  try { $doc = ConvertFrom-Json -InputObject $gout } catch { Stop-Cannot "the epic of #$issue could not be read: gh api graphql gave no valid JSON" }
  $parent = $null
  if ($null -ne $doc -and $doc.data -and $doc.data.repository -and $doc.data.repository.issue) { $parent = $doc.data.repository.issue.parent }
  if ($null -ne $parent -and $null -ne $parent.number) {
    $names = @()
    if ($parent.labels -and $parent.labels.nodes) { $names = @($parent.labels.nodes | ForEach-Object { [string]$_.name }) }
    if ($names -ccontains "paused") { Write-Line "gate: paused: epic #$($parent.number) has the label paused"; exit 4 }
  }

  # --- 5. the cost per issue ---
  foreach ($l in $lines) {
    $f = @($l.TrimEnd("`r") -split "`t")
    if ($f.Count -lt 6 -or $f[0] -cne "run" -or -not $f[5]) { continue }
    $ids = @($f[5] -split ",")
    if ($ids -notcontains $issue) { continue }
    $c = [double]0
    if ($f.Count -ge 10) { [void][double]::TryParse($f[9], [Globalization.NumberStyles]::Float, $inv, [ref]$c) }
    $spent += $c / $ids.Count
  }
  if ($spent -ge $cost - 0.0000001) {
    Write-Line ("gate: limit: #$issue has spent `$" + (Format-Money $spent) + " in headless runs; the limit is `$" + (Format-Money $cost) + " (limits.costPerIssueUsd)")
    exit 3
  }

  # --- 6. the minutes per issue ---
  $start = $null
  if ($slot) {
    $claim = ""
    foreach ($l in $lines) {
      $f = @($l.TrimEnd("`r") -split "`t")
      if ($f.Count -ge 9 -and $f[0] -ceq "take" -and $f[2] -ceq $slot -and $f[8] -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}') { $claim = $f[8] }
    }
    if ($claim) { $start = Get-LedgerEpoch $claim }
  }
  $rs = [string]$env:NIGHTMILL_RUN_STARTED
  if ($rs -cmatch '^[0-9]{1,12}$') {
    $rsv = [long]$rs
    if ($null -eq $start -or $rsv -gt $start) { $start = $rsv }
  }
  if ($null -eq $start) {
    [Console]::Error.WriteLine("gate: minutes per issue not measured (no slot and no driver run)")
  } else {
    $el = [long][math]::Floor(((Get-LedgerClock) - $start) / 60)
    if ($el -lt 0) { $el = 0 }
    if ($el -ge $minutes) {
      Write-Line "gate: limit: #$issue has been worked on for $el minutes in this run; the limit is $minutes (limits.minutesPerIssue)"
      exit 3
    }
  }
}

# --- 7. the turns per role ---
if ($role) {
  if ($null -eq $roleLimit) { Stop-Cannot "unknown role $role" }
  if ([long]$turns -gt $roleLimit) {
    Write-Line "gate: limit: the $role role took $turns turns; the limit is $roleLimit (limits.turnsPerRole.$role)"
    exit 3
  }
}

# --- 8. go ---
$k = $perRun
$left = [string]$env:NIGHTMILL_ISSUES_LEFT
if ($left -cmatch '^[0-9]{1,9}$' -and [long]$left -lt $perRun) { $k = [long]$left }
Write-Line "gate: issues per run: $k"
if ($issue) { Write-Line ("gate: spent on #${issue}: `$" + (Format-Money $spent) + " of `$" + (Format-Money $cost)) }
Write-Line "gate: go"
exit 0

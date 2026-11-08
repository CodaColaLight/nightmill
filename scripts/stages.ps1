# scripts/stages.ps1 - where a story's time went (iteration 41). PowerShell twin of stages.sh.
#   stages.ps1 [-Issue N | -Last N]      # one issue, or the last N takes (default: -Last 5)
# Reads the record <worktrees.root>\.slots\ledger.tsv that slot.ps1 and slot.sh append to (a take, every report, every
# freeing) and prints per take the time of each stage and its share of the total: take, not-reported, the reported
# step names as the slots reported them, and ci-and-merge (from the pull request's open to its merge). A time that
# cannot be known is unknown, never 0s. Read-only: it calls no gh, needs no network and writes no file. The rules are
# those of lib/stages.awk; both shells print the same bytes (LF). NIGHTMILL_CLOCK_FILE (tests only, see
# lib/ledger.ps1) fixes "now".
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$Issue,
  [string]$Last,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$ErrorActionPreference = "Stop"
function Exit-Usage { [Console]::Error.WriteLine("usage: stages.ps1 [-Issue N | -Last N]"); exit 1 }
$hasIssue = $PSBoundParameters.ContainsKey("Issue")
$hasLast = $PSBoundParameters.ContainsKey("Last")
if ($Rest -and @($Rest).Count -gt 0) { Exit-Usage }
if ($hasIssue -and $hasLast) { Exit-Usage }
$mode = "last"; $n = "5"
if ($hasIssue) { $mode = "issue"; $n = $Issue; if ($n -cnotmatch '^[1-9][0-9]{0,9}\z') { Exit-Usage } }
elseif ($hasLast) { $n = $Last; if ($n -cnotmatch '^[1-9][0-9]{0,2}\z') { Exit-Usage } }

. (Join-Path $PSScriptRoot "lib\ledger.ps1")

$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { [Console]::Error.WriteLine("run stages.ps1 from inside a git checkout of the project"); exit 1 }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { [Console]::Error.WriteLine("no $cfgPath (run /nightmill:init)"); exit 1 }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
if ($cfg.worktrees -and $cfg.worktrees.root) { $rootRel = $cfg.worktrees.root }
$root = [System.IO.Path]::GetFullPath((Join-Path $main $rootRel))
$record = Join-Path (Join-Path $root ".slots") "ledger.tsv"

$out = New-Object System.Text.StringBuilder
function Emit([string]$text) { [void]$out.Append($text).Append("`n") }
function Flush { [Console]::Out.Write($out.ToString()); [Console]::Out.Flush() }

if (-not (Test-Path -LiteralPath $record)) { Emit "no record yet: $record"; Flush; exit 0 }
$text = $null
try {
  if (-not (Test-Path -LiteralPath $record -PathType Leaf)) { throw "not a file" }
  $text = [System.IO.File]::ReadAllText($record)
} catch { [Console]::Error.WriteLine("stages: cannot read $record"); exit 1 }

$now = Get-LedgerClock
function Test-UtcStamp([string]$s) { return ($s -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z') }

# read the takes (decision 6)
$takes = New-Object System.Collections.ArrayList
$cur = @{}
$bad = 0
function New-Take($slot, [string]$branch, [long]$at) {
  $t = [pscustomobject]@{ Slot = $slot; Branch = $branch; First = $at; LastAt = $at; S = $null; F = $null
    Steps = (New-Object System.Collections.ArrayList); State = "running"; FName = ""; FStamp = ""; FAt = 0
    FFrom = ""; FTo = ""; FIssues = "" }
  [void]$takes.Add($t)
  $script:cur[$slot] = $t
  return $t
}
$lines = $text -split "`n"
foreach ($raw in $lines) {
  $line = $raw.TrimEnd("`r")
  if ($line -eq "") { continue }
  $f = $line -split "`t", -1
  $kind = $f[0]
  if ($kind -cne "take" -and $kind -cne "step" -and $kind -cne "free") { continue }
  if ($f.Count -ne 11 -or -not (Test-UtcStamp $f[1]) -or $f[2] -cnotmatch '^[0-9]+\z') { $bad++; continue }
  $slot = [long]$f[2]; $at = Get-LedgerEpoch $f[1]
  if ($kind -ceq "take") {
    if ($cur.ContainsKey($slot) -and $null -ne $cur[$slot]) { $cur[$slot].State = "not freed" }
    $t = New-Take $slot $f[3] $at
    if (Test-UtcStamp $f[8]) { $t.S = Get-LedgerEpoch $f[8] }
    if (Test-UtcStamp $f[9]) { $t.F = Get-LedgerEpoch $f[9] } else { $t.F = $at }
    continue
  }
  if (-not $cur.ContainsKey($slot) -or $null -eq $cur[$slot]) { $null = New-Take $slot $f[3] $at }
  $t = $cur[$slot]
  $t.LastAt = $at
  if ($kind -ceq "step") { [void]$t.Steps.Add([pscustomobject]@{ Name = $f[4]; At = $at }); continue }
  $t.State = "freed"; $t.FName = $f[4]; $t.FStamp = $f[1]; $t.FAt = $at
  $t.FFrom = $f[8]; $t.FTo = $f[9]; $t.FIssues = $f[10]
  $cur[$slot] = $null
}
if ($bad -gt 0) { [Console]::Error.WriteLine("stages: skipped $bad malformed lines of $record") }

# which takes (decision 10)
$sel = @()
if ($mode -eq "issue") {
  foreach ($t in $takes) {
    if ($t.State -ne "freed" -or -not $t.FIssues) { continue }
    if (@($t.FIssues -split ",") -ccontains $n) { $sel += $t }
  }
  if ($sel.Count -eq 0) {
    Emit "#${n}: no record; every stage unknown (no slot took it, or a version before iteration 41 freed it)"
    Flush; exit 0
  }
} else {
  $first = $takes.Count - [int]$n
  if ($first -lt 0) { $first = 0 }
  for ($i = $first; $i -lt $takes.Count; $i++) { $sel += $takes[$i] }
}

function Row([string]$a, [string]$b, [string]$c, [string]$d) { Emit ("  {0,-20} {1,4} {2,8} {3,6}" -f $a, $b, $c, $d) }
function Get-Share($t, $total) {
  if ($null -eq $t -or $null -eq $total -or $total -le 0) { return "-" }
  return ("{0}%" -f [long][math]::Floor(100 * $t / $total + 0.5))
}

# the time of each take (decisions 7 to 9)
$j = 0
foreach ($t in $sel) {
  $j++
  $S = $t.S
  $merged = ($t.State -eq "freed" -and (Test-UtcStamp $t.FFrom) -and (Test-UtcStamp $t.FTo))
  $C = $null; $E = $null
  if ($merged) {
    $from = Get-LedgerEpoch $t.FFrom; $to = Get-LedgerEpoch $t.FTo
    $firstKnown = if ($null -ne $S) { $S } else { $t.First }
    if ($from -ge $firstKnown) { $C = $from }
    else { foreach ($step in $t.Steps) { if ($step.At -lt $to) { $C = $step.At } } }
    $E = $to
  } elseif ($t.State -eq "freed") { $C = $t.FAt; $E = $C }
  elseif ($t.State -eq "not freed") { $C = $t.LastAt; $E = $C }
  else { $C = $now; $E = $C }
  $who = "-"
  if ($t.State -eq "freed" -and $t.FIssues) { $who = (@($t.FIssues -split "," | ForEach-Object { "#$_" }) -join ",") }
  if ($merged) { $st = "merged $($t.FTo)" } elseif ($t.State -eq "freed") { $st = "$($t.FName) $($t.FStamp)" } else { $st = $t.State }
  if ($j -gt 1) { [void]$out.Append("`n") }
  Emit "$who  $($t.Branch)  slot $($t.Slot)  $st"

  $rows = New-Object System.Collections.ArrayList
  $byName = @{}
  $add = {
    param([string]$name, $secs)
    if (-not $byName.ContainsKey($name)) {
      $r = [pscustomobject]@{ Name = $name; Runs = 0; Time = [long]0; Unknown = $false }
      $byName[$name] = $r; [void]$rows.Add($r)
    }
    $r = $byName[$name]
    $r.Runs++
    if ($null -eq $secs) { $r.Unknown = $true } else { if ($secs -lt 0) { $secs = 0 }; $r.Time += [long]$secs }
  }
  $steps = @($t.Steps)
  if ($null -ne $S) {
    & $add "take" ($t.F - $S)
    $end = if ($steps.Count -gt 0) { $steps[0].At } else { $C }
    if ($null -ne $C -and $null -ne $end -and $end -gt $C) { $end = $C }
    if ($null -eq $end) { & $add "not-reported" $null } else { & $add "not-reported" ($end - $t.F) }
  } elseif ($steps.Count -gt 0) { & $add "not-reported" $null }
  for ($i = 0; $i -lt $steps.Count; $i++) {
    if ($null -ne $C -and $steps[$i].At -ge $C) { continue }
    $nxt = if ($i -lt $steps.Count - 1) { $steps[$i + 1].At } else { $C }
    if ($null -ne $C -and $null -ne $nxt -and $nxt -gt $C) { $nxt = $C }
    if ($null -eq $nxt) { & $add $steps[$i].Name $null } else { & $add $steps[$i].Name ($nxt - $steps[$i].At) }
  }
  if ($merged -and $null -ne $C) { & $add "ci-and-merge" ($E - $C) }
  $total = $null
  if ($null -ne $S -and $null -ne $E) { $total = [long]($E - $S); if ($total -lt 0) { $total = [long]0 } }
  Row "stage" "runs" "time" "share"
  foreach ($r in $rows) {
    if ($r.Unknown) { Row $r.Name "$($r.Runs)" "unknown" "-" }
    else { Row $r.Name "$($r.Runs)" (Format-LedgerDuration $r.Time) $(if ($null -eq $total) { "-" } else { Get-Share $r.Time $total }) }
  }
  if ($null -eq $total) { Row "total" "" "unknown" "-" }
  else { Row "total" "" (Format-LedgerDuration $total) $(if ($total -gt 0) { "100%" } else { "-" }) }
}
Flush
exit 0

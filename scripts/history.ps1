# scripts/history.ps1 - how the work went in a window (iteration 54). PowerShell twin of history.sh.
#   history.ps1 [-From <t>] [-To <t>] | [-Run <stamp>]   [-Json | -Html <dir>]
# <t> is YYYY-MM-DD (00:00:00Z of that day) or YYYY-MM-DDTHH:MM:SSZ; <stamp> the second form. The window is [from, to],
# both ends included: to defaults to now, from to the earliest line of the record (or a week before to); -Run <stamp>
# is the window of one driver run, and only that run's run lines count.
# Reads the record <worktrees.root>\.slots\ledger.tsv (take, step, free and run lines) and prints the fix rounds and
# check fix rounds per issue, the cost per issue and the slot utilisation; the time issues stayed at each board status
# comes from the board's status changes, read with one query, the only gh command it calls (a read):
#   gh api graphql -f query='query($o: String!, $n: Int!, $after: String) { repositoryOwner(login: $o) { ... } }'
# A board that cannot be read gives ? and a note, never 0. The text (default), one JSON line (-Json, built here, not by
# ConvertTo-Json) or one static page, <dir>\index.html, that needs no network (-Html). It writes nothing else and sets
# nothing on GitHub. The rules are those of lib/history.awk; both shells print the same bytes (UTF-8, LF). Exit 0 when
# it printed or wrote its output, 1 for a record that cannot be read or a page that cannot be written, 2 for a usage
# error, outside a checkout or without the config. The arguments are read from $args (no param block), so that an
# option given twice or without its value is a usage error. NIGHTMILL_CLOCK_FILE (tests only, see lib/ledger.ps1)
# fixes "now". docs/specs/iteration-54-history-metrics.md.
$ErrorActionPreference = "Stop"

$usageText = "usage: history.ps1 [-From <t>] [-To <t>] | [-Run <stamp>]   [-Json | -Html <dir>]"
function Exit-Usage { [Console]::Error.WriteLine($usageText); exit 2 }

. (Join-Path $PSScriptRoot "lib\ledger.ps1")

# Get-Epoch: seconds since 1970 of YYYY-MM-DDTHH:MM:SS[Z], read as UTC, by the arithmetic of lib/history.awk
function Get-Epoch([string]$s) {
  $yr = [long]$s.Substring(0, 4); $mon = [long]$s.Substring(5, 2); $day = [long]$s.Substring(8, 2)
  if ($mon -le 2) { $yr-- }
  $yy = if ($yr -ge 0) { $yr } else { $yr - 399 }
  $era = [long][math]::Floor($yy / 400)
  $yoe = $yr - $era * 400
  $shift = if ($mon -gt 2) { -3 } else { 9 }
  $doy = [long][math]::Floor((153 * ($mon + $shift) + 2) / 5) + $day - 1
  $doe = $yoe * 365 + [long][math]::Floor($yoe / 4) - [long][math]::Floor($yoe / 100) + $doy
  return [long](($era * 146097 + $doe - 719468) * 86400 + [long]$s.Substring(11, 2) * 3600 + [long]$s.Substring(14, 2) * 60 + [long]$s.Substring(17, 2))
}
function Test-UtcStamp([string]$s) { return ($s -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z') }
# a real UTC stamp: the stamp printed back from its seconds is the same; $null when not
function Read-Stamp([string]$s) {
  if (-not (Test-UtcStamp $s)) { return $null }
  $e = Get-Epoch $s
  try { if ((Get-LedgerStamp $e) -cne $s) { return $null } } catch { return $null }
  return $e
}
function Read-Time([string]$s) {
  if ($s -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}\z') { $s = $s + "T00:00:00Z" }
  return (Read-Stamp $s)
}

# the arguments
$a = @($args)
$from = $null; $to = $null; $run = ""; $mode = "text"; $dir = ""
$seen = @{}
for ($i = 0; $i -lt $a.Count; $i++) {
  $opt = ([string]$a[$i]).ToLowerInvariant()
  if ($opt -eq "-h" -or $opt -eq "--help" -or $opt -eq "-help") { [Console]::Out.Write($usageText + "`n"); exit 0 }
  if (@("-from", "-to", "-run", "-json", "-html") -notcontains $opt) { Exit-Usage }
  if ($seen.ContainsKey($opt)) { Exit-Usage }
  $seen[$opt] = $true
  if ($opt -eq "-json") { $mode = "json"; continue }
  if ($i + 1 -ge $a.Count) { Exit-Usage }
  $i++
  $v = [string]$a[$i]
  switch ($opt) {
    "-from" { $from = Read-Time $v; if ($null -eq $from) { Exit-Usage } }
    "-to" { $to = Read-Time $v; if ($null -eq $to) { Exit-Usage } }
    "-run" { if ($null -eq (Read-Stamp $v)) { Exit-Usage }; $run = $v }
    "-html" { if ($v -eq "" -or $v.StartsWith("-")) { Exit-Usage }; $dir = $v; $mode = "html" }
  }
}
if ($seen.ContainsKey("-json") -and $seen.ContainsKey("-html")) { Exit-Usage }
if ($seen.ContainsKey("-run") -and ($seen.ContainsKey("-from") -or $seen.ContainsKey("-to"))) { Exit-Usage }
$now = Get-LedgerClock
if ($null -ne $from) {
  $toCheck = if ($null -ne $to) { $to } else { $now }
  if ($from -gt $toCheck) { Exit-Usage }
}

$prevOutputEncoding = $null
try {
  $prevOutputEncoding = [Console]::OutputEncoding
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
} catch { }
try {

$ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
$gitOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $ea
if (-not $gitOk -or -not $gitDir) { [Console]::Error.WriteLine("run history.ps1 from inside a git checkout of the project"); exit 2 }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { [Console]::Error.WriteLine("no $cfgPath (run /nightmill:init)"); exit 2 }
try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [Console]::Error.WriteLine("$cfgPath is not valid JSON"); exit 2 }
function Cfg($obj, [string[]]$path, $default) {
  foreach ($k in $path) {
    if ($null -eq $obj) { return $default }
    $p = $obj.PSObject.Properties[$k]
    if (-not $p) { return $default }
    $obj = $p.Value
  }
  if ($null -eq $obj -or "$obj" -eq "") { return $default }
  return $obj
}
$rootRel = "../" + (Split-Path $main -Leaf) + "-wt"
$rr = Cfg $cfg @("worktrees", "root") ""
if ($rr) { $rootRel = [string]$rr }
$root = [System.IO.Path]::GetFullPath((Join-Path $main $rootRel))
$record = Join-Path (Join-Path $root ".slots") "ledger.tsv"
$ledgerText = $null
if (Test-Path -LiteralPath $record) {
  try {
    if (-not (Test-Path -LiteralPath $record -PathType Leaf)) { throw "not a file" }
    $ledgerText = [System.IO.File]::ReadAllText($record)
  } catch { [Console]::Error.WriteLine("history: cannot read $record"); exit 1 }
}

$owner = [string](Cfg $cfg @("github", "owner") "")
$repo = [string](Cfg $cfg @("github", "repo") "")
$number = [string](Cfg $cfg @("github", "projectNumber") "")
$epic = [string](Cfg $cfg @("labels", "epic") "epic")
$haveWt = [bool]$cfg.PSObject.Properties["worktrees"]
$cfgSlots = [string](Cfg $cfg @("worktrees", "slots") "")
$keys = @("backlog", "ready", "spec", "specReview", "approved", "inProgress", "review", "done")
$defaults = @("Backlog", "Ready", "Spec", "Spec review", "Approved", "In progress", "Review", "Done")
$names = @()
for ($i = 0; $i -lt 8; $i++) { $names += [string](Cfg $cfg @("board", "statuses", $keys[$i]) $defaults[$i]) }
# a status name to its index, matched exactly (a hashtable would match regardless of case)
$keyOfExact = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
for ($i = 0; $i -lt 8; $i++) { if (-not $keyOfExact.ContainsKey($names[$i])) { $keyOfExact[$names[$i]] = $i } }

function Clean([string]$v) { return ($v -replace '[\x00-\x1F\x7F]', '') }
$notes = New-Object System.Collections.Generic.List[string]
function Add-Note([string]$s) { $script:notes.Add((Clean $s)) | Out-Null }

# ---- the ledger (decision 3), by the rules of lib/stages.awk
$takes = New-Object System.Collections.ArrayList
$runs = New-Object System.Collections.ArrayList
$cur = @{}
$bad = 0
$first = $null
function New-SlotHold([long]$slot, [long]$at) {
  $t = [pscustomobject]@{ Slot = $slot; Start = $at; LastAt = $at; Line = $false; State = "running"; Free = 0; Issues = ""
    Steps = (New-Object System.Collections.ArrayList) }
  [void]$script:takes.Add($t)
  $script:cur[$slot] = $t
  return $t
}
if ($null -ne $ledgerText) {
  foreach ($raw in ($ledgerText -split "`n")) {
    $line = $raw.TrimEnd("`r")
    $f = $line -split "`t", -1
    $kind = $f[0]
    if ($kind -cne "take" -and $kind -cne "step" -and $kind -cne "free" -and $kind -cne "run") { continue }
    if ($kind -ceq "run") {
      if ($f.Count -ne 11 -or -not (Test-UtcStamp $f[1]) -or -not (Test-UtcStamp $f[2])) { $bad++; continue }
      $at = Get-Epoch $f[1]
      if ($null -eq $first -or $at -lt $first) { $first = $at }
      [void]$runs.Add([pscustomobject]@{ At = $at; Run = $f[2]; Issues = $f[5]; Cost = $f[9] })
      continue
    }
    if ($f.Count -ne 11 -or -not (Test-UtcStamp $f[1]) -or $f[2] -cnotmatch '^[0-9]+\z') { $bad++; continue }
    $slot = [long]$f[2]; $at = Get-Epoch $f[1]
    if ($null -eq $first -or $at -lt $first) { $first = $at }
    if ($kind -ceq "take") {
      if ($cur.ContainsKey($slot) -and $null -ne $cur[$slot]) { $cur[$slot].State = "not freed" }
      $t = New-SlotHold $slot $at
      $t.Line = $true
      if (Test-UtcStamp $f[8]) { $t.Start = Get-Epoch $f[8] }
      continue
    }
    if (-not $cur.ContainsKey($slot) -or $null -eq $cur[$slot]) { $null = New-SlotHold $slot $at }
    $t = $cur[$slot]
    $t.LastAt = $at
    if ($kind -ceq "step") { [void]$t.Steps.Add($f[4]); continue }
    $t.State = "freed"; $t.Free = $at; $t.Issues = $f[10]
    $cur[$slot] = $null
  }
}
if ($bad -gt 0) { [Console]::Error.WriteLine("history: skipped $bad malformed lines of $record") }

# ---- the window (decision 2)
$runNote = ""
if ($run) {
  $FROM = Get-Epoch $run; $TO = $null
  foreach ($r in $runs) { if ($r.Run -ceq $run -and ($null -eq $TO -or $r.At -gt $TO)) { $TO = $r.At } }
  if ($null -eq $TO) { $TO = $now; $runNote = "no run lines for the driver run $run" }
  if ($TO -lt $FROM) { $TO = $FROM }
} else {
  $TO = if ($null -ne $to) { [long]$to } else { [long]$now }
  if ($null -ne $from) { $FROM = [long]$from } elseif ($null -ne $first) { $FROM = [long]$first } else { $FROM = $TO - 7 * 86400 }
  if ($FROM -gt $TO) { $FROM = $TO }
}
$W = [long]($TO - $FROM)
function In-Win([long]$t) { return ($t -ge $script:FROM -and $t -le $script:TO) }

# ---- the board (decision 6)
$query = 'query($o: String!, $n: Int!, $after: String) { repositoryOwner(login: $o) { ... on ProjectV2Owner { projectV2(number: $n) { items(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { content { ... on Issue { number labels(first: 50) { nodes { name } } timelineItems(first: 100, itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) { nodes { ... on ProjectV2ItemStatusChangedEvent { createdAt status project { number } } } } } } } } } } } }'
$epoch0 = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
# an event's createdAt as a stamp: pwsh's ConvertFrom-Json turns it into a DateTime, Windows PowerShell keeps the text
function Get-EventStamp($v) {
  if ($v -is [datetime]) {
    $d = [datetime]$v
    if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
    return $d.ToString("yyyy-MM-ddTHH:mm:ss", [Globalization.CultureInfo]::InvariantCulture) + "Z"
  }
  return [string]$v
}
$board = $true; $boardNote = ""; $more = $false
$nodes = New-Object System.Collections.ArrayList
if (-not $owner -or -not $number) { $board = $false; $boardNote = "github.owner and github.projectNumber are not set" }
elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) { $board = $false; $boardNote = "gh is not installed or not on the PATH" }
else {
  $after = ""
  for ($page = 1; $page -le 20; $page++) {
    $ga = @("api", "graphql", "-f", "query=$query", "-f", "o=$owner", "-F", "n=$number")
    if ($after) { $ga += @("-f", "after=$after") }
    $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $outLines = New-Object System.Collections.Generic.List[string]
    $errLines = New-Object System.Collections.Generic.List[string]
    try {
      & gh @ga 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $errLines.Add([string]$_.Exception.Message) | Out-Null }
        else { $outLines.Add([string]$_) | Out-Null }
      }
      $ghCode = $LASTEXITCODE
    } catch { $errLines.Add([string]$_.Exception.Message) | Out-Null; $ghCode = 1 }
    $ErrorActionPreference = $ea
    if ($ghCode -ne 0) {
      $board = $false
      $boardNote = ((@($errLines) -join " ") -replace "[`r`n]", " ").TrimEnd()
      if (-not $boardNote) { $boardNote = "gh api graphql failed" }
      break
    }
    $doc = $null
    try { $doc = (@($outLines) -join "`n") | ConvertFrom-Json } catch { $doc = $null }
    $conn = $null
    if ($null -ne $doc -and $doc.data -and $doc.data.repositoryOwner -and $doc.data.repositoryOwner.projectV2) { $conn = $doc.data.repositoryOwner.projectV2.items }
    if ($null -eq $conn) { $board = $false; $boardNote = "gh api graphql gave no board items"; break }
    foreach ($node in @($conn.nodes)) { if ($null -ne $node) { [void]$nodes.Add($node) } }
    $after = [string]$conn.pageInfo.endCursor
    if (-not ($conn.pageInfo.hasNextPage -eq $true -and $after)) { break }
    if ($page -ge 20) { $more = $true; break }
  }
}

$scount = @(0, 0, 0, 0, 0, 0, 0, 0); $stotal = @([long]0, 0, 0, 0, 0, 0, 0, 0)
$slens = @(); for ($i = 0; $i -lt 8; $i++) { $slens += , (New-Object System.Collections.Generic.List[long]) }
$issueSet = New-Object 'System.Collections.Generic.HashSet[long]'
$itime = @{}   # "<n>:<key index>" -> seconds
$smed = @($null, $null, $null, $null, $null, $null, $null, $null); $smax = @($null, $null, $null, $null, $null, $null, $null, $null)
if (-not $board) { Add-Note "the board was not read: $boardNote" }
else {
  $other = 0; $many = 0
  foreach ($node in $nodes) {
    $c = $node.content
    if ($null -eq $c -or -not $c.PSObject.Properties["number"] -or $null -eq $c.number) { continue }
    $num = [string]$c.number
    if ($num -cnotmatch '^[0-9]+\z') { continue }
    $labels = @()
    if ($c.labels -and $c.labels.nodes) { $labels = @($c.labels.nodes | ForEach-Object { [string]$_.name }) }
    if ($epic -and ($labels -ccontains $epic)) { continue }
    $evs = @()
    if ($c.timelineItems -and $c.timelineItems.nodes) { $evs = @($c.timelineItems.nodes) }
    if ($evs.Count -ge 100) { $many++ }
    $eat = @(); $est = @()
    foreach ($e in $evs) {
      if ($null -eq $e -or $null -eq $e.project -or [string]$e.project.number -cne $number) { continue }
      $st = Get-EventStamp $e.createdAt
      if (-not (Test-UtcStamp $st)) { continue }
      $eat += (Get-Epoch $st); $est += [string]$e.status
    }
    for ($k = 0; $k -lt $eat.Count - 1; $k++) {
      if (-not (In-Win $eat[$k + 1])) { continue }
      $len = [long]($eat[$k + 1] - $eat[$k]); if ($len -lt 0) { $len = 0 }
      if (-not $keyOfExact.ContainsKey($est[$k])) { $other++; continue }
      $ki = $keyOfExact[$est[$k]]
      $scount[$ki]++; $slens[$ki].Add($len); $stotal[$ki] += $len
      if ($ki -ge 1 -and $ki -le 6) {
        $n = [long]$num
        [void]$issueSet.Add($n)
        $tk = "${n}:$ki"
        if ($itime.ContainsKey($tk)) { $itime[$tk] += $len } else { $itime[$tk] = $len }
      }
    }
  }
  if ($other -gt 0) { Add-Note "$other stays at a status not in board.statuses were not counted" }
  if ($more) { Add-Note "the board listing stopped after 2000 items" }
  if ($many -gt 0) { Add-Note "$many issues have more than 100 status changes; only the first 100 were read" }
  for ($i = 0; $i -lt 7; $i++) {
    $sorted = @($slens[$i] | Sort-Object)
    $n = $sorted.Count
    if ($n -gt 0) { $smed[$i] = [long]$sorted[[int][math]::Floor(($n - 1) / 2)]; $smax[$i] = [long]$sorted[$n - 1] }
  }
}

# ---- the ledger notes
if ($null -eq $ledgerText) { Add-Note "no record yet: $record" }
if ($runNote) { Add-Note $runNote }

# ---- fix rounds per issue (decision 4): the takes freed in the window
$itake = @{}; $ireview = @{}; $iround = @{}; $icheck = @{}
foreach ($t in $takes) {
  if ($t.State -ne "freed" -or $t.Issues -eq "" -or -not (In-Win $t.Free)) { continue }
  $rmax = 0; $review = $false; $cmax = 0
  foreach ($nm in $t.Steps) {
    if ($nm -ceq "code-review") { $review = $true }
    elseif ($nm -cmatch '^(fix-round|dispute|test-finding)-([1-9][0-9]*)\z') { $v = [long]$Matches[2]; if ($v -gt $rmax) { $rmax = $v } }
    elseif ($nm -cmatch '^check-fix-([1-9][0-9]*)\z') { $v = [long]$Matches[1]; if ($v -gt $cmax) { $cmax = $v } }
  }
  foreach ($p in ($t.Issues -split ",")) {
    if ($p -cnotmatch '^[0-9]+\z') { continue }
    $n = [long]$p
    [void]$issueSet.Add($n)
    $itake[$n] = $true
    if ($review) { $ireview[$n] = $true }
    if (-not $iround.ContainsKey($n) -or $rmax -gt $iround[$n]) { $iround[$n] = $rmax }
    if (-not $icheck.ContainsKey($n) -or $cmax -gt $icheck[$n]) { $icheck[$n] = $cmax }
  }
}

# ---- cost per issue (decision 5)
$ctotal = [double]0; $cruns = 0; $cwithout = 0; $cnone = [double]0
$iruns = @{}; $icost = @{}
foreach ($r in $runs) {
  if (-not (In-Win $r.At)) { continue }
  if ($run -and $r.Run -cne $run) { continue }
  $cruns++
  $cost = [double]0
  if ($r.Cost -eq "") { $cwithout++ }
  else { $tmpv = [double]0; if ([double]::TryParse($r.Cost, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$tmpv)) { $cost = $tmpv } }
  $ctotal += $cost
  if ($r.Issues -eq "") { $cnone += $cost; continue }
  $parts = @($r.Issues -split ",")
  $cnt = $parts.Count
  foreach ($p in $parts) {
    if ($p -cnotmatch '^[0-9]+\z') { continue }
    $n = [long]$p
    [void]$issueSet.Add($n)
    if ($iruns.ContainsKey($n)) { $iruns[$n]++ } else { $iruns[$n] = 1 }
    if ($icost.ContainsKey($n)) { $icost[$n] += $cost / $cnt } else { $icost[$n] = $cost / $cnt }
  }
}

# ---- slot utilisation (decision 7)
$hi = 0; $noLine = 0; $anyTake = $false
$stakes = @{}; $sheld = @{}
foreach ($t in $takes) {
  $s0 = [long]$t.Start
  if ($t.State -eq "freed") { $e0 = [long]$t.Free } elseif ($t.State -eq "not freed") { $e0 = [long]$t.LastAt } else { $e0 = [long]$TO }
  if ($s0 -gt $TO -or $e0 -lt $FROM) { continue }
  if ($s0 -lt $FROM) { $s0 = $FROM }
  if ($e0 -gt $TO) { $e0 = $TO }
  $h = [long]($e0 - $s0); if ($h -lt 0) { $h = 0 }
  $sl = [long]$t.Slot
  $anyTake = $true
  if ($sl -gt $hi) { $hi = $sl }
  if ($stakes.ContainsKey($sl)) { $stakes[$sl]++; $sheld[$sl] += $h } else { $stakes[$sl] = 1; $sheld[$sl] = $h }
  if (-not $t.Line) { $noLine++ }
}
if ($noLine -gt 0) { Add-Note "$noLine takes have no take line; their held time starts at their first line" }
$slotsNone = (-not $haveWt -and -not $anyTake)
$S = 0; $sfrom = ""; $util = $null
$sshare = @{}
function Held([long]$sl) { if ($script:sheld.ContainsKey($sl)) { return [long]$script:sheld[$sl] } return [long]0 }
function Takes([long]$sl) { if ($script:stakes.ContainsKey($sl)) { return [long]$script:stakes[$sl] } return [long]0 }
if (-not $slotsNone) {
  if ($cfgSlots -cmatch '^[0-9]+\z' -and [long]$cfgSlots -gt 0) { $S = [long]$cfgSlots; $sfrom = "config" } else { $S = 2; $sfrom = "default" }
  if ($hi -gt $S) { $S = $hi; $sfrom = "record" }
  $sum = [long]0
  for ($sl = 1; $sl -le $S; $sl++) {
    $sum += (Held $sl)
    if ($W -gt 0) { $sshare[[long]$sl] = [long][math]::Floor(100.0 * (Held $sl) / $W + 0.5) } else { $sshare[[long]$sl] = $null }
  }
  if ($W -gt 0) { $util = [long][math]::Floor(100.0 * $sum / ($S * $W) + 0.5) }
}

# ---- the cells, as printed
$inv = [Globalization.CultureInfo]::InvariantCulture
function Money([double]$x) { return $x.ToString("F2", $script:inv) }
function Dur($t) { return (Format-LedgerDuration ([long]$t)) }
$ilist = @($issueSet | Sort-Object)
$header = "history $(Get-LedgerStamp $FROM) to $(Get-LedgerStamp $TO) ($(Dur $W))"
if ($run) { $header += ", driver run $run" }
$CN = @(); $CS = @(); $CM = @(); $CX = @(); $CT = @()
for ($i = 0; $i -lt 7; $i++) {
  $CN += (Clean $names[$i])
  if (-not $board) { $CS += "?"; $CM += "?"; $CX += "?"; $CT += "?" }
  else {
    $CS += "$($scount[$i])"; $CT += (Dur $stotal[$i])
    if ($scount[$i] -gt 0) { $CM += (Dur $smed[$i]); $CX += (Dur $smax[$i]) } else { $CM += "-"; $CX += "-" }
  }
}
$rowsI = @()
foreach ($n in $ilist) {
  $times = @()
  for ($ki = 1; $ki -le 6; $ki++) {
    if (-not $board) { $times += "?" }
    elseif ($itime.ContainsKey("${n}:$ki")) { $times += (Dur $itime["${n}:$ki"]) }
    else { $times += "-" }
  }
  $r = "-"
  if ($itake.ContainsKey($n)) { if (-not $ireview.ContainsKey($n) -and $iround[$n] -eq 0) { $r = "-" } else { $r = "$($iround[$n])" } }
  $c = "-"; if ($itake.ContainsKey($n)) { $c = "$($icheck[$n])" }
  $k = 0; if ($iruns.ContainsKey($n)) { $k = $iruns[$n] }
  $m = "-"; if ($k -gt 0) { $m = "`$" + (Money $icost[$n]) }
  $rowsI += [pscustomobject]@{ N = $n; Times = $times; R = $r; C = $c; K = $k; M = $m }
}
$costLine = "cost: `$$(Money $ctotal) in $cruns headless runs; `$$(Money $cnone) on no issue; $cwithout runs without a cost"
if ($slotsNone) { $slotLine = "slots: none recorded" }
else {
  $u = if ($null -eq $util) { "-" } else { "$util%" }
  $slotLine = "slots: $S ($sfrom), utilisation $u"
}
function Share-Text([long]$sl) { $v = $script:sshare[$sl]; if ($null -eq $v) { return "-" } return "$v%" }

$out = New-Object System.Text.StringBuilder
function Emit([string]$text) { [void]$script:out.Append($text).Append("`n") }
function Format-Row([string]$fmt, [object[]]$vals) { return [string]::Format($script:inv, $fmt, $vals) }

# a JSON string: " and \ escaped, every character below 0x20 as \u00xx, the rest as is (decision 10)
function Get-JsonString([string]$v) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $v.ToCharArray()) {
    if ($ch -eq [char]34 -or $ch -eq [char]92) { [void]$sb.Append([char]92).Append($ch) }
    elseif ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function JNum($v) { if ($null -eq $v) { return "null" } return "$v" }
# HTML: & < > " ' escaped, in that order, as the dashboard does
function Get-Html([string]$s) { return $s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;").Replace("'", "&#39;") }

if ($mode -eq "text") {
  Emit $header
  Emit ""
  $fs = '{0,-14} {1,6} {2,9} {3,9} {4,9}'
  Emit (Format-Row $fs @("status", "stays", "median", "max", "total"))
  for ($i = 0; $i -lt 7; $i++) { Emit (Format-Row $fs @($CN[$i], $CS[$i], $CM[$i], $CX[$i], $CT[$i])) }
  Emit ""
  if ($rowsI.Count -eq 0) { Emit "no issue in the window" }
  else {
    $fi = '{0,-6} {1,10} {2,10} {3,10} {4,10} {5,10} {6,10} {7,6} {8,6} {9,4} {10,8}'
    Emit (Format-Row $fi @("issue", "ready", "spec", "specReview", "approved", "inProgress", "review", "rounds", "checks", "runs", "cost"))
    foreach ($row in $rowsI) { Emit (Format-Row $fi (@("#$($row.N)") + $row.Times + @($row.R, $row.C, "$($row.K)", $row.M))) }
  }
  Emit $costLine
  Emit ""
  Emit $slotLine
  if (-not $slotsNone) {
    $fsl = '  {0,4} {1,6} {2,9} {3,6}'
    Emit (Format-Row $fsl @("slot", "takes", "held", "share"))
    for ($sl = 1; $sl -le $S; $sl++) { Emit (Format-Row $fsl @("$sl", "$(Takes $sl)", (Dur (Held $sl)), (Share-Text $sl))) }
  }
  foreach ($nt in $notes) { Emit "note: $nt" }
  [Console]::Out.Write($out.ToString())
  [Console]::Out.Flush()
  exit 0
}

if ($mode -eq "json") {
  $j = '{"from":' + (Get-JsonString (Get-LedgerStamp $FROM)) + ',"to":' + (Get-JsonString (Get-LedgerStamp $TO)) + ',"run":'
  if ($run) { $j += (Get-JsonString $run) } else { $j += "null" }
  if (-not $board) { $j += ',"statuses":null' }
  else {
    $parts = @()
    for ($i = 0; $i -lt 7; $i++) {
      $parts += ('{"key":' + (Get-JsonString $keys[$i]) + ',"name":' + (Get-JsonString $CN[$i]) + ',"stays":' + $scount[$i] + ',"median":' + (JNum $smed[$i]) + ',"max":' + (JNum $smax[$i]) + ',"total":' + $stotal[$i] + '}')
    }
    $j += ',"statuses":[' + ($parts -join ",") + ']'
  }
  $parts = @()
  foreach ($row in $rowsI) {
    $n = $row.N
    $o = '{"number":' + $n + ',"times":'
    if (-not $board) { $o += "null" }
    else {
      $tp = @()
      for ($ki = 1; $ki -le 6; $ki++) {
        $tv = "null"; if ($itime.ContainsKey("${n}:$ki")) { $tv = "$($itime["${n}:$ki"])" }
        $tp += ((Get-JsonString $keys[$ki]) + ":" + $tv)
      }
      $o += "{" + ($tp -join ",") + "}"
    }
    $rv = if ($row.R -eq "-") { "null" } else { $row.R }
    $cv = if ($row.C -eq "-") { "null" } else { $row.C }
    $mv = if ($row.M -eq "-") { "null" } else { Money $icost[$n] }
    $o += ',"rounds":' + $rv + ',"checks":' + $cv + ',"runs":' + $row.K + ',"cost":' + $mv + '}'
    $parts += $o
  }
  $j += ',"issues":[' + ($parts -join ",") + ']'
  $j += ',"cost":{"total":' + (Money $ctotal) + ',"runs":' + $cruns + ',"withoutCost":' + $cwithout + ',"noIssue":' + (Money $cnone) + '}'
  if ($slotsNone) { $j += ',"slots":null' }
  else {
    $parts = @()
    for ($sl = 1; $sl -le $S; $sl++) { $parts += ('{"slot":' + $sl + ',"takes":' + (Takes $sl) + ',"held":' + (Held $sl) + ',"share":' + (JNum $sshare[[long]$sl]) + '}') }
    $j += ',"slots":{"count":' + $S + ',"from":' + (Get-JsonString $sfrom) + ',"utilisation":' + (JNum $util) + ',"perSlot":[' + ($parts -join ",") + ']}'
  }
  $j += ',"notes":[' + ((@($notes) | ForEach-Object { Get-JsonString $_ }) -join ",") + ']}'
  [Console]::Out.Write($j + "`n")
  [Console]::Out.Flush()
  exit 0
}

# ---- the page (decision 11)
$title = Get-Html (Clean "nightmill history $owner/$repo")
Emit "<!DOCTYPE html>"
Emit '<html lang="en">'
Emit "<head>"
Emit '<meta charset="utf-8">'
Emit "<title>$title</title>"
Emit "<style>"
Emit "body { font-family: sans-serif; margin: 1.5em; }"
Emit "table { border-collapse: collapse; margin-bottom: 1em; }"
Emit "th, td { padding: 0.2em 0.8em; text-align: right; border-bottom: 1px solid #ccc; }"
Emit "th:first-child, td:first-child { text-align: left; }"
Emit ".bar { background: #48a; height: 0.8em; }"
Emit "</style>"
Emit "</head>"
Emit "<body>"
Emit "<h1>$title</h1>"
Emit "<p>$(Get-Html $header)</p>"
# the status table; the bar is the status's share of the summed totals of all eight statuses
$T = [long]0
if ($board) { for ($i = 0; $i -lt 8; $i++) { $T += $stotal[$i] } }
Emit "<table>"
Emit "<tr><th>status</th><th>stays</th><th>median</th><th>max</th><th>total</th><th></th></tr>"
for ($i = 0; $i -lt 7; $i++) {
  $bar = ""
  if ($board) {
    $p = 0; if ($T -gt 0) { $p = [long][math]::Floor((200 * [long]$stotal[$i] + $T) / (2 * $T)) }
    $bar = "<div class=`"bar`" style=`"width:$p%`"></div>"
  }
  Emit ("<tr><td>" + (Get-Html $CN[$i]) + "</td><td>" + (Get-Html $CS[$i]) + "</td><td>" + (Get-Html $CM[$i]) + "</td><td>" + (Get-Html $CX[$i]) + "</td><td>" + (Get-Html $CT[$i]) + "</td><td>" + $bar + "</td></tr>")
}
Emit "</table>"
if ($rowsI.Count -eq 0) { Emit "<p>no issue in the window</p>" }
else {
  Emit "<table>"
  Emit "<tr><th>issue</th><th>ready</th><th>spec</th><th>specReview</th><th>approved</th><th>inProgress</th><th>review</th><th>rounds</th><th>checks</th><th>runs</th><th>cost</th></tr>"
  foreach ($row in $rowsI) {
    $line = "<tr><td>#$($row.N)</td>"
    foreach ($tv in $row.Times) { $line += "<td>" + (Get-Html $tv) + "</td>" }
    $line += "<td>" + (Get-Html $row.R) + "</td><td>" + (Get-Html $row.C) + "</td><td>$($row.K)</td><td>" + (Get-Html $row.M) + "</td></tr>"
    Emit $line
  }
  Emit "</table>"
}
Emit "<p>$(Get-Html $costLine)</p>"
Emit "<p>$(Get-Html $slotLine)</p>"
if (-not $slotsNone) {
  Emit "<table>"
  Emit "<tr><th>slot</th><th>takes</th><th>held</th><th>share</th><th></th></tr>"
  for ($sl = 1; $sl -le $S; $sl++) {
    $v = $sshare[[long]$sl]; $p = if ($null -eq $v) { 0 } else { $v }
    Emit ("<tr><td>$sl</td><td>$(Takes $sl)</td><td>$(Dur (Held $sl))</td><td>$(Share-Text $sl)</td><td><div class=`"bar`" style=`"width:$p%`"></div></td></tr>")
  }
  Emit "</table>"
}
if ($notes.Count -gt 0) {
  Emit "<ul>"
  foreach ($nt in $notes) { Emit "<li>$(Get-Html $nt)</li>" }
  Emit "</ul>"
}
Emit "</body>"
Emit "</html>"

# written to a temporary file in <dir> and moved over index.html, so a reader never sees half a page
$pagePath = Join-Path $dir "index.html"
function Exit-Cannot([string]$why) {
  $first = @(([string]$why) -split "`r?`n" | Where-Object { $_ -ne "" })
  $w = if ($first.Count -gt 0) { $first[0].Trim() } else { "" }
  [Console]::Error.WriteLine("history: cannot write $script:pagePath ($w)")
  exit 1
}
if (Test-Path -LiteralPath $dir -PathType Leaf) { Exit-Cannot "$dir is a file" }
try { if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null } } catch { Exit-Cannot $_.Exception.Message }
$chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$rng = New-Object System.Random
$suffix = -join (1..6 | ForEach-Object { $chars[$rng.Next($chars.Length)] })
$part = Join-Path $dir (".index.html." + $suffix)
try {
  [System.IO.File]::WriteAllText($part, $out.ToString(), (New-Object System.Text.UTF8Encoding $false))
  if (Test-Path -LiteralPath $pagePath -PathType Leaf) { [System.IO.File]::Replace($part, $pagePath, $null) }
  else { [System.IO.File]::Move($part, $pagePath) }
} catch {
  $why = $_.Exception.Message
  try { if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force } } catch { }
  Exit-Cannot $why
}
[Console]::Out.Write("history: wrote $pagePath`n")
[Console]::Out.Flush()
exit 0
} finally {
  if ($null -ne $prevOutputEncoding) { try { [Console]::OutputEncoding = $prevOutputEncoding } catch { } }
}

# scripts/status.ps1 - one table of what waits for the maintainer and what is stuck (nightmill).
#
#   status.ps1 [-All] [-Porcelain | -Json]
#
# -Porcelain prints the same cells for a program, tab separated, one record per line ending with LF, as UTF-8:
# item (#, Status, Who, PR, Age, Flag, Title), note, slot (the ten cells of the Slots section) and capacity
# (docs/specs/iteration-31-dashboard.md); the text form does not change. -Json prints the same cells as one JSON
# object on one line: {"items":[...],"notes":[...],"slots":[...]|null,"capacity":"..."|null}, built here, not by
# ConvertTo-Json (docs/specs/iteration-54-history-metrics.md decision 10).
# Joins the board items, the pull requests and the slots and prints them as one table, Spec review and
# Approved first, with stale states flagged, then the Slots section: every slot with what its agent is doing
# (running, stalled or unknown, as slot.ps1 decides it; iteration 23). -All also lists the items at Backlog and Done. It only reads:
# gh project item-list / project view, gh pr list, gh api graphql (a query), slot.ps1 -Status -Porcelain and
# slot.ps1 -Capacity (the last line, when the project has worktrees).
# Run it from inside the project: any checkout or worktree of it. Settings come from .claude/nightmill.json
# in the main checkout (github, board.statuses, labels.epic, git.specPrefix, worktrees). The rules and the
# texts are in docs/specs/iteration-8-status.md; status.sh prints the same.
# Exit code 0 when the table was printed (flags do not change it), 2 for a usage error, a missing or
# unreadable config, a missing gh or a failed gh call.
# $env:NIGHTMILL_NOW (seconds since 1970, with the local time zone taken as UTC) fixes the clock; the smoke test uses it.
param(
  [switch]$All,
  [switch]$Porcelain,
  [switch]$Json,
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"

function Die([string]$msg) { [Console]::Error.WriteLine("status.ps1: $msg"); exit 2 }
if ($Rest -or ($Porcelain -and $Json)) { [Console]::Error.WriteLine("usage: status.ps1 [-All] [-Porcelain | -Json]"); exit 2 }
# -Json takes the porcelain path; the records are turned into the JSON object at the end
$asJson = [bool]$Json
if ($asJson) { $Porcelain = [switch]$true }

# -Porcelain: gh's output is decoded as UTF-8 and the records are written as UTF-8 (no byte order mark); the previous
# encoding is put back in the finally at the end
$prevOutputEncoding = $null
if ($Porcelain) {
  try {
    $prevOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
  } catch { }
}
try {

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die "gh is not installed or not on the PATH" }
$gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { Die "run status.ps1 from inside a git checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path $cfgPath)) { Die "no $cfgPath (run /nightmill:init)" }
try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Die "$cfgPath is not valid JSON" }

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

$owner = Cfg $cfg @("github", "owner") ""
$repo = Cfg $cfg @("github", "repo") ""
$number = Cfg $cfg @("github", "projectNumber") ""
if (-not $owner -or -not $repo -or -not $number) { Die "github.owner, github.repo and github.projectNumber are needed in $cfgPath" }
$specPrefix = Cfg $cfg @("git", "specPrefix") "spec/"
$epic = Cfg $cfg @("labels", "epic") "epic"
$stSpecReview = Cfg $cfg @("board", "statuses", "specReview") "Spec review"
$stApproved = Cfg $cfg @("board", "statuses", "approved") "Approved"
$stInProgress = Cfg $cfg @("board", "statuses", "inProgress") "In progress"
$stReview = Cfg $cfg @("board", "statuses", "review") "Review"
$stSpec = Cfg $cfg @("board", "statuses", "spec") "Spec"
$stReady = Cfg $cfg @("board", "statuses", "ready") "Ready"
$stBacklog = Cfg $cfg @("board", "statuses", "backlog") "Backlog"
$stDone = Cfg $cfg @("board", "statuses", "done") "Done"
$order = @($stSpecReview, $stApproved, $stInProgress, $stReview, $stSpec, $stReady, $stBacklog, $stDone)
$rank = @{}
for ($i = 0; $i -lt $order.Count; $i++) { $rank[$order[$i]] = $i + 1 }

$grace = 7200
$limitItems = 200
$limitPrs = 100

# ---- the clock: seconds on one scale, the local time of a slot marker read as if it were UTC
$epoch0 = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
function ToEpoch($v) {
  if ($v -is [datetime]) {
    $d = [datetime]$v
    if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
    elseif ($d.Kind -eq [DateTimeKind]::Unspecified) { $d = [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
    return [long]($d - $epoch0).TotalSeconds
  }
  $d = [datetime]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
  return [long]($d - $epoch0).TotalSeconds
}
if ($env:NIGHTMILL_NOW) {
  $now = [long]$env:NIGHTMILL_NOW
  $nowLocal = $now
} else {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $nowLocal = [long]([datetime]::SpecifyKind((Get-Date), [DateTimeKind]::Utc) - $epoch0).TotalSeconds
}

# StampOf YYYY-MM-DDTHH:MM:SS: seconds since 1970 with the time read as UTC, by the arithmetic of stamp in
# lib/status.awk (not a date parser, so every value of the form gives a number, as in slot.ps1)
function StampOf([string]$s) {
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

function Span([long]$sec) {
  if ($sec -lt 0) { $sec = 0 }
  if ($sec -lt 3600) { return "$([math]::Floor($sec / 60))m" }
  if ($sec -lt 86400) { return "$([math]::Floor($sec / 3600))h" }
  return "$([math]::Floor($sec / 86400))d"
}

# ---- the sources (only reads)
# not named Gh: function names are case-insensitive and would shadow the gh command
function Get-GhText([string]$what, [string[]]$ghArgs) {
  $text = (& gh @ghArgs | Out-String)
  if ($LASTEXITCODE -ne 0) { Die "$what failed (gh exit code $LASTEXITCODE)" }
  return $text
}

$itemsDoc = (Get-GhText "gh project item-list" @("project", "item-list", "$number", "--owner", "$owner", "--limit", "$limitItems", "--format", "json")) | ConvertFrom-Json
$items = @($itemsDoc.items)
$total = [int]$itemsDoc.totalCount

$prJson = Get-GhText "gh pr list" @("pr", "list", "--repo", "$owner/$repo", "--state", "all", "--limit", "$limitPrs", "--json", "number,title,headRefName,state,isDraft,updatedAt,statusCheckRollup,closingIssuesReferences")
# ConvertFrom-Json may hand back the top-level array as one object; the pipeline through ForEach-Object unrolls it
$rawPrs = @($prJson | ConvertFrom-Json | ForEach-Object { $_ })

$projectId = ((Get-GhText "gh project view" @("project", "view", "$number", "--owner", "$owner", "--format", "json")) | ConvertFrom-Json).id
if (-not $projectId) { Die "gh project view did not give the project id" }
$query = 'query($id: ID!, $after: String) { node(id: $id) { ... on ProjectV2 { items(first: 100, after: $after) { pageInfo { hasNextPage endCursor } nodes { createdAt content { ... on Issue { number timelineItems(last: 1, itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT]) { nodes { ... on ProjectV2ItemStatusChangedEvent { createdAt } } } } } } } } } }'
$ageAt = @{}
$after = ""
for ($page = 1; $page -le 20; $page++) {
  $a = @("api", "graphql", "-f", "query=$query", "-f", "id=$projectId")
  if ($after) { $a += @("-f", "after=$after") }
  $doc = (Get-GhText "gh api graphql" $a) | ConvertFrom-Json
  $conn = $doc.data.node.items
  foreach ($node in @($conn.nodes)) {
    if (-not $node.content -or -not $node.content.number) { continue }
    $ev = @($node.content.timelineItems.nodes)
    if ($ev.Count -gt 0 -and $ev[0].createdAt) { $ageAt["$($node.content.number)"] = ToEpoch $ev[0].createdAt }
    elseif ($node.createdAt) { $ageAt["$($node.content.number)"] = ToEpoch $node.createdAt }
  }
  $after = [string]$conn.pageInfo.endCursor
  if (-not ($conn.pageInfo.hasNextPage -eq $true -and $after)) { break }
}

$hasSlots = [bool]$cfg.PSObject.Properties["worktrees"]
$busy = @()
$slotRows = @()
if ($hasSlots) {
  try { $lines = @(& (Join-Path $PSScriptRoot "slot.ps1") -Status -Porcelain) } catch { Die "slot.ps1 failed: $($_.Exception.Message)" }
  # the capacity line, with the text of slot.ps1 -Capacity (iteration 22)
  try { $capLines = @(& (Join-Path $PSScriptRoot "slot.ps1") -Capacity) } catch { Die "slot.ps1 failed: $($_.Exception.Message)" }
  $capSlots = (@($capLines | Where-Object { "$_" -like "slots: *" }) | Select-Object -First 1)
  $capAgents = (@($capLines | Where-Object { "$_" -like "agents: *" }) | Select-Object -First 1)
  $capLine = "capacity: " + ("$capSlots" -replace '^slots: ', 'slots ') + ", " + ("$capAgents" -replace '^agents: ', 'agents ')
  # every line of slot.ps1 -Status -Porcelain, in its order; a busy line has ten fields (iteration 23)
  foreach ($l in $lines) {
    $f = @(([string]$l) -split "`t")
    while ($f.Count -lt 10) { $f += "" }
    $row = [pscustomobject]@{ Slot = $f[0]; State = $f[1]; Busy = $null }
    if ($f[1] -eq "busy") {
      $since = [datetime]::ParseExact($f[3], "yyyy-MM-ddTHH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
      $b = [pscustomobject]@{ Slot = $f[0]; Branch = $f[2]; Since = ToEpoch ([datetime]::SpecifyKind($since, [DateTimeKind]::Utc))
        Agent = $f[5]; Skill = $f[6]; Role = $f[7]; Step = $f[8]; Reported = $f[9] }
      $busy += $b
      $row.Busy = $b
    }
    $slotRows += $row
  }
}

# ---- pull requests
function CiOf($checks) {
  $checks = @($checks)
  if ($checks.Count -eq 0) { return "none" }
  $pending = $false
  foreach ($c in $checks) {
    $conc = [string]$c.conclusion; $stat = [string]$c.status; $st = [string]$c.state
    if ($conc -in @("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED") -or $st -in @("FAILURE", "ERROR")) { return "fail" }
    if ($stat -in @("QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED") -or $st -in @("PENDING", "EXPECTED")) { $pending = $true }
  }
  if ($pending) { return "pending" }
  return "pass"
}
$prs = @()
foreach ($p in $rawPrs) {
  $state = "open"
  if ($p.state -eq "MERGED") { $state = "merged" } elseif ($p.state -eq "CLOSED") { $state = "closed" } elseif ($p.isDraft -eq $true) { $state = "draft" }
  $closes = @()
  foreach ($r in @($p.closingIssuesReferences)) { if ($r.number) { $closes += "$($r.number)" } }
  $prs += [pscustomobject]@{
    Num = "$($p.number)"; State = $state; Head = [string]$p.headRefName; Title = [string]$p.title
    When = (ToEpoch $p.updatedAt); Closes = $closes; Ci = (CiOf $p.statusCheckRollup)
  }
}

function Belongs($p, [string]$n) { return (($p.Closes -contains $n) -or $p.Title.Contains("(#$n)")) }
function IsSpec($p) { return ($specPrefix -ne "" -and $p.Head.StartsWith($specPrefix, [StringComparison]::Ordinal)) }
function Score($p) {
  if ($p.State -eq "open" -or $p.State -eq "draft") { return 3e12 + $p.When }
  if ($p.State -eq "merged") { return 2e12 + $p.When }
  return 1e12 + $p.When
}
function Pick([string]$n, [string]$want, [string]$branch) {
  $best = $null; $bs = -1
  foreach ($p in $prs) {
    if ($want -eq "head") { $ok = ($p.Head -ceq $branch) }
    else {
      $ok = Belongs $p $n
      if ($ok -and $want -eq "spec" -and -not (IsSpec $p)) { $ok = $false }
      if ($ok -and $want -eq "impl" -and (IsSpec $p)) { $ok = $false }
    }
    if (-not $ok) { continue }
    $sc = Score $p
    if ($sc -gt $bs) { $bs = $sc; $best = $p }
  }
  return $best
}
function CountPrs([string]$n, [string]$want, [string[]]$states) {
  $c = 0
  foreach ($p in $prs) {
    if (-not (Belongs $p $n)) { continue }
    if ($want -eq "spec" -and -not (IsSpec $p)) { continue }
    if ($want -eq "impl" -and (IsSpec $p)) { continue }
    if ($states -contains $p.State) { $c++ }
  }
  return $c
}
function PrCell($p) {
  if ($null -eq $p) { return "-" }
  if ($p.State -eq "open") { return "#$($p.Num) open, ci $($p.Ci)" }
  return "#$($p.Num) $($p.State)"
}

# ---- the table
# a value as printed: every C0 control and DEL removed (#134), so a title cannot drive the terminal; the tabs and
# line ends of the layout are added after this
function Clean($v) { return ([string]$v) -replace '[\x01-\x1F\x7F]', '' }
function Format-Table2($rows, [bool[]]$right) {
  $cols = $rows[0].Count
  foreach ($r in $rows) { for ($c = 0; $c -lt $cols; $c++) { $r[$c] = Clean $r[$c] } }
  $w = @(0) * $cols
  foreach ($r in $rows) { for ($c = 0; $c -lt $cols; $c++) { if ($r[$c].Length -gt $w[$c]) { $w[$c] = $r[$c].Length } } }
  foreach ($r in $rows) {
    $parts = @()
    for ($c = 0; $c -lt $cols; $c++) { if ($right[$c]) { $parts += $r[$c].PadLeft($w[$c]) } else { $parts += $r[$c].PadRight($w[$c]) } }
    Write-Output (($parts -join "  ").TrimEnd(" "))
  }
}

$hiddenBacklog = 0; $hiddenDone = 0
$shown = @()
$idx = 0
foreach ($it in $items) {
  $idx++
  if ($it.content.type -ne "Issue") { continue }
  if ($epic -and (@($it.labels) -contains $epic)) { continue }
  if (-not $rank.ContainsKey([string]$it.status)) { continue }
  if (-not $All -and ($it.status -eq $stBacklog -or $it.status -eq $stDone)) {
    if ($it.status -eq $stBacklog) { $hiddenBacklog++ } else { $hiddenDone++ }
    continue
  }
  $n = "$($it.content.number)"
  $age = 0
  if ($ageAt.ContainsKey($n)) { $age = $now - $ageAt[$n] }
  $shown += [pscustomobject]@{ Idx = $idx; Item = $it; N = $n; Rank = $rank[[string]$it.status]; Age = $age }
}
$shown = @($shown | Sort-Object -Property @{ Expression = "Rank"; Ascending = $true }, @{ Expression = "Age"; Descending = $true }, @{ Expression = "Idx"; Ascending = $true })

$slotOf = @{}
foreach ($b in $busy) { $slotOf[$b.Branch] = $b.Slot }

$rows = @(, @("#", "Title", "Status", "Who", "PR", "Age", "Flag"))
$porc = New-Object System.Collections.Generic.List[string]
foreach ($s in $shown) {
  $it = $s.Item; $n = $s.N; $st = [string]$it.status
  $title = (Clean $it.title) -replace '^\[(Story|Bug)\] ', ''
  if ($title.Length -gt 36) { $title = $title.Substring(0, 33) + "..." }
  $want = "impl"
  if ($st -eq $stSpec -or $st -eq $stSpecReview) { $want = "spec" }
  $k = Pick $n $want ""
  $who = ""
  if ($it.PSObject.Properties["assignees"] -and @($it.assignees).Count -gt 0) { $who = [string]@($it.assignees)[0] }
  if (-not $who) {
    foreach ($p in $prs) { if ((Belongs $p $n) -and $slotOf.ContainsKey($p.Head)) { $who = "slot $($slotOf[$p.Head])"; break } }
  }
  if (-not $who) { $who = "-" }
  $hasAge = $ageAt.ContainsKey($n)
  $young = ($s.Age -le $grace)
  $flag = ""
  if ($st -eq $stReview) {
    if ((CountPrs $n "impl" @("open", "draft", "merged", "closed")) -gt 0 -and (CountPrs $n "impl" @("open", "draft")) -eq 0 -and $k) {
      $flag = "stale: Review but the PR is $($k.State)"
    }
  } elseif ($st -eq $stInProgress) {
    if ((CountPrs $n "impl" @("open", "draft", "merged", "closed")) -eq 0 -and $busy.Count -eq 0 -and -not $young -and $hasAge) { $flag = "stale: In progress, no PR and no busy slot" }
  } elseif ($st -eq $stSpec) {
    if ((CountPrs $n "spec" @("open", "draft", "merged")) -eq 0 -and -not $young -and $hasAge) { $flag = "stale: Spec but no spec PR" }
  }
  $ageText = "-"
  if ($hasAge) { $ageText = Span $s.Age }
  $rows += , @($n, $title, $st, $who, (PrCell $k), $ageText, $flag)
  # porcelain: the whole decoded title, the prefix removed case-sensitively, every tab, CR and LF one space
  $whole = (([string]$it.title) -creplace '^\[(Story|Bug)\] ', '') -replace "[`t`r`n]", " "
  $porc.Add((@("item", $n, $st, $who, (PrCell $k), $ageText, $flag, $whole) | ForEach-Object { Clean $_ }) -join "`t") | Out-Null
}
if (-not $Porcelain) {
  if ($shown.Count -eq 0) { Write-Output "nothing to show at these statuses" }
  else { Format-Table2 $rows @($true, $false, $false, $false, $false, $true, $false) }
}

$hid = ""
if ($hiddenBacklog -gt 0) { $hid = "$hiddenBacklog at $stBacklog" }
if ($hiddenDone -gt 0) { if ($hid) { $hid += ", " }; $hid += "$hiddenDone at $stDone" }
$notes = @()
if ($total -gt $limitItems) { $notes += "the board has $total items, only the first $limitItems were read" }
if ($prs.Count -ge $limitPrs) { $notes += "only the $limitPrs most recent pull requests were read" }
if ($Porcelain) {
  foreach ($nt in $notes) { $porc.Add("note`t$nt") | Out-Null }
} else {
  if ($hid) { Write-Output "not shown: $(Clean $hid) (use --all)" }
  foreach ($nt in $notes) { Write-Output "note: $nt" }
}

if ($hasSlots) {
  # the Slots section (iteration 23): every slot, free and busy; the agent state is the slot script's
  if (-not $Porcelain) {
    Write-Output ""
    Write-Output "slots"
  }
  $srows = @(, @("slot", "State", "Agent", "Branch", "Skill", "Step", "Report", "Since", "PR", "Flag"))
  foreach ($row in $slotRows) {
    $b = $row.Busy
    if ($null -eq $b) { $srows += , @("$($row.Slot)", $row.State, "", "", "", "", "", "", "", ""); continue }
    $k = Pick "" "head" $b.Branch
    $sinceAge = $nowLocal - $b.Since
    $flag = ""
    if ($k) {
      if ($k.State -eq "merged") { $flag = "stale: busy, PR merged (slot --release $($b.Slot))" }
      elseif ($k.State -eq "closed") { $flag = "stale: busy, PR closed (slot --abandon $($b.Slot))" }
    } elseif ($sinceAge -gt $grace) { $flag = "stale: busy, no open PR" }
    if (-not $b.Skill -and -not $b.Role) { $who = "?" }
    else {
      $sk = if ($b.Skill) { $b.Skill } else { "?" }
      $ro = if ($b.Role) { $b.Role } else { "?" }
      $who = "$sk/$ro"
    }
    $step = if ($b.Step) { $b.Step } else { "?" }
    $rep = "-"
    if ($b.Reported -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\z') {
      $rep = Span ($nowLocal - (StampOf $b.Reported))
    }
    $srows += , @("$($b.Slot)", "busy", $b.Agent, $b.Branch, $who, $step, $rep, (Span $sinceAge), (PrCell $k), $flag)
  }
  if ($Porcelain) {
    for ($r = 1; $r -lt $srows.Count; $r++) { $porc.Add("slot`t" + (($srows[$r] | ForEach-Object { Clean $_ }) -join "`t")) | Out-Null }
    $porc.Add("capacity`t" + ($capLine -replace '^capacity: ', '')) | Out-Null
  } else {
    Format-Table2 $srows @($true, $false, $false, $false, $false, $false, $true, $true, $false, $false)
    Write-Output $capLine
  }
}
# a JSON string: " and \ escaped, every character below 0x20 as \u00xx, the rest as is (iteration 54 decision 10)
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
if ($asJson) {
  $jItems = @(); $jNotes = @(); $jSlots = @(); $jCap = "null"
  $itemKeys = @("number", "status", "who", "pr", "age", "flag", "title")
  $slotKeys = @("slot", "state", "agent", "branch", "skill", "step", "report", "since", "pr", "flag")
  foreach ($l in $porc) {
    $f = $l -split "`t"
    if ($f[0] -eq "item" -or $f[0] -eq "slot") {
      $keys = if ($f[0] -eq "item") { $itemKeys } else { $slotKeys }
      $parts = @()
      for ($c = 0; $c -lt $keys.Count; $c++) {
        $cell = if ($c + 1 -lt $f.Count) { $f[$c + 1] } else { "" }
        if ($c -eq 0) { $parts += ('"' + $keys[$c] + '":' + [string]([long]$cell)) }
        else { $parts += ('"' + $keys[$c] + '":' + (Get-JsonString $cell)) }
      }
      $obj = "{" + ($parts -join ",") + "}"
      if ($f[0] -eq "item") { $jItems += $obj } else { $jSlots += $obj }
    } elseif ($f[0] -eq "note") { $jNotes += (Get-JsonString $f[1]) }
    elseif ($f[0] -eq "capacity") { $jCap = Get-JsonString $f[1] }
  }
  $slotsText = "null"
  if ($hasSlots) { $slotsText = "[" + ($jSlots -join ",") + "]" } else { $jCap = "null" }
  $text = '{"items":[' + ($jItems -join ",") + '],"notes":[' + ($jNotes -join ",") + '],"slots":' + $slotsText + ',"capacity":' + $jCap + "}`n"
  [Console]::Out.Write($text)
  [Console]::Out.Flush()
} elseif ($Porcelain) {
  # every record ends with one LF, written once: Write-Output would end the lines with CRLF on Windows
  $text = ""
  foreach ($l in $porc) { $text += $l + "`n" }
  [Console]::Out.Write($text)
  [Console]::Out.Flush()
}
exit 0
} finally {
  if ($null -ne $prevOutputEncoding) { try { [Console]::OutputEncoding = $prevOutputEncoding } catch { } }
}

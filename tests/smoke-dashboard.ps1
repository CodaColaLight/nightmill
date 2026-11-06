# tests/smoke-dashboard.ps1 - dashboard.ps1 against fixtures and a fake gh (a gh.cmd first on the PATH that writes
# the fixture file's bytes unchanged): the page is rendered once (-Once) into a temporary folder of the test from
# tests/fixtures/dashboard/run-stall-old-free/ (and tests/fixtures/status/c), the slot markers are written from
# markers.txt and the clock is fixed (NIGHTMILL_NOW = 2026-11-05T12:00:00). The page must equal expected.html, the
# file smoke-dashboard.sh compares with, so both shells write the same bytes. No network; nothing sleeps.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$D = Join-Path $here "scripts\dashboard.ps1"
$S = Join-Path $here "scripts\status.ps1"
$FIX = Join-Path $here "tests\fixtures\dashboard\run-stall-old-free"
$SFIX = Join-Path $here "tests\fixtures\status"
$NOW = "1793880000"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-dash-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Read-Lf([string]$path) { ([IO.File]::ReadAllText($path, $utf8)) -replace "`r`n", "`n" }

try {
  $pages = Join-Path $tmp "pages"
  New-Item -ItemType Directory $pages | Out-Null
  $page = Join-Path $pages "nightmill-dashboard-acme-widgets.html"

  # the project: one config with four slots, in a throwaway repository
  $work = Join-Path $tmp "work"
  git init -q -b main $work
  New-Item -ItemType Directory (Join-Path $work ".claude") | Out-Null
  $withSlots = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" },
  "worktrees": { "root": "../wt", "slots": 4 }
}
'@
  $noSlots = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "labels": { "epic": "epic" },
  "git": { "baseBranch": "main", "specPrefix": "spec/" }
}
'@
  $cfgFile = Join-Path $work ".claude\nightmill.json"
  Write-Utf8 $cfgFile $withSlots
  $plain = Join-Path $tmp "plain"
  git init -q -b main $plain
  $nogit = Join-Path $tmp "nogit"
  New-Item -ItemType Directory $nogit | Out-Null

  # a fake gh: it answers from $env:GH_FIX with the file's bytes unchanged, logs every call, fails when GH_FAIL is set
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory $bin | Out-Null
  Write-Utf8 (Join-Path $bin "gh-fake.ps1") @'
Add-Content -Path $env:GH_LOG -Value ($args -join " ")
if ($env:GH_FAIL) { [Console]::Error.WriteLine("HTTP 401: bad credentials"); exit 1 }
$what = "$($args[0]) $($args[1])"
$file = switch ($what) {
  "project item-list" { "items.json" }
  "pr list" { "prs.json" }
  "api graphql" { "ages.json" }
  default { $null }
}
$o = [Console]::OpenStandardOutput()
if ($what -eq "project view") { $b = [Text.Encoding]::ASCII.GetBytes('{"id": "PVT_test", "number": 1}'); $o.Write($b, 0, $b.Length); $o.Flush(); exit 0 }
if (-not $file) { [Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')"); exit 1 }
$b = [IO.File]::ReadAllBytes((Join-Path $env:GH_FIX $file))
$o.Write($b, 0, $b.Length)
$o.Flush()
exit 0
'@
  Write-Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n"

  $wt = Join-Path $tmp "wt"
  function Set-Markers([string]$file) {
    if (Test-Path $wt) { Remove-Item -Recurse -Force $wt }
    New-Item -ItemType Directory (Join-Path $wt ".slots") | Out-Null
    foreach ($line in (Read-Lf $file) -split "`n") {
      if (-not $line) { continue }
      $f = $line -split "`t"
      $q = @($f | ForEach-Object { $_.Replace('\', '\\').Replace('"', '\"') })
      if ($f.Count -ge 7) {
        Write-Utf8 (Join-Path $wt ".slots\slot-$($f[0]).json") ("{`n  `"slot`": $($q[0]),`n  `"branch`": `"$($q[1])`",`n  `"since`": `"$($q[2])`",`n  `"skill`": `"$($q[3])`",`n  `"role`": `"$($q[4])`",`n  `"step`": `"$($q[5])`",`n  `"reported`": `"$($q[6])`"`n}`n")
      } else {
        Write-Utf8 (Join-Path $wt ".slots\slot-$($f[0]).json") ("{`n  `"slot`": $($q[0]),`n  `"branch`": `"$($q[1])`",`n  `"since`": `"$($q[2])`"`n}`n")
      }
    }
  }

  # Run-Child <script> <dir> <gh fixture> <temp folder> <arguments> [gh fails]: Out (bytes decoded), Err, Code
  function Run-Child([string]$script, [string]$dir, [string]$fix, [string]$tdir, [string]$extra = "", [bool]$ghFails = $false) {
    $log = Join-Path $tmp "gh.log"
    Write-Utf8 $log ""
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $extra"
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = $utf8
    $psi.EnvironmentVariables["PATH"] = "$bin;" + $env:PATH
    $psi.EnvironmentVariables["GH_FIX"] = $fix
    $psi.EnvironmentVariables["GH_LOG"] = $log
    $psi.EnvironmentVariables["NIGHTMILL_NOW"] = $NOW
    $psi.EnvironmentVariables["TMP"] = $tdir
    $psi.EnvironmentVariables["TEMP"] = $tdir
    $psi.EnvironmentVariables["TMPDIR"] = $tdir
    if ($ghFails) { $psi.EnvironmentVariables["GH_FAIL"] = "1" } else { $psi.EnvironmentVariables.Remove("GH_FAIL") }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $script:OutRaw = $utf8.GetString($ms.ToArray())
    $script:Out = $script:OutRaw -replace "`r`n", "`n"
    $script:Err = ($errTask.Result) -replace "`r`n", "`n"
    $script:Code = $p.ExitCode
  }
  function Run-D([string]$dir, [string]$fix, [string]$tdir, [string]$extra = "", [bool]$ghFails = $false) { Run-Child $D $dir $fix $tdir $extra $ghFails }
  function Page { return [IO.File]::ReadAllText($page, $utf8) }
  function Has([string]$w, [string]$name) { if (-not (Page).Contains($w)) { Fail "$name`: the page does not hold: $w" } }
  function HasNot([string]$w, [string]$name) { if ((Page).Contains($w)) { Fail "$name`: the page holds: $w" } }
  function Count([string]$w) { $t = Page; $n = 0; $i = 0; while (($i = $t.IndexOf($w, $i, [StringComparison]::Ordinal)) -ge 0) { $n++; $i += $w.Length }; return $n }
  function RowOf([string]$prefix) { return @((Page) -split "`n" | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) }) }
  function SlotRowOf([string]$n) { return @(RowOf "<tr><td class=`"num`">$n</td>" | Where-Object { $_ -cmatch "^<tr><td class=`"num`">$n</td><td( class=`"free`")?>(busy|free)</td>" }) }

  Set-Markers (Join-Path $FIX "markers.txt")
  $gitBefore = (git -C $work status --porcelain --untracked-files=all) -join "`n"
  function MarkerBytes { return @(Get-ChildItem (Join-Path $wt ".slots") | Sort-Object Name | ForEach-Object { $_.Name + ":" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) }) -join " " }
  $marksBefore = MarkerBytes

  Write-Host "== the page names every slot"
  Run-D $work $FIX $pages "-Once"
  if ($Code -ne 0) { Fail "exit code $Code`: $Err" }
  if ($Err) { Fail "something on standard error: $Err" }
  if (-not (Test-Path -LiteralPath $page)) { Fail "no page at $page" }
  $outLines = @($Out.TrimEnd("`n") -split "`n")
  if ($outLines.Count -ne 2) { Fail "standard output is not two lines: $Out" }
  if ($outLines[0] -cne "dashboard: wrote $page") { Fail "the first line: $($outLines[0])" }
  if ($outLines[1] -cnotmatch '^dashboard: open file:///.*/nightmill-dashboard-acme-widgets\.html in a browser$') { Fail "the second line: $($outLines[1])" }
  $want = Read-Lf (Join-Path $FIX "expected.html")
  $got = Page
  if ($got -cne $want) {
    Write-Host "--- expected"; Write-Host $want; Write-Host "--- got"; Write-Host $got
    Fail "the page differs from expected.html"
  }
  foreach ($n in "1", "2", "3", "4") { if (@(SlotRowOf $n).Count -ne 1) { Fail "slot $n is not one row of the slot table" } }

  Write-Host "== each state is a word and a colour"
  foreach ($w in '<td class="running">running</td>', '<td class="stalled">stalled</td>', '<td class="unknown">unknown</td>',
    '<td class="free">free</td>', '<td class="flagged">stale: busy, no open PR</td>', '<td class="flagged">stale: busy, PR merged (slot --release 3)</td>') {
    Has $w "states"
  }

  Write-Host "== what waits"
  $t = Page
  $i2 = $t.IndexOf('<tr><td class="num">2</td><td>Read the', [StringComparison]::Ordinal)
  $i3 = $t.IndexOf('<tr><td class="num">3</td><td>Approved and waiting', [StringComparison]::Ordinal)
  $i6 = $t.IndexOf('<tr><td class="num">6</td><td>Path', [StringComparison]::Ordinal)
  if (-not ($i2 -ge 0 -and $i3 -gt $i2 -and $i6 -gt $i3)) { Fail "the items are not 2, 3, 6 in that order: $i2 $i3 $i6" }
  HasNot 'Busy one' "what waits"
  HasNot 'At review' "what waits"
  if (-not @(RowOf '<tr><td class="num">2</td><td>Read')[0].Contains('<td>#31 open, ci pass</td><td class="num">5h</td>')) { Fail "item 2: the PR and age cells" }
  if (-not @(RowOf '<tr><td class="num">3</td><td>Approved')[0].Contains('<td>Approved</td><td>-</td><td class="num">2d</td>')) { Fail "item 3: the PR and age cells" }
  Has '<p>capacity: slots 4 (config), agents 2 (default)</p>' "what waits"

  Write-Host "== hostile text is escaped"
  Has 'feat/&lt;b&gt;&amp;&#39;x' "escaping"
  Has ('Read the &lt;b&gt;spec&lt;/b&gt; &amp; &quot;approve&quot; ' + [char]0x2014 + ' caf' + [char]0xE9) "escaping"
  HasNot '<b>' "escaping"
  HasNot 'feat/<b' "escaping"

  Write-Host "== a title is decoded before the tab becomes a space"
  Run-Child $S $work $FIX $pages "-Porcelain"
  if ($Code -ne 0) { Fail "status.ps1 -Porcelain: exit code $Code`: $Err" }
  if (@($OutRaw -split "`n") -cnotcontains "item`t6`tApproved`t-`t-`t1d`t`tPath C:\temp and more") { Fail "the item 6 line: $OutRaw" }
  Has '<tr><td class="num">6</td><td>Path C:\temp and more</td><td>Approved</td><td>-</td><td class="num">1d</td></tr>' "title"
  HasNot 'temp\tand' "title"
  HasNot 'C:\\temp' "title"
  HasNot "C:\`temp" "title"

  Write-Host "== self-contained and read-only"
  Run-D $work $FIX $pages "-Once"
  if ((Count '<script>') -ne 1) { Fail "not exactly one <script>" }
  if ((Count '<meta http-equiv="refresh" content="60">') -ne 1) { Fail "not exactly one refresh of 60" }
  foreach ($w in 'data-every="60"', 'data-epoch="1793880000"', 'Rendered at 2026-11-05 12:00:00', '(worktrees.stalledAfterMinutes)', '30 minutes') { Has $w "self-contained" }
  foreach ($w in '<link', 'src=', 'href', '@import', 'url(', 'http://', 'https://', '<form', '<button', '<input', '<a ', 'fetch(', 'XMLHttpRequest', 'WebSocket', 'localStorage', 'sessionStorage') { HasNot $w "self-contained" }
  $log = @((Read-Lf (Join-Path $tmp "gh.log")) -split "`n" | Where-Object { $_ -ne "" })
  foreach ($c in "project item-list", "project view", "pr list", "api graphql") {
    if (-not ($log | Where-Object { $_.StartsWith("$c ") })) { Fail "gh $c was never called" }
  }
  foreach ($l in $log) { if ($l -cnotmatch '^(project item-list|project view|pr list|api graphql) ') { Fail "another gh call: $l" } }
  if (($log -join "`n") -match 'item-edit|item-add|item-archive|pr merge|issue edit|issue comment|issue close|mutation') { Fail "the dashboard changed something" }

  Write-Host "== gh cannot be read"
  Run-D $work $FIX $pages "-Once" $true
  if ($Code -ne 0) { Fail "a failing gh: exit code $Code`: $Err" }
  Has '<p class="unknown">unknown: the board could not be read (' "gh fails"
  Has 'HTTP 401: bad credentials)' "gh fails"
  Has '<p class="unknown">unknown: the pull requests, CI and flags of the slots could not be read (' "gh fails"
  foreach ($w in '<td class="running">running</td>', '<td class="stalled">stalled</td>', '<td class="unknown">unknown</td>', '<td class="free">free</td>',
    '<td class="num">2026-11-05T11:55:00</td><td class="num">2026-11-05T10:00:00</td>', '<p class="unknown">capacity: unknown</p>') { Has $w "gh fails" }
  foreach ($n in "1", "2", "3") {
    $row = @(SlotRowOf $n)
    if ($row.Count -ne 1 -or -not $row[0].EndsWith('<td class="unknown">unknown</td><td class="unknown">unknown</td></tr>')) { Fail "gh fails: slot $n has no unknown PR and Flag" }
    if ($row[0].Contains('<td class="free">')) { Fail "gh fails: slot $n is shown free" }
  }
  HasNot 'Nothing waits' "gh fails"

  Write-Host "== an unreadable marker is never free"
  Write-Utf8 (Join-Path $wt ".slots\slot-2.json") "{ not json"
  Run-D $work $FIX $pages "-Once"
  if ($Code -ne 0) { Fail "an unreadable marker: exit code $Code`: $Err" }
  HasNot '<td class="num">2</td><td class="free">free</td>' "unreadable marker"
  # slot.ps1 fails on the marker, so status.ps1 and the fallback both fail: both parts say unknown
  Has '<p class="unknown">unknown: the slots could not be read (' "unreadable marker"
  Has '<p class="unknown">unknown: the board could not be read (' "unreadable marker"
  Set-Markers (Join-Path $FIX "markers.txt")

  Write-Host "== nothing waits"
  Set-Markers (Join-Path $SFIX "c\markers.txt")
  Run-D $work (Join-Path $SFIX "c") $pages "-Once"
  if ($Code -ne 0) { Fail "nothing waits: exit code $Code`: $Err" }
  Has '<p>Nothing waits for you: no item at Spec review or Approved.</p>' "nothing waits"
  foreach ($row in '<tr><td class="num">1</td><td>busy</td><td class="stalled">stalled</td><td>feat/merged</td>',
    '<tr><td class="num">2</td><td>busy</td><td class="unknown">unknown</td><td>feat/closed</td>',
    '<tr><td class="num">3</td><td>busy</td><td class="stalled">stalled</td><td>feat/stale</td>',
    '<tr><td class="num">4</td><td>busy</td><td class="running">running</td><td>feat/new</td>') { Has $row "nothing waits" }

  Write-Host "== not all items read is not nothing waits"
  $c250 = Join-Path $tmp "c250"
  Copy-Item -Recurse (Join-Path $SFIX "c") $c250
  $items = (Read-Lf (Join-Path $SFIX "c\items.json")).Replace('"totalCount": 1', '"totalCount": 250')
  if (-not $items.Contains('"totalCount": 250')) { Fail "the fixture copy has no totalCount 250" }
  Write-Utf8 (Join-Path $c250 "items.json") $items
  Run-D $work $c250 $pages "-Once"
  Has '<p class="unknown">unknown: no item at Spec review or Approved among the items read; not all board items were read.</p>' "partial board"
  Has '<li>the board has 250 items, only the first 200 were read</li>' "partial board"
  HasNot 'Nothing waits' "partial board"
  Set-Markers (Join-Path $FIX "markers.txt")

  Write-Host "== without worktrees"
  Write-Utf8 $cfgFile $noSlots
  Run-D $work $FIX $pages "-Once"
  if ($Code -ne 0) { Fail "without worktrees: exit code $Code`: $Err" }
  Has '<p>No slots: .claude/nightmill.json has no worktrees section.</p>' "without worktrees"
  Has '<tr><td class="num">2</td><td>Read the' "without worktrees"
  Has '<tr><td class="num">3</td><td>Approved and waiting' "without worktrees"
  HasNot '<th>slot</th>' "without worktrees"
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== the interval is a config value"
  function With-Refresh([string]$v) { Write-Utf8 $cfgFile $withSlots.Replace('"slots": 4 }', "`"slots`": 4, `"dashboardRefreshSeconds`": $v }") }
  With-Refresh "15"
  Run-D $work $FIX $pages "-Once"
  if ($Code -ne 0) { Fail "refresh 15: exit code $Code`: $Err" }
  if ($Err) { Fail "refresh 15: something on standard error: $Err" }
  foreach ($w in 'content="15"', 'data-every="15"', 'reloads every 15 s', 'more than 45 s') { Has $w "refresh 15" }
  foreach ($v in "0", "9", "3601", "2.5", "60.0", '"60"', "true") {
    With-Refresh $v
    Run-D $work $FIX $pages "-Once"
    if ($Code -ne 0) { Fail "refresh $v`: exit code $Code" }
    if ($Err.TrimEnd("`n") -cne "dashboard: worktrees.dashboardRefreshSeconds must be a whole number from 10 to 3600; using 60") { Fail "refresh $v`: the warning: $Err" }
    Has 'content="60"' "refresh $v"
  }
  With-Refresh "null"
  Run-D $work $FIX $pages "-Once"
  if ($Err) { Fail "refresh null: a warning: $Err" }
  Has 'content="60"' "refresh null"
  Write-Utf8 $cfgFile $withSlots

  Write-Host "== errors"
  $errPages = Join-Path $tmp "errpages"
  New-Item -ItemType Directory $errPages | Out-Null
  foreach ($a in "--nope", "--help", "-Once extra") {
    Run-D $work $FIX $errPages $a
    if ($Code -ne 2) { Fail "$a`: exit code $Code" }
    if ($Err -cnotmatch '(?m)^usage: dashboard\.ps1 \[-Once\]$') { Fail "$a`: no usage line: $Err" }
  }
  Run-D $nogit $FIX $errPages "-Once"
  if ($Code -ne 2 -or -not $Err.Contains("from inside a checkout")) { Fail "outside a checkout: $Code $Err" }
  Run-D $plain $FIX $errPages "-Once"
  if ($Code -ne 2 -or -not $Err.Contains("run /nightmill:init")) { Fail "no config: $Code $Err" }
  Write-Utf8 $cfgFile $withSlots.Replace('"repo": "widgets", ', '')
  Run-D $work $FIX $errPages "-Once"
  if ($Code -ne 2 -or -not $Err.Contains("github.owner and github.repo are needed")) { Fail "no repo: $Code $Err" }
  Write-Utf8 $cfgFile $withSlots
  if (@(Get-ChildItem -Force $errPages).Count -ne 0) { Fail "an error case wrote a page" }

  Write-Host "== a page that cannot be written"
  # Windows PowerShell creates a missing TEMP folder when it starts, so the folder named here lies under a plain file:
  # it does not exist and cannot be created
  $blocker = Join-Path $tmp "blocker"
  Write-Utf8 $blocker "x"
  $missing = Join-Path $blocker "missing"
  Run-D $work $FIX $missing "-Once"
  if ($Code -ne 1) { Fail "a missing temporary folder: exit code $Code`: $Err" }
  $errLines = @($Err.TrimEnd("`n") -split "`n")
  if ($errLines.Count -ne 1) { Fail "not one line on standard error: $Err" }
  if (-not $errLines[0].StartsWith("dashboard: cannot write $(Join-Path $missing 'nightmill-dashboard-acme-widgets.html'): ")) { Fail "the message: $Err" }
  if (Test-Path -LiteralPath $missing) { Fail "the missing folder was created" }
  if ([IO.File]::ReadAllText($blocker) -cne "x") { Fail "the file under the missing folder changed" }
  Remove-Item -LiteralPath $blocker

  Write-Host "== the address is percent-encoded"
  $spaced = Join-Path $tmp "my pages"
  New-Item -ItemType Directory $spaced | Out-Null
  Run-D $work $FIX $spaced "-Once"
  if ($Code -ne 0) { Fail "a temporary folder with a space: exit code $Code`: $Err" }
  if (-not $Out.Contains("my%20pages/nightmill-dashboard-acme-widgets.html in a browser")) { Fail "the space is not %20: $Out" }
  Remove-Item -Recurse -Force $spaced

  Write-Host "== nothing is written in the project or the slots"
  if (((git -C $work status --porcelain --untracked-files=all) -join "`n") -cne $gitBefore) { Fail "git status changed" }
  if ((MarkerBytes) -cne $marksBefore) { Fail "a marker changed or .slots holds another file" }
  $left = @(Get-ChildItem -Force $pages | ForEach-Object { $_.Name })
  if ($left.Count -ne 1 -or $left[0] -cne "nightmill-dashboard-acme-widgets.html") { Fail "the temporary folder holds more than the page: $($left -join ', ')" }

  Write-Host "DASHBOARD OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

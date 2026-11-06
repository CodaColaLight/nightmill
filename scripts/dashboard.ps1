# scripts/dashboard.ps1 - a page in the browser with the slots and what waits for the maintainer (nightmill).
#
#   dashboard.ps1           rewrite the page every worktrees.dashboardRefreshSeconds seconds until Ctrl-C
#   dashboard.ps1 -Once     render it once and exit
#
# Read-only. Each render runs status.ps1 -Porcelain once in a child PowerShell (the cells of /status, from the same
# code) and, when that fails, slot.ps1 -Status -Porcelain (no network), and writes one self-contained HTML page to
# <temp>\nightmill-dashboard-<owner>-<repo>.html; the page reloads itself. It never calls the GitHub CLI itself,
# starts no server and opens no browser: it prints the file:// address to open once.
# Run it from inside the project: any checkout or worktree of it. The rules are in
# docs/specs/iteration-31-dashboard.md; dashboard.sh (with lib/dashboard.awk) writes the same page.
# Exit code 0 after -Once wrote the page, 1 when the page could not be written the first time, 2 for a usage error,
# no checkout, no or invalid config, no owner or repo.
# $env:NIGHTMILL_NOW (seconds since 1970) fixes the clock of the page and of the child scripts; the smoke test uses it.
param(
  [switch]$Once,
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"

function Die([string]$msg) { [Console]::Error.WriteLine("dashboard: $msg"); exit 2 }
if ($Rest) { [Console]::Error.WriteLine("usage: dashboard.ps1 [-Once]"); exit 2 }

$utf8 = New-Object System.Text.UTF8Encoding $false
$gitDir = $null
try { $gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null } catch { $gitDir = $null }
if ($LASTEXITCODE -ne 0 -or -not $gitDir) { Die "run dashboard.ps1 from inside a checkout of the project" }
$main = Split-Path ([string]$gitDir).Trim() -Parent
$cfgPath = Join-Path $main ".claude\nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath)) { Die "no $cfgPath (run /nightmill:init)" }
try { $cfg = [IO.File]::ReadAllText($cfgPath, $utf8) | ConvertFrom-Json } catch { Die "${cfgPath}: $($_.Exception.Message)" }

function Cfg($obj, [string[]]$path, $default) {
  foreach ($k in $path) {
    if ($null -eq $obj -or -not ($obj -is [System.Management.Automation.PSCustomObject])) { return $default }
    $p = $obj.PSObject.Properties[$k]
    if (-not $p) { return $default }
    $obj = $p.Value
  }
  if ($null -eq $obj -or "$obj" -eq "") { return $default }
  return $obj
}

$owner = [string](Cfg $cfg @("github", "owner") "")
$repo = [string](Cfg $cfg @("github", "repo") "")
if (-not $owner -or -not $repo) { Die "github.owner and github.repo are needed in $cfgPath" }

# the settings, read once at the start
$hasWt = [bool]($cfg -is [System.Management.Automation.PSCustomObject] -and $cfg.PSObject.Properties["worktrees"])
$wt = $null
if ($hasWt -and $cfg.worktrees -is [System.Management.Automation.PSCustomObject]) { $wt = $cfg.worktrees }
$every = 60
if ($wt) {
  $p = $wt.PSObject.Properties["dashboardRefreshSeconds"]
  if ($p -and $null -ne $p.Value) {
    $v = $p.Value
    if (($v -is [int] -or $v -is [long]) -and $v -ge 10 -and $v -le 3600) { $every = [int]$v }
    else { [Console]::Error.WriteLine("dashboard: worktrees.dashboardRefreshSeconds must be a whole number from 10 to 3600; using 60") }
  }
}
# worktrees.stalledAfterMinutes for the legend only (the slot script's note reaches the page's notes)
$stalled = 30
if ($wt) {
  $p = $wt.PSObject.Properties["stalledAfterMinutes"]
  if ($p -and ($p.Value -is [int] -or $p.Value -is [long]) -and $p.Value -ge 1 -and $p.Value -le 999999) { $stalled = [long]$p.Value }
}
$sr = [string](Cfg $cfg @("board", "statuses", "specReview") "Spec review")
$ap = [string](Cfg $cfg @("board", "statuses", "approved") "Approved")

# the page: in the temporary folder, one per project, the same file on every start
$safeOwner = $owner -replace '[^A-Za-z0-9._-]', '_'
$safeRepo = $repo -replace '[^A-Za-z0-9._-]', '_'
$page = [IO.Path]::Combine([IO.Path]::GetTempPath(), "nightmill-dashboard-$safeOwner-$safeRepo.html")
$upath = ([IO.Path]::GetFullPath($page)).Replace('\', '/')
if (-not $upath.StartsWith('/')) { $upath = '/' + $upath }
$enc = New-Object System.Text.StringBuilder
foreach ($b in $utf8.GetBytes($upath)) {
  $c = [char]$b
  if ($b -lt 128 -and "$c" -cmatch '^[A-Za-z0-9._~/:-]$') { [void]$enc.Append($c) } else { [void]$enc.Append(('%{0:X2}' -f $b)) }
}
$url = "file://" + $enc.ToString()

$psExe = (Get-Process -Id $PID).Path
$statusPs = Join-Path $PSScriptRoot "status.ps1"
$slotPs = Join-Path $PSScriptRoot "slot.ps1"
$script:child = $null
$script:pending = $null

# Invoke-Child <arguments>: a child PowerShell, both streams read as UTF-8 with ReadToEndAsync, waited for in steps of
# half a second (so that Ctrl-C ends a render that waits); an object with Code, Out, Err and Why (could not start)
function Invoke-Child([string]$arguments) {
  $r = [pscustomobject]@{ Code = $null; Out = ""; Err = ""; Why = "" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = $arguments
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $psi.WorkingDirectory = (Get-Location).ProviderPath
  try { $p = [System.Diagnostics.Process]::Start($psi) } catch { $r.Why = ($_.Exception.Message -replace "[`r`n]+", " "); return $r }
  $script:child = $p
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  while (-not $p.WaitForExit(500)) { }
  $p.WaitForExit()
  $r.Out = $outTask.Result
  $r.Err = $errTask.Result
  $r.Code = $p.ExitCode
  $script:child = $null
  $p.Dispose()
  return $r
}

# the lines of a stream: split at LF, one trailing CR removed from every line; a last empty piece is dropped
function Split-Lines([string]$s) {
  if (-not $s) { return @() }
  $a = @($s -split "`n")
  if ($a[$a.Count - 1] -eq "") { if ($a.Count -eq 1) { return @() }; $a = $a[0..($a.Count - 2)] }
  return @($a | ForEach-Object { if ($_.EndsWith("`r")) { $_.Substring(0, $_.Length - 1) } else { $_ } })
}

# the reason a child failed: its first non-empty line of standard error without trailing spaces, else its exit code
function Get-Reason($r, [string]$name) {
  if ($r.Why) { return $r.Why }
  foreach ($l in @(Split-Lines $r.Err)) {
    $t = $l.TrimEnd(' ')
    if ($t) { return $t }
  }
  return "$name exited with code $($r.Code)"
}

# the HTML escaping of every value from outside: & < > " ' and every control character to one space, in this order
function Esc([string]$s) {
  $s = $s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;").Replace("'", "&#39;")
  return [regex]::Replace($s, '[\x00-\x1F\x7F]', ' ')
}

function Td([string]$s) { return "<td>" + (Esc $s) + "</td>" }
function AgentTd([string]$s) {
  if ($s -ceq "running" -or $s -ceq "stalled" -or $s -ceq "unknown") { return "<td class=`"$s`">$s</td>" }
  return "<td class=`"unknown`">" + (Esc $s) + "</td>"
}

# one row of the slot table from ten cells; $null in PR or Flag is unknown (the fallback form)
function SlotRow($C) {
  $row = "<tr><td class=`"num`">" + (Esc $C[0]) + "</td>"
  if ($C[1] -ceq "free") {
    return $row + "<td class=`"free`">free</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>"
  }
  $row += (Td $C[1]) + (AgentTd $C[2]) + (Td $C[3]) + (Td $C[4]) + (Td $C[5])
  $row += "<td class=`"num`">" + (Esc $C[6]) + "</td><td class=`"num`">" + (Esc $C[7]) + "</td>"
  if ($null -eq $C[8]) { $row += "<td class=`"unknown`">unknown</td>" } else { $row += (Td $C[8]) }
  if ($null -eq $C[9]) { $row += "<td class=`"unknown`">unknown</td>" }
  elseif ($C[9] -ne "") { $row += "<td class=`"flagged`">" + (Esc $C[9]) + "</td>" }
  else { $row += "<td></td>" }
  return $row + "</tr>"
}

function Build-Page {
  $st = Invoke-Child "-NoProfile -ExecutionPolicy Bypass -File `"$statusPs`" -Porcelain"
  $stOk = ($null -eq $st.Why -or $st.Why -eq "") -and $st.Code -eq 0
  $notes = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Generic.List[object]
  $slots = New-Object System.Collections.Generic.List[object]
  $capacity = ""
  $partial = $false
  $slOk = $false
  $stReason = ""; $slReason = ""
  if ($stOk) {
    foreach ($l in @(Split-Lines $st.Out)) {
      $f = @($l -split "`t")
      while ($f.Count -lt 11) { $f += "" }
      if ($f[0] -ceq "item") {
        if ($f[2] -ceq $sr -or $f[2] -ceq $ap) { $items.Add($f) }
      } elseif ($f[0] -ceq "note") {
        $notes.Add($f[1])
        if ($f[1].StartsWith("the board has ", [StringComparison]::Ordinal) -and $f[1].Contains(", only the first ")) { $partial = $true }
      } elseif ($f[0] -ceq "slot") {
        $slots.Add(@($f[1], $f[2], $f[3], $f[4], $f[5], $f[6], $f[7], $f[8], $f[9], $f[10]))
      } elseif ($f[0] -ceq "capacity") { $capacity = $f[1] }
    }
    foreach ($l in @(Split-Lines $st.Err)) { if ($l -ne "") { $notes.Add($l) } }
  } else {
    $stReason = Get-Reason $st "status.ps1"
    if ($hasWt) {
      $quoted = $slotPs.Replace("'", "''")
      $sl = Invoke-Child "-NoProfile -ExecutionPolicy Bypass -Command `"[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding `$false; & '$quoted' -Status -Porcelain; exit `$LASTEXITCODE`""
      $slOk = (-not $sl.Why) -and $sl.Code -eq 0
      if ($slOk) {
        foreach ($l in @(Split-Lines $sl.Out)) {
          $f = @($l -split "`t")
          while ($f.Count -lt 10) { $f += "" }
          # the fallback form: the cells by the rule of the Slots section, times as written, PR and Flag unknown
          if ($f[1] -ceq "free") { $slots.Add(@($f[0], "free", "", "", "", "", "", "", "", "")); continue }
          if ($f[6] -eq "" -and $f[7] -eq "") { $who = "?" }
          else {
            $sk = $f[6]; if ($sk -eq "") { $sk = "?" }
            $ro = $f[7]; if ($ro -eq "") { $ro = "?" }
            $who = "$sk/$ro"
          }
          $step = $f[8]; if ($step -eq "") { $step = "?" }
          $rep = $f[9]; if ($rep -eq "") { $rep = "-" }
          $slots.Add(@($f[0], $f[1], $f[5], $f[2], $who, $step, $rep, $f[3], $null, $null))
        }
        foreach ($l in @(Split-Lines $sl.Err)) { if ($l -ne "") { $notes.Add($l) } }
      } else { $slReason = Get-Reason $sl "slot.ps1" }
    }
  }

  if ($env:NIGHTMILL_NOW) {
    $epoch = [long]$env:NIGHTMILL_NOW
    $when = [DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
  } else {
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $when = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
  }
  $title = (Esc $owner) + "/" + (Esc $repo)
  $sb = New-Object System.Text.StringBuilder
  function L([string]$s) { [void]$sb.Append($s).Append("`n") }
  L '<!DOCTYPE html>'
  L '<html lang="en">'
  L '<head>'
  L '<meta charset="utf-8">'
  L ('<meta http-equiv="refresh" content="' + $every + '">')
  L ('<title>nightmill: ' + $title + '</title>')
  L '<style>'
  L 'body { font-family: system-ui, sans-serif; margin: 1.5em; color: #1f2937; }'
  L 'table { border-collapse: collapse; margin: 0.5em 0; }'
  L 'th, td { border: 1px solid #d1d5db; padding: 0.25em 0.6em; text-align: left; white-space: nowrap; }'
  L 'th { background: #f3f4f6; }'
  L '.num { text-align: right; }'
  L '.running { background: #dcfce7; color: #14532d; }'
  L '.stalled { background: #fef3c7; color: #78350f; font-weight: bold; }'
  L '.unknown { background: #e5e7eb; color: #374151; font-style: italic; }'
  L '.free { color: #6b7280; }'
  L '.flagged { background: #fee2e2; color: #7f1d1d; font-weight: bold; }'
  L '</style>'
  L '</head>'
  L '<body>'
  L ('<h1>nightmill: ' + $title + '</h1>')
  L ('<p id="rendered" data-epoch="' + $epoch + '" data-every="' + $every + '">Rendered at ' + (Esc $when) + '<span id="ago"></span>; the page reloads every ' + $every + ' s.</p>')
  L ('<p id="stale" class="flagged" hidden>Out of date: this page has not been rewritten for more than ' + (3 * $every) + ' s. Is the dashboard script still running?</p>')
  L '<h2>Slots</h2>'
  $header = '<tr><th>slot</th><th>State</th><th>Agent</th><th>Branch</th><th>Skill</th><th>Step</th><th>Report</th><th>Since</th><th>PR</th><th>Flag</th></tr>'
  if (-not $hasWt) { L '<p>No slots: .claude/nightmill.json has no worktrees section.</p>' }
  elseif ($stOk) {
    L '<table>'; L $header
    foreach ($c in $slots) { L (SlotRow $c) }
    L '</table>'
    L ('<p>capacity: ' + (Esc $capacity) + '</p>')
  } elseif ($slOk) {
    L ('<p class="unknown">unknown: the pull requests, CI and flags of the slots could not be read (' + (Esc $stReason) + ')</p>')
    L '<table>'; L $header
    foreach ($c in $slots) { L (SlotRow $c) }
    L '</table>'
    L '<p class="unknown">capacity: unknown</p>'
  } else { L ('<p class="unknown">unknown: the slots could not be read (' + (Esc $slReason) + ')</p>') }
  L '<h2>Waiting for you</h2>'
  if (-not $stOk) { L ('<p class="unknown">unknown: the board could not be read (' + (Esc $stReason) + ')</p>') }
  elseif ($items.Count -gt 0) {
    L '<table>'
    L '<tr><th>#</th><th>Title</th><th>Status</th><th>PR</th><th>Age</th></tr>'
    foreach ($f in $items) {
      L ('<tr><td class="num">' + (Esc $f[1]) + '</td>' + (Td $f[7]) + (Td $f[2]) + (Td $f[4]) + '<td class="num">' + (Esc $f[5]) + '</td></tr>')
    }
    L '</table>'
  } elseif ($partial) { L ('<p class="unknown">unknown: no item at ' + (Esc $sr) + ' or ' + (Esc $ap) + ' among the items read; not all board items were read.</p>') }
  else { L ('<p>Nothing waits for you: no item at ' + (Esc $sr) + ' or ' + (Esc $ap) + '.</p>') }
  if ($notes.Count -gt 0) {
    L '<h2>Notes</h2>'
    L '<ul>'
    foreach ($n in $notes) { L ('<li>' + (Esc $n) + '</li>') }
    L '</ul>'
  }
  $m = $stalled
  L '<h2>What the words mean</h2>'
  L '<ul>'
  L ('<li><span class="running">running</span>: the agent in a busy slot reported a step within the last ' + $m + ' minutes (worktrees.stalledAfterMinutes).</li>')
  L ('<li><span class="stalled">stalled</span>: no report for more than ' + $m + ' minutes. The session may have ended, crashed or been abandoned, or one step runs long; a slot whose run is over (step done) and that waits for its merge shows it too. Look at it: nothing is stopped or freed.</li>')
  L '<li><span class="unknown">unknown</span>: a busy slot without a report (taken by hand or by an older version), or a value this page could not read. It is never taken as free or done.</li>'
  L '<li><span class="free">free</span>: no agent works in the slot.</li>'
  L '<li><span class="flagged">stale: ...</span>: flagged as /status flags it: a busy slot whose pull request merged or closed, or that has none after 2 hours.</li>'
  L '</ul>'
  L '<script>'
  L '(function () {'
  L '  var r = document.getElementById("rendered");'
  L '  var t = Number(r.getAttribute("data-epoch")), every = Number(r.getAttribute("data-every"));'
  L '  function tick() {'
  L '    var ago = Math.max(0, Math.floor(Date.now() / 1000 - t));'
  L '    document.getElementById("ago").textContent = ", " + ago + " s ago";'
  L '    document.getElementById("stale").hidden = ago <= 3 * every;'
  L '  }'
  L '  tick();'
  L '  setInterval(tick, 1000);'
  L '})();'
  L '</script>'
  L '</body>'
  L '</html>'
  return $sb.ToString()
}

# Write-Page <text>: through a sibling temporary file moved over the page; $false with one line when it fails
function Write-Page([string]$text) {
  $tmpf = "$page.$PID.tmp"
  $script:pending = $tmpf
  try {
    [IO.File]::WriteAllText($tmpf, $text, $utf8)
    if (Test-Path -LiteralPath $page) { [System.IO.File]::Replace($tmpf, $page, [NullString]::Value) }
    else { [System.IO.File]::Move($tmpf, $page) }
    $script:pending = $null
    return $true
  } catch {
    $msg = ($_.Exception.Message -replace "[`r`n]+", " ").Trim()
    try { if (Test-Path -LiteralPath $tmpf) { Remove-Item -LiteralPath $tmpf -Force } } catch { }
    $script:pending = $null
    [Console]::Error.WriteLine("dashboard: cannot write ${page}: $msg")
    return $false
  }
}

try {
  if (-not (Write-Page (Build-Page))) { exit 1 }
  if ($Once) {
    [Console]::Out.WriteLine("dashboard: wrote $page")
    [Console]::Out.WriteLine("dashboard: open $url in a browser")
    exit 0
  }
  [Console]::Out.WriteLine("dashboard: open $url in a browser")
  [Console]::Out.WriteLine("dashboard: rewriting the page every $every s; stop with Ctrl-C (the page stays as last written)")
  while ($true) {
    Start-Sleep -Seconds $every
    [void](Write-Page (Build-Page))
  }
} finally {
  # Ctrl-C: a child that still runs is ended (on Windows with its process tree), the temporary file removed
  $c = $script:child
  if ($c) {
    try {
      if (-not $c.HasExited) {
        if ($env:OS -eq "Windows_NT") { & taskkill /T /F /PID $c.Id 2>&1 | Out-Null } else { $c.Kill() }
      }
    } catch { }
  }
  if ($script:pending) { try { if (Test-Path -LiteralPath $script:pending) { Remove-Item -LiteralPath $script:pending -Force } } catch { } }
}

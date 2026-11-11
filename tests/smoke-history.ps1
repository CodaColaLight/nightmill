# tests/smoke-history.ps1 - scripts/history.ps1 against a fixture ledger, fixture board pages and a fake gh (iteration 54,
# #166; docs/specs/iteration-54-history-metrics.md, "Tests"): the same cases and the same expected files in
# tests/fixtures/history/ as tests/smoke-history.sh, so both shells print the same bytes. The clock is
# NIGHTMILL_CLOCK_FILE (test only): 2026-11-09T12:00:00Z, 1794225600 seconds since 1970. The fake gh is a .cmd that calls
# a .ps1, first on the PATH. No network. Runs on Windows PowerShell 5.1 and pwsh. Not run on the machine where it was
# written (no PowerShell there).
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$H = Join-Path $here "scripts\history.ps1"
$FIX = Join-Path $PSScriptRoot "fixtures\history"
$psExe = (Get-Command powershell).Source
# the Git helper below has the name of the program: resolve the program itself, a function would call itself
$script:gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nightmill-smoke-history-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$CLOCK_NOW = [long]1794225600

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Read-Lf([string]$path) { ([IO.File]::ReadAllText($path, $utf8)) -replace "`r`n", "`n" }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Has-Line([string]$text, [string]$pattern) { [regex]::IsMatch($text, "(?m)$pattern") }
function Git { $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $script:gitExe @args 2>&1 } finally { $ErrorActionPreference = $ea } }
function Git-Quiet { $null = Git @args }
if (-not (Test-Path $H)) { Fail "scripts/history.ps1 does not exist" }
. (Join-Path $here "scripts\lib\ledger.ps1")

try {
  # the fake gh: logs every call to $env:GH_LOG, answers api graphql from $env:BOARD_DIR\page-<i>.json by the after value
  # it is given (no after: page 1; after=cur1: page 2), exit 1 with a message when GH_FAIL is set, fails on any other call
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory -Path $bin | Out-Null
  Write-Utf8 (Join-Path $bin "gh-fake.ps1") @'
$a = @($args)
Add-Content -Path $env:GH_LOG -Value ($a -join ' ')
if ((@($a | Select-Object -First 2) -join ' ') -eq 'api graphql') {
  if ($env:GH_FAIL) { [Console]::Error.WriteLine('fake gh: boom'); exit 1 }
  $after = ''
  for ($i = 0; $i -lt ($a.Count - 1); $i++) {
    if (@('-f', '-F', '--raw-field', '--field') -ccontains [string]$a[$i] -and ([string]$a[$i + 1]).StartsWith('after=')) { $after = ([string]$a[$i + 1]).Substring(6) }
  }
  if ($after -eq '') { $file = 'page-1.json' }
  elseif ($after -eq 'cur1') { $file = 'page-2.json' }
  else { [Console]::Error.WriteLine("fake gh: no page after $after"); exit 1 }
  [Console]::Out.Write([IO.File]::ReadAllText((Join-Path $env:BOARD_DIR $file)))
  exit 0
}
[Console]::Error.WriteLine("fake gh: unexpected call: $($a -join ' ')")
exit 1
'@
  Write-Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n"

  # the project: a committed config (the default statuses), the worktrees root ../wt, the ledger in <root>\.slots
  $main = Join-Path $tmp "work"
  $L = Join-Path $tmp "wt\.slots\ledger.tsv"
  Git-Quiet init -q -b main $main
  Git-Quiet -C $main config user.email t@example.com
  Git-Quiet -C $main config user.name t
  New-Item -ItemType Directory -Force -Path (Join-Path $main ".claude"), (Join-Path $tmp "wt\.slots") | Out-Null
  # Set-Cfg [<the JSON string literal of the Backlog name>]: write and commit the config
  function Set-Cfg([string]$backlog = "") {
    $board = ""
    if ($backlog) { $board = ",`n  `"board`": { `"statuses`": { `"backlog`": $backlog } }" }
    Write-Utf8 (Join-Path $main ".claude\nightmill.json") "{`n  `"github`": { `"owner`": `"acme`", `"repo`": `"widgets`", `"projectNumber`": 1 },`n  `"maintainer`": { `"name`": `"Alex`" },`n  `"verification`": { `"check`": `"true`" },`n  `"labels`": { `"epic`": `"epic`" },`n  `"worktrees`": { `"root`": `"../wt`", `"slots`": 2 }$board`n}`n"
    Git-Quiet -C $main add -A
    Git-Quiet -C $main commit -q --allow-empty -m config
  }
  Set-Cfg
  Copy-Item (Join-Path $FIX "ledger.tsv") $L -Force
  $env:GH_LOG = Join-Path $tmp "gh.log"; $env:BOARD_DIR = $FIX; $env:NIGHTMILL_CLOCK_FILE = Join-Path $tmp "clock"
  Remove-Item Env:GH_FAIL -ErrorAction SilentlyContinue
  function Set-Clock([long]$v) { [IO.File]::WriteAllText($env:NIGHTMILL_CLOCK_FILE, "$v`n") }
  Set-Clock $CLOCK_NOW
  Write-Utf8 $env:GH_LOG ""

  # Snap: the checkout (tree and head) and the ledger; history changes neither
  function Snap {
    $s = (Git -C $main status --porcelain --untracked-files=all | Out-String) + (Git -C $main rev-parse HEAD | Out-String)
    if (Test-Path -LiteralPath $L -PathType Leaf) { $s += ([BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([IO.File]::ReadAllBytes($L)))) }
    $s
  }
  if ((Git -C $main status --porcelain --untracked-files=all | Out-String).Trim()) { Fail "the test project is not clean before the first run" }

  # Invoke-Hist <arguments> [environment] [folder]: history.ps1 in a child process (from the main checkout); Out and Err
  # (LF), OutRaw, OutBytes, Code. The checkout and the ledger are as before, and the fake gh saw nothing but the board
  # query (a read: no mutation).
  function Invoke-Hist([string]$arguments = "", [hashtable]$extraEnv = @{}, [string]$cwd = $main) {
    $before = Snap
    Write-Utf8 $env:GH_LOG ""
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$H`" $arguments"
    $psi.WorkingDirectory = $cwd
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["PATH"] = $bin + ";" + $env:PATH
    foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    $script:OutBytes = $ms.ToArray()
    $script:OutRaw = $utf8.GetString($script:OutBytes)
    $script:Out = $script:OutRaw -replace "`r`n", "`n"
    $script:Err = ($errTask.Result -replace "`r`n", "`n")
    $script:Code = $p.ExitCode
    if ($before -ne (Snap)) { Fail "history ${arguments}: the checkout or the ledger changed" }
    foreach ($ln in @(Get-Content $env:GH_LOG | Where-Object { $_ })) {
      if (-not ($ln.StartsWith("api graphql ") -and $ln.Contains("repositoryOwner"))) { Fail "history ${arguments}: a gh call other than the board query: $ln" }
      if ($ln.Contains("mutation")) { Fail "history ${arguments}: a gh call with a mutation: $ln" }
    }
  }
  function Want-Code([int]$expected, [string]$what) { if ($script:Code -ne $expected) { Fail "${what}: exit $($script:Code), $expected expected ($($script:Err))" } }
  function Has([string]$text, [string]$needle, [string]$what) { if (-not $text.Contains($needle)) { Fail "${what}: '$needle' not found in: $text" } }
  function Hasnt([string]$text, [string]$needle, [string]$what) { if ($text.Contains($needle)) { Fail "${what}: '$needle' found in: $text" } }
  function Same-Bytes([string]$what, [string]$file) { # the last stdout is byte for byte the file
    if ([Convert]::ToBase64String($script:OutBytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))) {
      Write-Host "--- expected ($file)"; Write-Host (Read-Lf $file); Write-Host "--- got"; Write-Host $script:Out
      Fail "${what}: the output differs from $file"
    }
  }
  function Only-Malformed-Note([string]$what) { # the one note on standard error: the skipped malformed line of the fixture ledger
    $lines = @($script:Err.TrimEnd("`n") -split "`n")
    if ($lines.Count -ne 1) { Fail "${what}: standard error is not one line: $($script:Err)" }
    if (-not (Has-Line $script:Err '^history: skipped 1 malformed lines of .*ledger\.tsv$')) { Fail "${what}: the note about the malformed line: $($script:Err)" }
  }
  function Fields([string]$text, [string]$first) { # the whitespace separated cells of the row that starts with <first>
    foreach ($row in ($text -split "`n")) { $f = @($row -split '\s+' | Where-Object { $_ -ne "" }); if ($f.Count -gt 0 -and $f[0] -ceq $first) { return $f } }
    return @()
  }
  function Cell([string]$text, [int]$n, [int]$c) { $f = @(Fields $text "#$n"); if ($f.Count -ge $c) { return $f[$c - 1] }; return "<none>" }
  function Money([double]$x) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F2}', $x) }

  Write-Host "== text"
  Invoke-Hist
  Want-Code 0 "text"
  Same-Bytes "text" (Join-Path $FIX "expected-text.txt")
  Only-Malformed-Note "text"
  $textOut = $script:Out
  if ("$(Cell $Out 12 8) $(Cell $Out 12 9) $(Cell $Out 12 11)" -cne '2 1 $3.00') { Fail "text: #12 is not rounds 2, checks 1, `$3.00: $Out" }
  if ("$(Cell $Out 13 8) $(Cell $Out 13 9) $(Cell $Out 13 11)" -cne '0 0 $2.50') { Fail "text: #13 is not rounds 0, checks 0, `$2.50: $Out" }
  if ("$(Cell $Out 14 8) $(Cell $Out 14 9) $(Cell $Out 14 11)" -cne '- 0 $3.00') { Fail "text: #14 is not rounds -, checks 0, `$3.00: $Out" }
  Has $Out 'cost: $8.90 in 4 headless runs; $0.40 on no issue; 1 runs without a cost' "text"
  Has $Out 'slots: 3 (record), utilisation 32%' "text"
  Has $Out 'note: 1 stays at a status not in board.statuses were not counted' "text"
  Has $Out 'note: 1 takes have no take line; their held time starts at their first line' "text"
  if (-not (Has-Line $Out '^Backlog +2 +2h10m +15h05m +17h15m$')) { Fail "text: the Backlog row (the lower middle of two stays)" }
  if (-not (Has-Line $Out '^Ready +3 +30m00s +3h00m +3h40m$')) { Fail "text: the Ready row (the middle of three stays)" }
  if (Has-Line $Out '^#5 ') { Fail "text: the epic is listed" }
  if ((Cell $Out 13 5) -cne "2h25m") { Fail "text: the project 2 event cut the Approved stay of #13: $(Cell $Out 13 5)" }
  if ($OutBytes -contains [byte]13) { Fail "text: a carriage return in the output" }
  if ($OutBytes[$OutBytes.Length - 1] -ne 10) { Fail "text: the output does not end with LF" }
  if ($OutBytes.Length -ge 3 -and $OutBytes[0] -eq 0xEF -and $OutBytes[1] -eq 0xBB -and $OutBytes[2] -eq 0xBF) { Fail "text: a byte order mark" }

  Write-Host "== json"
  Invoke-Hist "-Json"
  Want-Code 0 "json"
  Same-Bytes "json" (Join-Path $FIX "expected.json")
  Only-Malformed-Note "json"
  $jsonText = $script:Out
  if (@($jsonText.TrimEnd("`n") -split "`n").Count -ne 1) { Fail "json: the output is not one line" }
  if ($OutBytes -contains [byte]13) { Fail "json: a carriage return in the output" }
  try { $j = $jsonText | ConvertFrom-Json } catch { Fail "json: the output is not valid JSON: $_" }
  # its numbers are the text form's, before formatting
  $tl = @($textOut -split "`n")
  if (@($j.statuses).Count -ne 7) { Fail "json: not seven statuses" }
  for ($i = 0; $i -lt 7; $i++) {
    $f = @($tl[$i + 3] -split '\s+' | Where-Object { $_ -ne "" })
    $want = "$($f[$f.Count - 4]) $($f[$f.Count - 3]) $($f[$f.Count - 2]) $($f[$f.Count - 1])"
    $s = $j.statuses[$i]
    $got = "$($s.stays) $(Format-LedgerDuration $s.median) $(Format-LedgerDuration $s.max) $(Format-LedgerDuration $s.total)"
    if ($got -cne $want) { Fail "json: status $i is [$got], the text form has [$want]" }
  }
  foreach ($it in @($j.issues)) {
    $f = @(Fields $textOut "#$($it.number)")
    $want = "$($f[7]) $($f[8]) $($f[9]) $($f[10])"
    $r = "-"; if ($null -ne $it.rounds) { $r = "$($it.rounds)" }
    $c = "-"; if ($null -ne $it.checks) { $c = "$($it.checks)" }
    $got = "$r $c $($it.runs) `$$(Money $it.cost)"
    if ($got -cne $want) { Fail "json: issue #$($it.number) is [$got], the text form has [$want]" }
  }
  if ((Money $j.cost.total) -cne "8.90" -or $j.cost.runs -ne 4 -or $j.cost.withoutCost -ne 1 -or (Money $j.cost.noIssue) -cne "0.40") { Fail "json: the cost object" }
  if ($j.slots.count -ne 3 -or $j.slots.from -cne "record" -or $j.slots.utilisation -ne 32) { Fail "json: the slots object" }
  if ($null -ne $j.run) { Fail "json: run is not null" }

  Write-Host "== html"
  $report = Join-Path $tmp "report\sub"
  Invoke-Hist "-Html `"$report`""
  Want-Code 0 "html"
  if (-not (Has-Line $Out '^history: wrote .*index\.html$')) { Fail "html: stdout is [$Out]" }
  Only-Malformed-Note "html"
  $names = @(Get-ChildItem -Force -Name $report)
  if ($names.Count -ne 1 -or $names[0] -cne "index.html") { Fail "html: the folder holds more than index.html: $($names -join ', ')" }
  $pageFile = Join-Path $report "index.html"
  $pageBytes = [IO.File]::ReadAllBytes($pageFile)
  if ([Convert]::ToBase64String($pageBytes) -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $FIX "expected.html")))) { Fail "html: the page differs from expected.html" }
  $page = [IO.File]::ReadAllText($pageFile, $utf8)
  foreach ($w in '<script', '<link', '<a ', 'href', 'src=', 'url(', '@import', 'http', 'refresh', '<form', '<input') {
    if ($page.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Fail "html: the page contains '$w'" }
  }
  if ($pageBytes -contains [byte]13) { Fail "html: a carriage return in the page" }
  if ($pageBytes.Length -ge 3 -and $pageBytes[0] -eq 0xEF -and $pageBytes[1] -eq 0xBB -and $pageBytes[2] -eq 0xBF) { Fail "html: a byte order mark" }
  # a second run replaces the page; a name from the configuration is escaped
  Set-Cfg '"A&B <x>"'
  Invoke-Hist "-Html `"$report`""
  Want-Code 0 "html second run"
  $page = [IO.File]::ReadAllText($pageFile, $utf8)
  Has $page '<td>A&amp;B &lt;x&gt;</td>' "html escaping"
  Hasnt $page 'A&B' "html escaping"
  Hasnt $page '<x>' "html escaping"
  if (@(Get-ChildItem -Force -Name $report).Count -ne 1) { Fail "html second run: the folder holds more than index.html" }
  Set-Cfg

  Write-Host "== html not writable"
  $aFile = Join-Path $tmp "afile"
  Write-Utf8 $aFile "not a folder`n"
  Invoke-Hist "-Html `"$aFile`""
  Want-Code 1 "html not writable"
  Has $Err "history: cannot write " "html not writable"
  if ($OutRaw) { Fail "html not writable: stdout is [$OutRaw]" }
  if ((Read-Lf $aFile) -cne "not a folder`n") { Fail "html not writable: the file was changed" }
  if (@(Get-ChildItem -Recurse -Force -Filter ".index.html.*" $tmp -ErrorAction SilentlyContinue).Count -ne 0) { Fail "html not writable: a temporary file is left" }

  Write-Host "== names from the configuration lose their control characters"
  Set-Cfg '"Back\u0007log"'
  Invoke-Hist
  Want-Code 0 "names"
  if (-not (Has-Line $Out '^Backlog +[0-9?]+ ')) { Fail "names: the Backlog row (the name without its control character): $Out" }
  if ($OutRaw -cmatch '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]') { Fail "names: a control character reached the output" }
  Set-Cfg

  Write-Host "== window"
  Invoke-Hist "-From 2026-11-09T04:30:00Z -To 2026-11-09T05:15:00Z"
  Want-Code 0 "window"
  # the take without a take line is outside this window; the note about it is not part of this comparison
  $kept = (@($OutRaw -split "`n") | Where-Object { -not $_.Contains("no take line") }) -join "`n"
  if ($kept -cne (Read-Lf (Join-Path $FIX "expected-window.txt"))) { Write-Host "--- got"; Write-Host $kept; Fail "window: the output differs from expected-window.txt" }
  if ((Cell $Out 13 6) -cne "30m00s") { Fail "window: the stay that ends at the start of the window is not counted: $(Cell $Out 13 6)" }
  if ((Has-Line $Out '^#12 ') -or (Has-Line $Out '^#14 ')) { Fail "window: an issue without a take, a stay or a run in the window is listed" }
  Invoke-Hist "-From 2026-11-09 -To 2026-11-09"
  Want-Code 0 "window of dates"
  Has $Out "history 2026-11-09T00:00:00Z to 2026-11-09T00:00:00Z (0s)" "window of dates"
  Has $Out "utilisation -" "window of 0 seconds"

  Write-Host "== run"
  Invoke-Hist "-Run 2026-11-09T01:00:00Z"
  Want-Code 0 "run"
  Same-Bytes "run" (Join-Path $FIX "expected-run.txt")
  Has $Out "driver run 2026-11-09T01:00:00Z" "run"
  Has $Out 'cost: $8.50 in 2 headless runs;' "run"
  Invoke-Hist "-Json -Run 2026-11-09T01:00:00Z"
  Want-Code 0 "run json"
  if (-not $Out.Contains('"run":"2026-11-09T01:00:00Z"') -or -not $Out.Contains('"to":"2026-11-09T05:10:00Z"')) { Fail "run json: run and to: $Out" }
  try { $null = $Out | ConvertFrom-Json } catch { Fail "run json: not valid JSON: $_" }

  Write-Host "== run unknown"
  Invoke-Hist "-Run 2026-11-08T00:00:00Z"
  Want-Code 0 "run unknown"
  Has $Out "note: no run lines for the driver run 2026-11-08T00:00:00Z" "run unknown"
  Has $Out "history 2026-11-08T00:00:00Z to 2026-11-09T12:00:00Z (36h00m), driver run 2026-11-08T00:00:00Z" "run unknown"
  Has $Out 'cost: $0.00 in 0 headless runs; $0.00 on no issue; 0 runs without a cost' "run unknown"

  Write-Host "== gate agrees"
  # the fixture ledger of the gate (iteration 53): the spend of #21 is $4.00 and of #12 $3.00 (half of $6.00 for #11,#12)
  Copy-Item (Join-Path $PSScriptRoot "fixtures\gate\ledger.tsv") $L -Force
  Set-Clock 1794297660
  Invoke-Hist "-From 1970-01-01"
  Want-Code 0 "gate agrees"
  if ((Cell $Out 21 11) -cne '$4.00') { Fail "gate agrees: the cost of #21 is [$(Cell $Out 21 11)], `$4.00 expected: $Out" }
  if ((Cell $Out 12 11) -cne '$3.00') { Fail "gate agrees: the cost of #12 is [$(Cell $Out 12 11)], `$3.00 expected: $Out" }
  if ((Cell $Out 11 11) -cne '$3.00') { Fail "gate agrees: the cost of #11 is [$(Cell $Out 11 11)], `$3.00 expected: $Out" }
  Has $Out 'cost: $10.00 in 2 headless runs; $0.00 on no issue; 0 runs without a cost' "gate agrees"
  Copy-Item (Join-Path $FIX "ledger.tsv") $L -Force
  Set-Clock $CLOCK_NOW

  Write-Host "== board fails"
  Invoke-Hist "" @{ GH_FAIL = "1" }
  Want-Code 0 "board fails"
  Same-Bytes "board fails" (Join-Path $FIX "expected-boardfails.txt")
  Invoke-Hist "-Json" @{ GH_FAIL = "1" }
  Want-Code 0 "board fails json"
  Same-Bytes "board fails json" (Join-Path $FIX "expected-boardfails.json")
  try { $null = $Out | ConvertFrom-Json } catch { Fail "board fails json: not valid JSON: $_" }
  # no gh at all: git and the Windows system folders on the PATH, the fake gh and the real one left out
  $noGh = (Split-Path $script:gitExe -Parent) + ";$env:SystemRoot\System32;$env:SystemRoot"
  $ghThere = $false
  foreach ($d in $noGh -split ";") { foreach ($n in "gh.exe", "gh.cmd", "gh.bat") { if (Test-Path (Join-Path $d $n)) { $ghThere = $true } } }
  if (-not $ghThere) {
    Invoke-Hist "" @{ PATH = $noGh }
    Want-Code 0 "no gh"
    Has $Out "note: the board was not read: " "no gh"
    if (-not (Has-Line $Out '^Backlog +\? +\? +\? +\?$')) { Fail "no gh: the status rows are not ?: $Out" }
    if (-not (Has-Line $Out '^#12 +\? +\? +\? +\? +\? +\? +2 +1 +1 +\$3\.00$')) { Fail "no gh: the row of #12 (times ?, the ledger parts as in text): $Out" }
    if ((Get-Content $env:GH_LOG -Raw)) { Fail "no gh: the fake gh was called" }
  }

  Write-Host "== no ledger"
  Remove-Item $L
  Invoke-Hist
  Want-Code 0 "no ledger"
  if (-not (Has-Line $Out '^note: no record yet: .*[\\/]wt[\\/]\.slots[\\/]ledger\.tsv$')) { Fail "no ledger: the note: $Out" }
  Has $Out "history 2026-11-02T12:00:00Z to 2026-11-09T12:00:00Z (168h00m)" "no ledger"
  $wantBlock = (@((Read-Lf (Join-Path $FIX "expected-text.txt")) -split "`n")[2..9]) -join "`n"
  $gotBlock = (@($Out -split "`n")[2..9]) -join "`n"
  if ($gotBlock -cne $wantBlock) { Fail "no ledger: the status block is not the one of the board: $Out" }
  Hasnt $Out "no issue in the window" "no ledger"
  foreach ($n in 12, 13, 14) { if ((Cell $Out $n 11) -cne "-") { Fail "no ledger: the cost of #$n is [$(Cell $Out $n 11)], - expected: $Out" } }
  Invoke-Hist "-Json"
  Want-Code 0 "no ledger json"
  try { $null = $Out | ConvertFrom-Json } catch { Fail "no ledger json: not valid JSON: $_" }
  Copy-Item (Join-Path $FIX "ledger.tsv") $L -Force

  Write-Host "== fix rounds are the highest step number"
  # tests/fixtures/history/ledger-rounds.tsv: #31 repeats its steps (code-review, fix-round-1 twice, dispute-3, test-finding-2,
  # check-fix-1 twice): the highest k is 3 and 1, a count of lines would be 7 or 4 and 2; #32 has only test-finding-2; #33 a
  # code-review and no round; #34 a take without code-review and check-fix-2 before check-fix-1; #35 has a run line and no
  # take; #25 has one counted board stay and nothing else. The board page is the one of board-rounds\.
  Copy-Item (Join-Path $FIX "ledger-rounds.tsv") $L -Force
  $env:BOARD_DIR = Join-Path $FIX "board-rounds"
  Invoke-Hist
  Want-Code 0 "fix rounds"
  if ($Err) { Fail "fix rounds: standard error is [$Err]" }
  $rw = @{
    "31" = @('3 1 0 -', "#31 (dispute-3 and test-finding-2 among repeated steps) is not rounds 3, checks 1, runs 0, cost -")
    "32" = @('2 0 0 -', "#32 (test-finding-2 alone) is not rounds 2, checks 0")
    "33" = @('0 0 0 -', "#33 (a code-review and no round) is not rounds 0, checks 0")
    "34" = @('- 2 0 -', "#34 (no code-review; check-fix-2 then check-fix-1) is not rounds -, checks 2")
    "35" = @('- - 1 $1.50', "#35 (a run line, no take) is not rounds -, checks - (not 0), runs 1, `$1.50")
  }
  foreach ($n in 31, 32, 33, 34, 35) {
    if ("$(Cell $Out $n 8) $(Cell $Out $n 9) $(Cell $Out $n 10) $(Cell $Out $n 11)" -cne $rw["$n"][0]) { Fail "fix rounds: $($rw["$n"][1]): $((@($Out -split "`n") | Where-Object { $_.StartsWith("#$n ") }) -join '')" }
  }
  if ("$(Cell $Out 25 2) $(Cell $Out 25 8) $(Cell $Out 25 9) $(Cell $Out 25 10) $(Cell $Out 25 11)" -cne '10m00s - - 0 -') { Fail "fix rounds: #25 (a board stay, no take) is not ready 10m00s, rounds -, checks - (not 0): $Out" }
  Invoke-Hist "-Json"
  Want-Code 0 "fix rounds json"
  try { $jr = $Out | ConvertFrom-Json } catch { Fail "fix rounds json: not valid JSON: $_" }
  Has $Out '"rounds":3,"checks":1,"runs":0,"cost":null},{"number":32,' "fix rounds json: #31 is rounds 3, checks 1"
  Has $Out '"rounds":2,"checks":0,"runs":0,"cost":null},{"number":33,' "fix rounds json: #32 is rounds 2, checks 0"
  Has $Out '"rounds":0,"checks":0,"runs":0,"cost":null},{"number":34,' "fix rounds json: #33 is rounds 0, checks 0"
  Has $Out '"rounds":null,"checks":2,"runs":0,"cost":null},{"number":35,' "fix rounds json: #34 is rounds null, checks 2"
  Has $Out '"rounds":null,"checks":null,"runs":1,"cost":1.50}' "fix rounds json: #35 (no take) is rounds null, checks null"
  Has $Out '{"number":25,"times":{"ready":600,"spec":null,"specReview":null,"approved":null,"inProgress":null,"review":null},"rounds":null,"checks":null,"runs":0,"cost":null},{"number":31,' "fix rounds json: #25 (a stay, no take) is checks null"
  $env:BOARD_DIR = $FIX
  Copy-Item (Join-Path $FIX "ledger.tsv") $L -Force

  Write-Host "== usage"
  foreach ($a in "-Json -Html `"$tmp\x`"", "-Run 2026-11-09T01:00:00Z -From 2026-01-01", "-Run 2026-11-09T01:00:00Z -To 2026-11-10", "-From 2026-13-01",
      "-From 2026-11-09 -To 2026-11-08", "-Html", "-Json -Json", "-Bogus", "-Run 2026-11-09", "-From", "-From 2026-11-09 -From 2026-11-09", "extra") {
    Invoke-Hist $a
    Want-Code 2 "usage ($a)"
    if (-not (Has-Line $Err '^usage: history\.ps1')) { Fail "usage ($a): no usage line on standard error: [$Err]" }
    if ($OutRaw) { Fail "usage ($a): printed [$OutRaw]" }
    if ((Get-Content $env:GH_LOG -Raw)) { Fail "usage ($a): gh was called" }
  }
  if (Test-Path (Join-Path $tmp "x")) { Fail "usage: a folder was made" }
  Invoke-Hist "-h"
  Want-Code 0 "help"
  if (-not (Has-Line $Out '^usage: history\.ps1')) { Fail "help: no usage line on standard output: [$Out]" }

  Write-Host "== outside a checkout and without a config"
  $plain = Join-Path $tmp "plain"
  New-Item -ItemType Directory -Path $plain | Out-Null
  $ea = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $null = & $script:gitExe -C $plain rev-parse --git-dir 2>$null
  $inRepo = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $ea
  if (-not $inRepo) {
    Invoke-Hist "" @{} $plain
    if ($Code -ne 2) { Fail "outside a checkout: exit $Code" }
  }
  Git-Quiet init -q -b main $plain
  Invoke-Hist "" @{} $plain
  if ($Code -ne 2 -or $Err -notmatch "nightmill.json") { Fail "no config: exit ${Code}: $Err" }

  Write-Host "== a ledger that cannot be read"
  Remove-Item $L
  New-Item -ItemType Directory $L | Out-Null
  Invoke-Hist
  Want-Code 1 "a ledger that is a folder"
  Has $Err "history: cannot read " "a ledger that is a folder"
  Remove-Item $L
  Copy-Item (Join-Path $FIX "ledger.tsv") $L -Force

  Write-Host "smoke-history.ps1: ok"
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

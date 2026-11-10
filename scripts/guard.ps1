# scripts/guard.ps1 - the PreToolUse guard hook (PowerShell; iteration 47, #110), the twin of scripts/guard.sh.
# hooks/hooks.json wires guard.sh; this script is the same behaviour for a machine that runs hooks through PowerShell
# only, to be wired by hand (see the README). It refuses, with exit code 2 and one line on stderr:
#   - a board status edit to Ready or Approved (gh project item-edit with that option id, or the GraphQL mutation
#     updateProjectV2ItemFieldValue naming it); the option ids are read at run time with gh project field-list,
#     only for a command that edits a status, and a status edit is refused when they cannot be read
#   - every merge that is not gh pr merge ... --auto, gh pr merge with --admin, and a merge through gh api
#   - a force push and a push to git.baseBranch in every git form, git -C <slot path> push included
#   - (iteration 50, #253) a remote branch delete (git push --delete, -d, --prune, --mirror or an empty source :<ref>),
#     a forced local branch delete (git branch -D, or --delete with --force), and a GraphQL mutation (gh api graphql)
#     with a top-level field outside the six the skills need, or a query sent from a file (--input, query=@<file>)
# Everything else: exit 0 and no output. Off (exit 0) where the project has no .claude/nightmill.json, and for input
# that is not valid JSON, another tool or an empty command. The rules are in
# docs/specs/iteration-47-enforce-hard-rules.md (decision 5) and docs/specs/iteration-50-refuse-other-deletes.md
# (decisions 3 to 5). Windows PowerShell 5.1 and PowerShell 7. ASCII only.
#   CLAUDE_PROJECT_DIR   the project root (set by Claude Code); the current directory when unset
$ErrorActionPreference = "Stop"

function Get-Val($obj, [string[]]$names, [string]$default) {
  $cur = $obj
  foreach ($n in $names) {
    if ($null -eq $cur) { return $default }
    $p = $cur.PSObject.Properties[$n]
    if ($null -eq $p) { return $default }
    $cur = $p.Value
  }
  if ($null -eq $cur) { return $default }
  if ($cur -is [System.Management.Automation.PSCustomObject] -or $cur -is [array]) { return $default }
  return [string]$cur
}

try {
  $raw = [Console]::In.ReadToEnd()
  $ev = ConvertFrom-Json -InputObject $raw
} catch { exit 0 }
$tool = Get-Val $ev @("tool_name") ""
if ($tool -cne "Bash" -and $tool -cne "PowerShell") { exit 0 }
$cmd = Get-Val $ev @("tool_input", "command") ""
if ($cmd -eq "") { exit 0 }

$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { $root = (Get-Location).Path }
$cfgPath = Join-Path $root ".claude/nightmill.json"
if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) { exit 0 }
$cfg = $null
try { $cfg = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($cfgPath)) } catch { $cfg = $null }
$owner = Get-Val $cfg @("github", "owner") ""
$number = Get-Val $cfg @("github", "projectNumber") ""
$field = Get-Val $cfg @("board", "statusField") "Status"
$ready = Get-Val $cfg @("board", "statuses", "ready") "Ready"
$approved = Get-Val $cfg @("board", "statuses", "approved") "Approved"
$base = Get-Val $cfg @("git", "baseBranch") "main"
if ($base -eq "") { $base = "main" }

function Stop-Refused([string]$text) {
  [Console]::Error.WriteLine($text)
  exit 2
}

# The verdicts, in order: objects with Kind R (Val: the refusal), I (Val: the option id of an item-edit), Q (Val:
# the text of a GraphQL status edit) or M (Val: a GraphQL mutation field not on the allow list).
$script:verdicts = New-Object System.Collections.ArrayList
$script:queue = New-Object System.Collections.ArrayList

function Get-SubClose([string]$s, [int]$p, [string]$closer) {
  $q = ""; $depth = 1
  for ($j = $p; $j -lt $s.Length; $j++) {
    $ch = [string]$s[$j]
    if ($closer -eq "``") { if ($ch -eq "``") { return $j }; continue }
    if ($q -ne "") { if ($ch -eq $q) { $q = "" }; continue }
    if ($ch -eq "'" -or $ch -eq '"') { $q = $ch; continue }
    if ($ch -eq "(") { $depth++ }
    elseif ($ch -eq ")") { $depth--; if ($depth -eq 0) { return $j } }
  }
  return $s.Length
}

function Test-EndsWith([string]$w, [string]$suf) { return $w.EndsWith($suf, [StringComparison]::Ordinal) }

function Add-Verdict([string]$kind, [string]$val) {
  [void]$script:verdicts.Add([pscustomobject]@{ Kind = $kind; Val = $val })
}

# The GraphQL mutations the skills send (iteration 50, decision 5); every other one is refused
$script:allow = @("addSubIssue", "createProjectV2View", "enablePullRequestAutoMerge", "updateProjectV2Field",
  "updateProjectV2ItemFieldValue", "updateProjectV2View")

# Get-GqlBad <document>: the first top-level field of a mutation in the GraphQL document that is not on the allow
# list, or "". Strings and comments are skipped, names inside parentheses (arguments, variables) and nested
# selections are not looked at; the first name of a definition at brace depth 0 is its keyword (a later one its
# name, which may be a keyword too), a name at depth 1 a top-level field; a definition without a keyword is a query.
function Get-GqlBad([string]$s) {
  $n = $s.Length; $p = 0; $b = 0; $inmut = $false; $st = $true
  for ($i = 0; $i -lt $n; $i++) {
    $c = $s[$i]
    if ($c -eq [char]'"') {
      for ($i++; $i -lt $n; $i++) {
        if ($s[$i] -eq [char]'\') { $i++; continue }
        if ($s[$i] -eq [char]'"') { break }
      }
      continue
    }
    if ($c -eq [char]'#') { while ($i -lt $n -and $s[$i] -ne [char]"`n") { $i++ }; continue }
    if ($c -eq [char]'(') { $p++; continue }
    if ($c -eq [char]')') { if ($p -gt 0) { $p-- }; continue }
    if ($p -gt 0) { continue }
    if ($c -eq [char]'{') { if ($b -eq 0 -and $st) { $inmut = $false }; $st = $false; $b++; continue }
    if ($c -eq [char]'}') { if ($b -gt 0) { $b-- }; if ($b -eq 0) { $st = $true }; continue }
    if (-not ([string]$c -cmatch '^[_A-Za-z]$')) { continue }
    $j = $i
    while ($j + 1 -lt $n -and ([string]$s[$j + 1] -cmatch '^[_0-9A-Za-z]$')) { $j++ }
    $nm = $s.Substring($i, $j - $i + 1); $i = $j
    if ($b -eq 0) {
      if ($st) { $inmut = ($nm -ceq "mutation") }
      $st = $false
    } elseif ($b -eq 1 -and $inmut -and -not ($script:allow -ccontains $nm)) { return $nm }
  }
  return ""
}

function Invoke-JudgeGh([string[]]$w, [int]$k, [string]$text) {
  $merge = $false; $api = $false; $gql = $false; $auto = $false; $admin = $false; $disable = $false
  $rest = $false; $edit = $false; $opt = ""
  for ($m = $k + 1; $m -lt $w.Count; $m++) {
    $x = $w[$m]
    $next = $null; if ($m + 1 -lt $w.Count) { $next = $w[$m + 1] }
    if ($x -ceq "pr" -and $next -ceq "merge") { $merge = $true }
    if ($x -ceq "project" -and $next -ceq "item-edit") { $edit = $true }
    if ($x -ceq "api") { $api = $true }
    if ($x -ceq "graphql") { $gql = $true }
    if ($x -ceq "--auto") { $auto = $true }
    if ($x -ceq "--admin" -or $x.StartsWith("--admin=", [StringComparison]::Ordinal)) { $admin = $true }
    if ($x -ceq "--disable-auto") { $disable = $true }
    if ($x -cmatch 'pulls/[0-9]+/merge') { $rest = $true }
    if ($x -ceq "--single-select-option-id" -and $null -ne $next) { $opt = $next }
    elseif ($x.StartsWith("--single-select-option-id=", [StringComparison]::Ordinal)) { $opt = $x.Substring(26) }
  }
  if ($merge -and -not $disable) {
    if ($admin) { Add-Verdict "R" "admin"; return }
    if (-not $auto) { Add-Verdict "R" "auto"; return }
  }
  if ($api -and $rest) { Add-Verdict "R" "api"; return }
  if ($api -and $gql -and $text.Contains("mergePullRequest")) { Add-Verdict "R" "api"; return }
  if ($api -and $gql) {
    for ($m = $k + 1; $m -lt $w.Count; $m++) {
      $x = $w[$m]
      if ($x -ceq "--input" -or $x.StartsWith("--input=", [StringComparison]::Ordinal)) { Add-Verdict "R" "unread"; return }
      $doc = $null
      foreach ($pre in @("query=", "-fquery=", "-Fquery=", "--raw-field=query=", "--field=query=")) {
        if ($x.StartsWith($pre, [StringComparison]::Ordinal)) { $doc = $x.Substring($pre.Length); break }
      }
      if ($null -eq $doc) { continue }
      if ($doc.StartsWith("@", [StringComparison]::Ordinal)) { Add-Verdict "R" "unread"; return }
      $bad = Get-GqlBad $doc
      if ($bad -ne "") { Add-Verdict "M" $bad; return }
    }
  }
  if ($edit) { Add-Verdict "I" $opt; return }
  if ($api -and $gql -and $text.Contains("updateProjectV2ItemFieldValue")) { Add-Verdict "Q" $text }
}

function Invoke-JudgeGit([string[]]$w, [int]$k) {
  $sc = -1
  for ($m = $k + 1; $m -lt $w.Count; $m++) {
    $x = $w[$m]
    if ($x -ceq "-C" -or $x -ceq "-c" -or $x -ceq "--git-dir" -or $x -ceq "--work-tree") { $m++; continue }
    if ($x.StartsWith("-")) { continue }
    $sc = $m; break
  }
  if ($sc -lt 0) { return }
  if ($w[$sc] -ceq "branch") {
    $del = $false; $frc = $false
    for ($m = $sc + 1; $m -lt $w.Count; $m++) {
      $x = $w[$m]
      if ($x -cmatch '^-[A-Za-z]*D[A-Za-z]*$') { Add-Verdict "R" "fbd"; return }
      if ($x -ceq "--delete" -or $x -cmatch '^-[A-Za-z]*d[A-Za-z]*$') { $del = $true }
      if ($x -ceq "--force" -or $x -cmatch '^-[A-Za-z]*f[A-Za-z]*$') { $frc = $true }
    }
    if ($del -and $frc) { Add-Verdict "R" "fbd" }
    return
  }
  if ($w[$sc] -cne "push") { return }
  for ($m = $sc + 1; $m -lt $w.Count; $m++) {
    $x = $w[$m]
    if ($x.StartsWith("--force", [StringComparison]::Ordinal) -or $x -cmatch '^-[A-Za-z]*f[A-Za-z]*$' -or $x.StartsWith("+")) {
      Add-Verdict "R" "force"; return
    }
  }
  $skip = $false
  for ($m = $sc + 1; $m -lt $w.Count; $m++) {
    $x = $w[$m]
    if ($skip) { $skip = $false; continue }
    if ($x -ceq "-o" -or $x -ceq "--push-option" -or $x -ceq "--repo" -or $x -ceq "--receive-pack" -or $x -ceq "--exec") { $skip = $true; continue }
    if ($x -ceq "--delete" -or $x -ceq "--prune" -or $x -ceq "--mirror" -or $x -cmatch '^-[A-Za-z]*d[A-Za-z]*$') { Add-Verdict "R" "delete"; return }
    if ($x.StartsWith(":", [StringComparison]::Ordinal) -and $x.Length -gt 1) { Add-Verdict "R" "delete"; return }
  }
  $skip = $false
  for ($m = $sc + 1; $m -lt $w.Count; $m++) {
    $x = $w[$m]
    if ($skip) { $skip = $false; continue }
    if ($x -ceq "-o" -or $x -ceq "--push-option" -or $x -ceq "--repo" -or $x -ceq "--receive-pack" -or $x -ceq "--exec") { $skip = $true; continue }
    if ($x.StartsWith("-")) { continue }
    if ($x -ceq $base -or (Test-EndsWith $x (":" + $base)) -or (Test-EndsWith $x ("refs/heads/" + $base))) { Add-Verdict "R" "base"; return }
  }
}

function Invoke-Judge($words, [string]$text) {
  $w = [string[]]@($words)
  $k = 0
  while ($k -lt $w.Count -and $w[$k] -match '^[A-Za-z_][A-Za-z0-9_]*=') { $k++ }
  if ($k -ge $w.Count) { return }
  $first = $w[$k]
  if ($first -ceq "gh" -or $first.EndsWith("/gh") -or $first -ceq "gh.exe") { Invoke-JudgeGh $w $k $text }
  elseif ($first -ceq "git" -or $first.EndsWith("/git") -or $first -ceq "git.exe") { Invoke-JudgeGit $w $k }
}

function Invoke-Scan([string]$s, [bool]$isPs) {
  $esc = "\"; if ($isPs) { $esc = "``" }
  $q = ""; $cur = ""; $inword = $false; $text = ""
  $words = New-Object System.Collections.ArrayList
  $n = $s.Length
  for ($i = 0; $i -lt $n; $i++) {
    $c = [string]$s[$i]
    $d = ""; if ($i + 1 -lt $n) { $d = [string]$s[$i + 1] }
    if ($q -eq "'") { $text += $c; if ($c -eq "'") { $q = "" } else { $cur += $c }; continue }
    if ($c -eq $esc) { $text += $c + $d; $cur += $d; $inword = $true; $i++; continue }
    if (($c -eq '$' -and $d -eq "(") -or ($c -eq "``" -and -not $isPs)) {
      if ($c -eq "``") { $j = Get-SubClose $s ($i + 1) "``"; $start = $i + 1 } else { $j = Get-SubClose $s ($i + 2) ")"; $start = $i + 2 }
      [void]$script:queue.Add($s.Substring($start, [Math]::Max(0, [Math]::Min($j, $n) - $start)))
      $piece = $s.Substring($i, [Math]::Min($j, $n - 1) - $i + 1)
      $text += $piece; $cur += $piece; $inword = $true; $i = $j; continue
    }
    if ($q -eq '"') { $text += $c; if ($c -eq '"') { $q = "" } else { $cur += $c }; continue }
    if ($c -eq "'" -or $c -eq '"') { $text += $c; $q = $c; $inword = $true; continue }
    if ($c -eq ";" -or $c -eq "|" -or $c -eq "&" -or $c -eq "`n") {
      if ($inword) { [void]$words.Add($cur) }
      if ($words.Count -gt 0) { Invoke-Judge $words.ToArray() $text }
      $words.Clear(); $cur = ""; $inword = $false; $text = ""
      continue
    }
    $text += $c
    if ($c -eq " " -or $c -eq "`t" -or $c -eq "`r") {
      if ($inword) { [void]$words.Add($cur) }
      $cur = ""; $inword = $false
      continue
    }
    $cur += $c; $inword = $true
  }
  if ($inword) { [void]$words.Add($cur) }
  if ($words.Count -gt 0) { Invoke-Judge $words.ToArray() $text }
}

$isPs = ($tool -ceq "PowerShell")
Invoke-Scan $cmd $isPs
for ($qi = 0; $qi -lt $script:queue.Count -and $qi -lt 64; $qi++) { Invoke-Scan ([string]$script:queue[$qi]) $isPs }

# Test-WordIn <text> <id>: the id occurs in the text as a whole word (no letter, digit, _ or - right before or after)
function Test-WordIn([string]$t, [string]$id) {
  if ($id -eq "") { return $false }
  $from = 0
  while ($true) {
    $p = $t.IndexOf($id, $from, [StringComparison]::Ordinal)
    if ($p -lt 0) { return $false }
    $okB = ($p -eq 0) -or -not ([string]$t[$p - 1] -match '^[A-Za-z0-9_-]$')
    $e = $p + $id.Length
    $okA = ($e -ge $t.Length) -or -not ([string]$t[$e] -match '^[A-Za-z0-9_-]$')
    if ($okB -and $okA) { return $true }
    $from = $p + 1
  }
}

$script:looked = $false; $script:lookupOk = $false; $script:rid = ""; $script:aid = ""; $script:why = ""
function Invoke-Lookup {
  if ($script:looked) { return $script:lookupOk }
  $script:looked = $true
  if ($owner -eq "" -or $number -eq "") { $script:why = "github.owner or github.projectNumber is missing"; return $false }
  $expr = '.fields[] | select(.name == ' + (ConvertTo-Json $field) + ') | .options[]? | select(.name == ' + (ConvertTo-Json $ready) + ' or .name == ' + (ConvertTo-Json $approved) + ') | "\(.name)\t\(.id)"'
  # Windows PowerShell (and the Legacy mode of PowerShell 7) does not escape a double quote inside an argument
  $legacy = $true
  $pna = Get-Variable -Name PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue
  if ($null -ne $pna -and [string]$pna.Value -ne "Legacy") { $legacy = $false }
  if ($legacy) { $expr = $expr.Replace('"', '\"') }
  $ErrorActionPreference = "Continue"
  try {
    $out = & gh project field-list $number --owner $owner --format json --jq $expr 2>$null
    $code = $LASTEXITCODE
  } catch { $script:why = "gh project field-list failed"; return $false }
  if ($code -ne 0) { $script:why = "gh project field-list failed"; return $false }
  foreach ($line in @($out)) {
    $parts = ([string]$line).Split("`t")
    if ($parts.Count -lt 2) { continue }
    $name = $parts[0].Trim(); $id = $parts[1].Trim()
    if ($name -ceq $ready) { $script:rid = $id }
    if ($name -ceq $approved) { $script:aid = $id }
  }
  if ($script:rid -eq "" -and $script:aid -eq "") { $script:why = "gh printed neither id"; return $false }
  $script:lookupOk = $true
  return $true
}

function Stop-Status([string]$name) { Stop-Refused ("nightmill guard: refused: setting " + $name + " on the board. Only the maintainer sets " + $ready + " and " + $approved + ".") }
function Stop-Lookup { Stop-Refused ("nightmill guard: refused: a status edit, because the " + $ready + " and " + $approved + " option ids could not be read (" + $script:why + "). Read the board and try again; never set " + $ready + " or " + $approved + ".") }

foreach ($v in $script:verdicts) {
  if ($v.Kind -eq "R") {
    switch ($v.Val) {
      "auto" { Stop-Refused "nightmill guard: refused: a merge without --auto. Merge only with gh pr merge <pr> <git.mergeFlags>; git.mergeFlags must contain --auto." }
      "admin" { Stop-Refused "nightmill guard: refused: gh pr merge with --admin. Never merge past the checks." }
      "api" { Stop-Refused "nightmill guard: refused: a merge through gh api. Merge only with gh pr merge <pr> <git.mergeFlags>." }
      "force" { Stop-Refused "nightmill guard: refused: a force push. Push only with git push -u origin <branch>, never forced." }
      "base" { Stop-Refused ("nightmill guard: refused: a push to " + $base + ". Never push to the base branch.") }
      "delete" { Stop-Refused "nightmill guard: refused: deleting a remote branch. Push only with git push -u origin <branch>; never --delete, --prune, --mirror or an empty source." }
      "fbd" { Stop-Refused "nightmill guard: refused: a forced branch delete. Delete only a merged branch, with git branch -d <branch>." }
      "unread" { Stop-Refused "nightmill guard: refused: a GraphQL query the guard cannot read (--input or query=@<file>). Send it inline, as gh api graphql -f query='...'." }
    }
  } elseif ($v.Kind -eq "M") {
    Stop-Refused ("nightmill guard: refused: the GraphQL mutation " + $v.Val + ", which no skill sends.")
  } elseif ($v.Kind -eq "I") {
    if (-not (Invoke-Lookup)) { Stop-Lookup }
    if ($v.Val -ne "" -and $v.Val -ceq $script:rid) { Stop-Status $ready }
    if ($v.Val -ne "" -and $v.Val -ceq $script:aid) { Stop-Status $approved }
  } elseif ($v.Kind -eq "Q") {
    if (-not (Invoke-Lookup)) { Stop-Lookup }
    if (Test-WordIn $v.Val $script:rid) { Stop-Status $ready }
    if (Test-WordIn $v.Val $script:aid) { Stop-Status $approved }
  }
}
exit 0

# tests/smoke-models.ps1 - scripts/models.ps1: the table of every agent role, its model, where the model comes from,
# its rank and whether its pairing holds. The defaults are printed and named, a reviewer below its producer and a
# model that is not in the ranking are flagged, tester and worker never are, an invalid ranking is reported, usage
# errors exit 2, nothing is changed, the verdict agrees with validate-config, and the default config is found from a
# subfolder and from a second worktree. Same cases as smoke-models.sh. Needs git.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$M = Join-Path $here "scripts\models.ps1"
$V = Join-Path $here "scripts\validate-config.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-mod-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

$ex = [IO.File]::ReadAllText((Join-Path $here "templates\nightmill.example.json"), $utf8)
$bare = '{"github":{"owner":"o","repo":"r","projectNumber":1},"maintainer":{"name":"M"},"verification":{"check":"true"}}'

# Edit: replace a piece of the text; the piece has to exist.
function Edit([string]$text, [string]$old, [string]$new) {
  if (-not $text.Contains($old)) { Fail "fixture: '$old' is not in the example" }
  return $text.Replace($old, $new)
}

$DOES = @{
  specWriter   = 'writes the spec of a Ready story'
  specReviewer = 'reviews specWriter'
  tester       = 'writes the failing tests before the code'
  implementer  = 'writes the code of an Approved story'
  codeReviewer = 'reviews implementer and fixer'
  fixer        = 'fixes a bug'
  worker       = 'does mechanical, fully specified jobs'
}

# Table <role|model|from|rank|check>...: the expected table, with the padding worked out here (an oracle written
# apart from the script): every column but the last as wide as its widest cell, two spaces between, no trailing space.
function Table([string[]]$rows) {
  $w = @(4, 4, 5, 4, 4)
  $parsed = @()
  foreach ($r in $rows) {
    $f = $r.Split('|')
    $cells = @($f[0], $DOES[$f[0]], $f[1], $f[2], $f[3], $f[4])
    for ($k = 0; $k -lt 5; $k++) { if ($cells[$k].Length -gt $w[$k]) { $w[$k] = $cells[$k].Length } }
    $parsed += , $cells
  }
  $lines = @()
  $lines += ("role".PadRight($w[0]) + "  " + "does".PadRight($w[1]) + "  " + "model".PadRight($w[2]) + "  " + "from".PadRight($w[3]) + "  " + "rank".PadRight($w[4]) + "  check")
  foreach ($c in $parsed) {
    $lines += ($c[0].PadRight($w[0]) + "  " + $c[1].PadRight($w[1]) + "  " + $c[2].PadRight($w[2]) + "  " + $c[3].PadRight($w[3]) + "  " + $c[4].PadRight($w[4]) + "  " + $c[5])
  }
  return $lines -join "`n"
}

# Run-P <script> <arguments> [working directory]: run a script in a child powershell, return Out, Err and Code.
function Run-P([string]$script, [string]$arguments, [string]$cwd = "") {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $arguments"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  if ($cwd) { $psi.WorkingDirectory = $cwd }
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = ($out -replace "`r`n", "`n").TrimEnd("`n"); Err = $err; Code = $p.ExitCode }
}

$script:i = 0
# Run-M <name> <config text> <expected output>: exit 0 and the whole output equal to the expected text.
function Run-M([string]$name, [string]$text, [string]$want) {
  $script:i++
  $f = Join-Path $tmp ("case$($script:i).json")
  Write-Utf8 $f $text
  $r = Run-P $M "-Config `"$f`""
  if ($r.Code -ne 0) { Fail "$name : expected exit code 0, got $($r.Code): $($r.Out) $($r.Err)" }
  if ($r.Out -cne $want) { Fail "$name : wrong output. Got:`n$($r.Out)`nWanted:`n$want" }
}

$DEF_ROWS = @('specWriter|opus|default|3|-', 'specReviewer|opus|default|3|ok', 'tester|sonnet|default|2|-',
  'implementer|opus|default|3|-', 'codeReviewer|opus|default|3|ok', 'fixer|opus|default|3|-', 'worker|haiku|default|1|-')
$CFG_ROWS = @('specWriter|opus|config|3|-', 'specReviewer|opus|config|3|ok', 'tester|sonnet|config|2|-',
  'implementer|opus|config|3|-', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')
$RK_CFG = 'ranking: haiku < sonnet < opus < fable (config)'
$SW = '"specWriter": { "model": "opus" }'; $SR = '"specReviewer": { "model": "opus" }'
$CR = '"codeReviewer": { "model": "opus" }'; $RK = '"ranking": ["haiku", "sonnet", "opus", "fable"]'

try {
  Write-Host "== no keys prints the defaults and says so"
  $want1 = @'
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    default  3     -
specReviewer  reviews specWriter                        opus    default  3     ok
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: ok
No role model and no ranking in the config: these are the defaults of the schema.
'@ -replace "`r`n", "`n"
  $want1 = $want1.TrimEnd("`n")
  Run-M "no keys" $bare $want1
  $oracle1 = (Table $DEF_ROWS) + "`n`nranking: haiku < sonnet < opus < fable (default)`npairings: ok`nNo role model and no ranking in the config: these are the defaults of the schema."
  if ($oracle1 -cne $want1) { Fail "fixture: the oracle table differs from the literal example" }

  Write-Host "== a fully configured config"
  Run-M "example" $ex ((Table $CFG_ROWS) + "`n`n$RK_CFG`npairings: ok")

  Write-Host "== a reviewer below its producer is flagged"
  $want3 = @'
role          does                                      model   from     rank  check
specWriter    writes the spec of a Ready story          opus    config   3     -
specReviewer  reviews specWriter                        sonnet  config   2     BELOW specWriter
tester        writes the failing tests before the code  sonnet  default  2     -
implementer   writes the code of an Approved story      opus    default  3     -
codeReviewer  reviews implementer and fixer             opus    default  3     ok
fixer         fixes a bug                               opus    default  3     -
worker        does mechanical, fully specified jobs     haiku   default  1     -

ranking: haiku < sonnet < opus < fable (default)
pairings: 1 below, 0 not ranked
'@ -replace "`r`n", "`n"
  $want3 = $want3.TrimEnd("`n")
  $case3 = $bare.Substring(0, $bare.Length - 1) + ',"roles":{"specWriter":{"model":"opus"},"specReviewer":{"model":"sonnet"}}}'
  Run-M "spec reviewer below" $case3 $want3

  Write-Host "== the code reviewer below both producers"
  $case4 = Edit $ex $CR '"codeReviewer": { "model": "haiku" }'
  Run-M "code reviewer below" $case4 ((Table @('specWriter|opus|config|3|-', 'specReviewer|opus|config|3|ok', 'tester|sonnet|config|2|-',
    'implementer|opus|config|3|-', 'codeReviewer|haiku|config|1|BELOW implementer, fixer', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')) + "`n`n$RK_CFG`npairings: 2 below, 0 not ranked")

  Write-Host "== a model that is not in the ranking is flagged"
  $case5a = Edit $ex $SR '"specReviewer": { "model": "mystery" }'
  Run-M "unranked reviewer" $case5a ((Table @('specWriter|opus|config|3|-', 'specReviewer|mystery|config|-|NOT RANKED', 'tester|sonnet|config|2|-',
    'implementer|opus|config|3|-', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')) + "`n`n$RK_CFG`npairings: 0 below, 1 not ranked")
  $case5b = Edit $ex '"implementer": { "model": "opus" }' '"implementer": { "model": "mystery" }'
  Run-M "unranked producer" $case5b ((Table @('specWriter|opus|config|3|-', 'specReviewer|opus|config|3|ok', 'tester|sonnet|config|2|-',
    'implementer|mystery|config|-|NOT RANKED', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')) + "`n`n$RK_CFG`npairings: 0 below, 1 not ranked")

  Write-Host "== tester and worker are never flagged"
  Run-M "tester and worker" (Edit (Edit $ex '"tester": { "model": "sonnet" }' '"tester": { "model": "haiku" }') '"worker": { "model": "haiku" }' '"worker": { "model": "mystery" }') `
    ((Table @('specWriter|opus|config|3|-', 'specReviewer|opus|config|3|ok', 'tester|haiku|config|1|-',
    'implementer|opus|config|3|-', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|mystery|config|-|-')) + "`n`n$RK_CFG`npairings: ok")

  Write-Host "== same level in one ranking entry"
  $same = Edit (Edit $ex $RK '"ranking": ["haiku", "sonnet", "opus=claude-opus-5-5", "fable"]') $SW '"specWriter": { "model": "claude-opus-5-5" }'
  Run-M "same level" $same ((Table @('specWriter|claude-opus-5-5|config|3|-', 'specReviewer|opus|config|3|ok', 'tester|sonnet|config|2|-',
    'implementer|opus|config|3|-', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')) + "`n`nranking: haiku < sonnet < opus=claude-opus-5-5 < fable (config)`npairings: ok")

  Write-Host "== an empty model takes the default"
  Run-M "empty model" (Edit $ex $SR '"specReviewer": { "model": "" }') ((Table @('specWriter|opus|config|3|-', 'specReviewer|opus|default|3|ok', 'tester|sonnet|config|2|-',
    'implementer|opus|config|3|-', 'codeReviewer|opus|config|3|ok', 'fixer|opus|config|3|-', 'worker|haiku|config|1|-')) + "`n`n$RK_CFG`npairings: ok")

  Write-Host "== an invalid ranking"
  Run-M "invalid ranking" (Edit $ex $RK '"ranking": "opus"') ((Table @('specWriter|opus|config|-|-', 'specReviewer|opus|config|-|-', 'tester|sonnet|config|-|-',
    'implementer|opus|config|-|-', 'codeReviewer|opus|config|-|-', 'fixer|opus|config|-|-', 'worker|haiku|config|-|-')) + "`n`nranking: invalid (needs a non-empty list; run validate-config)`npairings: not checked")

  Write-Host "== usage errors exit 2"
  $r = Run-P $M "-Config `"$(Join-Path $tmp 'does-not-exist.json')`""
  if ($r.Code -ne 2) { Fail "missing config: expected exit code 2, got $($r.Code)" }
  if ($r.Err -notlike "*does-not-exist.json*") { Fail "missing config: the message does not name the path: $($r.Err)" }
  $f = Join-Path $tmp "bad.json"; Write-Utf8 $f '{"a": 1,}'
  $r = Run-P $M "-Config `"$f`""
  if ($r.Code -ne 2) { Fail "invalid JSON: expected exit code 2, got $($r.Code)" }
  $f = Join-Path $tmp "arr.json"; Write-Utf8 $f '[1]'
  $r = Run-P $M "-Config `"$f`""
  if ($r.Code -ne 2) { Fail "a config that is not an object: expected exit code 2, got $($r.Code)" }
  $r = Run-P $M "-NoSuchOption"
  if ($r.Code -ne 2) { Fail "unknown option: expected exit code 2, got $($r.Code)" }

  Write-Host "== it changes nothing"
  $ro = Join-Path $tmp "ro"; New-Item -ItemType Directory -Path $ro | Out-Null
  $roCfg = Join-Path $ro "nightmill.json"
  Write-Utf8 $roCfg $ex
  $beforeCfg = [IO.File]::ReadAllText($roCfg, $utf8)
  $beforeLs = (Get-ChildItem -LiteralPath $ro -Force | ForEach-Object { "$($_.Name) $($_.Length)" }) -join "`n"
  $r = Run-P $M "-Config `"$roCfg`""
  if ($r.Code -ne 0) { Fail "it changes nothing: the run failed: $($r.Out) $($r.Err)" }
  if ([IO.File]::ReadAllText($roCfg, $utf8) -cne $beforeCfg) { Fail "the config changed" }
  if ((Get-ChildItem -LiteralPath $ro -Force | ForEach-Object { "$($_.Name) $($_.Length)" }) -join "`n" -cne $beforeLs) { Fail "the folder changed" }

  Write-Host "== it agrees with validate-config"
  # the number of errors the validator gives for the pairing rule is B and the number of warnings is U (a role model
  # that is not an alias is an error of its own, which the table does not count)
  function Test-Agree([string]$name, [string]$text) {
    $f = Join-Path $tmp "agree.json"
    Write-Utf8 $f $text
    $m = Run-P $M "-Config `"$f`""
    $summary = ($m.Out -split "`n" | Where-Object { $_ -like "pairings: *" }) | Select-Object -First 1
    $b = 0; $u = 0
    if ($summary -match '^pairings: (\d+) below, (\d+) not ranked$') { $b = [int]$Matches[1]; $u = [int]$Matches[2] }
    $v = Run-P $V "-Config `"$f`""
    $lines = @($v.Out -split "`n")
    $e = @($lines | Where-Object { $_ -like "error: * ranks below *" }).Count
    $w = @($lines | Where-Object { $_ -like "warning: *" }).Count
    if ($e -ne $b) { Fail "$name : the table counts $b below, the validator $e errors: $($v.Out)" }
    if ($w -ne $u) { Fail "$name : the table counts $u not ranked, the validator $w warnings: $($v.Out)" }
  }
  Test-Agree "example" $ex
  Test-Agree "spec reviewer below" $case3
  Test-Agree "code reviewer below" $case4
  Test-Agree "unranked reviewer" $case5a
  Test-Agree "unranked producer" $case5b
  Test-Agree "same level" $same

  Write-Host "== it finds the config from a subfolder and from a second worktree"
  $repo = Join-Path $tmp "repo"
  git init -q -b main $repo
  git -C $repo config core.autocrlf false
  New-Item -ItemType Directory -Path (Join-Path $repo ".claude"), (Join-Path $repo "sub") | Out-Null
  Write-Utf8 (Join-Path $repo ".claude\nightmill.json") $case3
  Write-Utf8 (Join-Path $repo "sub\x.txt") "x"
  git -C $repo add -A
  git -C $repo -c user.name=t -c user.email=t@example.invalid commit -qm init
  $wt2 = Join-Path $tmp "repo-wt2"
  git -C $repo worktree add -q $wt2 -b other
  foreach ($d in @((Join-Path $repo "sub"), $wt2)) {
    $r = Run-P $M "" $d
    if ($r.Code -ne 0) { Fail "from $d : exit code $($r.Code): $($r.Out) $($r.Err)" }
    if ($r.Out -cne $want3) { Fail "from $d : wrong output. Got:`n$($r.Out)" }
  }

  Write-Host "MODELS OK"
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

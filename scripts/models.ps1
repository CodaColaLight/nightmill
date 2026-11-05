# scripts/models.ps1 - one table of the model of every agent role (nightmill).
#
#   models.ps1 [-Config path] [-Schema path]
#
# Prints one row per role: what it does, the model it runs on, whether that model comes from the config or from the
# default of the schema, its rank in models.ranking and whether its pairing holds (a reviewer must rank at least as
# high as each role it reviews), then the ranking, a summary line and, when the config sets nothing, a line that
# says so. It only reads. The texts and the rules are in docs/specs/iteration-16-models-command.md; models.sh
# prints the same.
# -Config  the file to read (default: .claude/nightmill.json of the main checkout, found with
#          git rev-parse --git-common-dir, so it works from any worktree of the project)
# -Schema  the schema for the defaults (default: schema/nightmill.schema.json of this plugin)
# Git is needed only to find the default config. Exit code 0 when the table was printed (a flag in it does not
# change that), 2 for a usage error, an unknown option, a missing or unreadable config or schema, a config that is
# not a JSON object, or a call outside a git checkout without -Config.
param(
  [string]$Config,
  [string]$Schema,
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Stop-Models([string]$msg) {
  [Console]::Error.WriteLine("models.ps1: $msg")
  exit 2
}
if ($Rest -and @($Rest).Count -gt 0) {
  [Console]::Error.WriteLine("unknown argument: $($Rest -join ' ')")
  [Console]::Error.WriteLine("usage: models.ps1 [-Config path] [-Schema path]")
  exit 2
}

$root = Split-Path $PSScriptRoot -Parent
if (-not $Config) {
  $gitDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $gitDir) { Stop-Models "run models.ps1 from inside a checkout of the project (or pass -Config)" }
  $Config = Join-Path (Split-Path ([string]$gitDir).Trim() -Parent) ".claude\nightmill.json"
  if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { Stop-Models "no $Config (run /nightmill:init)" }
}
if (-not $Schema) { $Schema = Join-Path $root "schema\nightmill.schema.json" }
foreach ($pair in @(@("config", $Config), @("schema", $Schema))) {
  if (-not (Test-Path -LiteralPath $pair[1] -PathType Leaf)) { Stop-Models "cannot read $($pair[0]): $($pair[1])" }
}

# --- JSON helpers: exact (case-sensitive) key access, as in validate-config.ps1 ----------------------------------

function Test-Has($obj, [string]$name) {
  return (($obj -is [System.Management.Automation.PSCustomObject]) -and (@($obj.PSObject.Properties.Name) -ccontains $name))
}

function Get-Child($obj, [string]$name) {
  if (Test-Has $obj $name) { return $obj.PSObject.Properties[$name].Value }
  return $null
}

# --- read the files -----------------------------------------------------------------------------------------------

$schemaDoc = $null
try { $schemaDoc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $Schema).Path, $utf8)) }
catch { Stop-Models "${Schema}: not valid JSON" }

$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Config).Path, $utf8)
$doc = $null
if ($text.Trim() -eq "") { Stop-Models "${Config}: not valid JSON (empty)" }
try { $doc = ConvertFrom-Json -InputObject $text } catch { Stop-Models "${Config}: not valid JSON" }
if ($text.TrimStart()[0] -ne '{' -or -not ($doc -is [System.Management.Automation.PSCustomObject])) { Stop-Models "${Config}: not a JSON object" }

# --- the roles ----------------------------------------------------------------------------------------------------

$roles = @("specWriter", "specReviewer", "tester", "implementer", "codeReviewer", "fixer", "worker")
$does = @{
  specWriter   = "writes the spec of a Ready story"
  specReviewer = "reviews specWriter"
  tester       = "writes the failing tests before the code"
  implementer  = "writes the code of an Approved story"
  codeReviewer = "reviews implementer and fixer"
  fixer        = "fixes a bug"
  worker       = "does mechanical, fully specified jobs"
}
# the producers each reviewer must rank at least as high as, in the order of the table
$prods = @{ specReviewer = @("specWriter"); codeReviewer = @("implementer", "fixer") }

# the effective ranking
$models = Get-Child $doc "models"
$hasRk = Test-Has $models "ranking"
$source = "config"
$rankOk = $true
if ($hasRk) {
  $rk = Get-Child $models "ranking"
  if (-not ($rk -is [System.Array]) -or @($rk).Count -eq 0) { $rankOk = $false }
}
else {
  $source = "default"
  $rk = Get-Child (Get-Child (Get-Child (Get-Child (Get-Child $schemaDoc "properties") "models") "properties") "ranking") "default"
  if (-not ($rk -is [System.Array]) -or @($rk).Count -eq 0) { $rankOk = $false }
}
$rank = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
$rLine = New-Object System.Collections.Generic.List[string]
if ($rankOk) {
  $i = 0
  foreach ($item in @($rk)) {
    $i++
    if ($item -is [string]) {
      $rLine.Add($item)
      foreach ($part in $item.Split([char]'=')) { if ($part -ne "" -and -not $rank.ContainsKey($part)) { $rank[$part] = $i } }
    }
  }
}

# the effective model of each role and where it comes from
$model = @{}; $from = @{}
$nConfig = 0
foreach ($role in $roles) {
  $m = Get-Child (Get-Child (Get-Child $doc "roles") $role) "model"
  if ($m -is [string] -and $m -ne "") { $model[$role] = $m; $from[$role] = "config"; $nConfig++; continue }
  $d = Get-Child (Get-Child (Get-Child (Get-Child (Get-Child (Get-Child $schemaDoc "properties") "roles") "properties") $role) "properties") "model"
  $d = Get-Child $d "default"
  if ($d -is [string] -and $d -ne "") { $model[$role] = $d; $from[$role] = "default" }
  else { $model[$role] = "-"; $from[$role] = "-" }
}

function Test-Ranked([string]$role) { return ($rankOk -and $model[$role] -ne "-" -and $rank.ContainsKey($model[$role])) }

$b = 0; $u = 0
$rankCell = @{}; $check = @{}
foreach ($role in $roles) {
  $rankCell[$role] = "-"; $check[$role] = "-"
  if (Test-Ranked $role) { $rankCell[$role] = [string]$rank[$model[$role]] }
  if (-not $rankOk) { continue }
  if ($role -ceq "specReviewer" -or $role -ceq "codeReviewer") {
    if ($model[$role] -ceq "-") { continue }
    if (-not (Test-Ranked $role)) { $check[$role] = "NOT RANKED"; $u++; continue }
    $below = New-Object System.Collections.Generic.List[string]
    foreach ($p in $prods[$role]) {
      if ((Test-Ranked $p) -and $rank[$model[$role]] -lt $rank[$model[$p]]) { $below.Add($p); $b++ }
    }
    if ($below.Count -gt 0) { $check[$role] = "BELOW " + ($below -join ", ") } else { $check[$role] = "ok" }
  }
  elseif ($role -ceq "specWriter" -or $role -ceq "implementer" -or $role -ceq "fixer") {
    if ($model[$role] -cne "-" -and -not (Test-Ranked $role)) { $check[$role] = "NOT RANKED"; $u++ }
  }
}

# --- the table: every column but the last as wide as its widest cell, two spaces between, no trailing space -------

$w1 = 4; $w2 = 4; $w3 = 5; $w4 = 4; $w5 = 4
foreach ($role in $roles) {
  if ($role.Length -gt $w1) { $w1 = $role.Length }
  if ($does[$role].Length -gt $w2) { $w2 = $does[$role].Length }
  if ($model[$role].Length -gt $w3) { $w3 = $model[$role].Length }
  if ($from[$role].Length -gt $w4) { $w4 = $from[$role].Length }
  if ($rankCell[$role].Length -gt $w5) { $w5 = $rankCell[$role].Length }
}
Write-Output ("role".PadRight($w1) + "  " + "does".PadRight($w2) + "  " + "model".PadRight($w3) + "  " + "from".PadRight($w4) + "  " + "rank".PadRight($w5) + "  check")
foreach ($role in $roles) {
  Write-Output ($role.PadRight($w1) + "  " + $does[$role].PadRight($w2) + "  " + $model[$role].PadRight($w3) + "  " + $from[$role].PadRight($w4) + "  " + $rankCell[$role].PadRight($w5) + "  " + $check[$role])
}
Write-Output ""
if ($rankOk) { Write-Output ("ranking: " + ($rLine -join " < ") + " (" + $source + ")") }
else { Write-Output "ranking: invalid (needs a non-empty list; run validate-config)" }
if (-not $rankOk) { Write-Output "pairings: not checked" }
elseif ($b -eq 0 -and $u -eq 0) { Write-Output "pairings: ok" }
else { Write-Output ("pairings: " + $b + " below, " + $u + " not ranked") }
if ($nConfig -eq 0 -and -not $hasRk) { Write-Output "No role model and no ranking in the config: these are the defaults of the schema." }
exit 0

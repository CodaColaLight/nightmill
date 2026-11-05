# scripts/validate-config.ps1 - check a nightmill config against the schema.
#
#   validate-config.ps1 [-Config path] [-Schema path] [-Strict]
#
# -Config  the file to check (default: .claude/nightmill.json in the repository this script lives in)
# -Schema  the schema to check against (default: schema/nightmill.schema.json in that repository)
# -Strict  warnings (unknown keys) fail too
#
# Prints one finding per line, sorted by path, then a summary:
#   error: worktrees.slots: expected integer, got string
#   warning: worktree: unknown key (did you mean "worktrees"?)
#   1 error, 1 warning
# Exit codes: 0 no error (and with -Strict no warning), 1 an error or, with -Strict, a warning, 2 a usage error
# or an unreadable file. Same behaviour and output as validate-config.sh.
#
# The validator walks the schema; it supports type, properties, required, items, minimum, minItems,
# additionalProperties (a schema, true or false) and enum. tests/lint.sh fails if the schema uses a keyword
# that is not on that list. After the walk, Test-Pairs checks that a reviewer role is not ranked below the
# role it reviews (iteration 15).
param(
  [string]$Config,
  [string]$Schema,
  [switch]$Strict,
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Usage {
  [Console]::Error.WriteLine("usage: validate-config.ps1 [-Config path] [-Schema path] [-Strict]")
  exit 2
}
if ($Rest -and @($Rest).Count -gt 0) { [Console]::Error.WriteLine("unknown argument: $($Rest -join ' ')"); Usage }

$root = Split-Path $PSScriptRoot -Parent
if (-not $Config) { $Config = Join-Path $root ".claude\nightmill.json" }
if (-not $Schema) { $Schema = Join-Path $root "schema\nightmill.schema.json" }
foreach ($pair in @(@("config", $Config), @("schema", $Schema))) {
  if (-not (Test-Path -LiteralPath $pair[1] -PathType Leaf)) { [Console]::Error.WriteLine("cannot read $($pair[0]): $($pair[1])"); exit 2 }
}

# --- JSON helpers -------------------------------------------------------------------------------------------

# The JSON kind of a parsed value: null, string, boolean, array, object, integer or number.
function Get-Kind($v) {
  if ($null -eq $v) { return "null" }
  if ($v -is [string]) { return "string" }
  if ($v -is [bool]) { return "boolean" }
  if ($v -is [System.Array]) { return "array" }
  if ($v -is [System.Management.Automation.PSCustomObject]) { return "object" }
  if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte] -or $v -is [uint32] -or $v -is [uint64]) { return "integer" }
  if ($v -is [double] -or $v -is [decimal] -or $v -is [single]) {
    if ($v -eq [math]::Floor($v)) { return "integer" } else { return "number" }
  }
  return "other"
}

function Test-Type($v, [string]$t) {
  $k = Get-Kind $v
  if ($t -ceq "number") { return ($k -ceq "integer" -or $k -ceq "number") }
  return ($k -ceq $t)
}

# The value as JSON text (for messages).
function Get-JsonText($v) {
  $k = Get-Kind $v
  if ($k -ceq "null") { return "null" }
  if ($k -ceq "string") { return '"' + ($v -replace '\\', '\\' -replace '"', '\"') + '"' }
  if ($k -ceq "boolean") { if ($v) { return "true" } else { return "false" } }
  if ($k -ceq "integer" -or $k -ceq "number") { return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $v)) }
  return $k
}

function Join-Key([string]$p, [string]$k) { if ($p -eq "") { return $k } else { return "$p.$k" } }

# A known key of the same object that equals the unknown one ignoring case, or with one trailing character
# added or removed; $null when there is none.
function Get-Hint([string]$key, [string[]]$known) {
  foreach ($k in $known) {
    if ($k.ToLowerInvariant() -ceq $key.ToLowerInvariant()) { return $k }
    if ($k.Length -eq $key.Length + 1 -and $k.StartsWith($key, [StringComparison]::Ordinal)) { return $k }
    if ($key.Length -eq $k.Length + 1 -and $key.StartsWith($k, [StringComparison]::Ordinal)) { return $k }
  }
  return $null
}

# --- findings ------------------------------------------------------------------------------------------------

$script:findings = New-Object System.Collections.Generic.List[string]
$script:errors = 0
$script:warnings = 0

# Add-Finding <path> <error|warning> <text>: stored as "path TAB rank TAB line" so an ordinal sort of the
# records is the order the bash version gets from LC_ALL=C sort.
function Add-Finding([string]$path, [string]$sev, [string]$msg) {
  $shown = if ($path -eq "") { "." } else { $path }
  $rank = if ($sev -ceq "error") { 0 } else { 1 }
  $script:findings.Add($shown + "`t" + $rank + "`t" + $sev + ": " + $shown + ": " + $msg)
  if ($sev -ceq "error") { $script:errors++ } else { $script:warnings++ }
}

# --- the walk ------------------------------------------------------------------------------------------------

function Test-Node($val, $s, [string]$p) {
  $sprops = @($s.PSObject.Properties.Name)
  $kind = Get-Kind $val
  if ($sprops -ccontains "type") {
    $t = [string]$s.type
    if (-not (Test-Type $val $t)) { Add-Finding $p "error" "expected $t, got $kind"; return }
  }
  if ($sprops -ccontains "enum") {
    $ok = $false
    foreach ($e in $s.enum) { if ((Get-JsonText $e) -ceq (Get-JsonText $val)) { $ok = $true } }
    if (-not $ok) {
      $list = (@($s.enum) | ForEach-Object { if ($_ -is [string]) { $_ } else { Get-JsonText $_ } }) -join ", "
      Add-Finding $p "error" ("must be one of: " + $list + ", got " + (Get-JsonText $val))
    }
  }
  if ($sprops -ccontains "minimum" -and ($kind -ceq "integer" -or $kind -ceq "number") -and $val -lt $s.minimum) {
    Add-Finding $p "error" ("must be at least " + (Get-JsonText $s.minimum) + ", got " + (Get-JsonText $val))
  }
  if ($kind -ceq "array") {
    $items = @($val)
    if ($sprops -ccontains "minItems" -and $items.Count -lt $s.minItems) {
      Add-Finding $p "error" ("needs at least " + $s.minItems + " items, got " + $items.Count)
    }
    if ($sprops -ccontains "items") {
      for ($i = 0; $i -lt $items.Count; $i++) { Test-Node $items[$i] $s.items ($p + "[" + $i + "]") }
    }
  }
  if ($kind -ceq "object") {
    $names = @($val.PSObject.Properties.Name)
    if ($sprops -ccontains "required") {
      foreach ($k in @($s.required)) {
        if (-not ($names -ccontains $k)) { Add-Finding (Join-Key $p $k) "error" "required key is missing" }
      }
    }
    $known = @()
    if ($sprops -ccontains "properties") { $known = @($s.properties.PSObject.Properties.Name) }
    foreach ($k in $names) {
      $child = Join-Key $p $k
      if ($known -ccontains $k) {
        Test-Node $val.PSObject.Properties[$k].Value $s.properties.PSObject.Properties[$k].Value $child
      }
      elseif ($k -ceq '$schema') { }
      elseif ($sprops -ccontains "additionalProperties") {
        $ap = $s.additionalProperties
        if ($ap -is [bool]) { if (-not $ap) { Add-Finding $child "error" "unknown key is not allowed" } }
        else { Test-Node $val.PSObject.Properties[$k].Value $ap $child }
      }
      else {
        $h = Get-Hint $k $known
        $msg = "unknown key"
        if ($null -ne $h) { $msg += " (did you mean `"" + $h + "`"?)" }
        Add-Finding $child "warning" $msg
      }
    }
  }
}

# --- the reviewer pairing (iteration 15) ---------------------------------------------------------------------
# A rule across keys, which the schema cannot express: a reviewer role must rank at least as high as each role
# it reviews (specReviewer over specWriter, codeReviewer over implementer and fixer), judged by models.ranking.
# It runs on the effective models (the config's roles.<role>.model when it is a non-empty string, else the
# default of the schema) and on the effective ranking (the config's, else the default of the schema), so a
# config without the keys is clean. Same texts and same findings as validate-config.sh (lib/validate.awk).

# Whether $obj is a JSON object that has exactly this key (the match is case-sensitive, as in the walk above).
function Test-Has($obj, [string]$name) {
  return (($obj -is [System.Management.Automation.PSCustomObject]) -and (@($obj.PSObject.Properties.Name) -ccontains $name))
}

# A child of a JSON object by exact key; $null when $obj is not an object or has no such key.
function Get-Child($obj, [string]$name) {
  if (Test-Has $obj $name) { return $obj.PSObject.Properties[$name].Value }
  return $null
}

# The model a role runs on: "" when neither the config nor the schema has one.
function Get-RoleModel($cfg, $sch, [string]$role) {
  $m = Get-Child (Get-Child (Get-Child $cfg "roles") $role) "model"
  if ($m -is [string] -and $m -ne "") { return $m }
  $d = Get-Child (Get-Child (Get-Child (Get-Child (Get-Child (Get-Child $sch "properties") "roles") "properties") $role) "properties") "model"
  $d = Get-Child $d "default"
  if ($d -is [string]) { return $d }
  return ""
}

function Test-Pairs($cfg, $sch) {
  if (-not ($cfg -is [System.Management.Automation.PSCustomObject])) { return }
  if (-not (Test-Has (Get-Child $sch "properties") "roles")) { return }
  $models = Get-Child $cfg "models"
  if (Test-Has $models "ranking") {
    $rk = Get-Child $models "ranking"
    if (-not ($rk -is [System.Array]) -or @($rk).Count -eq 0) { return }
  }
  else {
    $rk = Get-Child (Get-Child (Get-Child (Get-Child (Get-Child $sch "properties") "models") "properties") "ranking") "default"
    if (-not ($rk -is [System.Array])) { return }
  }
  # the rank of a name: the 1-based position of the first entry that has it as a part of a "="-joined entry
  $rank = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
  $i = 0
  foreach ($item in @($rk)) {
    $i++
    if ($item -is [string]) {
      foreach ($part in $item.Split([char]'=')) { if ($part -ne "" -and -not $rank.ContainsKey($part)) { $rank[$part] = $i } }
    }
  }
  $model = @{}
  foreach ($role in @("specWriter", "specReviewer", "implementer", "codeReviewer", "fixer")) {
    $m = Get-RoleModel $cfg $sch $role
    $model[$role] = $m
    if ($m -ne "" -and -not $rank.ContainsKey($m)) {
      Add-Finding ("roles." + $role + ".model") "warning" ("model " + (Get-JsonText $m) + " is not in models.ranking, so " + $role + " cannot be compared")
    }
  }
  # the pairs: reviewer, then the role it reviews
  foreach ($pair in @(@("specReviewer", "specWriter"), @("codeReviewer", "implementer"), @("codeReviewer", "fixer"))) {
    $rev = $pair[0]; $prod = $pair[1]
    if ($model[$rev] -eq "" -or $model[$prod] -eq "") { continue }
    if (-not $rank.ContainsKey($model[$rev]) -or -not $rank.ContainsKey($model[$prod])) { continue }
    if ($rank[$model[$rev]] -lt $rank[$model[$prod]]) {
      Add-Finding ("roles." + $rev + ".model") "error" ($rev + " on " + (Get-JsonText $model[$rev]) + " ranks below " + $prod + " on " + (Get-JsonText $model[$prod]))
    }
  }
}

# --- run -----------------------------------------------------------------------------------------------------

Write-Output "validating $Config against $Schema"

$schemaDoc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $Schema).Path, $utf8))
$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Config).Path, $utf8)

$doc = $null
$valid = $true
if ($text.Trim() -eq "") { $valid = $false }
else {
  try { $doc = ConvertFrom-Json -InputObject $text } catch { $valid = $false }
}

if (-not $valid) {
  Add-Finding "" "error" "not valid JSON"
}
elseif ($text.TrimStart()[0] -ne '{') {
  # ConvertFrom-Json unrolls a top-level array, so the kind of a document that is not an object comes from its text
  $c = $text.TrimStart()[0]
  $kind = switch -Regex ([string]$c) {
    '\[' { "array" }
    '"' { "string" }
    '[tf]' { "boolean" }
    'n' { "null" }
    default { Get-Kind $doc }
  }
  Add-Finding "" "error" "expected object, got $kind"
}
else {
  Test-Node $doc $schemaDoc ""
  Test-Pairs $doc $schemaDoc
}

$records = $script:findings.ToArray()
[Array]::Sort($records, [StringComparer]::Ordinal)
foreach ($r in $records) { Write-Output ($r.Split("`t", 3)[2]) }

$e = $script:errors
$w = $script:warnings
$eText = if ($e -eq 1) { "1 error" } else { "$e errors" }
$wText = if ($w -eq 1) { "1 warning" } else { "$w warnings" }
Write-Output "$eText, $wText"

if ($e -gt 0) { exit 1 }
if ($w -gt 0 -and $Strict) { exit 1 }
exit 0

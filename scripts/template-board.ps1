# scripts/template-board.ps1 - can /init copy nightmill's template board for this config? (nightmill)
#
#   template-board.ps1 -Config <file>
#
# <file> is the candidate config /init builds before it shows the plan. The script reads the template's
# location from templates/board-template.json in the plugin, the board field names and the eight status
# names from <file> (a key the file does not have takes its default from schema/nightmill.schema.json), and
# asks GitHub what the template board looks like. It only reads: gh project view and gh project field-list,
# never gh project copy or any mutation.
#
# Prints exactly one line:
#   template: usable (<owner>/<number>)
#   template: not usable: <reason>      none published | not reachable | fields differ | statuses differ
# Exit code 0 whenever the line was printed, "usable" or not. Exit 2 for a usage error, an unreadable file, gh
# missing or not logged in; the message goes to standard error. The rules and the texts are in
# docs/specs/iteration-9-init-template-board.md; template-board.sh prints the same.
param(
  [string]$Config,
  [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = "Stop"

function Die([string]$msg) { [Console]::Error.WriteLine("template-board.ps1: $msg"); exit 2 }
if ($Rest -or -not $Config) { [Console]::Error.WriteLine("usage: template-board.ps1 -Config <file>"); exit 2 }

$root = Split-Path $PSScriptRoot -Parent
$tplPath = Join-Path $root "templates\board-template.json"
$schemaPath = Join-Path $root "schema\nightmill.schema.json"
foreach ($f in @($Config, $tplPath, $schemaPath)) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Die "cannot read $f" }
}
function Read-Json([string]$path) {
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { Die "$path is not valid JSON" }
}
$cfg = Read-Json $Config
$schema = Read-Json $schemaPath
$tpl = Read-Json $tplPath

function Prop($obj, [string[]]$path) { # the value at the path, $null when a step is missing
  foreach ($k in $path) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$k]
    if (-not $p) { return $null }
    $obj = $p.Value
  }
  return $obj
}
function Cfg([string[]]$path, [string[]]$schemaPath) { # the config's string at the path, else the schema's default
  $v = Prop $cfg $path
  if ($null -ne $v -and "$v" -ne "") { return [string]$v }
  return [string](Prop $schema $schemaPath)
}

$fStatus = Cfg @("board", "statusField") @("properties", "board", "properties", "statusField", "default")
$fPriority = Cfg @("board", "priorityField") @("properties", "board", "properties", "priorityField", "default")
$fArea = Cfg @("board", "areaField") @("properties", "board", "properties", "areaField", "default")
$wanted = @()
foreach ($k in @("backlog", "ready", "spec", "specReview", "approved", "inProgress", "review", "done")) {
  $wanted += Cfg @("board", "statuses", $k) @("properties", "board", "properties", "statuses", "properties", $k, "default")
}

# where the template lives: owner a non-empty string, number an integer or null
$tOwner = Prop $tpl @("owner")
if ($tOwner -isnot [string] -or -not $tOwner) { Die "$tplPath`: owner must be a non-empty string" }
$numProp = $tpl.PSObject.Properties["number"]
if (-not $numProp) { Die "$tplPath`: number must be an integer or null" }
$tNumber = $null
if ($null -ne $numProp.Value) {
  if (($numProp.Value -isnot [int] -and $numProp.Value -isnot [long]) -or $numProp.Value -lt 1) { Die "$tplPath`: number must be an integer or null" }
  $tNumber = [long]$numProp.Value
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die "gh is not installed or not on the PATH" }

if ($null -eq $tNumber) {
  Write-Output "template: not usable: none published"
  exit 0
}

# a native call whose standard error is dropped: Text and Code
function Invoke-Gh([string[]]$ghArgs) {
  $eap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { $text = (& gh @ghArgs 2>$null | Out-String); $code = $LASTEXITCODE } finally { $ErrorActionPreference = $eap }
  return [pscustomobject]@{ Text = $text; Code = $code }
}

if ((Invoke-Gh @("auth", "status")).Code -ne 0) { Die "gh is not logged in (run gh auth login)" }

$view = Invoke-Gh @("project", "view", "$tNumber", "--owner", $tOwner, "--format", "json")
$list = $null
if ($view.Code -eq 0) { $list = Invoke-Gh @("project", "field-list", "$tNumber", "--owner", $tOwner, "--limit", "50", "--format", "json") }
$fields = $null
if ($list -and $list.Code -eq 0) { try { $fields = @((ConvertFrom-Json $list.Text).fields) } catch { $fields = $null } }
if ($null -eq $fields) {
  Write-Output "template: not usable: not reachable"
  exit 0
}

function Find-Field([string]$name) {
  foreach ($f in $fields) { if ($f.name -ceq $name -and $f.type -eq "ProjectV2SingleSelectField") { return $f } }
  return $null
}
foreach ($n in @($fStatus, $fPriority, $fArea)) {
  if (-not (Find-Field $n)) { Write-Output "template: not usable: fields differ"; exit 0 }
}

$have = @((Find-Field $fStatus).options | ForEach-Object { [string]$_.name })
if (($have -join "`n") -cne ($wanted -join "`n")) {
  Write-Output "template: not usable: statuses differ"
  exit 0
}

Write-Output "template: usable ($tOwner/$tNumber)"

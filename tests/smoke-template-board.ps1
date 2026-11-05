# tests/smoke-template-board.ps1 - template-board.ps1 against fixtures: a fake gh (a gh.cmd first on the PATH)
# answers from tests/fixtures/template-board/, the plugin files are copied to a throwaway root so that each
# scenario can have its own templates/board-template.json. The lines are the ones smoke-template-board.sh
# expects, so both shells print the same. No network.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$utf8 = New-Object System.Text.UTF8Encoding $false
$FIX = Join-Path $here "tests\fixtures\template-board"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-tplboard-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }

try {
  # a plugin root of its own: scripts, schema and a template location the scenarios change
  $plugin = Join-Path $tmp "plugin"
  New-Item -ItemType Directory (Join-Path $plugin "templates") | Out-Null
  New-Item -ItemType Directory (Join-Path $plugin "schema") | Out-Null
  Copy-Item -Recurse (Join-Path $here "scripts") (Join-Path $plugin "scripts")
  Copy-Item (Join-Path $here "schema\nightmill.schema.json") (Join-Path $plugin "schema")
  $S = Join-Path $plugin "scripts\template-board.ps1"

  # a fake gh: it answers from $env:GH_FIX\$env:GH_FIELDS and logs every call to $env:GH_LOG
  $bin = Join-Path $tmp "bin"
  New-Item -ItemType Directory $bin | Out-Null
  Write-Utf8 (Join-Path $bin "gh-fake.ps1") @'
Add-Content -Path $env:GH_LOG -Value ($args -join " ")
$what = "$($args[0]) $($args[1])"
if ($what -eq "auth status") {
  if ($env:GH_NOAUTH) { [Console]::Error.WriteLine("You are not logged into any GitHub hosts."); exit 1 }
  exit 0
}
if ($what -eq "project view" -or $what -eq "project field-list") {
  if ($env:GH_UNREACHABLE) { [Console]::Error.WriteLine("GraphQL: Could not resolve to a ProjectV2 with the number 7."); exit 1 }
  if ($args[1] -eq "view") { [Console]::Out.Write('{"number": 7, "title": "nightmill template", "public": true}'); exit 0 }
  [Console]::Out.Write([IO.File]::ReadAllText((Join-Path $env:GH_FIX $env:GH_FIELDS)))
  exit 0
}
[Console]::Error.WriteLine("unexpected gh call: $($args -join ' ')")
exit 1
'@
  Write-Utf8 (Join-Path $bin "gh.cmd") "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0gh-fake.ps1`" %*`r`nexit /b %errorlevel%`r`n"

  $cfgDefault = Join-Path $tmp "default.json"   # no board section at all: every name takes the schema default
  Write-Utf8 $cfgDefault '{ "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 }, "maintainer": { "name": "Alex" } }'
  $cfgArea = Join-Path $tmp "area.json"         # the area field is renamed
  Write-Utf8 $cfgArea '{ "board": { "areaField": "Module" } }'
  $cfgStatus = Join-Path $tmp "status.json"     # one status is renamed
  Write-Utf8 $cfgStatus '{ "board": { "statuses": { "review": "In review" } } }'
  $cfgCustom = Join-Path $tmp "custom.json"     # a renamed status field, area field and status, all present in fields-custom.json
  Write-Utf8 $cfgCustom '{ "board": { "statusField": "Stage", "areaField": "Module", "statuses": { "review": "In review" } } }'

  $log = Join-Path $tmp "gh.log"
  function Set-Template([string]$json) { Write-Utf8 (Join-Path $plugin "templates\board-template.json") $json }

  # Run-S <config> <fields fixture> [-Extra <arguments>] [-Env <hashtable>] [-Path <PATH>]: Out, Err, Code
  function Run-S([string]$config, [string]$fields, [string]$extra = "", [hashtable]$envVars = @{}, [string]$path = "", [bool]$noConfig = $false) {
    Write-Utf8 $log ""
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $configArg = if ($noConfig) { "" } else { "-Config `"$config`"" }
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$S`" $extra $configArg"
    $psi.WorkingDirectory = $tmp
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($path) { $psi.EnvironmentVariables["PATH"] = $path } else { $psi.EnvironmentVariables["PATH"] = "$bin;" + $env:PATH }
    $psi.EnvironmentVariables["GH_FIX"] = $FIX
    $psi.EnvironmentVariables["GH_FIELDS"] = $fields
    $psi.EnvironmentVariables["GH_LOG"] = $log
    foreach ($k in $envVars.Keys) { $psi.EnvironmentVariables[$k] = $envVars[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $script:Out = ($out -replace "`r`n", "`n").TrimEnd("`n")
    $script:Err = $errTask.Result
    $script:Code = $p.ExitCode
  }

  function Expect([string]$name, [string]$line) {
    if ($script:Code -ne 0) { Fail "$name`: exit code $($script:Code): $($script:Err)" }
    if ($script:Out -ne $line) { Fail "$name`: expected '$line', got '$($script:Out)'" }
    Write-Host "ok: $name"
  }

  Write-Host "== a usable template"
  Set-Template '{ "owner": "acme", "number": 7 }'
  Run-S $cfgDefault "fields-ok.json"
  Expect "usable, every name from the schema defaults" "template: usable (acme/7)"
  Run-S $cfgCustom "fields-custom.json"
  Expect "usable, field and status names from the config" "template: usable (acme/7)"

  Write-Host "== not usable"
  Set-Template '{ "owner": "acme", "number": null }'
  Run-S $cfgDefault "fields-ok.json"
  Expect "number is null" "template: not usable: none published"
  $ghLog = [IO.File]::ReadAllText($log)
  if ($ghLog.Trim()) { Fail "a template without a number must not call gh: $ghLog" }
  Set-Template '{ "owner": "acme", "number": 7 }'
  Run-S $cfgDefault "fields-ok.json" -envVars @{ GH_UNREACHABLE = "1" }
  Expect "gh cannot read the project" "template: not usable: not reachable"
  Run-S $cfgArea "fields-ok.json"
  Expect "the config renames a field the template does not have" "template: not usable: fields differ"
  Run-S $cfgDefault "fields-area-text.json"
  Expect "the area field is not single select" "template: not usable: fields differ"
  Run-S $cfgStatus "fields-ok.json"
  Expect "the config renames a status" "template: not usable: statuses differ"
  Run-S $cfgDefault "fields-missing-status.json"
  Expect "a Status option is missing in the template" "template: not usable: statuses differ"
  Run-S $cfgDefault "fields-swapped-status.json"
  Expect "the Status options are in another order" "template: not usable: statuses differ"

  Write-Host "== reads only"
  Run-S $cfgDefault "fields-ok.json"
  $calls = Get-Content $log
  foreach ($c in @("project view", "project field-list", "auth status")) {
    if (-not ($calls | Where-Object { $_ -like "$c*" })) { Fail "gh $c was never called" }
  }
  if ($calls | Where-Object { $_ -match 'copy|link|item-|field-create|api|mutation|edit|delete' }) { Fail "template-board.ps1 changed or asked for more than it should" }
  if (-not ($calls | Where-Object { $_ -like "project view 7 --owner acme*" })) { Fail "the template is not read from the owner and number of board-template.json: $calls" }

  Write-Host "== errors"
  Run-S $cfgDefault "fields-ok.json" -extra "-Nope"
  if ($Code -ne 2 -or $Out) { Fail "an unknown option must exit 2 with no output, got $Code '$Out'" }
  Run-S $cfgDefault "fields-ok.json" -noConfig $true
  if ($Code -ne 2 -or $Err -notmatch "usage") { Fail "no -Config must exit 2 with the usage: $Code $Err" }
  Run-S (Join-Path $tmp "does-not-exist.json") "fields-ok.json"
  if ($Code -ne 2 -or $Err -notmatch "does-not-exist.json") { Fail "an unreadable config must exit 2 and name the file: $Code $Err" }
  Write-Utf8 (Join-Path $tmp "broken.json") '{ "board": '
  Run-S (Join-Path $tmp "broken.json") "fields-ok.json"
  if ($Code -ne 2) { Fail "a config that is not JSON must exit 2, got $Code" }
  Run-S $cfgDefault "fields-ok.json" -envVars @{ GH_NOAUTH = "1" }
  if ($Code -ne 2 -or $Err -notmatch "not logged in") { Fail "gh not logged in must exit 2 with a message: $Code $Err" }
  Set-Template '{ "owner": "acme", "number": "seven" }'
  Run-S $cfgDefault "fields-ok.json"
  if ($Code -ne 2 -or $Err -notmatch "number must be an integer or null") { Fail "a template number that is not an integer must exit 2: $Code $Err" }
  Set-Template '{ "owner": "", "number": 7 }'
  Run-S $cfgDefault "fields-ok.json"
  if ($Code -ne 2 -or $Err -notmatch "owner must be a non-empty string") { Fail "an empty owner must exit 2: $Code $Err" }
  # no gh at all: only the Windows system folders on the PATH
  Set-Template '{ "owner": "acme", "number": 7 }'
  $sys = "$env:SystemRoot\System32;$env:SystemRoot"
  $ghInSys = $false
  foreach ($d in $sys -split ";") { if (Test-Path (Join-Path $d "gh.exe")) { $ghInSys = $true } }
  if (-not $ghInSys) {
    Run-S $cfgDefault "fields-ok.json" -path $sys
    if ($Code -ne 2 -or $Err -notmatch "gh is not installed") { Fail "a missing gh must exit 2 with a message: $Code $Err" }
  }

  Write-Host "TEMPLATE-BOARD OK"
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

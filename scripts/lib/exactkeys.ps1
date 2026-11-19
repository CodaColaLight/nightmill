# scripts/lib/exactkeys.ps1 - config keys by their exact spelling in PowerShell (iteration 57, #329). Dot-source it:
#   . (Join-Path $PSScriptRoot "lib\exactkeys.ps1")
#   $cfg = Select-ExactKeys $cfg            # right after the ConvertFrom-Json of the project config
# PowerShell's property access ($cfg.worktrees.slots, PSObject.Properties[$k]) ignores case; bash's json_get, the
# schema and validate-config do not. Select-ExactKeys reads schema/nightmill.schema.json of the plugin and, in every
# config object whose schema lists properties (recursing into the properties that match exactly, and into array items
# through items), removes each key that is not one of those properties exactly but equals one of them ignoring case
# ("Slots" next to the schema's "slots"). After that only the exact key can be found. Keys of an object without listed
# properties (worktrees.ports) and keys the schema does not know at all are left alone. When the schema cannot be
# read, the config is returned as it is. The object is changed in place and returned. validate-config.ps1 does not
# call it: it has to see the misspelled key to warn about it.

$script:NmExactKeysSchemaPath = Join-Path $PSScriptRoot "..\..\schema\nightmill.schema.json"
$script:NmExactKeysSchema = $null
$script:NmExactKeysRead = $false

function Remove-NmNearKeys($Node, $Schema) {
  if ($null -eq $Node -or $null -eq $Schema) { return }
  if ($Node -is [System.Management.Automation.PSCustomObject]) {
    $props = $null
    $pp = $Schema.PSObject.Properties | Where-Object { $_.Name -ceq "properties" } | Select-Object -First 1
    if ($pp) { $props = $pp.Value }
    if ($null -eq $props -or -not ($props -is [System.Management.Automation.PSCustomObject])) { return }
    $names = @($props.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($p in @($Node.PSObject.Properties)) {
      if ($names -ccontains $p.Name) {
        $sub = $props.PSObject.Properties | Where-Object { $_.Name -ceq $p.Name } | Select-Object -First 1
        if ($sub) { Remove-NmNearKeys $p.Value $sub.Value }
      } elseif ($names -contains $p.Name) {
        $Node.PSObject.Properties.Remove($p.Name)
      }
    }
  } elseif ($Node -is [System.Array]) {
    $ip = $Schema.PSObject.Properties | Where-Object { $_.Name -ceq "items" } | Select-Object -First 1
    if ($null -eq $ip) { return }
    foreach ($item in $Node) { Remove-NmNearKeys $item $ip.Value }
  }
}

function Select-ExactKeys($Config) {
  if ($null -eq $Config) { return $Config }
  # anything but an object is handed back as it came (the comma keeps an array from being unrolled)
  if (-not ($Config -is [System.Management.Automation.PSCustomObject])) { return , $Config }
  if (-not $script:NmExactKeysRead) {
    $script:NmExactKeysRead = $true
    try {
      $script:NmExactKeysSchema = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:NmExactKeysSchemaPath, (New-Object System.Text.UTF8Encoding($false))))
    } catch { $script:NmExactKeysSchema = $null }
  }
  if ($null -eq $script:NmExactKeysSchema) { return $Config }
  try { Remove-NmNearKeys $Config $script:NmExactKeysSchema } catch { }
  return $Config
}

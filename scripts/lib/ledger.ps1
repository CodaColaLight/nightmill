# scripts/lib/ledger.ps1 - the stage record (iteration 41): the clock, the UTC stamp, the duration text and the append
# of one line to <worktrees.root>\.slots\ledger.tsv. Dot-source it:  . (Join-Path $PSScriptRoot "lib\ledger.ps1")
# PowerShell twin of lib/ledger.sh. Used by slot.ps1 (it writes the record) and stages.ps1 (it reads it).
#
#   Get-LedgerClock               seconds since 1970, UTC
#   Get-LedgerStamp <seconds>     yyyy-MM-ddTHH:mm:ssZ (UTC)
#   Get-LedgerEpoch <stamp>       the inverse: seconds since 1970 of yyyy-MM-ddTHH:mm:ss[Z], read as UTC
#   Format-LedgerDuration <s>     0s, 42s, 1m05s, 39m00s, 1h40m, 26h03m
#   Add-LedgerLine <path> <fields>   one line, the fields joined by a tab; a failed write is tried again (21 tries in
#                                 all, 0.25 s apart), then one note on standard error; never throws
#
# NIGHTMILL_CLOCK_FILE is for the tests only: when it is set, the clock is the first line of that file (seconds since
# 1970, 1 to 12 digits), read again at every reading, so a test moves the clock by writing the file. A set but unusable
# file gives one note on standard error and the system clock.

$script:ledgerNoted = $false

function Get-LedgerClock {
  $f = $env:NIGHTMILL_CLOCK_FILE
  if ($f) {
    $v = ""
    try {
      if (Test-Path -LiteralPath $f -PathType Leaf) {
        $all = [System.IO.File]::ReadAllText($f)
        $v = @($all -split "`n")[0].TrimEnd("`r")
      }
    } catch { $v = "" }
    if ($v -cmatch '^[0-9]{1,12}\z') { return [long]$v }
    if (-not $script:ledgerNoted) {
      [Console]::Error.WriteLine("ledger: NIGHTMILL_CLOCK_FILE is not usable; using the system clock")
      $script:ledgerNoted = $true
    }
  }
  return [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-LedgerStamp([long]$s) {
  return [DateTimeOffset]::FromUnixTimeSeconds($s).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + "Z"
}

function Get-LedgerEpoch([string]$s) {
  $d = [DateTime]::ParseExact($s.Substring(0, 19), "yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
  return [long]([DateTimeOffset]::new($d, [TimeSpan]::Zero)).ToUnixTimeSeconds()
}

function Format-LedgerDuration([long]$t) {
  if ($t -lt 0) { $t = 0 }
  if ($t -lt 60) { return "${t}s" }
  if ($t -lt 3600) { return ("{0}m{1:00}s" -f [long][math]::Floor($t / 60), ($t % 60)) }
  return ("{0}h{1:00}m" -f [long][math]::Floor($t / 3600), [long][math]::Floor(($t % 3600) / 60))
}

function Add-LedgerLine([string]$path, [string[]]$fields) {
  $line = ($fields -join "`t") + "`n"
  $enc = New-Object System.Text.UTF8Encoding $false
  $why = ""
  for ($i = 1; $i -le 21; $i++) {
    try { [System.IO.File]::AppendAllText($path, $line, $enc); return }
    catch {
      $why = @("$($_.Exception.Message)" -split "`r?`n" | Where-Object { $_ -ne "" })[0]
      if ($null -eq $why) { $why = "" }
      $why = $why.Trim()
    }
    if ($i -lt 21) { Start-Sleep -Milliseconds 250 }
  }
  [Console]::Error.WriteLine("slot: the record was not written ($why)")
}

# tests/test-smoke-slot-tar.ps1 - regression for #304: smoke-slot.ps1 claim 5 unpacks the previous release's scripts\
# with a bare `tar`. Started from Git Bash on Windows the first `tar` on the PATH is GNU tar (Git\usr\bin), which reads
# `C:\...` as `host:file` ("Cannot connect to C: resolve failed") and extracts nothing, so prev\slot.ps1 is missing.
# This test takes the extraction out of tests/smoke-slot.ps1 (from the line that creates "$tmp\prev" to the line before
# the next Write-Cfg), runs it on a throwaway repository with a tag under a PATH that puts GNU tar first, and expects the
# archived scripts to be there. It also runs it with Windows' own tar first, as a control. The extraction between those
# two markers has to stay self-contained: it may use $here (the repository), $tag and $tmp, nothing defined elsewhere.
# Without a GNU tar on the machine (Linux, macOS, no Git for Windows) the GNU case is skipped, not forced.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("nm-smoke-tar-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpRoot | Out-Null
$origPath = $env:PATH
function Fail($msg) { $env:PATH = $origPath; Write-Host "FAIL: $msg"; exit 1 }

# the extraction lines of claim 5, as the smoke test writes them
$lines = Get-Content -LiteralPath (Join-Path $here "tests\smoke-slot.ps1")
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'New-Item' -and $lines[$i] -match [regex]::Escape('$tmp\prev"')) { $start = $i; break }
}
if ($start -lt 0) { Fail "tests/smoke-slot.ps1: the line that creates `"`$tmp\prev`" (the start of the previous-version extraction) was not found" }
$end = -1
for ($i = $start + 1; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'Write-Cfg') { $end = $i; break }
}
if ($end -lt 0) { Fail "tests/smoke-slot.ps1: no Write-Cfg line after the previous-version extraction" }
$block = ($lines[$start..($end - 1)]) -join "`n"
if ($block -notmatch 'archive') { Fail "tests/smoke-slot.ps1: the extraction block has no git archive call: $block" }
$sb = [scriptblock]::Create($block)

# a throwaway repository with a release tag and a scripts\ folder, as the smoke test's clone has
$repo = Join-Path $tmpRoot "repo"
New-Item -ItemType Directory -Path (Join-Path $repo "scripts") | Out-Null
Set-Content -LiteralPath (Join-Path $repo "scripts\slot.ps1") -Value "# previous version"
Set-Content -LiteralPath (Join-Path $repo "scripts\lib.ps1") -Value "# a library file"
git -C $repo init -q 2>&1 | Out-Null
git -C $repo add -A 2>&1 | Out-Null
git -C $repo -c user.name=t -c user.email=t@example.invalid commit -q -m "v0.0.1" 2>&1 | Out-Null
git -C $repo -c user.name=t -c user.email=t@example.invalid tag v0.0.1 2>&1 | Out-Null
if (-not (git -C $repo tag --list 'v0.0.1')) { Fail "setup: the throwaway repository has no tag" }

# every tar on the PATH, told apart by --version
$gnuDir = $null; $bsdDir = $null
foreach ($c in @(Get-Command tar -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq "Application" })) {
  $ver = (& $c.Source --version 2>&1 | Out-String)
  if ($ver -match "GNU tar") { if (-not $gnuDir) { $gnuDir = Split-Path $c.Source -Parent } }
  elseif (-not $bsdDir) { $bsdDir = Split-Path $c.Source -Parent }
}

# runs the extraction with $dir first on the PATH; returns the output and the files found under prev\
function Run-Extraction($dir, $label) {
  $tmp = Join-Path $tmpRoot $label
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $tag = "v0.0.1"
  $here = $repo   # the extraction reads the repository from $here, as in the smoke test
  $env:PATH = $dir + [IO.Path]::PathSeparator + $origPath
  $ErrorActionPreference = "Continue"
  try { $out = & $sb 2>&1 | Out-String } finally { $ErrorActionPreference = "Stop"; $env:PATH = $origPath }
  return @{ Out = $out; Tmp = $tmp }
}

Write-Host "== the previous version's scripts unpack when GNU tar is first on the PATH"
if (-not $gnuDir) {
  Write-Host "skipped: no GNU tar on this machine"
} else {
  $r = Run-Extraction $gnuDir "gnu"
  foreach ($f in "slot.ps1", "lib.ps1") {
    if (-not (Test-Path -LiteralPath (Join-Path $r.Tmp "prev\$f"))) {
      Fail "with GNU tar first ($gnuDir) prev\$f was not extracted: $($r.Out)"
    }
  }
}

Write-Host "== the previous version's scripts unpack when Windows' own tar is first on the PATH"
if (-not $bsdDir) {
  Write-Host "skipped: no bsdtar on this machine"
} else {
  $r = Run-Extraction $bsdDir "bsd"
  foreach ($f in "slot.ps1", "lib.ps1") {
    if (-not (Test-Path -LiteralPath (Join-Path $r.Tmp "prev\$f"))) {
      Fail "with bsdtar first ($bsdDir) prev\$f was not extracted: $($r.Out)"
    }
  }
}

Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
Write-Host "ok"

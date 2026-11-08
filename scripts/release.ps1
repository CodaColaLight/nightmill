# scripts/release.ps1 - cut a release of this repository in two steps. main only takes pull requests, so a
# release is prepared as a pull request and tagged after it has merged.
#
#   scripts\release.ps1 -Version X.Y.Z             prepare: branch release/vX.Y.Z with one commit that bumps
#                                                  .claude-plugin/plugin.json, cuts CHANGELOG.md and updates
#                                                  the README's "Version" line; push it and open the pull request
#   scripts\release.ps1 -Version X.Y.Z -Publish   after the merge: tag the release commit vX.Y.Z, push the tag
#                                                  and create the GitHub Release from the changelog section;
#                                                  each step that is already done is skipped, so a run that
#                                                  failed half way is finished by running it again
#   -DryRun     print what would happen, change and push nothing
#   -NoPr       prepare without pushing or opening the pull request (the branch stays local)
#   -NoRelease  publish without creating the GitHub Release (the tag is still pushed)
#
# Exit codes: 0 done, 1 refused (one line "refused: <reason>" on stderr), 2 usage error, a missing tool or an
# unexpected error. Needs git, and gh unless -DryRun, -NoPr or -NoRelease say otherwise. The repository is the
# one this script lives in. Same behaviour as release.sh.
param(
  [string]$Version,
  [switch]$Publish,
  [switch]$DryRun,
  [switch]$NoPr,
  [switch]$NoRelease
)
$ErrorActionPreference = "Stop"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Refuse([string]$m) { [Console]::Error.WriteLine("refused: $m"); exit 1 }
function Usage {
  [Console]::Error.WriteLine("usage: scripts\release.ps1 -Version X.Y.Z [-DryRun] [-NoPr]")
  [Console]::Error.WriteLine("       scripts\release.ps1 -Version X.Y.Z -Publish [-DryRun] [-NoRelease]")
  exit 2
}
function Need([string]$tool) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine("missing tool: $tool"); exit 2 }
}

if (-not $Version) { Usage }
Need git
if (-not $DryRun) {
  if ($Publish) { if (-not $NoRelease) { Need gh } } else { if (-not $NoPr) { Need gh } }
}

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# G: run git, return its output lines, leave the exit code in $script:rc. (Not named Git: a function of that
# name would shadow the git command.) Standard error is not redirected, so it cannot turn into an exception.
function G { $o = & git @args; $script:rc = $LASTEXITCODE; return $o }
function Text($lines) { return (($lines | ForEach-Object { "$_" }) -join "`n") }

$PJ = ".claude-plugin/plugin.json"
$tag = "v$Version"
$rbranch = "release/v$Version"

# --- helpers ---------------------------------------------------------------------------------------------

# The version in plugin.json text when there is exactly one version line, else $null.
function Get-JsonVersion([string]$text) {
  $m = [regex]::Matches($text, '(?m)^\s*"version":\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*,?\s*$')
  if ($m.Count -ne 1) { return $null }
  return $m[0].Groups[1].Value
}

function Test-Greater([string]$a, [string]$b) {
  $x = $a.Split("."); $y = $b.Split(".")
  for ($i = 0; $i -lt 3; $i++) {
    if ([int]$x[$i] -gt [int]$y[$i]) { return $true }
    if ([int]$x[$i] -lt [int]$y[$i]) { return $false }
  }
  return $false
}

# ok, empty (nothing under the heading) or missing (no heading)
function Get-UnreleasedState([string]$text) {
  $found = $false; $inside = $false; $content = $false
  foreach ($l in ($text -split "`r?`n")) {
    if (-not $inside) { if ($l -match '^## Unreleased\s*$') { $found = $true; $inside = $true }; continue }
    if ($l -match '^## ') { break }
    if ($l -match '\S') { $content = $true }
  }
  if (-not $found) { return "missing" }
  if (-not $content) { return "empty" }
  return "ok"
}

# The body of the changelog section for a version, without leading or trailing blank lines.
function Get-Section([string]$text, [string]$ver) {
  $out = New-Object System.Collections.Generic.List[string]
  $p = $false
  foreach ($l in ($text -split "`r?`n")) {
    if ($l -match '^## ') {
      if ($p) { break }
      if ($l.StartsWith("## $ver (")) { $p = $true; continue }
    }
    if ($p) { $out.Add($l) }
  }
  while ($out.Count -gt 0 -and $out[0].Trim() -eq "") { $out.RemoveAt(0) }
  while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq "") { $out.RemoveAt($out.Count - 1) }
  return ($out -join "`n")
}

# The text of a file on origin/main, or $null.
function Get-OriginFile([string]$path) {
  $o = G show "origin/main:$path"
  if ($script:rc -ne 0) { return $null }
  return (Text $o)
}

function Test-TagExists {
  $null = G rev-parse -q --verify "refs/tags/$tag"
  if ($script:rc -eq 0) { return $true }
  return ((Text (G ls-remote --tags origin "refs/tags/$tag")).Trim() -ne "")
}

# The commit the tag points at on origin (peeled), or "" when origin has no such tag.
function Get-RemoteTagCommit {
  $lines = @(G ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")
  if ($script:rc -ne 0) { Refuse "cannot list the tags on origin" }
  $plain = ""; $peeled = ""
  foreach ($l in $lines) {
    $f = "$l" -split "\s+"
    if ($f.Count -lt 2) { continue }
    if ($f[1] -eq "refs/tags/$tag^{}") { $peeled = $f[0] } elseif ($f[1] -eq "refs/tags/$tag") { $plain = $f[0] }
  }
  if ($peeled) { return $peeled }
  return $plain
}

try {
  # --- checks both modes make ------------------------------------------------------------------------------

  $null = G rev-parse --git-dir
  if ($script:rc -ne 0) { Refuse "$root is not a git repository" }
  if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { Refuse "version must be X.Y.Z with digits only, got '$Version'" }
  if ((Text (G status --porcelain)).Trim() -ne "") { Refuse "working tree has uncommitted changes" }
  $null = G fetch -q --no-tags origin main
  if ($script:rc -ne 0) { Refuse "cannot fetch origin" }

  # --- publish -------------------------------------------------------------------------------------------

  if ($Publish) {
    $ohold = Get-JsonVersion (Get-OriginFile $PJ)
    if ($ohold -ne $Version) { Refuse "origin/main does not hold version $Version in $PJ (is the release pull request merged?)" }
    $ocl = Get-OriginFile "CHANGELOG.md"
    if (-not $ocl -or $ocl -notmatch ("(?m)^## " + [regex]::Escape($Version) + " \(")) { Refuse "CHANGELOG.md on origin/main has no heading for $Version" }
    $ord = Get-OriginFile "README.md"
    if (-not $ord -or $ord -notmatch ("(?m)^Version " + [regex]::Escape($Version) + "\.")) { Refuse "README.md on origin/main has no 'Version $Version.' line" }

    # the oldest commit on origin/main's first-parent history that holds this version: the merge of the
    # release pull request, not whatever main has become since
    $cand = $null
    foreach ($c in @(G rev-list --first-parent origin/main)) {
      $o = G show "${c}:$PJ"
      $v = if ($script:rc -eq 0) { Get-JsonVersion (Text $o) } else { $null }
      if ($v -eq $Version) { $cand = "$c" } else { break }
    }
    if (-not $cand) { Refuse "no commit on origin/main holds version $Version" }

    # every step is skipped when it is already done, so a run that failed half way can be run again; only a
    # tag at another commit is refused
    $short = (Text (G rev-parse --short $cand)).Trim()
    $ltag = (Text (G rev-parse -q --verify "refs/tags/$tag^{commit}")).Trim()
    if ($script:rc -ne 0) { $ltag = "" }
    $rtag = Get-RemoteTagCommit
    if ($ltag -and $ltag -ne $cand) { Refuse ("tag $tag already exists at another commit (" + (Text (G rev-parse --short $ltag)).Trim() + ", not $short)") }
    if ($rtag -and $rtag -ne $cand) { Refuse ("tag $tag already exists on origin at another commit (" + $rtag.Substring(0, 7) + ", not $short)") }

    if ($DryRun) {
      Write-Output ("would tag " + (Text (G log -1 --format="%h %s" $cand)) + " as $tag, push the tag and create the GitHub Release (steps already done are skipped)")
      exit 0
    }
    if (-not $ltag -and -not $rtag) {
      $null = G tag -a $tag -m "nightmill $Version" $cand
      if ($script:rc -ne 0) { throw "git tag failed" }
    }
    if (-not $rtag) {
      $null = G push -q origin "refs/tags/$tag"
      if ($script:rc -ne 0) { throw "git push of the tag failed" }
      Write-Output "tagged $tag at $short"
    } else {
      Write-Output "tag $tag is already on origin at $short"
    }
    $haveRelease = $false
    if (-not $NoRelease) {
      # stderr is not redirected: under Stop a redirected native stderr becomes an exception
      $null = & gh release view $tag
      $haveRelease = ($LASTEXITCODE -eq 0)
      if ($haveRelease) { Write-Output "the GitHub Release $tag already exists" }
    }
    if (-not $NoRelease -and -not $haveRelease) {
      $notes = [IO.Path]::GetTempFileName()
      [IO.File]::WriteAllText($notes, ((Get-Section $ocl $Version) + "`n"), $utf8)
      & gh release create $tag --title "nightmill $Version" --notes-file $notes --verify-tag --latest
      $ghrc = $LASTEXITCODE
      Remove-Item $notes -ErrorAction SilentlyContinue
      if ($ghrc -ne 0) { throw "gh release create failed" }
    }
    exit 0
  }

  # --- prepare -------------------------------------------------------------------------------------------

  $branch = (Text (G branch --show-current)).Trim()
  if ($branch -ne "main") { Refuse ("not on main (on '" + $(if ($branch) { $branch } else { "a detached HEAD" }) + "')") }
  if ((Text (G rev-parse HEAD)).Trim() -ne (Text (G rev-parse origin/main)).Trim()) { Refuse "main is not equal to origin/main (pull or push first)" }

  $cur = Get-JsonVersion ([IO.File]::ReadAllText((Join-Path $root $PJ), $utf8))
  if (-not $cur) { Refuse "$PJ does not have exactly one version line" }
  if (-not (Test-Greater $Version $cur)) { Refuse "version $Version is not greater than the current $cur" }

  $clText = [IO.File]::ReadAllText((Join-Path $root "CHANGELOG.md"), $utf8)
  $state = Get-UnreleasedState $clText
  if ($state -eq "missing") { Refuse "CHANGELOG.md has no '## Unreleased' heading" }
  if ($state -eq "empty") { Refuse "the Unreleased section of CHANGELOG.md is empty" }
  $rdText = [IO.File]::ReadAllText((Join-Path $root "README.md"), $utf8)
  if ([regex]::Matches($rdText, '(?m)^Version [0-9]+\.[0-9]+\.[0-9]+\.').Count -ne 1) { Refuse "README.md does not have exactly one line starting with 'Version X.Y.Z.'" }

  if (Test-TagExists) { Refuse "tag $tag already exists" }
  $null = G show-ref --verify -q "refs/heads/$rbranch"
  $haveLocal = ($script:rc -eq 0)
  $haveRemote = ((Text (G ls-remote --heads origin $rbranch)).Trim() -ne "")
  if ($haveLocal -or $haveRemote) { Refuse "branch $rbranch already exists" }

  $date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
  Write-Output "release $cur -> $Version ($date)"
  Write-Output "  ${PJ}: version $cur -> $Version"
  Write-Output "  CHANGELOG.md: the Unreleased entries move under '## $Version ($date)'"
  Write-Output "  README.md: 'Version $cur.' -> 'Version $Version.'"
  Write-Output "  branch $rbranch, one commit 'Release $Version', pull request 'Release $Version'"
  if ($DryRun) { Write-Output "(dry run: nothing was changed)"; exit 0 }

  $null = G switch -q -c $rbranch
  if ($script:rc -ne 0) { throw "git switch failed" }
  try {
    $pjText = [IO.File]::ReadAllText((Join-Path $root $PJ), $utf8)
    $pjText = [regex]::Replace($pjText, '(?m)^(\s*"version":\s*")[0-9]+\.[0-9]+\.[0-9]+(")', ('${1}' + $Version + '${2}'))
    [IO.File]::WriteAllText((Join-Path $root $PJ), $pjText, $utf8)

    $nl = if ($clText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($l in ($clText -split "`r?`n")) {
      $out.Add($l)
      if (-not $done -and $l -match '^## Unreleased\s*$') { $out.Add(""); $out.Add("## $Version ($date)"); $done = $true }
    }
    [IO.File]::WriteAllText((Join-Path $root "CHANGELOG.md"), ($out -join $nl), $utf8)

    $rdNew = [regex]::Replace($rdText, '(?m)^Version [0-9]+\.[0-9]+\.[0-9]+\.', "Version $Version.")
    [IO.File]::WriteAllText((Join-Path $root "README.md"), $rdNew, $utf8)

    $null = G add $PJ CHANGELOG.md README.md
    if ($script:rc -ne 0) { throw "git add failed" }
    $null = G commit -q -m "Release $Version"
    if ($script:rc -ne 0) { throw "git commit failed" }
  }
  catch {
    $null = G reset -q --hard HEAD
    $null = G switch -q main
    $null = G branch -D $rbranch
    throw
  }

  if ($NoPr) {
    $null = G switch -q main
    Write-Output "prepared branch $rbranch (not pushed: -NoPr)"
    exit 0
  }

  $body = [IO.Path]::GetTempFileName()
  $text = (Get-Section ([IO.File]::ReadAllText((Join-Path $root "CHANGELOG.md"), $utf8)) $Version) + "`n`nAfter this merges, run ``scripts/release.ps1 -Version $Version -Publish`` (or ``scripts/release.sh --version $Version --publish``) to tag it and create the GitHub Release.`n"
  [IO.File]::WriteAllText($body, $text, $utf8)
  $null = G push -q -u origin $rbranch
  if ($script:rc -ne 0) { throw "git push failed" }
  & gh pr create --base main --head $rbranch --title "Release $Version" --body-file $body
  $ghrc = $LASTEXITCODE
  Remove-Item $body -ErrorAction SilentlyContinue
  if ($ghrc -ne 0) { throw "gh pr create failed" }
  $null = G switch -q main
}
catch {
  [Console]::Error.WriteLine("error: " + $_.Exception.Message)
  exit 2
}

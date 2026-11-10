# scripts/lib/baseconfig.ps1 - the configuration that governs a run: .claude/nightmill.json on the base branch, not the
# working tree's file (iteration 48, #111). Dot-source it:  . (Join-Path $PSScriptRoot "lib\baseconfig.ps1")
# PowerShell twin of lib/baseconfig.sh, the same rule and the same lines.
#
#   Get-BaseConfig <main checkout>
#
# The rule (the workflow skill's **The configuration**):
#   1. With refs/remotes/origin/HEAD (origin/<X>), the base ref is origin/HEAD; no pull request can change it.
#   2. Without it, but with a remote-tracking branch of origin: stop (run git remote set-head origin --auto once).
#      With no remote-tracking branch at all (no origin, never fetched): the working tree's file, with a note.
#   3. git show origin/HEAD:.claude/nightmill.json; when the file is not on that branch: the working tree's file, with
#      a note. Text that is not valid JSON stops.
#   4. When git.baseBranch (<B>, default main) of that configuration is not <X>: git show origin/<B>:... instead, and
#      a stop when that fails. git.baseBranch of that second file is not followed.
#   5. No fetch: the last fetched state is read.
# Returns an object:
#   Text   the configuration's text (git's output decoded as UTF-8, a leading BOM removed); $null after a fallback
#   Path   the working tree's file (read it after a fallback; it may not exist: the caller says "no <path>")
#   From   origin/HEAD:.claude/nightmill.json, origin/<B>:.claude/nightmill.json, or the working tree's path
#   Note   the fallback's line ("" when there was none); the caller prints it on standard error
#   Stop   the stop line ("" when there was none); the caller exits

# Invoke-BaseGit <main> <arguments>: git in that checkout, its output read as UTF-8 by the process, not the console (so
# no native error record and no code page); Out, Code
function Invoke-BaseGit([string]$m, [string[]]$arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $all = @("-C", $m) + @($arguments)
  $psi.Arguments = (@($all | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " ")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  $null = $errTask.Result
  return [pscustomobject]@{ Out = $out; Code = $p.ExitCode }
}

function Get-BaseConfig([string]$m) {
  $c = ".claude/nightmill.json"
  $path = Join-Path $m ".claude\nightmill.json"
  $r = [pscustomobject]@{ Text = $null; Path = $path; From = $path; Note = ""; Stop = "" }
  $h = Invoke-BaseGit $m @("symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD")
  $head = ""
  if ($h.Code -eq 0 -and $h.Out) { $head = $h.Out.Trim() }
  if (-not $head) {
    $any = Invoke-BaseGit $m @("for-each-ref", "--count=1", "refs/remotes/origin")
    if ($any.Code -eq 0 -and $any.Out -and $any.Out.Trim()) {
      $r.Stop = "origin/HEAD is not set, so the base branch's configuration cannot be found; run git remote set-head origin --auto once"
      return $r
    }
    $r.Note = "nightmill: no branch of origin is known; the configuration is read from the working tree."
    return $r
  }
  $s = Invoke-BaseGit $m @("show", "origin/HEAD:$c")
  if ($s.Code -ne 0) {
    $r.Note = "nightmill: origin/HEAD has no .claude/nightmill.json; the configuration is read from the working tree."
    return $r
  }
  $ref = "origin/HEAD"
  $text = $s.Out.TrimStart([char]0xFEFF)
  if ($text.Trim() -eq "") { $r.Stop = "the configuration on $ref is not valid JSON: the text is empty"; return $r }
  try { $doc = ConvertFrom-Json -InputObject $text } catch { $r.Stop = "the configuration on $ref is not valid JSON: $($_.Exception.Message)"; return $r }
  $b = "main"
  if ($doc -and $doc.git -and $doc.git.baseBranch) { $b = [string]$doc.git.baseBranch }
  $x = $head
  if ($x.StartsWith("origin/")) { $x = $x.Substring(7) }
  if ($x -cne $b) {
    $ref = "origin/$b"
    $s = Invoke-BaseGit $m @("show", "${ref}:$c")
    if ($s.Code -ne 0) {
      $r.Stop = "origin/$b has no .claude/nightmill.json (git.baseBranch of the configuration on origin/HEAD)"
      return $r
    }
    $text = $s.Out.TrimStart([char]0xFEFF)
    if ($text.Trim() -eq "") { $r.Stop = "the configuration on $ref is not valid JSON: the text is empty"; return $r }
    try { $null = ConvertFrom-Json -InputObject $text } catch { $r.Stop = "the configuration on $ref is not valid JSON: $($_.Exception.Message)"; return $r }
  }
  $r.Text = $text
  $r.From = "${ref}:$c"
  return $r
}

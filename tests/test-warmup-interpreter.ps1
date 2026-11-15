# tests/test-warmup-interpreter.ps1 - regression for bug #133: a warm-up command is one string, and one interpreter runs it
# in both shells (bash -c). The PowerShell twins ran it with Invoke-Expression, so `echo a && echo b` failed in Windows
# PowerShell 5.1 (no &&) while slot.sh and new-worktree.sh ran it. Here slot.ps1 -Take and new-worktree.ps1 run that
# warm-up and it must work; the schema description of warmup[].command must name the interpreter. Every check runs,
# then the failures are listed.
# Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-warmup-interp-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null
$script:failures = @()
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:failures += $msg }
$utf8n = New-Object System.Text.UTF8Encoding $false

# Run <script> <arguments>: a PowerShell script of the project in a child process, started in the main checkout
function Run([string]$script, [string]$arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here "scripts\$script")`" $arguments"
  $psi.WorkingDirectory = "$tmp\work"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Out = ($out -replace "`r`n", "`n"); Err = ($errTask.Result -replace "`r`n", "`n"); Code = $p.ExitCode }
}
function Gq { & git @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "setup: git $($args -join ' ') failed" } }

# Check-Warm <name> <result> <file>: the script exited 0 and its warm-up wrote 'b' to the file
function Check-Warm([string]$name, $r, [string]$file) {
  if ($r.Code -ne 0) { Fail "$name with the warm-up 'echo a && echo b > warmed.txt' exited $($r.Code): $($r.Out) / $($r.Err)"; return }
  if (-not (Test-Path $file)) { Fail "${name}: the warm-up did not run to its end (no warmed.txt after 'echo a && echo b > warmed.txt')"; return }
  $text = [System.IO.File]::ReadAllText($file)
  if ($text.Trim() -ne "b") { Fail "${name}: warmed.txt holds '$text', not b" }
}

# Check-Quoted <name> <file>: the warm-up `X=1; echo "a b" "$X" 'c $d' > quoted.txt; echo "it's" >> quoted.txt` wrote what
# bash -c makes of it (tests/test-warmup-interpreter.sh pins the same two lines against the bash twins): the inner double
# quotes kept (a b is one word), $X expanded by bash (1), the single-quoted $d left alone, the ; a command separator. A
# command handed to bash as an argument from Windows PowerShell 5.1 loses its inner double quotes and fails this.
function Check-Quoted([string]$name, [string]$file) {
  if (-not (Test-Path $file)) { Fail "${name}: the quoting warm-up did not run to its end (no quoted.txt)"; return }
  $text = ([System.IO.File]::ReadAllText($file) -replace "`r`n", "`n")
  $expect = "a b 1 c `$d`nit's`n"
  if ($text -ne $expect) { Fail "${name}: quoted.txt holds '$($text -replace "`n", '\n')', not what bash -c makes of the quoting warm-up: '$($expect -replace "`n", '\n')'" }
}

try {
  Write-Host "== a warm-up of 'echo a && echo b' works in slot.ps1 -Take and new-worktree.ps1"
  Gq init -q --bare "$tmp\origin.git"
  Gq init -q -b main "$tmp\work"
  Gq -C "$tmp\work" config core.autocrlf false
  New-Item -ItemType Directory "$tmp\work\.claude", "$tmp\work\client" | Out-Null
  $cfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "warmup": [
      { "dir": "client", "command": "echo a && echo b > warmed.txt" },
      { "dir": "client", "command": "X=1; echo \"a b\" \"$X\" 'c $d' > quoted.txt; echo \"it's\" >> quoted.txt" }
    ]
  }
}
'@
  [System.IO.File]::WriteAllText("$tmp\work\.claude\nightmill.json", $cfg, $utf8n)
  [System.IO.File]::WriteAllText("$tmp\work\client\keep.txt", "x`n")
  Gq -C "$tmp\work" add -A
  Gq -C "$tmp\work" -c user.name=t -c user.email=t@example.invalid commit -qm init
  Gq -C "$tmp\work" remote add origin "$tmp\origin.git"
  Gq -C "$tmp\work" push -q origin main
  Gq -C "$tmp\work" remote set-head origin main

  Check-Warm "slot.ps1 -Take" (Run "slot.ps1" "-Take feat/warm") "$tmp\wt\slot-1\client\warmed.txt"
  Check-Warm "new-worktree.ps1" (Run "new-worktree.ps1" "feat/extra") "$tmp\wt\feat-extra\client\warmed.txt"

  Write-Host "== a warm-up with double quotes, single quotes, a `$VAR and a ; gives the same file as bash -c"
  Check-Quoted "slot.ps1 -Take" "$tmp\wt\slot-1\client\quoted.txt"
  Check-Quoted "new-worktree.ps1" "$tmp\wt\feat-extra\client\quoted.txt"

  Write-Host "== the schema says which interpreter runs warmup[].command"
  $schema = [System.IO.File]::ReadAllText((Join-Path $here "schema\nightmill.schema.json"), $utf8n) | ConvertFrom-Json
  $desc = [string]$schema.properties.worktrees.properties.warmup.items.properties.command.description
  if (-not $desc) { Fail "the schema has no description for worktrees.warmup[].command" }
  elseif ($desc -notmatch '(?i)bash') { Fail "the schema description of worktrees.warmup[].command does not name the interpreter (bash): $desc" }
} finally {
  Set-Location $env:TEMP
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:failures.Count -gt 0) { Write-Host "$($script:failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "WARMUP INTERPRETER OK"

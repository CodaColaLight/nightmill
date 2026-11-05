# tests/smoke-slot.ps1 - slot.ps1 against a throwaway repository: status, take (with warm-up and
# port hints), a full board, the lockfile-hash skip, abandon. -Release is not covered (it needs gh
# and a merged PR). Runs on Windows PowerShell 5.1 and pwsh.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$S = Join-Path $here "scripts\slot.ps1"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nightmill-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }
function Slot { param([Parameter(ValueFromRemainingArguments = $true)]$a)
  # stdout only: redirecting a native command's stderr in Windows PowerShell 5.1 turns git's
  # progress lines into terminating errors. Failures are checked through the exit code.
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $S @a | Out-String
  $script:code = $LASTEXITCODE
  $out
}

try {
  git init -q --bare "$tmp\origin.git"
  git init -q -b main "$tmp\work"
  Set-Location "$tmp\work"
  git config core.autocrlf false
  New-Item -ItemType Directory ".claude", "client" | Out-Null
  $cfg = @'
{
  "github": { "owner": "acme", "repo": "widgets", "projectNumber": 1 },
  "maintainer": { "name": "Alex" },
  "verification": { "check": "true" },
  "git": { "baseBranch": "main" },
  "worktrees": {
    "root": "../wt",
    "slots": 2,
    "ports": { "server": 8100 },
    "warmup": [ { "dir": "client", "command": "echo warm > warmed.txt", "lockfile": "client/lock.txt" } ],
    "runHints": [ "PORT={port.server} slot {slot}" ]
  }
}
'@
  [System.IO.File]::WriteAllText("$tmp\work\.claude\nightmill.json", $cfg)
  [System.IO.File]::WriteAllText("$tmp\work\client\lock.txt", "v1`n")
  [System.IO.File]::WriteAllText("$tmp\work\.gitignore", "warmed.txt`n")
  git add -A
  git -c user.name=t -c user.email=t@example.invalid commit -qm init
  git remote add origin "$tmp\origin.git"
  git push -q origin main

  Write-Host "== status before anything"
  $out = Slot -Status
  if ($out -notmatch "slot 1  not created yet free") { Fail "initial status: $out" }

  Write-Host "== take slot 1"
  $out = Slot -Take feat/a
  if ($code -ne 0) { Fail "take exited $code`: $out" }
  if ($out -notmatch "Slot 1 is yours") { Fail "take did not report slot 1: $out" }
  if ($out -notmatch "port server: 8101") { Fail "port hint: $out" }
  if ($out -notmatch "PORT=8101 slot 1") { Fail "run hint placeholders: $out" }
  if (-not (Test-Path "$tmp\wt\slot-1\client\warmed.txt")) { Fail "warm-up did not run" }
  if ((git -C "$tmp\wt\slot-1" branch --show-current) -ne "feat/a") { Fail "branch in slot 1" }
  if (-not (Test-Path "$tmp\wt\.slots\slot-1.json")) { Fail "marker" }

  Write-Host "== take slot 2, third take fails"
  $out = Slot -Take feat/b
  if ($out -notmatch "Slot 2 is yours") { Fail "take slot 2: $out" }
  $out = Slot -Take feat/c
  if ($code -eq 0) { Fail "third take should fail" }
  $out = Slot -Status
  if ($out -notmatch "busy: feat/a") { Fail "status shows slot 1 busy: $out" }

  Write-Host "== -Porcelain: one tab separated line per slot"
  $out = Slot -Status -Porcelain
  $lines = @($out -split "`r?`n" | Where-Object { $_ -ne "" })
  if ($lines.Count -ne 2) { Fail "porcelain line count: $out" }
  $f1 = $lines[0] -split "`t"
  $f2 = $lines[1] -split "`t"
  if ($f1[0] -ne "1" -or $f1[1] -ne "busy" -or $f1[2] -ne "feat/a" -or -not $f1[3]) { Fail "porcelain line for slot 1: $($lines[0])" }
  if ($f2[0] -ne "2" -or $f2[1] -ne "busy" -or $f2[2] -ne "feat/b") { Fail "porcelain line for slot 2: $($lines[1])" }
  $out = Slot -Status
  if ($out -notmatch "slots = 2") { Fail "status without -Porcelain changed: $out" }

  Write-Host "== warm-up skipped while the lockfile is unchanged"
  $null = Slot -Abandon 1
  Remove-Item "$tmp\wt\slot-1\client\warmed.txt"
  $null = Slot -Take feat/d
  if (Test-Path "$tmp\wt\slot-1\client\warmed.txt") { Fail "warm-up ran again although the lockfile hash is unchanged" }

  Write-Host "== WORKER_SLOTS overrides the count"
  $env:WORKER_SLOTS = "3"
  $out = Slot -Status
  Remove-Item Env:WORKER_SLOTS
  if ($out -notmatch "slot 3") { Fail "WORKER_SLOTS override: $out" }

  Write-Host "== abandon both"
  $null = Slot -Abandon 1
  $null = Slot -Abandon 2
  $out = Slot -Status
  if ($out -notmatch "slot 2  ready           free") { Fail "slot 2 free after abandon: $out" }
  $out = Slot -Status -Porcelain
  $lines = @($out -split "`r?`n" | Where-Object { $_ -ne "" })
  if ($lines.Count -ne 2 -or $lines[0] -ne "1`tfree" -or $lines[1] -ne "2`tfree") { Fail "porcelain after abandon: $out" }

  Write-Host "SMOKE OK" -ForegroundColor Green
} finally {
  Set-Location $here
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# tests/smoke-guard.ps1 - scripts/guard.ps1 (the PreToolUse guard, twin of guard.sh; iteration 47, #110): the same
# cases as tests/smoke-guard.sh. Exit 2 and one line on stderr for a refusal, exit 0 and no output otherwise. A stub
# gh.cmd is first on the PATH. Each case runs in a child powershell process with the event on stdin.
$ErrorActionPreference = "Stop"
$here = Split-Path $PSScriptRoot -Parent
$G = Join-Path $here "scripts\guard.ps1"
$psExe = (Get-Command powershell).Source
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nm-guard-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fail($msg) { Write-Host "FAIL: $msg"; exit 1 }
if (-not (Test-Path $G)) { Fail "scripts/guard.ps1 does not exist" }

$bin = Join-Path $tmp "bin"; New-Item -ItemType Directory -Path $bin | Out-Null
$proj = Join-Path $tmp "proj"; New-Item -ItemType Directory -Path (Join-Path $proj ".claude") -Force | Out-Null
$trunk = Join-Path $tmp "trunk"; New-Item -ItemType Directory -Path (Join-Path $trunk ".claude") -Force | Out-Null
$bare = Join-Path $tmp "bare"; New-Item -ItemType Directory -Path $bare | Out-Null
[IO.File]::WriteAllText((Join-Path $proj ".claude\nightmill.json"), '{ "github": { "owner": "o", "projectNumber": 7 } }')
[IO.File]::WriteAllText((Join-Path $trunk ".claude\nightmill.json"), '{ "github": { "owner": "o", "projectNumber": 7 }, "git": { "baseBranch": "trunk" } }')
$log = Join-Path $tmp "gh.log"
$failFlag = Join-Path $tmp "gh.fail"
$stub = @(
  "@echo off",
  "echo called>>`"$log`"",
  "if `"%1`"==`"project`" if `"%2`"==`"field-list`" goto fl",
  "exit /b 0",
  ":fl",
  "if exist `"$failFlag`" exit /b 1",
  "echo Ready`tRID1",
  "echo Approved`tAID2",
  "exit /b 0"
)
[IO.File]::WriteAllText((Join-Path $bin "gh.cmd"), (($stub -join "`r`n") + "`r`n"))

# Invoke-Guard <project dir> <stdin text>; returns Out, Err, Code
function Invoke-Guard([string]$dir, [string]$stdin) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$G`""
  $psi.WorkingDirectory = $tmp
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables["CLAUDE_PROJECT_DIR"] = $dir
  $psi.EnvironmentVariables["PATH"] = $bin + ";" + $env:PATH
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($stdin)
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $out; Err = $err.Trim(); Code = $p.ExitCode }
}

function Event-Json([string]$tool, [string]$cmd) {
  $ev = @{ tool_name = $tool; tool_input = @{ command = $cmd }; cwd = $tmp }
  return ($ev | ConvertTo-Json -Depth 5 -Compress)
}

# Check <name> <tool> <command> <exit code> [stderr text] [project dir]
function Check($name, $tool, $cmd, $code, $text = "", $dir = $proj) {
  $r = Invoke-Guard $dir (Event-Json $tool $cmd)
  if ($r.Code -ne $code) { Fail "$name : expected exit $code, got $($r.Code) (stderr: $($r.Err))" }
  if ($code -eq 0) {
    if ($r.Err -ne "") { Fail "$name : expected no stderr, got: $($r.Err)" }
    if ($r.Out.Trim() -ne "") { Fail "$name : expected no output, got: $($r.Out)" }
  } else {
    if (-not $r.Err.StartsWith("nightmill guard: refused: ")) { Fail "$name : not a guard line: $($r.Err)" }
    if (@($r.Err -split "`r?`n").Count -ne 1) { Fail "$name : expected one stderr line, got: $($r.Err)" }
    if ($text -ne "" -and -not $r.Err.Contains($text)) { Fail "$name : stderr lacks '$text': $($r.Err)" }
  }
}
function B($name, $cmd, $code, $text = "", $dir = $proj) { Check $name "Bash" $cmd $code $text $dir }

$noauto = "a merge without --auto."
try {
  Write-Host "== a merge needs --auto"
  B "merge auto" 'gh pr merge 5 --auto --squash' 0
  B "merge squash" 'gh pr merge 5 --squash' 2 $noauto
  B "merge bare" 'gh pr merge 5' 2 $noauto
  B "merge with -R" 'gh -R o/r pr merge 5 --squash' 2 $noauto
  B "disable auto" 'gh pr merge 5 --disable-auto' 0
  B "rest merge" 'gh api -X PUT repos/o/r/pulls/5/merge' 2 "a merge through gh api."
  B "graphql merge" 'gh api graphql -f query=''mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }''' 2 "a merge through gh api."
  B "graphql auto merge" 'gh api graphql -f query=''mutation { enablePullRequestAutoMerge(input: {pullRequestId: "x"}) { clientMutationId } }''' 0
  B "merge after status" 'git status && gh pr merge 5 --squash' 2 $noauto
  B "commit message names a merge" 'git commit -m "gh pr merge 5 --squash"' 0

  Write-Host "== quotes"
  B "double quoted semicolon" 'git commit -m "x; gh pr merge 5 --squash"' 0
  B "single quoted operators" "git commit -m 'a && gh pr merge 5 | b'" 0
  B "escaped quote" 'git commit -m "a \" ; gh pr merge 5"' 0
  B "merge then quoted semicolon" 'gh pr merge 5 --squash; echo "a;b"' 2 $noauto
  B "command substitution" 'echo "$(gh pr merge 5 --squash)"' 2 $noauto
  Check "powershell tool, quoted merge" "PowerShell" 'git commit -m "x; gh pr merge 5"' 0

  Write-Host "== --admin"
  B "admin next to auto" 'gh pr merge 5 --auto --admin --squash' 2 "gh pr merge with --admin."

  Write-Host "== force push and push to the base branch"
  B "force slot form" 'git -C /w/slot-1 push --force origin feat/5-x' 2 "a force push."
  B "force short" 'git -C /w/slot-1 push -f origin feat/5-x' 2 "a force push."
  B "force cluster" 'git push -uf origin feat/5-x' 2 "a force push."
  B "force plus refspec" 'git -C /w/slot-1 push origin +feat/5-x' 2 "a force push."
  B "push main" 'git -C /w/slot-1 push origin main' 2 "a push to main."
  B "push full ref" 'git -C /w/slot-1 push origin HEAD:refs/heads/main' 2 "a push to main."
  B "push with -c" 'git -c x=y push origin HEAD:main' 2 "a push to main."
  B "push branch" 'git -C /w/slot-1 push -u origin feat/5-x' 0
  B "branch ending in main" 'git push -u origin feat/5-main' 0
  B "stash push with free text" 'git -C /w/slot-1 stash push --include-untracked -m "Unmet tests for #5: push main -f +x --force" -- t.sh' 0
  B "stash push plain" 'git stash push --include-untracked -m "Tester files for #5: push to main -f" -- t.sh' 0
  B "commit with free text" 'git -C /w/slot-1 commit -m "fix push --force to main; gh pr merge 5"' 0
  B "push trunk" 'git push origin trunk' 2 "a push to trunk." $trunk
  B "push main when trunk is the base" 'git push origin main' 0 "" $trunk

  Write-Host "== a status edit to Ready or Approved"
  $edit = 'gh project item-edit --id I --project-id P --field-id F --single-select-option-id'
  B "item-edit Ready" "$edit RID1" 2 "setting Ready on the board."
  B "item-edit Approved" "$edit AID2" 2 "setting Approved on the board."
  B "item-edit Approved with =" 'gh project item-edit --id I --project-id P --field-id F --single-select-option-id=AID2' 2 "setting Approved on the board."
  B "item-edit other status" "$edit SID3" 0
  B "ids that contain an option id" 'gh project item-edit --id XRID1Y --project-id AID2X --single-select-option-id SID3' 0
  $gql = "gh api graphql -f query='mutation {`n  updateProjectV2ItemFieldValue(input: {projectId: `"P`", itemId: `"I`", fieldId: `"F`", value: {singleSelectOptionId:`n  `"AID2`"}}) { clientMutationId } }'"
  B "graphql Approved" $gql 2 "setting Approved on the board."
  B "graphql other ids" 'gh api graphql -f query=''mutation { updateProjectV2ItemFieldValue(input: {projectId: "P", itemId: "XAID2", fieldId: "F", value: {singleSelectOptionId: "SID3"}}) { clientMutationId } }''' 0
  [IO.File]::WriteAllText($failFlag, "x")
  B "lookup fails" "$edit SID3" 2 "option ids could not be read"
  Remove-Item $failFlag -Force

  Write-Host "== everything else"
  if (Test-Path $log) { Remove-Item $log -Force }
  B "no status edit" 'gh pr view 5' 0
  if (Test-Path $log) { Fail "gh pr view: the guard called gh" }
  Check "other tool" "Edit" 'gh pr merge 5 --squash' 0
  Check "powershell tool, merge" "PowerShell" 'gh pr merge 5 --squash' 2 $noauto
  $r = Invoke-Guard $proj "this is not json"
  if ($r.Code -ne 0) { Fail "invalid JSON: expected exit 0, got $($r.Code)" }
  if ($r.Err -ne "" -or $r.Out.Trim() -ne "") { Fail "invalid JSON: expected no output" }
  $r = Invoke-Guard $bare (Event-Json "Bash" 'gh pr merge 5 --admin')
  if ($r.Code -ne 0) { Fail "no nightmill.json: expected exit 0, got $($r.Code)" }
  if ($r.Err -ne "" -or $r.Out.Trim() -ne "") { Fail "no nightmill.json: expected no output" }

  Write-Host "GUARD OK"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

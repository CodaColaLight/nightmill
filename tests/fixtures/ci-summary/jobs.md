### Job times

| Job | Result | Wall time |
|---|---|---|
| Lint (generic, JSON, skills, shell) | success | 42s |
| claude plugin validate (not blocking) | success | ? |
| bash scripts smoke tests | success | 7m25s |
| PowerShell smoke part 1 of 4 | success | 9m20s |
| PowerShell smoke part 2 of 4 | success | 8m48s |
| PowerShell smoke part 3 of 4 | failure | 8m30s |
| PowerShell smoke part 4 of 4 | success | 4m00s |
| PowerShell scripts smoke tests | in_progress | 10m20s (running) |

PowerShell scripts smoke tests: 9m20s from the start of the first part to the end of the last (4 parts).

#### Slowest steps: Lint (generic, JSON, skills, shell)

| Step | Time |
|---|---|
| Run bash tests/lint.sh | 36s |
| Run actions/checkout | 3s |
| Set up job | 2s |
| Complete job | 1s |

#### Slowest steps: claude plugin validate (not blocking)

| Step | Time |
|---|---|
| Run npm install | 40s |
| Run claude plugin validate | 20s |
| Run actions/setup-node | 6s |
| Run claude plugin test | 6s |
| Run actions/checkout | 3s |

#### Slowest steps: bash scripts smoke tests

| Step | Time |
|---|---|
| Run bash tests/check.sh | 7m06s |
| Set up job | 3s |
| Run actions/checkout | 3s |
| Complete job | 2s |
| Hide jq (the bash scripts must not need it) | 1s |

#### Slowest steps: PowerShell smoke part 1 of 4

| Step | Time |
|---|---|
| Run bash tests/check.sh | 9m08s |
| Set up job | 5s |
| Run actions/checkout | 5s |
| Complete job | 2s |

#### Slowest steps: PowerShell smoke part 2 of 4

| Step | Time |
|---|---|
| Run bash tests/check.sh | 8m39s |
| Set up job | 4s |
| Run actions/checkout | 3s |
| Complete job | 2s |

#### Slowest steps: PowerShell smoke part 3 of 4

| Step | Time |
|---|---|
| Run bash tests/check.sh | 8m22s |
| Set up job | 3s |
| Run actions/checkout | 3s |
| Complete job | 2s |

#### Slowest steps: PowerShell smoke part 4 of 4

| Step | Time |
|---|---|
| Run bash tests/check.sh | 3m51s |
| Run actions/checkout | 4s |
| Set up job | 3s |
| Complete job | 2s |

#### Slowest steps: PowerShell scripts smoke tests

| Step | Time |
|---|---|
| Job times | 10m11s (running) |
| Run actions/checkout | 5s |
| Set up job | 3s |
| Every part succeeded | 1s |


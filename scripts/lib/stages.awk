# scripts/lib/stages.awk - the computation of scripts/stages.sh (iteration 41): reads the record
# <worktrees.root>/.slots/ledger.tsv and prints the time per stage of the chosen takes. POSIX awk, run with LC_ALL=C.
# Variables: NOW (seconds since 1970, UTC), MODE (issue or last), N (the issue, or how many takes), PATHNAME (for the
# note). The rules are those of stages.ps1 (decisions 6 to 10 of docs/specs/iteration-41-stage-times.md):
#   a take line starts a take of its slot (an earlier open take of that slot is "not freed"); a step line belongs to
#   the slot's open take, or starts one whose start is unknown; a free line ends the open take, or is a take of its
#   own; a take without a free line at the end is running.
#   start S = the claim of the take line; cut C = the PR's open (from) for a merged PR, else the free line, the last
#   line (not freed) or now (running); end E = the merge (to) for a merged PR, else C. Rows: take (S to the take's
#   finish), not-reported (the finish to the first step), each step (to the next step, the last to C; a step at or
#   after C is dropped), ci-and-merge (C to the merge). Total E - S, unknown without S.

function isstamp(s) {
  return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/
}
# epoch: seconds since 1970 of YYYY-MM-DDTHH:MM:SSZ, read as UTC (the arithmetic of epoch_of in slot.sh)
function epoch(s,    y, m, d, era, yoe, doy, doe) {
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m <= 2) y = y - 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return (era * 146097 + doe - 719468) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2)
}
function dur(t,    h) {
  if (t < 0) t = 0
  if (t < 60) return sprintf("%ds", t)
  if (t < 3600) return sprintf("%dm%02ds", int(t / 60), t % 60)
  return sprintf("%dh%02dm", int(t / 3600), int((t % 3600) / 60))
}
function share(t, total) {
  if (t == "" || total == "" || total <= 0) return "-"
  return sprintf("%d%%", int(100 * t / total + 0.5))
}
function newtake(slot, branch, line) {
  nt++
  tslot[nt] = slot; tbranch[nt] = branch; tfirst[nt] = epoch(line); tlast[nt] = epoch(line)
  tS[nt] = ""; tF[nt] = ""; nsteps[nt] = 0; tstate[nt] = "running"
  cur[slot] = nt
  return nt
}
# add <take> <name> <seconds, or "" for unknown>: one stretch of a row
function add(t, name, secs,    k) {
  k = t SUBSEP name
  if (!(k in rruns)) { nrows[t]++; rname[t, nrows[t]] = name; rruns[k] = 0; rtime[k] = 0; runknown[k] = 0 }
  rruns[k]++
  if (secs == "") runknown[k] = 1
  else { if (secs < 0) secs = 0; rtime[k] += secs }
}

BEGIN { FS = "\t"; nt = 0; bad = 0 }
{
  sub(/\r$/, "")
  kind = $1
  if (kind != "take" && kind != "step" && kind != "free") next
  if (NF != 11 || !isstamp($2) || $3 !~ /^[0-9]+$/) { bad++; next }
  slot = $3 + 0; at = epoch($2)
  if (kind == "take") {
    if ((slot in cur) && cur[slot] > 0) tstate[cur[slot]] = "not freed"
    t = newtake(slot, $4, $2)
    if (isstamp($9)) tS[t] = epoch($9)
    tF[t] = isstamp($10) ? epoch($10) : at
    if (tS[t] == "") tF[t] = ""
    next
  }
  if (!(slot in cur) || cur[slot] == 0) newtake(slot, $4, $2)
  t = cur[slot]
  tlast[t] = at
  if (kind == "step") {
    nsteps[t]++; sname[t, nsteps[t]] = $5; sat[t, nsteps[t]] = at
    next
  }
  # free
  tstate[t] = "freed"; fname[t] = $5; fstamp[t] = $2; fat[t] = at
  ffrom[t] = $9; fto[t] = $10; fissues[t] = $11
  cur[slot] = 0
}
END {
  if (bad > 0) printf "stages: skipped %d malformed lines of %s\n", bad, PATHNAME > "/dev/stderr"
  # which takes
  nsel = 0
  if (MODE == "issue") {
    for (t = 1; t <= nt; t++) {
      if (tstate[t] != "freed" || fissues[t] == "") continue
      k = split(fissues[t], parts, ",")
      for (i = 1; i <= k; i++) if (parts[i] == N) { sel[++nsel] = t; break }
    }
    if (nsel == 0) {
      printf "#%s: no record; every stage unknown (no slot took it, or a version before iteration 41 freed it)\n", N
      exit 0
    }
  } else {
    first = nt - N + 1; if (first < 1) first = 1
    for (t = first; t <= nt; t++) sel[++nsel] = t
  }
  for (j = 1; j <= nsel; j++) {
    t = sel[j]
    S = tS[t]
    merged = (tstate[t] == "freed" && isstamp(ffrom[t]) && isstamp(fto[t]))
    C = ""; E = ""
    if (merged) {
      from = epoch(ffrom[t]); to = epoch(fto[t])
      firstknown = (S != "") ? S : tfirst[t]
      if (from >= firstknown) C = from
      else for (i = 1; i <= nsteps[t]; i++) if (sat[t, i] < to) C = sat[t, i]
      E = to
      who = ""
    } else if (tstate[t] == "freed") { C = fat[t]; E = C }
    else if (tstate[t] == "not freed") { C = tlast[t]; E = C }
    else { C = NOW; E = C }
    # the header
    who = ""
    if (tstate[t] == "freed" && fissues[t] != "") {
      k = split(fissues[t], parts, ",")
      for (i = 1; i <= k; i++) who = who (who == "" ? "" : ",") "#" parts[i]
    }
    if (who == "") who = "-"
    if (merged) st = "merged " fto[t]
    else if (tstate[t] == "freed") st = fname[t] " " fstamp[t]
    else st = tstate[t]
    if (j > 1) printf "\n"
    printf "%s  %s  slot %d  %s\n", who, tbranch[t], tslot[t], st
    # the rows
    if (S != "") {
      add(t, "take", tF[t] - S)
      end = (nsteps[t] > 0) ? sat[t, 1] : C
      if (C != "" && end > C) end = C
      if (end == "") add(t, "not-reported", "")
      else add(t, "not-reported", end - tF[t])
    } else if (nsteps[t] > 0) add(t, "not-reported", "")
    for (i = 1; i <= nsteps[t]; i++) {
      if (C != "" && sat[t, i] >= C) continue
      nxt = (i < nsteps[t]) ? sat[t, i + 1] : C
      if (C != "" && nxt != "" && nxt > C) nxt = C
      if (nxt == "") add(t, sname[t, i], "")
      else add(t, sname[t, i], nxt - sat[t, i])
    }
    if (merged && C != "") add(t, "ci-and-merge", E - C)
    total = ""
    if (S != "" && E != "") { total = E - S; if (total < 0) total = 0 }
    printf "  %-20s %4s %8s %6s\n", "stage", "runs", "time", "share"
    for (i = 1; i <= nrows[t]; i++) {
      k = t SUBSEP rname[t, i]
      if (runknown[k]) printf "  %-20s %4s %8s %6s\n", rname[t, i], rruns[k], "unknown", "-"
      else printf "  %-20s %4s %8s %6s\n", rname[t, i], rruns[k], dur(rtime[k]), (total == "" ? "-" : share(rtime[k], total))
    }
    if (total == "") printf "  %-20s %4s %8s %6s\n", "total", "", "unknown", "-"
    else printf "  %-20s %4s %8s %6s\n", "total", "", dur(total), (total > 0 ? "100%" : "-")
  }
}

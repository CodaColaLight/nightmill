# scripts/lib/status.awk - the join and the table of scripts/status.sh (it does not use json.awk itself).
# The input is JSON turned into flat records by json.awk ("<path> TAB <kind> TAB <value>"), one file each:
#   ST_ITEMS     gh project item-list --format json
#   ST_PRS       gh pr list --json number,title,headRefName,state,isDraft,updatedAt,statusCheckRollup,closingIssuesReferences
#   ST_AGEFILES  space separated; the pages of the GraphQL query that gives the time of each item's last status change
#   ST_SLOTS     slot.sh --status --porcelain (plain lines, not flat records)
# and the settings in ST_* environment variables (see BEGIN). Prints the table of what waits and what is stuck,
# or with ST_PORCELAIN=1 the same cells as tab separated records (item, note, slot; iteration 31), or with ST_JSON=1
# the same cells as one JSON object on one line (iteration 54; ST_CAPACITY holds the capacity cell, or is unset).
# The rules are in docs/specs/iteration-8-status.md; scripts/status.ps1 does the same.

function days(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y--
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

# seconds since 1970-01-01 of "YYYY-MM-DDTHH:MM:SS" (a trailing Z is ignored): the same clock on both sides
function stamp(s,   a) {
  split(s, a, /[-T:]/)
  return days(a[1] + 0, a[2] + 0, a[3] + 0) * 86400 + a[4] * 3600 + a[5] * 60 + a[6]
}

function span(sec) {
  if (sec < 0) sec = 0
  if (sec < 3600) return int(sec / 60) "m"
  if (sec < 86400) return int(sec / 3600) "h"
  return int(sec / 86400) "d"
}

function splitrec(line, r) {
  r[1] = ""; r[2] = ""; r[3] = ""
  split(line, r, "\t")
}

function load_items(f,   line, r, p, idx, rest, n) {
  while ((getline line < f) > 0) {
    splitrec(line, r)
    p = r[1]
    if (p == "totalCount") { total = r[3] + 0; continue }
    if (match(p, /^items\[[0-9]+\]/)) {
      idx = substr(p, 7, RLENGTH - 7) + 0
      rest = substr(p, RLENGTH + 1)
      if (idx + 1 > ni) ni = idx + 1
      if (rest == ".content.number") inum[idx] = r[3]
      else if (rest == ".content.type") itype[idx] = r[3]
      else if (rest == ".status") istatus[idx] = r[3]
      else if (rest == ".title") ititle[idx] = r[3]
      else if (rest ~ /^\.labels\[[0-9]+\]$/) ilabels[idx] = ilabels[idx] "," r[3] ","
      else if (rest == ".assignees[0]") iwho[idx] = r[3]
    }
  }
  close(f)
}

function load_prs(f,   line, r, p, k, rest, m, key) {
  while ((getline line < f) > 0) {
    splitrec(line, r)
    p = r[1]
    if (match(p, /^\[[0-9]+\]/)) {
      k = substr(p, 2, RLENGTH - 2) + 0
      rest = substr(p, RLENGTH + 1)
      if (k + 1 > np) np = k + 1
      if (rest == ".number") pnum[k] = r[3]
      else if (rest == ".state") pstate[k] = r[3]
      else if (rest == ".isDraft") pdraft[k] = r[3]
      else if (rest == ".headRefName") phead[k] = r[3]
      else if (rest == ".title") ptitle[k] = r[3]
      else if (rest == ".updatedAt") pwhen[k] = stamp(r[3])
      else if (rest ~ /^\.closingIssuesReferences\[[0-9]+\]\.number$/) pcloses[k] = pcloses[k] "," r[3] ","
      else if (match(rest, /^\.statusCheckRollup\[[0-9]+\]/)) {
        m = substr(rest, 20, RLENGTH - 20) + 0
        key = substr(rest, RLENGTH + 1)
        if (m + 1 > nchecks[k]) nchecks[k] = m + 1
        if (key == ".conclusion") cconc[k, m] = r[3]
        else if (key == ".status") cstat[k, m] = r[3]
        else if (key == ".state") cstate[k, m] = r[3]
      }
    }
  }
  close(f)
}

# the status of a pull request as shown: open, draft, merged or closed
function prstate(k) {
  if (pstate[k] == "MERGED") return "merged"
  if (pstate[k] == "CLOSED") return "closed"
  if (pdraft[k] == "true") return "draft"
  return "open"
}

function prci(k,   m, c, s, t, pend) {
  if (nchecks[k] + 0 == 0) return "none"
  pend = 0
  for (m = 0; m < nchecks[k]; m++) {
    c = cconc[k, m]; s = cstat[k, m]; t = cstate[k, m]
    if (c == "FAILURE" || c == "ERROR" || c == "TIMED_OUT" || c == "CANCELLED" || t == "FAILURE" || t == "ERROR") return "fail"
    if (s == "QUEUED" || s == "IN_PROGRESS" || s == "PENDING" || s == "WAITING" || s == "REQUESTED" || t == "PENDING" || t == "EXPECTED") pend = 1
  }
  if (pend) return "pending"
  return "pass"
}

# the epoch of the item's last status change, or of its creation; pages hold at most 100 items each
function load_ages(f,   line, r, p, idx, rest, i, num) {
  delete pnumOf; delete pstat; delete pmade
  nodes = 0
  while ((getline line < f) > 0) {
    splitrec(line, r)
    p = r[1]
    if (match(p, /^data\.node\.items\.nodes\[[0-9]+\]/)) {
      idx = substr(p, 23, RLENGTH - 23) + 0
      rest = substr(p, RLENGTH + 1)
      if (idx + 1 > nodes) nodes = idx + 1
      if (rest == ".content.number") pnumOf[idx] = r[3]
      else if (rest == ".content.timelineItems.nodes[0].createdAt") pstat[idx] = stamp(r[3])
      else if (rest == ".createdAt") pmade[idx] = stamp(r[3])
    }
  }
  close(f)
  for (i = 0; i < nodes; i++) {
    num = pnumOf[i]
    if (num == "") continue
    if (i in pstat) age_at[num] = pstat[i]
    else if (i in pmade) age_at[num] = pmade[i]
  }
}

# a pull request is the issue's when it closes it or its title names it as "(#N)"
function belongs(k, n) {
  return (index(pcloses[k], "," n ",") > 0 || index(ptitle[k], "(#" n ")") > 0)
}

function isspec(k) {
  return (specprefix != "" && substr(phead[k], 1, length(specprefix)) == specprefix)
}

# a better candidate: open or draft beats merged beats closed, then the more recent one
function score(k,   s) {
  s = prstate(k)
  if (s == "open" || s == "draft") return 3 * 1e12 + pwhen[k]
  if (s == "merged") return 2 * 1e12 + pwhen[k]
  return 1 * 1e12 + pwhen[k]
}

# the pull request to show among those of issue n (want: "spec", "impl" or "head" with a branch in wantbranch); -1 when none
function pick(n, want, wantbranch,   k, best, bs, sc, ok) {
  best = -1; bs = -1
  for (k = 0; k < np; k++) {
    if (want == "head") ok = (phead[k] == wantbranch)
    else {
      ok = belongs(k, n)
      if (ok && want == "spec" && !isspec(k)) ok = 0
      if (ok && want == "impl" && isspec(k)) ok = 0
    }
    if (!ok) continue
    sc = score(k)
    if (sc > bs) { bs = sc; best = k }
  }
  return best
}

function count_prs(n, want, states,   k, c, s) {
  c = 0
  for (k = 0; k < np; k++) {
    if (!belongs(k, n)) continue
    if (want == "spec" && !isspec(k)) continue
    if (want == "impl" && isspec(k)) continue
    s = prstate(k)
    if (index(states, s) > 0) c++
  }
  return c
}

function prcell(k,   s) {
  if (k < 0) return "-"
  s = prstate(k)
  if (s == "open") return "#" pnum[k] " open, ci " prci(k)
  return "#" pnum[k] " " s
}

# a value as printed: every C0 control and DEL removed (#134), so a title cannot drive the terminal; the tabs and
# line ends of the layout are added after this
function clean(s) {
  gsub(/[\001-\037\177]/, "", s)
  return s
}

# the table: rows in R[r, c] (row 0 is the header), widths W[c], right aligned columns in RA[c]
function pad(s, w, right) {
  if (right) return sprintf("%" w "s", s)
  return sprintf("%-" w "s", s)
}

function table(nrows, ncols,   r, c, line) {
  for (c = 1; c <= ncols; c++) {
    W[c] = 0
    for (r = 0; r <= nrows; r++) R[r, c] = clean(R[r, c])
    for (r = 0; r <= nrows; r++) if (length(R[r, c]) > W[c]) W[c] = length(R[r, c])
  }
  for (r = 0; r <= nrows; r++) {
    line = ""
    for (c = 1; c <= ncols; c++) {
      if (c > 1) line = line "  "
      line = line pad(R[r, c], W[c], RA[c])
    }
    sub(/ +$/, "", line)
    print line
  }
}

# the four escapes json.awk writes back into a flat value (\\ \n \t \r) decoded, read left to right (porcelain only)
function unflat(s,   out, i, n, c, d) {
  if (index(s, "\\") == 0) return s
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) {
      d = substr(s, i + 1, 1)
      if (d == "\\") { out = out "\\"; i++; continue }
      if (d == "n") { out = out "\n"; i++; continue }
      if (d == "t") { out = out "\t"; i++; continue }
      if (d == "r") { out = out "\r"; i++; continue }
    }
    out = out c
  }
  return out
}

# a JSON string: " and \\ escaped, every byte 0x00 to 0x1F as \\u00xx, the rest as is (iteration 54 decision 10)
function jstr(s,   out, i, n, c) {
  if (s !~ /[\001-\037"\\]/) return "\"" s "\""
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"" || c == "\\") out = out "\\" c
    else if (c ~ /[\001-\037]/) out = out sprintf("\\u%04x", index(CTRL, c))
    else out = out c
  }
  return "\"" out "\""
}

# porcelain: one record, the kind and the fields joined with tabs; with ST_JSON=1 one object of the JSON form
function record(kind, nf, F,   i, line) {
  if (json) {
    for (i = 1; i <= nf; i++) F[i] = clean(F[i])
    if (kind == "item") {
      j_items = j_items (j_items == "" ? "" : ",") "{\"number\":" (F[1] + 0) ",\"status\":" jstr(F[2]) ",\"who\":" jstr(F[3]) \
        ",\"pr\":" jstr(F[4]) ",\"age\":" jstr(F[5]) ",\"flag\":" jstr(F[6]) ",\"title\":" jstr(F[7]) "}"
    } else if (kind == "note") {
      j_notes = j_notes (j_notes == "" ? "" : ",") jstr(F[1])
    } else if (kind == "slot") {
      j_slots = j_slots (j_slots == "" ? "" : ",") "{\"slot\":" (F[1] + 0) ",\"state\":" jstr(F[2]) ",\"agent\":" jstr(F[3]) \
        ",\"branch\":" jstr(F[4]) ",\"skill\":" jstr(F[5]) ",\"step\":" jstr(F[6]) ",\"report\":" jstr(F[7]) \
        ",\"since\":" jstr(F[8]) ",\"pr\":" jstr(F[9]) ",\"flag\":" jstr(F[10]) "}"
    }
    return
  }
  line = kind
  for (i = 1; i <= nf; i++) line = line "\t" clean(F[i])
  printf "%s\n", line
}

function before(a, b) { # does shown item a come before b
  if (srank[a] != srank[b]) return (srank[a] < srank[b])
  return (sage[a] > sage[b])
}

BEGIN {
  all = (ENVIRON["ST_ALL"] == "1")
  porcelain = (ENVIRON["ST_PORCELAIN"] == "1")
  # the JSON form takes the porcelain path; record() collects the objects and the END of BEGIN prints them
  json = (ENVIRON["ST_JSON"] == "1")
  if (json) porcelain = 1
  CTRL = ""
  for (i = 1; i < 32; i++) CTRL = CTRL sprintf("%c", i)
  now = ENVIRON["ST_NOW"] + 0
  nowl = now
  if (ENVIRON["ST_NOWL"] != "") nowl = stamp(ENVIRON["ST_NOWL"])
  specprefix = ENVIRON["ST_SPECPREFIX"]
  epic = ENVIRON["ST_EPIC"]
  grace = 7200
  limit_items = 200; limit_prs = 100

  # the statuses in the order of the table
  nrank = split(ENVIRON["ST_ORDER"], order, "\t")   # specReview, approved, inProgress, review, spec, ready, backlog, done
  for (i = 1; i <= nrank; i++) rank[order[i]] = i
  st_review = order[4]; st_inprogress = order[3]; st_spec = order[5]; st_specreview = order[1]
  st_backlog = order[7]; st_done = order[8]

  load_items(ENVIRON["ST_ITEMS"])
  load_prs(ENVIRON["ST_PRS"])
  nf = split(ENVIRON["ST_AGEFILES"], agefiles, " ")
  for (i = 1; i <= nf; i++) load_ages(agefiles[i])

  # slots
  # every line of slot.sh --status --porcelain, in its order; a busy line has ten fields (iteration 23)
  nslots = 0; nbusy = 0
  while ((getline line < ENVIRON["ST_SLOTS"]) > 0) {
    for (f = 1; f <= 10; f++) r[f] = ""
    split(line, r, "\t")
    nslots++
    sl_n[nslots] = r[1]; sl_state[nslots] = r[2]
    if (r[2] == "busy") {
      nbusy++
      bslot[nbusy] = r[1]; bbranch[nbusy] = r[3]; bsince[nbusy] = r[4]
      sl_busy[nslots] = nbusy
      sl_agent[nslots] = r[6]; sl_skill[nslots] = r[7]; sl_role[nslots] = r[8]; sl_step[nslots] = r[9]; sl_rep[nslots] = r[10]
    }
  }
  close(ENVIRON["ST_SLOTS"])

  # the items to show
  hidden_backlog = 0; hidden_done = 0; ns = 0
  for (i = 0; i < ni; i++) {
    if (itype[i] != "Issue") continue
    if (epic != "" && index(ilabels[i], "," epic ",") > 0) continue
    if (!(istatus[i] in rank)) continue
    if (!all && (istatus[i] == st_backlog || istatus[i] == st_done)) {
      if (istatus[i] == st_backlog) hidden_backlog++; else hidden_done++
      continue
    }
    ns++
    sidx[ns] = i
    srank[ns] = rank[istatus[i]]
    if (inum[i] in age_at) sage[ns] = now - age_at[inum[i]]; else sage[ns] = 0
  }
  # insertion sort: status order, oldest first
  for (a = 2; a <= ns; a++) {
    v = sidx[a]; vr = srank[a]; vg = sage[a]
    b = a - 1
    while (b >= 1 && (vr < srank[b] || (vr == srank[b] && vg > sage[b]))) {
      sidx[b + 1] = sidx[b]; srank[b + 1] = srank[b]; sage[b + 1] = sage[b]
      b--
    }
    sidx[b + 1] = v; srank[b + 1] = vr; sage[b + 1] = vg
  }

  # busy slots by branch, for the Who column
  for (j = 1; j <= nbusy; j++) slotof[bbranch[j]] = bslot[j]

  R[0, 1] = "#"; R[0, 2] = "Title"; R[0, 3] = "Status"; R[0, 4] = "Who"; R[0, 5] = "PR"; R[0, 6] = "Age"; R[0, 7] = "Flag"
  RA[1] = 1; RA[6] = 1
  for (a = 1; a <= ns; a++) {
    i = sidx[a]; n = inum[i]; s = istatus[i]
    title = clean(ititle[i])
    sub(/^\[(Story|Bug)\] /, "", title)
    if (length(title) > 36) title = substr(title, 1, 33) "..."
    want = "impl"
    if (s == st_spec || s == st_specreview) want = "spec"
    k = pick(n, want, "")
    who = iwho[i]
    if (who == "") {
      for (kk = 0; kk < np && who == ""; kk++) if (belongs(kk, n) && (phead[kk] in slotof)) who = "slot " slotof[phead[kk]]
    }
    if (who == "") who = "-"
    flag = ""
    young = (sage[a] <= grace)
    if (s == st_review) {
      if (count_prs(n, "impl", "open draft merged closed") > 0 && count_prs(n, "impl", "open draft") == 0 && k >= 0) {
        flag = "stale: Review but the PR is " prstate(k)
      }
    } else if (s == st_inprogress) {
      if (count_prs(n, "impl", "open draft merged closed") == 0 && nbusy == 0 && !young && (n in age_at)) flag = "stale: In progress, no PR and no busy slot"
    } else if (s == st_spec) {
      if (count_prs(n, "spec", "open draft merged") == 0 && !young && (n in age_at)) flag = "stale: Spec but no spec PR"
    }
    R[a, 1] = n; R[a, 2] = title; R[a, 3] = s; R[a, 4] = who; R[a, 5] = prcell(k)
    R[a, 6] = (n in age_at) ? span(sage[a]) : "-"
    R[a, 7] = flag
    if (porcelain) {
      # the whole title: decoded, the prefix removed, every tab, CR and LF one space (iteration 31)
      ptitle_whole = unflat(ititle[i])
      sub(/^\[(Story|Bug)\] /, "", ptitle_whole)
      gsub(/[\t\r\n]/, " ", ptitle_whole)
      F[1] = n; F[2] = s; F[3] = who; F[4] = R[a, 5]; F[5] = R[a, 6]; F[6] = flag; F[7] = ptitle_whole
      record("item", 7, F)
    }
  }
  if (!porcelain) {
    if (ns == 0) print "nothing to show at these statuses"
    else table(ns, 7)
  }

  line = ""
  if (hidden_backlog > 0) line = hidden_backlog " at " st_backlog
  if (hidden_done > 0) line = line (line != "" ? ", " : "") hidden_done " at " st_done
  if (line != "" && !porcelain) print "not shown: " clean(line) " (use --all)"
  note_board = "the board has " total " items, only the first " limit_items " were read"
  note_prs = "only the " limit_prs " most recent pull requests were read"
  if (porcelain) {
    if (total > limit_items) { F[1] = note_board; record("note", 1, F) }
    if (np >= limit_prs) { F[1] = note_prs; record("note", 1, F) }
  } else {
    if (total > limit_items) print "note: " note_board
    if (np >= limit_prs) print "note: " note_prs
  }

  if (ENVIRON["ST_SLOTS_CONFIGURED"] == "1") {
    # the Slots section (iteration 23): every slot, free and busy; the agent state is the slot script's
    if (!porcelain) {
      print ""
      print "slots"
    }
    delete R; delete RA
    R[0, 1] = "slot"; R[0, 2] = "State"; R[0, 3] = "Agent"; R[0, 4] = "Branch"; R[0, 5] = "Skill"; R[0, 6] = "Step"
    R[0, 7] = "Report"; R[0, 8] = "Since"; R[0, 9] = "PR"; R[0, 10] = "Flag"
    RA[1] = 1; RA[7] = 1; RA[8] = 1
    for (s = 1; s <= nslots; s++) {
      for (c = 1; c <= 10; c++) R[s, c] = ""
      R[s, 1] = sl_n[s]; R[s, 2] = sl_state[s]
      if (!(s in sl_busy)) continue
      j = sl_busy[s]
      k = pick(0, "head", bbranch[j])
      sinceage = nowl - stamp(bsince[j])
      flag = ""
      if (k >= 0) {
        sstate = prstate(k)
        if (sstate == "merged") flag = "stale: busy, PR merged (slot --release " bslot[j] ")"
        else if (sstate == "closed") flag = "stale: busy, PR closed (slot --abandon " bslot[j] ")"
      } else if (sinceage > grace) flag = "stale: busy, no open PR"
      if (sl_skill[s] == "" && sl_role[s] == "") who = "?"
      else who = (sl_skill[s] == "" ? "?" : sl_skill[s]) "/" (sl_role[s] == "" ? "?" : sl_role[s])
      rep = "-"
      if (sl_rep[s] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) rep = span(nowl - stamp(sl_rep[s]))
      R[s, 3] = sl_agent[s]; R[s, 4] = bbranch[j]; R[s, 5] = who; R[s, 6] = (sl_step[s] == "" ? "?" : sl_step[s])
      R[s, 7] = rep; R[s, 8] = span(sinceage); R[s, 9] = prcell(k); R[s, 10] = flag
    }
    if (porcelain) {
      for (s = 1; s <= nslots; s++) {
        for (c = 1; c <= 10; c++) F[c] = R[s, c]
        record("slot", 10, F)
      }
    } else table(nslots, 10)
  }
  if (json) {
    printf "{\"items\":[%s],\"notes\":[%s],", j_items, j_notes
    if (ENVIRON["ST_SLOTS_CONFIGURED"] == "1") printf "\"slots\":[%s],\"capacity\":%s}\n", j_slots, jstr(clean(ENVIRON["ST_CAPACITY"]))
    else printf "\"slots\":null,\"capacity\":null}\n"
  }
  exit 0
}

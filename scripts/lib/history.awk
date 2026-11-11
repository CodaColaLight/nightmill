# scripts/lib/history.awk - the computation of scripts/history.sh (iteration 54): reads the run ledger
# <worktrees.root>/.slots/ledger.tsv and the board's status changes and prints how the work went in a window, as
# text, as one JSON line or as one HTML page. POSIX awk, run with LC_ALL=C. The rules are those of history.ps1
# (decisions 3 to 11 of docs/specs/iteration-54-history-metrics.md). Everything comes in the environment:
#   H_LEDGER     the ledger to read, or empty when there is none (H_PATHNAME names it in the notes)
#   H_NOW        the clock, seconds since 1970 (UTC)
#   H_FROM H_TO  the window ends in seconds, or empty for the defaults (decision 2); H_RUN a driver run's stamp
#   H_MODE       text, json or html
#   H_BOARD      1 when the board was read, then H_BOARDFILE holds its pages as "<page> TAB <json.awk flat record>";
#                0 when not, then H_BOARDNOTE holds the reason; H_MORE 1 when the listing stopped after 20 pages
#   H_PN H_EPIC  github.projectNumber and labels.epic; H_ST_<key> the names of board.statuses
#   H_HAVEWT     1 when the config has a worktrees key; H_SLOTS worktrees.slots, or empty
#   H_OWNER H_REPO  for the page's title
# The ledger lines are read by the rules of lib/stages.awk (iteration 41 decision 6): a take line starts a take of its
# slot (an earlier open take of that slot is "not freed"); a step line belongs to the slot's open take, or starts one
# without a take line; a free line ends the open take, or is a take of its own; a take without a free line is running.

function isstamp(s) {
  return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/
}
# epoch: seconds since 1970 of YYYY-MM-DDTHH:MM:SSZ, read as UTC (the arithmetic of lib/stages.awk)
function epoch(s,    y, m, d, era, yoe, doy, doe) {
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m <= 2) y = y - 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return (era * 146097 + doe - 719468) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2)
}
# stampof: the inverse, YYYY-MM-DDTHH:MM:SSZ of seconds since 1970 (the arithmetic of ledger_stamp)
function stampof(s,    z, sod, era, doe, yoe, y, doy, mp, d, m) {
  z = int(s / 86400); sod = s - z * 86400
  if (sod < 0) { sod += 86400; z-- }
  z += 719468
  era = int((z >= 0 ? z : z - 146096) / 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = (mp < 10) ? mp + 3 : mp - 9
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d, int(sod / 3600), int((sod % 3600) / 60), sod % 60)
}
function dur(t) {
  if (t < 0) t = 0
  if (t < 60) return sprintf("%ds", t)
  if (t < 3600) return sprintf("%dm%02ds", int(t / 60), t % 60)
  return sprintf("%dh%02dm", int(t / 3600), int((t % 3600) / 60))
}
function money(x) { return sprintf("%.2f", x) }
# every C0 control character and DEL removed (#134)
function clean(s) { gsub(/[\001-\037\177]/, "", s); return s }
# a JSON string: " and \ escaped, every byte 0x00 to 0x1F as \u00xx, the rest as is (decision 10)
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
function jnum(v) { return (v == "") ? "null" : v }
# HTML: & < > " ' escaped, in that order, as dashboard.awk does
function hesc(s) {
  gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); gsub(/'/, "\\&#39;", s)
  return s
}
# the four escapes json.awk writes back into a flat value (\\ \n \t \r) decoded
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
function note(s) { nnotes++; notes[nnotes] = clean(s) }
function inwin(t) { return (t >= FROM && t <= TO) }

function newtake(slot, at) {
  nt++
  tslot[nt] = slot; tstart[nt] = at; tlast[nt] = at; tline[nt] = 0; tstate[nt] = "running"
  tissues[nt] = ""; tsteps[nt] = ""
  cur[slot] = nt
  return nt
}

function readledger(f,   line, r, n, kind, slot, at, t, rc) {
  while ((rc = (getline line < f)) > 0) {
    sub(/\r$/, "", line)
    n = split(line, r, "\t")
    kind = r[1]
    if (kind != "take" && kind != "step" && kind != "free" && kind != "run") continue
    if (kind == "run") {
      if (n != 11 || !isstamp(r[2]) || !isstamp(r[3])) { bad++; continue }
      at = epoch(r[2])
      if (first == "" || at < first) first = at
      nr++
      rat[nr] = at; rrun[nr] = r[3]; rissues[nr] = r[6]; rcost[nr] = r[10]
      continue
    }
    if (n != 11 || !isstamp(r[2]) || r[3] !~ /^[0-9]+$/) { bad++; continue }
    slot = r[3] + 0; at = epoch(r[2])
    if (first == "" || at < first) first = at
    if (kind == "take") {
      if ((slot in cur) && cur[slot] > 0) tstate[cur[slot]] = "not freed"
      t = newtake(slot, at)
      tline[t] = 1
      if (isstamp(r[9])) tstart[t] = epoch(r[9])
      continue
    }
    if (!(slot in cur) || cur[slot] == 0) newtake(slot, at)
    t = cur[slot]
    tlast[t] = at
    if (kind == "step") { tsteps[t] = tsteps[t] "\t" r[5]; continue }
    tstate[t] = "freed"; tfree[t] = at; tissues[t] = r[11]
    cur[slot] = 0
  }
  close(f)
  return (rc < 0) ? 0 : 1
}

function readboard(f,   line, r, p, rest, pg, idx, k, key, sub2) {
  while ((getline line < f) > 0) {
    split(line, r, "\t")
    pg = r[1] + 0; p = r[2]
    if (!match(p, /^data\.repositoryOwner\.projectV2\.items\.nodes\[[0-9]+\]/)) continue
    idx = substr(p, 44, RLENGTH - 44) + 0
    rest = substr(p, RLENGTH + 1)
    key = pg SUBSEP idx
    if (!(key in seen)) { seen[key] = 1; ni++; item[ni] = key; inum[key] = ""; ilab[key] = ","; nev[key] = 0 }
    if (rest == ".content.number") inum[key] = r[4]
    else if (rest ~ /^\.content\.labels\.nodes\[[0-9]+\]\.name$/) ilab[key] = ilab[key] unflat(r[4]) ","
    else if (rest == ".content.timelineItems.nodes") ncount[key] = r[4] + 0
    else if (match(rest, /^\.content\.timelineItems\.nodes\[[0-9]+\]/)) {
      k = substr(rest, 30, RLENGTH - 30) + 0
      sub2 = substr(rest, RLENGTH + 1)
      if (k + 1 > nev[key]) nev[key] = k + 1
      if (sub2 == ".createdAt") evat[key, k] = r[4]
      else if (sub2 == ".status") evst[key, k] = unflat(r[4])
      else if (sub2 == ".project.number") evpn[key, k] = r[4]
    }
  }
  close(f)
}

BEGIN {
  FS = "\t"
  CTRL = ""
  for (i = 1; i < 32; i++) CTRL = CTRL sprintf("%c", i)
  NOW = ENVIRON["H_NOW"] + 0
  MODE = ENVIRON["H_MODE"]; RUN = ENVIRON["H_RUN"]
  nkeys = split("backlog ready spec specReview approved inProgress review done", K, " ")
  split("Backlog|Ready|Spec|Spec review|Approved|In progress|Review|Done", DEF, "|")
  for (i = 1; i <= nkeys; i++) {
    NAME[i] = ENVIRON["H_ST_" K[i]]
    if (NAME[i] == "") NAME[i] = DEF[i]
    if (!(NAME[i] in keyof)) keyof[NAME[i]] = i
  }
  nnotes = 0; nt = 0; nr = 0; bad = 0; first = ""

  # the ledger
  haveledger = (ENVIRON["H_LEDGER"] != "")
  if (haveledger && !readledger(ENVIRON["H_LEDGER"])) {
    printf "history: cannot read %s\n", ENVIRON["H_PATHNAME"] > "/dev/stderr"
    exit 1
  }
  if (bad > 0) printf "history: skipped %d malformed lines of %s\n", bad, ENVIRON["H_PATHNAME"] > "/dev/stderr"

  # the window (decision 2)
  runnote = ""
  if (RUN != "") {
    FROM = epoch(RUN); TO = ""
    for (j = 1; j <= nr; j++) if (rrun[j] == RUN && (TO == "" || rat[j] > TO)) TO = rat[j]
    if (TO == "") { TO = NOW; runnote = "no run lines for the driver run " RUN }
    if (TO < FROM) TO = FROM
  } else {
    TO = (ENVIRON["H_TO"] != "") ? ENVIRON["H_TO"] + 0 : NOW
    if (ENVIRON["H_FROM"] != "") FROM = ENVIRON["H_FROM"] + 0
    else if (first != "") FROM = first
    else FROM = TO - 7 * 86400
    if (FROM > TO) FROM = TO
  }
  W = TO - FROM

  # the board (decision 6)
  board = (ENVIRON["H_BOARD"] == "1")
  if (!board) note("the board was not read: " ENVIRON["H_BOARDNOTE"])
  else {
    readboard(ENVIRON["H_BOARDFILE"])
    pn = ENVIRON["H_PN"]; epic = ENVIRON["H_EPIC"]
    other = 0; many = 0
    for (i = 1; i <= nkeys; i++) { scount[i] = 0; stotal[i] = 0 }
    for (a = 1; a <= ni; a++) {
      key = item[a]; num = inum[key]
      if (num !~ /^[0-9]+$/) continue
      if (epic != "" && index(ilab[key], "," epic ",") > 0) continue
      if (ncount[key] >= 100) many++
      ne = 0
      for (k = 0; k < nev[key]; k++) {
        if (evpn[key, k] != pn || !isstamp(evat[key, k])) continue
        ne++; eat[ne] = epoch(evat[key, k]); est[ne] = evst[key, k]
      }
      for (e = 1; e < ne; e++) {
        if (!inwin(eat[e + 1])) continue
        len = eat[e + 1] - eat[e]; if (len < 0) len = 0
        if (!(est[e] in keyof)) { other++; continue }
        i = keyof[est[e]]
        scount[i]++; slen[i, scount[i]] = len; stotal[i] += len
        if (i >= 2 && i <= 7) {
          num += 0
          if (!(num in isin)) { isin[num] = 1; nis++; ilist[nis] = num }
          itime[num, i] += len; ihas[num, i] = 1
        }
      }
    }
    if (other > 0) note(other " stays at a status not in board.statuses were not counted")
    if (ENVIRON["H_MORE"] == "1") note("the board listing stopped after 2000 items")
    if (many > 0) note(many " issues have more than 100 status changes; only the first 100 were read")
    # median (the lower middle) and max of each status
    for (i = 1; i <= 7; i++) {
      n = scount[i]
      for (x = 2; x <= n; x++) {
        v = slen[i, x]; y = x - 1
        while (y >= 1 && slen[i, y] > v) { slen[i, y + 1] = slen[i, y]; y-- }
        slen[i, y + 1] = v
      }
      smed[i] = (n > 0) ? slen[i, int((n - 1) / 2) + 1] : ""
      smax[i] = (n > 0) ? slen[i, n] : ""
    }
  }

  # the ledger notes
  if (!haveledger) note("no record yet: " ENVIRON["H_PATHNAME"])
  if (runnote != "") note(runnote)

  # fix rounds per issue (decision 4): the takes freed in the window
  for (t = 1; t <= nt; t++) {
    if (tstate[t] != "freed" || tissues[t] == "" || !inwin(tfree[t])) continue
    rmax = 0; review = 0; cmax = 0
    ns = split(tsteps[t], st, "\t")
    for (s = 2; s <= ns; s++) {
      nm = st[s]
      if (nm == "code-review") review = 1
      else if (nm ~ /^(fix-round|dispute|test-finding)-[1-9][0-9]*$/) { v = nm; sub(/^.*-/, "", v); if (v + 0 > rmax) rmax = v + 0 }
      else if (nm ~ /^check-fix-[1-9][0-9]*$/) { v = nm; sub(/^.*-/, "", v); if (v + 0 > cmax) cmax = v + 0 }
    }
    c = split(tissues[t], parts, ",")
    for (j = 1; j <= c; j++) {
      if (parts[j] !~ /^[0-9]+$/) continue
      num = parts[j] + 0
      if (!(num in isin)) { isin[num] = 1; nis++; ilist[nis] = num }
      itake[num] = 1
      if (review) ireview[num] = 1
      if (rmax > iround[num] + 0) iround[num] = rmax
      if (cmax > icheck[num] + 0) icheck[num] = cmax
    }
  }

  # cost per issue (decision 5)
  ctotal = 0; cruns = 0; cwithout = 0; cnone = 0
  for (j = 1; j <= nr; j++) {
    if (!inwin(rat[j])) continue
    if (RUN != "" && rrun[j] != RUN) continue
    cruns++
    cost = rcost[j] + 0
    if (rcost[j] == "") cwithout++
    ctotal += cost
    if (rissues[j] == "") { cnone += cost; continue }
    c = split(rissues[j], parts, ",")
    for (x = 1; x <= c; x++) {
      if (parts[x] !~ /^[0-9]+$/) continue
      num = parts[x] + 0
      if (!(num in isin)) { isin[num] = 1; nis++; ilist[nis] = num }
      iruns[num]++; icost[num] += cost / c
    }
  }

  # slot utilisation (decision 7)
  hi = 0; noline = 0; anytake = 0
  for (t = 1; t <= nt; t++) {
    s0 = tstart[t]
    if (tstate[t] == "freed") e0 = tfree[t]
    else if (tstate[t] == "not freed") e0 = tlast[t]
    else e0 = TO
    if (s0 > TO || e0 < FROM) continue
    if (s0 < FROM) s0 = FROM
    if (e0 > TO) e0 = TO
    h = e0 - s0; if (h < 0) h = 0
    sl = tslot[t]
    anytake = 1
    if (sl > hi) hi = sl
    stakes[sl]++; sheld[sl] += h
    if (!tline[t]) noline++
  }
  if (noline > 0) note(noline " takes have no take line; their held time starts at their first line")
  slotsnone = (ENVIRON["H_HAVEWT"] != "1" && !anytake)
  if (!slotsnone) {
    if (ENVIRON["H_SLOTS"] ~ /^[0-9]+$/ && ENVIRON["H_SLOTS"] + 0 > 0) { S = ENVIRON["H_SLOTS"] + 0; sfrom = "config" }
    else { S = 2; sfrom = "default" }
    if (hi > S) { S = hi; sfrom = "record" }
    sum = 0
    for (sl = 1; sl <= S; sl++) {
      sum += sheld[sl] + 0
      sshare[sl] = (W > 0) ? int(100 * (sheld[sl] + 0) / W + 0.5) : ""
    }
    util = (W > 0) ? int(100 * sum / (S * W) + 0.5) : ""
  }

  # the issues in order of their numbers
  for (x = 2; x <= nis; x++) {
    v = ilist[x]; y = x - 1
    while (y >= 1 && ilist[y] > v) { ilist[y + 1] = ilist[y]; y-- }
    ilist[y + 1] = v
  }

  # the cells, as printed
  header = "history " stampof(FROM) " to " stampof(TO) " (" dur(W) ")" (RUN != "" ? ", driver run " RUN : "")
  for (i = 1; i <= 7; i++) {
    CN[i] = clean(NAME[i])
    if (!board) { CS[i] = "?"; CM[i] = "?"; CX[i] = "?"; CT[i] = "?" }
    else {
      CS[i] = scount[i]; CT[i] = dur(stotal[i])
      CM[i] = (scount[i] > 0) ? dur(smed[i]) : "-"
      CX[i] = (scount[i] > 0) ? dur(smax[i]) : "-"
    }
  }
  for (x = 1; x <= nis; x++) {
    num = ilist[x]
    for (i = 2; i <= 7; i++) IT[x, i] = !board ? "?" : (((num, i) in ihas) ? dur(itime[num, i]) : "-")
    IR[x] = !(num in itake) ? "-" : (!(num in ireview) && iround[num] + 0 == 0 ? "-" : iround[num] + 0)
    IC[x] = (num in itake) ? icheck[num] + 0 : "-"
    IN[x] = iruns[num] + 0
    IM[x] = (iruns[num] + 0 > 0) ? "$" money(icost[num]) : "-"
  }
  costline = "cost: $" money(ctotal) " in " cruns " headless runs; $" money(cnone) " on no issue; " cwithout " runs without a cost"
  slotline = slotsnone ? "slots: none recorded" : "slots: " S " (" sfrom "), utilisation " (util == "" ? "-" : util "%")

  if (MODE == "json") printjson()
  else if (MODE == "html") printhtml()
  else printtext()
  exit 0
}

function printtext(   i, x, sl) {
  print header
  print ""
  printf "%-14s %6s %9s %9s %9s\n", "status", "stays", "median", "max", "total"
  for (i = 1; i <= 7; i++) printf "%-14s %6s %9s %9s %9s\n", CN[i], CS[i], CM[i], CX[i], CT[i]
  print ""
  if (nis == 0) print "no issue in the window"
  else {
    printf "%-6s %10s %10s %10s %10s %10s %10s %6s %6s %4s %8s\n", "issue", "ready", "spec", "specReview", "approved", "inProgress", "review", "rounds", "checks", "runs", "cost"
    for (x = 1; x <= nis; x++)
      printf "%-6s %10s %10s %10s %10s %10s %10s %6s %6s %4s %8s\n", "#" ilist[x], IT[x, 2], IT[x, 3], IT[x, 4], IT[x, 5], IT[x, 6], IT[x, 7], IR[x], IC[x], IN[x], IM[x]
  }
  print costline
  print ""
  print slotline
  if (!slotsnone) {
    printf "  %4s %6s %9s %6s\n", "slot", "takes", "held", "share"
    for (sl = 1; sl <= S; sl++) printf "  %4s %6s %9s %6s\n", sl, stakes[sl] + 0, dur(sheld[sl] + 0), (sshare[sl] == "" ? "-" : sshare[sl] "%")
  }
  for (i = 1; i <= nnotes; i++) print "note: " notes[i]
}

function printjson(   out, i, x, num, sl, sep) {
  out = "{\"from\":" jstr(stampof(FROM)) ",\"to\":" jstr(stampof(TO)) ",\"run\":" (RUN == "" ? "null" : jstr(RUN))
  if (!board) out = out ",\"statuses\":null"
  else {
    out = out ",\"statuses\":["
    for (i = 1; i <= 7; i++) {
      out = out (i > 1 ? "," : "") "{\"key\":" jstr(K[i]) ",\"name\":" jstr(CN[i]) ",\"stays\":" scount[i] ",\"median\":" jnum(smed[i]) ",\"max\":" jnum(smax[i]) ",\"total\":" stotal[i] "}"
    }
    out = out "]"
  }
  out = out ",\"issues\":["
  for (x = 1; x <= nis; x++) {
    num = ilist[x]
    out = out (x > 1 ? "," : "") "{\"number\":" num ",\"times\":"
    if (!board) out = out "null"
    else {
      out = out "{"
      for (i = 2; i <= 7; i++) out = out (i > 2 ? "," : "") jstr(K[i]) ":" (((num, i) in ihas) ? itime[num, i] : "null")
      out = out "}"
    }
    out = out ",\"rounds\":" (IR[x] == "-" ? "null" : IR[x]) ",\"checks\":" (IC[x] == "-" ? "null" : IC[x]) ",\"runs\":" IN[x] ",\"cost\":" (IM[x] == "-" ? "null" : money(icost[num])) "}"
  }
  out = out "],\"cost\":{\"total\":" money(ctotal) ",\"runs\":" cruns ",\"withoutCost\":" cwithout ",\"noIssue\":" money(cnone) "}"
  if (slotsnone) out = out ",\"slots\":null"
  else {
    out = out ",\"slots\":{\"count\":" S ",\"from\":" jstr(sfrom) ",\"utilisation\":" jnum(util) ",\"perSlot\":["
    for (sl = 1; sl <= S; sl++) out = out (sl > 1 ? "," : "") "{\"slot\":" sl ",\"takes\":" (stakes[sl] + 0) ",\"held\":" (sheld[sl] + 0) ",\"share\":" jnum(sshare[sl]) "}"
    out = out "]}"
  }
  out = out ",\"notes\":["
  for (i = 1; i <= nnotes; i++) out = out (i > 1 ? "," : "") jstr(notes[i])
  out = out "]}"
  print out
}

function printhtml(   title, i, x, sl, T, p) {
  title = hesc(clean("nightmill history " ENVIRON["H_OWNER"] "/" ENVIRON["H_REPO"]))
  print "<!DOCTYPE html>"
  print "<html lang=\"en\">"
  print "<head>"
  print "<meta charset=\"utf-8\">"
  print "<title>" title "</title>"
  print "<style>"
  print "body { font-family: sans-serif; margin: 1.5em; }"
  print "table { border-collapse: collapse; margin-bottom: 1em; }"
  print "th, td { padding: 0.2em 0.8em; text-align: right; border-bottom: 1px solid #ccc; }"
  print "th:first-child, td:first-child { text-align: left; }"
  print ".bar { background: #48a; height: 0.8em; }"
  print "</style>"
  print "</head>"
  print "<body>"
  print "<h1>" title "</h1>"
  print "<p>" hesc(header) "</p>"
  # the status table; the bar is the status's share of the summed totals of all eight statuses
  T = 0
  if (board) for (i = 1; i <= 8; i++) T += stotal[i]
  print "<table>"
  print "<tr><th>status</th><th>stays</th><th>median</th><th>max</th><th>total</th><th></th></tr>"
  for (i = 1; i <= 7; i++) {
    if (!board) bar = ""
    else {
      p = (T > 0) ? int((200 * stotal[i] + T) / (2 * T)) : 0
      bar = "<div class=\"bar\" style=\"width:" p "%\"></div>"
    }
    print "<tr><td>" hesc(CN[i]) "</td><td>" hesc(CS[i]) "</td><td>" hesc(CM[i]) "</td><td>" hesc(CX[i]) "</td><td>" hesc(CT[i]) "</td><td>" bar "</td></tr>"
  }
  print "</table>"
  if (nis == 0) print "<p>no issue in the window</p>"
  else {
    print "<table>"
    print "<tr><th>issue</th><th>ready</th><th>spec</th><th>specReview</th><th>approved</th><th>inProgress</th><th>review</th><th>rounds</th><th>checks</th><th>runs</th><th>cost</th></tr>"
    for (x = 1; x <= nis; x++) {
      line = "<tr><td>#" ilist[x] "</td>"
      for (i = 2; i <= 7; i++) line = line "<td>" hesc(IT[x, i]) "</td>"
      line = line "<td>" hesc(IR[x]) "</td><td>" hesc(IC[x]) "</td><td>" hesc(IN[x]) "</td><td>" hesc(IM[x]) "</td></tr>"
      print line
    }
    print "</table>"
  }
  print "<p>" hesc(costline) "</p>"
  print "<p>" hesc(slotline) "</p>"
  if (!slotsnone) {
    print "<table>"
    print "<tr><th>slot</th><th>takes</th><th>held</th><th>share</th><th></th></tr>"
    for (sl = 1; sl <= S; sl++) {
      p = (sshare[sl] == "") ? 0 : sshare[sl]
      print "<tr><td>" sl "</td><td>" (stakes[sl] + 0) "</td><td>" dur(sheld[sl] + 0) "</td><td>" (sshare[sl] == "" ? "-" : sshare[sl] "%") "</td><td><div class=\"bar\" style=\"width:" p "%\"></div></td></tr>"
    }
    print "</table>"
  }
  if (nnotes > 0) {
    print "<ul>"
    for (i = 1; i <= nnotes; i++) print "<li>" hesc(notes[i]) "</li>"
    print "</ul>"
  }
  print "</body>"
  print "</html>"
}

# scripts/lib/dashboard.awk - the page of scripts/dashboard.sh (iteration 31), built from the output of
# status.sh --porcelain or, when that failed, of slot.sh --status --porcelain. Run it as
#   LC_ALL=C awk -f dashboard.awk
# with everything in DB_* environment variables (the environment, not -v, which would interpret backslashes):
#   DB_N interval, DB_E time of rendering (seconds since 1970), DB_T its local text (empty: DB_E read as UTC),
#   DB_M stalled threshold in minutes, DB_O owner, DB_R repository, DB_SR and DB_AP the Spec review and Approved
#   names, DB_WT 1 when the config has worktrees;
#   DB_ST_NAME, DB_ST_CODE, DB_ST_OUT, DB_ST_ERR  the status child: its name, exit code, standard output and error;
#   DB_SL_RAN 1 when the slot child ran, DB_SL_NAME, DB_SL_CODE, DB_SL_OUT, DB_SL_ERR  the same for it.
# Prints the page. scripts/dashboard.ps1 builds the same bytes; docs/specs/iteration-31-dashboard.md has the rules.
# The page reloads itself with <meta http-equiv="refresh" content="N"> and only shows: no link, form, button,
# input or request.

# the HTML escaping of every value from outside: & < > " ' and every control byte to one space, in this order
function esc(s,   out, i, n, c) {
  if (s !~ /[&<>"'\001-\037\177]/) return s
  out = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c in ESC) out = out ESC[c]
    else out = out c
  }
  return out
}

# the lines of a stream: split at LF, one trailing CR removed from every line; a last empty piece is dropped
function lines(s, A,   n, i) {
  if (s == "") return 0
  n = split(s, A, "\n")
  if (A[n] == "") n--
  for (i = 1; i <= n; i++) sub(/\r$/, "", A[i])
  return n
}

# the reason a child failed: its first non-empty line of standard error without trailing spaces, else its exit code
function reason(err, name, code,   E, n, i, l) {
  n = lines(err, E)
  for (i = 1; i <= n; i++) {
    l = E[i]
    sub(/ +$/, "", l)
    if (l != "") return l
  }
  return name " exited with code " code
}

# the inverse of days in lib/status.awk: YYYY-MM-DD HH:MM:SS of seconds since 1970, read as UTC
function utc_text(e,   z, era, doe, yoe, y, doy, mp, d, m, sec) {
  sec = e % 86400
  z = int(e / 86400) + 719468
  era = int(z / 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = (mp < 10) ? mp + 3 : mp - 9
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02d %02d:%02d:%02d", y, m, d, int(sec / 3600), int((sec % 3600) / 60), sec % 60)
}

function emit(s) { printf "%s\n", s }

function td(s) { return "<td>" esc(s) "</td>" }

function agent_td(s) {
  if (s == "running" || s == "stalled" || s == "unknown") return "<td class=\"" s "\">" s "</td>"
  return "<td class=\"unknown\">" esc(s) "</td>"
}

# one row of the slot table: the ten cells (C[1..10]), from status or from the slot script's fallback form
function slot_row(C,   row) {
  row = "<tr><td class=\"num\">" esc(C[1]) "</td>"
  if (C[2] == "free") {
    emit(row "<td class=\"free\">free</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>")
    return
  }
  row = row td(C[2]) agent_td(C[3]) td(C[4]) td(C[5]) td(C[6])
  row = row "<td class=\"num\">" esc(C[7]) "</td><td class=\"num\">" esc(C[8]) "</td>"
  if (C[9] == "\001unknown") row = row "<td class=\"unknown\">unknown</td>"
  else row = row td(C[9])
  if (C[10] == "\001unknown") row = row "<td class=\"unknown\">unknown</td>"
  else if (C[10] != "") row = row "<td class=\"flagged\">" esc(C[10]) "</td>"
  else row = row "<td></td>"
  emit(row "</tr>")
}

function slot_header() {
  emit("<table>")
  emit("<tr><th>slot</th><th>State</th><th>Agent</th><th>Branch</th><th>Skill</th><th>Step</th><th>Report</th><th>Since</th><th>PR</th><th>Flag</th></tr>")
}

BEGIN {
  for (i = 1; i < 32; i++) ESC[sprintf("%c", i)] = " "
  ESC[sprintf("%c", 127)] = " "
  ESC["&"] = "&amp;"; ESC["<"] = "&lt;"; ESC[">"] = "&gt;"; ESC["\""] = "&quot;"; ESC["'"] = "&#39;"

  every = ENVIRON["DB_N"] + 0
  epoch = ENVIRON["DB_E"] + 0
  when = ENVIRON["DB_T"]
  if (when == "") when = utc_text(epoch)
  sr = ENVIRON["DB_SR"]; ap = ENVIRON["DB_AP"]
  title = esc(ENVIRON["DB_O"]) "/" esc(ENVIRON["DB_R"])

  st_ok = (ENVIRON["DB_ST_CODE"] == "0")
  nnotes = 0; nitems = 0; nslots = 0; capacity = ""; partial = 0
  if (st_ok) {
    n = lines(ENVIRON["DB_ST_OUT"], L)
    for (i = 1; i <= n; i++) {
      for (f = 1; f <= 11; f++) F[f] = ""
      split(L[i], F, "\t")
      if (F[1] == "item") {
        if (F[3] == sr || F[3] == ap) {
          nitems++
          it_n[nitems] = F[2]; it_status[nitems] = F[3]; it_pr[nitems] = F[5]; it_age[nitems] = F[6]; it_title[nitems] = F[8]
        }
      } else if (F[1] == "note") {
        notes[++nnotes] = F[2]
        if (index(F[2], "the board has ") == 1 && index(F[2], ", only the first ") > 0) partial = 1
      } else if (F[1] == "slot") {
        nslots++
        for (f = 1; f <= 10; f++) S[nslots, f] = F[f + 1]
      } else if (F[1] == "capacity") capacity = F[2]
    }
    n = lines(ENVIRON["DB_ST_ERR"], L)
    for (i = 1; i <= n; i++) if (L[i] != "") notes[++nnotes] = L[i]
  } else {
    st_reason = reason(ENVIRON["DB_ST_ERR"], ENVIRON["DB_ST_NAME"], ENVIRON["DB_ST_CODE"])
    if (ENVIRON["DB_SL_RAN"] == "1") {
      sl_ok = (ENVIRON["DB_SL_CODE"] == "0")
      if (sl_ok) {
        n = lines(ENVIRON["DB_SL_OUT"], L)
        for (i = 1; i <= n; i++) {
          for (f = 1; f <= 10; f++) F[f] = ""
          split(L[i], F, "\t")
          nslots++
          # the fallback form: the cells by the rule of the Slots section, times as written, PR and Flag unknown
          S[nslots, 1] = F[1]; S[nslots, 2] = F[2]
          for (f = 3; f <= 10; f++) S[nslots, f] = ""
          if (F[2] == "free") continue
          S[nslots, 3] = F[6]; S[nslots, 4] = F[3]
          if (F[7] == "" && F[8] == "") S[nslots, 5] = "?"
          else S[nslots, 5] = (F[7] == "" ? "?" : F[7]) "/" (F[8] == "" ? "?" : F[8])
          S[nslots, 6] = (F[9] == "" ? "?" : F[9])
          S[nslots, 7] = (F[10] == "" ? "-" : F[10]); S[nslots, 8] = F[4]
          S[nslots, 9] = "\001unknown"; S[nslots, 10] = "\001unknown"
        }
        n = lines(ENVIRON["DB_SL_ERR"], L)
        for (i = 1; i <= n; i++) if (L[i] != "") notes[++nnotes] = L[i]
      } else sl_reason = reason(ENVIRON["DB_SL_ERR"], ENVIRON["DB_SL_NAME"], ENVIRON["DB_SL_CODE"])
    }
  }

  emit("<!DOCTYPE html>")
  emit("<html lang=\"en\">")
  emit("<head>")
  emit("<meta charset=\"utf-8\">")
  emit("<meta http-equiv=\"refresh\" content=\"" every "\">")
  emit("<title>nightmill: " title "</title>")
  emit("<style>")
  emit("body { font-family: system-ui, sans-serif; margin: 1.5em; color: #1f2937; }")
  emit("table { border-collapse: collapse; margin: 0.5em 0; }")
  emit("th, td { border: 1px solid #d1d5db; padding: 0.25em 0.6em; text-align: left; white-space: nowrap; }")
  emit("th { background: #f3f4f6; }")
  emit(".num { text-align: right; }")
  emit(".running { background: #dcfce7; color: #14532d; }")
  emit(".stalled { background: #fef3c7; color: #78350f; font-weight: bold; }")
  emit(".unknown { background: #e5e7eb; color: #374151; font-style: italic; }")
  emit(".free { color: #6b7280; }")
  emit(".flagged { background: #fee2e2; color: #7f1d1d; font-weight: bold; }")
  emit("</style>")
  emit("</head>")
  emit("<body>")
  emit("<h1>nightmill: " title "</h1>")
  emit("<p id=\"rendered\" data-epoch=\"" epoch "\" data-every=\"" every "\">Rendered at " esc(when) "<span id=\"ago\"></span>; the page reloads every " every " s.</p>")
  emit("<p id=\"stale\" class=\"flagged\" hidden>Out of date: this page has not been rewritten for more than " (3 * every) " s. Is the dashboard script still running?</p>")
  emit("<h2>Slots</h2>")
  if (ENVIRON["DB_WT"] != "1") emit("<p>No slots: .claude/nightmill.json has no worktrees section.</p>")
  else if (st_ok) {
    slot_header()
    for (s = 1; s <= nslots; s++) { for (f = 1; f <= 10; f++) C[f] = S[s, f]; slot_row(C) }
    emit("</table>")
    emit("<p>capacity: " esc(capacity) "</p>")
  } else if (sl_ok) {
    emit("<p class=\"unknown\">unknown: the pull requests, CI and flags of the slots could not be read (" esc(st_reason) ")</p>")
    slot_header()
    for (s = 1; s <= nslots; s++) { for (f = 1; f <= 10; f++) C[f] = S[s, f]; slot_row(C) }
    emit("</table>")
    emit("<p class=\"unknown\">capacity: unknown</p>")
  } else emit("<p class=\"unknown\">unknown: the slots could not be read (" esc(sl_reason) ")</p>")
  emit("<h2>Waiting for you</h2>")
  if (!st_ok) emit("<p class=\"unknown\">unknown: the board could not be read (" esc(st_reason) ")</p>")
  else if (nitems > 0) {
    emit("<table>")
    emit("<tr><th>#</th><th>Title</th><th>Status</th><th>PR</th><th>Age</th></tr>")
    for (i = 1; i <= nitems; i++) {
      emit("<tr><td class=\"num\">" esc(it_n[i]) "</td>" td(it_title[i]) td(it_status[i]) td(it_pr[i]) "<td class=\"num\">" esc(it_age[i]) "</td></tr>")
    }
    emit("</table>")
  } else if (partial) emit("<p class=\"unknown\">unknown: no item at " esc(sr) " or " esc(ap) " among the items read; not all board items were read.</p>")
  else emit("<p>Nothing waits for you: no item at " esc(sr) " or " esc(ap) ".</p>")
  if (nnotes > 0) {
    emit("<h2>Notes</h2>")
    emit("<ul>")
    for (i = 1; i <= nnotes; i++) emit("<li>" esc(notes[i]) "</li>")
    emit("</ul>")
  }
  m = ENVIRON["DB_M"]
  emit("<h2>What the words mean</h2>")
  emit("<ul>")
  emit("<li><span class=\"running\">running</span>: the agent in a busy slot reported a step within the last " m " minutes (worktrees.stalledAfterMinutes).</li>")
  emit("<li><span class=\"stalled\">stalled</span>: no report for more than " m " minutes. The session may have ended, crashed or been abandoned, or one step runs long; a slot whose run is over (step done) and that waits for its merge shows it too. Look at it: nothing is stopped or freed.</li>")
  emit("<li><span class=\"unknown\">unknown</span>: a busy slot without a report (taken by hand or by an older version), or a value this page could not read. It is never taken as free or done.</li>")
  emit("<li><span class=\"free\">free</span>: no agent works in the slot.</li>")
  emit("<li><span class=\"flagged\">stale: ...</span>: flagged as /status flags it: a busy slot whose pull request merged or closed, or that has none after 2 hours.</li>")
  emit("</ul>")
  emit("<script>")
  emit("(function () {")
  emit("  var r = document.getElementById(\"rendered\");")
  emit("  var t = Number(r.getAttribute(\"data-epoch\")), every = Number(r.getAttribute(\"data-every\"));")
  emit("  function tick() {")
  emit("    var ago = Math.max(0, Math.floor(Date.now() / 1000 - t));")
  emit("    document.getElementById(\"ago\").textContent = \", \" + ago + \" s ago\";")
  emit("    document.getElementById(\"stale\").hidden = ago <= 3 * every;")
  emit("  }")
  emit("  tick();")
  emit("  setInterval(tick, 1000);")
  emit("})();")
  emit("</script>")
  emit("</body>")
  emit("</html>")
  exit 0
}

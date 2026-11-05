# scripts/lib/models.awk - the table of scripts/models.sh (use it together with json.awk):
#   MOD_CONFIG=config.json MOD_SCHEMA=schema.json LC_ALL=C awk -f json.awk -f models.awk
# Prints one table, one row per agent role (role, what it does, the model it runs on, whether the model comes
# from the config or from the schema default, its rank, and whether its pairing holds), then the ranking, the
# summary of the pairings and, when the config sets nothing, a line that says so. The texts, the columns and the
# rules are in docs/specs/iteration-16-models-command.md; models.ps1 prints the same.
# The effective model of a role is roles.<role>.model of the config when it is a non-empty string, else the default
# of the schema; the effective ranking is models.ranking of the config, else the default of the schema. The rank of
# a model is the 1-based position of the first ranking entry that has it as a part of a "="-joined entry.
# Exit code 2 (message on standard error) when the config or the schema cannot be read or parsed, or the config is
# not a JSON object. Only reads.

# a child of a node, 0 when the node itself is 0
function mch(id, key) {
  if (!id) return 0
  return json_child(id, key)
}

function mpad(s, w,   r) {
  r = s
  while (length(r) < w) r = r " "
  return r
}

# the model a role runs on and where it comes from, in mmodel[role] and mfrom[role]
function mresolve(role,   n, d) {
  n = mch(mch(mch(croot, "roles"), role), "model")
  if (n && jk[n] == "string" && jv[n] != "") {
    mmodel[role] = jv[n]; mfrom[role] = "config"; nconfig++
    return
  }
  d = mch(mch(mch(mch(mch(mch(sroot, "properties"), "roles"), "properties"), role), "properties"), "model")
  d = mch(d, "default")
  if (d && jk[d] == "string" && jv[d] != "") {
    mmodel[role] = jv[d]; mfrom[role] = "default"
    return
  }
  mmodel[role] = "-"; mfrom[role] = "-"
}

function mranked(role) {
  return (rankok && mmodel[role] != "-" && (mmodel[role] in vrank))
}

BEGIN {
  sfile = ENVIRON["MOD_SCHEMA"]
  cfile = ENVIRON["MOD_CONFIG"]
  stext = json_read(sfile)
  if (!jread_ok) { print "models: cannot read schema: " sfile > "/dev/stderr"; exit 2 }
  sroot = json_parse(stext)
  if (!sroot) { print "models: " sfile ": " jerr > "/dev/stderr"; exit 2 }
  ctext = json_read(cfile)
  if (!jread_ok) { print "models: cannot read config: " cfile > "/dev/stderr"; exit 2 }
  croot = json_parse(ctext)
  if (!croot) { print "models: " cfile ": not valid JSON (" jerr ")" > "/dev/stderr"; exit 2 }
  if (jk[croot] != "object") { print "models: " cfile ": not a JSON object" > "/dev/stderr"; exit 2 }

  nroles = split("specWriter specReviewer tester implementer codeReviewer fixer worker", roles, " ")
  does["specWriter"] = "writes the spec of a Ready story"
  does["specReviewer"] = "reviews specWriter"
  does["tester"] = "writes the failing tests before the code"
  does["implementer"] = "writes the code of an Approved story"
  does["codeReviewer"] = "reviews implementer and fixer"
  does["fixer"] = "fixes a bug"
  does["worker"] = "does mechanical, fully specified jobs"

  # the effective ranking
  rk = mch(mch(croot, "models"), "ranking")
  hasrk = (rk != 0)
  source = "config"
  rankok = 1
  if (rk) {
    if (jk[rk] != "array" || jn[rk] == 0) rankok = 0
  } else {
    source = "default"
    rk = mch(mch(mch(mch(mch(sroot, "properties"), "models"), "properties"), "ranking"), "default")
    if (!rk || jk[rk] != "array" || jn[rk] == 0) rankok = 0
  }
  rline = ""
  if (rankok) {
    for (i = 1; i <= jn[rk]; i++) {
      item = jc[rk, i]
      if (jk[item] != "string") continue
      if (rline != "") rline = rline " < "
      rline = rline jv[item]
      n = split(jv[item], parts, "=")
      for (j = 1; j <= n; j++) if (parts[j] != "" && !(parts[j] in vrank)) vrank[parts[j]] = i
    }
  }

  for (i = 1; i <= nroles; i++) mresolve(roles[i])

  # the pairs: the producers each reviewer must rank at least as high as, in the order of the table
  prods["specReviewer"] = "specWriter"
  prods["codeReviewer"] = "implementer fixer"

  B = 0; U = 0
  for (i = 1; i <= nroles; i++) {
    role = roles[i]
    rank[role] = "-"; check[role] = "-"
    if (mranked(role)) rank[role] = vrank[mmodel[role]]
    if (!rankok) continue
    if (role == "specReviewer" || role == "codeReviewer") {
      if (mmodel[role] == "-") continue
      if (!mranked(role)) { check[role] = "NOT RANKED"; U++; continue }
      below = ""
      np = split(prods[role], pl, " ")
      for (j = 1; j <= np; j++) {
        if (mranked(pl[j]) && vrank[mmodel[role]] < vrank[mmodel[pl[j]]]) {
          if (below != "") below = below ", "
          below = below pl[j]
          B++
        }
      }
      if (below != "") check[role] = "BELOW " below
      else check[role] = "ok"
    } else if (role == "specWriter" || role == "implementer" || role == "fixer") {
      if (mmodel[role] != "-" && !mranked(role)) { check[role] = "NOT RANKED"; U++ }
    }
  }

  # the table: every column but the last as wide as its widest cell, two spaces between, no trailing space
  w1 = length("role"); w2 = length("does"); w3 = length("model"); w4 = length("from"); w5 = length("rank")
  for (i = 1; i <= nroles; i++) {
    role = roles[i]
    if (length(role) > w1) w1 = length(role)
    if (length(does[role]) > w2) w2 = length(does[role])
    if (length(mmodel[role]) > w3) w3 = length(mmodel[role])
    if (length(mfrom[role]) > w4) w4 = length(mfrom[role])
    if (length(rank[role]) > w5) w5 = length(rank[role])
  }
  print mpad("role", w1) "  " mpad("does", w2) "  " mpad("model", w3) "  " mpad("from", w4) "  " mpad("rank", w5) "  check"
  for (i = 1; i <= nroles; i++) {
    role = roles[i]
    print mpad(role, w1) "  " mpad(does[role], w2) "  " mpad(mmodel[role], w3) "  " mpad(mfrom[role], w4) "  " mpad(rank[role], w5) "  " check[role]
  }
  print ""
  if (rankok) print "ranking: " rline " (" source ")"
  else print "ranking: invalid (needs a non-empty list; run validate-config)"
  if (!rankok) print "pairings: not checked"
  else if (B == 0 && U == 0) print "pairings: ok"
  else print "pairings: " B " below, " U " not ranked"
  if (nconfig == 0 && !hasrk) print "No role model and no ranking in the config: these are the defaults of the schema."
  exit 0
}

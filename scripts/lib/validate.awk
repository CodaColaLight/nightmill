# scripts/lib/validate.awk - the walk of scripts/validate-config.sh (use it together with json.awk):
#   VAL_CONFIG=config.json VAL_SCHEMA=schema.json LC_ALL=C awk -f json.awk -f validate.awk
# Prints one record per finding, "<path> TAB <rank> TAB <line>" (rank 0 for an error, 1 for a warning), in
# no particular order; the caller sorts them with LC_ALL=C sort. Same checks, texts and order as
# validate-config.ps1: type, enum, pattern, not (only { "pattern": ... }), minimum, minItems, items, required,
# properties, additionalProperties (a schema, true or false); an unknown key is a warning, with a hint when it looks like a typo. After the
# walk, vpairs() checks that a reviewer role is not ranked below the role it reviews (iteration 15).
# Exit code 2 (message on standard error) when the schema or the config cannot be read, or the schema is
# not valid JSON. A config that is not valid JSON is a finding.

# the kind of a node: null, string, boolean, array, object, integer or number
function vkind(id,   x) {
  if (jk[id] == "number") {
    x = jv[id] + 0
    if (x == int(x)) return "integer"
    return "number"
  }
  return jk[id]
}

function vtypeok(id, t,   k) {
  k = vkind(id)
  if (t == "number") return (k == "integer" || k == "number")
  return (k == t)
}

# the JSON text of a scalar; the kind for an object or array
function vtext(id,   k) {
  k = jk[id]
  if (k == "string") return json_quote(jv[id])
  if (k == "number" || k == "boolean") return jv[id]
  if (k == "null") return "null"
  return k
}

function vsame(a, b) {
  if (jk[a] != jk[b]) return 0
  if (jk[a] == "number") return ((jv[a] + 0) == (jv[b] + 0))
  if (jk[a] == "string" || jk[a] == "boolean") return (jv[a] == jv[b])
  if (jk[a] == "null") return 1
  return 0
}

function vjoin(p, k) {
  if (p == "") return k
  return p "." k
}

function vfinding(path, sev, msg,   shown, rank) {
  shown = path
  if (shown == "") shown = "."
  rank = 1
  if (sev == "error") rank = 0
  print shown "\t" rank "\t" sev ": " shown ": " msg
}

# a known key of the object schema `props` that equals the unknown key ignoring case, or with one trailing
# character added or removed; "" when there is none
function vhint(key, props,   i, k, lkey) {
  lkey = tolower(key)
  for (i = 1; i <= jn[props]; i++) {
    k = jkey[props, i]
    if (tolower(k) == lkey) return k
    if (length(k) == length(key) + 1 && substr(k, 1, length(key)) == key) return k
    if (length(key) == length(k) + 1 && substr(key, 1, length(k)) == k) return k
  }
  return ""
}

function vnode(id, sid, path,   k, t, e, pt, nt, i, ok, list, item, mn, mi, it, req, props, ap, key, cid, cpath, pn, h, msg) {
  k = vkind(id)
  t = json_child(sid, "type")
  if (t && !vtypeok(id, jv[t])) {
    vfinding(path, "error", "expected " jv[t] ", got " k)
    return
  }
  e = json_child(sid, "enum")
  if (e) {
    ok = 0
    for (i = 1; i <= jn[e]; i++) if (vsame(id, jc[e, i])) ok = 1
    if (!ok) {
      list = ""
      for (i = 1; i <= jn[e]; i++) {
        item = jc[e, i]
        if (i > 1) list = list ", "
        if (jk[item] == "string") list = list jv[item]
        else list = list vtext(item)
      }
      vfinding(path, "error", "must be one of: " list ", got " vtext(id))
    }
  }
  # pattern and not (iteration 48): a search, case-sensitive (LC_ALL=C); a value that is not a string is not judged
  if (k == "string") {
    pt = json_child(sid, "pattern")
    if (pt && jk[pt] == "string" && jv[id] !~ jv[pt]) {
      vfinding(path, "error", "must match the pattern " jv[pt] ", got " vtext(id))
    }
    nt = json_child(json_child(sid, "not") + 0, "pattern")
    if (nt && jk[nt] == "string" && jv[id] ~ jv[nt]) {
      vfinding(path, "error", "must not match the pattern " jv[nt] ", got " vtext(id))
    }
  }
  mn = json_child(sid, "minimum")
  if (mn && (k == "integer" || k == "number") && (jv[id] + 0) < (jv[mn] + 0)) {
    vfinding(path, "error", "must be at least " vtext(mn) ", got " vtext(id))
  }
  if (k == "array") {
    mi = json_child(sid, "minItems")
    if (mi && jn[id] < (jv[mi] + 0)) vfinding(path, "error", "needs at least " jv[mi] " items, got " jn[id])
    it = json_child(sid, "items")
    if (it) for (i = 1; i <= jn[id]; i++) vnode(jc[id, i], it, path "[" (i - 1) "]")
  }
  if (k == "object") {
    req = json_child(sid, "required")
    if (req) {
      for (i = 1; i <= jn[req]; i++) {
        key = jv[jc[req, i]]
        if (!json_child(id, key)) vfinding(vjoin(path, key), "error", "required key is missing")
      }
    }
    props = json_child(sid, "properties")
    ap = json_child(sid, "additionalProperties")
    for (i = 1; i <= jn[id]; i++) {
      key = jkey[id, i]
      cid = jc[id, i]
      cpath = vjoin(path, key)
      pn = 0
      if (props) pn = json_child(props, key)
      if (pn) vnode(cid, pn, cpath)
      else if (key == "$schema") { }
      else if (ap) {
        if (jk[ap] == "boolean") {
          if (jv[ap] == "false") vfinding(cpath, "error", "unknown key is not allowed")
        }
        else vnode(cid, ap, cpath)
      }
      else {
        h = ""
        if (props) h = vhint(key, props)
        msg = "unknown key"
        if (h != "") msg = msg " (did you mean \"" h "\"?)"
        vfinding(cpath, "warning", msg)
      }
    }
  }
}

# --- the reviewer pairing (iteration 15) -------------------------------------------------------------------
# A rule across keys, which the schema cannot express: a reviewer role must rank at least as high as each role
# it reviews (specReviewer over specWriter, codeReviewer over implementer and fixer), judged by models.ranking.
# It runs on the effective models (the config's roles.<role>.model when it is a non-empty string, else the
# default of the schema) and on the effective ranking (the config's, else the default of the schema), so a
# config without the keys is clean. Same texts and same findings as validate-config.ps1.

# a child of a node, 0 when the node itself is 0
function vch(id, key) {
  if (!id) return 0
  return json_child(id, key)
}

# the model a role runs on: "" when neither the config nor the schema has one
function vrolemodel(role,   n, d) {
  n = vch(vch(vch(croot, "roles"), role), "model")
  if (n && jk[n] == "string" && jv[n] != "") return jv[n]
  d = vch(vch(vch(vch(vch(vch(sroot, "properties"), "roles"), "properties"), role), "properties"), "model")
  d = vch(d, "default")
  if (d && jk[d] == "string") return jv[d]
  return ""
}

function vpairs(   rk, i, item, n, j, parts, role, roles, nroles, pair, rev, prod, m, rrank, prank) {
  if (jk[croot] != "object") return
  if (!vch(vch(sroot, "properties"), "roles")) return
  rk = vch(vch(croot, "models"), "ranking")
  if (rk) {
    if (jk[rk] != "array" || jn[rk] == 0) return
  } else {
    rk = vch(vch(vch(vch(vch(sroot, "properties"), "models"), "properties"), "ranking"), "default")
    if (!rk || jk[rk] != "array") return
  }
  # the rank of a name: the 1-based position of the first entry that has it as a part of a "="-joined entry
  for (i = 1; i <= jn[rk]; i++) {
    item = jc[rk, i]
    if (jk[item] != "string") continue
    n = split(jv[item], parts, "=")
    for (j = 1; j <= n; j++) if (parts[j] != "" && !(parts[j] in vrank)) vrank[parts[j]] = i
  }
  nroles = split("specWriter specReviewer implementer codeReviewer fixer", roles, " ")
  for (i = 1; i <= nroles; i++) {
    role = roles[i]
    vmodel[role] = vrolemodel(role)
    if (vmodel[role] != "" && !(vmodel[role] in vrank)) {
      vfinding("roles." role ".model", "warning", "model " json_quote(vmodel[role]) " is not in models.ranking, so " role " cannot be compared")
    }
  }
  # the pairs: reviewer, then the role it reviews
  split("specReviewer:specWriter codeReviewer:implementer codeReviewer:fixer", pair, " ")
  for (i = 1; i <= 3; i++) {
    split(pair[i], m, ":")
    rev = m[1]; prod = m[2]
    if (vmodel[rev] == "" || vmodel[prod] == "") continue
    if (!(vmodel[rev] in vrank) || !(vmodel[prod] in vrank)) continue
    rrank = vrank[vmodel[rev]]; prank = vrank[vmodel[prod]]
    if (rrank < prank) {
      vfinding("roles." rev ".model", "error", rev " on " json_quote(vmodel[rev]) " ranks below " prod " on " json_quote(vmodel[prod]))
    }
  }
}

BEGIN {
  if (ENVIRON["VAL_CONFIG"] == "") exit 0
  sfile = ENVIRON["VAL_SCHEMA"]
  cfile = ENVIRON["VAL_CONFIG"]
  stext = json_read(sfile)
  if (!jread_ok) { print "cannot read schema: " sfile > "/dev/stderr"; exit 2 }
  sroot = json_parse(stext)
  if (!sroot) { print "json: " sfile ": " jerr > "/dev/stderr"; exit 2 }
  ctext = json_read(cfile)
  if (!jread_ok) { print "cannot read config: " cfile > "/dev/stderr"; exit 2 }
  croot = json_parse(ctext)
  if (!croot) { vfinding("", "error", "not valid JSON"); exit 0 }
  vnode(croot, sroot, "")
  vpairs()
  exit 0
}

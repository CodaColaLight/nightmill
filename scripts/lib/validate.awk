# scripts/lib/validate.awk - the walk of scripts/validate-config.sh (use it together with json.awk):
#   VAL_CONFIG=config.json VAL_SCHEMA=schema.json LC_ALL=C awk -f json.awk -f validate.awk
# Prints one record per finding, "<path> TAB <rank> TAB <line>" (rank 0 for an error, 1 for a warning), in
# no particular order; the caller sorts them with LC_ALL=C sort. Same checks, texts and order as
# validate-config.ps1: type, enum, minimum, minItems, items, required, properties, additionalProperties
# (a schema, true or false); an unknown key is a warning, with a hint when it looks like a typo.
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

function vnode(id, sid, path,   k, t, e, i, ok, list, item, mn, mi, it, req, props, ap, key, cid, cpath, pn, h, msg) {
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
  exit 0
}

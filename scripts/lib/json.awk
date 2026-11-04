# scripts/lib/json.awk - a strict JSON parser in POSIX awk, for the bash scripts (no jq needed).
#
# Run it as   LC_ALL=C awk -f json.awk     with the work given in the environment:
#   JSON_MODE=flat   JSON_FILE=path   print one record per node (see below); exit 1 on invalid JSON
#   JSON_MODE=check  JSON_FILE=path   print nothing; exit 1 on invalid JSON
#   JSON_MODE=quote  JSON_S=string    print the string as a JSON string literal (like jq's tojson)
# With JSON_MODE unset the file only defines functions, for other awk programs (validate.awk).
# The environment, not -v, carries values because -v would interpret backslash sequences in them.
#
# Flat record, parent before children, in document order:  <path> TAB <kind> TAB <value>
#   path   keys joined with dots, "[i]" for an array item: worktrees.warmup[0].command; the root is empty
#   kind   object, array, string, number, boolean or null
#   value  for an object or array the number of children; for a string its decoded text with \ newline tab
#          and carriage return written as \\ \n \t \r (a record is always one line); a number or boolean
#          as written; empty for null
#
# The grammar is RFC 8259: no trailing commas, comments, single quotes, leading zeros, control characters
# in strings, text after the value, or nesting deeper than 64 levels. \uXXXX is decoded to UTF-8 (a
# surrogate pair gives one character); \u0000 is not supported. An error is one line on standard error,
# "json: <file>: <reason> at byte <n>".
#
# The node table other programs use: jk[id] kind, jv[id] value (strings decoded), jn[id] number of
# children, jc[id, i] child id and jkey[id, i] its key (objects only), for i = 1..jn[id].
#
# Only POSIX awk: no gensub, no switch, no length(array), no regex intervals, no arrays of arrays.

function json_fail(msg) {
  if (jerr == "") jerr = msg " at byte " (jp - 1)
  return 0
}

function json_new(kind, val,   id) {
  id = ++jcount
  jk[id] = kind
  jv[id] = val
  jn[id] = 0
  return id
}

function json_isdigit(c) {
  return (c != "" && c >= "0" && c <= "9")
}

function json_ws(   c) {
  while (jp <= jlen) {
    c = substr(jt, jp, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") jp++
    else break
  }
}

function json_hex(h,   i, v, d) {
  v = 0
  h = tolower(h)
  for (i = 1; i <= length(h); i++) {
    d = index("0123456789abcdef", substr(h, i, 1)) - 1
    v = v * 16 + d
  }
  return v
}

function json_ishex4(h,   i) {
  if (length(h) != 4) return 0
  for (i = 1; i <= 4; i++) if (index("0123456789abcdefABCDEF", substr(h, i, 1)) == 0) return 0
  return 1
}

# the UTF-8 bytes of a code point (needs LC_ALL=C so that %c writes one byte)
function json_utf8(cp) {
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}

# parses the string at jp (on the opening quote); the decoded text is left in jstr
function json_string(   c, out, h, cp, lo) {
  jp++
  out = ""
  while (1) {
    if (jp > jlen) return json_fail("unterminated string")
    c = substr(jt, jp, 1)
    if (c == "\"") { jp++; jstr = out; return 1 }
    if (c == "\\") {
      jp++
      c = substr(jt, jp, 1)
      if (c == "\"") out = out "\""
      else if (c == "\\") out = out "\\"
      else if (c == "/") out = out "/"
      else if (c == "b") out = out "\b"
      else if (c == "f") out = out "\f"
      else if (c == "n") out = out "\n"
      else if (c == "r") out = out "\r"
      else if (c == "t") out = out "\t"
      else if (c == "u") {
        h = substr(jt, jp + 1, 4)
        if (!json_ishex4(h)) return json_fail("bad \\u escape")
        cp = json_hex(h)
        jp += 4
        if (cp >= 55296 && cp <= 56319) {
          if (substr(jt, jp + 1, 2) == "\\u" && json_ishex4(substr(jt, jp + 3, 4))) {
            lo = json_hex(substr(jt, jp + 3, 4))
            if (lo < 56320 || lo > 57343) return json_fail("bad surrogate pair")
            cp = 65536 + (cp - 55296) * 1024 + (lo - 56320)
            jp += 6
          }
          else return json_fail("lone surrogate")
        }
        else if (cp >= 56320 && cp <= 57343) return json_fail("lone surrogate")
        if (cp == 0) return json_fail("\\u0000 is not supported")
        out = out json_utf8(cp)
      }
      else return json_fail("bad escape")
      jp++
      continue
    }
    if (c < " ") return json_fail("control character in string")
    out = out c
    jp++
  }
}

function json_number(   s, c) {
  s = jp
  if (substr(jt, jp, 1) == "-") jp++
  c = substr(jt, jp, 1)
  if (c == "0") {
    jp++
    if (json_isdigit(substr(jt, jp, 1))) return json_fail("leading zero in number")
  }
  else if (json_isdigit(c)) { while (json_isdigit(substr(jt, jp, 1))) jp++ }
  else return json_fail("bad number")
  if (substr(jt, jp, 1) == ".") {
    jp++
    if (!json_isdigit(substr(jt, jp, 1))) return json_fail("bad number")
    while (json_isdigit(substr(jt, jp, 1))) jp++
  }
  c = substr(jt, jp, 1)
  if (c == "e" || c == "E") {
    jp++
    c = substr(jt, jp, 1)
    if (c == "+" || c == "-") jp++
    if (!json_isdigit(substr(jt, jp, 1))) return json_fail("bad number")
    while (json_isdigit(substr(jt, jp, 1))) jp++
  }
  return json_new("number", substr(jt, s, jp - s))
}

function json_object(depth,   id, n, key, child, c) {
  id = json_new("object", "")
  jp++
  json_ws()
  if (substr(jt, jp, 1) == "}") { jp++; return id }
  while (1) {
    json_ws()
    if (substr(jt, jp, 1) != "\"") return json_fail("expected a string key")
    if (!json_string()) return 0
    key = jstr
    json_ws()
    if (substr(jt, jp, 1) != ":") return json_fail("expected ':'")
    jp++
    child = json_value(depth + 1)
    if (!child) return 0
    n = ++jn[id]
    jc[id, n] = child
    jkey[id, n] = key
    json_ws()
    c = substr(jt, jp, 1)
    if (c == ",") { jp++; continue }
    if (c == "}") { jp++; return id }
    return json_fail("expected ',' or '}'")
  }
}

function json_array(depth,   id, n, child, c) {
  id = json_new("array", "")
  jp++
  json_ws()
  if (substr(jt, jp, 1) == "]") { jp++; return id }
  while (1) {
    child = json_value(depth + 1)
    if (!child) return 0
    n = ++jn[id]
    jc[id, n] = child
    json_ws()
    c = substr(jt, jp, 1)
    if (c == ",") { jp++; continue }
    if (c == "]") { jp++; return id }
    return json_fail("expected ',' or ']'")
  }
}

function json_value(depth,   c) {
  if (depth > 64) return json_fail("nesting too deep")
  json_ws()
  if (jp > jlen) return json_fail("unexpected end of input")
  c = substr(jt, jp, 1)
  if (c == "{") return json_object(depth)
  if (c == "[") return json_array(depth)
  if (c == "\"") {
    if (!json_string()) return 0
    return json_new("string", jstr)
  }
  if (c == "-" || json_isdigit(c)) return json_number()
  if (substr(jt, jp, 4) == "true") { jp += 4; return json_new("boolean", "true") }
  if (substr(jt, jp, 5) == "false") { jp += 5; return json_new("boolean", "false") }
  if (substr(jt, jp, 4) == "null") { jp += 4; return json_new("null", "") }
  return json_fail("unexpected character")
}

# parse a text; returns the root node id, or 0 with the reason in jerr
function json_parse(text) {
  jt = text
  jlen = length(jt)
  jp = 1
  jerr = ""
  jroot = json_value(1)
  if (!jroot) return 0
  json_ws()
  if (jp <= jlen) { jroot = 0; json_fail("unexpected text after the value"); return 0 }
  return jroot
}

# the whole file as one text; jread_ok is 0 when it cannot be read
function json_read(path,   line, text, rc) {
  text = ""
  jread_ok = 1
  while ((rc = (getline line < path)) > 0) text = text line "\n"
  close(path)
  if (rc < 0) jread_ok = 0
  return text
}

# the child of an object node with this key (the last one when a key repeats), or 0
function json_child(id, key,   i, r) {
  r = 0
  for (i = 1; i <= jn[id]; i++) if (jkey[id, i] == key) r = jc[id, i]
  return r
}

function json_escape_flat(s,   out, i, c, n) {
  if (index(s, "\\") == 0 && index(s, "\n") == 0 && index(s, "\t") == 0 && index(s, "\r") == 0) return s
  out = ""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") out = out "\\\\"
    else if (c == "\n") out = out "\\n"
    else if (c == "\t") out = out "\\t"
    else if (c == "\r") out = out "\\r"
    else out = out c
  }
  return out
}

# a string as a JSON string literal
function json_quote(s,   out, i, c, n, k) {
  out = "\""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\"") out = out "\\\""
    else if (c == "\\") out = out "\\\\"
    else if (c == "\n") out = out "\\n"
    else if (c == "\t") out = out "\\t"
    else if (c == "\r") out = out "\\r"
    else if (c == "\b") out = out "\\b"
    else if (c == "\f") out = out "\\f"
    else if (c < " ") {
      for (k = 1; k < 32; k++) if (c == sprintf("%c", k)) break
      out = out sprintf("\\u%04x", k)
    }
    else out = out c
  }
  return out "\""
}

function json_emit(id, path,   k, n, i, cpath, key) {
  k = jk[id]
  if (k == "object" || k == "array") {
    print path "\t" k "\t" jn[id]
    n = jn[id]
    for (i = 1; i <= n; i++) {
      if (k == "object") {
        key = json_escape_flat(jkey[id, i])
        if (path == "") cpath = key
        else cpath = path "." key
      }
      else cpath = path "[" (i - 1) "]"
      json_emit(jc[id, i], cpath)
    }
  }
  else if (k == "string") print path "\t" k "\t" json_escape_flat(jv[id])
  else print path "\t" k "\t" jv[id]
}

BEGIN {
  json_mode = ENVIRON["JSON_MODE"]
  if (json_mode == "flat" || json_mode == "check") {
    json_file = ENVIRON["JSON_FILE"]
    json_text = json_read(json_file)
    if (!jread_ok) {
      print "json: cannot read " json_file > "/dev/stderr"
      exit 1
    }
    if (!json_parse(json_text)) {
      print "json: " json_file ": " jerr > "/dev/stderr"
      exit 1
    }
    if (json_mode == "flat") json_emit(jroot, "")
    exit 0
  }
  if (json_mode == "quote") {
    print json_quote(ENVIRON["JSON_S"])
    exit 0
  }
}

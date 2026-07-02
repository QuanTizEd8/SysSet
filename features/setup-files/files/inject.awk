# inject.awk — implements the `inject` operation for setup-files.
#
# Invoked as: awk -v bm_re=... -v em_re=... ... -f inject.awk "$dest"
#
# awk -v scalars (safe: no backslashes/newlines, so awk's -v escape
# processing — which recognises \t/\n/\\ etc. and silently drops an unknown
# backslash escape like \[ down to a bare [ — cannot corrupt them):
#   bm_re    1 = bm is an ERE (object-form marker), 0 = literal exact-line match
#   em_re    1 = em is an ERE, 0 = literal exact-line match
#   inf      if_not_found: end_of_file | beginning_of_file | fail
#   anc_pos  anchor position: after | before
#   anf      anchor_not_found: fail | end_of_file | beginning_of_file
#   lead_nl  leading_newline: true | false
#   trail_nl trailing_newline: true | false
#   rew      rewrite_markers: true | false
#
# ENVIRON (NOT passed via -v: ENVIRON values are taken verbatim from the
# process environment, with no escape processing at all — required both for
# multi-line safety, AND because bm/em/anc are ERE patterns that legitimately
# contain backslash escapes, e.g. anchor: '^\[section\]$'. awk -v would
# silently mangle \[ to a bare [, changing a literal-bracket match into a
# bracket-expression character class — a correctness bug, not just a
# formatting quirk):
#   _SF_AWK_CONTENT  block content
#   _SF_AWK_BW       begin marker literal write-text
#   _SF_AWK_EW       end marker literal write-text
#   _SF_AWK_BM       begin marker match value (literal string or ERE, per bm_re)
#   _SF_AWK_EM       end marker match value (literal string or ERE, per em_re)
#   _SF_AWK_ANCHOR   anchor match value (ERE); empty string means "no anchor set"
#
# Exit codes: 0 success, 2 malformed (begin with no end), 3 multiple blocks
# found, 4 anchor not found (anchor_not_found=fail), 5 block not found
# (if_not_found=fail).
function with_trailing_nl(s) {
  # Force exactly one trailing newline onto content before the end marker is
  # printed. Without this, content supplied without its own trailing newline
  # (e.g. a one-line plain-scalar YAML value) would run directly into the end
  # marker text on the same physical line — corrupting the line structure so
  # badly that a later update-in-place pass, which reprints the end-marker
  # line verbatim when rewrite_markers is false, would reprint the stale
  # leftover content glued onto it.
  if (length(s) == 0) return s
  if (substr(s, length(s), 1) != "\n") return s "\n"
  return s
}
BEGIN {
  bw = ENVIRON["_SF_AWK_BW"]
  ew = ENVIRON["_SF_AWK_EW"]
  content = ENVIRON["_SF_AWK_CONTENT"]
  bm = ENVIRON["_SF_AWK_BM"]
  em = ENVIRON["_SF_AWK_EM"]
  anc = ENVIRON["_SF_AWK_ANCHOR"]
  n = 0
  bi = 0
  ei = 0
}
{ lines[++n] = $0 }
END {
  # Locate an existing begin/end marker pair (bm_re/em_re: 1=ERE match, 0=literal exact line).
  for (i = 1; i <= n; i++) {
    if (!bi && (bm_re ? lines[i] ~ bm : lines[i] == bm)) {
      bi = i
      continue
    }
    if (bi && !ei && (em_re ? lines[i] ~ em : lines[i] == em)) {
      ei = i
      break
    }
  }
  if (bi && !ei) {
    print "ERROR:malformed" > "/dev/stderr"
    exit 2
  }
  if (ei) {
    for (i = ei + 1; i <= n; i++) {
      if (bm_re ? lines[i] ~ bm : lines[i] == bm) {
        print "ERROR:multiple" > "/dev/stderr"
        exit 3
      }
    }
  }

  if (bi && ei) {
    # Update the existing block in place.
    for (i = 1; i <= n; i++) {
      if (i == bi) {
        print(rew == "true" ? bw : lines[i])
        printf "%s", with_trailing_nl(content)
        i = ei
        print(rew == "true" ? ew : lines[i])
        continue
      }
      print lines[i]
    }
    exit 0
  }

  # No existing block: determine insertion point.
  ins = -99
  if (anc != "") {
    for (i = 1; i <= n; i++) {
      if (lines[i] ~ anc) {
        ins = (anc_pos == "before" ? i - 1 : i)
        break
      }
    }
    if (ins == -99) {
      if (anf == "fail") {
        print "ERROR:anchor" > "/dev/stderr"
        exit 4
      }
      if (anf == "end_of_file") ins = n
      if (anf == "beginning_of_file") ins = 0
    }
  } else {
    if (inf == "end_of_file") ins = n
    else if (inf == "beginning_of_file") ins = 0
    else {
      print "ERROR:notfound" > "/dev/stderr"
      exit 5
    }
  }

  block = ""
  if (lead_nl == "true" && ins > 0 && n > 0 && lines[ins] !~ /^[[:space:]]*$/) block = "\n"
  block = block bw "\n" with_trailing_nl(content) ew
  if (trail_nl == "true") block = block "\n"

  for (i = 1; i <= n; i++) {
    if (ins == 0 && i == 1) printf "%s", block
    print lines[i]
    if (i == ins && ins < n) printf "%s", block
  }
  if (ins >= n) printf "%s", block
}

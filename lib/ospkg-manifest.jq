include "ctx-match";

def ctx: $ctx;

def to_lines: if type == "array" then join("\n") else . end;

def merge_flags(gf; pf):
  if   gf == null and pf == null then null
  elif gf == null then pf
  elif pf == null then gf
  else [(gf | if type == "array" then .[] else . end),
        (pf | if type == "array" then .[] else . end)] | join(" ")
  end;

def repo_content:
  if type == "string" then .
  else empty
  end;

# visit(k; inherited_flags): traverse packages array, emitting items of kind k.
def visit(k; gf):
  if type == "string" then
    if k == "package" then
      {kind: "package", name: ., command: null, flags: gf, version: null}
    else empty end
  elif has("packages") then
    # group object
    if item_when_matches then
      . as $g |
      merge_flags(gf; ($g.flags // null)) as $mf |
      if k == "prescript" then
        (if $g | has("prescript") then
          {kind: "prescript", content: ($g.prescript | to_lines)} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "key" then
        (if $g | has("keys") then
          $g.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
        else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "repo" then
        (if $g | has("repos") then $g.repos[] | {kind: "repo", content: repo_content} else empty end),
        ($g.packages[] | visit(k; $mf))
      elif k == "package" then
        ($g.packages[] | visit(k; $mf))
      elif k == "script" then
        ($g.packages[] | visit(k; $mf)),
        (if $g | has("script") then
          {kind: "script", content: ($g.script | to_lines)} else empty end)
      else
        ($g.packages[] | visit(k; $mf))
      end
    else empty
    end
  else
    # package object
    if item_when_matches then
      . as $e |
      if k == "prescript" then
        if $e | has("prescript") then
          {kind: "prescript", content: ($e.prescript | to_lines)}
        else empty end
      elif k == "key" then
        if $e | has("keys") then
          $e.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
        else empty end
      elif k == "repo" then
        if $e | has("repos") then $e.repos[] | {kind: "repo", content: repo_content} else empty end
      elif k == "package" then
        {kind: "package",
         name: (
           ($e[$pm] // $e.name) as $n
           | if ($n | type) == "string" and ($n | length) > 0 then $n else null end
         ),
         command: ($e.command // null),
         flags: merge_flags(gf; ($e.flags // null)),
         version: ($e.version // null)}
      elif k == "script" then
        if $e | has("script") then
          {kind: "script", content: ($e.script | to_lines)}
        else empty end
      else empty
      end
    else empty
    end
  end;

# ── Emit items in pipeline phase order ────────────────────────────────────────
# Normalize array shorthand to {packages: [...]} so all phase logic is uniform.
(if (. | type) == "array" then {packages: .} else . end) as $doc |

# Top-level when: skip entire manifest if it does not match.
if ($doc | has("when")) and (($doc | item_when_matches) | not) then
  empty
else

# Phase: PRESCRIPTS — top-level, then inline
(if $doc | has("prescripts") then
  {kind: "prescript", content: ($doc.prescripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("prescript"; null) else empty end),

# Phase: KEYS — top-level, PM block, then inline
(if $doc | has("keys") then
  $doc.keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("keys")) then
  $doc[$pm].keys[] | {kind: "key", url: (.url // null), dest: .dest, dearmor: (.dearmor // null), fingerprint: (.fingerprint // null)}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("key"; null) else empty end),

# Phase: REPOS — top-level, PM block, then inline
(if $doc | has("repos") then
  $doc.repos[] | {kind: "repo", content: repo_content}
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("repos")) then
  $doc[$pm].repos[] | {kind: "repo", content: repo_content}
else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("repo"; null) else empty end),

# Phase: PM-SPECIFIC SETUP — top-level then PM-block
(if $pm == "apt" then
  (if $doc | has("ppas") then $doc.ppas[] | {kind: "ppa", ppa: .} else empty end),
  (if ($doc | has("apt")) and ($doc.apt | has("ppas")) then
    $doc.apt.ppas[] | {kind: "ppa", ppa: .} else empty end)
else empty end),
(if $pm == "brew" then
  (if $doc | has("taps") then $doc.taps[] | {kind: "tap", tap: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("taps")) then
    $doc.brew.taps[] | {kind: "tap", tap: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("copr") then $doc.copr[] | {kind: "copr", copr: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("copr")) then
    $doc.dnf.copr[] | {kind: "copr", copr: .} else empty end)
else empty end),
(if $pm == "dnf" then
  (if $doc | has("modules") then $doc.modules[] | {kind: "module", module: .} else empty end),
  (if ($doc | has("dnf")) and ($doc.dnf | has("modules")) then
    $doc.dnf.modules[] | {kind: "module", module: .} else empty end)
else empty end),
(if $doc | has("groups") then
  $doc.groups[] |
  if type == "string" and (length) > 0 then {kind: "group", group: .}
  elif (type == "object") and item_when_matches
       and ((.name | type) == "string")
       and ((.name | length) > 0) then
    {kind: "group", group: .name}
  else empty
  end
else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("groups")) then
  $doc[$pm].groups[] |
  if type == "string" and (length) > 0 then {kind: "group", group: .}
  elif (type == "object") and item_when_matches
       and ((.name | type) == "string")
       and ((.name | length) > 0) then
    {kind: "group", group: .name}
  else empty
  end
else empty end),

# Phase: PACKAGES — inline packages array, then PM-specific packages block
(if $doc | has("packages") then
  $doc.packages[] | visit("package"; null)
  | select(
      (.name | type) == "string"
      and ((.name | length) > 0)
    ) else empty end),
(if ($doc | has($pm)) and ($doc[$pm] | has("packages")) then
  $doc[$pm].packages[] | visit("package"; null)
  | select(
      (.name | type) == "string"
      and ((.name | length) > 0)
    )
else empty end),

# Phase: CASKS (brew/macOS only) — top-level then PM block
(if $pm == "brew" then
  (if $doc | has("casks") then $doc.casks[] | {kind: "cask", cask: .} else empty end),
  (if ($doc | has("brew")) and ($doc.brew | has("casks")) then
    $doc.brew.casks[] | {kind: "cask", cask: .} else empty end)
else empty end),

# Phase: SCRIPTS — PM block, then top-level, then inline
(if ($doc | has($pm)) and ($doc[$pm] | has("scripts")) then
  {kind: "script", content: ($doc[$pm].scripts | to_lines)} else empty end),
(if $doc | has("scripts") then
  {kind: "script", content: ($doc.scripts | to_lines)} else empty end),
(if $doc | has("packages") then
  $doc.packages[] | visit("script"; null) else empty end)

end

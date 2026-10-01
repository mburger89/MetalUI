#!/bin/zsh
# Public-API census for plan task 15, the replacement closeout (ruling CX-A).
#
# Prints one tab-separated line per `public`/`open` declaration in every
# Sources/ target that ships in a library product or is re-exported by
# `MetalUI` (`@_exported import` in Sources/MetalUI/App.swift):
#
#   target <TAB> file:line <TAB> owner <TAB> kind <TAB> name
#
# `owner` is the enclosing type or extension, dotted for nesting (`-` at file
# scope); `kind` is the declaration keyword (struct, enum, class, protocol,
# typealias, actor, func, init, subscript, var, let, case, associatedtype,
# operator); `name` is the declared base name (`init`/`subscript` for those).
# Owners are read from 4-space indentation, which every file under Sources/
# uses; a declaration the reader cannot attribute prints owner `?` and must be
# resolved by hand in the inventory (record §66).
#
# USAGE: docs/probes/closeout-public-api.sh [repo-root]   (default: this repo)
# The recorded output is docs/probes/closeout-public-api.tsv; re-run and diff.
set -e
ROOT=${1:-${0:A:h:h:h}}
cd $ROOT
TARGETS=(MetalUI MetalUICore MetalUILayout MetalUIPlatform MetalUIPrimitives
         MetalUITextSystem MetalUIRender MetalUIText MetalUIAppKit MetalUIScene
         MetalUIFreeType MetalUIHarfBuzz MetalUIPortableText MetalUISystemFonts
         MetalUIDemoContent)
for t in $TARGETS; do
  for f in $(git ls-files "Sources/$t/*.swift" | sort); do
    awk -v T=$t -v F=$f '
      function indent(s) { match(s, /^ */); return RLENGTH }
      function ownerAt(k,   o, i) { o = ""; for (i = 0; i < k; i += 4) if (own[i] != "") o = (o == "" ? own[i] : o "." own[i]); return o == "" ? "-" : o }
      /^[ ]*\/\// { next }
      {
        line = $0; k = indent(line)
        # forget owners at or deeper than this indentation when a new
        # declaration or closing brace appears at it
        if (line ~ /^[ ]*}/) { for (i = k; i <= 64; i += 4) own[i] = ""; next }
        decl = line; sub(/^[ ]*/, "", decl)
        while (decl ~ /^@[A-Za-z_]+(\([^)]*\))?[ ]/) sub(/^@[A-Za-z_]+(\([^)]*\))?[ ]+/, "", decl)
        isTypeLike = (decl ~ /^((public|open|package|internal|fileprivate|private|final|indirect|nonisolated)[ ]+)*(struct|enum|class|protocol|extension|actor)[ ]/)
        if (isTypeLike) {
          for (i = k; i <= 64; i += 4) own[i] = ""
          n = decl; sub(/^((public|open|package|internal|fileprivate|private|final|indirect|nonisolated)[ ]+)*(struct|enum|class|protocol|extension|actor)[ ]+/, "", n)
          sub(/[^A-Za-z0-9_.].*$/, "", n); own[k] = n
        }
        if (decl !~ /^(public|open)[ ]/) next
        if (decl ~ /^(public|open)[ ]+(import|extension)[ ]/) next
        d = decl; sub(/^((public|open|package|final|static|override|mutating|nonmutating|nonisolated|indirect|convenience|required|lazy|dynamic|weak|unowned|private\(set\)|internal\(set\)|package\(set\)|fileprivate\(set\))[ ]+)*/, "", d)
        sub(/^class[ ]+(func|var|subscript)/, "&", d); if (d ~ /^class[ ]+(func|var|subscript)[ ]/) sub(/^class[ ]+/, "", d)
        kind = d; sub(/[ (<].*$/, "", kind)
        name = d; sub(/^[a-z]+[ ]*/, "", name)
        if (kind == "init" || kind == "init?" || kind == "subscript") { name = kind; kind = (kind ~ /^init/ ? "init" : "subscript") }
        else { sub(/[^A-Za-z0-9_`+*\/=<>!&|^~%.-].*$/, "", name); sub(/[(<:].*$/, "", name) }
        o = (isTypeLike ? ownerAt(k) : ownerAt(k))
        if (isTypeLike && k == 0) o = "-"
        print T "\t" F ":" FNR "\t" o "\t" kind "\t" name
      }' $f
  done
done

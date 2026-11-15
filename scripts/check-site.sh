#!/bin/zsh
# Checks the static site before publishing. Usage: scripts/check-site.sh [dir=site]. Exit 0 = pass.
setopt nullglob
dir=${1:-site}
fail=0
bad() { print -u2 "FAIL: $1"; fail=1 }

[[ -f $dir/index.html ]] || { print -u2 "FAIL: $dir/index.html missing"; exit 1 }

# Local href/src targets exist (relative to the page; # and query stripped).
for page in $dir/*.html; do
  base=$(dirname $page)
  grep -oE '(href|src)="[^"]*"' $page | sed -E 's/^(href|src)="//; s/"$//' | while read -r ref; do
    case $ref in
      http://*|https://*|mailto:*|data:*|\#*|"") continue ;;
      api/*|/MetalUI/*) continue ;;  # the DocC archive is assembled at deploy time (Task 5); /MetalUI/ is 404.html's <base>
    esac
    target=${ref%%[?#]*}
    [[ -z $target ]] && continue
    [[ $target == /* ]] && p=$dir$target || p=$base/$target
    [[ -e $p ]] || bad "$page: $ref points at a missing file"
  done
done

# No off-site scripts or stylesheets.
for f in $dir/*.html; do
  grep -oE '<script[^>]*src="https?://[^"]*"' $f | while read -r l; do bad "$f: off-site script: $l"; done
  grep -oE '<link[^>]*rel="stylesheet"[^>]*href="https?://[^"]*"' $f | while read -r l; do bad "$f: off-site stylesheet: $l"; done
  grep -oE '<link[^>]*href="https?://[^"]*"[^>]*rel="stylesheet"' $f | while read -r l; do bad "$f: off-site stylesheet: $l"; done
done
grep -nE '@import|url\(["'"'"']?https?:' $dir/*.css 2>/dev/null | while read -r l; do bad "off-site CSS reference: $l"; done

# Weight (HTML, CSS, JS, images; not the two source notes).
total=$(find $dir -type f ! -name quickstart.md ! -name CREDITS.md -exec stat -f %z {} + | awk '{s+=$1} END {print s+0}')
(( total <= 1572864 )) || bad "site weighs $total bytes, over 1572864"
print "weight: $total bytes"

idx=$dir/index.html
grep -q '<meta name="viewport"' $idx || bad "index.html lacks a viewport meta"
grep -q '<title>[^<]' $idx || bad "index.html lacks a title"
grep -q 'prefers-color-scheme' $dir/style.css 2>/dev/null || bad "style.css lacks prefers-color-scheme"
grep -q 'Experimental' $idx || bad "index.html lacks the word Experimental"
xmllint --html --noout $idx 2>&1 | grep -v "^$" | grep -iE "error|parser" | grep -vE "Tag (header|nav|main|section|article|figure|figcaption|footer) invalid" | while read -r l; do bad "xmllint: $l"; done

(( fail == 0 )) && print "site ok"
exit $fail

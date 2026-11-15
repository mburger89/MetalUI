#!/bin/zsh
# Build the static DocC API reference.
#   usage: scripts/build-docs.sh <out-dir>
# Entry page: <out-dir>/documentation/metalui/index.html (hosting base path MetalUI/api).
set -euo pipefail
cd "${0:A:h}/.."

out=${1:?usage: scripts/build-docs.sh <out-dir>}
out=${out:A}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift build --target MetalUI \
  -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$tmp/sg-all"

# MetalUI and its @_exported modules only.
mkdir -p "$tmp/sg"
for m in MetalUI MetalUICore MetalUILayout MetalUIPlatform MetalUIPrimitives \
         MetalUITextSystem MetalUIRender MetalUICodeBuffer MetalUIMarkdown; do
  for f in "$tmp/sg-all/$m.symbols.json" "$tmp/sg-all/$m@"*.symbols.json(N); do
    [[ -f $f ]] && cp "$f" "$tmp/sg/"
  done
done

rm -rf "$out"; mkdir -p "${out:h}"
xcrun docc convert Sources/MetalUI/MetalUI.docc \
  --additional-symbol-graph-dir "$tmp/sg" \
  --fallback-display-name MetalUI \
  --fallback-bundle-identifier com.mburger89.MetalUI \
  --transform-for-static-hosting \
  --hosting-base-path MetalUI/api \
  --output-path "$out" 2>&1 | tee "$tmp/docc.log"

[[ -f $out/documentation/metalui/index.html ]] || { echo "missing documentation/metalui/index.html" >&2; exit 1; }
echo "docc warnings: $(grep -c 'warning:' "$tmp/docc.log" || true)"

# MetalUITesting: a second archive under api/testing (no catalog, symbol graph only).
mkdir -p "$tmp/sgt"
swift build --target MetalUITesting \
  -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$tmp/sgt-all"
cp "$tmp/sgt-all/MetalUITesting.symbols.json" "$tmp/sgt/"
xcrun docc convert \
  --additional-symbol-graph-dir "$tmp/sgt" \
  --fallback-display-name MetalUITesting \
  --fallback-bundle-identifier com.mburger89.MetalUITesting \
  --transform-for-static-hosting \
  --hosting-base-path MetalUI/api/testing \
  --output-path "$out/testing"
[[ -f $out/testing/documentation/metaluitesting/index.html ]] || { echo "missing testing archive" >&2; exit 1; }

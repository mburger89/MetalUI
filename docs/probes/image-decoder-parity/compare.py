# Image-decoder parity (ruling PX-C): the portable decoder against ImageIO and
# against what SwiftUI draws, on the same files.
#
# HOW TO RUN (macOS; from this directory, any scratch directory as $T):
#
#   python3 gen-fixtures.py $T/fx                      # 22 files, known pixels
#   clang -O1 -I <dir with stb_image.h> stb-decode.c -o $T/stbdec
#   xcrun swiftc -O imageio-decode.swift -o $T/iio     # MetalUI's ImageIO path at 359444e
#   xcrun swiftc -O swiftui-decode.swift -o $T/sui     # Image(nsImage:) via ImageRenderer
#   (cd $T && python3 <this dir>/compare.py fx/*)
#
# Each tool prints premultiplied sRGB RGBA8 ("w h" then the bytes) or "nil".
# `imageio-decode.swift` is `ImageBitmap(contentsOfFile:)`'s body at 359444e
# (draw into a premultipliedLast sRGB CGContext); `stb-decode.c` is the ruled
# portable rule (16-bit rounded to 8, then ImageTexture's premultiply);
# `swiftui-decode.swift` draws `Image(nsImage: NSImage(contentsOfFile:))` with
# `ImageRenderer` at scale 1 and reads it back the same way.
#
# stb_image.h: v2.30, https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
# fetched 2026-10-07, sha256 594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3.
#
# RECORDED 2026-10-07 by the portable-app design session, macOS 27.0.1
# (26A434), Apple Swift 6.4, Apple clang 2100.3.33.1, Pillow 12.3.0 (JPEGs):
#
#   corrupt-idat.png       swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb nil              imageio-vs-stb nil
#   corrupt-ihdr.png       swiftui-vs-imageio nil              swiftui-vs-stb nil              imageio-vs-stb nil
#   corrupt-truncated.png  swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb nil              imageio-vs-stb nil
#   gray.jpg               swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 6/252 max 1      imageio-vs-stb 6/252 max 1
#   gray1.png              swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   gray4.png              swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   gray8.png              swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   graya8.png             swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   palette2-trns.png      swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   q90-prog.jpg           swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 35/252 max 2     imageio-vs-stb 35/252 max 2
#   q90.jpg                swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 35/252 max 2     imageio-vs-stb 35/252 max 2
#   rand16.png             swiftui-vs-imageio 0/16384 max 0    swiftui-vs-stb 0/16384 max 0    imageio-vs-stb 0/16384 max 0
#   rand8-adam7.png        swiftui-vs-imageio 0/16384 max 0    swiftui-vs-stb 0/16384 max 0    imageio-vs-stb 0/16384 max 0
#   rand8.png              swiftui-vs-imageio 0/16384 max 0    swiftui-vs-stb 0/16384 max 0    imageio-vs-stb 0/16384 max 0
#   rgb8-gama18.png        swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 172/252 max 19   imageio-vs-stb 172/252 max 19
#   rgb8-p3.png            swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 161/252 max 87   imageio-vs-stb 161/252 max 87
#   rgb8-srgb.png          swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   rgb8.png               swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   rgba16-adam7.png       swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   rgba16.png             swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   rgba8-adam7.png        swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#   rgba8.png              swiftui-vs-imageio 0/252 max 0      swiftui-vs-stb 0/252 max 0      imageio-vs-stb 0/252 max 0
#
# And on the SMK configurator's 66 icons (Resources/{macOS,Linux,Windows}/
# Icons/{light,dark}/*.png at its feat/metalui-port: 36 of 48×48 and 30 of
# 66×66, 8-bit RGBA; 44 untagged with bKGD, 22 sRGB-tagged with eXIf), every
# file: swiftui-vs-imageio 0, swiftui-vs-stb 0, imageio-vs-stb 0 bytes differ.
#
# READING NOTES.
# - SwiftUI draws exactly what ImageIO decodes, on every file (0 bytes differ):
#   ImageIO's answer IS SwiftUI's answer for these files.
# - The portable rule equals both, byte for byte, on every 8-bit PNG that is
#   untagged or sRGB-tagged — RGBA, RGB, gray 1/4/8, gray+alpha, palette with
#   tRNS, Adam7 — and on 16-bit PNGs (rand16: 16384 bytes, 0 differ), because
#   16-bit samples are ROUNDED to 8 bits. (stb's own 8-bit path truncates,
#   v >> 8, and then differs: rgba16 29/252 bytes, max 2 — measured first,
#   the reason the rule rounds.) ImageIO's premultiply matches ImageTexture's
#   (c × a + 127) / 255 on every alpha (rand8: 16384 bytes, 0 differ).
# - It differs where ImageIO COLOUR-MANAGES: a gAMA 1/1.8 PNG (max 19) and a
#   Display P3 iCCP PNG (max 87); the portable rule takes samples as sRGB.
# - JPEG differs by at most 2 (IDCT and chroma upsampling are the decoder's).
# - Corrupt files: ImageIO (so SwiftUI) returns a partial image for a flipped
#   bit inside IDAT and for a file cut in half; stb returns nil for both. A
#   flipped bit in IHDR's width: nil from all three.

import subprocess, sys, os
def run(tool, f):
    o = subprocess.run([tool, f], capture_output=True, text=True).stdout.split('\n')
    if o[0].startswith('nil'): return None
    return list(map(int, o[1].split()))
def diff(a, b):
    if a is None or b is None: return 'nil'
    d = [abs(x - y) for x, y in zip(a, b)]
    return f"{sum(1 for x in d if x)}/{len(d)} max {max(d)}"
for f in sys.argv[1:]:
    s, i, u = run('./stbdec', f), run('./iio', f), run('./sui', f)
    print(f"{os.path.basename(f):22s} swiftui-vs-imageio {diff(u, i):16s} swiftui-vs-stb {diff(u, s):16s} imageio-vs-stb {diff(i, s)}")

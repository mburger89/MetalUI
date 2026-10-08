# Image-decoder parity fixtures (ruling PX-C): small PNGs with KNOWN pixels,
# written by a pure-Python encoder (zlib only) so the expected values come from
# this file, not from any decoder.
#
# Usage:
#   python3 gen-fixtures.py <out-dir>        # the probe set (compare.py)
#   python3 gen-fixtures.py --tests [<dir>]  # the committed test set (spec
#       §4.2), default Tests/MetalUICrossPlatformTests/ImageFixtures; prints
#       each 4×3 PNG's expected premultiplied bytes as a Swift literal, computed
#       here from the straight pixels with ImageTexture's rule
#       ((c × a + 127) / 255; 16-bit samples first rounded (v × 255 + 32767) /
#       65535, PX-C item 2). JPEG and TIFF need Pillow (12.3.0 when recorded).
import zlib, struct, sys, os
TESTS = len(sys.argv) > 1 and sys.argv[1] == '--tests'
if TESTS:
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', '..', '..', 'Tests',
                                                             'MetalUICrossPlatformTests', 'ImageFixtures')
else:
    out = sys.argv[1]
os.makedirs(out, exist_ok=True)
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
ADAM7 = [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
def pack_row(samples, depth):
    if depth >= 8:
        b = bytearray()
        for s in samples: b += s.to_bytes(depth // 8, 'big')
        return bytes(b)
    b = bytearray(); acc = 0; n = 0
    for s in samples:
        acc = (acc << depth) | s; n += depth
        if n == 8: b.append(acc); acc = 0; n = 0
    if n: b.append(acc << (8 - n))
    return bytes(b)
def png(name, w, h, ctype, depth, pix, interlace=False, extra=b'', pre=b''):
    # pix[y][x] = tuple of samples per channel
    raw = bytearray()
    if not interlace:
        for y in range(h): raw += b'\0' + pack_row([s for p in pix[y] for s in p], depth)
    else:
        for x0, y0, dx, dy in ADAM7:
            for y in range(y0, h, dy):
                row = [s for x in range(x0, w, dx) for s in pix[y][x]]
                if row: raw += b'\0' + pack_row(row, depth)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, depth, ctype, 0, 0, 1 if interlace else 0)) \
        + pre + extra + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    open(os.path.join(out, name), 'wb').write(data)
def premul8(pix):
    # pix[y][x] = (r, g, b, a) straight 8-bit -> the premultiplied bytes.
    b = []
    for row in pix:
        for r, g, bl, a in row: b += [(r * a + 127) // 255, (g * a + 127) // 255, (bl * a + 127) // 255, a]
    return b
def to_rgba(ctype, depth, pix, pal=None, trns=None):
    # One fixture's straight 8-bit RGBA, from its samples (the expected values).
    def s8(v): return (v * 255 + 32767) // 65535 if depth == 16 else (v * 255 // ((1 << depth) - 1) if depth < 8 else v)
    res = []
    for row in pix:
        r_ = []
        for p in row:
            if ctype == 0: g = s8(p[0]); r_.append((g, g, g, 255))
            elif ctype == 4: g = s8(p[0]); r_.append((g, g, g, s8(p[1])))
            elif ctype == 2: r_.append((s8(p[0]), s8(p[1]), s8(p[2]), 255))
            elif ctype == 6: r_.append(tuple(s8(v) for v in p))
            elif ctype == 3: c = pal[p[0]]; r_.append((c[0], c[1], c[2], trns[p[0]] if p[0] < len(trns) else 255))
        res.append(r_)
    return res
if TESTS:
    # The committed test set (spec §4.2). 4×3 images whose expected bytes are
    # printed; 9×7 twins for Adam7; the corrupt, oversized and thumbnail files.
    W, H = 4, 3
    rgba = [[(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (200, 100, 50, 128)],
            [(10, 20, 30, 0), (255, 255, 255, 64), (17, 34, 51, 200), (128, 128, 128, 255)],
            [(0, 0, 0, 255), (250, 5, 99, 1), (77, 155, 233, 128), (1, 2, 3, 254)]]
    pal = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (200, 100, 50)]
    trns = bytes([255, 128, 0, 64])
    rgba16 = [[(0, 255, 386, 65535), (32896, 65280, 65535, 65535), (65535, 0, 255, 65535), (386, 32896, 65280, 65535)],
              [(1000, 2000, 3000, 65535), (65535, 65535, 65535, 32896), (12345, 23456, 34567, 65535), (0, 0, 0, 0)],
              [(257, 514, 771, 65535), (65280, 65280, 65280, 65535), (128, 127, 129, 65535), (40000, 50000, 60000, 65535)]]
    rgb = [[p[:3] for p in r] for r in rgba]
    specs = [  # name, ctype, depth, samples, extra kwargs
        ('gray1.png', 0, 1, [[((x + y) & 1,) for x in range(W)] for y in range(H)], {}),
        ('gray4.png', 0, 4, [[((x + y * 3) % 16,) for x in range(W)] for y in range(H)], {}),
        ('gray8.png', 0, 8, [[(p[0],) for p in r] for r in rgba], {}),
        ('graya8.png', 4, 8, [[(p[0], p[3]) for p in r] for r in rgba], {}),
        ('palette2-trns.png', 3, 2, [[((x + y) % 4,) for x in range(W)] for y in range(H)],
         {'pre': chunk(b'PLTE', bytes(c for p in pal for c in p)) + chunk(b'tRNS', trns)}),
        ('rgb8.png', 2, 8, rgb, {}),
        ('rgba8.png', 6, 8, rgba, {}),
        ('rgba8-adam7.png', 6, 8, rgba, {'interlace': True}),
        ('rgba16.png', 6, 16, rgba16, {}),
        ('rgb8-srgb.png', 2, 8, rgb, {'extra': chunk(b'sRGB', b'\0')}),
    ]
    icc_path = '/System/Library/ColorSync/Profiles/Display P3.icc'
    if os.path.exists(icc_path):
        icc = open(icc_path, 'rb').read()
        specs.append(('rgb8-p3.png', 2, 8, rgb, {'extra': chunk(b'iCCP', b'Display P3\0\0' + zlib.compress(icc))}))
    else:
        print('no Display P3 profile: rgb8-p3.png not rewritten')
    for name, ctype, depth, samples, kw in specs:
        png(name, W, H, ctype, depth, samples, **kw)
        expected = premul8(to_rgba(ctype, depth, samples, pal, trns))
        print('%s: %s' % (name, expected))
    W9, H9 = 9, 7
    rgba9 = [[((x*29) % 256, (y*37) % 256, ((x+y)*17) % 256, (x*31 + y*13) % 256) for x in range(W9)] for y in range(H9)]
    png('rgba8-9x7.png', W9, H9, 6, 8, rgba9)
    png('rgba8-adam7-9x7.png', W9, H9, 6, 8, rgba9, interlace=True)
    # Corrupt copies of the 4×3 rgba8.png: one flipped bit inside IDAT's data,
    # the first half of the file, one flipped bit in IHDR's width.
    d = bytearray(open(os.path.join(out, 'rgba8.png'), 'rb').read())
    i = d.index(b'IDAT')
    c = bytearray(d); c[i + 10] ^= 0x01; open(os.path.join(out, 'corrupt-idat.png'), 'wb').write(c)
    open(os.path.join(out, 'corrupt-truncated.png'), 'wb').write(d[:len(d) // 2])
    c = bytearray(d); c[20] ^= 0x01; open(os.path.join(out, 'corrupt-ihdr.png'), 'wb').write(c)
    # One solid row at the dimension cap and one past it (valid CRCs, PX-D).
    for w in (16384, 16385):
        png('wide-%dx1.png' % w, w, 1, 6, 8, [[(10, 20, 30, 255)] * w])
    try:
        from PIL import Image
        # A smooth 4×3 source at 4:4:4: a JPEG of rgb8's pixels (4:2:0, Pillow's
        # default) decodes up to ~200 away from them — chroma is averaged over
        # 2×2 — so "within 3 of the source" (test 2.5) needs smooth content
        # (measured with stb: 4:4:4, steps 2/3/4/6/8 → max 1/2/3/3/3).
        smooth = [[(120 + x * 6, 80 + y * 6, 60 + (x + y) * 3) for x in range(W)] for y in range(H)]
        im = Image.new('RGB', (W, H))
        for y in range(H):
            for x in range(W): im.putpixel((x, y), smooth[y][x])
        im.save(os.path.join(out, 'q90.jpg'), quality=90, subsampling=0)
        print('q90.jpg source (straight RGB): %s' % [c for r in smooth for p in r for c in p])
        # thumb.jpg: q90.jpg with an APP1 right after SOI whose payload holds
        # FF D8 FF DA 00 02 00 FF D9 (a thumbnail's SOI, SOS and EOI); and
        # thumb-truncated.jpg, the same with its main scan cut in half
        # (PX-O item 2: a raw FF DA ... FF D9 scan passes it).
        j = open(os.path.join(out, 'q90.jpg'), 'rb').read()
        payload = bytes([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x00, 0xFF, 0xD9])
        t = j[:2] + bytes([0xFF, 0xE1]) + struct.pack('>H', len(payload) + 2) + payload + j[2:]
        open(os.path.join(out, 'thumb.jpg'), 'wb').write(t)
        k = 2 + 2 + 2 + len(payload)
        while True:  # walk segments to the main SOS
            assert t[k] == 0xFF
            m = t[k + 1]; L = struct.unpack('>H', t[k + 2:k + 4])[0]
            if m == 0xDA: break
            k += 2 + L
        scan = k + 2 + L
        eoi = len(t) - 2
        open(os.path.join(out, 'thumb-truncated.jpg'), 'wb').write(t[:scan + (eoi - scan) // 2])
        # A TIFF (ImageIO decodes it on Apple; nil elsewhere, PX-C item 5).
        im = Image.open(os.path.join(out, 'rgb8.png')).convert('RGB')
        im.save(os.path.join(out, 'rgb8.tiff'))
    except ImportError:
        print('no Pillow: JPEG and TIFF fixtures not rewritten')
    sys.exit(0)
W, H = 9, 7
rgba = [[((x*29) % 256, (y*37) % 256, ((x+y)*17) % 256, (x*31 + y*13) % 256) for x in range(W)] for y in range(H)]
png('rgba8.png', W, H, 6, 8, rgba)
png('rgba8-adam7.png', W, H, 6, 8, rgba, interlace=True)
png('rgb8.png', W, H, 2, 8, [[p[:3] for p in r] for r in rgba])
png('gray8.png', W, H, 0, 8, [[(p[0],) for p in r] for r in rgba])
png('graya8.png', W, H, 4, 8, [[(p[0], p[3]) for p in r] for r in rgba])
png('gray1.png', W, H, 0, 1, [[((x + y) & 1,) for x in range(W)] for y in range(H)])
png('gray4.png', W, H, 0, 4, [[((x + y*3) % 16,) for x in range(W)] for y in range(H)])
pal = [(255,0,0),(0,255,0),(0,0,255),(200,100,50)]
trns = bytes([255, 128, 0, 64])
png('palette2-trns.png', W, H, 3, 2, [[((x + y) % 4,) for x in range(W)] for y in range(H)],
    pre=chunk(b'PLTE', bytes(c for p in pal for c in p)) + chunk(b'tRNS', trns))
rgba16 = [[(p[0]*257 + (x*7 % 256), p[1]*257 + 128, p[2]*257 + 255, p[3]*257 + (y*11 % 256)) for x, p in enumerate(r)] for y, r in enumerate(rgba)]
png('rgba16.png', W, H, 6, 16, rgba16)
png('rgba16-adam7.png', W, H, 6, 16, rgba16, interlace=True)
png('rgb8-gama18.png', W, H, 2, 8, [[p[:3] for p in r] for r in rgba], extra=chunk(b'gAMA', struct.pack('>I', 55556)))
png('rgb8-srgb.png', W, H, 2, 8, [[p[:3] for p in r] for r in rgba], extra=chunk(b'sRGB', b'\0'))
icc = open('/System/Library/ColorSync/Profiles/Display P3.icc', 'rb').read() if os.path.exists('/System/Library/ColorSync/Profiles/Display P3.icc') else None
if icc: png('rgb8-p3.png', W, H, 2, 8, [[p[:3] for p in r] for r in rgba], extra=chunk(b'iCCP', b'Display P3\0\0' + zlib.compress(icc)))
# Two 64×64 random images (seeded), 16-bit and 8-bit (plain and Adam7).
import random
random.seed(7)
W = H = 64
png('rand16.png', W, H, 6, 16, [[tuple(random.randrange(65536) for _ in range(4)) for x in range(W)] for y in range(H)])
pix8 = [[tuple(random.randrange(256) for _ in range(4)) for x in range(W)] for y in range(H)]
png('rand8.png', W, H, 6, 8, pix8)
png('rand8-adam7.png', W, H, 6, 8, pix8, interlace=True)
# JPEGs need Pillow (12.3.0 when recorded); skipped without it.
try:
    from PIL import Image
    im = Image.open(os.path.join(out, 'rgb8.png')).convert('RGB')
    im.save(os.path.join(out, 'q90.jpg'), quality=90)
    im.save(os.path.join(out, 'q90-prog.jpg'), quality=90, progressive=True)
    im.convert('L').save(os.path.join(out, 'gray.jpg'), quality=90)
except ImportError:
    print('no Pillow: JPEG fixtures skipped')
# Corrupt copies of rgba8.png: one flipped bit inside IDAT's data, the first
# half of the file, one flipped bit in IHDR's width.
d = bytearray(open(os.path.join(out, 'rgba8.png'), 'rb').read())
i = d.index(b'IDAT')
c = bytearray(d); c[i + 10] ^= 0x01; open(os.path.join(out, 'corrupt-idat.png'), 'wb').write(c)
open(os.path.join(out, 'corrupt-truncated.png'), 'wb').write(d[:len(d) // 2])
c = bytearray(d); c[20] ^= 0x01; open(os.path.join(out, 'corrupt-ihdr.png'), 'wb').write(c)

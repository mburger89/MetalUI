# Image-decoder parity fixtures (ruling PX-C): small PNGs with KNOWN pixels,
# written by a pure-Python encoder (zlib only) so the expected values come from
# this file, not from any decoder. Usage: python3 gen-fixtures.py <out-dir>
# Writes small PNG fixtures with known pixels (pure Python, zlib only).
import zlib, struct, sys, os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
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

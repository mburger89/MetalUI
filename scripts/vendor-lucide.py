#!/usr/bin/env python3
"""Generate Sources/MetalUIIconData/LucideData.swift from one pinned `lucide-static` tarball (record 232, SYM-I).

    python3 -I scripts/vendor-lucide.py <lucide-static-X.Y.Z.tgz> <expected-sha256> <output-dir>

The tarball is only READ: its LICENSE and the listed `icons/<name>.svg` members are streamed out of it with
`tarfile` (nothing is extracted to disk, nothing in it is executed). The script refuses to run unless

  * the tarball's sha256 equals <expected-sha256>, and
  * `package/LICENSE` starts with "ISC License" and carries the Feather MIT text,

then converts every listed icon to one path of move / line / cubic / close commands (circle, ellipse, rect,
line, polyline, polygon, quadratics, smooth curves and SVG elliptical arcs are all reduced to those four, so
neither the runtime nor MetalUIPath needs arc maths) and writes `LucideData.swift` and `LICENSE` into <output-dir>.
`VENDORED.md` is written by hand beside them (version, sha256, icon list).

Opcodes: 0 move (x y), 1 line (x y), 2 cubic (c1x c1y c2x c2y x y), 3 close. Coordinates are in the icons'
24 x 24 viewBox, rounded to 3 decimals.
"""
import hashlib
import math
import re
import sys
import tarfile
import xml.etree.ElementTree as ET

# The Lucide icons MetalUI bundles (the SF name table in Sources/MetalUI/BundledSymbols.swift maps onto these).
ICONS = [
    "search", "file", "file-text", "pencil", "square-pen", "file-plus", "square-terminal", "brain", "sparkles",
    "globe", "user", "circle-user", "triangle-alert", "x", "circle-x", "play", "square", "circle-stop", "check",
    "chevron-right", "chevron-down", "copy", "undo-2", "square-arrow-out-up-right", "columns-2", "cpu", "circle",
    "triangle", "star",
    # Record 232 addendum: eight more Alloy names.
    "list-checks", "message-circle-question", "clipboard-list", "puzzle", "info", "paperclip", "image", "settings",
    # Record 252 (G16): the plain eye forms.
    "eye", "eye-off",
]

# Ring composites (record 252, SYM-P): Lucide has no circled form of these, so the script builds one: Lucide's own `circle`
# (cx 12, cy 12, r 10) plus the inner icon's geometry scaled about (12, 12) by the factor and baked into the path data.
# The stroke width is not scaled (it stays the ring's, as SF's circled symbols do). A later `.circle` request adds a row.
# (synthetic name, inner Lucide icon, scale)
COMPOSITES = [
    ("eye-circle", "eye", 0.5),
    ("eye-off-circle", "eye-off", 0.5),
]

ARITY = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


class Out:
    def __init__(self):
        self.ops = []
        self.coords = []
        self.cur = (0.0, 0.0)
        self.start = (0.0, 0.0)
        self.open = False

    def move(self, x, y):
        self.ops.append(0); self.coords += [x, y]
        self.cur = self.start = (x, y); self.open = True

    def line(self, x, y):
        if not self.open: self.move(*self.cur)
        self.ops.append(1); self.coords += [x, y]; self.cur = (x, y)

    def cubic(self, a, b, c, d, x, y):
        if not self.open: self.move(*self.cur)
        self.ops.append(2); self.coords += [a, b, c, d, x, y]; self.cur = (x, y)

    def close(self):
        self.ops.append(3); self.cur = self.start; self.open = False


def arc(out, x1, y1, rx, ry, phi_deg, large, sweep, x2, y2):
    """SVG elliptical arc (endpoint form) as cubics of at most 90 degrees (SVG 1.1 implementation notes F.6)."""
    if (x1, y1) == (x2, y2): return
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        out.line(x2, y2); return
    phi = math.radians(phi_deg % 360)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        s = math.sqrt(lam); rx *= s; ry *= s
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0.0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0: dt -= 2 * math.pi
    if sweep and dt < 0: dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)

    def pt(t):
        return (cx + rx * math.cos(t) * cp - ry * math.sin(t) * sp, cy + rx * math.cos(t) * sp + ry * math.sin(t) * cp)

    def der(t):
        return (-rx * math.sin(t) * cp - ry * math.cos(t) * sp, -rx * math.sin(t) * sp + ry * math.cos(t) * cp)

    t = t1
    for i in range(n):
        p0, d0 = pt(t), der(t)
        t2 = t + step
        p1, d1 = pt(t2), der(t2)
        end = (x2, y2) if i == n - 1 else p1
        out.cubic(p0[0] + k * d0[0], p0[1] + k * d0[1], p1[0] - k * d1[0], p1[1] - k * d1[1], end[0], end[1])
        t = t2


NUMBER = re.compile(r"[\s,]*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)")
FLAG = re.compile(r"[\s,]*([01])")


def path_data(out, d):
    pos = 0
    cmd = None
    last_c2 = None  # previous cubic's second control point, for S
    last_q = None   # previous quadratic's control point, for T
    while True:
        m = re.compile(r"[\s,]*").match(d, pos)
        pos = m.end()
        if pos >= len(d): break
        if d[pos].isalpha():
            cmd = d[pos]; pos += 1
            if cmd not in "MmLlHhVvCcSsQqTtAaZz": raise ValueError("unknown command in " + d)
            if cmd in "Zz":
                out.close(); last_c2 = last_q = None
                continue
        elif cmd is None:
            raise ValueError("path data starts with a number: " + d)
        up = cmd.upper()
        args = []
        for k in range(ARITY[up]):
            # An arc's 4th and 5th arguments are single-character flags, which may touch the next number ("01-3").
            rx_ = FLAG if (up == "A" and k in (3, 4)) else NUMBER
            m = rx_.match(d, pos)
            if not m: raise ValueError("short arguments in " + d)
            args.append(float(m.group(1))); pos = m.end()
        rel = cmd != up
        cx, cy = out.cur
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if up == "M":
            out.move(args[0] + ox, args[1] + oy)
            cmd = "l" if rel else "L"  # further pairs are implicit lineto
            last_c2 = last_q = None
        elif up == "L":
            out.line(args[0] + ox, args[1] + oy); last_c2 = last_q = None
        elif up == "H":
            out.line(args[0] + ox, cy); last_c2 = last_q = None
        elif up == "V":
            out.line(cx, args[0] + oy); last_c2 = last_q = None
        elif up == "C":
            a = (args[0] + ox, args[1] + oy); b = (args[2] + ox, args[3] + oy); e = (args[4] + ox, args[5] + oy)
            out.cubic(*a, *b, *e); last_c2 = b; last_q = None
        elif up == "S":
            a = (2 * cx - last_c2[0], 2 * cy - last_c2[1]) if last_c2 else (cx, cy)
            b = (args[0] + ox, args[1] + oy); e = (args[2] + ox, args[3] + oy)
            out.cubic(*a, *b, *e); last_c2 = b; last_q = None
        elif up in "QT":
            if up == "Q":
                q = (args[0] + ox, args[1] + oy); e = (args[2] + ox, args[3] + oy)
            else:
                q = (2 * cx - last_q[0], 2 * cy - last_q[1]) if last_q else (cx, cy)
                e = (args[0] + ox, args[1] + oy)
            out.cubic(cx + 2 / 3 * (q[0] - cx), cy + 2 / 3 * (q[1] - cy),
                      e[0] + 2 / 3 * (q[0] - e[0]), e[1] + 2 / 3 * (q[1] - e[1]), *e)
            last_q = q; last_c2 = None
        elif up == "A":
            arc(out, cx, cy, args[0], args[1], args[2], args[3] != 0, args[4] != 0, args[5] + ox, args[6] + oy)
            last_c2 = last_q = None


def ellipse(out, cx, cy, rx, ry):
    out.move(cx + rx, cy)
    arc(out, cx + rx, cy, rx, ry, 0, False, True, cx, cy + ry)
    arc(out, cx, cy + ry, rx, ry, 0, False, True, cx - rx, cy)
    arc(out, cx - rx, cy, rx, ry, 0, False, True, cx, cy - ry)
    arc(out, cx, cy - ry, rx, ry, 0, False, True, cx + rx, cy)
    out.close()


def rect(out, x, y, w, h, rx, ry):
    if rx == 0 and ry == 0:
        out.move(x, y); out.line(x + w, y); out.line(x + w, y + h); out.line(x, y + h); out.close(); return
    rx = min(rx or ry, w / 2); ry = min(ry or rx, h / 2)
    out.move(x + rx, y)
    out.line(x + w - rx, y); arc(out, x + w - rx, y, rx, ry, 0, False, True, x + w, y + ry)
    out.line(x + w, y + h - ry); arc(out, x + w, y + h - ry, rx, ry, 0, False, True, x + w - rx, y + h)
    out.line(x + rx, y + h); arc(out, x + rx, y + h, rx, ry, 0, False, True, x, y + h - ry)
    out.line(x, y + ry); arc(out, x, y + ry, rx, ry, 0, False, True, x + rx, y)
    out.close()


def convert(svg_text, name):
    root = ET.fromstring(svg_text)
    if root.get("viewBox") != "0 0 24 24": raise ValueError(name + ": viewBox is not 0 0 24 24")
    out = Out()
    for el in root:
        tag = el.tag.split("}")[-1]
        # Each element is its own SVG path: its current point starts at the origin (a relative `m` is absolute there).
        out.cur = out.start = (0.0, 0.0)
        out.open = False
        f = lambda key, default=0.0: float(el.get(key, default))
        if tag == "path": path_data(out, el.get("d"))
        elif tag == "circle": ellipse(out, f("cx"), f("cy"), f("r"), f("r"))
        elif tag == "ellipse": ellipse(out, f("cx"), f("cy"), f("rx"), f("ry"))
        elif tag == "rect": rect(out, f("x"), f("y"), f("width"), f("height"), f("rx"), f("ry"))
        elif tag == "line": out.move(f("x1"), f("y1")); out.line(f("x2"), f("y2"))
        elif tag in ("polyline", "polygon"):
            nums = [float(t) for t in re.findall(r"[-+]?(?:\d+\.?\d*|\.\d+)", el.get("points"))]
            out.move(nums[0], nums[1])
            for j in range(2, len(nums), 2): out.line(nums[j], nums[j + 1])
            if tag == "polygon": out.close()
        else:
            raise ValueError(name + ": unsupported element " + tag)
    return out


def composite(inner, scale):
    """The ring (Lucide `circle`) followed by `inner` scaled about the view-box centre."""
    out = Out()
    ellipse(out, 12.0, 12.0, 10.0, 10.0)
    out.ops += inner.ops
    for i, v in enumerate(inner.coords):
        out.coords.append(12.0 + (v - 12.0) * scale)
    return out


def swift_name(name):
    parts = name.split("-")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def num(v):
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    tgz, expected, outdir = sys.argv[1:4]
    digest = hashlib.sha256(open(tgz, "rb").read()).hexdigest()
    if digest != expected: sys.exit("sha256 mismatch: " + digest)
    with tarfile.open(tgz, "r:gz") as tar:
        licence = tar.extractfile("package/LICENSE").read().decode("utf-8")
        if not licence.startswith("ISC License") or "The MIT License (MIT)" not in licence:
            sys.exit("licence is not ISC with the Feather MIT portion; stop")
        version = re.search(r'"version":\s*"([^"]+)"', tar.extractfile("package/package.json").read().decode()).group(1)
        icons = {n: convert(tar.extractfile("package/icons/%s.svg" % n).read().decode("utf-8"), n) for n in ICONS}
        for name, inner, scale in COMPOSITES:
            # The inner icon is read from the tarball itself, so it need not be in ICONS (it is only bundled if listed).
            icons[name] = composite(icons[inner] if inner in icons else convert(
                tar.extractfile("package/icons/%s.svg" % inner).read().decode("utf-8"), inner), scale)
            ICONS.append(name)
    lines = [
        "// GENERATED by scripts/vendor-lucide.py from lucide-static %s (sha256 %s) — do not edit." % (version, digest),
        "// Lucide, ISC licence with portions MIT (Feather): see LICENSE and VENDORED.md in this directory.",
        "// Opcodes: 0 move (x y), 1 line (x y), 2 cubic (c1x c1y c2x c2y x y), 3 close; a 24 x 24 viewBox.",
        "",
        "/// One bundled icon: its path as opcodes and coordinates (record 232, `SYM-I`). Imports nothing; `package` data only.",
        "package struct IconPathData: Sendable, Hashable {",
        "    package let ops: [UInt8]",
        "    package let coords: [Float]",
        "}",
        "",
        "/// The bundled Lucide icons, by Lucide name.",
        "package enum LucideIcons {",
        "    package static let version = \"%s\"" % version,
        "    package static let tarballSHA256 = \"%s\"" % digest,
        "    /// The viewBox side every icon is drawn on.",
        "    package static let viewBoxSide: Float = 24",
        "    /// Lucide's own stroke width on that grid (its regular weight).",
        "    package static let strokeWidth: Float = 2",
        "    package static let names: [String] = [" + ", ".join('"%s"' % n for n in ICONS) + "]",
        "",
        "    package static func data(named name: String) -> IconPathData? {",
        "        switch name {",
    ]
    for n in ICONS: lines.append('        case "%s": return %s' % (n, swift_name(n)))
    lines += ["        default: return nil", "        }", "    }", ""]
    total_ops = total_coords = 0
    for n in ICONS:
        o = icons[n]
        total_ops += len(o.ops); total_coords += len(o.coords)
        lines.append("    private static let %s = IconPathData(" % swift_name(n))
        lines.append("        ops: [%s] as [UInt8]," % ", ".join(str(x) for x in o.ops))
        lines.append("        coords: [%s] as [Float])" % ", ".join(num(v) for v in o.coords))
    lines.append("}")
    open(outdir + "/LucideData.swift", "w").write("\n".join(lines) + "\n")
    open(outdir + "/LICENSE", "w").write(licence)
    print("lucide-static %s sha256 %s: %d icons, %d opcodes, %d coordinates" % (version, digest, len(ICONS), total_ops, total_coords))


main()

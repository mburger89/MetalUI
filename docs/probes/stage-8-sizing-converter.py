#!/usr/bin/env python3
"""Stage 8's sizing converter (plan task 7, stage 8; ruling LR-ES, spec §5).

An INSTRUMENT, not a finished migration: it applies the recipe's two
mechanical rules and flags every site it cannot decide.

  R1  a run of adjacent sizing calls on one receiver (`.width`, `.height`,
      `.minWidth`, `.maxWidth`, `.minHeight`, `.maxHeight`, in any order,
      whitespace/newlines between them) becomes ONE `.frame(...)` at the run's
      place — fixed axes as `frame(width:height:)`, bounds as
      `frame(minWidth:maxWidth:minHeight:maxHeight:)`; a later call on the same
      axis wins, as `StyledElement.modifying` does. A run mixing a fixed axis
      with a bound is left alone and flagged MIXED (R5 decides it by hand).
  R3  when the receiver is a `Row`/`Column`/`Box` block (`... }.width(...)`),
      the frame gets the alignment that puts the container's hugging content
      where the sized container put it: Row `.leading`, Column `.top`, Box
      `.topLeading`. A `Stack` or an unrecognised block is flagged CONTAINER.

Flags printed, never fixed: STYLE-AFTER-FRAME (a `Style`-writing modifier
follows the new frame on the same chain — it would report
`modifierLayer.style`, R4), MIXED, CONTAINER. It does not move a decoration,
handler, `.id` or `.focusable` written BEFORE the sizing call (R2), does not
touch `fraction:`/`percent:` calls or comment lines, and does not fix a helper's
stored return type (`-> Box<...>`), which the compiler reports.

Measured by the design session (record §50 §4): on `DisabledTests` and
`FocusTests` (80 frames) R1 alone left 20 issues in 37 tests; R1 + R3 left one,
a literal structural id path used to locate state (spec §5, R7).

Usage: python3 docs/probes/stage-8-sizing-converter.py <file>...   (edits in place)
"""
import re, sys
NAMES = ['minWidth','maxWidth','minHeight','maxHeight','width','height']
FIXED = {'width','height'}
def match_paren(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(': depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0: return j
    return -1
call_re = re.compile(r'\.(' + '|'.join(NAMES) + r')\(')
def convert(src, fname):
    out = []; i = 0; n = 0; flags = []
    while True:
        m = call_re.search(src, i)
        if not m: out.append(src[i:]); break
        # skip `fraction:`/`percent:` and comments
        line_start = src.rfind('\n', 0, m.start()) + 1
        if '//' in src[line_start:m.start()]:
            out.append(src[i:m.end()]); i = m.end(); continue
        run = []; j = m.start()
        while True:
            mm = call_re.match(src, j)
            if not mm: break
            close = match_paren(src, mm.end() - 1)
            arg = src[mm.end():close]
            if arg.startswith('fraction:') or arg.startswith('percent:'): break
            run.append((mm.group(1), arg)); k = close + 1
            ws = re.match(r'\s*', src[k:]).end()
            if call_re.match(src, k + ws): j = k + ws
            else: j = k; break
        if not run:
            out.append(src[i:m.end()]); i = m.end(); continue
        d = {}
        for name, arg in run: d[name] = arg   # later wins, as modifying does
        fixed = [x for x in ('width','height') if x in d]
        bounds = [x for x in ('minWidth','maxWidth','minHeight','maxHeight') if x in d]
        lineno = src.count('\n', 0, m.start()) + 1
        if fixed and bounds:
            flags.append(f"{fname}:{lineno}: MIXED fixed+bounds {d}")
            out.append(src[i:j]); i = j; continue
        order = ['width','height'] if fixed else ['minWidth','maxWidth','minHeight','maxHeight']
        args = ', '.join(f"{x}: {d[x]}" for x in order if x in d)
        # R3: a container's frame reproduces where the container put its content.
        k0 = m.start()
        while k0 > 0 and src[k0-1] in ' \t\n': k0 -= 1
        align = None
        if k0 > 0 and src[k0-1] == '}':
            depth = 0; p0 = k0 - 1
            while p0 >= 0:
                if src[p0] == '}': depth += 1
                elif src[p0] == '{':
                    depth -= 1
                    if depth == 0: break
                p0 -= 1
            head = src[max(0, p0-80):p0]
            hm = re.search(r'\b(Row|Column|Box|Stack|HStack|VStack|ZStack)\s*(\([^()]*\))?\s*$', head)
            kind = hm.group(1) if hm else None
            align = {'Row': '.leading', 'Column': '.top', 'Box': '.topLeading'}.get(kind)
            if kind in ('Stack', None): flags.append(f"{fname}:{src.count(chr(10),0,m.start())+1}: CONTAINER {kind} needs manual alignment")
            # container modifiers written between the block and the sizing call are on the SAME chain only if not before '}' — ignore
        if align: args += f", alignment: {align}"
        out.append(src[i:m.start()]); out.append(f".frame({args})"); i = j; n += 1
        tail = src[j:j+160]
        if re.match(r'\s*\.(flexGrow|flexShrink|flexBasis|alignSelf|margin|position|inset|alignItems|justifyContent|justifyItems|gap|width|height)\(', tail):
            flags.append(f"{fname}:{lineno}: STYLE-AFTER-FRAME {tail.strip()[:60]!r}")
    return ''.join(out), n, flags
tot = 0
for f in sys.argv[1:]:
    s = open(f).read(); t, n, fl = convert(s, f); open(f, 'w').write(t); tot += n
    for x in fl: print(x)
    print(f"# {f}: {n} frames")
print(f"# total {tot}")

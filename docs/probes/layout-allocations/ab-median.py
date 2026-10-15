import sys,re,statistics,collections
d=collections.defaultdict(list)
for l in open(sys.argv[1]):
    m=re.match(r"(\S+) (\S+) \d+ median_ms=([\d.]+)",l)
    if m: d[(m[1],m[2])].append(float(m[3]))
sc=[]
for (s,v) in d:
    if s not in sc: sc.append(s)
for s in sc:
    out=[]
    for (ss,v),xs in d.items():
        if ss==s: out.append(f"{v}: med {statistics.median(xs):.3f} [{min(xs):.3f}-{max(xs):.3f}] n={len(xs)}")
    print(s,"|"," | ".join(out))

import sys,subprocess,collections,re
path,pat=sys.argv[1],sys.argv[2]
names=open(path+".names").read().split("\n")
c=collections.Counter()
for l in open(path):
    p=l.split(); st=[names[int(x)] for x in p[1:]]
    if any(pat in s for s in st):
        i=next(i for i,s in enumerate(st) if pat in s)
        c[tuple(st[i:i+7])]+=1
uniq=sorted({s for k in c for s in k})
dm=subprocess.run(["swift","demangle","--simplified"],input="\n".join(uniq),capture_output=True,text=True).stdout.split("\n")
d=dict(zip(uniq,dm))
for k,v in c.most_common(5):
    print(v); [print("   ",d[s][:110]) for s in k]

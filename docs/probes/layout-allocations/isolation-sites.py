import sys,collections
import an
for path in sys.argv[1:]:
    roots=an.parse(path); mt=max(roots,key=lambda r:r["cnt"] if "main-thread" in r["func"] else 0)
    c=collections.Counter(); tot=mt["cnt"]
    def rec(n,stack):
        f=an.clean(n["func"])
        if f.startswith("swift_task_isCurrentExecutor") or f.startswith("pthread_main_np") or f.startswith("swift_task_getMainExecutor") or f.startswith("swift_getCurrentTaskExecutor"):
            s=n["cnt"]-sum(k["cnt"] for k in n["kids"])
            # nearest MetalUI-ish ancestor
            anc=[x for x in stack if x[1]=="Prof.base"][-1:] 
            c[(anc[0][0] if anc else "?")+"  @"+str(anc[0][2] if anc else "")]+=n["cnt"]
            return
        for k in n["kids"]: rec(k,stack+[(f,n["lib"],n["line"])])
    rec(mt,[])
    print(path,tot)
    for k,v in c.most_common(12): print("  %4.1f%% %4d %s"%(100*v/tot,v,k[:150]))

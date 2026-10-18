#!/usr/bin/env python3
"""Read-only: armor records' body lists in the running game (opens /proc/<pid>/mem for reading only)."""
import os,struct,json,collections
def game():
    for p in os.listdir("/proc"):
        if not p.isdigit(): continue
        try:
            cmd=open(f"/proc/{p}/cmdline","rb").read()
            if b"helldivers2.exe" not in cmd or not cmd.startswith(b"S:"): continue
            for line in open(f"/proc/{p}/maps"):
                if line.rstrip().endswith("/data/game/game.dll") and " 00000000 " in line: return int(p),int(line.split("-")[0],16)
        except Exception: pass
pid,base=game()
mem=open(f"/proc/{pid}/mem","rb",buffering=0)
def rd(a,n): mem.seek(a); return mem.read(n)
u32=lambda a: struct.unpack("<I",rd(a,4))[0]
u64=lambda a: struct.unpack("<Q",rd(a,8))[0]
armors=json.load(open(os.path.expanduser("~/hd2-passive-picker/data/armors.json")))
cat=u64(base+0x33264F8); first=u64(cat); n=u32(cat+8)
print("catalog",hex(cat),"kits",n)
hist=collections.Counter(); samples={}
for i in range(n):
    at=u64(first+i*8); item=u32(at)
    a=armors.get(str(item))
    if not a: continue
    lst,cnt,z=u64(at+48),u32(at+56),u32(at+60)
    bodies=[]
    for b in range(cnt):
        h=rd(lst+b*24,24); typ,_,pp,pc,z2=struct.unpack("<IIQII",h)
        ps=[struct.unpack("<III",rd(pp+k*96+8,12)) for k in range(pc)]
        bodies.append((typ,ps,z2))
    ws=[w for _,ps,_ in bodies for (s,k,w) in ps if k==0 and w<=2]
    cls=ws[0] if ws and all(w==ws[0] for w in ws) else "mixed"
    hist[cls]+=1
    samples.setdefault(cls,[]).append((a["n"],cnt,z,[(t,z2," ".join(f"{s}.{k}.{w}" for s,k,w in ps)) for t,ps,z2 in bodies]))
print(dict(hist))
for c,l in samples.items():
    print("==",c)
    for s in l[:4]: print("  ",s)

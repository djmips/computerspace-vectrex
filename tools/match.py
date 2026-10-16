import os
import pathlib
import re
from analyse import load
RTL = pathlib.Path(os.environ.get("CS_RTL", pathlib.Path(__file__).resolve().parents[2] / "computerspace" / "rtl"))
src=open(RTL / "rocket_diode_images.vhd",encoding="latin-1").read()
bases=[]
for k in range(4):
    blk=src[src.index(f"rocket_image_{k} : rocket_image"):]
    bases.append(re.findall(r'\("([01]{16})"\)',blk)[:16])
def pts(rows): return {(r,c) for r,row in enumerate(rows) for c,ch in enumerate(row) if ch=="1"}
def transforms(s):
    out={}
    for tr in range(2):
        for fr in range(2):
            for fc in range(2):
                t=set()
                for r,c in s:
                    rr,cc=(c,r) if tr else (r,c)
                    t.add((15-rr if fr else rr, 15-cc if fc else cc))
                out[(tr,fr,fc)]=t
    return out
CANDS=[((k,)+key,t) for k,b in enumerate(bases) for key,t in transforms(pts(b)).items()]
def best(s):
    """s: set of (row,col) screen points; try all translations."""
    res=[]
    for key,t in CANDS:
        bestd=None
        for oy in range(-20,20):
            for ox in range(-20,20):
                pass
        # align by trying offsets that map some point of t onto some point of s
        offs={(sy-ty,sx-tx) for (sy,sx) in s for (ty,tx) in t}
        for oy,ox in offs:
            tt={(y+oy,x+ox) for y,x in t}
            d=len(tt ^ s)
            if bestd is None or d<bestd[0]: bestd=(d,oy,ox)
        res.append((bestd[0],key,bestd[1],bestd[2]))
    res.sort()
    return res[:2]
def stable_images(frames, x_lo, x_hi, until_ms):
    seq=[];prev=None;stable=0
    for fno,ms,L in frames:
        if ms>until_ms: break
        p=[(y-255 if y>200 else y, x) for x,y in L["obj"] if x_lo<=x<=x_hi and (y<40 or y>200)]
        if not p: continue
        sh=frozenset(p)
        stable = stable+1 if sh==prev else 0
        if stable==2 and (not seq or seq[-1][1]!=sh): seq.append((fno,sh))
        prev=sh
    return seq
if __name__=="__main__":
    frames,_=load("out/scenA.txt")
    for fno,sh in stable_images(frames,95,150,3400):
        print(fno, best(set(sh)))

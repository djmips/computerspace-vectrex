"""Generate all 32 rocket headings (screen row, col) from the base images, per the simulation."""
from match import bases, pts, transforms
GROUP = [(0,1,0), (1,1,0), (1,0,0), (0,0,0)]           # transform for headings 0-3, 4-7, 8-11, 12-15
IMG   = [0,1,2,3, 3,2,1,0, 0,1,2,3, 3,2,1,0]
def heading(h):
    k = h % 16
    t = transforms(pts(bases[IMG[k]]))[GROUP[k//4]]
    if h >= 16:
        t = {(15-r, 15-c) for r,c in t}
    return t
def show(t):
    return "\n".join("".join("#" if (r,c) in t else "." for c in range(16)) for r in range(16))
if __name__ == "__main__":
    import sys
    for h in map(int, sys.argv[1:]):
        print(f"heading {h}"); print(show(heading(h))); print()

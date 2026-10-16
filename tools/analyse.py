"""Analyse a tb_spec dump: clusters of object pixels per frame.

  python analyse.py out/scenA.txt
Pixel x is game clocks since hsync minus 96 (0..255 visible); y is the line since vsync.
Layers: bit3 inversion, bit2 objects (rocket/saucer/missiles), bit1 digits, bit0 stars.
"""
import collections
import sys

X0 = 96


def load(path):
    frames = []          # (frame_no, ms, {layer: set((x,y))})
    blank = []
    cur = None
    for row in open(path):
        p = row.split()
        if not p:
            continue
        if p[0] == "F":
            cur = (int(p[1]), int(p[2]), collections.defaultdict(set))
            frames.append(cur)
        elif p[0] == "B":
            blank.append(tuple(int(v) for v in p[1:4]) + (p[4],))
        elif cur is not None:
            x, y, v = int(p[0]) - X0, int(p[1]), p[2]
            for bit, name in ((0, "inv"), (1, "obj"), (2, "dig"), (3, "star")):
                if v[bit] == "1":
                    cur[2][name].add((x, y))
    return frames, blank


def clusters(pix, gap=5):
    """Group pixels whose Chebyshev distance is <= gap."""
    pix = set(pix)
    out = []
    while pix:
        seed = pix.pop()
        group, todo = {seed}, [seed]
        while todo:
            cx, cy = todo.pop()
            near = [q for q in pix if abs(q[0] - cx) <= gap and abs(q[1] - cy) <= gap]
            for q in near:
                pix.discard(q)
                group.add(q)
                todo.append(q)
        out.append(group)
    return out


def shape(group):
    x0 = min(p[0] for p in group)
    y0 = min(p[1] for p in group)
    return x0, y0, frozenset((x - x0, y - y0) for x, y in group)


def grid(sh, w=16, h=16):
    return "\n".join("".join("#" if (x, y) in sh else "." for x in range(w)) for y in range(h))


if __name__ == "__main__":
    frames, blank = load(sys.argv[1])
    print(f"{len(frames)} frames, {frames[0][1]}..{frames[-1][1]} ms")
    for fno, ms, layers in frames[::25]:
        cl = clusters(layers["obj"])
        desc = ", ".join(f"({min(p[0] for p in g)},{min(p[1] for p in g)}) n={len(g)}" for g in sorted(cl, key=len))
        print(f"  F{fno} {ms} ms: obj {len(layers['obj'])} px in {len(cl)} clusters: {desc}; "
              f"dig {len(layers['dig'])} star {len(layers['star'])} inv {len(layers['inv'])}")

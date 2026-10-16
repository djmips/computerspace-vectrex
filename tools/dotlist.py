"""Write one object's dots as a segmented dot list for the game's draw loop.

Format (all bytes):
    label
        n, rmin, rmax, cmin, cmax  ; dots in this segment (re-anchor before it), and the rows/cols
                                   ; its dots use (rmax/cmax exclusive): a copy straddling an edge
                                   ; skips segments with no dot in the field
        dY, dX, row, col           ; n times: beam move, then the dot's grid cell
        n ...                      ; next segment
        0                          ; end of the list
The draw loop re-anchors at the start of every segment (re-zero, a move to the object's grid
corner, postab's remainder added to the segment's first move). A segment's first move is from the
corner at FIRST_SCALE; the others are from the previous dot at DOT_SCALE, a small scale whose short
ramp the draw loop hides behind its own setup (no polling). On a real Vectrex the error builds up
along a chain of relative moves, which is why chains are cut into segments. row/col let the loop
skip dots that fall outside the field when the object straddles an edge.
"""
from vxparams import FIRST_SCALE, DOT_SCALE, FLIP, units_per_px

U_FIRST = units_per_px(FIRST_SCALE)
U_DOT = units_per_px(DOT_SCALE)
ANCHOR_LIMIT = 119        # a segment's first move also carries postab's remainder (|rem| <= 8)


def emit(label, dots, every):
    """dots: ordered (row, col) floats in grid pixels. Returns (asm lines, worst error in px).

    Each move is rounded from where the beam really is after the previous rounded move, so rounding
    does not build up. Self-test: replaying the emitted moves lands every dot within half a DAC step.
    """
    lines = [label]
    worst = 0.0
    landed = []
    # segments of `every` dots, cut early where a dot-to-dot step would not fit at DOT_SCALE
    segs, cur = [], []
    for p in dots:
        if cur and (len(cur) == every or max(abs(p[0] - cur[-1][0]), abs(p[1] - cur[-1][1])) * U_DOT > 126):
            segs.append(cur)
            cur = []
        cur.append(p)
    segs.append(cur)
    s = 0
    for seg in segs:
        cells = [(min(15, max(0, int(round(r)))), min(15, max(0, int(round(c))))) for r, c in seg]
        lines.append(f"                    DB       {len(seg)}, {min(r for r, _ in cells)}, "
                     f"{max(r for r, _ in cells) + 1}, {min(c for _, c in cells)}, {max(c for _, c in cells) + 1}")
        by = bx = 0.0                                       # beam, grid pixels from the corner
        for i, (r, c) in enumerate(seg):
            u = U_FIRST if i == 0 else U_DOT
            dY = round((c - by) * u)
            dX = round((r - bx) * u)
            lim = ANCHOR_LIMIT if i == 0 else 127
            assert abs(dY) <= lim and abs(dX) <= lim, (label, s + i, dY, dX)
            by += dY / u
            bx += dX / u
            row = min(15, max(0, int(round(r))))
            col = min(15, max(0, int(round(c))))
            lines.append(f"                    DB       {dY * FLIP}, {dX * FLIP}, {row}, {col}")
            worst = max(worst, abs(by - c), abs(bx - r))
            landed.append((bx, by))
        s += len(seg)
    lines.append("                    DB       0")
    # self-test: replay the bytes
    i, k = 1, 0
    while True:
        n = int(lines[i].split("DB")[1].split(",")[0])
        i += 1
        if n == 0:
            break
        y = x = 0.0
        for j in range(n):
            dY, dX, _, _ = (int(v) for v in lines[i].split("DB")[1].split(","))
            dY, dX = dY * FLIP, dX * FLIP
            u = U_FIRST if j == 0 else U_DOT
            y += dY / u
            x += dX / u
            r, c = dots[k]
            assert abs(y - c) <= 0.5 / U_DOT + 0.5 / U_FIRST + 1e-9 and \
                   abs(x - r) <= 0.5 / U_DOT + 0.5 / U_FIRST + 1e-9, (label, k)
            k += 1
            i += 1
    assert k == len(dots)
    return lines, worst

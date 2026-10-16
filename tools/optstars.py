"""Pick stars from the original field and order them for the cheapest dot-to-dot drawing.

  python optstars.py <out.inc> <n_stars> [--half=0|1] [--snake]
Reads data/stars.txt. --half=h takes every other star of an even-spread (farthest-point) order,
for drawing the full field interlaced over two frames.
Rotated playfield: original x -> Vectrex y (up), original y -> Vectrex x.
Cost model (cycles, from the measured generated code):
  star move at scale 16: 74 (lit) ; reach 127 DAC units per axis
  blank jump at scale S in (16, 32, 64, 127): 40 + 12 (latch set/restore) + (S + 12) pad
"""
import math
import random
import sys
import pathlib
from vxparams import FLIP

RAMP_EXTRA = 3
# Square pixels: the original's 256 visible pixels fill only ~83% of a TV line (256 of 382
# game clocks, ~44 of ~52 us) while its 239 lines fill the height, so its pixels are close to
# square and the 32 rocket headings (flips and transposes of 4 images) look like true rotations.
KY, KX = 7, 7                     # DAC units per original pixel at scale 16
BASE = 16
PAD_LIT = 14                      # NOPs after the T1 write at scale 16 (hardware-confirmed)

out, n = sys.argv[1], int(sys.argv[2])
snake = "--snake" in sys.argv

DATA = pathlib.Path(__file__).resolve().parents[1] / "data" / "stars.txt"
stars = [tuple(int(v) for v in l.split()) for l in open(DATA) if l.strip() and not l.startswith("#")]
pts = [((x - 128) * KY, (y - 130) * KX) for x, y in stars]       # (vy, vx) units at scale 16

# --- farthest-point sampling in physical space (deterministic start: nearest the centre) ---
def d2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
chosen = [min(range(len(pts)), key=lambda i: d2(pts[i], (0, 0)))]
dist = [d2(p, pts[chosen[0]]) for p in pts]
while len(chosen) < min(n, len(pts)):
    i = max(range(len(pts)), key=lambda k: dist[k])
    chosen.append(i)
    for k, p in enumerate(pts):
        dist[k] = min(dist[k], d2(p, pts[i]))
sub = [pts[i] for i in chosen]
for a in sys.argv:
    if a.startswith("--half="):                 # interlace: every other star of the even-spread order
        h = int(a.split("=")[1])
        sub = [pts[i] for i in chosen[h::2]]


def scale_for(dy, dx):
    """Smallest T1 scale that reaches (dy, dx) units-at-scale-16 in one move with |DAC| <= 127."""
    # a move lasts scale + RAMP_EXTRA cycles (ramp on 11 after the T1 write, off 14 after it ends)
    m = max(abs(dy), abs(dx))
    return max(BASE // 2, min(255, math.ceil((BASE + RAMP_EXTRA) * m / 127) - RAMP_EXTRA))


def move_cost(a, b):
    sc = scale_for(b[0] - a[0], b[1] - a[1])
    return 40 + 6 + (sc + 12) + 6          # setup, latch write, wait for the ramp to end, light


def tour_cost(order):
    cur, c = (0, 0), 0
    for p in order:
        c += move_cost(cur, p)
        cur = p
    return c


# --- ordering ---
if snake:
    bands = {}
    for p in sub:
        bands.setdefault((p[1] + 130 * KX) // (16 * KX), []).append(p)
    order = []
    for b in sorted(bands):
        order += sorted(bands[b], key=lambda p: p[0], reverse=(b % 2 == 1))
else:
    left = sub[:]
    cur, order = (0, 0), []
    while left:
        j = min(range(len(left)), key=lambda k: (move_cost(cur, left[k]), d2(cur, left[k])))
        cur = left.pop(j)
        order.append(cur)
    improved = True
    while improved:                                   # 2-opt on the open path
        improved = False
        for i in range(len(order) - 1):
            for j in range(i + 2, len(order) + 1):
                new = order[:i] + order[i:j][::-1] + order[j:]
                if tour_cost(new) < tour_cost(order):
                    order, improved = new, True
print(f"{len(order)} stars, model cost {tour_cost(order)} cycles")

# --- code generation ---
# Pipelined: while a star's move ramps, the next star's scale goes into the T1 latch (the running
# timer ignores it) and its dY into A, so they cost no time of their own. The light comes at the
# same time after the T1 write as the hardware-confirmed version (write ~scale + 19 cycles after),
# never earlier.
moves = []
cur = (0.0, 0.0)
worst = 0.0
for p in order:
    dy, dx = p[0] - cur[0], p[1] - cur[1]
    sc = scale_for(dy, dx)
    k = (sc + RAMP_EXTRA) / (BASE + RAMP_EXTRA)
    jy = max(-127, min(127, round(dy / k)))
    jx = max(-127, min(127, round(dx / k)))
    moves.append((jy * FLIP, jx * FLIP, sc))
    cur = (cur[0] + jy * k, cur[1] + jx * k)     # where the beam really is (unflipped)
    worst = max(worst, abs(cur[0] - p[0]), abs(cur[1] - p[1]))

L = [f"                    lda      #{moves[0][2]}",
      "                    sta      <VIA_t1_cnt_lo",
     f"                    lda      #{moves[0][0]}"]
cycles = 8
for n, (dy, dx, sc) in enumerate(moves):
    L += ["                    sta      <VIA_port_a",
          "                    clr      <VIA_port_b",
         f"                    ldb      #{dx}",
          "                    nop",
          "                    nop",
          "                    inc      <VIA_port_b",
          "                    stb      <VIA_port_a",
          "                    clrb",
          "                    stb      <VIA_shift_reg",
          "                    clr      <VIA_t1_cnt_hi"]
    if n + 1 < len(moves):
        ny, nx, nsc = moves[n + 1]
        L += [f"                    lda      #{nsc}",
               "                    sta      <VIA_t1_cnt_lo",
              f"                    lda      #{ny}"]
    else:
        L += ["                    nop"] * 4                  # the same 8 cycles
    t_old = 2 * ((sc + 12 + 1) // 2) + 6                     # the confirmed write time
    k = max(0, -(-(t_old - 14) // 2))                        # ceil((t_old - 14) / 2)
    L += ["                    nop"] * k
    L += ["                    ldb      #$ff",
          "                    stb      <VIA_shift_reg"]
    cycles += 38 + 8 + 2 * k + 6
L += ["                    nop"] * 6                          # the last star glows like the rest
L += ["                    lda      #16",
      "                    sta      <VIA_t1_cnt_lo",
      "                    clrb",
      "                    stb      <VIA_shift_reg"]
open(out, "w").write(chr(10).join(L) + chr(10))
print(f"generated: {len(order)} moves, est {cycles} cycles, worst position error {worst:.2f} units "
      f"({worst / KX:.2f} original px)")

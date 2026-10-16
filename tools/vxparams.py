"""Drawing constants shared by the generators (postab.py, rocketgen.py; optstars.py keeps its own
star-specific scale choices but the same pixel size).

Square pixels: the original's 256 visible pixels fill only ~83% of a TV line (256 of 382 game
clocks, ~44 of ~52 us) while its 239 lines fill the height, so its pixels are close to square.
"""

BASE = 16                 # reference scale for "units"
K = 7                     # DAC units per original pixel at the reference scale, both axes
RAMP_EXTRA = 3            # a move lasts scale + 3 cycles (ramp on 11 after the T1 write, off 14 after)

MOVE_SCALE = 170          # absolute moves to an object's grid origin (reach +-144 px)
DOT_SCALE = 16            # moves between an object's dots. 8 vs 16 vs 32 looked the same on hardware;
                          # 16 keeps a re-anchored dot (up to 15 px from the grid corner) within a byte
ANCHOR_EVERY = 3          # re-anchor a dot chain every N dots: the error builds up along a chain on a
                          # real Vectrex (shape test 3, 2026-10-16: 3 looks good, 5 fine, never: skinny)


def units_per_px(scale):
    """DAC units per original pixel when moving at this scale."""
    return K * (BASE + RAMP_EXTRA) / (scale + RAMP_EXTRA)

"""Drawing constants shared by the generators (postab.py, rocketgen.py; optstars.py keeps its own
star-specific scale choices but the same pixel size).

Square pixels: the original's 256 visible pixels fill only ~83% of a TV line (256 of 382 game
clocks, ~44 of ~52 us) while its 239 lines fill the height, so its pixels are close to square.
"""

FLIP = -1                 # the field's orientation on the Vectrex: original "up" to Vectrex right
                          # (-1: the cart side up, as a 4:3 cradle holds the console) or left (1).
                          # Every generator negates the moves it emits; computerspace.asm reads
                          # FIELD_FLIP from postab.inc for its own moves.
BASE = 16                 # reference scale for "units"
K = 7                     # DAC units per original pixel at the reference scale, both axes
RAMP_EXTRA = 3            # a move lasts scale + 3 cycles (ramp on 11 after the T1 write, off 14 after)

MOVE_SCALES = (32, 64, 108, 150)   # moves from the centre to an object's grid origin: the
                                   # smallest class that reaches (time ~ scale); 150 reaches 146 px
FIRST_SCALE = 16          # a segment's first move, from the object's grid corner (up to 15 px)
DOT_SCALE = 6             # the other moves, dot to dot (reach 8.6 px; the ship needs 8.2): a short ramp the draw loop
                          # hides behind its setup. 8/16/32 looked the same on hardware.
ANCHOR_EVERY = 4          # (the ship; 3 looked good, 5 fine on hardware; 4 for the frame budget)
                          # re-anchor a dot chain every N dots: the error builds up along a chain on a
                          # real Vectrex (shape test 3, 2026-10-16: 3 looks good, 5 fine, never: skinny)


def units_per_px(scale):
    """DAC units per original pixel when moving at this scale."""
    return K * (BASE + RAMP_EXTRA) / (scale + RAMP_EXTRA)

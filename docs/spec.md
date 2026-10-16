# Computer Space: game specification for the Vectrex port

Extracted from the gate-level FPGA recreation of the original boards (Mattias G 2015, DarFPGA 2017),
in [djmips/computerspace](https://github.com/djmips/computerspace) at `rtl/`. Citations are
`file:line` into that folder. Values marked **(sim)** were measured in a GHDL simulation of the core;
**(unverified)** marks anything inferred rather than read or measured.

The original runs at 59.885 Hz (NTSC-like); the Vectrex at 50 Hz. Rates are given per second or per
original frame so they can be rescaled.

## 1. Screen

- Visible playfield **256 × 239 pixels** (sim): x = game clocks 96..351 after hsync, 239 lines with
  vblank low, 16 lines blanked. The motion counters treat the whole 256 × 255 field (including the
  blanked lines) as one wrapping space (`motion_board.vhd:319-352`).
- Everything wraps on both axes, including through the 16 blanked lines (objects can hide there).
- Frame: 382 game clocks × 255 lines at 5.8333 MHz = 59.885 Hz.

## 2. Objects and artwork

| Object | Grid | Lit points | Source |
|---|---|---|---|
| Rocket | 16 × 16 | ~15–20 dots per image, 4 base images | `rocket_diode_images.vhd:64-142` |
| Rocket flame | 1–2 extra dots | when thrusting, pulsing | `rocket_diode_images.vhd:157-178` |
| Saucer | 16 × 8, shown twice | 18 dots + "rotating light" dots in column 4 | `saucer_diode_image.vhd:55-91` |
| Rocket missile | 1 × 1 | 1 | `motion_board.vhd:446-497` |
| Saucer missile | 1 × 1 | 1 | `motion_board.vhd:1425-1472` |

- The objects are sparse dot patterns, not filled sprites.
- **32 rocket headings** (~11.25° apart) are made from the 4 base images by reading them forwards or
  backwards on each axis and optionally swapping the axes (`memory_board.vhd:356-433`, table of all 32).
- Rule confirmed against 18 simulated headings (screen rows/cols, with the table's `"…"` rows as
  rows): for heading h, k = h mod 16, image = [0,1,2,3, 3,2,1,0, 0,1,2,3, 3,2,1,0][k], transform for
  k = 0-3: flip rows; 4-7: transpose then flip rows; 8-11: transpose; 12-15: none. Headings 16-31 are
  headings 0-15 rotated 180° (flip rows and columns). In 8 of 18 headings the dot on the grid's bottom
  row appears one pixel right of the table position (sim): ignore.
- **Two saucers** are one motion counter displayed twice: the enable decode leaves out the top
  vertical bit, so a second copy appears 128 lines away (`motion_board.vhd:1069-1070`).

## 3. Rocket

### Rotation
- One heading step per pulse of the thrust/rotate clock while a rotate button is held.
- The clock: `clocks.vhd:86-99` toggles every 2,777,779 cycles of 50 MHz, a 9 Hz square wave.
- **Measured (sim): one heading step every 6.67 frames = 9.0 steps/s**, a full turn in 3.56 s.
- **Open question:** the clock's comment says "18 Hz, measured 18.2 Hz at real Memory Board"
  (`clocks.vhd:83-84`). If that figure is the real board's rotation clock, the core turns at half the
  original speed. Keep the rate one constant in the port and check against footage of a real cabinet.
- Heading 0 points up (about 3° right of north), heading 8 east, 16 down, 24 west; clockwise
  increases the heading (sim).

### Thrust and velocity
- Velocity is held per axis as a signed level −7..+7 (74193 up/down counters,
  `memory_board.vhd:1293-1334` horizontal, `:1493-` vertical). No friction, no drift.
- While thrust is held, each thrust/rotate clock pulse (`memory_board.vhd:1281`) changes each axis by
  one level toward the heading's sign on that axis, clamped at ±7 (`:1368-1449`):
  - horizontal: +1 (right) when heading is in 0–180°, −1 (left) in 180–360°; **no change within two
    headings of due north or south** (`:1469-1490`);
  - vertical: likewise from up/down, with no change within two headings of due east or west.
- Thrust uses only the *sign* of each component, not cos/sin.
- Screen speed: at most 1 pixel per original frame per axis. The 3-bit level selects pulse trains
  derived from the frame rate (nominally 15, 7.5 and 3.75 Hz) and the rocket moves one pixel on
  frames where the OR of the selected trains is active (`motion_board.vhd:716-735`, `:861-907`).
- **Speed per level** (from the divider chain `motion_board.vhd:881-960` and the bit mapping
  `computer_space_logic.vhd:257-263`): bit 2 moves on 1 frame in 4, bit 1 on 1 frame in 8, bit 0 on
  1 frame in 16, and bit 0's frames are a subset of bit 1's. So levels 0..7 move
  **0, 1, 2, 2, 4, 5, 6, 6 pixels per 16 frames**; top speed 6/16 px/frame = 22.5 px/s. The sim
  measured 2/16 (7.5 px/s) after about three thrust pulses, consistent with level 2 or 3.
- Thrust/flame pulses come at the same 9 per second as rotation (sim: 0.3 s of thrust from rest
  pointing south gave a straight downward drift, no horizontal motion).

### Rocket missile
- One missile at a time; fire is ignored while one is in flight. Lifetime 2.3 s
  (`clocks.vhd:172`; the timer process is at `motion_board.vhd:542-557`).
- Direction: 16 directions, recomputed **every frame from the rocket's current heading**, which is
  what makes the missile steerable (`memory_board.vhd:1706-1828`):
  - within one heading of N/S/E/W: straight, 1 px/frame on that axis;
  - within one heading of the diagonals: 1 px/frame on both axes;
  - in between (~22.5° and ~67.5° off an axis): 1 px/frame on the major axis, 1 px every second frame
    on the minor axis.
- The missile's speed does not include the rocket's velocity.

## 4. Saucers

- Each axis either moves 1 px every second frame (30 px/s) or is still (`motion_board.vhd:970-986`,
  `:1108-1120`). So 8 directions or stopped, at 30 px/s per moving axis.
- A new direction is latched once per saucer cycle from bits of the saucer's own position counter,
  effectively pseudo-random (`motion_board.vhd:1123-1148`).
- Saucer cycle: 2.3 s, then a 0.2 s hold, repeating (`motion_board.vhd:1156-1175`, `clocks.vhd:178-188`).
  The missile launches at the start of the cycle and the direction change follows a moment later
  (`:1182-1212`).

### Saucer missile
- Launched once per cycle from the saucer whose counter rolls over (`motion_board.vhd:1293-1303`).
- **Aimed once at launch, then straight** (not homing). For each axis: if the rocket is within
  32 pixels of the saucer on that axis, no motion on that axis; otherwise 1 px/frame toward the rocket
  (`motion_board.vhd:1215-1403`, `:1452-1464`). If within 32 pixels on both axes the missile stands
  still: a "mine".
- 60 px/s per moving axis, lifetime 2.3 s.

## 5. Collisions and explosions

- Three hit tests, all **box overlaps**: the objects' display enables, which cover the whole 16×16
  rocket grid and each 16×8 saucer grid, not just the lit dots (`sync_star_board.vhd:596-662`):
  - rocket missile (1 px) in a saucer box: rocket scores (`:661`, `:735-755`);
  - saucer missile (1 px) in the rocket box: saucer scores (`:660`, `:771-793`);
  - rocket box overlapping a saucer box: collision (`:662`, `:698-719`).
- Rocket missile vs rocket and saucer missile vs saucer are not tested.
- After a hit, a timer counts explosion-clock periods (6 Hz, `clocks.vhd:107-120`) and clears all
  flags after about 7 periods, ~1.2 s (`sync_star_board.vhd:817-921`). During the event the hit
  object is hidden (rocket: `c5_8`; saucer: `b6_1`, `:614-667`), and the rocket spins when hit by a
  missile (`SB_M`, `:798`).
- Screen flash (whole-picture inversion) and explosion sound: the first explosion-clock period of
  the event, ~1/6 s (`sync_star_board.vhd:927-941`).

## 6. Game flow

- Start is accepted only with a coin credited and no game running (`sync_star_board.vhd:1372-1378`);
  it clears both scores and the timer (`:1450`). One coin, one game: extra coins are not counted
  (the coin latch, `:1238-1285`). With the 2-plays switch a coin lasts two games (`:1290-1303`).
- After start the rocket stays hidden about 1.15 s (sim: game on at 180 ms, rocket visible from
  ~1333 ms).
- Start positions (sim, game pixels, grid top-left): rocket at x 114, y -3 (straddling the vertical
  wrap, mostly in the blanked lines), heading 0 (up); saucers at x ~165, y 5 and y 132.
- The game ends when the timer rolls over from 99 to 00, about 100 s after start (`:1393`, `:1427-1442`).
- Hyperspace (replay): at that rollover, if the replay switch is on, the rocket's score is higher
  than the saucers' (`:1196-1230`) and the game is not already in replay (`:1385`), the game goes on
  for another 100 s with the whole picture inverted (`:942`). Scores are not reset; the next rollover
  ends it.

## 7. Score and timer

- Four 7-segment digits in an 8 × 16 cell, strokes 2 pixels thick, in one column at the right edge
  (sim): rocket score at x 240, y 91; saucer score at x 240, y 123; game time tens at x 224 and units
  at x 240, y 155. Steady (no blinking) during play.
- Rocket score counter is binary (shows odd glyphs past 9), saucer score and time are decimal
  (`sync_star_board.vhd:1012-1050`). Time advances once per second while a game is on
  (`sync_star_board.vhd:948-955`, `clocks.vhd:147-160`).

## 8. Stars

- A fixed field of ~370 single-pixel stars over the whole playfield (sim: 375 visible pixels in 370
  clusters, almost all 1 px). Positions can be taken from the simulation dump.

## 9. Drawing inventory and Vectrex frame budget

Per frame in the original: stars ~370 dots; rocket 15 dots (+1-2 flame); saucers 2 × ~20 dots;
missiles 2 dots; digits 4 glyphs (≤ 28 strokes).

Measured on the Vectrex (vecx-run `--track auto`, budget 30,000 cycles at 50 Hz): the BIOS `Dot_List`
costs **~197 cycles per dot** almost regardless of scale (375 stars: 74,032 cycles at scale 16 and 32,
79,352 at scale 64), so it is out for the stars. A custom dot loop should approach 50-60 cycles a dot
(unverified estimate): even then 370 stars would take ~20,000 cycles. The star count, or how the
field is drawn, is a design decision.

Measured, generated straight-line code (one block per star: set Y and X, blank via the shift
register, start T1 at scale 16, wait, then load $FF so the shift register holds the beam on at the
star while the next move is set up; blank moves where a jump exceeds one move's reach):
- The light must wait until the move has really ended: the integrators keep moving ~14 cycles after
  T1 expires (ramp-off delay), so lighting 12 cycles after the T1 write gave streaks. Lighting
  ~28-30 cycles after the write gives clean dots: confirmed on a real Vectrex (2026-10-16, 14 NOPs
  after the T1 write: clean dots, no tails; the field wavers slightly at ~42 fps with 474 chained moves).
- All 375 stars: 474 moves (99 blank fillers), **33,958 cycles** (~71 cycles per move).
- `CLR` on the shift register vs `CLRB`/`STB`: no visible difference in vecx-run.
- **A move lasts scale + 3 cycles** (ramp on 11 cycles after the T1 write, off 14 after T1 ends), so
  the distance is DAC × (scale + 3). With one scale everywhere this only enlarges the picture; with
  per-move scales it must be modelled, or short low-scale moves overshoot (37% at scale 8) and the
  errors accumulate along a chain. Applies to all game drawing, not just stars.
- Per-move scale (just enough to reach the next star), wait (scale + 12) cycles before lighting, and
  an order optimised for cycles (nearest neighbour + 2-opt): 135 stars ~11,250 cycles, 188 stars
  ~14,550; tracking where each move really lands keeps the worst position error under 0.2 original
  pixels.
- Not tried yet: lighting more than one star per move with a shift-register pattern.

## 10. Vectrex design notes (not part of the original)

Decided (2026-10-16):
- **Playfield rotated 90°** to fill the portrait screen: the 4:3 field becomes 3:4, matching the
  Vectrex. Original x maps to Vectrex vertical, original y to Vectrex horizontal (direction of the
  mapping still to choose); the score/timer column becomes a row.
- **Stars: the full original field, interlaced and dimmed** (revised 2026-10-16 after a hardware
  comparison). The 375 visible stars are split into two halves of ~188, each spread over the whole
  field (alternate entries of a farthest-point ordering), drawn on alternate frames: each star
  refreshes at 25 Hz, everything else at 50 Hz. On a real Vectrex this "flickers a bit but looks
  better, especially when dimmer" than a 135-star subset drawn every frame (which also looked too
  regular). Measured: ~14,550 cycles per half (generated code, per-move scale, optimised order).
- Star intensity **$2F** (hardware, 2026-10-16: $5F less three $10 steps looked best; $1F flickers least but is a
  little dim, worth another try later);
  objects at $7F. The original mixes stars at about half level.

- Whole-screen inversion (explosion flash, hyperspace) has no vector equivalent: substitute a
  brightness flash, a border, or a starfield change.
- Collision boxes translate directly to rectangle tests in game coordinates.
- Rescaling 59.885 Hz to 50 Hz: move by accumulated sub-pixel steps rather than skipping frames.

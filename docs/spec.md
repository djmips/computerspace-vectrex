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
- **No calibration screen, ever.** Cart in, power on, Computer Space: nothing for the player to set
  up, as on the original. So the picture must look right on any console without per-console values:
  re-anchoring dot chains is the method, not Kristof Tuts' zero-reference calibration (which needs a
  value set by eye per console and scale, a BUZZ/NO BUZZ interval, and somewhere to save it).
  Speed comes from pipelining the
  draw code (small scales, setup overlapped with the ramp, no polling), with a timing margin.
- **Playfield rotated 90°**, clockwise: original "up" is the Vectrex's right, the cartridge side, so
  the picture is upright with the console on its side in a 4:3 cradle (which holds it cart side up;
  changed 2026-10-16, it was anticlockwise). Original x -> Vectrex down, original y -> Vectrex left.
  One sign, `FLIP` in `tools/vxparams.py` (`FIELD_FLIP` in postab.inc for the hand-written digit
  sweeps), turns it back. The score/timer column becomes a row.
- **Square pixels** (corrected 2026-10-16). The original's field is *not* 4:3: its 256 visible
  pixels fill only ~83% of a TV line (256 of 382 game clocks, ~44 of ~52 us) while its 239 lines fill
  the height, so its pixels are close to square. An 8:7 mapping (assuming 4:3) visibly distorted the
  rotating ship on hardware. Now 7 DAC units per pixel at scale 16 on both axes: the field is about
  239 x 256, full width and ~80% of the Vectrex screen height.
- **The 16 blanked lines are dropped**: the wrap space is 256 x 239, all visible; nothing can hide
  in an invisible band.
- **Objects crossing an edge** are drawn once per copy (up to four at a corner), lighting only the
  dots that fall inside the field.
- **Pre-rotated ship.** The core's 32 headings (flips/transposes of 4 base images) have uneven
  proportions (length/width 1.19-1.34) and uneven angle steps (7-22 degrees): fine on the original's
  soft TV, plainly wrong on the Vectrex. The ship is the core's heading-0 image rotated about its
  centroid to exactly 5.625 + 11.25 h degrees (`tools/rocketgen.py`; `--diode` gives the core's own
  images). Length/width is now 1.24 at every heading.
- **Dot chains must re-anchor on hardware.** A ship drawn as one chain of 15 relative dot moves went
  skinny at the diagonals on a real Vectrex (fine in vecx-run); the dot scale (8/16/32) and a longer Y
  sample/hold settle made no difference; drawing each dot from a freshly zeroed beam fixed it (shape
  test). The error builds up along a chain. Re-zeroing (Reset0Ref + move to
  the grid corner) every 3 dots looks good, every 5 is acceptable; ~430 cycles per re-anchor.
  Ship dots move at scale 16 (`tools/vxparams.py`: DOT_SCALE, ANCHOR_EVERY).
- **Saucers re-anchor too, every 5 dots** (hardware, 2026-10-16). They don't rotate, but without
  re-anchoring a saucer visibly changes shape as it moves around the screen (the error depends on
  screen position too, worst for the left/top saucer); with re-anchoring it barely does.
  **Reserve, use with care:** saucers without re-anchoring save ~2,300 cycles a frame and looked
  acceptable on a decent console, but a worse Vectrex will distort more. Only fall back to it if the
  frame budget forces it, and test on more than one console first.
- **Re-anchor cost** after optimisation: inline zero + move from the centre at the smallest of four
  scales that reaches the object (32/64/108/150, `tools/postab.py`): ~150-300 cycles, by distance.
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

## 11. The Vectrex implementation (2026-10-16)

### Game flow and controls
- Power on: BIOS title "COMPUTER SPACE", then attract mode: the saucers fly, no rocket, no missiles,
  no sound; the digits show the last scores and time. For 3 s after a game the buttons are ignored
  (the final score stays up). Then **any button** starts a game (the Vectrex has
  no coin slot: coin and Start in one press). Replay (hyperspace) is always on (the operator switch).
- Buttons as on the cabinet's control panel, left to right (Fire Missile, Thrust, Rotate, Rotate): 1 fire, 2 thrust,
  3 rotate anticlockwise, 4 rotate clockwise (holding fire refires when the missile expires, as on
  the original).
- The rocket's state (position, heading, velocity) is never reset, as on the original (no reset on
  its motion or memory boards): each game picks it up where the last one left it. The first game
  after power-on rolls it at random, as the original's counters power up, seeded by the frame
  count at the first press.
- A game: the rocket appears 58 frames (~1.15 s) after start; time counts 0..99 once a second; at the
  roll-over the game ends, or once goes on in hyperspace if the rocket's score is higher.

### Rules as implemented (`game.asm`)
- Rocket missile: launched near the rocket's centre, 16 directions from the current heading every
  frame (`tools/tables.py`), 2.3 s.
- Saucer missile: launched from the first saucer copy at the start of each 2.5 s saucer cycle, aimed
  once per axis (still within 32 px), 60 px/s per axis, 2.3 s. Not in attract mode or while the
  saucers are hidden.
- Collisions are box tests with wrap: rocket missile in either saucer box (16x8) scores for the
  rocket (0..99; the original: 4-bit binary); saucer missile in the rocket box (16x16) scores for the
  saucers (0..99; the original: 0..9); rocket and saucer boxes overlapping: no score. One event at a time, 58 frames:
  saucer hit -> saucer hidden; rocket hit -> spins (heading +5 of 32 per frame, ~7.8 turns/s) for 33 frames, then hidden;
  collision -> both hidden. Frames 8..15 of an event are the flash.
- Death spin: the core clocks the heading counter from the 340 kHz explosion clock while spinning
  (`memory_board.vhd:950`, `clocks.vhd:121-139`, ~170,000 steps/s), so the heading changes many times
  while one frame of the ship is drawn: a fast blur. Here: 5 headings of 32 per frame (was 1, too
  slow on hardware), `SPIN_STEP` in `game.asm`.
- Flash and hyperspace: a vector display cannot invert the picture; the stars brighten instead
  ($7F in the flash, $5F in hyperspace, $2F normally).

### Display
- Score and time: 7-segment glyphs from the original 7448 table (`tools/digits.py`), 2-px strokes,
  **rotated with the field** (they read with the Vectrex on its side), at the original's places
  (rows 91/123/155; tens at column 224, units at 240). **Two digits each** (a departure: the original
  shows one digit per score); a score's tens is hidden while 0, the time always shows both. Scores
  count 0..99 (the original: rocket 4-bit binary, saucer 0..9).
- Drawn as raster sweeps **along the original's raster direction** (along the console's long axis), one sweep per glyph
  row through the tens and the units, alternate rows on alternate frames. One shift-register byte per
  glyph: a blank slot, then columns 0-6; the register's hold draws column 7 (always equal to 6). The
  writes are **18 cycles apart** (+11 tens, +29 off, +47 units, +65 off), as in the BIOS text printer.
  The sweep runs 16 px per 36 cycles (DAC 59), so a glyph is ~7 px wide and the units sit 16 px after
  the tens. Each sweep comes back at the same rate for the same time (the ramp delays cancel on any
  console) and steps to the next row on the way (DAC 5 over 55 cycles: 2.07 px; units only: DAC 14
  over 19 cycles: 2 px). One re-anchor per number, the 12 anchors looked up at power-on.
- History (2026-10-16, hardware): the first two versions (glyph columns as 16-px sweeps, two bytes
  written **16 cycles apart**) lost the bottom stroke on a real Vectrex but not in vecx-run: a write
  while the 6522 is still shifting the previous byte cuts that byte short (the count carries on), so
  only the first bit or two of the second byte came out. Delaying the beam-off write changed nothing
  (seen on the console). Confirmed on hardware with the 18-cycle row
  sweeps: the 0 closes. The first version also slanted (its column
  return was a separate move tuned in vecx-run) and read the wrong way for a Vectrex on its side.
- Frame cost: the digits take ~2,300 cycles more than the long-sweep version (24 short sweeps, each
  with its return): vecx-run 2 min, 30,000 cycles average, 76% of frames over, 48.2 fps.
- Engine flame: one dot behind the tail while thrusting, side to side with the 9 Hz thrust clock
  (`rocket_flame`), not drawn on a copy straddling an edge.
- Stars: **350 of the 375** (175 per frame), see the budget below.

### Sound (`sound.asm`, PSG)
- A: rocket missile tone (966/947/957 Hz, averaging 957 Hz; the core: missile position counter bit 11, 15,270 lines/s / 16 = 954 Hz; volume 9) while it flies, else turn beeps (1,913 Hz; the core: saucer counter bit 10, 1,909 Hz) while rotating,
  beeping at 9 Hz (on for the high half of the rotate clock, as the original gates it with
  `thrust_and_rotate_clk`, `memory_board.vhd:968-969`);
  B: saucer missile tone (3,906/3,750/3,750 Hz, averaging 3,802 Hz; the core: counter bit 9, line rate / 4 = 3,818 Hz; confirmed by ear
  against the DE1 and a video of a cabinet; volume 8); C: noise: the background drone through a game (the core's ambiance voice; volume 6, ~10 dB under the thrust), thrust (louder, brighter), explosion
  as the core's (`computer_space_sound.vhd:320-400`): 0.38 s held, then a
  2.84 s linear fade (a per-frame volume table), tone C at a random 84-156 Hz each frame chopping the
  lowest noise (the AY ANDs them) for the rumble; restarted per hit (was one 1 s PSG envelope decay,
  which sounded like a gunshot on hardware). Silent outside a game.
- The tones step through three periods, one at each of three points a frame (frame start, after the
  stars, after the saucers; the PSG can only be written between drawing stages): a stand-in for the
  core's rough tone, whose position counters stop in vertical blanking and jump phase every frame
  (the turn beeps: 1,953/1,913/1,875 Hz).
- Not verified by ear (vecx-run cannot capture the PSG): register writes checked only.

### Frame budget (vecx-run, 2 min of random play)
- ~27,700 cycles per frame on average (budget 30,000), ~11% of frames over (8-minute soak: 27,800,
  17%), mostly when objects straddle a seam (extra copies); then the game runs that frame slow.
  49.6 fps (was 49.2 with the BIOS frame wait: 29,100 average, 21% over).
- Per stage (averages): frame wait ~100, logic + sound ~1,800, stars ~12,300, rocket ~3,500,
  saucers ~5,000, missiles ~1,000, digits ~4,000.
- Frame wait: Alex Herbert's FRWAIT from Protector (`frame_wait`), not the BIOS Wait_Recal.
  Wait_Recal restarts timer 2 and then recalibrates (~900 cycles) in the new frame's time; FRWAIT
  recalibrates in the old frame's spare time (zero, then the ramp held open with the DAC at $40,
  flipped every 31 cycles, until timer 2 runs out) and skips it when the frame ran over. Its
  side effect: the stars' `Moveto_d(0,0)` no longer runs at Recalibrate's $FF scale (~250 cycles).
  The re-anchors zero as its ZERGND does (one 16-bit write of port B and the DAC, two `dec`s:
  ~8 cycles less each). Considered and dropped: carrying an overrun into the next frame's timer
  (frames would average 50 Hz but vary in length, so in brightness).
- On hardware (2026-10-16): the stars and score text are slightly more jittery than with Wait_Recal;
  kept for the frame time. Likely causes: the recalibration varies with the spare time (none on a
  frame that ran over), and the re-anchor's zero hold is ~7 cycles shorter (still longer than
  ZERGND's own). If it needs fixing: a fixed short recalibration every frame, or the longer zero.
- Draw method: dot chains in segments, each re-anchored (zero + one move from the centre at the
  smallest of four scales that reaches); a pipelined dot loop (chain moves at scale 6, the next move
  prepared during the ramp, no polling, lit scale + 17 + 4 cycles after the start); straddling copies
  skip segments with no dot in the field; star code generated straight-line and pipelined.
- **Compromises made for the budget (all one setting each; check on hardware):**
  - the ship re-anchors every **4** dots (hardware: 3 good, 5 fine) - `tools/vxparams.py` ANCHOR_EVERY;
  - saucers in segments of **6** dots (hardware-tested: 5) - `saucergen.py --anchor`;
  - the saucer light as **one dot per 2-px dash** (4, not 8) - `saucergen.py --light-full` for both;
  - **350** stars - `optstars.py ... 350`.
  Undoing all four costs roughly 2,500 cycles a frame.

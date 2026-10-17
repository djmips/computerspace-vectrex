;***************************************************************************
; Computer Space (Nutting Associates, 1971) for the Vectrex
;
; Single-bank 32K cartridge. Built with VIDE's assembler (Asmj) through the
; vecx-run kit: see build.ps1. Game rules: docs/spec.md.
;
; Coordinates are the original's: x right 0..255, y down 0..238 (the 16
; blanked lines of the original are dropped). The playfield is drawn rotated
; 90 degrees: original x -> Vectrex Y, original y -> Vectrex X.
;
; DP stays $D0 for the whole frame; RAM is addressed extended.
;***************************************************************************

                    INCLUDE  "VECTREX.I"

FIELD_H             equ      239                    ; field rows (original y)
STAR_INTENSITY      equ      $2F                    ; chosen on hardware; $1F flickers least
FLASH_INTENSITY     equ      $7F                    ; explosion flash: the original inverts the picture
OBJ_INTENSITY       equ      $7F
; DOT_SCALE and MOVE_SCALE come from postab.inc (tools/vxparams.py)

; Rotate/thrust clock: the core steps 9 times a second (clocks.vhd:86-99; its
; comment says 18 Hz on a real board - open question, docs/spec.md 3).
; Phase accumulator per 50 Hz frame: 9 * 256 / 50 = 46.
ROT_RATE            equ      46

; Saucers (docs/spec.md 4): each axis still or 30 px/s; a new direction
; every 2.5 s; two copies 127 rows apart (one counter shown twice).
SAUCER_SPEED        equ      153                    ; 1/256 px per 50 Hz frame (29.94 px/s)
SAUCER_CYCLE        equ      125                    ; frames between direction changes
SAUCER_GAP          equ      127                    ; rows between the two copies

; Controller buttons (Vec_Btn_State, stick 1), laid out like the cabinet panel
; (left to right: Fire Missile, Thrust, Rotate anticlockwise, Rotate clockwise)
BTN_FIRE            equ      $01                    ; button 1: fire
BTN_THRUST          equ      $02                    ; button 2: thrust
BTN_CCW             equ      $04                    ; button 3: rotate anticlockwise
BTN_CW              equ      $08                    ; button 4: rotate clockwise

;***************************************************************************
; RAM
;***************************************************************************
                    BSS
                    ORG      $c880

frame_count         ds       1

; rocket
rk_x                ds       2                      ; grid origin column, 8.8 fixed point
rk_y                ds       2                      ; grid origin row, 8.8 fixed point
rk_heading          ds       1                      ; 0..31, 0 = up, clockwise
rk_vx               ds       1                      ; velocity level -7..7 (+ = right)
rk_vy               ds       1                      ; velocity level -7..7 (+ = down)
rot_acc             ds       1                      ; rotate/thrust clock phase

; saucers
sc_x                ds       2                      ; grid origin column, 8.8
sc_y                ds       2                      ; grid origin row, 8.8 (the first copy)
sc_dx               ds       1                      ; -1, 0, +1
sc_dy               ds       1
sc_timer            ds       1                      ; frames to the next direction change
rng                 ds       1                      ; 8-bit LFSR state, never 0
rk_cold             ds       1                      ; 1 until the first game rolls the rocket

; game (game.asm)
game_on             ds       1                      ; 0: attract mode
hyper               ds       1                      ; 1: hyperspace (the replay round)
hy_flash            ds       1                      ; frames left of the flash burst that starts it
over_lock           ds       1                      ; frames the buttons stay locked after a game
wob_i               ds       1                      ; sound: which of the three pitch steps
snd_a               ds       1                      ; sound: channel A plays 0 nothing, 1 missile, 2 turn
boom_i              ds       1                      ; explosion sound: frame into it, BOOM_LEN = none
boom_rng            ds       1                      ; its own random rumble period
score_rk            ds       1                      ; rocket score, 0..99
score_sc            ds       1                      ; saucer score, 0..99
tm_units            ds       1                      ; game time, two decimal digits
tm_tens             ds       1
sec_acc             ds       1                      ; frames into the current second
rk_hide             ds       1                      ; frames until the rocket appears
ev_timer            ds       1                      ; frames left in the explosion event, 0 = none
ev_kind             ds       1                      ; EV_* bits
rm_on               ds       1                      ; rocket missile
rm_x                ds       2
rm_y                ds       2
rm_life             ds       1
sm_on               ds       1                      ; saucer missile
sm_x                ds       2
sm_y                ds       2
sm_dx               ds       1                      ; -1, 0, +1
sm_dy               ds       1
sm_life             ds       1
co_sy               ds       1                      ; collision scratch: a saucer copy's row
star_int            ds       1                      ; this frame's star intensity
dg_par              ds       1                      ; digits: this frame's row parity
dg_k                ds       1                      ; this number's anchor block: 0, 20, 40
dg_tens             ds       1                      ; this number's tens, $FF = not shown
dg_p1               ds       2                      ; this frame's first row of the tens glyph
dg_p2               ds       2                      ; and of the units glyph
dg_cols             ds       1                      ; sweeps left in this number
dg_t1               ds       1                      ; this number's sweep time (T1)
dg_anchors          ds       60                     ; 12 anchors as pos_lookup left them (dacy, dacx,
                                                    ; remy0, remx0, mscale): number 0-2, parity 0-1,
                                                    ; from the tens / from the units

; object drawing (draw_object / draw_copy)
d_list              ds       2                      ; dot chain: count, then (dY, dX, row, col)
d_px                ds       1                      ; grid origin column 0..255
d_py                ds       1                      ; grid origin row 0..238
d_w                 ds       1                      ; grid width (cols)
d_h                 ds       1                      ; grid height (rows)
d_gx                ds       2                      ; this copy's origin column, signed
d_gy                ds       2                      ; this copy's origin row, signed
d_cmin              ds       1                      ; visible cols [cmin, cmax) of this copy
d_cmax              ds       1
d_rmin              ds       1                      ; visible rows [rmin, rmax)
d_rmax              ds       1
d_cmax_main         ds       1
d_rmax_main         ds       1
d_remy              ds       1                      ; postab remainder for the first dot
d_remx              ds       1
d_count             ds       1
d_tmp               ds       1
d_dacy              ds       1                      ; this copy's corner: Moveto values
d_dacx              ds       1
d_remy0             ds       1                      ; and remainders, re-applied at each anchor
d_remx0             ds       1
d_clip              ds       1                      ; 0: the whole copy is in the field
d_mscale            ds       1                      ; this copy's move scale (postab class)
d_flame             ds       2                      ; 0, or a flame move to add after the last dot

;***************************************************************************
; Cartridge header
;***************************************************************************
                    CODE
                    ORG      0

                    DB       "g GCE 2026", $80      ; 'g' is the copyright sign
                    DW       music1                 ; BIOS tune for the title screen
                    DB       $F8, $50, $20, -$56    ; title: height, width, rel y, rel x
                    DB       "COMPUTER SPACE", $80
                    DB       0                      ; end of header

;***************************************************************************
; Start
;***************************************************************************
start
                    clr      frame_count
                    clr      rk_heading
                    clr      rk_vx
                    clr      rk_vy
                    clr      rot_acc
                    ldd      #120*256               ; mid-field until the first game rolls
                    std      rk_x                   ; the rocket's power-up state (game_start)
                    ldd      #112*256
                    std      rk_y
                    lda      #1
                    sta      rk_cold
                    ldd      #150*256               ; saucers start near the top, moving right
                    std      sc_x
                    ldd      #5*256
                    std      sc_y
                    lda      #1
                    sta      sc_dx
                    clr      sc_dy
                    lda      #SAUCER_CYCLE
                    sta      sc_timer
                    lda      #$5A
                    sta      rng
                    clr      d_flame                ; no flame until the rocket sets one
                    clr      d_flame+1
                    jsr      game_init
                    jsr      digits_init
                    jsr      sound_init

;***************************************************************************
;***************************************************************************
; Frame loop
;***************************************************************************
main
                    jsr      frame_wait             ; exits with DP = $D0
t_logic             jsr      sound_update           ; first: the PSG shares the VIA ports with the beam
                    inc      frame_count
                    jsr      Read_Btns              ; Vec_Btn_State: held buttons
                    tst      game_on
                    beq      no_rocket_ctl
                    jsr      rocket_update
no_rocket_ctl       jsr      saucer_update
                    jsr      game_update
                    ; stars: brighter in a flash (explosion, hyperspace start); bright stars
                    ; show the interlace as flicker, so only briefly
                    lda      #STAR_INTENSITY
                    sta      star_int
                    jsr      flash_on
                    beq      si_flash
                    lda      #FLASH_INTENSITY
                    sta      star_int
si_flash

t_frame_start       jsr      draw_stars             ; (t_* labels: frame-time profiling points)
t_stars_done        jsr      sound_wobble           ; (between drawing stages only)

                    lda      #OBJ_INTENSITY
                    jsr      Intensity_a
                    jsr      rocket_visible
                    beq      no_rocket
                    ldb      rk_heading
                    aslb
                    ldx      #rocket_tab
                    ldx      b,x
                    stx      d_list
                    lda      rk_x
                    sta      d_px
                    lda      rk_y
                    sta      d_py
                    lda      #16
                    sta      d_w
                    sta      d_h
                    ; the engine flame while thrusting, side to side with the thrust clock
                    clr      d_flame
                    clr      d_flame+1
                    lda      Vec_Btn_State
                    bita     #BTN_THRUST
                    beq      rk_no_flame
                    ldb      rk_heading
                    lda      #4
                    mul
                    addd     #rocket_flame
                    tst      rot_acc
                    bpl      rk_flame_side
                    addd     #2
rk_flame_side       std      d_flame
rk_no_flame         jsr      draw_object
                    clr      d_flame                ; only the rocket has one
                    clr      d_flame+1
no_rocket
t_rocket_done       jsr      saucers_visible
                    beq      no_saucers
                    jsr      draw_saucers
no_saucers
t_saucers_done      jsr      sound_wobble
                    jsr      draw_missiles
t_missiles_done     jsr      draw_digits
t_digits_done

                    jsr      Reset0Ref              ; park the beam at the centre
                    jmp      main

;***************************************************************************
; frame_wait: Alex Herbert's FRWAIT (from Protector) in place of Wait_Recal.
; With time left in the frame it recalibrates in that time (zero, then the
; ramp held open with the DAC at $40, flipped every 31 cycles, until timer 2
; runs out); a frame that ran over skips the recalibration. Wait_Recal
; restarts timer 2 first and recalibrates in the next frame's time (~900
; cycles). Exits with DP = $D0 and the integrators held at zero.
;***************************************************************************
frame_wait
                    lda      #$D0
                    tfr      a,dp
                    lda      #$20
                    bita     <VIA_int_flags
                    bne      fw_restart             ; ran over: no recalibration
                    lda      #$30
fw_gate             cmpa     <VIA_t2_hi             ; (high byte only: reading the low byte clears the flag)
                    blt      fw_gate
                    jsr      zero_beam
                    ldd      #$0040
                    stb      <VIA_port_a            ; DAC $40
                    sta      <VIA_port_b            ; mux on (Y), ramp bit low
                    ldd      #$CE18
                    sta      <VIA_cntl              ; integrate
                    stb      <VIA_aux_cntl          ; PB7 off T1: the ramp stays open
                    ldd      #$BF00
                    std      <VIA_t1_cnt_lo
fw_recal            lda      #$40
                    bita     <VIA_int_flags
                    beq      fw_t2
                    neg      <VIA_port_a
                    ldd      #$1F00
                    std      <VIA_t1_cnt_lo
fw_t2               lda      #$20
                    bita     <VIA_int_flags
                    beq      fw_recal
fw_restart          ldd      #$3075                 ; timer 2: 30000 cycles
                    std      <VIA_t2_lo
                    ldd      #$0400                 ; a 4-cycle T1, so PB7 comes back high (ramp off)
                    std      <VIA_t1_cnt_lo
                    ldd      #$0198
                    sta      <VIA_port_b
                    stb      <VIA_aux_cntl          ; PB7 on T1 again
; zero_beam: ZERGND: hold the integrators at zero, zero reference 0
zero_beam
                    lda      #$CC
                    sta      <VIA_cntl              ; /ZERO low
                    ldd      #$0300
                    std      <VIA_port_b            ; mux off, DAC 0
                    dec      <VIA_port_b            ; mux on: zero reference 0
                    nop
                    nop
                    dec      <VIA_port_b            ; mux off
                    rts

;***************************************************************************
; rocket_update: rotation and thrust on the rotate/thrust clock, then motion
;***************************************************************************
rocket_update
                    lda      rot_acc
                    adda     #ROT_RATE
                    sta      rot_acc
                    bcc      rk_move                ; no clock tick this frame
                    ; rotate (both buttons together: no turn)
                    lda      Vec_Btn_State
                    anda     #BTN_CCW+BTN_CW
                    cmpa     #BTN_CW
                    bne      rk_not_cw
                    inc      rk_heading
                    bra      rk_turned
rk_not_cw           cmpa     #BTN_CCW
                    bne      rk_turned
                    dec      rk_heading
rk_turned           lda      rk_heading
                    anda     #31
                    sta      rk_heading
                    ; thrust: each axis one level toward the heading's sign on it,
                    ; except near the other axis (memory_board.vhd:1368-1490, 1836-1843)
                    lda      Vec_Btn_State
                    bita     #BTN_THRUST
                    beq      rk_move
                    ldx      #thrust_tab
                    ldb      rk_heading
                    abx
                    abx
                    lda      ,x                     ; horizontal step -1/0/+1
                    adda     rk_vx
                    cmpa     #7
                    bgt      rk_hx
                    cmpa     #-7
                    blt      rk_hx
                    sta      rk_vx
rk_hx               lda      1,x                    ; vertical step -1/0/+1
                    adda     rk_vy
                    cmpa     #7
                    bgt      rk_move
                    cmpa     #-7
                    blt      rk_move
                    sta      rk_vy
rk_move
                    ; x += speed(vx), wraps at 256 by itself
                    ldb      rk_vx
                    jsr      level_speed
                    addd     rk_x
                    std      rk_x
                    ; y += speed(vy), wrapped into 0..238
                    ldb      rk_vy
                    jsr      level_speed
                    tst      rk_vy
                    bmi      rk_up
                    addd     rk_y
                    cmpa     #FIELD_H
                    blo      rk_y_ok
                    suba     #FIELD_H
                    bra      rk_y_ok
rk_up               addd     rk_y
                    cmpa     #FIELD_H
                    blo      rk_y_ok
                    adda     #FIELD_H               ; went below 0: wrap to the bottom
rk_y_ok             std      rk_y
                    rts

;***************************************************************************
; saucer_update: a new direction every SAUCER_CYCLE frames, then move
;***************************************************************************
saucer_update
                    dec      sc_timer
                    bne      sc_move
                    lda      #SAUCER_CYCLE
                    sta      sc_timer
                    jsr      random                 ; bits 0/1: x moves / x direction,
                    tfr      a,b                    ; bits 2/3: y moves / y direction
                    jsr      axis_dir
                    sta      sc_dx
                    lsrb
                    lsrb
                    jsr      axis_dir
                    sta      sc_dy
sc_move
                    ; x, wraps at 256 by itself
                    lda      sc_dx
                    beq      sc_y_move
                    ldx      #sc_x
                    jsr      step_axis
sc_y_move           lda      sc_dy
                    beq      sc_done
                    ldx      #sc_y
                    jsr      step_axis
                    lda      sc_y                   ; wrap into 0..238
                    cmpa     #FIELD_H
                    blo      sc_done
                    tst      sc_dy
                    bmi      sc_y_under
                    suba     #FIELD_H
                    sta      sc_y
                    bra      sc_done
sc_y_under          adda     #FIELD_H
                    sta      sc_y
sc_done             rts

; axis_dir: A = 0 if B bit 0 is clear, else +1 or -1 from B bit 1
axis_dir
                    clra
                    bitb     #1
                    beq      ad_done
                    lda      #1
                    bitb     #2
                    beq      ad_done
                    lda      #-1
ad_done             rts

; step_axis: add (A > 0) or subtract (A < 0) SAUCER_SPEED to the 8.8 value at X
step_axis
                    tsta
                    bmi      sa_neg
                    ldd      ,x
                    addd     #SAUCER_SPEED
                    std      ,x
                    rts
sa_neg              ldd      ,x
                    subd     #SAUCER_SPEED
                    std      ,x
                    rts

; random: A = next value of an 8-bit LFSR (period 255)
random
                    lda      rng
                    lsla
                    bcc      rnd_done
                    eora     #$1D
rnd_done            sta      rng
                    rts

;***************************************************************************
; draw_saucers: both copies, with the light phase from the saucer's and the
; rocket's columns (the original lights it from a rocket counter bit)
;***************************************************************************
draw_saucers
                    lda      sc_x
                    suba     rk_x
                    anda     #3
                    asla
                    ldx      #saucer_tab
                    ldx      a,x
                    stx      d_list
                    lda      sc_x
                    sta      d_px
                    lda      sc_y
                    sta      d_py
                    lda      #16
                    sta      d_w
                    lda      #8
                    sta      d_h
                    jsr      draw_object
                    lda      sc_y                   ; the second copy, SAUCER_GAP rows on
                    adda     #SAUCER_GAP
                    bcs      ds_wrap                ; past 255
                    cmpa     #FIELD_H
                    blo      ds_ok
ds_wrap             suba     #FIELD_H
ds_ok               sta      d_py
                    lda      sc_x
                    sta      d_px
                    jmp      draw_object

;***************************************************************************
; pos_lookup: the move from the centre to grid origin (d_gx, d_gy): the
; smallest scale class that reaches (d_mscale), its DAC values (d_dacy,
; d_dacx) and the remainders for the first move after it (d_remy0, d_remx0)
;***************************************************************************
pos_lookup
                    ; move class: the smallest scale whose reach covers both axes
                    ldd      d_gx
                    addd     #16+need_y
                    tfr      d,u
                    lda      ,u                     ; the column's class
                    sta      d_tmp
                    ldd      d_gy
                    addd     #16+need_x
                    tfr      d,u
                    lda      ,u                     ; the row's class
                    cmpa     d_tmp
                    bhs      dc_class
                    lda      d_tmp
dc_class            ldu      #move_scales           ; A = class
                    ldb      a,u
                    stb      d_mscale
                    asla
                    sta      d_tmp                  ; class * 2
                    ldu      #pos_y_tab
                    ldu      a,u                    ; this class's column table
                    ldd      d_gx
                    addd     #16
                    lslb
                    rola
                    leau     d,u
                    ldd      ,u                     ; A = dac, B = remainder
                    sta      d_dacy
                    stb      d_remy0
                    lda      d_tmp
                    ldu      #pos_x_tab
                    ldu      a,u                    ; this class's row table
                    ldd      d_gy
                    addd     #16
                    lslb
                    rola
                    leau     d,u
                    ldd      ,u
                    sta      d_dacx
                    stb      d_remx0
                    rts

;***************************************************************************
; anchor_move: with the beam off, re-zero the integrators and move to the
; position pos_lookup found; returns when the move has ended
;***************************************************************************
anchor_move
                    ldd      #$00CC
                    stb      <VIA_cntl              ; /ZERO low
                    sta      <VIA_shift_reg
                    ldd      #$0300
                    std      <VIA_port_b            ; mux off, DAC 0
                    dec      <VIA_port_b            ; mux on: zero reference 0
                    nop
                    nop
                    dec      <VIA_port_b            ; mux off
                    lda      d_mscale
                    sta      <VIA_t1_cnt_lo
                    lda      d_dacy
                    sta      <VIA_port_a
                    clr      <VIA_port_b
                    lda      #$CE
                    sta      <VIA_cntl              ; /ZERO high: integrate
                    inc      <VIA_port_b
                    ldb      d_dacx
                    stb      <VIA_port_a
                    clr      <VIA_t1_cnt_hi
                    ldb      #$40
am_wait             bitb     <VIA_int_flags
                    beq      am_wait
                    nop                             ; the ramp tail (14 cycles)
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    rts

;***************************************************************************
; draw_digits: the scores and the time as on the original: 7-segment glyphs,
; two digits each (a score's tens hidden while 0), rotated with the field and
; at the original's places (rows 91, 123, 155; tens at column 224, units 240).
; Raster sweeps along the original's raster direction (the long axis): one sweep
; per glyph row through the tens and the units, one shift-register byte per
; glyph, the writes 18 cycles apart as in the BIOS text printer (a write
; while the shift register is still sending cuts the byte short on a real
; 6522). Alternate rows on alternate frames. Each sweep comes back at the same
; rate for the same time (the ramp delays cancel on any console), stepping
; 2 px to the next row on the way.
;***************************************************************************
DIGIT_INTENSITY     equ      $7F
DG_RATE             equ      59*FIELD_FLIP          ; 16 px per 36 cycles (133 DAC-cycles per px)
DG_T1_2             equ      52                     ; tens + units: last write +65, motion to +66
DG_T1_1             equ      16                     ; units only: last write +29, motion to +30
DG_STEP_2           equ      5*FIELD_FLIP           ; the return's step: 2.07 px in 55 cycles
DG_STEP_1           equ      14*FIELD_FLIP          ; 2 px in 19 cycles
draw_digits
                    lda      #DIGIT_INTENSITY
                    jsr      Intensity_a
                    lda      frame_count
                    anda     #1
                    sta      dg_par
                    clr      dg_k
                    lda      score_rk
                    jsr      dg_split
                    jsr      dg_number
                    lda      #20
                    sta      dg_k
                    lda      score_sc
                    jsr      dg_split
                    jsr      dg_number
                    tst      hyper                  ; hyperspace: the time blinks
                    beq      dd_time
                    lda      frame_count
                    bita     #16
                    beq      dd_time
                    rts
dd_time             lda      #40
                    sta      dg_k
                    lda      tm_tens                ; the time shows both digits
                    ldb      tm_units
; dg_number: A = tens ($FF: not shown), B = units, dg_k = the anchor block
dg_number
                    sta      dg_tens
                    tfr      b,a
                    jsr      dg_glyph
                    stx      dg_p2
                    ldb      dg_k
                    tst      dg_par
                    beq      dn_par
                    addb     #10
dn_par              lda      dg_tens
                    bmi      dn_units
                    pshs     b
                    jsr      dg_glyph
                    stx      dg_p1
                    puls     b
                    lda      #DG_T1_2
                    sta      dg_t1
                    ldx      #dg_anchors
                    abx
                    jsr      dg_anchor
                    ldx      dg_p1
                    ldu      dg_p2
                    lda      #8
                    sta      dg_cols
dg_l2
                    lda      #DG_RATE
                    sta      <VIA_port_a
                    clr      <VIA_port_b            ; mux on: Y, the sweep rate
                    ldb      ,u
                    nop
                    inc      <VIA_port_b            ; mux off
                    clr      <VIA_port_a            ; X still
                    lda      ,x
                    clr      <VIA_t1_cnt_hi         ; start: motion from +11
                    brn      *
                    nop
                    nop
                    sta      <VIA_shift_reg         ; +11 tens
                    clra
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    sta      <VIA_shift_reg         ; +29 off (column 7 held 2 cycles)
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    stb      <VIA_shift_reg         ; +47 units
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    sta      <VIA_shift_reg         ; +65 off
                    leax     2,x                    ; two rows on
                    leau     2,u
                    dec      dg_cols
                    beq      dg_last
                    jsr      dg_wait
                    lda      #DG_STEP_2
                    jsr      dg_back
                    bra      dg_l2
dn_units            addb     #5                     ; the anchor at the units
                    lda      #DG_T1_1
                    sta      dg_t1
                    ldx      #dg_anchors
                    abx
                    jsr      dg_anchor
                    ldu      dg_p2
                    lda      #8
                    sta      dg_cols
dg_l1
                    lda      #DG_RATE
                    sta      <VIA_port_a
                    clr      <VIA_port_b            ; mux on: Y, the sweep rate
                    ldb      ,u
                    nop
                    inc      <VIA_port_b            ; mux off
                    clr      <VIA_port_a            ; X still
                    clr      <VIA_t1_cnt_hi         ; start: motion from +11
                    brn      *
                    nop
                    nop
                    stb      <VIA_shift_reg         ; +11 units
                    clra
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    sta      <VIA_shift_reg         ; +29 off
                    leau     2,u
                    dec      dg_cols
                    beq      dg_last
                    jsr      dg_wait
                    lda      #DG_STEP_1
                    jsr      dg_back
                    bra      dg_l1
dg_last             bra      dg_wait

; dg_back: the beam off, back down the sweep at the same rate for the same
; time, A = the step to the next row (X)
dg_back
                    ldb      #-DG_RATE
                    stb      <VIA_port_a
                    clr      <VIA_port_b            ; mux on: Y
                    nop
                    nop
                    nop
                    inc      <VIA_port_b            ; mux off
                    sta      <VIA_port_a            ; X: the step
                    clr      <VIA_t1_cnt_hi         ; (T1 latch: this number's sweep time)
; dg_wait: until the move has ended, ramp tail included
dg_wait
                    ldb      #$40
dg_w                bitb     <VIA_int_flags
                    beq      dg_w
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    rts

; dg_split: A = 0..99 -> A = tens ($FF when 0: not shown), B = units
dg_split
                    ldb      #-1
ds_loop             incb
                    suba     #10
                    bcc      ds_loop
                    adda     #10
                    exg      a,b
                    tsta
                    bne      ds_done
                    deca
ds_done             rts

; dg_anchor: X = an anchor record: re-anchor there, then the remainder move;
; leaves T1 latched at this number's sweep time
dg_anchor
                    lda      ,x
                    sta      d_dacy
                    lda      1,x
                    sta      d_dacx
                    lda      4,x
                    sta      d_mscale
                    jsr      anchor_move
                    lda      #FIRST_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      2,x                    ; remy0
                    ldb      3,x                    ; remx0
                    sta      <VIA_port_a
                    clr      <VIA_port_b
                    nop
                    nop
                    nop
                    inc      <VIA_port_b
                    stb      <VIA_port_a
                    clr      <VIA_t1_cnt_hi
                    lda      dg_t1
                    sta      <VIA_t1_cnt_lo
                    bra      dg_wait

; dg_glyph: X = this frame's first row of value A
dg_glyph
                    ldb      #16
                    mul                             ; D = 16 * value
                    addd     #digit_rows
                    tfr      d,x
                    ldb      dg_par
                    abx
                    rts

; digits_init: the digit anchors never move: look them up once. Sweeps start
; one slot before the glyph (the blank leading bit): columns 223 and 239.
dg_places           dw       223,91, 239,91, 223,92, 239,92
                    dw       223,123, 239,123, 223,124, 239,124
                    dw       223,155, 239,155, 223,156, 239,156
digits_init
                    ldx      #dg_anchors
                    ldy      #dg_places
di_loop             ldd      ,y++
                    std      d_gx
                    ldd      ,y++
                    std      d_gy
                    pshs     x,y
                    jsr      pos_lookup
                    puls     x,y
                    lda      d_dacy
                    sta      ,x+
                    lda      d_dacx
                    sta      ,x+
                    lda      d_remy0
                    sta      ,x+
                    lda      d_remx0
                    sta      ,x+
                    lda      d_mscale
                    sta      ,x+
                    cmpy     #dg_places+48
                    bne      di_loop
                    rts

;***************************************************************************
; draw_missiles: each missile in flight is one dot: re-zero, move there, and
; a last short move carrying the position remainder
;***************************************************************************
draw_missiles
                    tst      rm_on
                    beq      dm_saucer
                    lda      rm_x
                    ldb      rm_y
                    jsr      draw_point
dm_saucer           tst      sm_on
                    beq      dm_done
                    lda      sm_x
                    ldb      sm_y
                    jmp      draw_point
dm_done             rts

; draw_point: one dot at field column A, row B
draw_point
                    pshs     b
                    tfr      a,b
                    clra
                    std      d_gx
                    puls     b
                    clra
                    std      d_gy
                    jsr      pos_lookup
                    jsr      anchor_move
                    lda      #FIRST_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      d_remy0
                    ldb      d_remx0
                    sta      <VIA_port_a
                    clr      <VIA_port_b
                    nop
                    nop
                    nop
                    inc      <VIA_port_b
                    stb      <VIA_port_a
                    clr      <VIA_t1_cnt_hi         ; (the beam is already off)
                    ldb      #$40
dp_wait             bitb     <VIA_int_flags
                    beq      dp_wait
                    nop                             ; the ramp tail
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    lda      #$ff
                    sta      <VIA_shift_reg         ; the dot
                    ldb      #6
dp_glow             decb
                    bne      dp_glow
                    stb      <VIA_shift_reg
                    rts

;***************************************************************************
; level_speed: D = signed speed (1/256 px per frame) for velocity level B
;***************************************************************************
level_speed
                    tstb
                    bmi      ls_neg
                    ldx      #speed_tab
                    abx
                    abx
                    ldd      ,x
                    rts
ls_neg              negb
                    ldx      #speed_tab
                    abx
                    abx
                    ldd      ,x
                    coma
                    comb
                    addd     #1
                    rts

;***************************************************************************
; draw_stars: half of the original star field, alternating each frame
;***************************************************************************
draw_stars
                    lda      star_int
                    jsr      Intensity_a
                    jsr      Reset0Ref
                    ldd      #0
                    jsr      Moveto_d               ; releases the integrators from zero
                    lda      frame_count
                    bita     #1
                    lbne     stars_odd
                    INCLUDE  "stars_a.inc"
                    rts
stars_odd
                    INCLUDE  "stars_b.inc"
                    rts

;***************************************************************************
; draw_object: draw a dot-chain object at (d_px, d_py), wrapping at the
; field edges. An object that crosses an edge is drawn once per copy (up to
; four at a corner); each copy lights only its dots that fall in the field.
;   in: d_list, d_px, d_py, d_w, d_h
;***************************************************************************
draw_object
                    ; columns: does the object cross x = 256?
                    lda      #0
                    suba     d_px                   ; A = 256 - px (mod 256)
                    ldb      d_px
                    beq      x_whole
                    cmpa     d_w
                    blo      x_cut
x_whole             lda      d_w
x_cut               sta      d_cmax_main
                    ; rows: does it cross y = 239?
                    lda      #FIELD_H
                    suba     d_py                   ; A = 239 - py
                    cmpa     d_h
                    blo      y_cut
                    lda      d_h
y_cut               sta      d_rmax_main

                    ; main copy
                    clra
                    ldb      d_px
                    std      d_gx
                    ldb      d_py
                    std      d_gy
                    clr      d_cmin
                    lda      d_cmax_main
                    sta      d_cmax
                    clr      d_rmin
                    lda      d_rmax_main
                    sta      d_rmax
                    jsr      draw_copy

                    ; copy wrapped across x (origin at px - 256)
                    lda      d_cmax_main
                    cmpa     d_w
                    beq      no_xwrap
                    ldd      d_gx
                    subd     #256
                    std      d_gx
                    lda      d_cmax_main
                    sta      d_cmin
                    lda      d_w
                    sta      d_cmax
                    jsr      draw_copy
                    ; and across both (corner)
                    lda      d_rmax_main
                    cmpa     d_h
                    beq      no_corner
                    ldd      d_gy
                    subd     #FIELD_H
                    std      d_gy
                    lda      d_rmax_main
                    sta      d_rmin
                    lda      d_h
                    sta      d_rmax
                    jsr      draw_copy
no_corner
no_xwrap
                    ; copy wrapped across y (origin at py - 239)
                    lda      d_rmax_main
                    cmpa     d_h
                    beq      no_ywrap
                    clra
                    ldb      d_px
                    std      d_gx
                    clra
                    ldb      d_py
                    subd     #FIELD_H
                    std      d_gy
                    clr      d_cmin
                    lda      d_cmax_main
                    sta      d_cmax
                    lda      d_rmax_main
                    sta      d_rmin
                    lda      d_h
                    sta      d_rmax
                    jsr      draw_copy
no_ywrap
                    rts

;***************************************************************************
; draw_copy: one copy of a segmented dot list (tools/dotlist.py) with its grid
; origin at (d_gx, d_gy) (signed, may be just off the field), lighting dots
; with row in [d_rmin, d_rmax) and col in [d_cmin, d_cmax).
; Every segment starts with a re-anchor: the beam is re-zeroed and moved to the
; corner again, because on hardware the error builds up along a chain.
; X = list, Y = dots left in the segment.
;***************************************************************************
draw_copy
                    jsr      pos_lookup
                    ; clipped unless the whole grid is in the field
                    clr      d_clip
                    lda      d_cmin
                    ora      d_rmin
                    bne      dc_clipped
                    lda      d_cmax
                    cmpa     d_w
                    bne      dc_clipped
                    lda      d_rmax
                    cmpa     d_h
                    beq      dc_whole
dc_clipped          inc      d_clip
dc_whole
                    ldx      d_list
seg_loop
                    ldb      ,x                     ; dots in this segment, 0 = end
                    lbeq     seg_end
                    clra
                    tfr      d,y
                    tst      d_clip
                    beq      seg_go
                    ; straddling copy: skip a segment with no dot in the field
                    lda      1,x                    ; segment rows [1,x .. 2,x), cols [3,x .. 4,x)
                    cmpa     d_rmax
                    lbhs     seg_skip
                    lda      2,x
                    cmpa     d_rmin
                    lbls     seg_skip
                    lda      3,x
                    cmpa     d_cmax
                    lbhs     seg_skip
                    lda      4,x
                    cmpa     d_cmin
                    lbls     seg_skip
seg_go              leax     5,x
                    ; re-anchor: let the previous dot glow, blank, re-zero, back to the corner
                    ldb      #6
seg_glow            decb
                    bne      seg_glow
                    stb      <VIA_shift_reg         ; B = 0: beam off
                    ; re-zero the integrators (as Alex Herbert's ZERGND in Protector)
                    lda      #$CC
                    sta      <VIA_cntl              ; /ZERO low
                    ldd      #$0300
                    std      <VIA_port_b            ; mux off, DAC 0
                    dec      <VIA_port_b            ; mux on: zero reference 0
                    nop
                    nop
                    dec      <VIA_port_b            ; mux off
                    ; move to the corner at this copy's scale (as Moveto_d)
                    lda      d_mscale
                    sta      <VIA_t1_cnt_lo
                    lda      d_dacy
                    sta      <VIA_port_a            ; Y to the DAC
                    clr      <VIA_port_b            ; mux on
                    lda      #$CE
                    sta      <VIA_cntl              ; /ZERO high: integrate
                    inc      <VIA_port_b            ; mux off
                    ldb      d_dacx
                    stb      <VIA_port_a            ; X to the DAC
                    clr      <VIA_t1_cnt_hi         ; start the move
                    ldb      #$40
seg_wait            bitb     <VIA_int_flags         ; until T1 has run out
                    beq      seg_wait
                    lda      #FIRST_SCALE           ; (these ~25 cycles cover the ramp-off delay)
                    sta      <VIA_t1_cnt_lo
                    lda      ,x                     ; the first move carries the remainder
                    adda     d_remy0
                    ldb      1,x
                    addb     d_remx0
                    tst      d_clip
                    lbne     chk_entry

; --- whole copy in view, pipelined: no polling. While a move ramps, the next
; move is prepared (pointer, count, next dY, the DAC scale latch, which the
; running timer ignores); the dot is lit a counted number of cycles after the
; move started: scale + 3 + 14 (ramp tail) + a 4-cycle margin.
; First move of the segment, at FIRST_SCALE: lit 38 cycles after the T1 write.
                    sta      <VIA_port_a            ; Y to the DAC
                    clr      <VIA_port_b            ; mux on: sample Y
                    leax     4,x                    ; (sample/hold settle)
                    nop
                    inc      <VIA_port_b            ; mux off
                    stb      <VIA_port_a            ; X to the DAC
                    clrb
                    stb      <VIA_shift_reg         ; beam off for the move
                    clr      <VIA_t1_cnt_hi         ; start the move
                    lda      #DOT_SCALE             ; the chain moves' scale, for the next move
                    sta      <VIA_t1_cnt_lo
                    leay     -1,y
                    beq      fast_last16
                    lda      ,x                     ; next dY
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    ldb      #$ff
                    stb      <VIA_shift_reg         ; beam on, held at the dot
                    ldb      1,x                    ; next dX
; Chain moves, at DOT_SCALE: lit 28 cycles after the T1 write.
fast_loop           sta      <VIA_port_a
                    clr      <VIA_port_b
                    leax     4,x
                    nop
                    inc      <VIA_port_b
                    stb      <VIA_port_a
                    clrb
                    stb      <VIA_shift_reg
                    clr      <VIA_t1_cnt_hi
                    leay     -1,y
                    beq      fast_last
                    lda      ,x
                    nop
                    nop
                    nop
                    nop
                    nop
                    ldb      #$ff
                    stb      <VIA_shift_reg
                    ldb      1,x
                    bra      fast_loop
fast_last16         nop                             ; last dot after a FIRST_SCALE move
                    nop
fast_last           nop                             ; last dot after a chain move
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    ldb      #$ff
                    stb      <VIA_shift_reg
                    jmp      seg_loop

; --- copy straddling an edge: light only the dots in the field. The test fills
; the move's wait; the scale latch is set for the chain moves after each start.
chk_next            lda      ,x
                    ldb      1,x
chk_entry           sta      <VIA_port_a
                    clr      <VIA_port_b
                    nop
                    nop
                    nop
                    inc      <VIA_port_b
                    stb      <VIA_port_a
                    clrb
                    stb      <VIA_shift_reg
                    clr      <VIA_t1_cnt_hi
                    lda      #DOT_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      2,x
                    cmpa     d_rmin
                    blo      chk_hidden
                    cmpa     d_rmax
                    bhs      chk_hidden
                    lda      3,x
                    cmpa     d_cmin
                    blo      chk_hidden
                    cmpa     d_cmax
                    bhs      chk_hidden
                    lda      #$ff
                    sta      <VIA_shift_reg
                    bra      chk_step
chk_hidden          nop                             ; a hidden dot still needs its move to end
                    nop
                    nop
                    nop
                    nop
                    nop
chk_step            leax     4,x
                    leay     -1,y
                    bne      chk_next
                    jmp      seg_loop

seg_skip            ldb      #6                     ; the last lit dot glows as long as the others
seg_skip_glow       decb
                    bne      seg_skip_glow
                    stb      <VIA_shift_reg         ; B = 0: beam off
                    ldb      ,x                     ; past the header and n entries
                    lslb
                    lslb
                    addb     #5
                    abx
                    jmp      seg_loop

seg_end             ldb      #6                     ; the last dot glows as long as the others
seg_glow2           decb
                    bne      seg_glow2
                    stb      <VIA_shift_reg
                    ldx      d_flame                ; the rocket engine flame, after the last dot
                    beq      seg_done
                    tst      d_clip                 ; (not on a copy straddling an edge)
                    bne      seg_done
                    lda      #FIRST_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      ,x
                    ldb      1,x
                    sta      <VIA_port_a
                    clr      <VIA_port_b
                    nop
                    nop
                    nop
                    inc      <VIA_port_b
                    stb      <VIA_port_a
                    clr      <VIA_t1_cnt_hi         ; (the beam is off)
                    ldb      #$40
fl_wait             bitb     <VIA_int_flags
                    beq      fl_wait
                    nop                             ; the ramp tail
                    nop
                    nop
                    nop
                    nop
                    nop
                    nop
                    lda      #$ff
                    sta      <VIA_shift_reg         ; the flame dot
                    ldb      #6
fl_glow             decb
                    bne      fl_glow
                    stb      <VIA_shift_reg
seg_done            rts

;***************************************************************************
; Data
;***************************************************************************
; Speed per velocity level in 1/256 px per 50 Hz frame: the core moves
; 0,1,2,2,4,5,6,6 px per 16 frames of 59.885 Hz (docs/spec.md 3).
speed_tab           DW       0, 19, 38, 38, 77, 96, 115, 115

; Thrust step per heading: (horizontal, vertical). Horizontal +1 (right) for
; headings 0-15, -1 for 16-31, none within 16 deg of north/south (0,1,14-17,
; 30,31). Vertical -1 (up) for 0-7 and 24-31, +1 (down) for 8-23, none within
; 16 deg of east/west (6-9, 22-25). Generated from those rules.
thrust_tab
                    DB        0,-1,   0,-1,   1,-1,   1,-1,   1,-1,   1,-1,   1, 0,   1, 0
                    DB        1, 0,   1, 0,   1, 1,   1, 1,   1, 1,   1, 1,   0, 1,   0, 1
                    DB        0, 1,   0, 1,  -1, 1,  -1, 1,  -1, 1,  -1, 1,  -1, 0,  -1, 0
                    DB       -1, 0,  -1, 0,  -1,-1,  -1,-1,  -1,-1,  -1,-1,   0,-1,   0,-1

                    INCLUDE  "postab.inc"
                    INCLUDE  "rocket.inc"
                    INCLUDE  "saucer.inc"
                    INCLUDE  "tables.inc"
                    INCLUDE  "digits.inc"
; a missile: one dot (a segmented dot list, tools/dotlist.py)
missile_dot         DB       1, 0, 1, 0, 1
                    DB       0, 0, 0, 0
                    DB       0

                    INCLUDE  "game.asm"
                    INCLUDE  "sound.asm"

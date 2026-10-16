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
OBJ_INTENSITY       equ      $7F
; DOT_SCALE and MOVE_SCALE come from postab.inc (tools/vxparams.py)

; Rotate/thrust clock: the core steps 9 times a second (clocks.vhd:86-99; its
; comment says 18 Hz on a real board - open question, docs/spec.md 3).
; Phase accumulator per 50 Hz frame: 9 * 256 / 50 = 46.
ROT_RATE            equ      46

; Controller buttons (Vec_Btn_State, stick 1), laid out like the cabinet panel
BTN_CCW             equ      $01                    ; button 1: rotate anticlockwise
BTN_CW              equ      $02                    ; button 2: rotate clockwise
BTN_THRUST          equ      $04                    ; button 3: thrust
BTN_FIRE            equ      $08                    ; button 4: fire

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
                    ldd      #114*256               ; the original's start: column 114,
                    std      rk_x
                    ldd      #(FIELD_H-14)*256      ; row -14 (on the wrap seam)
                    std      rk_y

;***************************************************************************
;***************************************************************************
; Frame loop
;***************************************************************************
main
                    jsr      Wait_Recal             ; exits with DP = $D0
                    inc      frame_count
                    jsr      Read_Btns              ; Vec_Btn_State: held buttons
                    jsr      rocket_update

                    jsr      draw_stars

                    lda      #OBJ_INTENSITY
                    jsr      Intensity_a
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
                    jsr      draw_object

                    jsr      Reset0Ref              ; park the beam at the centre
                    jmp      main

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
                    lda      #STAR_INTENSITY
                    jsr      Intensity_a
                    jsr      Reset0Ref
                    ldd      #0
                    jsr      Moveto_d               ; releases the integrators from zero
                    lda      Vec_Loop_Count+1
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
; draw_copy: one copy of a dot chain with its grid origin at (d_gx, d_gy)
; (signed, may be just off the field), lighting dots with row in
; [d_rmin, d_rmax) and col in [d_cmin, d_cmax). Entries are
; (dY, dX, row, col, anchor); at an anchor the beam is re-zeroed and moved to
; the corner again, because on hardware the error builds up along a chain.
;***************************************************************************
draw_copy
                    ldd      d_gx                   ; Vectrex Y from the column
                    addd     #16
                    lslb
                    rola
                    addd     #pos_y
                    tfr      d,u
                    ldd      ,u                     ; A = dac, B = remainder
                    sta      d_dacy
                    stb      d_remy0
                    ldd      d_gy                   ; Vectrex X from the row
                    addd     #16
                    lslb
                    rola
                    addd     #pos_x
                    tfr      d,u
                    ldd      ,u
                    sta      d_dacx
                    stb      d_remx0

                    ldx      d_list
                    lda      ,x+
                    sta      d_count
dot_loop
                    tst      4,x
                    beq      dot_rel
                    ; anchor: let the previous dot glow, blank, re-zero, back to the corner
                    ldb      #6
dot_glow            decb
                    bne      dot_glow
                    stb      <VIA_shift_reg         ; B = 0: beam off
                    pshs     x
                    jsr      Reset0Ref
                    lda      #MOVE_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      d_dacy
                    ldb      d_dacx
                    jsr      Moveto_d
                    lda      #DOT_SCALE
                    sta      <VIA_t1_cnt_lo
                    lda      d_remy0
                    sta      d_remy
                    lda      d_remx0
                    sta      d_remx
                    puls     x
dot_rel
                    lda      ,x                     ; dY (+ remainder after an anchor)
                    adda     d_remy
                    ldb      1,x                    ; dX
                    addb     d_remx
                    sta      <VIA_port_a            ; Y to the DAC
                    clr      <VIA_port_b            ; mux on: sample Y
                    nop
                    nop
                    nop
                    inc      <VIA_port_b            ; mux off
                    stb      <VIA_port_a            ; X to the DAC
                    clrb
                    stb      <VIA_shift_reg         ; beam off for the move
                    clr      <VIA_t1_cnt_hi         ; start the move
                    ; during the move (scale + ~17 cycles until it really ends): in the field?
                    lda      2,x
                    cmpa     d_rmin
                    blo      dot_hidden
                    cmpa     d_rmax
                    bhs      dot_hidden
                    lda      3,x
                    cmpa     d_cmin
                    blo      dot_hidden
                    cmpa     d_cmax
                    bhs      dot_hidden
                    lda      #$ff
                    sta      <VIA_shift_reg         ; beam on, held at the dot
dot_hidden
                    clr      d_remy
                    clr      d_remx
                    leax     5,x
                    dec      d_count
                    bne      dot_loop
                    ldb      #6                     ; the last dot glows as long as the others
dot_glow2           decb
                    bne      dot_glow2
                    stb      <VIA_shift_reg
                    rts

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

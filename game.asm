;***************************************************************************
; Computer Space game rules (docs/spec.md): game flow, missiles, collisions,
; explosions, scores and the game timer. Included by computerspace.asm.
; DP = $D0 throughout; RAM is addressed extended.
;***************************************************************************

EV_LEN              equ      58                     ; explosion event: ~7/6 s (7 periods of 6 Hz)
OVER_LOCK_LEN       equ      150                    ; 3 s after a game: buttons ignored, scores shown
HY_FLASH_LEN        equ      48                     ; hyperspace start: flashes while bit 3 is set
EV_SPIN_END         equ      33                     ; a hit rocket spins for ~4/6 s, then hides
SPIN_STEP           equ      5                      ; headings (of 32) per frame while spinning: ~7.8 turns/s
                                                    ; (the core clocks the heading at ~170 kHz: a blur)
EV_FLASH_FROM       equ      8                      ; the flash: the 2nd 1/6 s of the event
EV_FLASH_TO         equ      16
EV_SAUCER           equ      $01                    ; saucer hit by the rocket missile: saucer hidden
EV_SPIN             equ      $02                    ; rocket hit by the saucer missile: spin, then hidden
EV_CRASH            equ      $04                    ; rocket and saucer collided: both hidden
START_HIDE          equ      58                     ; the rocket appears ~1.15 s after start
MISSILE_LIFE        equ      115                    ; 2.3 s (clocks.vhd:172,178)
AIM_NEAR            equ      32                     ; saucer missile: no motion on an axis within 32 px
REPLAY              equ      1                      ; hyperspace on (the operator's replay switch)

;***************************************************************************
; game_init: power-on: attract mode, scores and time at zero
;***************************************************************************
game_init
                    clr      game_on
                    clr      over_lock
                    clr      hyper
                    clr      hy_flash
                    clr      score_rk
                    clr      score_sc
                    clr      tm_units
                    clr      tm_tens
                    clr      sec_acc
                    clr      ev_timer
                    clr      ev_kind
                    clr      rm_on
                    clr      sm_on
                    clr      rk_hide
                    rts

;***************************************************************************
; game_start: a coin and Start in one press (any button, in attract mode)
;***************************************************************************
game_start
                    lda      #1
                    sta      game_on
                    clr      hyper
                    clr      hy_flash
                    clr      score_rk
                    clr      score_sc
                    clr      tm_units
                    clr      tm_tens
                    clr      sec_acc
                    clr      ev_timer
                    clr      ev_kind
                    clr      rm_on
                    clr      sm_on
                    lda      #START_HIDE
                    sta      rk_hide
                    clr      rk_heading
                    clr      rk_vx
                    clr      rk_vy
                    ldd      #114*256               ; the original's start: column 114,
                    std      rk_x
                    ldd      #(FIELD_H-14)*256      ; row -14 (on the wrap seam)
                    std      rk_y
                    rts

;***************************************************************************
; game_update: once per frame, after the inputs and the saucers have moved
;***************************************************************************
game_update
                    tst      game_on
                    bne      gu_playing
                    tst      over_lock              ; just over: the scores stay, buttons locked
                    beq      gu_unlocked
                    dec      over_lock
                    rts
gu_unlocked         lda      Vec_Buttons            ; attract: any new button press starts
                    anda     #$0F
                    beq      gu_attract_done
                    jsr      game_start
gu_attract_done     rts

gu_playing
                    tst      hy_flash
                    beq      gu_no_hyf
                    dec      hy_flash
gu_no_hyf           jsr      game_clock
                    tst      game_on                ; the game may just have ended
                    beq      gu_attract_done
                    tst      rk_hide
                    beq      gu_no_hide
                    dec      rk_hide
gu_no_hide
                    jsr      event_update
                    jsr      rocket_missile
                    jsr      saucer_missile
                    jsr      collisions
                    rts

;***************************************************************************
; game_clock: the game time counts once a second; at 99 -> 00 the game ends,
; or goes on in hyperspace once if the rocket is ahead (sync_star_board.vhd
; 1380-1442)
;***************************************************************************
game_clock
                    inc      sec_acc
                    lda      sec_acc
                    cmpa     #50
                    blo      gc_done
                    clr      sec_acc
                    inc      tm_units
                    lda      tm_units
                    cmpa     #10
                    blo      gc_done
                    clr      tm_units
                    inc      tm_tens
                    lda      tm_tens
                    cmpa     #10
                    blo      gc_done
                    clr      tm_tens                ; 99 -> 00: end of the game
                    tst      hyper
                    bne      gc_over
                    lda      #REPLAY
                    beq      gc_over
                    lda      score_rk
                    cmpa     score_sc
                    bls      gc_over
                    lda      #1                     ; the rocket is ahead: hyperspace
                    sta      hyper
                    lda      #HY_FLASH_LEN          ; it starts with a burst of flashes
                    sta      hy_flash
gc_done             rts
gc_over             clr      game_on
                    lda      #OVER_LOCK_LEN
                    sta      over_lock
                    clr      hyper
                    clr      hy_flash
                    clr      rm_on
                    clr      sm_on
                    clr      ev_timer
                    clr      ev_kind
                    rts

;***************************************************************************
; event_update: the explosion event after a hit or a collision
;***************************************************************************
event_update
                    tst      ev_timer
                    beq      eu_done
                    dec      ev_timer
                    bne      eu_running
                    clr      ev_kind                ; over: everything back
                    rts
eu_running          lda      ev_kind
                    bita     #EV_SPIN
                    beq      eu_done
                    jsr      ev_age
                    cmpa     #EV_SPIN_END
                    bhs      eu_done
                    lda      rk_heading             ; a hit rocket spins
                    adda     #SPIN_STEP
                    anda     #31
                    sta      rk_heading
eu_done             rts

; ev_age: A = frames since the event started
ev_age
                    lda      #EV_LEN
                    suba     ev_timer
                    rts

; event_start: A = the EV_* kind; ignored while an event is running
event_start
                    tst      ev_timer
                    bne      es_busy
                    sta      ev_kind
                    lda      #EV_LEN
                    sta      ev_timer
es_busy             rts

;***************************************************************************
; Visibility and the flash
;***************************************************************************
; rocket_visible: Z clear if the rocket is shown
rocket_visible
                    tst      game_on
                    beq      rv_no
                    tst      rk_hide
                    bne      rv_no
                    lda      ev_kind
                    bita     #EV_CRASH
                    bne      rv_no
                    bita     #EV_SPIN
                    beq      rv_yes
                    jsr      ev_age
                    cmpa     #EV_SPIN_END
                    bhs      rv_no
rv_yes              lda      #1
                    rts
rv_no               clra
                    rts

; saucers_visible: Z clear if the saucers are shown
saucers_visible
                    lda      ev_kind
                    bita     #EV_SAUCER+EV_CRASH
                    bne      sv_no
                    lda      #1
                    rts
sv_no               clra
                    rts

; flash_on: Z clear during the explosion flash
flash_on
                    lda      hy_flash               ; the hyperspace start: 3 flashes
                    bita     #8
                    bne      fo_yes
                    tst      ev_timer
                    beq      fo_no
                    jsr      ev_age
                    cmpa     #EV_FLASH_FROM
                    blo      fo_no
                    cmpa     #EV_FLASH_TO
                    bhs      fo_no
fo_yes              lda      #1
                    rts
fo_no               clra
                    rts

;***************************************************************************
; rocket_missile: fire (one at a time; holding fire refires when it expires),
; steer it with the rocket's heading every frame, expire after 2.3 s
;***************************************************************************
rocket_missile
                    tst      rm_on
                    bne      rm_fly
                    lda      Vec_Btn_State
                    bita     #BTN_FIRE
                    beq      rm_done
                    jsr      rocket_visible
                    beq      rm_done
                    lda      rk_x                   ; launch near the rocket's centre
                    adda     #8
                    clrb
                    std      rm_x
                    lda      rk_y
                    adda     #8
                    cmpa     #FIELD_H
                    blo      rm_y0
                    suba     #FIELD_H
rm_y0               clrb
                    std      rm_y
                    lda      #MISSILE_LIFE
                    sta      rm_life
                    lda      #1
                    sta      rm_on
                    rts
rm_fly
                    dec      rm_life
                    bne      rm_move
                    clr      rm_on
                    rts
rm_move             ldb      rk_heading             ; steered by the current heading
                    aslb
                    aslb
                    ldx      #missile_tab
                    abx
                    ldd      ,x                     ; dx
                    addd     rm_x
                    std      rm_x
                    ldd      2,x                    ; dy
                    ldx      #rm_y
                    jsr      add_y_wrap
rm_done             rts

; add_y_wrap: the 8.8 row at X += D (signed), wrapped into 0..238
add_y_wrap
                    tsta
                    bmi      ayw_neg
                    addd     ,x
                    cmpa     #FIELD_H
                    blo      ayw_ok
                    suba     #FIELD_H
                    bra      ayw_ok
ayw_neg             addd     ,x
                    cmpa     #FIELD_H
                    blo      ayw_ok
                    adda     #FIELD_H
ayw_ok              std      ,x
                    rts

;***************************************************************************
; saucer_missile: launched from the saucer at the start of each saucer cycle,
; aimed once per axis at the rocket (still if within 32 px on that axis),
; then straight; 2.3 s (motion_board.vhd:1215-1464)
;***************************************************************************
saucer_missile
                    lda      sc_timer
                    cmpa     #SAUCER_CYCLE          ; the cycle just restarted
                    bne      sm_fly
                    tst      sm_on
                    bne      sm_fly
                    jsr      saucers_visible
                    beq      sm_fly
                    ; aim: x
                    lda      rk_x
                    suba     sc_x                   ; rocket - saucer centre, mod 256 (both +8)
                    jsr      aim_axis
                    sta      sm_dx
                    ; y: rocket centre (row +8) vs saucer centre (row +4), mod 239, signed
                    lda      rk_y
                    adda     #4
                    suba     sc_y
                    bcc      sm_ay
                    adda     #FIELD_H
sm_ay               cmpa     #FIELD_H
                    blo      sm_ay2
                    suba     #FIELD_H
sm_ay2              cmpa     #FIELD_H/2             ; to signed -119..119
                    blo      sm_ay3
                    suba     #FIELD_H
sm_ay3              jsr      aim_axis
                    sta      sm_dy
                    lda      sc_x                   ; from the saucer's centre
                    adda     #8
                    clrb
                    std      sm_x
                    lda      sc_y
                    adda     #4
                    clrb
                    std      sm_y
                    lda      #MISSILE_LIFE
                    sta      sm_life
                    lda      #1
                    sta      sm_on
                    rts
sm_fly
                    tst      sm_on
                    beq      sm_done
                    dec      sm_life
                    bne      sm_move
                    clr      sm_on
                    rts
sm_move             lda      sm_dx
                    beq      sm_my
                    ldd      #MISSILE_SPEED
                    tst      sm_dx
                    bpl      sm_mx
                    ldd      #-MISSILE_SPEED
sm_mx               addd     sm_x
                    std      sm_x
sm_my               lda      sm_dy
                    beq      sm_done
                    ldd      #MISSILE_SPEED
                    tst      sm_dy
                    bpl      sm_my2
                    ldd      #-MISSILE_SPEED
sm_my2              ldx      #sm_y
                    jsr      add_y_wrap
sm_done             rts

; aim_axis: A = signed distance (target - source) -> A = -1, 0 or +1
aim_axis
                    tsta
                    bmi      aa_neg
                    cmpa     #AIM_NEAR
                    blo      aa_zero
                    lda      #1
                    rts
aa_neg              cmpa     #-AIM_NEAR
                    bgt      aa_zero
                    lda      #-1
                    rts
aa_zero             clra
                    rts

;***************************************************************************
; collisions: box tests with wrap (sync_star_board.vhd:596-662): the rocket's
; 16x16 grid, each saucer's 16x8 grid, missiles 1 px. Only one event at a time.
;***************************************************************************
collisions
                    tst      ev_timer
                    lbne     co_done
                    jsr      saucers_visible
                    lbeq     co_rocket_only
                    ; rocket missile in either saucer: a point for the rocket
                    tst      rm_on
                    beq      co_crash
                    lda      sc_y
                    sta      co_sy
                    jsr      co_missile_saucer
                    bne      co_rm_hit
                    jsr      second_saucer_y
                    sta      co_sy
                    jsr      co_missile_saucer
                    beq      co_crash
co_rm_hit           clr      rm_on
                    lda      score_rk               ; 0..99 (two digits; the original: 4-bit binary)
                    inca
                    cmpa     #100
                    blo      co_rm2
                    clra
co_rm2              sta      score_rk
                    lda      #EV_SAUCER
                    jmp      event_start
co_crash
                    ; rocket and a saucer collide: both hidden, no point
                    jsr      rocket_visible
                    beq      co_done
                    lda      sc_y
                    sta      co_sy
                    jsr      co_rocket_saucer
                    bne      co_crashed
                    jsr      second_saucer_y
                    sta      co_sy
                    jsr      co_rocket_saucer
                    beq      co_rocket_only
co_crashed          lda      #EV_CRASH
                    jmp      event_start
co_rocket_only
                    ; saucer missile in the rocket: a point for the saucers
                    tst      sm_on
                    beq      co_done
                    jsr      rocket_visible
                    beq      co_done
                    lda      sm_x
                    suba     rk_x
                    cmpa     #16
                    bhs      co_done
                    lda      sm_y
                    suba     rk_y
                    bcc      co_sm2
                    adda     #FIELD_H
co_sm2              cmpa     #16
                    bhs      co_done
                    clr      sm_on
                    lda      score_sc               ; 0..99 (two digits; the original: 0..9)
                    inca
                    cmpa     #100
                    blo      co_sm3
                    clra
co_sm3              sta      score_sc
                    lda      #EV_SPIN
                    jmp      event_start
co_done             rts

; second_saucer_y: A = the second copy's row, SAUCER_GAP rows on
second_saucer_y
                    lda      sc_y
                    adda     #SAUCER_GAP
                    bcs      ssy_wrap
                    cmpa     #FIELD_H
                    blo      ssy_ok
ssy_wrap            suba     #FIELD_H
ssy_ok              rts

; co_missile_saucer: Z clear if the rocket missile is in the saucer at (sc_x, co_sy)
co_missile_saucer
                    lda      rm_x
                    suba     sc_x
                    cmpa     #16
                    bhs      cms_no
                    lda      rm_y
                    suba     co_sy
                    bcc      cms_y
                    adda     #FIELD_H
cms_y               cmpa     #8
                    bhs      cms_no
                    lda      #1
                    rts
cms_no              clra
                    rts

; co_rocket_saucer: Z clear if the rocket's box overlaps the saucer at (sc_x, co_sy)
co_rocket_saucer
                    lda      sc_x                   ; x: either starts within the other
                    suba     rk_x
                    cmpa     #16
                    blo      crs_x_ok
                    lda      rk_x
                    suba     sc_x
                    cmpa     #16
                    bhs      crs_no
crs_x_ok            lda      co_sy                  ; y: saucer row within the rocket's 16,
                    suba     rk_y
                    bcc      crs_y1
                    adda     #FIELD_H
crs_y1              cmpa     #16
                    blo      crs_yes
                    lda      rk_y                   ; or the rocket's row within the saucer's 8
                    suba     co_sy
                    bcc      crs_y2
                    adda     #FIELD_H
crs_y2              cmpa     #8
                    bhs      crs_no
crs_yes             lda      #1
                    rts
crs_no              clra
                    rts

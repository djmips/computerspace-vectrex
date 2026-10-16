;***************************************************************************
; Computer Space sounds on the PSG (AY-3-8912). Included by computerspace.asm.
;
; The original (computer_space_sound.vhd, DarFPGA) mixes: a background
; drone and the thrust (shaped noise), the explosion (noise and a ~100 Hz
; wobble, decaying), and square-wave tones for turning and both missiles.
; Here:
;   channel A, tone:  the rocket missile while it flies, else the turn buzz
;   channel B, tone:  the saucer missile while it flies
;   channel C, noise: the drone during play; louder and brighter while
;                     thrusting; the explosion on the PSG envelope (one decay)
; Silent outside a game, as on the original.
;
; Call at the start of a frame, before any drawing: the PSG is written through
; VIA ports A and B, which the beam uses. Sound_Byte: A = register, B = value
; (it keeps the BIOS shadow at $C800). Only changed registers are written.
;***************************************************************************

PSG_MIXER           equ      %00011100              ; tones A, B on; noise on C; I/O A input (buttons)
; The tones (periods: 1.5 MHz / 16 / period) step through three periods, one at
; each of three points a frame (frame start, after the stars, after the
; saucers): the core's tones jump phase every frame (its position counters stop
; in vertical blanking), a rough tone; stepping the pitch approximates it.
; Each set averages to the core's pitch (all periods < 256: one register).
;   rocket missile: the core 954 Hz (missile counter bit 11, line rate / 16)
;   saucer missile: the core 3818 Hz (counter bit 9, line rate / 4)
;   turn beeps:     the core 1909 Hz (saucer counter bit 10, MB_K, line rate / 8)
VOL_RM              equ      9                      ; (11 was too loud on hardware)
VOL_SM              equ      8                      ; (10 was too loud on hardware)
VOL_TURN            equ      7
NOISE_DRONE         equ      31                     ; the background drone: low noise, quiet
VOL_DRONE           equ      4
NOISE_THRUST        equ      10                     ; thrust: brighter, louder
VOL_THRUST          equ      10
NOISE_BOOM          equ      31                     ; explosion: the lowest noise,
PSG_MIXER_BOOM      equ      %00011000              ; chopped by tone C (the AY ANDs tone and noise)
BOOM_TONE           equ      600                    ; + 0..510: a random 84..156 Hz rumble each frame
BOOM_LEN            equ      161                    ; frames: 0.38 s full, then a 2.84 s linear fade

;***************************************************************************
; sound_init: silence, mixer set
;***************************************************************************
sound_init
                    clr      wob_i
                    clr      snd_a
                    lda      #BOOM_LEN
                    sta      boom_i
                    lda      #$5A
                    sta      boom_rng
                    jsr      Clear_Sound
                    lda      #7
                    ldb      #PSG_MIXER
                    jmp      Sound_Byte

;***************************************************************************
; sound_update: once a frame, before drawing
;***************************************************************************
sound_update
                    tst      game_on
                    bne      su_game
                    lda      #BOOM_LEN              ; outside a game: all quiet
                    sta      boom_i
                    clr      snd_a
                    lda      #7
                    ldb      #PSG_MIXER
                    jsr      psg_set
                    clra
                    ldb      #0
                    jsr      psg_set_a8
                    lda      #9
                    clrb
                    jsr      psg_set
                    lda      #10
                    clrb
                    jmp      psg_set
su_game
                    jsr      wob_next               ; A = this point's pitch step
                    ; channel A: rocket missile, else the turn buzz
                    tst      rm_on
                    beq      su_turn
                    ldx      #wob_rm
                    ldb      a,x
                    clra
                    jsr      psg_tone_a
                    lda      #1
                    sta      snd_a
                    lda      #8
                    ldb      #VOL_RM
                    jsr      psg_set
                    bra      su_b
su_turn             lda      Vec_Btn_State
                    bita     #BTN_CCW+BTN_CW
                    beq      su_a_off
                    jsr      rocket_visible
                    beq      su_a_off
                    tst      rot_acc                ; beeps: on for the high half of the 9 Hz
                    bpl      su_a_off               ; rotate clock (memory_board.vhd:968-969)
                    lda      wob_i
                    ldx      #wob_tn
                    ldb      a,x
                    clra
                    jsr      psg_tone_a
                    lda      #2
                    sta      snd_a
                    lda      #8
                    ldb      #VOL_TURN
                    jsr      psg_set
                    bra      su_b
su_a_off            clr      snd_a
                    lda      #8
                    clrb
                    jsr      psg_set
su_b
                    ; channel B: saucer missile
                    ldb      #0
                    tst      sm_on
                    beq      su_b_vol
                    lda      wob_i
                    ldx      #wob_sm
                    ldb      a,x
                    lda      #2
                    jsr      psg_set
                    lda      #3
                    clrb
                    jsr      psg_set
                    ldb      #VOL_SM
su_b_vol            lda      #9
                    jsr      psg_set
                    ; channel C: the explosion (as the core's: held, then a long linear fade,
                    ; a low random rumble), else thrust, else the drone
                    lda      ev_timer
                    cmpa     #EV_LEN                ; a new explosion: (re)start it
                    bne      su_boom
                    clr      boom_i
su_boom             ldb      boom_i
                    cmpb     #BOOM_LEN
                    bhs      su_noise
                    ldx      #boom_vol
                    abx                             ; (B up to 160: not a signed b,x offset)
                    lda      ,x
                    inc      boom_i
                    tfr      a,b
                    lda      #10
                    jsr      psg_set
                    lda      #6
                    ldb      #NOISE_BOOM
                    jsr      psg_set
                    lda      #7
                    ldb      #PSG_MIXER_BOOM
                    jsr      psg_set
                    lda      boom_rng               ; this frame's rumble period
                    lsla
                    bcc      su_rng
                    eora     #$1D
su_rng              sta      boom_rng
                    tfr      a,b
                    clra
                    lslb
                    rola
                    addd     #BOOM_TONE
                    pshs     a
                    lda      #4
                    jsr      psg_set                ; B = fine
                    puls     b
                    lda      #5
                    jmp      psg_set                ; coarse
su_noise            lda      #7
                    ldb      #PSG_MIXER
                    jsr      psg_set
                    lda      Vec_Btn_State
                    bita     #BTN_THRUST
                    beq      su_drone
                    jsr      rocket_visible
                    beq      su_drone
                    lda      #6
                    ldb      #NOISE_THRUST
                    jsr      psg_set
                    lda      #10
                    ldb      #VOL_THRUST
                    jmp      psg_set
su_drone            lda      #6
                    ldb      #NOISE_DRONE
                    jsr      psg_set
                    lda      #10
                    ldb      #VOL_DRONE
                    jmp      psg_set

; wob_next: the next of the three pitch steps: A = wob_i (0..2)
wob_next
                    lda      wob_i
                    inca
                    cmpa     #3
                    blo      wn_ok
                    clra
wn_ok               sta      wob_i
                    rts

;***************************************************************************
; sound_wobble: between drawing stages (the PSG shares the VIA ports with the
; beam; the beam is off and still there): the next pitch of each sounding tone
;***************************************************************************
sound_wobble
                    jsr      wob_next
                    ldb      snd_a                  ; channel A: 1 rocket missile, 2 turn beeps
                    beq      sw_b
                    ldx      #wob_rm
                    cmpb     #1
                    beq      sw_a
                    ldx      #wob_tn
sw_a                ldb      a,x
                    pshs     a
                    clra                            ; register 0: fine period
                    jsr      psg_set
                    puls     a
sw_b                tst      sm_on
                    beq      sw_done
                    ldx      #wob_sm
                    ldb      a,x
                    lda      #2
                    jmp      psg_set
sw_done             rts

; the three periods of each tone (average frequency vs the core's)
wob_rm              DB       97,99,98               ; 966, 947, 957 Hz: 957 (954)
wob_sm              DB       24,25,25               ; 3906, 3750, 3750 Hz: 3802 (3818)
wob_tn              DB       48,49,50               ; 1953, 1913, 1875 Hz: 1914 (1909)

; boom_vol: the explosion's volume per frame (generated: 19 frames at 14, then
; amplitude 1 - k/142 as AY steps of ~3 dB, v = 14 + 2 log2(a))
boom_vol
                    DB       14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
                    DB       14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,14
                    DB       14,14,14,14,14,14,14,14,14,14,13,13,13,13,13,13
                    DB       13,13,13,13,13,13,13,13,13,13,13,13,13,13,13,13
                    DB       13,13,13,13,13,13,13,13,13,13,13,13,13,12,12,12
                    DB       12,12,12,12,12,12,12,12,12,12,12,12,12,12,12,12
                    DB       12,12,12,12,12,12,11,11,11,11,11,11,11,11,11,11
                    DB       11,11,11,11,11,11,11,10,10,10,10,10,10,10,10,10
                    DB       10,10,10,10,9,9,9,9,9,9,9,9,8,8,8,8
                    DB       8,8,8,7,7,7,7,6,6,6,5,5,4,4,3,2
                    DB       0

; psg_tone_a: channel A tone period D
psg_tone_a
                    pshs     a
                    lda      #0
                    jsr      psg_set                ; B = fine
                    puls     b
                    lda      #1
                    jmp      psg_set                ; coarse

; psg_set_a8: channel A volume B
psg_set_a8
                    lda      #8

; psg_set: PSG register A = B, only if it differs from the shadow
psg_set
                    ldx      #Vec_Snd_Shadow
                    cmpb     a,x
                    beq      ps_same
                    jmp      Sound_Byte
ps_same             rts

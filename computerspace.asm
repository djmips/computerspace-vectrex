;***************************************************************************
; Computer Space (Nutting Associates, 1971) for the Vectrex
;
; Single-bank 32K cartridge. Built with VIDE's assembler (Asmj) through the
; vecx-run kit: see build.ps1.
;***************************************************************************

                    INCLUDE  "VECTREX.I"

;***************************************************************************
; RAM
;***************************************************************************
                    BSS
                    ORG      $c880                  ; user RAM

frame_count         ds       1

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
; Code
;***************************************************************************
start
                    clr      frame_count

main
                    jsr      Wait_Recal             ; frame sync; exits with DP = $D0
                    inc      frame_count
                    jsr      Intensity_5F
                    lda      #$7f
                    sta      <VIA_t1_cnt_lo         ; scale
                    jsr      Reset0Ref              ; leaves the integrators held at zero (PCR $CC)
                    ldd      #0
                    jsr      Moveto_d               ; a move releases them ($CE); Draw_VLc does not
                    ldx      #placeholder
                    jsr      Draw_VLc
                    jsr      Reset0Ref              ; park the beam at the centre
                    bra      main

; Placeholder shape until the real artwork: a rocket-like arrow, nose up
placeholder
                    DB       3                      ; 4 vectors (count - 1)
                    DB       -40, 15                ; (dy, dx) from the nose
                    DB       10, -15
                    DB       -10, -15
                    DB       40, 15

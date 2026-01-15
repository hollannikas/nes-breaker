.segment "HEADER"
.byte "NES", $1A
.byte 1      ; 1 × 16KB PRG
.byte 0      ; 0 × CHR (CHR RAM)
.byte $00    ; mapper / mirroring
.byte $00
.res 8, 0

.segment "CODE"
; Reset Vector
RESET:
    SEI		; Disable IRQ
    CLD		; Clear decimal mode
    LDX #$FF
    TXS		; Initialize stack

    INX
    STX $2000	; Disable NMI
    STX $2001	; Disable rendering

FOREVER:
WAITVBLANK:
   BIT $2002
   BPL WAITVBLANK
   JMP FOREVER

NMI: 
   RTI

IRQ:
   RTI

; =====================
; VECTORS
; =====================
.segment "VECTORS"
.word NMI
.word RESET
.word IRQ

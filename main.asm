.segment "HEADER"
.byte $4E, $45, $53, $1A
.byte 2      ; 2 * 16KB PRG = 32KB
.byte 0      ; 0 × CHR (CHR RAM)
.byte $00    ; mapper / mirroring
.byte $00
.res 8, 0

.segment "CODE"
; Reset Vector
RESET:
    LDX #$00
    ; --- Wait for two VBlanks ---
PPUWARMUP:
    BIT $2002
    BPL PPUWARMUP
    INX
    CPX #$02
    BNE PPUWARMUP

    SEI		    ; Disable IRQ
    CLD		    ; Clear decimal mode
    LDX #$FF
    TXS		    ; Initialize stack

    INX
    STX $2000	; Disable NMI
    STX $2001	; Disable rendering

LoadPalette:
    LDA $2002   ; reset latch
    LDA #$3F
    STA $2006
    LDA #$00
    STA $2006

    LDX #$00
    LDA #$0F    ; Black
InitPaletteLoop:
    STA $2007
    INX
    CPX #$20    ; 32 entries
    BNE InitPaletteLoop

    ; Set Color 1 to White
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$01
    STA $2006
    LDA #$30        ; White
    STA $2007

    ; --- Load Graphics (CHR RAM) ---
    LDA $2002       ; reset latch
    LDA #$00
    STA $2006       ; PPU Addr $0000 (Start of Pattern Table)
    LDA #$00
    STA $2006

    ; 1. Clear Tile 0 (Make it empty/black)
    LDX #$00
ClearTile0:
    LDA #$00
    STA $2007
    INX
    CPX #$10        ; 16 bytes needed for one tile
    BNE ClearTile0

    ; 2. Load Tile 1 (Make it solid)
    ; Note: PPU Addr is already at $0010 after the previous loop writes
    LDX #$00
LoadTile1:
    LDA #$FF        ; Full pixel row (Solid)
    STA $2007
    INX
    CPX #$08
    BNE LoadTile1
    
    LDX #$00
ZeroPlane1:
    LDA #$00
    STA $2007
    INX
    CPX #$08
    BNE ZeroPlane1

    LDA $2002
    LDA #$20
    STA $2006
    LDA #$00
    STA $2006

    ; Clear Nametable (1024 bytes: 960 NT + 64 AT)
    LDX #$00
    LDY #$04        ; Loop 4 times (4 * 256 = 1024)
    LDA #$00        ; Tile 0 (Empty)
ClearNT:
    STA $2007
    INX
    BNE ClearNT
    DEY
    BNE ClearNT

    ; Draw One Tile at Top-Left ($2000)
    LDA $2002
    LDA #$20
    STA $2006
    LDA #$00
    STA $2006
    LDA #$01        ; Tile 1
    STA $2007

    LDA #%00001010  ; background on
    STA $2001

    ; --- Reset Scroll ---
    LDA $2002       ; Reset latch
    LDA #$00
    STA $2005       ; Scroll X
    STA $2005       ; Scroll Y

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

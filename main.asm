.segment "HEADER"
.byte $4E, $45, $53, $1A
.byte 2      ; 2 * 16KB PRG = 32KB
.byte 0      ; 0 × CHR (CHR RAM)
.byte $00    ; mapper / mirroring
.byte $00
.res 8, 0

.segment "ZEROPAGE"
sprite_x: .res 1
sprite_y: .res 1
buttons1: .res 1
nmi_ready: .res 1

.segment "OAM"
OAM_RAM: .res 256

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

    ; --- Clear OAM RAM ---
    LDY #$00
    LDA #$FF    ; Move to Y=$FF (off-screen)
ClearOAM:
    STA OAM_RAM, y
    INY
    INY
    INY
    INY
    BNE ClearOAM

    ; --- Setup First Sprite ---
    LDA #128
    STA sprite_x
    STA sprite_y
    STA OAM_RAM         ; Sprite 0 Y
    LDA #$01
    STA OAM_RAM+1       ; Sprite 0 Tile Index (Tile 1)
    LDA #$00
    STA OAM_RAM+2       ; Sprite 0 Attributes (Palette 0)
    LDA sprite_x
    STA OAM_RAM+3       ; Sprite 0 X

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

    ; Set Background Palette 0, Color 1 to White
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$01
    STA $2006
    LDA #$30        ; White
    STA $2007

    ; Set Sprite Palette 0, Color 1 to White
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$11        ; Address $3F11 (Sprite Palette 0, Color 1)
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

    LDA #%00011010  ; background on, sprites on
    STA $2001

    LDA #$80        ; Enable NMI
    STA $2000

    ; --- Reset Scroll ---
    LDA $2002       ; Reset latch
    LDA #$00
    STA $2005       ; Scroll X
    STA $2005       ; Scroll Y

FOREVER:
WAITVBLANK:
    LDA nmi_ready
    BEQ WAITVBLANK
    
    ; Clear NMI flag
    LDA #$00
    STA nmi_ready

    ; Read Controller 1
    JSR ReadController1

    ; Game Logic: Movement
CheckUp:
    LDA buttons1
    AND #%00001000      ; Up is 4th bit
    BEQ CheckDown
    DEC sprite_y
CheckDown:
    LDA buttons1
    AND #%00000100      ; Down is 3rd bit
    BEQ CheckLeft
    INC sprite_y
CheckLeft:
    LDA buttons1
    AND #%00000010      ; Left is 2nd bit
    BEQ CheckRight
    DEC sprite_x
CheckRight:
    LDA buttons1
    AND #%00000001      ; Right is 1st bit
    BEQ DoneInput
    INC sprite_x
DoneInput:

    ; Update OAM RAM
    LDA sprite_y
    STA OAM_RAM
    LDA sprite_x
    STA OAM_RAM+3

    JMP FOREVER

ReadController1:
    LDA #$01
    STA $4016
    LDA #$00
    STA $4016
    LDX #$08
ReadController1Loop:
    LDA $4016
    LSR A
    ROL buttons1
    DEX
    BNE ReadController1Loop
    RTS

NMI: 
    ; OAM DMA
    LDA #$00
    STA $2003
    LDA #$02
    STA $4014

    ; Set NMI Ready
    LDA #$01
    STA nmi_ready
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

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
game_state: .res 1
ptr: .res 2

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

    ; --- Setup Game State ---
    LDA #$00
    STA game_state

LoadPalettes:
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$00
    STA $2006

    LDX #$00
LoadPalettesLoop:
    LDA title_pal, x
    STA $2007
    INX
    CPX #$10
    BNE LoadPalettesLoop

    ; Set Sprite Palette 0, Color 1 to White for Gameplay
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$11
    STA $2006
    LDA #$30
    STA $2007

LoadCHR:
    LDA $2002
    LDA #$00
    STA $2006
    STA $2006
    
    LDA #<title_chr
    STA ptr
    LDA #>title_chr
    STA ptr+1

    LDX #$10    ; 16 pages of 256 bytes = 4096 bytes (4KB)
    LDY #$00
CopyCHRLoop:
    LDA (ptr), y
    STA $2007
    INY
    BNE CopyCHRLoop
    INC ptr+1
    DEX
    BNE CopyCHRLoop

LoadNametable:
    LDA $2002
    LDA #$20
    STA $2006
    LDA #$00
    STA $2006

    LDA #<title_nam
    STA ptr
    LDA #>title_nam
    STA ptr+1

    LDX #$04    ; 4 pages = 1024 bytes (Name + Attr tables)
    LDY #$00
CopyNAMLoop:
    LDA (ptr), y
    STA $2007
    INY
    BNE CopyNAMLoop
    INC ptr+1
    DEX
    BNE CopyNAMLoop

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

    ; Game Logic: Machine State
    LDA game_state
    BEQ StateTitle
    JMP StateGameplay

StateTitle:
    LDA buttons1
    AND #%00010000      ; Start is 5th bit
    BEQ DoneInput
    INC game_state      ; Transition to StateGameplay

    ; --- CLEAR SCREEN FOR GAMEPLAY ---
    ; Turn off rendering to safely clear memory
    LDA #$00
    STA $2001

    ; Clear Nametable ($2000-$23FF)
    LDA $2002
    LDA #$20
    STA $2006
    LDA #$00
    STA $2006

    LDX #$00
    LDY #$04        ; Loop 4 times (4 * 256 = 1024)
    LDA #$00        ; Blank Tile
ClearNTGame:
    STA $2007
    INX
    BNE ClearNTGame
    DEY
    BNE ClearNTGame

    ; Reset Scroll
    LDA $2002
    LDA #$00
    STA $2005
    STA $2005

    ; Turn rendering back on
    LDA #%00011010  ; background on, sprites on
    STA $2001

    JMP DoneInput

StateGameplay:
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

    LDA game_state
    BEQ SkipSpriteUpdate

    ; Update OAM RAM
    LDA sprite_y
    STA OAM_RAM
    LDA sprite_x
    STA OAM_RAM+3
SkipSpriteUpdate:

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
; DATA
; =====================
.segment "RODATA"
title_chr: .incbin "title.chr"
title_nam: .incbin "title.nam"
title_pal: .incbin "title.pal"

; =====================
; VECTORS
; =====================
.segment "VECTORS"
.word NMI
.word RESET
.word IRQ

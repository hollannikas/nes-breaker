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
map_row: .res 1
map_col: .res 1
tile_temp: .res 1
temp_coord: .res 1
col_x: .res 1
col_y: .res 1
col_box_x: .res 1
col_box_y: .res 1
col_box_w: .res 1
col_box_h: .res 1
point_x: .res 1
point_y: .res 1
player_dir: .res 1
music_ptr: .res 2
music_wait: .res 1
music_start_ptr: .res 2
slime_x: .res 1
slime_y: .res 1
slime_dir_x: .res 1
slime_dir_y: .res 1
frame_counter: .res 1

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

    ; --- Setup Meta Sprite Anchor ---
    LDA #128
    STA sprite_x
    STA sprite_y
    LDA #0
    STA player_dir
    
    LDA #64
    STA slime_x
    STA slime_y
    LDA #1
    STA slime_dir_x
    STA slime_dir_y
    LDA #0
    STA frame_counter
    
    ; Initialize OAM RAM for the 24 tiles (Layer 0: 0-11, Layer 1: 12-23)
    LDX #$00        ; OAM Index
    LDY #$00        ; Tile Index
InitPlayerSpritesLoop:
    LDA #$FF        ; Initial Y (Offscreen)
    STA OAM_RAM, x
    INX
    TYA             ; Tile Index (0-23)
    STA OAM_RAM, x
    INX
    ; Palette selection: If Tile Index < 12, use Pal 0, else Pal 1
    CPY #12
    BCC SetPal0
    LDA #$01        ; Palette 1
    JMP StorePal
SetPal0:
    LDA #$00        ; Palette 0
StorePal:
    STA OAM_RAM, x
    INX
    LDA #$FF        ; Initial X (Offscreen)
    STA OAM_RAM, x
    INX
    INY
    CPY #24
    BNE InitPlayerSpritesLoop

    ; --- APU Frame Counter IRQ Setup ---
    LDA #$0F
    STA $4015       ; Enable Sq1, Sq2, Tri, Noise
    LDA #$00
    STA $4017       ; 4-step sequence, IRQ enabled
    LDA #1          ; Title screen song
    JSR PlaySong
    CLI             ; Enable IRQs

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

LoadPlayerCHR:
    LDA $2002
    LDA #$10        ; Sprite Pattern Table starts at $1000
    STA $2006
    LDA #$00
    STA $2006
    
    LDA #<player_chr
    STA ptr
    LDA #>player_chr
    STA ptr+1

    ; We need 768 bytes now (48 tiles) to cover both right and left facing sprites.
    LDX #3      ; 3 pages (768 bytes)
    LDY #$00
CopyPlayerCHRLoop:
    LDA (ptr), y
    STA $2007
    INY
    BNE CopyPlayerCHRLoop
    INC ptr+1
    DEX
    BNE CopyPlayerCHRLoop

    ; Load Slime CHR immediately after player
    LDA #<slime_chr
    STA ptr
    LDA #>slime_chr
    STA ptr+1
    LDY #0
CopySlimeCHRLoop:
    LDA (ptr), y
    STA $2007
    INY
    CPY #64     ; 4 tiles = 64 bytes
    BNE CopySlimeCHRLoop

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

    LDA #$88        ; Enable NMI, Background $0000, Sprites $1000
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
    BNE StartPressed
    JMP DoneInput       ; Out of bounds branch fixed
StartPressed:
    INC game_state      ; Transition to StateGameplay

    LDA #2              ; Play gameplay song
    JSR PlaySong

    ; --- CLEAR SCREEN FOR GAMEPLAY ---
    ; Turn off NMI and rendering to safely clear memory and draw
    LDA #$00
    STA $2000           ; Disable NMI
    STA $2001           ; Disable rendering

    ; Load Custom Background CHR
    JSR LoadGameplayCHR

    ; Load Custom Background Palettes
    JSR LoadGameplayPalettes

    ; Draw our gameplay background map
    JSR DrawMap

    ; Draw background attributes
    JSR DrawAttributes

    ; Load 3 player colors into Sprite Palette 0 ($3F11 - $3F13)
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$11
    STA $2006
    
    LDA player_pal+0
    STA $2007
    LDA player_pal+1
    STA $2007
    LDA player_pal+2
    STA $2007

    ; Load 3 player colors into Sprite Palette 1 ($3F15 - $3F17)
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$15
    STA $2006

    LDA player_pal+3
    STA $2007
    LDA player_pal+4
    STA $2007
    LDA player_pal+5
    STA $2007

    ; Load 3 slime colors into Sprite Palette 2 ($3F19 - $3F1B)
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$19
    STA $2006

    LDA #$0F        ; Black outline
    STA $2007
    LDA #$2A        ; Green
    STA $2007
    LDA #$3A        ; Light Green
    STA $2007

    ; Reset Scroll
    LDA $2002
    LDA #$00
    STA $2005
    STA $2005

    ; Re-enable NMI and rendering
    LDA #$88        ; Enable NMI, Background $0000, Sprites $1000
    STA $2000
    LDA #%00011010  ; background on, sprites on
    STA $2001

    JMP DoneInput

StateGameplay:
    ; --- Vertical Movement Check ---
    LDA sprite_y
    STA temp_coord      ; Initial proposed Y

    LDA buttons1
    AND #%00001000      ; Up
    BEQ @not_up
    DEC temp_coord
    JMP @do_y_check
@not_up:
    LDA buttons1
    AND #%00000100      ; Down
    BEQ @no_y_move
    INC temp_coord

@do_y_check:
    ; Setup collision parameters for Y movement
    LDA sprite_x
    STA col_x
    LDA temp_coord
    STA col_y
    LDA #4
    STA col_box_x
    LDA #16
    STA col_box_y
    LDA #15
    STA col_box_w
    LDA #15
    STA col_box_h

    JSR CheckSpriteCollision
    BNE @no_y_move      ; Collision, don't move Y
    LDA temp_coord
    STA sprite_y        ; Apply Y movement
@no_y_move:

    ; --- Horizontal Movement Check ---
    LDA sprite_x
    STA temp_coord      ; Initial proposed X

    LDA buttons1
    AND #%00000010      ; Left
    BEQ @not_left
    DEC temp_coord
    LDA #1
    STA player_dir      ; Set direction to Left (1)
    JMP @do_x_check
@not_left:
    LDA buttons1
    AND #%00000001      ; Right
    BEQ @no_x_move
    INC temp_coord
    LDA #0
    STA player_dir      ; Set direction to Right (0)

@do_x_check:
    ; Setup collision parameters for X movement
    LDA temp_coord
    STA col_x
    LDA sprite_y
    STA col_y
    LDA #4
    STA col_box_x
    LDA #16
    STA col_box_y
    LDA #15
    STA col_box_w
    LDA #15
    STA col_box_h

    JSR CheckSpriteCollision
    BNE @no_x_move      ; Collision, don't move X
    LDA temp_coord
    STA sprite_x        ; Apply X movement
@no_x_move:

DoneInput:

    LDA game_state
    BEQ SkipSpriteUpdate

    JSR UpdateMetaSprite
    
    INC frame_counter
    LDA frame_counter
    AND #$01
    BNE @skip_slime_move
    JSR UpdateSlime
@skip_slime_move:
    JSR DrawSlime

SkipSpriteUpdate:

    JMP FOREVER

; -----------------------------------------
; Subroutine: UpdateMetaSprite
; Takes the root `sprite_x` and `sprite_y` 
; and mathematically offsets the 12 hardware 
; sprites to form a 24x32 character.
; -----------------------------------------
UpdateMetaSprite:
    LDX #$00        ; OAM offset (0, 4, 8, ... 92)
    LDY #$00        ; Tile loop counter (0 to 23)
UpdateGridLoop:
    ; We need to modulo the Tile Loop counter by 12, because both layers 
    ; stack on top of each other and follow the exact same 3x4 grid!
    TYA
Mod12Loop:
    CMP #12
    BCC CalcGrid
    SEC
    SBC #12
    JMP Mod12Loop

CalcGrid:
    ; A is now 0-11, representing the grid index
    ; Calculate row and column from A
    ; Let's save A
    PHA

    ; --- Calculate Y Offset ---
    ; Row = A / 3
    ; We do CMP on A (the modded offset)
    CMP #3
    BCC Row0
    CMP #6
    BCC Row1
    CMP #9
    BCC Row2
Row3:
    LDA sprite_y
    CLC
    ADC #24
    JMP SetY
Row2:
    LDA sprite_y
    CLC
    ADC #16
    JMP SetY
Row1:
    LDA sprite_y
    CLC
    ADC #8
    JMP SetY
Row0:
    LDA sprite_y
SetY:
    STA OAM_RAM, x

    ; --- Calculate X Offset ---
    ; Col = A % 3
    PLA              ; Restore A (modded offset 0-11)
ColLoop:
    CMP #3
    BCC SetColPos
    SEC
    SBC #3
    JMP ColLoop
SetColPos:
    ; A is now 0, 1, or 2
    ASL A
    ASL A
    ASL A           ; Multiply by 8
    CLC
    ADC sprite_x
    STA OAM_RAM+3, x

    ; --- Set Tile Index ---
    LDA player_dir
    BEQ @facing_right
    TYA
    CLC
    ADC #24
    JMP @store_tile
@facing_right:
    TYA
@store_tile:
    STA OAM_RAM+1, x

    ; Increment
    INX
    INX
    INX
    INX
    INY
    CPY #24         ; Ensure we update all 24 sprites
    BNE UpdateGridLoop
    RTS

UpdateSlime:
    ; --- X Movement ---
    LDA slime_x
    CLC
    ADC slime_dir_x
    STA temp_coord

    LDA temp_coord
    STA col_x
    LDA slime_y
    STA col_y
    LDA #2
    STA col_box_x
    STA col_box_y
    LDA #12
    STA col_box_w
    STA col_box_h

    JSR CheckSpriteCollision
    BNE @hit_wall_x
    LDA temp_coord
    STA slime_x
    JMP @done_x
@hit_wall_x:
    LDA slime_dir_x
    EOR #$FE
    STA slime_dir_x
@done_x:

    ; --- Y Movement ---
    LDA slime_y
    CLC
    ADC slime_dir_y
    STA temp_coord

    LDA slime_x
    STA col_x
    LDA temp_coord
    STA col_y
    LDA #2
    STA col_box_x
    STA col_box_y
    LDA #12
    STA col_box_w
    STA col_box_h

    JSR CheckSpriteCollision
    BNE @hit_wall_y
    LDA temp_coord
    STA slime_y
    JMP @done_y
@hit_wall_y:
    LDA slime_dir_y
    EOR #$FE
    STA slime_dir_y
@done_y:
    RTS

DrawSlime:
    ; Sprite 1 (Top Left)
    LDA slime_y
    STA OAM_RAM+96
    LDA #$30        ; Tile 48
    STA OAM_RAM+97
    LDA #$02        ; Palette 2
    STA OAM_RAM+98
    LDA slime_x
    STA OAM_RAM+99

    ; Sprite 2 (Top Right)
    LDA slime_y
    STA OAM_RAM+100
    LDA #$31        ; Tile 49
    STA OAM_RAM+101
    LDA #$02
    STA OAM_RAM+102
    LDA slime_x
    CLC
    ADC #8
    STA OAM_RAM+103

    ; Sprite 3 (Bottom Left)
    LDA slime_y
    CLC
    ADC #8
    STA OAM_RAM+104
    LDA #$32        ; Tile 50
    STA OAM_RAM+105
    LDA #$02
    STA OAM_RAM+106
    LDA slime_x
    STA OAM_RAM+107

    ; Sprite 4 (Bottom Right)
    LDA slime_y
    CLC
    ADC #8
    STA OAM_RAM+108
    LDA #$33        ; Tile 51
    STA OAM_RAM+109
    LDA #$02
    STA OAM_RAM+110
    LDA slime_x
    CLC
    ADC #8
    STA OAM_RAM+111
    RTS

PlaySong:
    PHA             ; Save song ID
    SEI             ; Disable interrupts to prevent race condition on music_ptr
    PLA
    CMP #0
    BNE @check_title
    ; Silence song
    LDA #<silence_seq
    STA music_ptr
    STA music_start_ptr
    LDA #>silence_seq
    STA music_ptr+1
    STA music_start_ptr+1
    JMP @done

@check_title:
    CMP #1
    BNE @check_gameplay
    LDA #<title_music_seq
    STA music_ptr
    STA music_start_ptr
    LDA #>title_music_seq
    STA music_ptr+1
    STA music_start_ptr+1
    JMP @done

@check_gameplay:
    LDA #<music_seq
    STA music_ptr
    STA music_start_ptr
    LDA #>music_seq
    STA music_ptr+1
    STA music_start_ptr+1

@done:
    LDA #0
    STA music_wait      ; Start immediately
    ; Silence channels to prevent hanging notes
    LDA #$30
    STA $4000           ; Silence Square 1
    STA $4004           ; Silence Square 2
    LDA #$00
    STA $4008           ; Silence Triangle
    STA $400C           ; Silence Noise

    CLI                 ; Re-enable interrupts
    RTS

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

LoadGameplayCHR:
    LDA $2002
    LDA #$00
    STA $2006
    LDA #$10        ; Start at tile index $01 (PPU address $0010)
    STA $2006
    
    LDA #<bg_tiles
    STA ptr
    LDA #>bg_tiles
    STA ptr+1

    LDY #$00
@loop:
    LDA (ptr), y
    STA $2007
    INY
    CPY #128        ; 8 tiles * 16 bytes = 128 bytes
    BNE @loop
    RTS

LoadGameplayPalettes:
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$00        ; Background palettes start at $3F00
    STA $2006
    LDX #$00
@loop:
    LDA game_bg_pal, x
    STA $2007
    INX
    CPX #16
    BNE @loop
    RTS

DrawMap:
    ; Set PPU address to $2000
    LDA $2002
    LDA #$20
    STA $2006
    LDA #$00
    STA $2006

    LDA #0
    STA map_row

@row_loop:
    ; --- Draw Top Half ---
    LDA #0
    STA map_col
@top_col_loop:
    ; Calculate map index: map_row * 16 + map_col
    LDA map_row
    ASL A
    ASL A
    ASL A
    ASL A           ; A = map_row * 16
    CLC
    ADC map_col     ; A = map_row * 16 + map_col
    TAX
    LDA game_map, x ; Get metatile type
    BNE @top_wall
    ; Floor top-half
    LDA #$01        ; Floor TL
    STA $2007
    LDA #$02        ; Floor TR
    STA $2007
    JMP @top_next
@top_wall:
    LDA #$05        ; Wall TL
    STA $2007
    LDA #$06        ; Wall TR
    STA $2007
@top_next:
    INC map_col
    LDA map_col
    CMP #16
    BNE @top_col_loop

    ; --- Draw Bottom Half ---
    LDA #0
    STA map_col
@bot_col_loop:
    ; Calculate map index: map_row * 16 + map_col
    LDA map_row
    ASL A
    ASL A
    ASL A
    ASL A           ; A = map_row * 16
    CLC
    ADC map_col     ; A = map_row * 16 + map_col
    TAX
    LDA game_map, x ; Get metatile type
    BNE @bot_wall
    ; Floor bottom-half
    LDA #$03        ; Floor BL
    STA $2007
    LDA #$04        ; Floor BR
    STA $2007
    JMP @bot_next
@bot_wall:
    LDA #$07        ; Wall BL
    STA $2007
    LDA #$08        ; Wall BR
    STA $2007
@bot_next:
    INC map_col
    LDA map_col
    CMP #16
    BNE @bot_col_loop

    INC map_row
    LDA map_row
    CMP #15
    BNE @row_loop
    RTS

DrawAttributes:
    ; Set PPU address to $23C0
    LDA $2002
    LDA #$23
    STA $2006
    LDA #$C0
    STA $2006

    LDA #0
    STA map_row     ; ar (0..7)
@ar_loop:
    LDA #0
    STA map_col     ; ac (0..7)
@ac_loop:
    ; Calculate offset: ar * 32 + ac * 2
    LDA map_row
    ASL A           ; ar * 2
    ASL A           ; ar * 4
    ASL A           ; ar * 8
    ASL A           ; ar * 16
    ASL A           ; ar * 32
    STA tile_temp   ; tile_temp = ar * 32

    LDA map_col
    ASL A           ; ac * 2
    CLC
    ADC tile_temp   ; A = ar * 32 + ac * 2
    TAX             ; X is the map index for TL

    ; 1. TL
    LDA game_map, x
    STA tile_temp   ; tile_temp = TL palette (0 or 1)

    ; 2. TR
    LDA game_map+1, x
    ASL A
    ASL A           ; Shift left by 2
    ORA tile_temp
    STA tile_temp   ; tile_temp = (TR << 2) | TL

    ; 3. BL and BR
    LDA map_row
    CMP #7          ; Is it the last attribute row?
    BNE @read_bl_br
    ; If ar == 7, BL and BR are floor (0)
    JMP @write_attr

@read_bl_br:
    ; BL index is X + 16
    LDA game_map+16, x
    ASL A
    ASL A
    ASL A
    ASL A           ; Shift left by 4
    ORA tile_temp
    STA tile_temp

    ; BR index is X + 17
    LDA game_map+17, x
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A           ; Shift left by 6
    ORA tile_temp
    STA tile_temp

@write_attr:
    LDA tile_temp
    STA $2007

    INC map_col
    LDA map_col
    CMP #8
    BNE @ac_loop

    INC map_row
    LDA map_row
    CMP #8
    BNE @ar_loop
    RTS

CheckPointCollision:
    ; Check if point_y is out of bounds
    LDA point_y
    CMP #240
    BCS @collision

    LSR A
    LSR A
    LSR A
    LSR A           ; A = row (0..14)
    ASL A
    ASL A
    ASL A
    ASL A           ; A = row * 16
    STA tile_temp

    LDA point_x
    LSR A
    LSR A
    LSR A
    LSR A           ; A = col (0..15)
    CLC
    ADC tile_temp   ; A = row * 16 + col
    TAX
    LDA game_map, x
    BEQ @no_collision

@collision:
    LDA #1
    RTS
@no_collision:
    LDA #0
    RTS

CheckSpriteCollision:
    ; Calculate X_start
    LDA col_x
    CLC
    ADC col_box_x
    STA point_x     ; point_x = X_start

    ; Calculate Y_start
    LDA col_y
    CLC
    ADC col_box_y
    STA point_y     ; point_y = Y_start

    ; Corner 1: Top-Left (X_start, Y_start)
    JSR CheckPointCollision
    BNE @collision_found

    ; Corner 2: Top-Right (X_end, Y_start)
    LDA point_x
    CLC
    ADC col_box_w
    STA point_x
    JSR CheckPointCollision
    BNE @collision_found

    ; Corner 3: Bottom-Right (X_end, Y_end)
    LDA col_y
    CLC
    ADC col_box_y
    CLC
    ADC col_box_h
    STA point_y
    JSR CheckPointCollision
    BNE @collision_found

    ; Corner 4: Bottom-Left (X_start, Y_end)
    LDA col_x
    CLC
    ADC col_box_x
    STA point_x
    ; point_y is already Y_end
    JSR CheckPointCollision
    BNE @collision_found

    ; No collision
    LDA #0
    RTS

@collision_found:
    LDA #1
    RTS


NMI: 
    ; OAM DMA
    LDA #$00
    STA $2003
    LDA #$02
    STA $4014

    ; Reset Scroll
    LDA $2002
    LDA #$00
    STA $2005
    STA $2005

    ; Set NMI Ready
    LDA #$01
    STA nmi_ready
    RTI

IRQ:
    PHA
    TXA
    PHA
    TYA
    PHA

    ; Acknowledge APU Frame Counter IRQ
    LDA $4015

    ; Decrement wait timer
    LDA music_wait
    BEQ _read_next
    DEC music_wait
    JMP _end_irq

_read_next:
    LDY #0
    LDA (music_ptr), Y
    BNE _process_frame
    ; If duration is 0, loop back to start
    LDA music_start_ptr
    STA music_ptr
    LDA music_start_ptr+1
    STA music_ptr+1
    LDA (music_ptr), Y

_process_frame:
    ; A has duration
    STA music_wait

    ; Melody (Square 1)
    INY
    LDA (music_ptr), Y
    BEQ _skip_sq1       ; If note 0, rest
    TAX
    LDA #$8F            ; Duty 10, volume 15
    STA $4000
    LDA note_periods_lo, X
    STA $4002
    LDA note_periods_hi, X
    STA $4003
    JMP _do_tri
_skip_sq1:
    LDA #$30            ; Volume 0, halt length counter
    STA $4000

_do_tri:
    ; Bass (Triangle)
    INY
    LDA (music_ptr), Y
    BEQ _skip_tri
    TAX
    LDA #$FF            ; Triangle linear counter max
    STA $4008
    LDA note_periods_lo, X
    STA $400A
    LDA note_periods_hi, X
    STA $400B
    JMP _do_noise
_skip_tri:
    LDA #$00
    STA $4008

_do_noise:
    ; Drum (Noise)
    INY
    LDA (music_ptr), Y
    BEQ _skip_noise
    TAX
    LDA #$0F            ; Noise volume 15
    STA $400C
    LDA noise_periods, X
    STA $400E
    LDA #$08            ; Length counter
    STA $400F
    JMP _advance
_skip_noise:
    LDA #$30
    STA $400C

_advance:
    ; Advance ptr by 4
    CLC
    LDA music_ptr
    ADC #4
    STA music_ptr
    BCC _end_irq
    INC music_ptr+1

_end_irq:
    PLA
    TAY
    PLA
    TAX
    PLA
    RTI

; =====================
; DATA
; =====================
.segment "RODATA"

note_periods_lo:
    .byte 0    ; 0: Rest
    ; C3 to B3
    .byte $56, $F9, $A6, $80, $3A, $FC, $C4
    ; C4 to B4
    .byte $AA, $7C, $52, $3F, $1C, $FD, $E1
    ; C5 to B5
    .byte $D4, $BD, $A8, $9F, $8D, $7E, $70

note_periods_hi:
    .byte 0
    ; C3 to B3
    .byte $03, $02, $02, $02, $02, $01, $01
    ; C4 to B4
    .byte $01, $01, $01, $01, $01, $00, $00
    ; C5 to B5
    .byte $00, $00, $00, $00, $00, $00, $00

noise_periods:
    .byte 0      ; 0: Rest
    .byte $04    ; 1: Kick / Low snare
    .byte $0C    ; 2: Hi-hat
    .byte $08    ; 3: Snare

silence_seq:
    .byte 255, 0, 0, 0
    .byte 0

title_music_seq:
    ; Dur, Sq1, Tri, Noise
    ; Measure 1: F Major
    .byte 12, 13, 4, 1   ; A4, F3, Kick
    .byte 12, 15, 4, 2   ; C5, F3, Hihat
    .byte 12, 18, 4, 3   ; F5, F3, Snare
    .byte 12, 15, 4, 2   ; C5, F3, Hihat

    ; Measure 2: G Major
    .byte 12, 14, 5, 1   ; B4, G3, Kick
    .byte 12, 16, 5, 2   ; D5, G3, Hihat
    .byte 12, 19, 5, 3   ; G5, G3, Snare
    .byte 12, 16, 5, 2   ; D5, G3, Hihat

    ; Measure 3: E Minor
    .byte 12, 12, 3, 1   ; G4, E3, Kick
    .byte 12, 14, 3, 2   ; B4, E3, Hihat
    .byte 12, 17, 3, 3   ; E5, E3, Snare
    .byte 12, 14, 3, 2   ; B4, E3, Hihat

    ; Measure 4: A Minor
    .byte 12, 15, 6, 1   ; C5, A3, Kick
    .byte 12, 17, 6, 2   ; E5, A3, Hihat
    .byte 12, 20, 6, 3   ; A5, A3, Snare
    .byte 12, 17, 6, 2   ; E5, A3, Hihat

    .byte 0              ; Loop

music_seq:
    ; Dur, Sq1, Tri, Noise
    ; Measure 1: C Major (C - E - G)
    .byte 15, 8, 1, 1    ; C4, C3, Kick
    .byte 15, 0, 0, 2    ; Rest, Rest, Hihat
    .byte 15, 10, 1, 3   ; E4, C3, Snare
    .byte 15, 12, 1, 2   ; G4, C3, Hihat

    ; Measure 2: G Major (G - B - D)
    .byte 15, 12, 5, 1   ; G4, G3, Kick
    .byte 15, 0, 0, 2    ; Rest, Rest, Hihat
    .byte 15, 9, 5, 3    ; D4, G3, Snare
    .byte 15, 14, 5, 2   ; B4, G3, Hihat

    ; Measure 3: A Minor (A - C - E)
    .byte 15, 13, 6, 1   ; A4, A3, Kick
    .byte 15, 0, 0, 2    ; Rest, Rest, Hihat
    .byte 15, 8, 6, 3    ; C4, A3, Snare
    .byte 15, 10, 6, 2   ; E4, A3, Hihat

    ; Measure 4: F Major (F - A - C)
    .byte 15, 11, 4, 1   ; F4, F3, Kick
    .byte 15, 0, 0, 2    ; Rest, Rest, Hihat
    .byte 15, 13, 4, 3   ; A4, F3, Snare
    .byte 15, 8, 4, 2    ; C4, F3, Hihat

    .byte 0              ; Loop

title_chr: .incbin "title.chr"
title_nam: .incbin "title.nam"
title_pal: .incbin "title.pal"
player_chr: .incbin "player.chr"
player_pal: .incbin "player.pal"
bg_tiles: .incbin "bg_tiles.chr"
slime_chr: .incbin "slime.chr"

game_bg_pal:
    ; Palette 0: Wooden Floor
    .byte $0F, $07, $17, $27
    ; Palette 1: Tile Wall (brick / stone wall)
    .byte $0F, $02, $12, $22 ; Blue/gray stone wall
    ; Palette 2: Unused
    .byte $0F, $00, $10, $30
    ; Palette 3: Unused
    .byte $0F, $0F, $0F, $0F

game_map:
    ; 15 rows of 16 metatiles. 0 = Wooden floor (passable), 1 = Tile wall (impassable)
    .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    .byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    .byte 1,0,1,1,0,0,1,1,1,1,0,0,1,1,0,1
    .byte 1,0,1,1,0,0,0,0,0,0,0,0,1,1,0,1
    .byte 1,0,0,0,0,1,1,0,0,1,1,0,0,0,0,1
    .byte 1,0,0,0,0,1,1,0,0,1,1,0,0,0,0,1
    .byte 1,0,1,1,0,0,0,0,0,0,0,0,1,1,0,1
    .byte 1,0,1,1,0,1,1,1,1,1,1,0,1,1,0,1
    .byte 1,0,0,0,0,1,1,1,1,1,1,0,0,0,0,1
    .byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    .byte 1,0,1,1,0,0,1,1,1,1,0,0,1,1,0,1
    .byte 1,0,1,1,0,0,1,1,1,1,0,0,1,1,0,1
    .byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    .byte 1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
    .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; =====================
; VECTORS
; =====================
.segment "VECTORS"
.word NMI
.word RESET
.word IRQ

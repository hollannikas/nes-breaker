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
buttons1_prev: .res 1
proj_active: .res 1
proj_x: .res 1
proj_y: .res 1
proj_dir: .res 1
proj_dist: .res 1
nmi_ready: .res 1
game_state: .res 1
ptr: .res 2
map_row: .res 1
map_col: .res 1
tile_temp: .res 1
irq_temp: .res 1
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
sq1_note: .res 1
tri_note: .res 1
noise_note: .res 1
player_hp: .res 1
player_score: .res 1
invuln_timer: .res 2
sfx_state: .res 1
sfx_timer: .res 1
sfx_mask: .res 1

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
    STA proj_active
    STA player_score
    
    LDA #64
    STA slime_x
    STA slime_y
    LDA #1
    STA slime_dir_x
    STA slime_dir_y
    LDA #0
    STA frame_counter
    
    LDA #100
    STA player_hp
    
    LDA #0
    STA invuln_timer
    STA invuln_timer+1
    STA sfx_state
    STA sfx_mask
    
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
    LDA #0
    STA $4015
    LDA #%00001111      ; Enable Square 1, Square 2, Triangle, Noise
    STA $4015
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

    ; Load UI CHR immediately after slime
    LDA #<ui_chr
    STA ptr
    LDA #>ui_chr
    STA ptr+1
    LDY #0
@loop1:
    LDA (ptr), y
    STA $2007
    INY
    BNE @loop1
    INC ptr+1
@loop2:
    LDA (ptr), y
    STA $2007
    INY
    CPY #112
    BNE @loop2

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
    CMP #1
    BEQ @is_gameplay
    CMP #2
    BEQ @is_gameover
    JMP StateTitle

@is_gameplay:
    JSR HandleProjectile
    JMP StateGameplay
@is_gameover:
    JMP StateGameOver

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

    ; Load 3 UI colors into Sprite Palette 3 ($3F1D - $3F1F)
    LDA $2002
    LDA #$3F
    STA $2006
    LDA #$1D
    STA $2006

    LDA #$30        ; White outline
    STA $2007
    LDA #$16        ; Red (Full block)
    STA $2007
    LDA #$26        ; Light Red (Highlight)
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
    JMP DoneInput

StateGameOver:
    LDA buttons1
    AND #%00010000      ; Start is 5th bit
    BNE @restart
    JMP DoneInput
@restart:
    JMP RESET

DoneInput:

    LDA game_state
    CMP #1
    BNE SkipSpriteUpdate

    JSR UpdateMetaSprite
    
    INC frame_counter
    LDA frame_counter
    AND #$01
    BNE @skip_slime_move
    JSR UpdateSlime
@skip_slime_move:
    JSR DrawSlime
    JSR CheckPlayerSlimeCollision
    JSR UpdateHPBar

SkipSpriteUpdate:

    JMP FOREVER

; -----------------------------------------
; Subroutine: UpdateMetaSprite
; Takes the root `sprite_x` and `sprite_y` 
; and mathematically offsets the 12 hardware 
; sprites to form a 24x32 character.
; -----------------------------------------
UpdateMetaSprite:
    ; If invuln_timer > 0, blink by hiding player every 4th frame
    LDA invuln_timer
    ORA invuln_timer+1
    BEQ @normal_draw
    
    LDA frame_counter
    AND #$04
    BNE @hide_player
@normal_draw:
    LDX #$00        ; OAM offset (0, 4, 8, ... 92)
    LDY #$00        ; Tile loop counter (0 to 23)
    JMP UpdateGridLoop

@hide_player:
    ; Move all player sprites offscreen
    LDX #0
@hide_loop:
    LDA #$FF
    STA OAM_RAM, x
    INX
    INX
    INX
    INX
    CPX #96         ; 24 sprites * 4 = 96
    BNE @hide_loop
    RTS

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

CheckPlayerSlimeCollision:
    ; Handle invulnerability timer
    LDA invuln_timer
    BNE @dec_timer
    LDA invuln_timer+1
    BNE @dec_timer_hi
    JMP @do_collision_check

@dec_timer_hi:
    DEC invuln_timer+1
@dec_timer:
    DEC invuln_timer
    RTS         ; Still invulnerable, skip collision

@do_collision_check:
    ; AABB Collision
    ; Player right (sprite_x + 19) <= Slime left (slime_x + 2)
    LDA sprite_x
    CLC
    ADC #19
    STA temp_coord
    LDA slime_x
    CLC
    ADC #2
    CMP temp_coord
    BCS @no_collision

    ; Slime right (slime_x + 14) <= Player left (sprite_x + 4)
    LDA slime_x
    CLC
    ADC #14
    STA temp_coord
    LDA sprite_x
    CLC
    ADC #4
    CMP temp_coord
    BCS @no_collision

    ; Player bottom (sprite_y + 31) <= Slime top (slime_y + 2)
    LDA sprite_y
    CLC
    ADC #31
    STA temp_coord
    LDA slime_y
    CLC
    ADC #2
    CMP temp_coord
    BCS @no_collision

    ; Slime bottom (slime_y + 14) <= Player top (sprite_y + 16)
    LDA slime_y
    CLC
    ADC #14
    STA temp_coord
    LDA sprite_y
    CLC
    ADC #16
    CMP temp_coord
    BCS @no_collision

    ; Collision!
    ; Set timer to 60 (1 second at 60 fps)
    LDA #<60
    STA invuln_timer
    LDA #>60
    STA invuln_timer+1

    ; Play Damage SFX (ID 1)
    LDA #1
    JSR PlaySFX

    ; Reduce HP
    LDA player_hp
    SEC
    SBC #20
    BCS @hp_ok
    LDA #0
@hp_ok:
    STA player_hp
    BEQ @game_over
    JMP @no_collision

@game_over:
    LDA #2
    STA game_state

    LDA #3
    JSR PlaySong    ; Play Game Over tune

    ; Hide all existing sprites
    LDX #0
@hide_all_loop:
    LDA #$FF
    STA OAM_RAM, x
    INX
    INX
    INX
    INX
    CPX #160
    BNE @hide_all_loop

    JSR DrawGameOverSprites

    LDA #%00010000  ; Enable sprites, disable background
    STA $2001
    
    ; Done processing collision
    JMP DoneInput

@no_collision:
    RTS

DrawGameOverSprites:
    ; G
    LDA #116        ; Y position
    STA OAM_RAM+160
    LDA #$39        ; G
    STA OAM_RAM+161
    LDA #$03        ; Palette 3
    STA OAM_RAM+162
    LDA #92         ; X position
    STA OAM_RAM+163

    ; A
    LDA #116
    STA OAM_RAM+164
    LDA #$3A        ; A
    STA OAM_RAM+165
    LDA #$03
    STA OAM_RAM+166
    LDA #100
    STA OAM_RAM+167

    ; M
    LDA #116
    STA OAM_RAM+168
    LDA #$3B        ; M
    STA OAM_RAM+169
    LDA #$03
    STA OAM_RAM+170
    LDA #108
    STA OAM_RAM+171

    ; E
    LDA #116
    STA OAM_RAM+172
    LDA #$3C        ; E
    STA OAM_RAM+173
    LDA #$03
    STA OAM_RAM+174
    LDA #116
    STA OAM_RAM+175

    ; O
    LDA #116
    STA OAM_RAM+176
    LDA #$3D        ; O
    STA OAM_RAM+177
    LDA #$03
    STA OAM_RAM+178
    LDA #132
    STA OAM_RAM+179

    ; V
    LDA #116
    STA OAM_RAM+180
    LDA #$3E        ; V
    STA OAM_RAM+181
    LDA #$03
    STA OAM_RAM+182
    LDA #140
    STA OAM_RAM+183

    ; E
    LDA #116
    STA OAM_RAM+184
    LDA #$3C        ; E
    STA OAM_RAM+185
    LDA #$03
    STA OAM_RAM+186
    LDA #148
    STA OAM_RAM+187

    ; R
    LDA #116
    STA OAM_RAM+188
    LDA #$3F        ; R
    STA OAM_RAM+189
    LDA #$03
    STA OAM_RAM+190
    LDA #156
    STA OAM_RAM+191

    RTS

PlaySFX:
    CMP #1
    BEQ @play_id1
    CMP #3
    BEQ @play_id3
    RTS
@play_id1:
    ; --- Damage SFX (Noise) ---
    LDA #1
    STA sfx_state
    LDA #$08        ; Mask Noise
    STA sfx_mask
    LDA #30         ; 30 frames
    STA sfx_timer
    
    ; Init hardware
    LDA #$3F
    STA $400C       ; Noise volume 15, envelope disable
    LDA #$08
    STA $400F       ; Length counter
    RTS
@play_id3:
    ; --- Boop SFX (Square 1) ---
    LDA #3
    STA sfx_state
    LDA #$01        ; Mask Sq1
    STA sfx_mask
    LDA #8          ; 8 frames
    STA sfx_timer
    
    ; Init hardware
    LDA #$BF
    STA $4000       ; Sq1 duty 50%, vol 15
    LDA #$00
    STA $4001       ; Sweep off
    LDA #$50        ; High pitch (timer = $0050)
    STA $4002
    LDA #$08
    STA $4003       ; Trigger
    RTS

UpdateHPBar:
    ; Draw Score Tens
    LDA player_score
    LSR A
    LSR A
    LSR A
    LSR A
    CLC
    ADC #$41        ; Tile index 65 ('0')
    STA OAM_RAM+145
    LDA #8          ; Y pos
    STA OAM_RAM+144
    LDA #$03        ; Palette 3
    STA OAM_RAM+146
    LDA #16         ; X pos
    STA OAM_RAM+147

    ; Draw Score Ones
    LDA player_score
    AND #$0F
    CLC
    ADC #$41        ; Tile index 65 ('0')
    STA OAM_RAM+149
    LDA #8          ; Y pos
    STA OAM_RAM+148
    LDA #$03        ; Palette 3
    STA OAM_RAM+150
    LDA #24         ; X pos
    STA OAM_RAM+151

    ; Draw 'H'
    LDA #0          ; Y position
    STA OAM_RAM+112
    LDA #$34        ; Tile for 'H'
    STA OAM_RAM+113
    LDA #$03        ; Palette 3
    STA OAM_RAM+114
    LDA #16         ; X position
    STA OAM_RAM+115

    ; Draw 'P'
    LDA #0          ; Y position
    STA OAM_RAM+116
    LDA #$35        ; Tile for 'P'
    STA OAM_RAM+117
    LDA #$03        ; Palette 3
    STA OAM_RAM+118
    LDA #24         ; X position
    STA OAM_RAM+119

    ; Calculate full double-blocks
    LDA player_hp
    LDX #0          ; FF block count
@div20_loop:
    CMP #20
    BCC @div20_done
    SBC #20
    INX
    JMP @div20_loop
@div20_done:
    STX tile_temp   ; tile_temp = number of FF tiles (0-5)
    
    ; A has the remainder (0-19)
    CMP #10
    BCC @rem_less_10
    ; 10-19 remainder means 1 more box is full (FE tile)
    LDA #$37        ; FE tile
    JMP @store_mid
@rem_less_10:
    ; 0-9 remainder means no extra full boxes (EE tile)
    LDA #$38        ; EE tile
@store_mid:
    STA temp_coord  ; Store the middle tile type
    
    LDY #0          ; Loop counter (0 to 4)
    LDA #36         ; Initial X position for the first block
    STA point_x     ; Just use point_x as temp X position
@draw_blocks_loop:
    ; Calculate OAM index: 120 + Y * 4
    TYA
    ASL A
    ASL A
    CLC
    ADC #120
    TAX             ; X = OAM index

    ; Y position
    LDA #0
    STA OAM_RAM, x
    
    ; Determine tile (FF vs FE vs EE)
    CPY tile_temp
    BCC @full_block
    BEQ @mid_block
    ; Empty block
    LDA #$38        ; EE tile
    JMP @set_tile
@mid_block:
    LDA temp_coord
    JMP @set_tile
@full_block:
    LDA #$36        ; FF tile
@set_tile:
    STA OAM_RAM+1, x
    
    ; Palette
    LDA #$03        ; Palette 3
    STA OAM_RAM+2, x
    
    ; X position
    LDA point_x
    STA OAM_RAM+3, x
    
    ; Advance X position by 8
    CLC
    ADC #8
    STA point_x
    
    INY
    CPY #5          ; Only 5 blocks to stay under 8-sprite limit
    BNE @draw_blocks_loop
    
    RTS

PlaySong:
    PHA             ; Save song ID
    SEI             ; Disable interrupts to prevent race condition on music_ptr
    PLA
    CMP #0
    BNE @chk_1
    LDA #<silence_seq
    STA music_start_ptr
    LDA #>silence_seq
    STA music_start_ptr+1
    JMP @init_music
@chk_1:
    CMP #1
    BNE @chk_2
    LDA #<title_music_seq
    STA music_start_ptr
    LDA #>title_music_seq
    STA music_start_ptr+1
    JMP @init_music
@chk_2:
    CMP #2
    BNE @chk_3
    LDA #<music_seq
    STA music_start_ptr
    LDA #>music_seq
    STA music_start_ptr+1
    JMP @init_music
@chk_3:
    CMP #3
    BNE @done
    LDA #<game_over_seq
    STA music_start_ptr
    LDA #>game_over_seq
    STA music_start_ptr+1
    JMP @init_music
@done:
    CLI
    RTS

@init_music:
    LDA music_start_ptr
    STA music_ptr
    LDA music_start_ptr+1
    STA music_ptr+1
    LDA #0
    STA music_wait      ; Start immediately
    STA sq1_note
    STA tri_note
    STA noise_note
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
    LDA buttons1
    STA buttons1_prev
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

HandleProjectile:
    ; Check for B button to shoot
    LDA buttons1_prev
    EOR #$FF        ; Invert
    AND buttons1
    AND #$40        ; B button
    BEQ UpdateProjectile
    
    ; B pressed this frame. Can we shoot?
    LDA proj_active
    BNE UpdateProjectile
    
    ; Spawn projectile
    LDA #1
    STA proj_active
    LDA sprite_x
    STA proj_x
    LDA sprite_y
    STA proj_y
    LDA player_dir  ; 0=Right, 1=Left
    STA proj_dir
    LDA #0
    STA proj_dist
    
UpdateProjectile:
    LDA proj_active
    BNE @active
    RTS
@active:
    ; Move 3 pixels based on dir (0=Right, 1=Left)
    LDA proj_dir
    CMP #0
    BEQ @move_right
    CMP #1
    BEQ @move_left
    RTS

@move_left:
    LDA proj_x
    SEC
    SBC #3
    STA proj_x
    JMP @moved
@move_right:
    LDA proj_x
    CLC
    ADC #3
    STA proj_x
    
@moved:
    LDA proj_dist
    CLC
    ADC #3
    STA proj_dist
    CMP #48         ; 3 * 16 pixels
    BCC @check_slime
    LDA #0
    STA proj_active
    RTS
    
@check_slime:
    ; AABB collision between proj and slime
    ; Proj box: proj_x+2 to proj_x+6, proj_y+2 to proj_y+6
    ; Slime box: slime_x to slime_x+16, slime_y to slime_y+16
    
    ; 1. proj_right < slime_left ?
    LDA proj_x
    CLC
    ADC #6
    CMP slime_x
    BCC @no_hit
    
    ; 2. proj_left > slime_right ?
    LDA slime_x
    CLC
    ADC #16
    CMP proj_x
    BCC @no_hit
    
    ; 3. proj_bottom < slime_top ?
    LDA proj_y
    CLC
    ADC #6
    CMP slime_y
    BCC @no_hit
    
    ; 4. proj_top > slime_bottom ?
    LDA slime_y
    CLC
    ADC #16
    CMP proj_y
    BCC @no_hit
    
    ; HIT!
    LDA #0
    STA proj_active
    
    ; Play SFX ID 3 (Boop)
    LDA #3
    JSR PlaySFX
    
    ; Increment Score (Pseudo-BCD)
    LDA player_score
    CLC
    ADC #1
    STA tile_temp
    AND #$0F
    CMP #$0A
    BCC @save_score
    
    LDA tile_temp
    CLC
    ADC #6
    STA tile_temp
    CMP #$A0
    BCC @save_score
    
    LDA #0
    STA tile_temp
@save_score:
    LDA tile_temp
    STA player_score
    
    ; Respawn Slime
    LDA sprite_x
    CMP #128
    BCS @spawn_left
    LDA #176
    STA slime_x
    JMP @y_check
@spawn_left:
    LDA #64
    STA slime_x
@y_check:
    LDA sprite_y
    CMP #120
    BCS @spawn_top
    LDA #192
    STA slime_y
    RTS
@spawn_top:
    LDA #32
    STA slime_y
    
@no_hit:
    ; Draw Projectile
    LDA proj_active
    BEQ @hide_proj
    LDA proj_y
    STA OAM_RAM+140
    LDA #$40        ; Tile index 64 (Star)
    STA OAM_RAM+141
    LDA #$03        ; Palette 3
    STA OAM_RAM+142
    LDA proj_x
    STA OAM_RAM+143
    RTS
@hide_proj:
    LDA #255
    STA OAM_RAM+140
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

    ; --- SFX ENGINE ---
    LDA sfx_state
    BEQ @process_music

    CMP #1
    BEQ @do_sfx1
    CMP #3
    BEQ @do_sfx3
    JMP @process_music

@do_sfx1:
    ; Damage SFX (Noise Sweep)
    DEC sfx_timer
    BEQ @end_sfx_noise
    LDA sfx_timer
    LSR A
    LSR A
    ORA #$01        ; Shift period down
    STA $400E
    JMP @process_music

@end_sfx_noise:
    LDA #$30
    STA $400C       ; Silence Noise
    JMP @end_sfx

@do_sfx3:
    ; Boop SFX (Square 1)
    DEC sfx_timer
    BEQ @end_sfx_sq1
    JMP @process_music

@end_sfx_sq1:
    LDA #$30
    STA $4000
    JMP @end_sfx

@end_sfx:
    LDA #0
    STA sfx_state
    STA sfx_mask

@process_music:
    ; Check wait timer
    LDA music_wait
    BNE _do_effects
    
_read_next:
    LDY #0
    LDA (music_ptr), Y
    BNE _process_fetch
    ; If duration is 0, loop back to start
    LDA music_start_ptr
    STA music_ptr
    LDA music_start_ptr+1
    STA music_ptr+1
    LDA (music_ptr), Y

_process_fetch:
    ; A has duration
    STA music_wait

    ; Fetch Melody (Square 1)
    INY
    LDA (music_ptr), Y
    STA sq1_note
    AND #$3F
    BEQ @skip_sq1_init
    TAX
    LDA note_periods_hi, X
    STA $4003
@skip_sq1_init:

    ; Fetch Bass (Triangle)
    INY
    LDA (music_ptr), Y
    STA tri_note
    BEQ @skip_tri_init
    TAX
    LDA note_periods_hi, X
    STA $400B
@skip_tri_init:

    ; Fetch Drum (Noise)
    INY
    LDA (music_ptr), Y
    STA noise_note
    BEQ @skip_noise_init
    
    LDA sfx_mask
    AND #$08
    BNE @skip_noise_init

    LDA noise_note
    TAX
    LDA #$05            ; envelope decay rate 5 (crisp hit)
    STA $400C
    LDA noise_periods, X
    STA $400E
    LDA #$08            ; length counter
    STA $400F
@skip_noise_init:

    ; Advance ptr by 4
    CLC
    LDA music_ptr
    ADC #4
    STA music_ptr
    BCC _do_effects
    INC music_ptr+1

_do_effects:
    DEC music_wait

    ; --- Square 1 (Melody) ---
    LDA sfx_mask
    AND #$01
    BNE _do_tri
    
    LDA sq1_note
    AND #$3F
    BEQ _skip_sq1
    TAX
    
    ; Duty Cycle Flip Effect
    LDA sq1_note
    AND #$80
    BEQ @no_duty_flip
    LDA frame_counter
    AND #$04
    BNE @duty1
@no_duty_flip:
    LDA #$BF            ; Duty 50%, volume 15
    JMP @set_duty
@duty1:
    LDA #$7F            ; Duty 25%, volume 15
@set_duty:
    STA $4000
    
    ; Vibrato Effect
    LDA note_periods_lo, X
    STA irq_temp
    
    LDA sq1_note
    AND #$40
    BEQ @no_vibrato
    LDA frame_counter
    AND #$02
    BEQ @no_vibrato
    INC irq_temp       ; Add 1 to pitch period
@no_vibrato:
    LDA irq_temp
    STA $4002
    JMP _do_tri
_skip_sq1:
    LDA #$30
    STA $4000

_do_tri:
    ; --- Triangle (Bass) ---
    LDA tri_note
    BEQ _skip_tri
    TAX
    LDA #$FF
    STA $4008
    LDA note_periods_lo, X
    STA $400A
    JMP _end_irq
_skip_tri:
    LDA #$00
    STA $4008

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
    ; A driving F Major - G Major - E Minor - A Minor arpeggio sequence
    ; Tempo: 6 frames per step
    
    ; Measure 1: F Major (F A C)
    .byte 6, 203, 4, 1   ; F4, F3, Kick
    .byte 6, 205, 0, 2   ; A4, Rest, Hihat
    .byte 6, 207, 0, 3   ; C5, Rest, Snare
    .byte 6, 210, 0, 2   ; F5, Rest, Hihat
    .byte 6, 207, 4, 1   ; C5, F3, Kick
    .byte 6, 205, 0, 2   ; A4, Rest, Hihat
    .byte 6, 210, 0, 3   ; F5, Rest, Snare
    .byte 6, 212, 0, 2   ; A5, Rest, Hihat

    ; Measure 2: G Major (G B D)
    .byte 6, 204, 5, 1   ; G4, G3, Kick
    .byte 6, 206, 0, 2   ; B4, Rest, Hihat
    .byte 6, 208, 0, 3   ; D5, Rest, Snare
    .byte 6, 211, 0, 2   ; G5, Rest, Hihat
    .byte 6, 208, 5, 1   ; D5, G3, Kick
    .byte 6, 206, 0, 2   ; B4, Rest, Hihat
    .byte 6, 211, 0, 3   ; G5, Rest, Snare
    .byte 6, 213, 0, 2   ; B5, Rest, Hihat

    ; Measure 3: E Minor (E G B)
    .byte 6, 202, 3, 1   ; E4, E3, Kick
    .byte 6, 204, 0, 2   ; G4, Rest, Hihat
    .byte 6, 206, 0, 3   ; B4, Rest, Snare
    .byte 6, 209, 0, 2   ; E5, Rest, Hihat
    .byte 6, 206, 3, 1   ; B4, E3, Kick
    .byte 6, 204, 0, 2   ; G4, Rest, Hihat
    .byte 6, 209, 0, 3   ; E5, Rest, Snare
    .byte 6, 211, 0, 2   ; G5, Rest, Hihat

    ; Measure 4: A Minor (A C E)
    .byte 6, 205, 6, 1   ; A4, A3, Kick
    .byte 6, 207, 0, 2   ; C5, Rest, Hihat
    .byte 6, 209, 0, 3   ; E5, Rest, Snare
    .byte 6, 212, 0, 2   ; A5, Rest, Hihat
    .byte 6, 209, 6, 1   ; E5, A3, Kick
    .byte 6, 207, 0, 2   ; C5, Rest, Hihat
    .byte 6, 212, 0, 3   ; A5, Rest, Snare
    .byte 6, 212, 0, 2   ; A5, Rest, Hihat
    .byte 0              ; Loop

music_seq:
    ; Slower driving bass for gameplay
    ; Measure 1: C Major (C E G)
    .byte 6, 143, 1, 1    ; C5, C3, Kick
    .byte 6, 143, 1, 2    ; C5, C3, Hihat
    .byte 6, 143, 8, 3    ; C5, C4, Snare (octave jump bass!)
    .byte 6, 143, 1, 2    ; C5, C3, Hihat
    .byte 6, 140, 1, 1    ; G4, C3, Kick
    .byte 6, 140, 1, 2    ; G4, C3, Hihat
    .byte 6, 140, 8, 3    ; G4, C4, Snare
    .byte 6, 140, 1, 2    ; G4, C3, Hihat

    ; Measure 2: G Major (G B D)
    .byte 6, 142, 5, 1    ; B4, G3, Kick
    .byte 6, 142, 5, 2    ; B4, G3, Hihat
    .byte 6, 142, 12, 3   ; B4, G4, Snare
    .byte 6, 142, 5, 2    ; B4, G3, Hihat
    .byte 6, 140, 5, 1    ; G4, G3, Kick
    .byte 6, 140, 5, 2    ; G4, G3, Hihat
    .byte 6, 140, 12, 3   ; G4, G4, Snare
    .byte 6, 140, 5, 2    ; G4, G3, Hihat

    ; Measure 3: F Major
    .byte 6, 141, 4, 1    ; A4, F3, Kick
    .byte 6, 141, 4, 2    ; A4, F3, Hihat
    .byte 6, 141, 11, 3   ; A4, F4, Snare
    .byte 6, 141, 4, 2    ; A4, F3, Hihat
    .byte 6, 139, 4, 1    ; F4, F3, Kick
    .byte 6, 139, 4, 2    ; F4, F3, Hihat
    .byte 6, 139, 11, 3   ; F4, F4, Snare
    .byte 6, 139, 4, 2    ; F4, F3, Hihat
    
    ; Measure 4: G Major
    .byte 6, 142, 5, 1    ; B4, G3, Kick
    .byte 6, 142, 5, 2    ; B4, G3, Hihat
    .byte 6, 142, 12, 3   ; B4, G4, Snare
    .byte 6, 142, 5, 2    ; B4, G3, Hihat
    .byte 6, 144, 5, 1    ; D5, G3, Kick
    .byte 6, 144, 5, 2    ; D5, G3, Hihat
    .byte 6, 144, 12, 3   ; D5, G4, Snare
    .byte 6, 144, 5, 2    ; D5, G3, Hihat

    .byte 0              ; Loop

game_over_seq:
    ; Sad A Minor arpeggio (A4 -> E4 -> C4 -> A3)
    .byte 20, 141, 6, 0    ; A4 (with vibrato/duty), A3 Bass
    .byte 20, 138, 0, 0    ; E4
    .byte 20, 136, 0, 0    ; C4
    .byte 90, 134, 6, 0    ; A3, A3 Bass
    .byte 255,  0, 0, 0    ; Silence
    .byte 0

title_chr: .incbin "title.chr"
title_nam: .incbin "title.nam"
title_pal: .incbin "title.pal"
player_chr: .incbin "player.chr"
player_pal: .incbin "player.pal"
bg_tiles: .incbin "bg_tiles.chr"
slime_chr: .incbin "slime.chr"
ui_chr: .incbin "ui.chr"

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

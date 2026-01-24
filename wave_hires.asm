// wave_hires.asm
// High Resolution Wave Simulator for C64

// --- constants ---
.const BITMAP_MEM = $2000
.const SCREEN_RAM = $0400

// --- zero page variables (safe zone only) ---
// Only 2-byte pointers that need indirect addressing modes
.label zp_draw_ptr   = $fb // 2 bytes - used for (indirect),y addressing
.label zp_temp_ptr   = $fd // 2 bytes - used for (indirect),y addressing

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

* = $4000

start:
    lda #0
    sta $d020    // border black

    jsr show_splash
    jsr init_tables
    jsr init_graphics

restart_sim:
    jsr init_graphics
    jsr init_physics
    jsr display_full 

wait_start:
    jsr $ffe4       // GETIN
    beq wait_start

loop:
    jsr solve
    jsr display_delta
    
    // Check key for restart or exit
    jsr $ffe4
    beq loop
    
    // Check if key is 1, 2, or 3
    cmp #$31        // '1' in ASCII
    beq key_1
    cmp #$32        // '2' in ASCII
    beq key_2
    cmp #$33        // '3' in ASCII
    beq key_3
    
    // Any other key exits
    jsr cleanup
    rts

key_1:
    lda #1
    sta config_select
    jmp restart_sim

key_2:
    lda #2
    sta config_select
    jmp restart_sim

key_3:
    lda #3
    sta config_select
    jmp restart_sim

// ----------------------------------------------------------------
// Initialization
// ----------------------------------------------------------------

init_tables:
    ldx #0          // Y coordinate 0..199
tloop:
    stx iter_h      
    lda #199
    sec
    sbc iter_h
    tay             // Y = Inverted Y (C64 bitmap 0,0 is top left)
    
    tya
    lsr
    lsr
    lsr 
    sta $fb         // Row = Y / 8
    
    tya
    and #7
    sta $fc         // Line = Y % 8
    
    // Base = $2000 + (Row * 320) + Line
    // Row * 320 = (Row * 256) + (Row * 64)
    lda $fb
    asl
    asl
    asl
    asl
    asl
    asl
    sta zp_temp_ptr     // Row * 64 Lo
    lda $fb
    lsr
    lsr
    sta zp_temp_ptr+1   // Row * 64 Hi

    lda zp_temp_ptr
    clc
    adc #<$2000
    sta zp_temp_ptr
    lda zp_temp_ptr+1
    adc $fb             // + (Row * 256)
    adc #>$2000
    sta zp_temp_ptr+1

    lda zp_temp_ptr
    clc
    adc $fc             // + Line offset
    ldx iter_h
    sta table_y_lo,x
    lda zp_temp_ptr+1
    adc #0
    sta table_y_hi,x
    
    inx
    cpx #200
    bne tloop
    rts

init_graphics:
    lda #0
    tay
    ldx #$20        // Clear $2000-$3FFF
clrbm:
    stx zp_temp_ptr+1
    sty zp_temp_ptr
!:  sta (zp_temp_ptr),y
    iny
    bne !-
    inx
    cpx #$40
    bne clrbm
    
    ldx #0          // Set screen colors (White on Black)
    lda #$10 
clrscr:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+$100,x
    sta SCREEN_RAM+$200,x
    sta SCREEN_RAM+$300,x
    inx
    bne clrscr

    lda $d011
    ora #%00100000  // Enable Bitmap Mode
    sta $d011
    lda #%00011000  // Bitmap $2000, Screen $0400
    sta $d018
    rts

init_physics:
    ldx #0
ploop:
    txa
    asl
    tay
    lda #0
    sta heights,y
    
    // Select initial heights based on config_select
    lda config_select
    cmp #1
    beq load_center_wave
    cmp #2
    beq load_shifted_wave
    cmp #3
    beq load_two_waves
    
    // Default to shifted_wave
    jmp load_shifted_wave

load_center_wave:
    lda init_heights_center_wave,x
    jmp store_height

load_shifted_wave:
    lda init_heights_shifted_wave,x
    jmp store_height

load_two_waves:
    lda init_heights_two_waves,x
    
store_height:
    sta heights+1,y
    sta display_heights,x // Match initial visual to physics
    sta target_h          // Use to draw initial column
    
    // Physics requires 0 velocity
    lda #0
    sta velocities,y
    sta velocities+1,y
    
    inx
    cpx #40
    bne ploop
    rts

cleanup:
    // 1. Reset Hardware to Text Mode
    lda #%00011011  
    sta $d011
    lda #%00010100  
    sta $d018

    // 2. Restore Colors
    lda #14         
    sta $d020
    lda #6          
    sta $d021
    lda #1          
    sta $0286
    
    jsr $ff81       // Screen Editor Initialization
    rts

// ----------------------------------------------------------------
// Splash Screen Strings
// ----------------------------------------------------------------

.encoding "screencode_upper" 

splash_text:
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "             WAVE SIMULATOR             "
    .text "                                        "
    .text "                   BY                   "
    .text "                                        "
    .text "            MATTHIAS MUELLER            "
    .text "                                        "
    .text "                                        "
    .text "           TEN MINUTE PHYSICS           "
    .text "         WWW.MATTHIASMUELLER.INFO       "
    .text "                                        "
    .text "                                        "
    .text " RESET DIFFERENT STATES WITH KEYS 1 - 3 "
    .text "     START / QUIT WITH ANY OTHER KEY    "
    .text "                                        "
    .text "           HAVE FUN WAVING!             "
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "                                        "
    .text "                                        "

// ----------------------------------------------------------------
// Splash Screen
// ----------------------------------------------------------------

show_splash:
    lda #0          // Black
    sta $d021       // Set background color register
    // Copy splash_text (1000 bytes = 25 lines * 40 chars) to SCREEN_RAM
    lda #<splash_text
    sta zp_temp_ptr
    lda #>splash_text
    sta zp_temp_ptr+1
    
    lda #<SCREEN_RAM
    sta zp_draw_ptr
    lda #>SCREEN_RAM
    sta zp_draw_ptr+1
    
    ldx #0              // Page counter
copy_loop:
    ldy #0              // Low byte counter
copy_page:
    lda (zp_temp_ptr),y
    sta (zp_draw_ptr),y
    iny
    bne copy_page
    
    // Next page
    inc zp_temp_ptr+1
    inc zp_draw_ptr+1
    inx
    cpx #4              // 4 pages covers 1024 bytes
    bne copy_loop
    
    // Copy remaining bytes up to 1000 (we copied 1024, so skip 24 bytes)
    // This is safer: just stop here since 1000 bytes is enough for 25 lines
    
done_copy:
    // Set color RAM for splash text (yellow = 7)
    lda #7
    ldx #0
clr_color_loop:
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    inx
    bne clr_color_loop
    
    // Wait for key
    lda #0
wait_for_key:
    jsr $ffe4           // GETIN
    beq wait_for_key
    
    rts

// ----------------------------------------------------------------
// Display Logic
// ----------------------------------------------------------------

display_full:
    lda #0
    sta x_counter
dfull_loop:
    // Calculate Bitmap Column Offset (X * 8)
    lda x_counter
    sta zp_col_offset
    lda #0
    sta zp_col_offset+1
    
    // Shift left 3 times (x8)
    asl zp_col_offset
    rol zp_col_offset+1
    asl zp_col_offset
    rol zp_col_offset+1
    asl zp_col_offset
    rol zp_col_offset+1
    
    // Target Height
    lda x_counter
    asl
    tay
    lda heights+1,y
    // Scale x2 (Double Visualization)
    cmp #100        // If >= 100, doubled value >= 200
    bcs full_max
    asl             // Double it
    jmp full_store
full_max:  
    lda #199
full_store:
    sta target_h
    
    // Reset display height to target
    ldx x_counter
    sta display_heights,x
    
    // If 0, skip
    lda target_h
    beq next_col_full
    
    // Draw 0..target_h - use table pointers directly
    lda #0
    sta iter_h

draw_full_pixel:
    ldy iter_h
    lda table_y_lo,y
    clc
    adc zp_col_offset
    sta zp_draw_ptr
    lda table_y_hi,y
    adc zp_col_offset+1
    sta zp_draw_ptr+1
    
    lda #$FF
    ldy #0
    sta (zp_draw_ptr),y
    
    inc iter_h
    lda iter_h
    cmp target_h
    bcc draw_full_pixel
    
next_col_full:
    inc x_counter
    lda x_counter
    cmp #40
    beq d_exit
    jmp dfull_loop
d_exit:
    rts

display_delta:
    lda #0
    sta x_counter
    sta zp_col_offset
    sta zp_col_offset+1
dloop:
    // Column base is already in zp_col_offset

    ldx x_counter
    lda display_heights,x
    sta current_h
    
    txa
    asl
    tay
    lda heights+1,y      // Get physics high byte
    // Scale x2 (Double Visualization)
    cmp #100             // If >= 100, doubled value >= 200
    bcs delta_max
    asl                  // Double it
    jmp delta_store
delta_max:  
    lda #199
delta_store:
    sta target_h
    
    cmp current_h
    beq next_col
    bcc draw_down

draw_up:
    lda #$FF
    sta fill_val
    lda current_h
    sta iter_h
    lda target_h
    sta limit_h
    jmp render_loop

draw_down:
    lda #0
    sta fill_val
    lda target_h
    sta iter_h
    lda current_h
    sta limit_h

render_loop:
    ldy iter_h
    lda table_y_lo,y
    clc
    adc zp_col_offset
    sta zp_draw_ptr
    lda table_y_hi,y
    adc zp_col_offset+1
    sta zp_draw_ptr+1

    lda fill_val
    ldy #0
    sta (zp_draw_ptr),y

    inc iter_h
    lda iter_h
    cmp limit_h
    bcc render_loop

    ldx x_counter
    lda target_h
    sta display_heights,x

next_col:
    // Advance column offset by 8
    lda zp_col_offset
    clc
    adc #8
    sta zp_col_offset
    bcc !+
    inc zp_col_offset+1
!:
    inc x_counter
    lda x_counter
    cmp #40
    beq done_delta
    jmp dloop
done_delta:
    rts

// ----------------------------------------------------------------
// Physics Engine
// ----------------------------------------------------------------

solve:
    jsr update_velocities
    jsr update_heights
    rts

update_velocities:
    // Sync boundaries for reflection
    lda heights
    sta left_boundary
    lda heights+1
    sta left_boundary+1
    
    lda heights+78
    sta right_boundary
    lda heights+79
    sta right_boundary+1

    ldx #0
uvloop:
    // (Left + Right)
    lda heights-2,x
    clc
    adc heights+2,x
    sta temp_sum
    lda heights-1,x
    adc heights+3,x
    sta temp_sum+1
    
    // / 2
    lsr temp_sum+1
    ror temp_sum
    
    // Accel = (Avg - Height) / 2
    lda temp_sum
    sec
    sbc heights,x
    sta temp_term
    lda temp_sum+1
    sbc heights+1,x
    sta temp_term+1
    
    // Inline divide_by_2
    // Corresponding to dt = 1/16 s, h = sqrt(2) m , c = 4 m/s 
    lda temp_term+1
    cmp #$80            // Sign to Carry
    ror temp_term+1
    ror temp_term
    
    // velocities += Accel
    lda velocities,x
    clc
    adc temp_term
    sta velocities,x
    lda velocities+1,x
    adc temp_term+1
    sta velocities+1,x

    // Inline dampen_velocity
    // Calculate delta = velocity >> 10
    lda velocities+1,x
    sta temp_term       // Start with v >> 8
    
    cmp #$80            // Sign to Carry
    ror temp_term       // v >> 9
    cmp #$80
    ror temp_term       // v >> 10
    
    // Sign extend delta high byte
    bmi !+
    lda #0
    beq !++
!:  lda #$FF
!:
    sta temp_term+1
    
    // velocity -= delta
    lda velocities,x
    sec
    sbc temp_term
    sta velocities,x
    lda velocities+1,x
    sbc temp_term+1
    sta velocities+1,x

    inx
    inx
    cpx #80
    bne uvloop
    rts

update_heights:
    ldx #0
hloop:
    lda velocities,x
    sta temp_acc
    lda velocities+1,x
    sta temp_acc+1
    
    // Inline Divide by 16 (ASR 4 times)
    // This corresponds to dt = 1/16 s
    
    // Shift 1
    lda temp_acc+1
    cmp #$80        // Copy Sign Bit to Carry
    ror temp_acc+1
    ror temp_acc
    
    // Shift 2
    lda temp_acc+1
    cmp #$80
    ror temp_acc+1
    ror temp_acc
    
    // Shift 3
    lda temp_acc+1
    cmp #$80
    ror temp_acc+1
    ror temp_acc
    
    // Shift 4
    lda temp_acc+1
    cmp #$80
    ror temp_acc+1
    ror temp_acc
    
    lda heights,x
    clc
    adc temp_acc
    sta heights,x
    lda heights+1,x
    adc temp_acc+1
    sta heights+1,x

    // Simple Clamping
    bpl !+
    lda #0
    sta heights,x
    sta heights+1,x
    jmp next_h
!:  lda heights+1,x
    cmp #200
    bcc next_h
    lda #199
    sta heights+1,x
    lda #0
    sta heights,x

next_h:
    inx
    inx
    cpx #80
    bne hloop
    rts


// ----------------------------------------------------------------
// Data
// ----------------------------------------------------------------

left_boundary:  .word 0
heights:        .fill 80, 0
right_boundary: .word 0
velocities:     .fill 80, 0
display_heights:.fill 40, 0

table_y_lo:     .fill 200, 0
table_y_hi:     .fill 200, 0

init_heights_center_wave: // Initial heights high byte (40 bytes)
    .byte  10,  11,  12,  15,  18,  21,  27,  32,  37,  43
    .byte  49,  55,  61,  66,  72,  75,  79,  82,  84,  85
    .byte  85,  84,  82,  79,  75,  72,  66,  61,  55,  49
    .byte  43,  37,  32,  27,  21,  18,  15,  12,  11,  10

init_heights_shifted_wave: // Initial heights high byte (40 bytes)
    .byte  20,  20,  20,  20,  20,  20,  20,  20,  20,  20
    .byte  20,  21,  22,  24,  28,  31,  36,  42,  47,  53
    .byte  59,  65,  71,  76,  82,  85,  89,  92,  94,  95
    .byte  95,  94,  92,  89,  85,  82,  76,  71,  65,  59

init_heights_two_waves: // 40 bytes: Two humps at the ends (all values +10)
    .byte  20,  28,  40,  52,  58,  58,  52,  40,  28,  22
    .byte  20,  20,  20,  20,  20,  20,  20,  20,  20,  20
    .byte  20,  20,  20,  20,  20,  20,  20,  22,  28,  40
    .byte  52,  58,  58,  52,  40,  28,  20,  20,  20,  20
    
init_heights_ramp: // 40 bytes: Linear ramp from 10 to 100
    .byte  10,  12,  15,  17,  20,  22,  25,  27,  30,  32
    .byte  35,  37,  40,  42,  45,  47,  50,  52,  55,  57
    .byte  60,  62,  65,  67,  70,  72,  75,  77,  80,  82
    .byte  85,  87,  90,  92,  95,  97, 100, 100, 100, 100
    
// ----------------------------------------------------------------
// Runtime Variables (Safe RAM, not Zero Page)
// ----------------------------------------------------------------
x_counter:      .byte 0
iter_h:         .byte 0
target_h:       .byte 0
current_h:      .byte 0
fill_val:       .byte 0
limit_h:        .byte 0
zp_col_offset:  .word 0
temp_sum:       .word 0
temp_term:      .word 0
temp_acc:       .word 0
temp_shift:     .word 0
config_select:  .byte 0

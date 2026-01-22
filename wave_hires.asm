// wave_hires.asm
// High Resolution Wave Simulator for C64
// Fixes: Register preservation, sign-extended shifts, and column loop logic.

// --- constants ---
.const BITMAP_MEM = $2000
.const SCREEN_RAM = $0400

// --- zero page variables ---
// Physics and Display counters
.label x_counter     = $02 
.label iter_h        = $03
.label target_h      = $04
.label current_h     = $05
.label fill_val      = $06
.label limit_h       = $07

// Addressing pointers
.label zp_col_offset = $08 // 2 bytes
.label zp_draw_ptr   = $0a // 2 bytes
.label zp_temp_ptr   = $0c // 2 bytes

// Math variables
.label temp_sum      = $0e // 2 bytes
.label temp_term     = $10 // 2 bytes
.label temp_acc      = $12 // 2 bytes

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

* = $4000

start:
    // 1. Setup
    lda #0 
    sta $d020    
    sta $d021    

    jsr show_splash
    jsr init_tables
    jsr init_graphics
    jsr init_physics
    
    // Draw initial state robustly
    jsr display_full 

wait_start:
    jsr $ffe4       // GETIN
    beq wait_start

loop:
    jsr solve
    jsr display_delta
    
    // Check key to exit
    jsr $ffe4
    beq loop
    
    jsr cleanup
    rts

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
//    lda init_heights_dambreak,x
    lda init_heights_shifted_wave,x
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
    lda $d011
    and #%11011111
    sta $d011
    lda #%00010100 
    sta $d018
    jsr $e544
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
    .text "           TEN MINUTE PHYSICS           "
    .text "         WWW.MATTHIASMUELLER.INFO       "
    .text "                                        "
    .text "  CHOOSE INITIAL STATE WITH KEYS 1 - 3  "
    .text "          EXIT WITH THE Q KEY           "
    .text "                                        "
    .text "           HAVE FUN WAVING!             "
    .text "                                        "
    .text "                                        "
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
    // Copy splash_text (1000 bytes = 25 lines * 40 chars) to SCREEN_RAM
    lda #<splash_text
    sta zp_temp_ptr
    lda #>splash_text
    sta zp_temp_ptr+1
    
    lda #<SCREEN_RAM
    sta zp_draw_ptr
    lda #>SCREEN_RAM
    sta zp_draw_ptr+1
    
    ldx #0              // High byte counter
    ldy #0              // Low byte counter
copy_loop:
    lda (zp_temp_ptr),y
    sta (zp_draw_ptr),y
    iny
    bne copy_loop
    
    // Next page
    inc zp_temp_ptr+1
    inc zp_draw_ptr+1
    inx
    cpx #4              // 4 pages covers 1000 bytes (pages 0-3)
    bne copy_loop
    
    // Copy remaining 232 bytes (1000 - 768)
    ldy #0
copy_final:
    cpy #232
    beq done_copy
    lda (zp_temp_ptr),y
    sta (zp_draw_ptr),y
    iny
    bne copy_final
    
done_copy:
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
    
    // Draw 0..target_h
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
dloop:
    // Calculate column base (X * 8)
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

    ldx x_counter
    lda display_heights,x
    sta current_h
    
    txa
    asl
    tay
    lda heights+1,y  // Get physics high byte
    // Scale x2 (Double Visualization)
    cmp #100        // If >= 100, doubled value >= 200
    bcs delta_max
    asl             // Double it
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
    inc x_counter
    lda x_counter
    cmp #40
    bne dloop
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
    stx x_counter
    txa
    asl
    tay
    
    // (Left + Right)
    lda heights-2,y
    clc
    adc heights+2,y
    sta temp_sum
    lda heights-1,y
    adc heights+3,y
    sta temp_sum+1
    
    // / 2
    lsr temp_sum+1
    ror temp_sum
    
    // Accel = (Avg - Height) / 2
    lda temp_sum
    sec
    sbc heights,y
    sta temp_term
    lda temp_sum+1
    sbc heights+1,y
    sta temp_term+1
    
    jsr divide_by_2
    
    ldx x_counter
    txa
    asl
    tay
    lda velocities,y
    clc
    adc temp_acc
    sta velocities,y
    lda velocities+1,y
    adc temp_acc+1
    sta velocities+1,y

    inx
    cpx #40
    bne uvloop
    rts

update_heights:
    ldx #0
hloop:
    stx x_counter
    txa
    asl
    tay
    lda velocities,y
    sta temp_term
    lda velocities+1,y
    sta temp_term+1
    
    jsr divide_by_16
    
    ldx x_counter
    txa
    asl
    tay
    lda heights,y
    clc
    adc temp_acc
    sta heights,y
    lda heights+1,y
    adc temp_acc+1
    sta heights+1,y

    // Simple Clamping
    bpl !+
    lda #0
    sta heights,y
    sta heights+1,y
    jmp next_h
!:  lda heights+1,y
    cmp #200
    bcc next_h
    lda #199
    sta heights+1,y
    lda #0
    sta heights,y

next_h:
    inx
    cpx #40
    bne hloop
    rts

// Signed Division Subroutines
divide_by_2:
    lda temp_term+1
    asl             // Carry = sign bit
    lda temp_term+1
    ror             // Shift sign back in
    sta temp_acc+1
    lda temp_term
    ror
    sta temp_acc
    rts

divide_by_16:
    lda temp_term+1
    sta temp_acc+1
    lda temp_term
    sta temp_acc
    ldy #4
div_loop:
    lda temp_acc+1
    asl
    lda temp_acc+1
    ror
    sta temp_acc+1
    lda temp_acc
    ror
    sta temp_acc
    dey
    bne div_loop
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

init_heights_wave: // Initial heights high byte (40 bytes)
    .byte   0,   1,   3,   6,  10,  15,  22,  29,  36,  44
    .byte  52,  60,  68,  75,  82,  87,  92,  96,  99, 100
    .byte 100,  99,  96,  92,  87,  82,  75,  68,  60,  52
    .byte  44,  36,  29,  22,  15,  10,   6,   3,   1,   0

init_heights_shifted_wave: // Initial heights high byte (40 bytes)
    .byte   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
    .byte   0,   1,   3,   6,  10,  15,  22,  29,  36,  44
    .byte  52,  60,  68,  75,  82,  87,  92,  96,  99, 100
    .byte 100,  99,  96,  92,  87,  82,  75,  68,  60,  52

init_heights_dambreak: // Initial heights high byte (40 bytes)
    .byte 100, 100, 100, 100, 100,  10,  10,  10,  10,  10
    .byte  10,  10,  10,  10,  10,  10,  10,  10,  10,  10
    .byte  10,  10,  10,  10,  10,  10,  10,  10,  10,  10
    .byte  10,  10,  10,  10,  10,  10,  10,  10,  10,  10

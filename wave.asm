// Variables - Moved to Zero Page ($02-$10)
.label xpos          = $02
.label ypos          = $03
.label colorpos      = $04 // 2 bytes
.label scaled_height = $06
.label temp_sum      = $07
.label temp_term     = $08
.label target        = $09
.label prev_scaled   = $10 // 40 bytes ($10 to $37)

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

.const AIR_COLOR   = 14 
.const WATER_COLOR = 6  
.const SOLID_CHAR  = 160 // Solid block
.const DEFAULT_TEXT_COLOR = 14

* = $c000
start:  
    lda #AIR_COLOR
    sta $d020
    sta $d021
    jsr init
    
wait_start:
    jsr $ffe4
    beq wait_start

mainloop:
    jsr solve
    jsr display
    jsr $ffe4
    beq mainloop
    jmp exit

exit:
    jsr cleanup
    rts

init:
    // 1. Clear simulation data
    ldx #0
init_sim_loop:
    lda initheights,x
    sta heights,x
    lda #0
    sta velocities,x
    sta prev_scaled,x // Initialize previous display state to 0
    inx
    cpx #40
    bne init_sim_loop

    // 2. Prepare Screen: Fill with solid blocks and air color
    ldx #0
init_scr_loop:
    lda #SOLID_CHAR
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $06e8,x // Screen is 1000 chars ($03e8)
    lda #AIR_COLOR
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne init_scr_loop
    rts

display:
    ldx #0
col_loop:
    stx xpos
    
    // Compute new scaled height (0-24)
    lda heights,x
    lsr; lsr; lsr
    cmp #25
    bcc ok
    lda #24
ok: sta scaled_height

    // Compare with what is currently on screen
    ldy xpos
    cmp prev_scaled,y
    beq next_col        // No change in this column
    bcs grow_water      // New height is higher -> add water color

shrink_water:
    // Change WATER to AIR from prev down to new
    lda prev_scaled,x
    sta temp_term       // Current row pointer
shrink_loop:
    ldy temp_term
    jsr color_air_at_xy
    dec temp_term
    lda temp_term
    cmp scaled_height
    bne shrink_loop
    beq update_prev     // Done with column

grow_water:
    // Change AIR to WATER from prev up to new
    lda prev_scaled,x
    sta temp_term
grow_loop:
    inc temp_term       // Start one above previous
    ldy temp_term
    jsr color_water_at_xy
    lda temp_term
    cmp scaled_height
    bne grow_loop

update_prev:
    ldx xpos
    lda scaled_height
    sta prev_scaled,x

next_col:
    ldx xpos
    inx
    cpx #40
    bne col_loop
    rts

// --- Fast Coloring Subroutines ---

color_water_at_xy:
    lda #WATER_COLOR
    .byte $2c           // BIT trick to skip next LDA
color_air_at_xy:
    lda #AIR_COLOR
    sta target          // Store color to write

    // Calculate Row: 24 - Y (Y is in register Y)
    tya 
    eor #$ff            // Fast "24 - Y" approximation or use SEC/SBC
    clc
    adc #25             // Now A = 24 - Y
    tay

    // Use Lookup Table for Color RAM
    lda color_lo,y
    sta colorpos
    lda color_hi,y
    sta colorpos+1
    
    ldy xpos
    lda target
    sta (colorpos),y
    rts

// --- Physics Logic (Same as before) ---

solve:
    jsr updatevelocities
    jsr updateheights
    rts

updatevelocities:
    lda heights
    sta leftboundary
    lda heights+39
    sta rightboundary
    ldx #0
uvloop:
    lda heights-1,x
    lsr 
    adc #0 
    sta temp_sum
    lda heights+1,x
    lsr
    clc
    adc temp_sum
    sta temp_sum
    lda heights,x
    sta temp_term
    lda temp_sum
    sec
    sbc temp_term
    clc
    adc velocities,x
    sta velocities,x
    inx
    cpx #40
    bne uvloop
    rts

updateheights:
    ldx #0
hloop:
    lda velocities,x
    clc
    cmp #$80
    ror; ror; ror       // Delta = velocity / 8
    sta temp_term   
    lda velocities,x 
    bmi neg_vel
pos_vel:
    lda heights,x
    clc
    adc temp_term
    bcs clamp_255
    jmp store_height
neg_vel:
    lda heights,x
    clc
    adc temp_term
    bcc clamp_0
    jmp store_height
clamp_255: lda #255: jmp store_height
clamp_0:   lda #0
store_height:
    sta heights,x
    inx
    cpx #40
    bne hloop
    rts

cleanup:
    lda #DEFAULT_TEXT_COLOR
    sta $0286 
    jsr $e544 
    rts

// --- Data Section ---

leftboundary:  .byte 0
heights:       .fill 40, 0 
rightboundary: .byte 0
velocities:    .fill 40, 0
initheights:   .fill 10, 200, .fill 30, 40

// Row Lookup Tables for Color RAM ($D800)
color_lo: .fill 25, <($d800 + i * 40)
color_hi: .fill 25, >($d800 + i * 40)

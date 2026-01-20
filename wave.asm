// Variables - Moved to Zero Page ($02-$08)
.label xpos     = $02
.label ypos     = $03
.label char_pos  = $04 // Takes 2 bytes ($04 and $05)
.label color_pos = $06 // Takes 2 bytes ($06 and $07)
.label scaled_height = $09
.label temp_sum = $0a
.label temp_term = $0b
.label current_h_iter = $0c
.label end_h_val = $0d
.label fill_color_val = $0e

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

.const AIR_COLOR   = 14 
.const WATER_COLOR = 6  
.const DEFAULT_TEXT_COLOR = 14 // Or 1 for white

* = $c000
start:  
    // Optional: Set background and border to light blue (Sky)
    lda #AIR_COLOR
    sta $d020
    sta $d021

    jsr init
    jsr display
    
wait_start:
    jsr $ffe4       // GETIN
    beq wait_start

main_loop:
    jsr solve
    jsr display

    jsr $ffe4       // GETIN
    beq main_loop    // No key? Continue
    jmp exit        // Key pressed? Exit

exit:
    jsr cleanup
    rts

init:
    // Clear Screen to Solid Block (160)
    ldx #0
    lda #160 // Solid Block
clear_loop:
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear_loop

    ldx #0
init_loop:
    lda init_heights,x
    sta heights,x
    
    lda #0
    sta velocities,x
    sta display_heights,x
    
    inx
    cpx #40
    bne init_loop
    rts

cleanup:
    // 1. Reset the KERNAL cursor color
    lda #DEFAULT_TEXT_COLOR
    sta $0286 

    // 2. Clear the screen (optional but helpful)
    // This calls the KERNAL routine to clear screen and reset pointers
    jsr $e544 
    
    // 3. Reset border/background to default if you changed them
    lda #14 // Light Blue border
    sta $d020
    lda #6  // Blue background
    sta $d021
    rts

display:
    ldx #0
    stx xpos
disp_loop:
    ldx xpos
    lda heights,x
    lsr
    lsr
    lsr
    sta scaled_height // New Height

    lda display_heights,x // Old Height
    cmp scaled_height
    beq update_done     // Equal, nothing to do

    bcc rising_water    // Old < New

falling_water:
    // Old > New.
    // Range: [New, Old). Color: AIR.
    
    lda #AIR_COLOR
    sta fill_color_val

    lda scaled_height
    sta current_h_iter // Start
    lda display_heights,x
    sta end_h_val     // End
    jmp start_fill

rising_water:
    // Old < New.
    // Range: [Old, New). Color: WATER.
    
    lda #WATER_COLOR
    sta fill_color_val

    lda display_heights,x
    sta current_h_iter
    lda scaled_height
    sta end_h_val

start_fill:
    // Loop h from current_h_iter to end_h_val - 1
fill_loop:
    lda current_h_iter
    cmp end_h_val
    bcs fill_done

    // Calculate Row = 24 - h
    lda #24
    sec
    sbc current_h_iter
    tay // Y = Row Index

    // Setup Pointer
    lda row_lo,y
    sta color_pos
    lda row_hi,y
    sta color_pos+1
    
    // Write Color
    ldy xpos  // Column Index
    lda fill_color_val
    sta (color_pos),y
    
    inc current_h_iter
    jmp fill_loop

fill_done:
    // Update displayheights
    ldx xpos
    lda scaled_height
    sta display_heights,x

update_done:
    inc xpos
    lda xpos
    cmp #40
    bne disp_loop
    rts

solve:
    jsr update_velocities
    jsr update_heights

    rts


update_velocities:
    // reflecting boundaries
    lda heights
    sta left_boundary
    lda heights+39
    sta right_boundary
    
    ldx #0
uvloop:

    // Calculate Average of Neighbors
    lda heights-1,x
    clc
    adc heights+1,x
    ror               // A = (Left + Right) / 2
    sta temp_sum
    
    lda heights,x
    sta temp_term
    lda temp_sum
    sec
    sbc temp_term

    jsr mult_by_timestep

    clc
    adc velocities,x
    sta velocities,x

    inx
    cpx #40
    bne uvloop
    rts

update_heights:
    ldx #0
hloop:
    lda velocities,x // Check sign of velocity (and delta)
    jsr mult_by_timestep
    sta temp_term
    lda heights,x
    clc
    adc temp_term
    
    // Clamp to [0, 200]
    bmi clamp_to_zero    // If negative (bit 7 set), clamp to 0
    cmp #201
    bcs clamp_to_200     // If >= 201, clamp to 200
    jmp store_height
    
clamp_to_zero:
    lda #0
    jmp store_height
    
clamp_to_200:
    lda #200
    
store_height:
    sta heights,x

    inx
    cpx #40
    bne hloop
    rts

mult_by_timestep: // simply divide by 16 with rounding toward zero
    bpl positive   
    clc
    adc #3         // add 7 to round toward zero
        
positive:
    // Now do 2 arithmetic right shifts (divide by 16) 
    cmp #$80       
    ror
    cmp #$80
    ror
    rts    

left_boundary:
    .byte 0
heights:
    .fill 40, 0 
right_boundary:
    .byte 0

display_heights:
    .fill 40, 0 

init_heights:
    .fill 5, 10
    .fill 5, 30
    .fill 5, 50
    .fill 5, 70
    .fill 5, 100
    .fill 5, 70
    .fill 5, 30
    .fill 5, 10
    
velocities:
    .fill 40, 0

// Tables for Color RAM rows
row_lo:
    .fill 25, <($d800 + i*40)
row_hi:
    .fill 25, >($d800 + i*40)
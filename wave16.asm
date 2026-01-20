// Variables - Moved to Zero Page ($02-$1f)
.label xpos     = $02
.label ypos     = $03
.label char_pos  = $04 // Takes 2 bytes ($04 and $05)
.label color_pos = $06 // Takes 2 bytes ($06 and $07)
.label scaled_height = $09
.label current_h_iter = $0c
.label end_h_val = $0d
.label fill_color_val = $0e

// 16-bit temporaries
.label temp_sum_lo = $10
.label temp_sum_hi = $11
.label temp_term_lo = $12
.label temp_term_hi = $13
.label temp_avg_lo = $14
.label temp_avg_hi = $15
.label temp_acc_lo = $16
.label temp_acc_hi = $17

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

wait_key:
    jsr $ffe4       // GETIN
    beq wait_key    // No key? Wait
    cmp #$51        // Check if 'Q' (PETSCII 81)
    beq exit        // If 'Q', exit
    jmp main_loop   // Otherwise, continue simulation

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
    lda init_heights_lo,x
    sta heights_lo,x
    lda init_heights_hi,x
    sta heights_hi,x
    
    lda #0
    sta velocities_lo,x
    sta velocities_hi,x
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
    lda heights_hi,x    // Use high byte of 16-bit height
    lsr
    lsr
    lsr
    sta scaled_height // New Height (0-25 range)

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
    lda heights_lo
    sta left_boundary_lo
    lda heights_hi
    sta left_boundary_hi
    lda heights_lo+39
    sta right_boundary_lo
    lda heights_hi+39
    sta right_boundary_hi
    
    ldx #0
uvloop:
    // Calculate Average of Neighbors: (Left + Right) / 2
    // Add lo bytes
    lda heights_lo-1,x
    clc
    adc heights_lo+1,x
    sta temp_sum_lo
    
    // Add hi bytes with carry
    lda heights_hi-1,x
    adc heights_hi+1,x
    sta temp_sum_hi
    
    // Divide by 2 (16-bit right shift)
    lsr temp_sum_hi
    ror temp_sum_lo
    
    // Subtract current height: avg - heights[x]
    lda temp_sum_lo
    sec
    sbc heights_lo,x
    sta temp_term_lo
    
    lda temp_sum_hi
    sbc heights_hi,x
    sta temp_term_hi
    
    // Multiply by timestep (divide by 16)
    jsr mult_by_timestep_16
    
    // Add to velocity
    lda temp_acc_lo
    clc
    adc velocities_lo,x
    sta velocities_lo,x
    
    lda temp_acc_hi
    adc velocities_hi,x
    sta velocities_hi,x

    inx
    cpx #40
    bne uvloop
    rts

update_heights:
    ldx #0
hloop:
    // Load velocity into temp for timestep multiply
    lda velocities_lo,x
    sta temp_term_lo
    lda velocities_hi,x
    sta temp_term_hi
    
    // Multiply by timestep (divide by 16)
    jsr mult_by_timestep_16
    
    // Add to height
    lda heights_lo,x
    clc
    adc temp_acc_lo
    sta temp_sum_lo
    
    lda heights_hi,x
    adc temp_acc_hi
    sta temp_sum_hi
    
    // Clamp to [0, $C800] (0 to 51200, which is 200*256)
    // Check if negative (bit 7 of hi byte)
    lda temp_sum_hi
    bmi clamp_to_zero
    
    // Check if > $C800 (hi > $C8 or hi==$C8 and lo > 0)
    cmp #$C9
    bcs clamp_to_max
    cmp #$C8
    bne store_height
    lda temp_sum_lo
    cmp #$01
    bcs clamp_to_max
    lda temp_sum_hi  // Restore hi byte
    jmp store_height
    
clamp_to_zero:
    lda #0
    sta temp_sum_lo
    sta temp_sum_hi
    jmp store_height
    
clamp_to_max:
    lda #$00
    sta temp_sum_lo
    lda #$C8
    sta temp_sum_hi
    
store_height:
    lda temp_sum_lo
    sta heights_lo,x
    lda temp_sum_hi
    sta heights_hi,x

    inx
    cpx #40
    bne hloop
    rts

// 16-bit signed divide by 16 (arithmetic right shift 4 times)
// Input: temp_term_lo/hi, Output: temp_acc_lo/hi
mult_by_timestep_16:
    lda temp_term_lo
    sta temp_acc_lo
    lda temp_term_hi
    sta temp_acc_hi
    
    // Do 4 arithmetic right shifts
    // Shift 1
    lda temp_acc_hi
    cmp #$80
    ror temp_acc_hi
    ror temp_acc_lo
    
    // Shift 2
    lda temp_acc_hi
    cmp #$80
    ror temp_acc_hi
    ror temp_acc_lo
    
    // Shift 3
    lda temp_acc_hi
    cmp #$80
    ror temp_acc_hi
    ror temp_acc_lo
    
    // Shift 4
    lda temp_acc_hi
    cmp #$80
    ror temp_acc_hi
    ror temp_acc_lo
    
    rts    

left_boundary_lo:
    .byte 0
left_boundary_hi:
    .byte 0
    
heights_lo:
    .fill 40, 0 
heights_hi:
    .fill 40, 0
    
right_boundary_lo:
    .byte 0
right_boundary_hi:
    .byte 0

display_heights:
    .fill 40, 0 

// Initial heights scaled by 256 for 16-bit (low bytes)
init_heights_lo:
    .byte   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
    .byte   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
    .byte   0,   0,   0,   0,   0,   0,   0,   0,   0,   0
    .byte   0,   0,   0,   0,   0,   0,   0,   0,   0,   0

// Initial heights scaled by 256 for 16-bit (high bytes)
init_heights_hi:
    .byte   0,   1,   3,   6,  10,  15,  22,  29,  36,  44
    .byte  52,  60,  68,  75,  82,  87,  92,  96,  99, 100
    .byte 100,  99,  96,  92,  87,  82,  75,  68,  60,  52
    .byte  44,  36,  29,  22,  15,  10,   6,   3,   1,   0
        
velocities_lo:
    .fill 40, 0
velocities_hi:
    .fill 40, 0

// Tables for Color RAM rows
row_lo:
    .fill 25, <($d800 + i*40)
row_hi:
    .fill 25, >($d800 + i*40)
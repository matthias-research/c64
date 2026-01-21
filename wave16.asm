// Variables - Moved to Zero Page ($02-$1f)
.label xpos     = $02
.label ypos     = $03
.label char_pos  = $04 // Takes 2 bytes ($04 and $05)
.label color_pos = $06 // Takes 2 bytes ($06 and $07)
.label frame_counter = $08
.label scaled_height = $09
.label current_h_iter = $0c
.label end_h_val = $0d
.label fill_color_val = $0e

// 16-bit temporaries (2 bytes each, interleaved lo/hi)
.label temp_sum = $10   // Takes 2 bytes ($10=lo, $11=hi)
.label temp_term = $12  // Takes 2 bytes ($12=lo, $13=hi)
.label temp_avg = $14   // Takes 2 bytes ($14=lo, $15=hi)
.label temp_acc = $16   // Takes 2 bytes ($16=lo, $17=hi)
.label offset = $18     // For x*2 calculations

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
    beq wait_start  // Wait for key press to start

main_loop:
    jsr solve
    jsr display
    jsr update_timer

    jsr $ffe4       // GETIN - Check if key pressed
    bne exit        // If any key pressed, exit
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
    // Calculate offset = x * 2
    txa
    asl
    tay
    
    // Lo byte = 0
    lda #0
    sta heights,y
    sta velocities,y
    
    // Hi byte from init_heights
//    lda init_heights_dambreak,x
    lda init_heights_shifted_wave,x
    sta heights+1,y
    
    // Clear velocities hi byte
    lda #0
    sta velocities+1,y
    
    // Clear display_heights
    sta display_heights,x
    
    inx
    cpx #40
    bne init_loop
    
    // Initialize frame counter
    lda #0
    sta frame_counter
    
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

update_timer:
    inc frame_counter    // Increment the counter
    lda frame_counter    // Load it
    and #%00000111       // Mask to get 0-7
    clc
    adc #48              // Add '0' to get PETSCII digit
    sta $0400            // Store at top-left corner (screen memory)
    
    lda #1               // White color
    sta $d800            // Store at top-left corner (color memory)
    rts

display:
    ldx #0
    stx xpos
disp_loop:
    ldx xpos
    txa
    asl
    tay
    
    lda heights+1,y    // Use high byte of 16-bit height
    lsr
    lsr
    lsr
    sta scaled_height // New Height (0-25 range)

    ldx xpos
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
    lda heights+1
    sta left_boundary+1
    lda heights+78  // 39*2 = 78
    sta right_boundary
    lda heights+79  // 39*2+1 = 79
    sta right_boundary+1
    
    ldx #0
uvloop:
    // Calculate offset = x * 2
    txa
    asl
    sta offset
    
    // Calculate Average of Neighbors: (Left + Right) / 2
    // Left neighbor offset = (x-1)*2 = offset - 2
    // Right neighbor offset = (x+1)*2 = offset + 2
    
    // Add lo bytes
    ldy offset
    lda heights-2,y  // Left neighbor lo
    clc
    adc heights+2,y  // Right neighbor lo
    sta temp_sum
    
    // Add hi bytes with carry
    lda heights-1,y  // Left neighbor hi
    adc heights+3,y  // Right neighbor hi
    sta temp_sum+1
    
    // Divide by 2 (16-bit right shift)
    lsr temp_sum+1
    ror temp_sum
    
    // Subtract current height: avg - heights[x]
    lda temp_sum
    sec
    sbc heights,y
    sta temp_term
    
    lda temp_sum+1
    sbc heights+1,y
    sta temp_term+1
    
    // Δt × c² / (Δx)² = (1/16) × 16 / 2 = 1/2 (wave speed: 2√2 columns/timestep)
    jsr divide_by_2
    
    // Add to velocity
    ldy offset
    lda temp_acc
    clc
    adc velocities,y
    sta velocities,y
    
    lda temp_acc+1
    adc velocities+1,y
    sta velocities+1,y

    inx
    cpx #40
    bne uvloop
    rts

update_heights:
    ldx #0
hloop:
    // Calculate offset = x * 2
    txa
    asl
    tay
    
    // Load velocity into temp for timestep multiply
    lda velocities,y
    sta temp_term
    lda velocities+1,y
    sta temp_term+1
    
    // we use a time step of 1/16
    jsr divide_by_16
    
    // Add to height
    lda heights,y
    clc
    adc temp_acc
    sta temp_sum
    
    lda heights+1,y
    adc temp_acc+1
    sta temp_sum+1
    
    // Clamp to [0, $C800] (0 to 51200, which is 200*256)
    // Check if negative (bit 7 of hi byte)
    lda temp_sum+1
    bmi clamp_to_zero
    
    // Check if > $C800 (hi > $C8 or hi==$C8 and lo > 0)
    cmp #$C9
    bcs clamp_to_max
    cmp #$C8
    bne store_height
    lda temp_sum
    cmp #$01
    bcs clamp_to_max
    lda temp_sum+1  // Restore hi byte
    jmp store_height
    
clamp_to_zero:
    lda #0
    sta temp_sum
    sta temp_sum+1
    jmp store_height
    
clamp_to_max:
    lda #$00
    sta temp_sum
    lda #$C8
    sta temp_sum+1
    
store_height:
    lda temp_sum
    sta heights,y
    lda temp_sum+1
    sta heights+1,y

    inx
    cpx #40
    bne hloop
    rts

// 16-bit signed divide by 16 (arithmetic right shift 4 times)
// Input: temp_term, Output: temp_acc
divide_by_16:
    lda temp_term
    sta temp_acc
    lda temp_term+1
    sta temp_acc+1
    
    // Do 4 arithmetic right shifts
    // Shift 1
    lda temp_acc+1
    cmp #$80
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
    
    rts    

// 16-bit signed divide by 2
// Input: temp_term, Output: temp_acc
divide_by_2:
    lda temp_term+1
    cmp #$80
    ror
    sta temp_acc+1
    lda temp_term
    ror
    sta temp_acc
    rts    

// Boundary values (2 bytes each)
left_boundary:
    .byte 0, 0
    
// Heights array: 40 elements * 2 bytes = 80 bytes (interleaved lo/hi)
heights:
    .fill 80, 0 
    
right_boundary:
    .byte 0, 0

display_heights:
    .fill 40, 0 

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
    .byte  10,  10,  10,  10,  10,  10,  10,  10,  10,  10
    .byte  10,  10,  10,  10,  10, 100, 100, 100, 100, 100
    .byte 100, 100, 100, 100, 100,  10,  10,  10,  10,  10
    .byte  10,  10,  10,  10,  10,  10,  10,  10,  10,  10
            
// Velocities array: 40 elements * 2 bytes = 80 bytes (interleaved lo/hi)
velocities:
    .fill 80, 0

// Tables for Color RAM rows
row_lo:
    .fill 25, <($d800 + i*40)
row_hi:
    .fill 25, >($d800 + i*40)

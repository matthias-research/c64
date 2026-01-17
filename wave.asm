// Variables - Moved to Zero Page ($02-$08)
.label xpos     = $02
.label ypos     = $03
.label charpos  = $04 // Takes 2 bytes ($04 and $05)
.label colorpos = $06 // Takes 2 bytes ($06 and $07)
.label scaled_height = $09
.label temp_sum = $0a
.label temp_term = $0b

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

.const AIR_COLOR   = 14 
.const WATER_COLOR = 6  
.const AIR_CHAR    = 32 
.const WATER_CHAR  = 160
.const DEFAULT_TEXT_COLOR = 14 // Or 1 for white

* = $c000
start:  
    // Optional: Set background and border to light blue (Sky)
    lda #AIR_COLOR
    sta $d020
    sta $d021

    jsr init
    
wait_start:
    jsr $ffe4       // GETIN
    beq wait_start

mainloop:
    jsr solve
    jsr display

    jsr $ffe4       // GETIN
    beq mainloop    // No key? Continue
    jmp exit        // Key pressed? Exit

exit:
    jsr cleanup
    rts

init:
    ldx #0
init_loop:
    lda initheights,x
    sta heights,x
    
    lda #0
    sta velocities,x
    
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
    // Initialize Pointers to Screen ($0400) and Color RAM ($D800)
    lda #$00
    sta charpos
    sta colorpos
    lda #$04
    sta charpos+1
    lda #$D8
    sta colorpos+1
    
    lda #0
    sta ypos
yloop:
    lda #0
    sta xpos
xloop:
    jsr drawchar
    
    // Increment Pointers
    inc charpos
    bne skip1
    inc charpos+1
skip1:
    inc colorpos
    bne skip2
    inc colorpos+1
skip2:
    
    inc xpos
    lda xpos
    cmp #40
    bne xloop
    
    inc ypos
    lda ypos
    cmp #25
    bne yloop
    rts

drawchar:
    ldx xpos
    lda heights,x
    lsr
    lsr
    lsr
    sta scaled_height

    lda #24
    sec
    sbc ypos
    
    cmp scaled_height
    bcs setair      
    
setwater:
    lda #WATER_CHAR
    ldy #0
    sta (charpos),y
    lda #WATER_COLOR
    sta (colorpos),y
    rts
    
setair:
    lda #AIR_CHAR
    ldy #0
    sta (charpos),y
    lda #AIR_COLOR
    sta (colorpos),y
    rts

solve:
    jsr updatevelocities
    jsr updateheights

    rts

updatevelocities:
    // reflecting boundaries
    lda heights
    sta leftboundary
    lda heights+39
    sta rightboundary
    
    ldx #0
uvloop:
    lda heights-1,x
    lsr 
    adc #0 // round up
    sta temp_sum
    lda heights+1,x
    lsr
//    adc #0 // round up
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
    ror
    cmp #$80
    ror
    cmp #$80
    ror
    sta temp_term   // Save signed delta

    lda velocities,x // Check sign of velocity (and delta)
    bmi neg_vel

pos_vel:
    lda heights,x
    clc
    adc temp_term
    bcs clamp_255   // Carry Set = Overflow > 255
    jmp store_height

neg_vel:
    lda heights,x
    clc
    adc temp_term
    bcc clamp_0     // Carry Clear = Underflow < 0
    jmp store_height

clamp_255:
    lda #255
    jmp store_height

clamp_0:
    lda #0

store_height:
    sta heights,x

    inx
    cpx #40
    bne hloop
    rts

leftboundary:
    .byte 0
heights:
    .fill 40, 0 
rightboundary:
    .byte 0

initheights:
    .fill 10, 100   // dam break
    .fill 30, 10
    
velocities:
    .fill 40, 0

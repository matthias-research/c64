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
    
mainloop:
    jsr solve
    jsr display

waitkey:
    jsr $ffe4       // GETIN
    beq waitkey     // Wait for key press
    
    cmp #'Q'        // Check for 'Q' to exit
    beq exit
    cmp #'q'        // Check for 'q' to exit
    beq exit
    
    jmp mainloop    // Continue simulation

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
    sta temp_sum
    lda heights+1,x
    lsr
    clc
    adc temp_sum
    sta temp_sum
    
    lda heights,x
    lsr
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
    cmp #$80
    ror
    cmp #$80
    ror
    cmp #$80
    ror
    
    clc
    adc heights,x
    
    cmp #201
    bcc store_height
    
    ldy velocities,x
    bmi clamp_zero
    
    lda #200
    jmp store_height

clamp_zero:
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
    .fill 10, 50   // dam break
    .fill 30, 10
    
velocities:
    .fill 40, 0

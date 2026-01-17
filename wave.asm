// Variables - Moved to Zero Page ($02-$08)
.label xpos     = $02
.label ypos     = $03
.label charpos  = $04 // Takes 2 bytes ($04 and $05)
.label colorpos = $06 // Takes 2 bytes ($06 and $07)

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
    
mainloop:
    jsr display
    
    jsr $ffe4      // GETIN
    beq mainloop   // Loop if no key pressed
    
    jsr cleanup
    rts

cleanup:
    // 1. Reset the KERNAL cursor color
    lda #DEFAULT_TEXT_COLOR
    sta $0286 

    // 2. Clear the screen (optional but helpful)
    // This calls the KERNAL routine to clear screen and reset pointers
    // jsr $e544 
    
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
    lda #24
    sec
    sbc ypos
    
    ldx xpos
    cmp heights,x
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

heights:
    .fill 10, 15    // 10 columns at height 15
    .fill 10, 10    // 10 columns at height 10
    .fill 10, 5     // 10 columns at height 5
    .fill 10, 2     // 10 columns at height 2
// Simple C64 Bitmap Mode Test (Simplified)
// Removes address lookup tables in favor of pointer arithmetic

.const BITMAP_MEM = $2000
.const SCREEN_RAM = $0400

.label ptr_draw = $02    // Pointer used for drawing the current bar
.label ptr_col  = $04    // Pointer to the bottom of the current column
.label height   = $06    // Pixels remaining to draw

.pc = $0801 "BasicUpstart"
:BasicUpstart(start)

* = $0810
start:  
    // 1. Setup Colors (White on Black)
    // We can do this efficiently using the fact that Screen RAM is $0400-$07E7
    ldx #0
    lda #$10        // White foreground, Black background
set_colors:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+$0100,x
    sta SCREEN_RAM+$0200,x
    sta SCREEN_RAM+$0300,x // Covers up to $07FF
    inx
    bne set_colors
    
    // 2. Clear Bitmap Memory ($2000-$3FFF)
    // Using a nested loop is more compact than unrolling
    lda #0
    tay             // Y = 0 (byte index)
    ldx #$20        // X = High byte start ($20)
clear_loop:
    stx $FB         // Store High Byte in ZP for indirect addressing
    sty $FA         // Store Low Byte (always 0 initially)
    lda #0
inner_clear:
    sta ($FA),y     // Store 0 at pointer
    iny
    bne inner_clear
    inx             // Next page
    cpx #$40        // Stop at $4000
    bne clear_loop

    // 3. Enable Bitmap Mode
    lda $d011
    ora #%00100000  // Bit 5: Bitmap Mode
    sta $d011
    
    lda #%00011000  // Bitmap at $2000, Screen at $0400
    sta $d018

    jsr draw_bars

    // 4. Wait for key
wait_key:
    jsr $ffe4
    beq wait_key

    // 5. Restore text mode
    lda $d011
    and #%11011111
    sta $d011
    lda #%00010100  // Reset memory pointers
    sta $d018
    jsr $e544       // Clear screen
    rts

// ---------------------------------------------------------
// Main Drawing Routine
// ---------------------------------------------------------
draw_bars:
    // Initialize Column Pointer to the bottom-left of the bitmap area.
    // Row 24 starts at $2000 + (24 * 320) = $3E00.
    lda #<$3E00
    sta ptr_col
    lda #>$3E00
    sta ptr_col+1
    
    ldx #0          // X = Current Column (0-39)

col_loop:
    // Save current column index
    txa
    pha
    
    // Setup drawing pointer for this column
    lda ptr_col
    sta ptr_draw
    lda ptr_col+1
    sta ptr_draw+1
    
    // Get height for this column
    lda heights,x
    sta height
    
    jsr draw_single_bar

    // Prepare ptr_col for the NEXT column
    // The next column is just 8 bytes ahead in memory
    lda ptr_col
    clc
    adc #8
    sta ptr_col
    bcc !+
    inc ptr_col+1
!:
    // Restore column index and loop
    pla
    tax
    inx
    cpx #40
    bne col_loop
    rts

// ---------------------------------------------------------
// Draw Single Bar
// Draws upwards from ptr_draw based on 'height'
// ---------------------------------------------------------
draw_single_bar:
    lda height
    beq exit_draw   // Height 0? Done.

    cmp #8
    bcc partial_fill // Less than 8 pixels? Do partial fill.

    // --- FULL BLOCK FILL (8 pixels) ---
    ldy #7
    lda #$FF
fill_8:
    sta (ptr_draw),y
    dey
    bpl fill_8

    // Move pointer UP one character row.
    // In bitmap, up one row = subtract 320 ($0140)
    sec
    lda ptr_draw
    sbc #$40
    sta ptr_draw
    lda ptr_draw+1
    sbc #$01
    sta ptr_draw+1

    // Decrease height by 8 and loop
    lda height
    sec
    sbc #8
    sta height
    jmp draw_single_bar

partial_fill:
    // --- PARTIAL BLOCK FILL ---
    // We want to fill from the BOTTOM of the char.
    // E.g., Height 3 means fill bytes 5, 6, 7.
    // Start index Y = 8 - Height.
    lda #8
    sec
    sbc height
    tay             // Y = Start index
    
    lda #$FF
part_loop:
    sta (ptr_draw),y
    iny
    cpy #8
    bne part_loop
    
exit_draw:
    rts

// ---------------------------------------------------------
// Data
// ---------------------------------------------------------
heights: 
    .byte   0,   1,   3,   6,  10,  15,  22,  29,  36,  44
    .byte  52,  60,  68,  75,  82,  87,  92,  96,  99, 100
    .byte 100,  99,  96,  92,  87,  82,  75,  68,  60,  52
    .byte  44,  36,  29,  22,  15,  10,   6,   3,   1,   0
// BasicUpstart2 creates the "10 SYS 2064" Basic line for you automatically
:BasicUpstart2(start)

.encoding "petscii_upper"  // Ensures characters map correctly to C64 uppercase

start:
    ldx #00         // Initialize X register to 0 (our index counter)

print_loop:
    lda message, x  // Load character from label 'message' + X offset
    beq done        // If byte is 0 (end of string), jump to 'done'
    
    jsr $ffd2       // Call KERNAL routine CHROUT (print char in A to screen)
    
    inx             // Increment X to point to next character
    jmp print_loop  // Jump back to start of loop

done:
    rts             // Return to BASIC (exits the program)

// Data section
message:
    .text "HELLO WORLD" // The string to print
    .byte 0             // Null terminator to mark end of string
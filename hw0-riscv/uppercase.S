        .section .data
input_string:   .asciz "Hello world!"

        # tohost/fromhost are data locations used by Spike
        .align 8
tohost: .byte 0
        .align 8
fromhost: .byte 0

        
        .section .text
        .globl _start
_start:
        # Load the address of the input string into a0
        la a0, input_string
loop: 
        lb t0, 0(a0)
        beqz t0, end_program 

        li t1, 'a' 
        blt t0, t1, skip # means that character is already capital
        li t2, 'z' 
        bgt t0, t2, skip # means that character is special (like punctuation)
        
        # since we're here, we know character is currently lowercase 
        addi t0, t0, -32 # because 'a' - 32 = 'A'
        sb t0, 0(a0)
skip: 
        addi a0, a0, 1 # next char 
        j loop
        
end_program:
        # jump here when you're done
        j end_program



uppercase.bin:     file format elf32-littleriscv


Disassembly of section .text:

00010074 <_start>:
   10074:	ffff2517          	auipc	a0,0xffff2
   10078:	f8c50513          	addi	a0,a0,-116 # 2000 <__DATA_BEGIN__>

0001007c <loop>:
   1007c:	00050283          	lb	t0,0(a0)
   10080:	02028263          	beqz	t0,100a4 <end_program>
   10084:	06100313          	li	t1,97
   10088:	0062ca63          	blt	t0,t1,1009c <skip>
   1008c:	07a00393          	li	t2,122
   10090:	0053c663          	blt	t2,t0,1009c <skip>
   10094:	fe028293          	addi	t0,t0,-32
   10098:	00550023          	sb	t0,0(a0)

0001009c <skip>:
   1009c:	00150513          	addi	a0,a0,1
   100a0:	fddff06f          	j	1007c <loop>

000100a4 <end_program>:
   100a4:	0000006f          	j	100a4 <end_program>

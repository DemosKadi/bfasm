set debuginfod enabled off
file bf
#set args scripts/hw.bf
#set args scripts/test.bf
#set args scripts/infinite_squares.bf
set args scripts/hanoi.bf
layout asm
layout regs
break _start
run

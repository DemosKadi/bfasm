set debuginfod enabled off
set disassembly-flavor intel
#file bf
#set args scripts/te.bf
#set args scripts/hw.bf
#set args scripts/test.bf
#set args scripts/infinite_squares.bf
#set args scripts/hanoi.bf
layout asm
layout regs
break _start
run

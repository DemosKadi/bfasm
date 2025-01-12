%macro print 2
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1; sys_write
    mov rdi, 1; stdout
    mov rsi, %1; message to write
    mov rdx, %2; message length
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

%macro eprint 2
    push rax
    push rdi
    push rsi
    push rdx
    mov rax, 1; sys_write
    mov rdi, 2; stderr
    mov rsi, %1; message to write
    mov rdx, %2; message length
    syscall
    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

%macro exit 1
    mov rax, 60; sys_exit
    mov rdi, %1; exit code
    syscall
%endmacro

; This should not explicitly be written
; Just used to indicate that unused code (which is zeroed) is invalid
%define OP_INVALID  0

; byte     word
; opcode + count
%define OP_ADD      1
%define OP_ADD_SIZE 3

; byte     word
; opcode + count
%define OP_SUB      2
%define OP_SUB_SIZE 3

; byte     word
; opcode + count
%define OP_MOVE_LEFT        3
%define OP_MOVE_LEFT_SIZE   3

; byte     word
; opcode + count
%define OP_MOVE_RIGHT       4
%define OP_MOVE_RIGHT_SIZE  3

; byte     word
; opcode + jump target
%define OP_LOOP_LEFT    5
%define OP_LOOP_LEFT_SIZE 3

; byte     word
; opcode + jump target
%define OP_LOOP_RIGHT       6
%define OP_LOOP_RIGHT_SIZE  3

; byte
; opcode
%define OP_PRINT        7
%define OP_PRINT_SIZE   1

; byte
; opcode
%define OP_READ         8
%define OP_READ_SIZE    1

bf_code_size    equ 0x20000 ; 128kib
tape_size       equ 0x8000 ; 32kib
input_buf_size  equ 0x10000 ; 64kib

section .data
usage_msg_str       db "usage: bf <path to brainfuck program>", 0xa
usage_msg_str_len   equ $ - usage_msg_str

open_file_fail_str      db "could not open file", 0xa
open_file_fail_str_len  equ $ - open_file_fail_str

compilation_loop_imbalance_str      db "Compilation failed, loops are not matched", 0xa
compilation_loop_imbalance_str_len  equ $ - compilation_loop_imbalance_str

op_instruction_table:
    dq op_invalid
    dq op_add
    dq op_sub
    dq op_move_left
    dq op_move_right
    dq op_loop_left
    dq op_loop_right
    dq op_print
    dq op_read
    dq op_invalid

compilation_jump_table:
    times 43 dq compile.check_done  ; 0..43
    dq compile.check_plus           ; 43
    dq compile.check_comma          ; 44
    dq compile.check_minus          ; 45
    dq compile.check_dot            ; 46
    times 13 dq compile.check_done  ; 47..60
    dq compile.check_left           ; 60
    dq compile.check_done           ; 61
    dq compile.check_right          ; 62
    times 28 dq compile.check_done  ; 63..91
    dq compile.check_loop_left      ; 91
    dq compile.check_done           ; 92
    dq compile.check_loop_right     ; 93
    times 162 dq compile.check_done ; 94..256

%ifdef DEBUG
add_str             db "add", 0xa
add_str_len         equ $ - add_str
read_str            db "read", 0xa
read_str_len        equ $ - read_str
sub_str             db "sub", 0xa
sub_str_len         equ $ - sub_str
print_str           db "print", 0xa
print_str_len       equ $ - print_str
move_left_str       db "move_left", 0xa
move_left_str_len   equ $ - move_left_str
move_right_str      db "move_right", 0xa
move_right_str_len  equ $ - move_right_str
loop_left_str       db "loop_left", 0xa
loop_left_str_len   equ $ - loop_left_str
loop_right_str      db "loop_right", 0xa
loop_right_str_len  equ $ - loop_right_str
%endif

invalid_op_str      db "invalid instruction", 0xa
invalid_op_str_len  equ $ - invalid_op_str

crash_loop_left_str         db "[", 0xa
crash_loop_left_str_len     db $ - crash_loop_left_str
crash_loop_right_str        db "]", 0xa
crash_loop_right_str_len    db $ - crash_loop_right_str

section .bss
bf_source       resb    bf_code_size
bf_code         resb    bf_code_size
bf_data         resb    tape_size
bf_code_len     resw    1

input_buffer        resb    input_buf_size
input_buffer_start  resw    1
input_buffer_end    resw    1

section .text
global _start
_start:
    ;   read first command line arg into rdi
    pop rdi ; argc

    ;   check if argc is not 1
    cmp rdi, 1
    jle no_args

    pop rsi; discard argv[0]
    pop rsi; get argv[1]

    ;   open file given by command line parameter
    mov rax, 2; syscall open
    mov rdi, rsi; move filename from rsi to rdi
    mov rsi, 0; flags (0 for readonly)
    mov rdx, 0; mode (unused for reading)
    syscall

    ;   check file was opened correctly
    cmp rax, 0
    jl  open_file_error

    ;   save file descriptor in r8
    mov r8, rax

    ;   read file content into bf_source
    mov rax, 0; sys_read
    mov rdi, r8; stdin
    mov rsi, bf_source; bf_source
    mov rdx, bf_code_size
    syscall

    ;   move the read count into r9
    mov r9, rax

    ;   close the file descriptor
    mov rax, 3; syscall close
    mov rdi, r8
    syscall

    call compile
;.compile_done:

%ifdef DEBUG
    call dbg_print
%endif

    call brainfuck

    exit 0

%define PROGRAM_IDX r10
%define OUTPUT_IDX r11
%define OUTPUT_IDX_WORD r11w

%macro CHECK 3
    %1:
    mov byte [bf_code + OUTPUT_IDX], %2
    add OUTPUT_IDX, %3
    jmp .check_done
%endmacro

compile:
    xor PROGRAM_IDX, PROGRAM_IDX ; the program index
    xor OUTPUT_IDX, OUTPUT_IDX ; the output index

    .compile_impl:
    xor rbx, rbx
    mov bl, [bf_source + r10]; read the current instruction

    jmp [compilation_jump_table + rbx * 8]

    CHECK .check_left,  OP_MOVE_LEFT,  OP_MOVE_LEFT_SIZE
    CHECK .check_right, OP_MOVE_RIGHT, OP_MOVE_RIGHT_SIZE
    CHECK .check_plus,  OP_ADD,        OP_ADD_SIZE
    CHECK .check_minus, OP_SUB,        OP_SUB_SIZE
    CHECK .check_dot,   OP_PRINT,      OP_PRINT_SIZE
    CHECK .check_comma, OP_READ,       OP_READ_SIZE

    .check_loop_left:
    push OUTPUT_IDX ; pushing current output idx to stack, to get it when loop is closed
    mov byte [bf_code + OUTPUT_IDX], OP_LOOP_LEFT
    mov word [bf_code + OUTPUT_IDX + 1], 0 ; INFO: using word for now, since code is max 64k size so word should be enough
    add OUTPUT_IDX, OP_LOOP_LEFT_SIZE ; INFO: adding opcode + wordsize
    push OUTPUT_IDX ; now pushing the jump offset to the stack

    jmp .check_done

    .check_loop_right:
    pop rax ; getting the jump offset
    pop rbx ; getting the offset of the loop beginning
    inc word bx ; getting the offset of the loop operand

    mov byte [bf_code + OUTPUT_IDX], OP_LOOP_RIGHT
    mov word [bf_code + OUTPUT_IDX + 1], ax ; writing the jump target for the beginning of the loop
    add OUTPUT_IDX, OP_LOOP_RIGHT_SIZE

    mov word [bf_code + rbx], OUTPUT_IDX_WORD ; updating the jump target for the beginning of th loop
    jmp .check_done

    .check_done:
    inc PROGRAM_IDX ; increment the current counter
    cmp PROGRAM_IDX, r9 ; check if the current counter is the same 
    jl .compile_impl ; jump to compile impl if the current index is less than the size

    .compilation_done:

    xor PROGRAM_IDX, PROGRAM_IDX ; reset r10 to 0
    mov word [bf_code_len], OUTPUT_IDX_WORD
    xor OUTPUT_IDX, OUTPUT_IDX ; reset r10 to 0
    ret

    .compilation_fail:
    eprint compilation_loop_imbalance_str, compilation_loop_imbalance_str_len
    exit 1

%define PROGRAM_IDX r10
%define PROGRAM_IDX_WORD r10w
%define TAPE_IDX r11
%define CELL [bf_data + TAPE_IDX]
%macro SAVE 0
    push PROGRAM_IDX
    push TAPE_IDX
%endmacro

%macro LOAD 0
    pop TAPE_IDX
    pop PROGRAM_IDX
%endmacro

%macro TRACE_OP 2
    %ifdef DEBUG
        ;SAVE
        ;print %1, %2
        ;LOAD
    %endif
%endmacro

brainfuck:
    xor PROGRAM_IDX, PROGRAM_IDX
    xor TAPE_IDX, TAPE_IDX

    .brainfuck_impl:
    ;mov r12, [bf_code_len]
    ;pop r12 ; read the size from the stack
    cmp word PROGRAM_IDX_WORD, [bf_code_len]
    ; check if the current index (r10) is lower than the code size (r12)
    ; if it is:
    ;   go to the actual implementation
    ; else:
    ;   return
    jge .brainfuck_done
    xor r13, r13 ; make sure r13 is empty
    mov byte r13b, [bf_code + PROGRAM_IDX] ; read the current instruction

    call [op_instruction_table + r13 * 8] ; call the function for the current op

    jmp .brainfuck_impl ; jump back to the beginning of the implemantation

    .brainfuck_done:
    ret

op_add:
    TRACE_OP add_str, add_str_len

    inc byte CELL ; I assume it wraps

    add PROGRAM_IDX, OP_ADD_SIZE
    ret

op_read:
    TRACE_OP read_str, read_str_len

    ; clear rax and rbx
    xor rax, rax
    xor rbx, rbx
    ; read the positions
    mov ax, [input_buffer_start]
    mov bx, [input_buffer_end]
    cmp ax, bx
    ; check if buffer is empty
    jne .read_from_buffer
    ; read from stdin into buffer if buffer is empty
    ;xor rax, rax ; reset buffer start to 0
    ;xor rbx, rbx

    push TAPE_IDX

    ; make read syscall into input_buffer
    mov rax, 0 ; sys_read
    mov rdi, 0 ; stdin
    mov rsi, input_buffer
    mov rdx, input_buf_size
    syscall

    pop TAPE_IDX

    ; write new input buffer start and end into 'variables'
    mov word [input_buffer_end], ax
    mov word [input_buffer_start], 0


    .read_from_buffer:
    xor rax, rax ; clear rax 
    mov ax, [input_buffer_start] ; read input_buffer_start into rax

    mov bl, [input_buffer + rax] ; read the current input value into bl
    mov CELL, bl ; move the current input value into the current cell
    inc ax ; increase the input buffer start
    mov [input_buffer_start], ax ; write the new start into memory

    add PROGRAM_IDX, OP_READ_SIZE
    ret

op_sub:
    TRACE_OP sub_str, sub_str_len

    dec byte CELL

    add PROGRAM_IDX, OP_SUB_SIZE
    ret

op_print:
    TRACE_OP print_str, print_str_len

    push TAPE_IDX

    mov rax, 1; sys_write
    mov rdi, 1; stdout
    lea rsi, CELL
    mov rdx, 1; message length
    syscall

    pop TAPE_IDX

    add PROGRAM_IDX, OP_PRINT_SIZE
    ret

op_move_left:
    TRACE_OP move_left_str, move_left_str_len

    dec TAPE_IDX ; if a program tries to go sub 0 the behaviour is undefined

    add PROGRAM_IDX, OP_MOVE_LEFT
    ret

op_move_right:
    TRACE_OP move_right_str, move_right_str_len

    inc TAPE_IDX ; if a program exceedes the tape length, it is undefined behaviour

    add PROGRAM_IDX, OP_MOVE_RIGHT_SIZE
    ret

op_loop_left:
    TRACE_OP loop_left_str, loop_left_str_len

    ; check if the current cell is 0
    cmp byte CELL, 0
    je .skip_loop

    ; if the current cell is not zero, increase index to next operation
    add PROGRAM_IDX, OP_LOOP_LEFT_SIZE ; operand + word size

    ret

    .skip_loop:
    ; if the current cell is 0, skip to the next closing index
    mov word PROGRAM_IDX_WORD, [bf_code + PROGRAM_IDX + 1]
    ret

op_loop_right:
    TRACE_OP loop_right_str, loop_right_str_len
    ; check if currend cell is not zero
    cmp byte CELL, 0
    jne .repeat_loop

    add PROGRAM_IDX, OP_LOOP_RIGHT_SIZE ; operand + word size
    ret

    ; else just go ahead
    .repeat_loop:
    mov word PROGRAM_IDX_WORD, [bf_code + PROGRAM_IDX + 1]
    ret

op_invalid:
    TRACE_OP invalid_op_str, invalid_op_str_len
    eprint invalid_op_str, invalid_op_str_len
    exit 1

%ifdef DEBUG
%macro DBG_PRINT 1
    SAVE
    push rax
    push rbx
    push rdi
    push rsi
    push rdx

    push %1

    mov rax, 1; sys_write
    mov rdi, 1; stdout
    mov rbx, %1
    mov rsi, rsp
    ;lea rsi, rbx
    ;mov rsi, %1; message to write
    mov rdx, 1; message length
    syscall

    add rsp, 8

    pop rdx
    pop rsi
    pop rdi
    pop rbx
    pop rax
    LOAD
%endmacro

%macro DBG_IMPL 3
    cmp byte bl, %1
    jne %2
    DBG_PRINT %3
    inc PROGRAM_IDX
    jmp .dbg_print_impl
%endmacro

%macro DBG_IMPL_LOOP 3
    cmp byte bl, %1
    jne %2
    DBG_PRINT %3
    add PROGRAM_IDX, 3
    jmp .dbg_print_impl
%endmacro

dbg_print:
    xor PROGRAM_IDX, PROGRAM_IDX
    .dbg_print_impl:
    ;mov  ax, [bf_code_len]
    cmp word PROGRAM_IDX_WORD, [bf_code_len]
    jge .dbg_done

    mov byte bl, [bf_code + PROGRAM_IDX]

    .dbg_add:
    DBG_IMPL OP_ADD, .dbg_sub, '+'
    .dbg_sub:
    DBG_IMPL OP_SUB, .dbg_move_left, '-'
    .dbg_move_left:
    DBG_IMPL OP_MOVE_LEFT, .dbg_move_right, '<'
    .dbg_move_right:
    DBG_IMPL OP_MOVE_RIGHT, .dbg_loop_left, '>'
    .dbg_loop_left:
    DBG_IMPL_LOOP OP_LOOP_LEFT, .dbg_loop_right, '['
    .dbg_loop_right:
    DBG_IMPL_LOOP OP_LOOP_RIGHT, .dbg_op_print, ']'
    .dbg_op_print:
    DBG_IMPL OP_PRINT, .dbg_op_read, '.'
    .dbg_op_read:
    DBG_IMPL OP_READ, .dbg_invalid, ','
    .dbg_invalid:
    DBG_PRINT '!'
    inc PROGRAM_IDX
    jmp .dbg_print_impl

    .dbg_done:
    ret
;dbg_done:
    ;jmp dbg_print_done
%endif

no_args:
    eprint usage_msg_str, usage_msg_str_len
    exit   1

open_file_error:
    eprint open_file_fail_str, open_file_fail_str_len
    exit   1

invalid_instruction:
    exit 1

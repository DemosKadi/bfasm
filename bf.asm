%macro print_raw 2+
    ; store the string at a macro local, pseudo label
    ; then skip to the print implementation
    jmp %%endstr
    %%str:  db %2
    %%endstr:

    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 1; sys_write
    mov rdi, %1; stderr
    mov rsi, %%str; message to write
    mov rdx, %%endstr - %%str; message length
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

%define print(s) print_raw 1, s
%define println(s) print_raw 1, s, 0xa
%define eprint(s) print_raw 2, s
%define eprintln(s) print_raw 2, s, 0xa

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

; byte
; opcode
%define OP_SET_CELL_ZERO        9
%define OP_SET_CELL_ZERO_SIZE   1

bf_code_size    equ 0x20000 ; 128kib
tape_size       equ 0x8000 ; 32kib
input_buf_size  equ 0x10000 ; 64kib
print_buffer_capacity   equ 0xFF ; 255b

section .data
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
    dq op_set_cell_zero
    dq op_invalid

compilation_jump_table:
    times 43 dq compile.unknown  ; 0..43
    dq compile.plus              ; 43
    dq compile.comma             ; 44
    dq compile.minus             ; 45
    dq compile.dot               ; 46
    times 13 dq compile.unknown  ; 47..60
    dq compile.left              ; 60
    dq compile.unknown           ; 61
    dq compile.right             ; 62
    times 28 dq compile.unknown  ; 63..91
    dq compile.loop_left         ; 91
    dq compile.unknown           ; 92
    dq compile.loop_right        ; 93
    times 162 dq compile.unknown ; 94..256

section .bss
bf_source       resb    bf_code_size
bf_code         resb    bf_code_size
bf_data         resb    tape_size
bf_code_len     resw    1
; buffering stdout
print_buffer        resb    print_buffer_capacity
; the actual size of the data currently in the buffer
print_buffer_size   resb    1

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
    call brainfuck

    exit 0

%define PROGRAM_IDX r10
%define OUTPUT_IDX r11
%define OUTPUT_IDX_WORD r11w

%macro CHECK 2
    mov byte [bf_code + OUTPUT_IDX], %1
    add OUTPUT_IDX, %2
    inc PROGRAM_IDX
    jmp .step_done
%endmacro

%macro COMPILE 2
    mov byte [bf_code + OUTPUT_IDX], %1

    xor rax, rax ; rax is used as the counter

    %%collect:
    ; read the 'next' byte and check if it is still a valid move left byte
    cmp bl, [bf_source + PROGRAM_IDX]
    ; if it is not move_left anymore jumpt to check done
    jne %%collect_done

    inc rax ; increase rax everytime another of the same elements was found
    inc PROGRAM_IDX

    ; check if PROGRAM_IDX is out of bounds and go to compilation finished if it is
    cmp PROGRAM_IDX, r9
    jl  %%collect
    jmp .done

    %%collect_done:
    mov word [bf_code + OUTPUT_IDX + 1], ax
    add OUTPUT_IDX, %2
    jmp .step_done
%endmacro

compile:
    xor PROGRAM_IDX, PROGRAM_IDX ; the program index
    xor OUTPUT_IDX, OUTPUT_IDX ; the output index

    .implementation:
    movzx rbx, byte [bf_source + PROGRAM_IDX]; read the current instruction

    jmp [compilation_jump_table + rbx * 8]

    .dot:   CHECK   OP_PRINT,      OP_PRINT_SIZE
    .comma: CHECK   OP_READ,       OP_READ_SIZE

    .right: COMPILE OP_MOVE_RIGHT, OP_MOVE_RIGHT_SIZE
    .plus:  COMPILE OP_ADD,        OP_ADD_SIZE
    .minus: COMPILE OP_SUB,        OP_SUB_SIZE
    .left:  COMPILE OP_MOVE_LEFT,  OP_MOVE_LEFT_SIZE

    .loop_left:
    mov rax, bf_source
    add rax, PROGRAM_IDX

    ; check if the next is a -
    inc rax
    cmp byte [rax], '-'
    jne .loop_left_regular
    ; that check was wrong, it was an and check
    ; or a plus
    ;cmp byte [rax], '+'
    ;jne .loop_left_regular

    ; check if the op after that is the closing loop
    inc rax
    cmp byte [rax], ']'
    jne .loop_left_regular

    mov byte [bf_code + OUTPUT_IDX], OP_SET_CELL_ZERO
    inc OUTPUT_IDX
    add PROGRAM_IDX, 3
    jmp .step_done


    .loop_left_regular:
    push OUTPUT_IDX ; pushing current output idx to stack, to get it when loop is closed
    mov byte [bf_code + OUTPUT_IDX], OP_LOOP_LEFT
    mov word [bf_code + OUTPUT_IDX + 1], 0 ; INFO: using word for now, since code is max 64k size so word should be enough
    add OUTPUT_IDX, OP_LOOP_LEFT_SIZE ; INFO: adding opcode + wordsize
    push OUTPUT_IDX ; now pushing the jump offset to the stack
    inc PROGRAM_IDX
    jmp .step_done

    .loop_right:
    pop rax ; getting the jump offset
    pop rbx ; getting the offset of the loop beginning
    inc word bx ; getting the offset of the loop operand

    mov byte [bf_code + OUTPUT_IDX], OP_LOOP_RIGHT
    mov word [bf_code + OUTPUT_IDX + 1], ax ; writing the jump target for the beginning of the loop
    add OUTPUT_IDX, OP_LOOP_RIGHT_SIZE

    mov word [bf_code + rbx], OUTPUT_IDX_WORD ; updating the jump target for the beginning of th loop
    inc PROGRAM_IDX
    jmp .step_done

    .unknown:
    inc PROGRAM_IDX

    .step_done:
    cmp PROGRAM_IDX, r9 ; check if the current counter is the same 
    jl .implementation ; jump to compile impl if the current index is less than the size

    .done:
    xor PROGRAM_IDX, PROGRAM_IDX ; reset r10 to 0
    mov word [bf_code_len], OUTPUT_IDX_WORD
    xor OUTPUT_IDX, OUTPUT_IDX ; reset r10 to 0
    ret

    .failed:
    eprintln("Compilation failed, loops are not matched")
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

%macro TRACE_OP 1
    %ifdef TRACE
        SAVE
        println(%1)
        LOAD
    %endif
%endmacro
%define trace(op) TRACE_OP op

brainfuck:
    xor PROGRAM_IDX, PROGRAM_IDX
    xor TAPE_IDX, TAPE_IDX

    .brainfuck_impl:
    cmp word PROGRAM_IDX_WORD, [bf_code_len]
    ; check if the current index (r10) is lower than the code size (r12)
    ; if it is:
    ;   go to the actual implementation
    ; else:
    ;   return
    jae .brainfuck_done
    movzx r13, byte [bf_code + PROGRAM_IDX] ; read the current instruction

    jmp [op_instruction_table + r13 * 8] ; call the function for the current op

    ;jmp .brainfuck_impl ; jump back to the beginning of the implemantation

    .brainfuck_done:
    call print_flush
    ret

op_add:
    trace("add")

    ; get the add count and add it to the cell
    mov ax, [bf_code + PROGRAM_IDX + 1]
    add word CELL, ax

    add PROGRAM_IDX, OP_ADD_SIZE
    jmp brainfuck.brainfuck_impl

op_read:
    trace("read")

    ; read the positions
    movzx rax, word [input_buffer_start]
    movzx rbx, word [input_buffer_end]
    cmp ax, bx
    ; check if buffer is empty
    jne .read_from_buffer
    ; read from stdin into buffer if buffer is empty

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
    movzx rax, word [input_buffer_start] ; read input_buffer_start into rax

    mov bl, [input_buffer + rax] ; read the current input value into bl
    mov CELL, bl ; move the current input value into the current cell
    inc ax ; increase the input buffer start
    mov [input_buffer_start], ax ; write the new start into memory

    add PROGRAM_IDX, OP_READ_SIZE
    jmp brainfuck.brainfuck_impl

op_sub:
    trace("sub")

    ; get the sub count and sub it from the cell
    mov ax, [bf_code + PROGRAM_IDX + 1]
    sub word CELL, ax

    add PROGRAM_IDX, OP_SUB_SIZE
    jmp brainfuck.brainfuck_impl

op_print:
    trace("print")

    movzx rsi, byte CELL
    call print_buffered

    add PROGRAM_IDX, OP_PRINT_SIZE
    jmp brainfuck.brainfuck_impl

op_move_left:
    trace("move left")

    ; get the move count and sub it from the TAPE_IDX
    movzx rax, word [bf_code + PROGRAM_IDX + 1]
    sub TAPE_IDX, rax

    add PROGRAM_IDX, OP_MOVE_LEFT
    jmp brainfuck.brainfuck_impl

op_move_right:
    trace("move right")

    ; get the move count and sub it from the TAPE_IDX
    movzx rax, word [bf_code + PROGRAM_IDX + 1]
    add TAPE_IDX, rax

    add PROGRAM_IDX, OP_MOVE_RIGHT_SIZE
    jmp brainfuck.brainfuck_impl

op_loop_left:
    trace("loop left")

    ; check if the current cell is 0
    cmp byte CELL, 0
    je .skip_loop

    ; if the current cell is not zero, increase index to next operation
    add PROGRAM_IDX, OP_LOOP_LEFT_SIZE ; operand + word size

    jmp brainfuck.brainfuck_impl

    .skip_loop:
    ; if the current cell is 0, skip to the next closing index
    mov word PROGRAM_IDX_WORD, [bf_code + PROGRAM_IDX + 1]
    jmp brainfuck.brainfuck_impl

op_loop_right:
    trace("loop right")
    ; check if currend cell is not zero
    cmp byte CELL, 0
    jne .repeat_loop

    add PROGRAM_IDX, OP_LOOP_RIGHT_SIZE ; operand + word size
    jmp brainfuck.brainfuck_impl

    ; else just go ahead
    .repeat_loop:
    mov word PROGRAM_IDX_WORD, [bf_code + PROGRAM_IDX + 1]
    jmp brainfuck.brainfuck_impl

op_set_cell_zero:
    mov CELL, byte 0
    inc PROGRAM_IDX
    jmp brainfuck.brainfuck_impl

op_invalid:
    trace("invalid operation")
    eprintln("invalid instruction")
    exit 1

no_args:
    eprintln("usage: bf <path to brainfuck program>")
    exit   1

open_file_error:
    eprintln("could not open file")
    exit   1

invalid_instruction:
    exit 1

;; expects a single byte to print
;; will flush the buffer to stdout if the buffer is full or 0xa (a new line) was printed
print_buffered:
    ; TODO: assume that the buffer is not full
    movzx rax, byte [print_buffer_size]
    mov byte [print_buffer + rax], sil
    inc byte [print_buffer_size]

    ; check if character to print is a new_line
    cmp byte sil, 0xa
    je short .flush_buffer

    ; check if the buffer was filled
    ;movzx rax, byte [print_buffer_size]
    cmp byte [print_buffer_size], print_buffer_capacity
    ;cmp ax, print_buffer_capacity
    ; only check for equality there is no byte >0xFF
    je short .flush_buffer

    ret

    .flush_buffer:
    call print_flush

    ; TODO: check if buffer is full and then print
    ret

;; flushes the buffer
print_flush:
    push TAPE_IDX

    mov rax, 1; sys_write
    mov rdi, 1; stdout
    lea rsi, print_buffer
    ; clears rdx and moves the data in
    movzx rdx, byte [print_buffer_size]; message length
    syscall

    ; reset the buffer size to zero after the print
    mov byte [print_buffer_size], 0

    pop TAPE_IDX

    ret

build:
    nasm -gdwarf -f elf64 -O0 -o bf.o bf.asm
    ld -fuse-ld=mold -o bf bf.o

build-debug:
    nasm -DDEBUG -gdwarf -f elf64 -O0 -o bf.o bf.asm
    ld -fuse-ld=mold -o bf bf.o

release:
    nasm -f elf64 -o bf.o bf.asm
    ld -s --gc-sections -z noseparate-code -O3 -fuse-ld=mold -o bf bf.o

debug FILE: build
    gdb --command=debug.gdb --args ./bf {{FILE}}

bench FILE: release
    hyperfine --shell=none -r 5 "./bf {{FILE}}"

clean:
    rm bf.o bf

run FILE: build
    ./bf {{FILE}}

run-debug FILE: build-debug
    ./bf {{FILE}}

run-release FILE: release
    ./bf {{FILE}}

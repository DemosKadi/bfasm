#gcc -no-pie -nostdlib -m64 -o bf bf.o
#ld -o bf bf.o
build: object
    ld -fuse-ld=mold -o bf bf.o

object:
    nasm -f elf64 -o bf.o bf.asm

build-debug: object-debug
    ld -fuse-ld=mold -o bf bf.o

object-debug:
    nasm -DDEBUG -f elf64 -o bf.o bf.asm

#if {{DEBUG}} == "DEBUG" || {{DEBUG}} == "true" { nasm -f elf64 -DDEBUG -o bf.o bf.asm } else { nasm -f elf64 -o bf.o bf.asm }

release: object-release
    ld -s --gc-sections -z noseparate-code -O3 -fuse-ld=mold -o bf bf.o

object-release:
    nasm -f elf64 -O3 -o bf.o bf.asm

clean:
    rm bf.o bf

run FILE: build
    ./bf {{FILE}}

run-debug FILE: build-debug
    ./bf {{FILE}}

run-release FILE: release
    ./bf {{FILE}}

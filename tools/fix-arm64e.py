#!/usr/bin/env python3
"""5.34: mark the arm64e slices as ptrauth ABI v1.

Linux Theos (cctools-port ld64) emits arm64e code with the PAC instructions
(pacibsp / autibsp / retab are present), but it writes cpusubtype 0x2 into the
universal header instead of 0x80000002. dyld on an arm64e device reads that as
the retired pre-ptrauth ABI and refuses the image, so the tweak loads on arm64
and silently does nothing on A12 and newer.

The macOS toolchain sets the bit itself, so this is a no-op there: the script
only touches slices whose cpusubtype is exactly 0x2.
"""
import struct
import sys

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 0x2
PTRAUTH_ABI = 0x80000000


def fix(path):
    with open(path, 'r+b') as fh:
        head = fh.read(8)
        if len(head) < 8:
            return False
        magic, count = struct.unpack('>II', head)
        if magic not in (FAT_MAGIC, FAT_MAGIC_64):
            return False  # thin image: nothing to rewrite
        entry = 20 if magic == FAT_MAGIC else 32
        offset = 8
        changed = False
        for _ in range(count):
            fh.seek(offset)
            raw = fh.read(entry)
            cputype, cpusubtype = struct.unpack('>II', raw[:8])
            if cputype == CPU_TYPE_ARM64 and cpusubtype == CPU_SUBTYPE_ARM64E:
                fh.seek(offset + 4)
                fh.write(struct.pack('>I', CPU_SUBTYPE_ARM64E | PTRAUTH_ABI))
                changed = True
            offset += entry
        return changed


def main():
    for path in sys.argv[1:]:
        try:
            if fix(path):
                print('arm64e ptrauth ABI marked: %s' % path)
            else:
                print('already marked or not universal: %s' % path)
        except FileNotFoundError:
            print('missing (skipped): %s' % path)


if __name__ == '__main__':
    main()

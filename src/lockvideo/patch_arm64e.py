#!/usr/bin/env python3
"""
Mach-O cputype 伪装工具：arm64 (0x0100000C) -> arm64e (0x0100000E)

原理：arm64e 是 arm64 的超集，不含 PAC 指令的 arm64 代码在 arm64e 进程里
完全合法。改 header 里的 cputype 即可骗过 dyld 的架构校验，
绕开 "have 'arm64', need 'arm64e'" 报错，同时避开
Linux 工具链编真 arm64e 时 PAC ABI 不兼容导致的运行时崩溃。

支持 thin (单架构) 和 fat (多架构) 两种 Mach-O。
"""
import struct
import sys

CPU_TYPE_ARM64  = 0x0100000C
CPU_TYPE_ARM64E = 0x0100000E

def patch_thin(data: bytes) -> bytes:
    # 64-bit magic: 0xFEEDFACF (LE bytes: CF FA ED FE)
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic != 0xFEEDFACF:
        raise ValueError(f"不是 64-bit thin Mach-O, magic=0x{magic:X}")
    cputype = struct.unpack_from('<I', data, 4)[0]
    if cputype == CPU_TYPE_ARM64:
        struct.pack_into('<I', data, 4, CPU_TYPE_ARM64E)
        print(f"  patched: cputype arm64 (0x{CPU_TYPE_ARM64:X}) -> arm64e (0x{CPU_TYPE_ARM64E:X})")
    elif cputype == CPU_TYPE_ARM64E:
        print("  已经是 arm64e，跳过")
    else:
        print(f"  cputype=0x{cputype:X} 非 arm64，跳过")
    return data

def patch_fat(data: bytes) -> bytes:
    nfat = struct.unpack_from('>I', data, 4)[0]
    print(f"  fat binary, {nfat} 个 slice")
    for i in range(nfat):
        off = 8 + i * 20
        cputype_off = off
        cputype = struct.unpack_from('>I', data, cputype_off)[0]
        if cputype == CPU_TYPE_ARM64:
            struct.pack_into('>I', data, cputype_off, CPU_TYPE_ARM64E)
            print(f"  slice[{i}] patched: arm64 -> arm64e")
        else:
            print(f"  slice[{i}] cputype=0x{cputype:X} 跳过")
    return data

def main():
    path = sys.argv[1]
    with open(path, 'rb') as f:
        data = bytearray(f.read())
    magic = struct.unpack_from('<I', data, 0)[0]
    print(f"处理 {path}:")
    if magic in (0xCAFEBABE, 0xCAFEBABF):   # fat (BE magic)
        patch_fat(data)
    else:
        patch_thin(data)
    with open(path, 'wb') as f:
        f.write(data)

if __name__ == '__main__':
    main()

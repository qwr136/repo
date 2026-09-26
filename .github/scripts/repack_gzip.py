#!/usr/bin/env python3
# 把 theos 打出来的 deb 里 data.tar.lzma 重压缩为 data.tar.gz。
# 部分 iOS 包管理器/设备 dpkg 不认 LZMA alone 格式，会报 Bad Deb。
# 只做纯重压缩，不重新解包，tar 内 root/wheel 属主原样保留。
import glob, gzip, lzma, os, sys, time

def ar_members(p):
    data = open(p, 'rb').read()
    off = 8
    out = []
    while off + 60 <= len(data):
        hdr = data[off:off + 60]
        name = hdr[0:16].decode().strip()
        size = int(hdr[48:58].decode().strip())
        out.append((name, data[off + 60:off + 60 + size]))
        off += 60 + size + (size % 2)
    return out

def ar_header(name, size):
    h = name.ljust(16).encode()
    h += str(int(time.time())).encode().ljust(12)   # mtime（与 GNU dpkg-deb 一致）
    h += b'0'.ljust(6)           # uid
    h += b'0'.ljust(6)           # gid
    h += b'100644'.ljust(8)      # mode
    h += str(size).ljust(10).encode()
    h += b'\x60\x0a'
    assert len(h) == 60
    return h

changed = 0
for p in sorted(glob.glob('*.deb')):
    ms = ar_members(p)
    parts = [b'!<arch>\n']
    for name, body in ms:
        if name == 'data.tar.lzma':
            body = gzip.compress(
                lzma.decompress(body, format=lzma.FORMAT_ALONE), 9, mtime=0)
            name = 'data.tar.gz'
            changed += 1
        parts.append(ar_header(name, len(body)))
        parts.append(body)
        if len(body) % 2:
            parts.append(b'\n')
    open(p, 'wb').write(b''.join(parts))
    print('repacked ->', p, os.path.getsize(p), 'bytes')

if changed == 0:
    print('没有发现 data.tar.lzma，无需重打包')
sys.exit(0)

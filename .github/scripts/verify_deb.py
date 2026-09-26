#!/usr/bin/env python3
# deb 发布前自检：任何一项不过直接让 CI 失败，防止再出现 Bad Deb。
#   1) ar 结构合法，成员为 debian-binary / control.tar.gz / data.tar.gz（不允许 lzma）
#   2) control 所有字段必须是单行（带续行的多行字段 Sileo 解析不了，会报 Bad Deb）
#   3) Architecture 必须是 iphoneos-arm64（rootless 标准）
#   4) data.tar.gz 能完整解出 tar
import gzip, io, sys, tarfile

def ar_members(p):
    data = open(p, 'rb').read()
    assert data[:8] == b'!<arch>\n', 'ar 魔数不对'
    off = 8
    out = []
    while off + 60 <= len(data):
        hdr = data[off:off + 60]
        name = hdr[0:16].decode().strip()
        size = int(hdr[48:58].decode().strip())
        out.append((name, data[off + 60:off + 60 + size]))
        off += 60 + size + (size % 2)
    return out

fail = False
for p in sorted(glob.glob('*.deb')) if (glob := __import__('glob')) else []:
    print('====', p)
    try:
        ms = ar_members(p)
        names = [n for n, _ in ms]
        assert 'debian-binary' in names, f'缺 debian-binary: {names}'
        ct = next((b for n, b in ms if n.startswith('control.tar')), None)
        dt = next((b for n, b in ms if n.startswith('data.tar')), None)
        assert ct and dt, f'缺 control/data: {names}'
        assert any(n.startswith('data.tar.gz') for n in names), \
            f'data 流不是 gzip: {names}'
        ctrl_bytes = gzip.decompress(ct)
        tf = tarfile.open(fileobj=io.BytesIO(ctrl_bytes))
        ctrl_name = next(n for n in tf.getnames() if n.strip('./') == 'control' or n == 'control')
        ctrl = tf.extractfile(ctrl_name).read().decode()
        for line in ctrl.split('\n'):
            if line[:1] in (' ', '\t'):
                raise AssertionError(f'control 存在续行（Sileo 不兼容）: {line[:60]}')
        arch = next((l.split(':', 1)[1].strip() for l in ctrl.split('\n')
                     if l.startswith('Architecture:')), '')
        assert arch == 'iphoneos-arm64', f'Architecture={arch}，应为 iphoneos-arm64'
        data_tar = gzip.decompress(dt)
        dtf = tarfile.open(fileobj=io.BytesIO(data_tar))
        assert len(dtf.getnames()) > 0, 'data.tar 为空'
        print(f'  OK  arch={arch}  data条目={len(dtf.getnames())}  control 全单行')
    except AssertionError as e:
        print('  FAIL:', e)
        fail = True

sys.exit(1 if fail else 0)

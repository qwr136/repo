#!/usr/bin/env python3
"""Read actual RootHide debs; validate structures, never rewrite Mach-O headers.
Embedded signatures are checked structurally, not cryptographically/device-tested.
Only Python's standard library and dpkg-deb are required (no optional otool bypass).
"""
import hashlib
import io
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
import tarfile
import uuid
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent
TWEAK = 'Library/MobileSubstrate/DynamicLibraries/LockMessageVideo.dylib'
PREFS = 'Library/PreferenceBundles/LockMessageVideoPrefs.bundle'
ENTRY = 'Library/PreferenceLoader/Preferences/LockMessageVideoPrefs.plist'
JBROOT = '@loader_path/.jbroot/'
ARM64 = 0x0100000c


def require(condition, message):
    if not condition:
        raise ValueError(message)


def control_fields(text):
    fields = {}
    key = None
    for line in text.splitlines():
        if line[:1].isspace() and key:
            fields[key] += '\n' + line.strip()
        elif ':' in line:
            key, value = line.split(':', 1)
            require(key not in fields, 'duplicate control field: ' + key)
            fields[key] = value.strip()
    return fields


def signature_structure(blob, code_limit):
    require(len(blob) >= 20, 'truncated embedded signature')
    magic, length, count = struct.unpack_from('>III', blob)
    require(magic == 0xfade0cc0 and 12 <= length <= len(blob), 'bad signature SuperBlob')
    require(0 < count <= 64 and 12 + count * 8 <= length, 'bad signature index')
    ranges, slots, directories = [], set(), []
    for i in range(count):
        slot, offset = struct.unpack_from('>II', blob, 12 + i * 8)
        require(slot not in slots, 'duplicate signature slot')
        slots.add(slot)
        require(12 + count * 8 <= offset <= length - 8, 'signature blob offset out of bounds')
        submagic, size = struct.unpack_from('>II', blob, offset)
        require(8 <= size <= length - offset, 'signature blob size out of bounds')
        require(all(offset + size <= a or offset >= b for a, b in ranges), 'overlapping signature blobs')
        ranges.append((offset, offset + size))
        if slot == 0 or 0x1000 <= slot <= 0x1005:
            require(submagic == 0xfade0c02 and size >= 44, 'missing/truncated CodeDirectory')
            cd = blob[offset:offset + size]
            version, flags, hash_offset, ident_offset, special, code_slots, limit = struct.unpack_from('>7I', cd, 8)
            hash_size, hash_type, platform, page_size = struct.unpack_from('>4B', cd, 36)
            require(version >= 0x20001, 'unsupported CodeDirectory version')
            require(hash_type in (1, 2, 3, 4) and hash_size == {1: 20, 2: 32, 3: 20, 4: 48}[hash_type], 'invalid signature hash format')
            require(0 < limit <= code_limit and page_size <= 30, 'invalid signed code limit/page size')
            expected_slots = (limit + (1 << page_size) - 1) >> page_size if page_size else 1
            require(code_slots == expected_slots, 'inconsistent signature code slots')
            require(44 <= ident_offset < size and b'\0' in cd[ident_offset:], 'invalid signature identifier')
            require(hash_offset - special * hash_size >= 44 and hash_offset + code_slots * hash_size <= size, 'signature hashes out of bounds')
            directories.append({'slot': slot, 'version': version, 'flags': flags, 'hash_type': hash_type, 'code_slots': code_slots})
    require(0 in slots and directories, 'no primary CodeDirectory')
    return directories


def command_string(command, minimum):
    require(len(command) >= minimum, 'truncated string load command')
    offset = struct.unpack_from('<I', command, 8)[0]
    require(minimum <= offset < len(command), 'load-command string offset out of bounds')
    end = command.find(b'\0', offset)
    require(end >= offset, 'unterminated load-command string')
    return command[offset:end].decode('utf-8')


def inspect_macho(data, tweak=False):
    require(len(data) >= 8 and data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'), 'expected universal dual-slice Mach-O')
    count = struct.unpack_from('>I', data, 4)[0]
    require(count == 2, 'expected exactly arm64 and arm64e slices')
    wide = data[3] == 0xbf
    stride = 32 if wide else 20
    table_end = 8 + count * stride
    require(table_end <= len(data), 'truncated fat architecture table')
    slices, regions, seen = [], [], set()
    for i in range(count):
        values = struct.unpack_from('>IIQQII' if wide else '>IIIII', data, 8 + i * stride)
        cpu, subtype, offset, size, align = values[:5]
        require(not wide or values[5] == 0, 'nonzero fat reserved field')
        sub = subtype & 0x00ffffff
        require(cpu == ARM64 and sub in (0, 2) and sub not in seen, 'wrong/duplicate CPU subtype')
        require(align <= 30 and offset % (1 << align) == 0, 'invalid fat alignment')
        require(offset >= table_end and size >= 32 and offset + size <= len(data), 'fat slice outside file')
        require(all(offset + size <= a or offset >= b for a, b in regions), 'overlapping fat slices')
        seen.add(sub)
        regions.append((offset, offset + size))
        thin = data[offset:offset + size]
        magic, thin_cpu, thin_sub, filetype, ncmds, command_size, flags, reserved = struct.unpack_from('<8I', thin)
        require(magic == 0xfeedfacf and thin_cpu == cpu and thin_sub == subtype, 'fat/thin Mach-O header mismatch')
        # Theos iOS PreferenceBundles use -dynamiclib too (MH_DYLIB=6),
        # unlike macOS loadable MH_BUNDLE files. Check the actual target format.
        require(filetype == 6, 'wrong Mach-O filetype; expected Theos iOS dylib')
        require(0 < ncmds <= 4096 and ncmds * 8 <= command_size <= size - 32, 'bad load-command region')
        pos, end = 32, 32 + command_size
        dependencies, rpaths, identifiers = [], [], []
        signature, binary_uuid = None, None
        for _ in range(ncmds):
            require(pos + 8 <= end, 'truncated load command')
            cmd, length = struct.unpack_from('<II', thin, pos)
            require(length >= 8 and length % 8 == 0 and pos + length <= end, 'load command out of bounds')
            command = thin[pos:pos + length]
            if cmd in (0xc, 0x80000018, 0x8000001f, 0x80000023, 0x20):
                dependencies.append(command_string(command, 24))
            elif cmd == 0xd:
                identifiers.append(command_string(command, 24))
            elif cmd == 0x8000001c:
                rpaths.append(command_string(command, 12))
            elif cmd == 0x1b:
                require(length == 24 and binary_uuid is None, 'bad/duplicate UUID command')
                binary_uuid = str(uuid.UUID(bytes=command[8:24]))
                require(command[8:24] != bytes(16), 'zero UUID')
            elif cmd == 0x1d:
                require(length == 16 and signature is None, 'bad/duplicate signature command')
                sig_offset, sig_size = struct.unpack_from('<II', command, 8)
                require(sig_offset >= end and sig_size > 0 and sig_offset + sig_size <= size, 'signature outside slice')
                signature = signature_structure(thin[sig_offset:sig_offset + sig_size], sig_offset)
            pos += length
        require(pos == end and binary_uuid and signature, 'missing UUID/signature or inconsistent commands')
        require(dependencies, 'no dynamic dependencies')
        for dep in dependencies + rpaths + identifiers:
            require('/var/jb' not in dep and '/.jbroot-' not in dep, 'hardcoded rootless/randomized root: ' + dep)
            require('..' not in PurePosixPath(dep).parts, 'traversing dependency/rpath')
        for dep in dependencies:
            require(dep.startswith((JBROOT, '/usr/lib/', '/System/Library/')), 'non-native dependency: ' + dep)
        require(JBROOT + 'usr/lib/libroothide.dylib' in dependencies, 'missing native @loader_path/.jbroot libroothide dependency')
        substrate = [dep for dep in dependencies if PurePosixPath(dep).name in ('libsubstrate.dylib', 'CydiaSubstrate')]
        if tweak:
            require(substrate and all(dep.startswith(JBROOT) for dep in substrate), 'missing/non-native substrate dependency')
        slices.append({'arch': 'arm64e' if sub == 2 else 'arm64', 'cpu_subtype': subtype, 'uuid': binary_uuid, 'dependencies': dependencies, 'rpaths': rpaths, 'dylib_ids': identifiers, 'signature_structure': signature})
    require(seen == {0, 2}, 'missing dual architectures')
    return slices


def read_payload(deb):
    result = subprocess.run(['dpkg-deb', '--fsys-tarfile', str(deb)], check=True, stdout=subprocess.PIPE)
    members = {}
    with tarfile.open(fileobj=io.BytesIO(result.stdout), mode='r:*') as archive:
        for member in archive:
            raw = member.name
            while raw.startswith('./'):
                raw = raw[2:]
            if raw in ('', '.'):
                continue
            path = PurePosixPath(raw)
            require(not path.is_absolute() and '..' not in path.parts, 'unsafe archive path: ' + raw)
            name = str(path)
            require(name not in members, 'duplicate archive path: ' + name)
            require(not (name == 'var' or name.startswith('var/')), 'unexpected true-root/rootless payload: ' + name)
            require(member.isdir() or member.isfile() or member.issym(), 'unsupported archive entry: ' + name)
            if member.issym():
                target = PurePosixPath(member.linkname)
                require('/var/jb' not in member.linkname, 'rootless symlink: ' + name)
                require(not target.is_absolute() and '..' not in target.parts, 'unsafe archive symlink: ' + name)
            require(member.size <= 128 * 1024 * 1024, 'oversized payload member: ' + name)
            contents = archive.extractfile(member).read() if member.isfile() else None
            members[name] = (member, contents)
    return members


def verify_package(deb, source):
    require(deb.is_file() and deb.stat().st_size > 0, 'missing deb: ' + str(deb))
    fields = control_fields(subprocess.check_output(['dpkg-deb', '-f', str(deb)], text=True))
    require(fields.get('Package') == source.get('Package') == 'com.minis.lockmessagevideo', 'wrong package identifier')
    require(fields.get('Architecture') == source.get('Architecture') == 'iphoneos-arm64e', 'not native RootHide architecture')
    require(fields.get('Version') == source.get('Version') == '0.0.100', 'wrong package version')
    deps = fields.get('Depends', '')
    for dependency in ('mobilesubstrate', 'preferenceloader', 'roothide'):
        require(re.search(r'(?:^|,)\s*' + dependency + r'(?:\s*\([^)]*\))?\s*(?=,|$)', deps), 'missing control dependency: ' + dependency)
    members = read_payload(deb)

    def file(name):
        require(name in members and members[name][0].isfile(), 'missing/nonregular payload: ' + name)
        require(members[name][1], 'empty payload: ' + name)
        return members[name][1]

    def plist(name):
        obj = plistlib.loads(file(name))
        require(isinstance(obj, dict), 'invalid plist dictionary: ' + name)
        return obj

    info = plist(PREFS + '/Info.plist')
    require(info.get('CFBundleVersion') == info.get('CFBundleShortVersionString') == source['Version'], 'prefs CFBundle versions mismatch')
    require(info.get('CFBundleExecutable') == 'LockMessageVideoPrefs' and info.get('CFBundleIdentifier') == 'com.minis.lockmessagevideo.prefs', 'wrong prefs executable/identifier')
    require(info.get('NSPrincipalClass') == 'LMVPRootListController' and info.get('CFBundlePackageType') == 'BNDL', 'wrong preference bundle structure')
    require(plist(TWEAK.replace('.dylib', '.plist')) == {'Filter': {'Bundles': ['com.apple.springboard']}}, 'unexpected injection filter')
    entry = plist(ENTRY).get('entry', {})
    require(entry.get('bundle') == 'LockMessageVideoPrefs' and entry.get('detail') == 'LMVPRootListController' and entry.get('cell') == 'PSLinkCell' and entry.get('isController') is True, 'wrong PreferenceLoader entry')
    binaries = {}
    for name in (TWEAK, PREFS + '/LockMessageVideoPrefs'):
        data = file(name)
        require(members[name][0].mode & 0o111, 'nonexecutable Mach-O payload: ' + name)
        binaries[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'slices': inspect_macho(data, tweak=name == TWEAK)}
    return {'file': deb.name, 'size': deb.stat().st_size, 'sha256': hashlib.sha256(deb.read_bytes()).hexdigest(), 'control': fields, 'payload': sorted(members), 'binaries': binaries}


def main(argv):
    require(argv, 'usage: verify-roothide-deb.py packages/*.deb')
    receipt_path = ROOT / 'build-receipt.json'
    receipt_path.unlink(missing_ok=True)
    source = control_fields((ROOT / 'control').read_text())
    receipts = [verify_package(Path(arg).resolve(), source) for arg in argv]
    receipt = {'source_commit': os.getenv('GITHUB_SHA', 'local'), 'theos_revision': os.getenv('THEOS_REV', 'local'), 'sdk_revision': os.getenv('SDK_REV', 'local'), 'scheme': 'roothide', 'signature_verification': 'embedded structure only; not cryptographic trust', 'device_test': False, 'packages': receipts}
    receipt_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
    print('PASS: actual native RootHide package layout, control/CFBundle versions, filter, arm64+arm64e, UUIDs, signature structures and native dependencies; device behavior not tested')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, OSError, struct.error, plistlib.InvalidFileException, tarfile.TarError, subprocess.CalledProcessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)

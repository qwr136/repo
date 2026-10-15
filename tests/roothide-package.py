#!/usr/bin/env python3
"""RootHide source contracts plus positive/negative synthetic artifact tests.
Fixtures are NOT release builds or evidence of device compatibility.
"""
import copy
import importlib.util
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_roothide', ROOT / 'verify-roothide-deb.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)
checks = 0


def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


def reject(call, message):
    try:
        call()
    except ValueError:
        check(True, message)
    else:
        raise AssertionError('accepted invalid fixture: ' + message)


make = (ROOT / 'Makefile').read_text()
source = verify.control_fields((ROOT / 'control').read_text())
check(re.search(r'^ARCHS\s*=\s*arm64 arm64e\s*$', make, re.M), 'dual-slice ARCHS')
check(re.search(r'^THEOS_PACKAGE_SCHEME\s*=\s*roothide\s*$', make, re.M), 'native scheme')
check('TARGET := iphone:clang:15.6:15.0' in make, 'pinned target')
for target in ('LockMessageVideo', 'LockMessageVideoPrefs'):
    check(target + '_LIBRARIES = roothide' in make, target + ' libroothide linkage')
check(source['Version'] == '1.11' and source['Architecture'] == 'iphoneos-arm64e', 'control metadata')
info = plistlib.loads((ROOT / 'LockMessageVideoPrefs/Info.plist').read_bytes())
check(info['CFBundleVersion'] == info['CFBundleShortVersionString'] == source['Version'], 'CFBundle versions')
check(plistlib.loads((ROOT / 'LockMessageVideo.plist').read_bytes()) == plistlib.loads((ROOT / 'layout/Library/MobileSubstrate/DynamicLibraries/LockMessageVideo.plist').read_bytes()), 'source/staged filter parity')
paths = (ROOT / 'LMVPaths.h').read_text()
check('resolved = jbroot(logicalPath);' in paths and 'return @"/var/mobile/LockMessageVideo";' in paths, 'installed resources vs true-root user data')
check('LMVInstalledPath(@"/Library/PreferenceBundles/LockMessageVideoPrefs.bundle")' in paths, 'native preference resource mapping')
check('/var/jb' not in paths, 'no fixed rootless runtime prefix')
for name in ('build.yml', 'easter-compile.yml'):
    workflow = (ROOT / '.github/workflows' / name).read_text()
    for token in ('macos-15', 'workflow_dispatch:', 'https://github.com/roothide/theos.git', 'cfba89a53a05b4a1b822121158acc3669c20602f', '0222fd5413cf4b9af096f37b4621afa2688572f7', 'iPhoneOS15.6.sdk', 'libexec/gnubin', 'THEOS_PACKAGE_SCHEME=roothide', 'ARCHS="arm64 arm64e"', 'python3 verify-roothide-deb.py packages/*.deb', 'build-receipt.json', 'python3 tests/roothide-package.py'):
        check(token in workflow, name + ': ' + token)
    check('https://github.com/theos/theos.git' not in workflow and 'macos-14' not in workflow, 'no old toolchain: ' + name)
    if name == 'build.yml':
        check('push:' in workflow and 'fix/1.11-roothide' in workflow, 'authorized branch push enabled')
    else:
        check('push:' not in workflow, 'auxiliary workflow is manual-only')
base = subprocess.check_output(['git', '-C', str(ROOT), 'show', 'HEAD:.github/workflows/build.yml'], text=True)
current = (ROOT / '.github/workflows/build.yml').read_text()
# 0.0.123: the user asked to remove the desktop Reachability feature and its code,
# so its CI entry goes with it. This is the ONLY intentional removal, and it is
# named explicitly rather than weakening the retention rule for every other test.
RETIRED = {'check python3 tests/desktop-reachability.py'}
for line in base.splitlines():
    stripped = line.strip()
    if stripped.startswith('check ') and stripped not in RETIRED:
        check(line in current, 'preserve existing test: ' + stripped)
check(RETIRED.pop() not in current, 'the retired test entry is really gone')
print('PASS: native RootHide source contracts, pinned CI and all existing main CI tests retained')


def string_command(cmd, name):
    encoded = name.encode() + b'\0'
    size = (24 + len(encoded) + 7) & ~7
    return struct.pack('<6I', cmd, size, 24, 0, 0, 0) + encoded + bytes(size - 24 - len(encoded))


def thin(subtype, tweak=True, roothide=True, dep=None, signed=True):
    dependencies = ['/usr/lib/libSystem.B.dylib']
    if roothide:
        dependencies.append(verify.JBROOT + 'usr/lib/libroothide.dylib')
    if tweak:
        dependencies.append(dep or verify.JBROOT + 'usr/lib/libsubstrate.dylib')
    commands = [string_command(0xc, name) for name in dependencies]
    commands.append(struct.pack('<II', 0x1b, 24) + bytes([subtype + 1]) * 16)
    command_size = sum(map(len, commands)) + (16 if signed else 0)
    offset = 32 + command_size
    signature = b''
    if signed:
        identifier = b'lmv-test\0'
        hash_offset = 44 + len(identifier)
        directory = struct.pack('>9I4BI', 0xfade0c02, hash_offset + 32, 0x20001, 2, hash_offset, 44, 0, 1, offset, 32, 2, 0, 12, 0) + identifier + bytes(32)
        signature = struct.pack('>5I', 0xfade0cc0, 20 + len(directory), 1, 0, 20) + directory
        commands.append(struct.pack('<4I', 0x1d, 16, offset, len(signature)))
    header = struct.pack('<8I', 0xfeedfacf, verify.ARM64, subtype, 6, len(commands), command_size, 0, 0)
    return header + b''.join(commands) + signature


def fat(tweak=True, **kwargs):
    a, b = thin(0, tweak, **kwargs), thin(2, tweak, **kwargs)
    offset_a, offset_b = 4096, 8192
    table = struct.pack('>II', 0xcafebabe, 2)
    table += struct.pack('>5I', verify.ARM64, 0, offset_a, len(a), 12)
    table += struct.pack('>5I', verify.ARM64, 2, offset_b, len(b), 12)
    return table + bytes(offset_a - len(table)) + a + bytes(offset_b - offset_a - len(a)) + b


for tweak in (True, False):
    check({s['arch'] for s in verify.inspect_macho(fat(tweak), tweak)} == {'arm64', 'arm64e'}, 'valid dual slices')
reject(lambda: verify.inspect_macho(thin(0), True), 'thin binary')
reject(lambda: verify.inspect_macho(fat(roothide=False), True), 'missing libroothide')
reject(lambda: verify.inspect_macho(fat(dep='/var/jb/usr/lib/libsubstrate.dylib'), True), 'rootless substrate')
reject(lambda: verify.inspect_macho(fat(dep='/usr/lib/libsubstrate.dylib'), True), 'absolute substrate')
reject(lambda: verify.inspect_macho(fat(signed=False), True), 'missing signature')
bad = bytearray(fat())
struct.pack_into('<I', bad, 8192 + 8, 0)
reject(lambda: verify.inspect_macho(bytes(bad), True), 'fat/thin spoofed subtype')
bad = bytearray(fat())
struct.pack_into('>I', bad, 8 + 20 + 8, 4096)
reject(lambda: verify.inspect_macho(bytes(bad), True), 'overlapping slices')
bad = bytearray(fat())
struct.pack_into('<I', bad, 4096 + 36, 4)
reject(lambda: verify.inspect_macho(bytes(bad), True), 'truncated load command')
bad = bytearray(fat())
magic = bad.index(struct.pack('>I', 0xfade0c02))
struct.pack_into('>I', bad, magic, 0)
reject(lambda: verify.inspect_macho(bytes(bad), True), 'invalid CodeDirectory')
print('PASS: dual-slice Mach-O, UUID, signature and dependency positive/negative fixtures')

check(shutil.which('dpkg-deb') is not None, 'dpkg-deb required for actual archive tests')
with tempfile.TemporaryDirectory(prefix='lmv-rh-test-') as directory:
    root = Path(directory) / 'stage'
    (root / 'DEBIAN').mkdir(parents=True)
    control = 'Package: com.minis.lockmessagevideo\nVersion: 1.11\nArchitecture: iphoneos-arm64e\nMaintainer: Test <test@example.invalid>\nDescription: synthetic verifier fixture only\nDepends: mobilesubstrate, preferenceloader, roothide\n'
    (root / 'DEBIAN/control').write_text(control)
    for name, data in ((verify.TWEAK, fat()), (verify.PREFS + '/LockMessageVideoPrefs', fat(False)), (verify.PREFS + '/Info.plist', plistlib.dumps(info)), (verify.TWEAK.replace('.dylib', '.plist'), (ROOT / 'LockMessageVideo.plist').read_bytes()), (verify.ENTRY, (ROOT / 'layout' / verify.ENTRY).read_bytes())):
        dest = root / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        dest.chmod(0o755 if name.endswith('.dylib') or name.endswith('/LockMessageVideoPrefs') else 0o644)
    deb = Path(directory) / 'fixture.deb'

    def build():
        subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(root), str(deb)], check=True, stdout=subprocess.DEVNULL)
        return verify.verify_package(deb, source)

    receipt = build()
    check(len(receipt['binaries']) == 2 and receipt['control']['Architecture'] == 'iphoneos-arm64e', 'actual deb positive fixture')
    wrong = copy.deepcopy(info)
    wrong['CFBundleVersion'] = '0.0.99'
    (root / verify.PREFS / 'Info.plist').write_bytes(plistlib.dumps(wrong))
    reject(build, 'CFBundle version')
    (root / verify.PREFS / 'Info.plist').write_bytes(plistlib.dumps(info))
    filter_path = root / verify.TWEAK.replace('.dylib', '.plist')
    filter_path.write_bytes(plistlib.dumps({'Filter': {'Bundles': ['com.apple.Preferences']}}))
    reject(build, 'injection filter')
    filter_path.write_bytes((ROOT / 'LockMessageVideo.plist').read_bytes())
    (root / 'var/jb').mkdir(parents=True)
    reject(build, 'var/jb layout')
    (root / 'var/jb').rmdir()
    (root / 'var').rmdir()
    (root / 'DEBIAN/control').write_text(control.replace('iphoneos-arm64e', 'iphoneos-arm64'))
    reject(build, 'rootless package architecture')
    (root / 'DEBIAN/control').write_text(control.replace(', roothide', ''))
    reject(build, 'missing roothide control dependency')
print('PASS: actual dpkg-deb archive fixtures reject layout, metadata, filter and CFBundle mismatches')
print('PASS: %d RootHide package/source checks; synthetic fixtures only, device behavior not tested' % checks)

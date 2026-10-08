#!/usr/bin/env python3
"""Source contracts + filesystem-boundary model; not an iOS execution test."""
from pathlib import Path
import os, stat, tempfile
root=Path(__file__).resolve().parents[1]
prefs=(root/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak=(root/'Tweak.xm').read_text()
imp=(root/'LockMessageVideoPrefs/LMVImport.h').read_text()
storage=(root/'LockMessageVideoPrefs/LMVMaterialStorage.h').read_text()
assert prefs.index('preferenceSpecifierNamed:@"打开素材路径"') < prefs.index('preferenceSpecifierNamed:@"清空原素材"') < prefs.index('preferenceSpecifierNamed:@"启用诊断日志"')
assert '[diagnostics setProperty:@NO forKey:@"default"]' in prefs
assert 'style:UIAlertActionStyleDestructive' in prefs and '无法撤销' in prefs
assert 'self.materialBusy = YES' in prefs and 'self.materialBusy = NO' in prefs
assert 'dispatch_async(LMVMaterialQueue()' in prefs
assert 'dispatch_sync(LMVMaterialQueue()' in imp and 'if (NSThread.isMainThread)' in imp
assert 'std::atomic_bool LMVDiagnosticsEnabled(false)' in tweak
log=tweak.split('static void LMVDiagnostic(NSString *event) {',1)[1].split('@interface LMVFrameSnapshot',1)[0]
assert log.count('LMVDiagnosticsEnabled.load()')==2
assert 'LMVDiagnosticsEnabled.exchange(diagnosticsEnabled)' in tweak
assert 'CFSTR("DiagnosticsEnabled")' in tweak
assert 'AVAssetReaderVideoCompositionOutput' in imp and 'composition.frameDuration=' in imp
assert 'CGAffineTransformMakeTranslation(-CGRectGetMinX(oriented)' in imp
assert 'AVVideoExpectedSourceFrameRateKey' in imp and 'if (!sizeFailure) break' in imp
assert 'error.code==11 || error.code==16' in imp
assert 'AT_SYMLINK_NOFOLLOW' in storage and storage.count('O_NOFOLLOW')==2
assert 'S_ISREG(status.st_mode)' in storage and 'unlinkat(original,entry->d_name,0)' in storage
assert 'rewinddir(directory)' in storage and 'if (failed || remaining)' in storage
assert 'removeItemAtPath' not in storage and 'CFPreferencesSetAppValue' not in storage
# Exercise equivalent nonrecursive fd-relative boundary policy on Linux.
with tempfile.TemporaryDirectory() as tmp:
    base=Path(tmp); originals=base/'originals'; library=base/'library'
    originals.mkdir(); library.mkdir(); (library/'selected.mov').write_bytes(b'keep')
    (originals/'video.mov').write_bytes(b'remove')
    (originals/'nested').mkdir(); (originals/'nested'/'child.mov').write_bytes(b'keep')
    (originals/'link').symlink_to(library,target_is_directory=True)
    fd=os.open(originals,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    for name in os.listdir(fd):
        status=os.stat(name,dir_fd=fd,follow_symlinks=False)
        if stat.S_ISREG(status.st_mode): os.unlink(name,dir_fd=fd)
    assert sorted(os.listdir(fd))==['link','nested']; os.close(fd)
    assert (library/'selected.mov').read_bytes()==b'keep'
    assert (originals/'nested'/'child.mov').read_bytes()==b'keep'
    assert (originals/'link').is_symlink()
print('PASS: diagnostics OFF/both guards/notification, clear confirmation+queue+fd boundaries, frame-limited adaptive compression/size-only retry contracts; filesystem policy model (not iOS runtime)')

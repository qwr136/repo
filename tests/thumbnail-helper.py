#!/usr/bin/env python3
"""3.10.7: thumbnail decoding is outsourced to a headless one-shot tool.

The contract this guards:
  * the tool exists, is built and installed under usr/libexec,
  * it decodes one material and writes the same sidecar the host reads,
  * both hosts (SpringBoard and Preferences) hand the work out before decoding,
  * every failure path falls back to the previous in-process behaviour,
  * the list no longer advertises a per-row spinner or a film glyph.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
helper = (root / 'helper' / 'helper.m').read_text()
makefile = (root / 'Makefile').read_text()
facade = (root / 'LMVThumbnailHelper.h').read_text()
importer = (root / 'LockMessageVideoPrefs' / 'LMVImport.h').read_text()
picker = (root / 'LockMessageVideoPrefs' / 'LMVMaterialPicker.h').read_text()

# --- the tool itself -------------------------------------------------------------
assert 'int main(int argc, char *argv[])' in helper, 'the helper must be a program, not a category'
assert 'LMVDecodeThumbnail(relative)' in helper and 'LMVWriteThumbnail(relative, revision, poster)' in helper, \
    'the helper writes the same sidecar the host reads'
assert 'LMVReadThumbnail(relative, revision)' in helper, 'an existing poster must never be rewritten'
assert 'thumbReady' in helper, 'the host has to learn that a poster landed'
assert 'UIKit' in helper and 'AVFoundation' in helper, 'the helper decodes with the same frameworks'
# No UI, no window, no player: it must stay a headless decoder.
for forbidden in ('UIWindow', 'AVPlayerLayer', 'UIApplication', 'presentViewController'):
    assert forbidden not in helper, 'the helper must not take part in UI: ' + forbidden

# --- privileges & diagnostics (3.10.8) -------------------------------------------
ents = (root / 'helper' / 'lmvthumb.entitlements').read_text()
assert 'platform-application' in ents, 'a tool spawned from SpringBoard needs platform-application'
assert 'com.apple.private.security.no-container' in ents
assert 'lmvthumb_ENTITLEMENTS = helper/lmvthumb.entitlements' in makefile, \
    'the entitlements have to be attached to the tool target'
# Distinguish "never started" from "cannot write /var/mobile".
assert '/tmp/lmvthumb.log' in helper, 'a second log location is required to diagnose a silent exit'
assert 'geteuid()' in helper, 'the tool must record which identity it runs as'
assert 'posix_spawn_file_actions_addopen' in facade, \
    'the tool stdout/stderr is captured so a dyld failure is visible'

# --- packaging -------------------------------------------------------------------
assert 'TOOL_NAME = lmvthumb' in makefile and 'lmvthumb_FILES = helper/helper.m' in makefile
assert 'lmvthumb_INSTALL_PATH = /usr/libexec' in makefile, 'the tool lives beside the system helpers'
assert 'tool.mk' in makefile, 'the tool target has to be included'

# --- path resolution (RootHide has no fixed /var/jb) -----------------------------
assert 'dladdr' in facade and 'stringByDeletingLastPathComponent' in facade, \
    'the executable path is derived from the loaded dylib, not hard-coded'
assert '@"/var/jb/usr/libexec/lmvthumb"' in facade and '@"/usr/libexec/lmvthumb"' in facade, \
    'literal installs stay supported'
assert 'access(candidate.fileSystemRepresentation, X_OK)' in facade, 'a candidate is only used if it is executable'
assert 'posix_spawn' in facade and 'environ' in facade

# --- dispatch ledger -------------------------------------------------------------
assert 'LMVHelperDispatched' in facade and 'LMVHelperDispatchWindow' in facade, \
    'no thundering herd of helper processes'
assert 'if (LMVHelperDispatched[relative]) return 1;' in facade, \
    'an in-flight material must not be decoded by the host as well'
assert 'LMVHelperMaxInFlight' in facade and 'return 2;' in facade, \
    'a whole catalog asking at once must not become one process per row'

# --- import path -----------------------------------------------------------------
assert 'LMVSpawnThumbnailHelper(relative)' in importer, 'import hands the decode out'
assert importer.index('LMVSpawnThumbnailHelper(relative)') < importer.index('LMVDecodeThumbnail(relative)'), \
    'the handoff happens before any local decode'
assert 'LMVSpawnThumbnailHelper(relative) == 0' in importer, \
    'the local decode runs only when the tool is unusable'

# --- list path -------------------------------------------------------------------
assert 'LMVSpawnThumbnailHelper(relative)' in picker
assert 'LMVMaterialOutsourceLimit' in picker, 'a broken file must not start processes forever'
assert '"outsource-exhausted"' in picker, 'the budget is observable'
assert 'dispatch == 1' in picker and 'dispatch == 2' in picker, \
    'accepted and saturated are distinguishable'
assert '"outsource-deferred"' in picker
assert 'thumbnailProduced:' in picker and 'LMVMaterialThumbReady' in picker, \
    'a finished poster repaints the row without a reopen'
# The two things the user asked to never see again.
assert '"生成中…"' not in picker, 'the 生成中 label is gone'
assert 'arrow.triangle.2.circlepath' not in picker, 'the per-row spinner is gone'
assert 'systemImageNamed:@"film"' not in picker, 'the film glyph is gone'
assert 'tertiarySystemFillColor' in picker, 'a missing poster shows a neutral block instead'

print('PASS: thumbnail decoding handed to lmvthumb (headless tool, roothide path derivation, '
      'spawn-first with in-process fallback, bounded in-flight, no per-row spinner or film glyph)')

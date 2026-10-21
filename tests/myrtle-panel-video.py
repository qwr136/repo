#!/usr/bin/env python3
"""1.77: the Myrtle panel channel.

The Myrtle panel is the surface that appears under the App Library / search UI. It
is a new channel, so this locks the four things that were learned the hard way on
the Squid and CopyVault channels - each of those cost a device round trip:

  1. never require `playerLayer.readyForDisplay` BEFORE mounting (it only turns true
     once the layer is on screen, so that is a deadlock);
  2. never require an unlocked device (the panel lives over Notification Center,
     which is on the Lock Screen);
  3. never exit silently - the gate must say whether it was the switch or the
     material;
  4. the poster must be prepared before the path is selected.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
module = (root / 'LMVMyrtlePanelVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()

# --- wiring ---------------------------------------------------------------
assert '#include "LMVMyrtlePanelVideo.h"' in tweak, 'the channel is included'
assert 'LMVMyrtlePanelVideoRefresh(reload);' in tweak, 'refreshed with every other channel'
assert tweak.count('LMVMyrtlePanelVideoSuspend();') == 2, 'suspended on both suspend paths'
assert 'LMVAudioConsume(@"Myrtle",' in tweak, 'its own audio target'

# --- window identity ------------------------------------------------------
# 1.82: exactly ONE surface carries the channel - the App Library panel window.
# `MyrtleHostWindow` is the floating-app surface (the WeChat chat list card) and
# `MyrtleKeyboardWindow` is a sibling at a lower level.
assert 'static BOOL LMVMyrtleWindowName(NSString *name) {' in module
assert '[name isEqualToString:@"MyrtleWindow"]' in module, \
    'only the App Library panel window is accepted'
assert 'MyrtleHostWindow' in module, 'the floating-app surface is documented as excluded'
assert 'LMVMyrtlePanelWindow(NSUInteger skip)' in module

# --- one mount only: the App Library LIST page ----------------------------
# The icon grid is a centred MyrtleSelectorView (320 pt); the list spans the
# window minus its 12 pt inset (~406 pt). Both rules are required: the selector
# can own list children that would otherwise be picked by size alone.
assert '[NSStringFromClass(child.class) isEqualToString:@"MyrtleSelectorView"]' in module, \
    'the icon grid is excluded by class'
assert 'if(frame.size.width<bounds.size.width*.85)continue;' in module, \
    'the list page is the only card wide enough to mount'

# --- the two deadlocks, and the silent exit --------------------------------
env = module[module.index('static BOOL LMVMyrtlePanelEnvironment(void) {'):]
env = env[:env.index('\n}\n')]
assert '&& !blank;' in env, 'a dark screen still stops the channel'
assert '&& !locked' not in env, 'the panel lives on the Lock Screen - never require unlocked'
assert 'myrtle-panel env init=' in env, 'a failing environment says which condition failed'

mount = module[module.index('- (void)update {', module.index('@implementation LMVMyrtlePanelVideoManager')):]
mount = mount[:mount.index('\n@end')]
# 2.60: no poster; a prewarmed player is the only mount requirement.
assert 'BOOL live=self.playback.player && !self.playback.error;' in mount, \
    'mounting must not wait for readyForDisplay'
assert 'self.playback.posterLayer.hidden=YES;' not in mount, 'the poster is never hidden by hand'
assert 'preparePosterForPath' not in module, 'no poster is used'
assert 'LMVMyrtlePanelEnabled && LMVMyrtlePanelPath.length && LMVMyrtlePanelRevision.length' in module, 'prewarm guard'

gate = module[module.index('static void LMVMyrtlePanelVideoRefresh(BOOL reload) {'):]
gate = gate[:gate.index('\n}\n')]
assert 'myrtle-panel gate enabled=%d path=%d revision=%d' in gate, 'the empty gate is observable'
assert 'myrtle-panel windows env=%d win=%d' in gate, 'a missing window prints the window list'

# --- a UIVisualEffectView refuses direct subviews -------------------------
assert '[container isKindOfClass:UIVisualEffectView.class])return NO;' in module, \
    'the blur view is never used as a container directly'
assert '@try {[container insertSubview:self.host atIndex:index];}' in module
assert 'self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;' in module, 'the host is inert'

# --- settings: same switch / material / sound / volume layout as CV --------
assert '@"Myrtle": @"Myrtle 面板背景视频"' in prefs, 'it is a selectable material target'
assert '"SquidPanel", @"AT", @"CV", @"Myrtle", @"PA", @"GS", @"CCBorder", @"CopyLogX"] containsObject:target];' in prefs
assert '[myrtleEnabled setProperty:@"MyrtleBackgroundEnabled" forKey:@"key"]' in prefs
assert 'myrtleMaterial.buttonAction = @selector(switchMyrtle:);' in prefs
assert '[self appendAudioForTarget:@"Myrtle" title:@"播放"]' in prefs, 'sound switch + volume slider'

# --- 1.82: the sound chain must actually carry Myrtle ---------------------
# The UI was wired in 1.77 but `LMVAudioTargets()` still stopped at CV, so
# `LMVAudioConsume(@"Myrtle", ...)` returned on a nil channel: the switch and
# the slider wrote preferences no one read.
audio = (root / 'LMVMediaAudio.h').read_text()
assert '@"CV",@"Myrtle",@"PA",@"GS",@"CCBorder",@"CopyLogX"]' in audio, 'the audio channel list includes Myrtle'
assert 'NSString *key=[target stringByAppendingString:@"SoundEnabled"];' in audio

# --- the easter panel mirrors Settings ------------------------------------
assert 'static NSInteger LMVEasterMyrtleSection(void) { return LMVEasterCVSection() + 1; }' in panel
assert 'if (section == LMVEasterMyrtleSection()) return @"Myrtle 面板背景视频";' in panel
assert 'key = @"MyrtleVideo";' in panel
assert '@"CV", @"Myrtle", @"PA", @"GS", @"CCBorder", @"CopyLogX"];' in panel, 'the audio target list carries it'

print('PASS: 1.82 Myrtle single mount + sound chain')

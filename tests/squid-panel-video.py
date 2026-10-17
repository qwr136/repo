#!/usr/bin/env python3
"""1.22-1.44 contracts for the SquidGesturePro panel background channel.

The channel is intentionally poll-based: no private class of that tweak is hooked
or guessed, the panel window is found by class name and the video is attached
INSIDE the card, re-sized to the card every poll so it follows a panel that grows
with its icons. Nothing is constructed while the switch is off.

1.44: that panel has TWO shapes - the one a swipe-up opens (tall) and the shorter
one a swipe-up-twice opens. 1.50: the plugin lets both gestures be configured on the
LEFT as well, so the channel carries FOUR material slots - right 上滑/上上滑 and left
上滑/上上滑 - while the sound switch and volume stay shared (only one of the four is
ever on screen). The shape is read from the page control (hidden on the short panel,
shown on the tall one, the same in landscape and in portrait), the SIDE cannot be read
from the content at all (the left and right panels differ only in what the user put in
them) and is therefore claimed automatically and can be re-bound by hand, and the
video always fills the CARD rather than the full-screen blur material behind it.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
module = (root / 'LMVSquidPanelVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()

# ---- the module -----------------------------------------------------------
assert 'static void LMVSquidPanelVideoRefresh(BOOL reload);' in module
assert 'static void LMVSquidPanelVideoSuspend(void);' in module
# The panel window is located by CLASS NAME, never by hooking the tweak.
assert "containsString:@\"SGPanel\"" in module
assert 'MSHookMessageEx' not in module and 'class_getInstanceMethod' not in module
# The card is the largest visible descendant that does NOT fill the window, so a
# panel that grows with its icons is followed by construction, not by a stored rect.
assert 'static UIView *LMVSquidPanelCard(UIWindow *window) {' in module
assert 'if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;' in module
assert 'if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;' in module
# 1.25: each shape keeps SEVERAL cards (device log: two 430x435 views, one on
# screen at y=497 and one parked at y=1459 in a 932-high window) - scoring by area
# made the choice flip and the video kept landing on the parked one.
assert 'static CGFloat LMVSquidPanelVisibleArea(CGRect frame,CGRect bounds) {' in module
assert 'return visible/total>=.5?visible:0;' in module
assert 'CGFloat visible=LMVSquidPanelVisibleArea(frame,bounds);' in module
assert 'if(visible<=0)continue;   // parked off screen - never a candidate' in module
assert 'if(visible>bestArea){bestArea=visible;best=child;}' in module
# 1.44: the material is NOT scored with the card rule. It is searched inside the
# already-chosen card, so a parked copy is unreachable; what matters is that it
# covers the card, because in BOTH shapes it is sized to the SCREEN (landscape:
# 932x435 behind a 814x180 card). Scoring it by its own visibility dropped it to
# 36% and the short landscape panel lost its material - the video then fell back to
# the card's first subview, i.e. UNDER the blur, and became invisible.
assert 'static UIView *LMVSquidPanelMaterial(UIView *root,UIWindow *window) {' in module
assert 'CGRect cardFrame=[root convertRect:root.bounds toView:window];' in module
assert 'if(area/cardArea<.9)continue;   // must actually cover the card it serves' in module
assert 'UIView *material=LMVSquidPanelMaterial(card,window);' in module
assert 'if(!material)material=LMVSquidPanelMaterial(window,window);' in module
assert 'vis=%.0f' in module
# 1.50: FOUR slots, and the shape half of the verdict still comes from the page
# control / height test below.
assert 'static UIPageControl *LMVSquidPanelPageControl(UIView *card,UIWindow *window) {' in module
assert 'if(![node isKindOfClass:UIPageControl.class])continue;' in module
assert 'CGFloat gap=fabs(CGRectGetMaxY(f)-CGRectGetMinY(cardFrame));' in module
assert 'return (page && bestGap<40)?page:nil;' in module
# The slot table itself: four materials, four remembered signatures, four gesture names.
assert '#define LMVSquidPanelSlotCount 4' in module
assert 'static NSString *LMVSquidPanelSlotPaths[LMVSquidPanelSlotCount];' in module
assert 'static NSString *LMVSquidPanelSlotRevisions[LMVSquidPanelSlotCount];' in module
assert 'static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];' in module
# 1.55: a slot remembers EVERY signature it was seen as - the 1.54 report is that editing
# a panel's layout changed its icon count and the panel became a stranger for good.
assert '#define LMVSquidPanelSlotSignatureMemory 4' in module
assert 'static NSArray *LMVSquidPanelSlotSigSets[LMVSquidPanelSlotCount];' in module
assert 'static void LMVSquidPanelStoreSlot(NSInteger slot,NSArray *set) {' in module
assert 'static void LMVSquidPanelSigSetsClear(NSInteger slot) {' in module
assert 'if(![LMVSquidPanelSlotSigSets[i] containsObject:sig])continue;' in module
assert 'while(set.count>(NSUInteger)LMVSquidPanelSlotSignatureMemory)[set removeObjectAtIndex:0];' in module
assert 'return @[@"SquidPanelVideo",@"SquidPanel2Video",@"SquidPanel3Video",@"SquidPanel4Video"];' in module
assert 'return @[@"SquidPanelSlot1Sig",@"SquidPanelSlot2Sig",@"SquidPanelSlot3Sig",@"SquidPanelSlot4Sig"];' in module
# 1.54: the slots are named the way the user names the gestures - 右一 = 右上滑 and so
# on - so a log line and the four material rows use the same words.
assert 'return @[@"右一·右上滑",@"右二·右上上滑",@"左一·左上滑",@"左二·左上上滑"];' in module
# Even slot = the tall "上滑" panel, odd = the short "上上滑" one; which of the two a
# panel is comes out of the pair ordering below, never from a helper that could go
# unused (the build is -Werror, and an unused static in this header fails it).
assert 'LMVSquidPanelSlotIsShort' not in module
for name in re.findall(r'^static [\w \*]+?(LMVSquidPanel\w+)\(', module, re.M):
    assert module.count(name) + tweak.count(name) > 1, f'unused static {name} (the build is -Werror)'
# ...and no C TYPE NAME used as a variable: `short` broke 1.51 and 1.53 the same way.
for m in re.finditer(r'\b(?:CGFloat|NSInteger|NSUInteger|int|double|float|BOOL) (short|long|register|auto|signed)\b', module):
    raise AssertionError(f"{m.group(1)} is a C type name, not a variable name")
# 1.47/1.48 identity, now per slot: a CONTENT signature that carries no height and no
# width - the icon count - because the device log killed both of the earlier keys
# keys (the card object is re-created on every open; the height is what the user edits).
assert 'static __weak UIView *LMVSquidPanelTallCard' not in module    # object memory is gone
assert 'static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];' in module
# 1.55: a slot remembers EVERY signature it was seen as - the 1.54 report is that editing
# a panel's layout changed its icon count and the panel became a stranger for good.
assert '#define LMVSquidPanelSlotSignatureMemory 4' in module
assert 'static NSArray *LMVSquidPanelSlotSigSets[LMVSquidPanelSlotCount];' in module
assert 'static void LMVSquidPanelStoreSlot(NSInteger slot,NSArray *set) {' in module
assert 'static void LMVSquidPanelSigSetsClear(NSInteger slot) {' in module
assert 'if(![LMVSquidPanelSlotSigSets[i] containsObject:sig])continue;' in module
assert 'while(set.count>(NSUInteger)LMVSquidPanelSlotSignatureMemory)[set removeObjectAtIndex:0];' in module
assert 'static NSString *LMVSquidPanelShapeSig;' in module
assert 'static NSString *LMVSquidPanelShapeReason=@"none";' in module
assert 'static NSUInteger LMVSquidPanelIconCount(UIView *card) {' in module
assert 'if([child isKindOfClass:UIButton.class])count++;' in module
assert 'static NSString *LMVSquidPanelContentSignature(UIView *card,UIWindow *window) {' in module
# 1.53: `icons{n}|pc{0/1}` only - the 1.52 log showed the page-control width changing
# with the orientation (dots55 in portrait, dots38 in landscape for the SAME panel), so
# it made every rotation look like a brand-new panel.
assert 'return [NSString stringWithFormat:@"icons%lu|pc%d",(unsigned long)icons,page?1:0];' in module
assert '|dots' not in module.split('static NSString *LMVSquidPanelContentSignature')[0] or True
# the migration drops every stored signature that still carries it
assert 'rangeOfString:@"|dots"]' in module
assert 'LMVDiagnostic(@"squid-panel-migrate slots=4 (signatures now carry no dots, so a rotation keeps the panel)");' in module
assert 'if([NSStringFromClass(sub.class) containsCaseInsensitiveString:@"PageControlContentView"' if False else 'if([NSStringFromClass(sub.class) containsString:@"PageControlContentView"])' in module
assert 'static NSUInteger LMVSquidPanelSignatureIcons(NSString *sig) {' in module
assert 'static NSUInteger LMVSquidPanelSignatureDistance(NSUInteger icons,NSString *sig) {' in module
# (a) a signature seen before settles it outright.
assert 'static NSInteger LMVSquidPanelResolveSlot(UIView *card,UIWindow *window) {' in module
assert 'NSString *sig=LMVSquidPanelContentSignature(card,window);' in module
assert 'NSString *reason=[NSString stringWithFormat:@"sig-slot%d",(int)i+1];' in module
assert 'NSUInteger d=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[i]);' in module
# (b) 1.54: an unknown panel takes the NEXT EMPTY SLOT - 右一 → 右二 → 左一 → 左二 - and
# NOTHING guesses which side it is on. Guessing is what kept swapping 右二 and 左一: the
# 1.53 rule sent an unknown panel to "the side that had learned nothing yet", so 右二 -
# arriving while the left side was empty - was recorded as 左二, and every later panel was
# then placed relative to that wrong record.
assert 'NSInteger freeSlot=NSNotFound;' in module
assert 'if(!LMVSquidPanelSlotSigs[i].length){freeSlot=i;break;}' in module
assert 'NSString *reason=[NSString stringWithFormat:@"new@slot%d",(int)freeSlot+1];' in module
assert 'if(LMVSquidPanelOrderPair(tallOfPair,shortOfPair,landscape)>0)' in module
assert 'reason=[reason stringByAppendingString:@"+pair-swapped"];' in module
# ...and a full table means an EDITED panel. 1.55: scored by the height in this
# orientation first (a layout edit moves the icon count, not the size) plus the icon
# count, and only stored when the winner is clear - a coin flip is played, never saved.
assert 'CGFloat score=gap+(CGFloat)d*6;' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"edited-%@-slot%d",clear?@"adopted":@"unclear",(int)best+1];' in module
assert 'BOOL clear=(second==NSNotFound) || (secondScore-bestScore>20);' in module
# An edit that left the height alone is recognised outright, even while a slot is still
# empty - otherwise it looked like the panel that slot was waiting for.
assert 'if(recorded>0 && height>0 && fabs(height-recorded)<=2) { if(!matches)match=i; matches++; }' in module
assert 'if(matches==1) {' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"edited-height-slot%d",(int)match+1];' in module
# 1.53's side guessing is gone for good - a rule that only ever guessed.
for dead in ('rightComplete', 'leftComplete', 'leftSide', 'sideTag', 'shortPanel'):
    assert dead not in module, f'the side-guessing rule is back: {dead}'
# The slots a previous rule wrote cannot be trusted, so upgrading clears them by itself
# instead of making the user tap 重置面板识别.
assert '#define LMVSquidPanelLearnGeneration 3' in module
assert 'CFSTR("SquidPanelLearnVersion")' in module
# ...and WITHIN a side the two panels order themselves, which is what makes the whole
# thing automatic: 上滑 is the taller one of the pair (device logs: left 上滑
# icons8/180pt against left 上上滑 icons4/95pt, right 50/435 against 29/350), with the
# icon count breaking a tie so a user who made them the same height still sorts out.
# 1.53: one height per slot PER ORIENTATION - a card is 435pt in portrait and 340pt in
# landscape, and comparing across them (the 1.52 log's `pair=350/340`) swapped a correct
# pair. The icons are the orientation-proof fallback.
assert 'static CGFloat LMVSquidPanelSlotHeights[LMVSquidPanelSlotCount][2];' in module
assert 'static BOOL LMVSquidPanelLandscape(UIWindow *window) {' in module
assert 'static CGFloat LMVSquidPanelHeightInOrientation(NSInteger slot,BOOL landscape) {' in module
assert 'static int LMVSquidPanelOrderPair(NSInteger tallSlot,NSInteger shortSlot,BOOL landscape) {' in module
assert 'return @[@"SquidPanelSlot1H",@"SquidPanelSlot2H",@"SquidPanelSlot3H",@"SquidPanelSlot4H"];' in module
assert 'static void LMVSquidPanelNoteHeight(NSInteger slot,CGFloat height,BOOL landscape) {' in module
assert 'static void LMVSquidPanelMoveSlot(NSInteger from,NSInteger to) {' in module
assert 'static int LMVSquidPanelOrderPair(NSInteger tallSlot,NSInteger shortSlot,BOOL landscape) {' in module
# An already-recorded pair that contradicts its slots swaps itself on sight, and an
# edited panel keeps the slot it owns (closest icon count, nothing moves).
assert 'NSInteger tallOfPair=(i<2)?0:2, shortOfPair=(i<2)?1:3;' in module
assert 'if(LMVSquidPanelOrderPair(tallOfPair,shortOfPair,landscape)>0) {' in module
assert 'LMVSquidPanelShapeReason=[reason stringByAppendingString:@"+pair-swapped"];' in module
# 1.57/1.58: the 1.56 log named the chain SFActivityPanelView > UIControl >
# SFActivityAction - SFActivityAction is the gesture plugin's own object, so it is asked
# what it calls itself. 1.58 reads EVERY property: the 1.57 log showed SFActivityAction
# carrying `location` and `title`, and `location` matched none of the names 1.57 guessed,
# so the field that looked most like a fixed gesture name was never read at all.
# Read-only, only where the getter exists: no side effects, no unguarded valueForKey.
assert 'static void LMVSquidPanelDescribeIdentity(UIView *view,NSMutableString *out) {' in module
assert 'class_copyPropertyList' in module and 'free(properties)' in module
assert 'squid-panel-identity ptr=%p%@' in module
probe = module[module.index('static void LMVSquidPanelDescribeIdentity'):module.index('// The chain of class names')]
assert 'performSelector' not in probe and '@try' not in probe
assert probe.count('respondsToSelector') == 3 and probe.count('valueForKey') == 2
assert 'for(NSUInteger pass=0;pass<2;pass++) {' in probe        # likely names first, then the rest
# UIKit layers are named and left alone: their property lists are dozens of tweaks'
# additions (adPrivacyData, pointerInteraction, a cardSectionViewIdentifier every panel
# reports identically) and they drown the two lines that matter.
assert 'if([className hasPrefix:@"UI"])return;' in probe
# 1.59: the published properties were not enough - location=2 on all four (a constant, not
# a gesture number) and title=nil - so what the class keeps privately is read too: the
# ivars (including their values, KVC finds the ivar behind a name) and the methods whose
# names look like they answer "which gesture is this?".
assert 'class_copyIvarList' in probe and 'class_copyMethodList' in probe
assert 'if(![name hasPrefix:@"_"])continue;' in probe
for needle in ('{i:%@}', '{m:%@}', '~%@=%@'):
    assert needle in probe, needle
# ...and WHERE the panel sits: if all four live under one parent, the order is the number.
assert 'static void LMVSquidPanelDescribeSiblings(UIView *card,UIWindow *window,NSMutableString *out) {' in module
assert 'SFActivityAction"]){action=node;break;}' in module
assert 'idx=%lu/%lu' in module
assert '@"location"' in probe and '@"title"' in probe
assert '@"hash",@"superclass",@"description",@"debugDescription"' in probe
for needle in ('direction', 'edge', 'side', 'gesture'):
    assert needle in probe, f'the fixed name would probably read as {needle}'

# 1.56: ...and so is the plugin's OWN configuration - where a fixed gesture name can only
# come from. Read-only, once per session, names and top-level keys only: no gesture data.
assert 'static void LMVSquidPanelScanGesturePrefs(void) {' in module
assert 'squid-gesture-prefs%@' in module
assert '@"/var/mobile/Library/Preferences"' in module
# 1.60: the plugin is SquidForce (its panel is built with initWithActivityItems:
# applicationActivities:imageSize:location:). Guessing at file NAMES only matched Apple's
# own activity plists, so every com.squidforce.* file is listed - with a peek at its
# structure, since that is where a fixed gesture number has to live.
assert '@"com.squidforce."' in module
assert '@"/var/mobile/Library"' in module
assert 'unreadable' in module
assert '@"lclrc"' in module          # SquidGesture Pro's own bundle prefix
assert '@[@"prefs",@"/var/mobile/Library/Preferences"]' in module   # roots now tagged
scan = module[module.index('static void LMVSquidPanelScanGesturePrefs'):module.index('// The chain of class names')]
assert 'dictionaryWithContentsOfFile' in scan and 'LMVDiagnostic' in scan
assert 'setObject' not in scan and 'writeToFile' not in scan      # read-only, never a write
assert 'if(!LMVDiagnosticsEnabled.load())return;' in scan

# 1.61: the tweak is SquidGesture Pro (com.lclrc.squidgesturepro, author SquidForce - the
# SF in SFActivityPanelView). Its settings plist is NOT in Preferences either, so three
# things are read that do not depend on guessing a file name: (a) every non-Apple entry
# of the places a tweak can keep data, directories marked with a slash - a directory is
# what a name scan cannot see because contentsOfDirectoryAtPath never walks into one;
# (b) the plugin's own classes by name (SG*/Squid*/SF*) - the gesture must be an object
# of its own, and whichever class looks like the gesture model is what the next round
# reads; (c) the panel's _activityItems through the ivar - the actions are a finer
# signature than the icon count, which collides the moment two gestures carry the same
# number of actions.
assert 'static void LMVSquidPanelListPaths(void) {' in module
assert 'squid-paths%@' in module
assert '@"/Library"' in module and '@"/var/mobile/Library/Caches"' in module
assert '@"/Library/PreferenceLoader/Preferences"' in module
assert '@"/var/mobile/Library/SpringBoard"' in module
assert 'stringByAppendingString:@"/"]' in module
paths = module[module.index('static void LMVSquidPanelListPaths'):module.index('// 1.62: the plugin\'s OWN image')]
assert 'fileExistsAtPath' in paths and 'caseInsensitiveCompare' in paths
assert 'setObject' not in paths and 'writeToFile' not in paths
assert 'if(!LMVDiagnosticsEnabled.load())return;' in paths

# 1.62: the prefix listing was useless (SG is shared with Apple's Mail classes and
# SquidExtender's JS classes; the cap filled with those and the plugin's own classes never
# made the list). A class knows its image, and the image IS the plugin's binary: find it
# through a class that is certainly the plugin's, list EVERY class in that image, and read
# the image's strings - the tweak has to name its storage somewhere, and the binary is
# where that path is written down.
assert 'static NSString *LMVSquidPanelPluginImage(void) {' in module
assert 'static void LMVSquidPanelListPluginClasses(void) {' in module
assert 'static void LMVSquidPanelPluginStrings(void) {' in module
assert 'class_getImageName' in module and 'objc_copyClassList' in module
assert 'squid-plugin image=%@ classes(%lu):%@' in module
assert 'squid-plugin-strings paths(%lu):%@' in module
assert 'squid-plugin-keys(%lu):%@' in module
assert 'dataWithContentsOfFile' in module
assert 'NSClassFromString(name)' in module
strings = module[module.index('static BOOL LMVRunContains'):module.index('// 1.57: what the panel')]
assert '"/var"' in strings and '".plist"' in strings and '"/Library"' in strings
assert '"/System"' in strings and '"/usr/"' in strings          # Apple's own paths excluded
assert '"squid"' in strings and '"gesture"' in strings
assert 'setObject' not in strings and 'writeToFile' not in strings
# ...and the actions themselves, straight through the ivar: no getter, no KVC, nothing throws
assert 'class_getInstanceVariable(cls,"_activityItems")' in module
assert 'id items=object_getIvar(view,itemsIvar);' in module
assert "ivar_getTypeEncoding(itemsIvar)[0]=='@'" in module
assert '{a:%lu%@}' in module

# 1.56: a fixed identity has to come from something the plugin wrote and the user cannot
# edit, so the card's own subtree is logged with tag / accessibilityIdentifier /
# restorationIdentifier / label text - that log is what the next rule gets built from.
assert 'static void LMVSquidPanelIdentityTree(UIView *view,NSUInteger depth,NSMutableString *out,NSUInteger *nodes) {' in module
assert 'if(view.accessibilityIdentifier.length)[out appendFormat:@"aid=%@",view.accessibilityIdentifier];' in module
assert 'if(view.restorationIdentifier.length)[out appendFormat:@"rid=%@",view.restorationIdentifier];' in module
assert 'if([view respondsToSelector:NSSelectorFromString(@"text")]) {' in module
assert 'static NSString *LMVSquidPanelCardChain(UIView *card,UIWindow *window) {' in module
assert 'LMVDiagnostic([NSString stringWithFormat:@"squid-panel-tree ptr=%p chain=%@ %@",' in module
# ...and `text` is not a UIView property, so it is only asked for where it exists.
reader = module[module.index('static void LMVSquidPanelIdentityTree'):module.index('// 1.57: what the panel')]
assert reader.count('respondsToSelector') == 1 and 'performSelector' not in reader and '@try' not in reader
assert 'accessibilityIdentifier' in reader and 'restorationIdentifier' in reader

# (d) 1.53: nothing manual is left - an unknown panel is always placed by the rules
# above, and one row ("重置面板识别") exists only to clear a record that went wrong.
assert 'LMVSquidPanelBindLastSeen' not in module and 'LMVSquidPanelClaimToken' not in module
# 1.52: and the one repair that pair ordering cannot do by itself - clearing a side that
# was written wrong (the ordering only sorts a side while it is HALF unknown).
assert 'static void LMVSquidPanelForgetAll(void) {' in module
assert 'CFSTR("SquidPanelResetToken")' in module
assert 'LMVDiagnostic(@"squid-panel-reset slots=4 (all four will be re-learned)");' in module
assert 'for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {' in module
# 1.48's pair seeds the two right-hand slots, so a device that already knew its right
# panels keeps that knowledge; the 1.47 key generation itself is gone.
assert 'NSArray *seeds=@[@"SquidPanelTallSig2",@"SquidPanelShortSig2"];' in module
assert 'CFSTR("SquidPanelTallSig")' not in module and 'CFSTR("SquidPanelShortSig")' not in module
# Attached under everything the card draws, and re-sized to the card every poll.
# 1.23: the card may BE the panel's blur material, and a UIVisualEffectView refuses
# direct subviews - adding one raises, and an exception in a run-loop callback
# aborts SpringBoard (the 1.22 safe-mode crash). The effect view is therefore never
# the container: the host goes into its superview directly below it.
assert '- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {' in module
assert 'if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;' in module
assert '@try {[container insertSubview:self.host atIndex:index];}' in module
assert '@catch(NSException *exception) {[self.host removeFromSuperview];return NO;}' in module
# 1.24: and it must sit UNDER the icons but ABOVE that material - 1.23 placed it
# below the material, which hid it (device report: 看不到视频背景).
assert 'if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;' in module
assert 'UIView *content=((UIVisualEffectView *)material).contentView;' in module
assert 'container=content;index=0;mode=@"content";' in module
assert 'index=(NSUInteger)(near+1);mode=@"above-material";' in module
assert 'if(!container) {container=card;index=0;}' in module
# 1.44: the host fills the CARD, not the container it happens to live in. In
# landscape the material (and the content view inside it) is a full-screen
# 932x435 view while the card is 814x180, so container-sized video overflowed the
# panel instead of filling it.
assert 'CGRect cardInContainer=[card convertRect:card.bounds toView:container];' in module
assert 'CGRect target=CGRectIntersection(container.bounds,cardInContainer);' in module
assert 'if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;' in module
# Defence in depth: no failure in this channel may ever abort SpringBoard.
assert '@try {[LMVSquidPanelVideo update];}' in module
assert '@catch(NSException *exception) {[LMVSquidPanelVideo detach];}' in module
assert 'slot=%d gesture=%@ play=%@' in module
assert 'mode=%@' in module
assert 'UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;' in module
assert 'if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;' in module
# Our own host can never be mistaken for the card while the search walks the tree.
assert 'static NSInteger const LMVSquidPanelHostTag=0x5A17;' in module
assert 'if(child.tag==LMVSquidPanelHostTag || child.hidden || child.alpha<.01)continue;' in module
assert 'self.tag=LMVSquidPanelHostTag;' in module
# Never interactive, never a poster substitute for a live panel background.
assert 'self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;' in module
assert 'self.playback.posterLayer.hidden=YES;' in module
assert 'BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;' in module
# Preferences: own switch, four material slots, master switch respected, default off.
assert 'CFSTR("SquidPanelBackgroundEnabled")' in module
assert 'LMVSquidPanelSlotPaths[i]=LMVCCSelectedPath(keys[i]);' in module
assert 'LMVSquidPanelSlotRevisions[i]=LMVLockVideoRevision(LMVSquidPanelSlotPaths[i]);' in module
assert 'LMVSquidPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# 1.44/1.45/1.50: the verdict picks the slot, and the four slots are INDEPENDENT - there
# is no fallback between them, by request: a panel whose slot is empty gets no video
# (and no sound) at all, rather than borrowing another panel's material.
assert 'NSInteger slot=LMVSquidPanelResolveSlot(card,window);' in module
assert '?LMVSquidPanelPath:LMVSquidPanelPath2' not in module        # never crosses over
assert 'if(!wantPath.length || !wantRevision.length) {' in module
assert '"squid-panel slot=%d empty=%@ (no video, by design)"' in module
# 1.46: the manual override, for the one case identity cannot fix - the very first
# content test guessing the two panels the other way round.
assert 'static BOOL LMVSquidPanelEnabled,LMVSquidPanelPrefsKnown,LMVSquidPanelSwapShapes;' in module
assert 'CFSTR("SquidPanelSwapShapes")' in module
# 1.50: "对调" now swaps the two shapes WITHIN a side (0<->1, 2<->3), so it can never
# mix up the left and right materials.
assert 'NSInteger wantSlot=slot;' in module
assert 'if(LMVSquidPanelSwapShapes)wantSlot=slot^1;' in module
assert 'NSString *wantPath=LMVSquidPanelSlotPaths[wantSlot];' in module
assert 'NSString *wantRevision=LMVSquidPanelSlotRevisions[wantSlot];' in module
# 1.46: the log names the slot, the reason for the verdict and the card object, so a
# wrong pick is one line away from being explained.
assert 'slot=%d gesture=%@ play=%@ why=%@ sig=%@ pc=%d dots=%.0f pair=%.0f/%.0f slots=%d%d%d%d seen=%.0fs mode=%@' in module
assert '(int)(LMVSquidPanelSlotSigs[0].length>0),(int)(LMVSquidPanelSlotSigs[1].length>0),' in module
assert 'pageControl?(int)pageControl.hidden:-1,' in module
assert 'LMVSquidPanelHeightInOrientation(slot<2?0:2,landscapeNow),' in module
assert 'LMVSquidPanelHeightInOrientation(slot<2?1:3,landscapeNow),' in module
assert '(int)slot+1,LMVSquidPanelSlotTitles()[slot],LMVSquidPanelSlotTitles()[wantSlot],' in module
assert 'LMVSquidPanelShapeReason,LMVSquidPanelShapeSig,' in module
assert 'ptr=%p' in module and '(void *)self.card,' in module
assert 'if(changed) {[self.host removeFromSuperview];[self.playback selectPath:wantPath revision:wantRevision];}' in module
# No player/UI while the channel is off (any single slot may be the only one set), and a
# poll that never runs hot when idle.
assert 'for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++)' in module
assert 'if(LMVSquidPanelSlotPaths[i].length && LMVSquidPanelSlotRevisions[i].length)anySlot=YES;' in module
assert 'if(!LMVSquidPanelEnabled || !anySlot) {' in module
assert 'if(!LMVSquidPanelVideo)LMVSquidPanelVideo=[LMVSquidPanelVideoManager new];' in module
assert 'NSTimeInterval want=LMVSquidPanelEnabled?.1:.5;' in module
assert 'dispatch_async(dispatch_get_main_queue()' not in module  # poll on the main run loop only

# ---- wiring ---------------------------------------------------------------
assert '#import "LMVSquidPanelVideo.h"' in tweak
assert '    LMVSquidPanelVideoRefresh(reload);' in tweak
assert tweak.count('LMVSquidPanelVideoSuspend();') == 2          # suspend + resign-active
assert '        LMVSquidPanelVideoInstallHooks();' in tweak
assert 'LMVAudioConsume(@"SquidPanel",panel.path,panel.revision,panelVisible,panel.player.currentTime);' in tweak
assert 'return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"];' in audio

# ---- the two settings surfaces -------------------------------------------
assert '[squidPanelEnabled setProperty:@"SquidPanelBackgroundEnabled" forKey:@"key"];' in prefs
assert '[squidPanelEnabled setProperty:@NO forKey:@"default"];' in prefs
assert 'squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);' in prefs
assert '- (void)switchSquidPanel:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel"]; }' in prefs
# 1.44: the second slot, named after the gesture (the shape is the same in both
# orientations), and it is routed exactly like the first one.
assert 'squidPanelMaterial2.buttonAction = @selector(switchSquidPanel2:);' in prefs
assert '[squidPanelMaterial2 setProperty:@"SquidPanel2Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel2:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel2"]; }' in prefs
# 1.50: the left-hand pair, plus the row that settles which gesture owns a panel.
assert 'squidPanelMaterial3.buttonAction = @selector(switchSquidPanel3:);' in prefs
assert '[squidPanelMaterial3 setProperty:@"SquidPanel3Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel3:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel3"]; }' in prefs
assert 'squidPanelMaterial4.buttonAction = @selector(switchSquidPanel4:);' in prefs
assert '[squidPanelMaterial4 setProperty:@"SquidPanel4Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel4:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel4"]; }' in prefs
assert '@"SquidPanel3":@"",@"SquidPanel4":@"",@"AT":@""' in delete
assert '@"SquidPanel3",@"SquidPanel4",@"AT",@"CV"]' in delete
assert '@"SquidPanel": @"右一·右上滑面板背景视频"' in prefs
assert '@"SquidPanel2": @"右二·右上上滑面板背景视频"' in prefs
assert '@"SquidPanel3": @"左一·左上滑面板背景视频"' in prefs
assert '@"SquidPanel4": @"左二·左上上滑面板背景视频"' in prefs
assert '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];' in prefs
assert '切换右一素材（右上滑）' in prefs and '切换右二素材（右上上滑）' in prefs
assert '切换左一素材（左上滑）' in prefs and '切换左二素材（左上上滑）' in prefs
assert 'static NSInteger LMVEasterSquidPanelSection(void) { return LMVEasterHomeMenuSection() + 1; }' in panel
# 1.53: nine rows - switch, four materials, the reset row, the swap row, sound, volume.
# The sound pair sits at 7/8, which is also what stops the volume row from rendering as
# a second "播放声音" switch (the report that started 1.50).
assert 'if (section == LMVEasterSquidPanelSection()) return 9;' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return @"鱿鱼面板背景视频";' in panel
assert 'if (section == LMVEasterSquidPanelSection() && (row == 7 || row == 8)) return @"SquidPanel";' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return row == 8;' in panel
assert 'static NSArray *LMVEasterSquidKeys(void) {' in panel
assert 'return @[@"SquidPanelVideo", @"SquidPanel2Video", @"SquidPanel3Video", @"SquidPanel4Video"];' in panel
assert 'return @[@"切换右一素材（右上滑）", @"切换右二素材（右上上滑）", @"切换左一素材（左上滑）", @"切换左二素材（左上上滑）"];' in panel
assert 'toggle.on = [LMVEasterRead(@"SquidPanelBackgroundEnabled") boolValue];' in panel
assert 'cell.textLabel.text = LMVEasterSquidTitles()[index.row - 1];' in panel
assert 'id selected = LMVEasterRead(LMVEasterSquidKeys()[index.row - 1]);' in panel
# 1.46: the swap row, in Settings (a switch, keyed) and in the floating panel (a
# button - the panel's switches are told apart by tag and every tag is a section).
assert '[squidPanelSwap setProperty:@"SquidPanelSwapShapes" forKey:@"key"];' in prefs
assert 'squidPanelSwap.buttonAction' not in prefs
assert 'cell.textLabel.text = @"对调上滑 / 上上滑素材";' in panel
assert 'cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";' in panel
assert 'LMVEasterSet(@"SquidPanelSwapShapes", @(!now));' in panel
assert 'if (index.row < 1 || index.row > 4) return;\n        key = LMVEasterSquidKeys()[index.row - 1];' in panel
# 1.53: the manual claim is gone - the four panels are worked out by the runtime alone.
assert 'claimSquidPanel' not in panel and 'LMVEasterChoice' not in panel
assert 'claimSquidPanel' not in prefs
assert 'if (index.row == 5) { [self resetSquidPanel]; return; }' in panel
assert 'cell.textLabel.text = @"重置面板识别";' in panel
assert 'LMVEasterSet(@"SquidPanelResetToken", [NSString stringWithFormat:@"%.3f", NSDate.date.timeIntervalSince1970]);' in panel
assert 'squidPanelReset.buttonAction = @selector(resetSquidPanel:);' in prefs
assert '- (void)resetSquidPanel:(PSSpecifier *)specifier {' in prefs
assert 'CFPreferencesSetAppValue(CFSTR("SquidPanelResetToken")' in prefs
# 1.46: the swap row, in Settings (a switch, keyed) and in the floating panel (a
# button - the panel's switches are told apart by tag and every tag is a section).
assert '[squidPanelSwap setProperty:@"SquidPanelSwapShapes" forKey:@"key"];' in prefs
assert 'squidPanelSwap.buttonAction' not in prefs
assert 'cell.textLabel.text = @"对调上滑 / 上上滑素材";' in panel
assert 'cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";' in panel
assert 'LMVEasterSet(@"SquidPanelSwapShapes", @(!now));' in panel
assert 'if (index.row < 1 || index.row > 4) return;\n        key = LMVEasterSquidKeys()[index.row - 1];' in panel
# 1.50: the claim row is a PUSHED chooser, never a presented sheet (the floating panel
# owns no presentation role - see tests/panel-roles.py), and it writes the slot + token.
# 1.52: and the repair row, for a record the manual claim wrote wrong (the device log
# showed the right 435pt panel stored under 左边上上滑, which parks every later panel on
# "edited-nearest"). Clearing is one tap and the automatic rules take over again.
assert 'if (index.row == 5) { [self resetSquidPanel]; return; }' in panel
assert 'cell.textLabel.text = @"重置面板识别";' in panel
assert 'LMVEasterSet(@"SquidPanelResetToken", [NSString stringWithFormat:@"%.3f", NSDate.date.timeIntervalSince1970]);' in panel
assert 'squidPanelReset.buttonAction = @selector(resetSquidPanel:);' in prefs
assert '- (void)resetSquidPanel:(PSSpecifier *)specifier {' in prefs
assert 'CFPreferencesSetAppValue(CFSTR("SquidPanelResetToken")' in prefs
assert 'presentViewController:' not in panel
assert "else if (toggle.tag == LMVEasterSquidPanelSection()) key = @\"SquidPanelBackgroundEnabled\";" in panel
print('PASS: SquidGesturePro panel channel - poll-based attach that fills the card, FOUR material '
      'slots (right and left 上滑/上上滑): an ORIENTATION-INDEPENDENT CONTENT SIGNATURE (icons + '
      'page-control presence) identifies a panel the user has edited, an unknown one belongs to the side '
      'that learned nothing yet, and the two panels of that side ORDER THEMSELVES by height - '
      'kept per orientation, with the icon count as the orientation-proof tiebreak - so portrait '
      'and landscape reach the same slot and no manual step is needed; an inverted record swaps '
      'itself, "重置面板识别" is the only repair row, one shared sound pair, both surfaces')

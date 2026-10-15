#!/usr/bin/env python3
"""Exercise the actual Desktop manager/hooks with Foundation and real CALayers."""
from pathlib import Path
import ast,platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVDesktopVideo.h').read_text();s=(r/'Tweak.xm').read_text()
assert '#import "LMVDesktopVideo.h"' in s and 'LMVDesktopVideoRefresh(reload)' in s
assert 'LMVDesktopVideoInstallHooks()' in s and 'LMVDesktopVideoSuspend()' in s
assert 'LMVCacheFrame' not in h and 'LMVAcquireOriginal' not in h
assert 'LMVDesktopExplicitWallpaper' in h and 'homescreenWallpaperView' in h
assert 'sharedWallpaperView' not in h  # Ambiguous Lock/Home source must not be used.
# 0.0.138: while a cover or a SpringBoard presentation is up, the surface is
# only hidden, never torn down (a teardown restored the wallpaper lease and the
# original wallpaper showed through the translucent switcher).
assert 'BOOL appForeground=!definitiveAway && !visible &&' in h
assert '(retainedAttachment || switcherPresented || ccPresented || sheetCover);' in h
assert 'static BOOL LMVDesktopSwitcherPresented(void) {' in h
assert 'static BOOL LMVDesktopControlCenterPresented(void) {' in h
assert '[@"SBMainSwitcherControllerCoordinator",@"SBAppSwitcherController"]' in h
assert 'LMVDesktopBoolSelector(shared,@"isAnySwitcherVisible")' in h
assert 'LMVDesktopBoolSelector(shared,@"isVisible")' in h
# 1.15: a presented switcher/CC keeps the freeze only while the cover probe can
# still see its surface - the SpringBoard flag flips a whole animation late.
assert '- (void)classifyPresentationForCoverOnScreen:(BOOL)coverOnScreen {' in h, 'the pixels decide when a presentation releases the desktop'
assert 'BOOL switcherPresented=self.effectiveSwitcherPresented;' in h
assert 'BOOL ccPresented=self.effectiveControlCenterPresented;' in h
assert 'self.effectiveSwitcherPresented=switcher && !(self.switcherSawCover && !coverOnScreen);' in h, 'a released switcher stops holding the freeze'
assert 'self.effectiveControlCenterPresented=cc && !(self.ccSawCover && !coverOnScreen);' in h, 'a released Control Center stops holding the freeze'
assert 'if (switcher) {if (coverOnScreen) self.switcherSawCover=YES;} else self.switcherSawCover=NO;' in h, 'the probe must have seen the surface to be believed'
assert 'if (cc) {if (coverOnScreen) self.ccSawCover=YES;} else self.ccSawCover=NO;' in h
assert '[self classifyPresentationForCoverOnScreen:coverOnScreen];' in h, 'the update classifies against the geometry'
assert '[self classifyPresentationForCoverOnScreen:switcherCover||ccCover||sheetCover||appCover||!CGRectIsEmpty(cover)];' in h, 'the watcher classifies every frame'
# 1.15: an exposed desktop is its own proof that Home is what is on screen.
assert 'BOOL coverOnScreen=switcherCover||ccCover||sheetCover||appWindowCover||!CGRectIsEmpty(cover);' in h
assert 'BOOL desktopExposed=self.geometryCoverSeen && !coverOnScreen && !unknownCover;' in h, 'only a probe that has seen a cover may trust an empty one'
assert '(foreground==1 || homeConfirmed || desktopExposed) && !unknownCover;' in h, 'the exposed desktop replaces the lagging frontmost probe'
assert 'pixels && appForeground && retainedAttachment && self.lease' in h
assert 'if (diagnostics)' in h
assert 'static void LMVDesktopRequestUpdate' in h and '- (void)syncGeometry' in h
assert 'LMVRequestSafeUpdate' not in h, 'Desktop hooks must not trigger global full passes'
assert 'BOOL geometryChanged=' in h and 'if(!content.hidden)' in h

# 0.0.123: opening an app must not fall back to the original wallpaper. `home=1`
# holds steady while the frontmost probe flips to -1 for the launch, so the probe
# may never veto a confirmed Home view (it did, and the surface was torn down).
assert 'foreground>=0 &&' not in h
assert 'BOOL environment=screenKnown && !blank && lockKnown && self.authenticatedSession &&' in h
assert '(foreground==1 || homeConfirmed || desktopExposed) && !unknownCover;' in h, 'an exposed desktop is accepted on its own (1.15)'

# 0.0.124: backboardd was burning CPU compositing the desktop video layer while an
# opaque surface fully covered it. The layer is hidden only when BOTH independent
# proofs hold for a full grace period - the cover geometry AND the frontmost probe -
# so a probe flap or an app-launch transition can never hide a desktop the user is
# looking at, and the layer is never detached (recovery is instant, no wallpaper
# flash). `composited`/`decode`/`opaque` expose the state in the log.
# 0.0.137: the switcher/CC/NC hide the layer at fg==1 too; hiding behind a
# translucent surface is safe because the suppress-lease stays applied - the
# wallpaper can never show through the blur (the leak fix), and only a FULL
# notification pull restores it on purpose. An UNKNOWN cover HOLDS (no
# teardown -> no lease restore) instead of tearing down - the in-app swipe-up
# switcher leak was the teardown restoring the wallpaper mid-transition.
assert 'if (covered && (foreground!=1 || switcherCover || ccCover || sheetFullCover)) {' in h
assert 'BOOL opaqueCover=covered && self.coveredSince>0 && holdNow-self.coveredSince>=0.3;' in h
assert 'BOOL definitiveAway=!configured || !screenKnown || blank || !lockKnown || locked ||' in h
assert 'self.playback.error!=nil;' in h
# 0.0.137: a GENUINE unknown (no CoverSheet content) still fails closed, while
# the transient invalid-rect flap is a silent skip - that flap was restoring the
# wallpaper lease and leaking the original wallpaper through the switcher blur.
assert 'unknownCover || self.playback.error' in h, 'a genuine unknown cover still tears down (fail closed)'
assert 'if (!content) {*unknown=YES;continue;}' in h
assert h.count('if (!LMVLockVideoRectValid(converted)) continue;') >= 2, 'the CoverSheet transient flap is a silent skip'
assert h.count('if(self.host.hidden!=hostHidden)self.host.hidden=hostHidden;') == 2, 'both live branches use one rule'
assert 'self.host.hidden=YES;' in h, 'the real teardown still hides it'
assert 'shown=%d composited=%d decode=%d opaque=%d' in h

# 0.0.125: a foreground APPLICATION is the common fully-covered desktop, and the
# old probe (CoverSheet windows only) never saw it - the video composited and
# decoded behind the app the whole time, which is the backboardd CPU burn. The
# probe now whitelists always-opaque above-Home window classes only; everything
# else (status bar, snapshots, this tweak's own floating surfaces) stays
# excluded, and app-window conversion failures never set *unknown (that would
# tear the desktop down and flash the wallpaper).
assert 'window==destination || LMVDesktopHomeWindow(window) ||' in h
assert '![name isEqualToString:@"SBWindow"])) continue;' in h, 'the app surface SBWindow is recognised (1.15)'
assert 'BOOL covered=container && LMVDesktopFullyCovered(container,cover) && !appExitRelease;' in h, 'the release window is not a cover either (1.15)'
assert 'Class ccModule=NSClassFromString(@"LMVControlCenterVideoManager");' in h and 'controlCenterWindowIsEmpty' in h, 'the CC module answer is used when it is reachable (1.15)'
assert 'fullyCovered=NO;                                     // 1.15: not a cover at all' in h, 'the watcher is not silenced by a released cover (1.15)'
assert 'if (!appSurfaceWasUp) {self.appAway=NO;self.appLeftAt=0;}' in h, 'the release closes as soon as the app surface is gone (1.15)'
assert 'if (foreground==-1) {self.appAway=YES;self.appLeftAt=0;self.shellAtExit=NO;}' in h, 'the frontmost probe arms the release (1.15)'
assert 'if (self.shellAtExit) {switcherCover=NO;ccCover=NO;}' in h, 'only the shells that were already up at the exit are ignored (1.15)'
assert 'if (appNow-self.appLeftAt<=0.8)' in h, 'the release window is bounded (1.15)'
assert 'if (!LMVLockVideoRectValid(converted)) continue;' in h
# 0.0.126: the cover follows the app's ANIMATED frame, not the model frame that
# stays full-screen for the whole zoom - otherwise the wallpaper flashes on
# entering or leaving an app until the animation ends.
assert 'CALayer *presentation=window.layer.presentationLayer;' in h
assert 'CGRect converted=[window convertRect:(presentation?presentation.frame:window.frame) toWindow:destination];' in h
# 0.0.127: a FADING app window is already revealing the desktop (the exit
# cross-fade keeps the model frame full-screen until removal), so it is NOT a
# cover; and the freeze follows the frontmost probe so the player resumes the
# moment the desktop is exposed instead of when the window is finally removed.
assert 'if ((presentation && presentation.opacity<0.99) || window.alpha<0.99) continue;' in h
assert 'BOOL appWindowCover=NO,switcherCover=NO,ccCover=NO,sheetCover=NO,sheetFullCover=NO;' in h
assert 'LMVDesktopCoverRect(container.window,&unknownCover,&appWindowCover,&switcherCover,&ccCover,&sheetCover,&sheetFullCover)' in h
# 0.0.136: the 0.0.128 model - the desktop is either INVISIBLE (opaque full
# cover from app windows, no translucent contributor, fg!=1) and then the video
# freezes+hides, or it is VISIBLE and the video PLAYS under the translucent
# switcher/CC/NC blur and any fading app window - closing them needs no resume.
# 0.0.137: ANY full cover freezes video+audio immediately (the switcher/CC/NC
# at fg==1 included); play only when the desktop is exposed. Resume is the
# watcher's job (~16 ms), and a full NC pull restores the wallpaper on purpose.
# 0.0.138: the sheet (any pull), the switcher and the CC all freeze video AND
# audio; the SpringBoard state is authoritative so they freeze even when no
# covering window matched on this build.
# 0.0.140: the sheet freezes only at the BOTTOM of the pull (`covered`); during
# the pull the player keeps running (hidden layer, wallpaper behind) so the
# release resumes with zero delay. Switcher/CC freeze as soon as presented.
assert 'BOOL freeze=appForeground || (visible && (switcherPresented || ccPresented)) ||' in h
assert '(visible && covered && (sheetFullCover || switcherCover || ccCover || foreground!=1)),' in h
assert 'play=visible && !covered && !switcherPresented && !ccPresented && !(sheetFullCover && !self.sheetPreexisting);' in h
# the sheet hides the layer but must NOT stop the player - a stopped player is
# what made the release feel slow.
assert '} else if(!(sheetFullCover && !self.sheetPreexisting) && (self.playback.wantsPlayback || self.playback.frozen || self.playback.posterOnlyVisible))' in h
# 0.0.139: the layer hides only behind an OPAQUE APP cover or under a
# notification pull - behind the translucent switcher/CC the FROZEN frame stays
# visible (and the lease keeps the wallpaper hidden, so nothing leaks).
assert h.count('BOOL opaqueAppCover=opaqueCover && !(switcherCover || ccCover);') == 2
assert h.count('BOOL hostHidden=opaqueAppCover || (sheetFullCover && !self.sheetPreexisting);') == 2
assert 'if(self.host.hidden!=hostHidden)self.host.hidden=hostHidden;' in h
assert 'self.sheetWallpaperShown=YES;' in h
assert 'if (!sheetFullCover) self.sheetWallpaperShown=NO;' in h
assert 'self.sheetPreexisting=self.lastSheetCover;self.sheetWallpaperShown=NO;' in h, 'a sheet already up at suspend is pre-existing on wake'
assert h.count('self.sheetPreexisting=self.lastSheetCover;self.sheetWallpaperShown=NO;') == 1
# 1.15: the pull is classified FULL only when it really covers the screen
assert 'onScreen.size.width>=destination.bounds.size.width-1 &&' in h and        'onScreen.size.height>=destination.bounds.size.height-1) *sheetFullCover=YES;' in h, \
    'a pull is a full cover only once it covers the screen (same tolerance as the cover test)'
assert '*sheetCover=NO;*sheetFullCover=NO;' in h, 'the probe reports both flags'
assert 'BOOL held=presented || sheetFullCover ||' in h, 'the watcher silences while the frozen state still holds'
assert 'if (held) return;                            // still exactly what we froze on' in h
assert '} else if (!held) return;                        // still exactly what we play on' in h
# 1.15: the Control Center holds the desktop only while its CONTENT is on screen
# 1.15: the content probe is shared by the CC and the app/switcher surfaces
assert 'static CGFloat LMVDesktopContentCoverage(UIWindow *window,UIView *root,UIWindow *destination) {' in h, 'one content-coverage probe for every covering surface'
assert 'for (UIView *child in root.subviews) {' in h
assert 'CGFloat ccContent=LMVDesktopContentCoverage(window,root,destination);' in h and 'if (ccContent>=0 && ccContent<0.6) continue; // the content has left' in h, 'the CC window frame is not a cover once the content slid away'
assert 'CGFloat appContent=LMVDesktopContentCoverage(window,window.rootViewController.viewIfLoaded,destination);' in h and 'if (appContent>=0 && appContent<0.4) continue;' in h, 'an app/switcher window frame is not a cover once its content shrinks away'
assert 'desktop-cover-owner %@' in h, 'the log names the surface that holds the cover'
assert 'return (CGRectIsEmpty(onScreen)?0:onScreen.size.width*onScreen.size.height)/full;' in h, 'content that left the screen entirely counts as gone, not unmeasurable'
assert 'CALayer *paint=child.layer.presentationLayer;if (!paint) paint=child.layer;' in h, 'a missing presentation layer means not animating, not unmeasurable'
assert 'CGRect screenInWindow=[destination convertRect:destination.bounds toWindow:window];' in h, 'the screen rect is carried into the CC window (no cross-tree conversion)'
assert 'desktop-windows-skipped %@' in h, 'the skipped full-screen windows are listed for diagnosis'
# the unlock/withdrawal sheet must NOT show the wallpaper - only a pull the user
# performed on an already-visible desktop does.
assert 'if (sheetCover && !attachedBefore && self.host.superview!=nil) self.sheetPreexisting=YES;' in h, 'an attach under a sheet marks it pre-existing'
assert 'if (visible && sheetFullCover && !self.sheetPreexisting) {' in h, 'only a pull that covered the screen shows the wallpaper'
assert 'self.sheetWallpaperShown=YES;' in h
assert 'if (!self.lease && !self.sheetWallpaperShown) {self.lease=[LMVDesktopContentLease new];' in h, 'the lease must not be re-acquired while the sheet shows the wallpaper'
assert 'if (self.lease && !self.lease.baselineHidden) {if(!content.hidden)content.hidden=YES;self.lease.applied=YES;}' in h, 'nil-guarded apply - the restored wallpaper must not be re-hidden through a nil lease'
assert 'BOOL opaqueCover=covered && self.coveredSince>0 && holdNow-self.coveredSince>=0.3;' in h
# 0.0.134: the Control Center does not freeze the video at fg==1 either - the
# close needs no resume (instant like the user asked); coveredNow keeps the
# audio off under it. Only the notification sheet freezes at fg==1 (its close
# is caught early by the content probe, and the watcher backs it up).
# 0.0.134: the switcher does NOT freeze the video at fg==1 (the app exit path
# runs through it - the 0.0.130 instant feel); it still counts as a cover for
# the audio (coveredNow) and freezes at fg!=1 like anything else.
# 0.0.136: coveredNow means "the video is not audible" - it follows the SAME
# condition as the freeze (not the raw geometry), so audio and video never
# disagree; the flip syncs the Desktop audio directly with no timer beat.
assert '@property(nonatomic) BOOL coveredNow;' in h
assert 'self.coveredNow=audioCovered;' in h
assert 'BOOL audioCovered=appForeground || (visible && (switcherPresented || ccPresented)) ||' in h, 'a notification pull keeps the sound'
assert '(visible && covered && (sheetFullCover || switcherCover || ccCover || foreground!=1));' in h
assert 'if(LMVDesktopAudioPauseHook)LMVDesktopAudioPauseHook();' in h
assert '!LMVDesktopVideo.coveredNow && LMVAudioLayerExposed' in s
# 0.0.132: the app switcher is NOT an app exit - covering the desktop with the
# switcher freezes the video and stops the audio, exactly like an app cover.
assert 'if ([name containsString:@"Switcher"]) *switcherCover=YES;' in h
assert '*ccCover=YES;' in h, 'the CC branch marks its own cover kind'
assert 'else *appWindowCover=YES;' in h
assert 'if (self.host.superview!=nil) [self startCoverWatch];' in h
assert 'opaque=%d sheet=%d sheetFull=%d appc=%d sw=%d cc=%d swEff=%d ccEff=%d geoSeen=%d' in h

# 0.0.128: while the layer is hidden behind an opaque app, a per-frame watcher
# re-checks the cheap cover geometry and hands over to a full update the moment
# the exit cross-fade starts revealing the desktop - the wallpaper content that
# shows through the fading app was visible for up to one ~0.4 s update tick
# (the reported occasional flash); now the unhide lands within ~16 ms.
assert '@property(nonatomic,strong) CADisplayLink *coverWatch;' in h
assert '- (void)startCoverWatch {' in h and '- (void)stopCoverWatch {' in h
assert '- (void)coverWatchTick:(CADisplayLink *)link {' in h
assert '[CADisplayLink displayLinkWithTarget:self selector:@selector(coverWatchTick:)]' in h
# 0.0.137: the watcher runs while the surface exists and watches BOTH
# directions - a cover appearing freezes within ~16 ms, the desktop being
# revealed resumes within ~16 ms.
assert 'if (self.host.superview!=nil) [self startCoverWatch];' in h
assert 'else [self stopCoverWatch];' in h
assert 'if (self.host.hidden || self.playback.frozen) {' in h
# 1.15: one condition, both directions - a geometry cover (switcher/CC/app on
# screen at fg==1) used to match no listed reason, so the tick fired every frame.
assert '(fullyCovered && (fg!=1 || switcherCover || ccCover || appCover));' in h, 'a geometry cover silences the watcher too'
assert 'if (presented) return;' in h or 'if (held) return;' in h
assert 'BOOL presented=self.effectiveSwitcherPresented||self.effectiveControlCenterPresented;' in h, 'the watcher silences on a still-visible presentation only'
assert '[self stopCoverWatch];' in h, 'suspend and the tick both stop the watcher'
assert '[self.coverWatch invalidate];self.coverWatch=nil;' in h
assert '[_coverWatch invalidate];' in h, 'dealloc cleans the watcher up'
assert 'cover-watch-reveal' in h
# 0.0.131: the desktop freeze pauses the Desktop audio channel directly through
# the Tweak.xm-wired hook - the 10 Hz audio timer alone let the desktop sound
# keep playing for up to half a second after an app covered the desktop.
assert 'static void (^LMVDesktopAudioPauseHook)(void);' in h
assert 'if(LMVDesktopAudioPauseHook)LMVDesktopAudioPauseHook();' in h
assert '!LMVDesktopVideo.coveredNow && LMVAudioLayerExposed' in s
# 0.0.135: the coveredNow FLIP syncs the Desktop audio directly in both
# directions - pause the instant anything covers the desktop, resume (seeked to
# the video player's current time) the instant it clears. No timer beat.
assert 'static void (^LMVDesktopAudioCoverHook)(BOOL covered);' in h
assert 'BOOL wasCovered=self.coveredNow;' in h
assert 'if (audioCovered!=wasCovered && LMVDesktopAudioCoverHook) LMVDesktopAudioCoverHook(audioCovered);' in h
assert "LMVDesktopAudioCoverHook=^(BOOL covered){" in s
assert 'else LMVAudioResumeTarget(@"Desktop",LMVDesktopVideo.playback.player?LMVDesktopVideo.playback.player.currentTime:kCMTimeZero);' in s
audio=(r/'LMVMediaAudio.h').read_text()
assert 'static void LMVAudioResumeTarget(NSString *target,CMTime time) {' in audio
assert "[c.player playImmediatelyAtRate:1];c.lastSync=CACurrentMediaTime();" in audio, 'the audio sync gates on the cover, not just the player state'

# 0.0.129: any OTHER visible window whose root view covers ~the whole screen is a
# SHEET cover - the Control Center root slides in and out, and full-screen
# search/overlay presenters freeze the desktop video exactly like the
# notification sheet (fg==1 under them: freeze only, never hide). CoverSheet
# keeps its content probe because its ROOT stays full-screen while the sliding
# content leaves. Guards: root loaded/visible/opaque, animated frame on screen,
# >=90% of the destination; easter/snapshot/status-bar names stay excluded.
assert "if (window==destination || LMVDesktopHomeWindow(window) ||" in h
assert '![name isEqualToString:@"SBWindow"])) continue;' in h, 'the app surface SBWindow is recognised (1.15)'
assert 'BOOL covered=container && LMVDesktopFullyCovered(container,cover) && !appExitRelease;' in h, 'the release window is not a cover either (1.15)'
assert 'Class ccModule=NSClassFromString(@"LMVControlCenterVideoManager");' in h and 'controlCenterWindowIsEmpty' in h, 'the CC module answer is used when it is reachable (1.15)'
assert 'fullyCovered=NO;                                     // 1.15: not a cover at all' in h, 'the watcher is not silenced by a released cover (1.15)'
assert 'if (!appSurfaceWasUp) {self.appAway=NO;self.appLeftAt=0;}' in h, 'the release closes as soon as the app surface is gone (1.15)'
assert 'if (foreground==-1) {self.appAway=YES;self.appLeftAt=0;self.shellAtExit=NO;}' in h, 'the frontmost probe arms the release (1.15)'
assert 'if (self.shellAtExit) {switcherCover=NO;ccCover=NO;}' in h, 'only the shells that were already up at the exit are ignored (1.15)'
assert 'if (appNow-self.appLeftAt<=0.8)' in h, 'the release window is bounded (1.15)'
assert 'if (!LMVLockVideoRectValid(converted)) continue;' in h
# 0.0.129's generalized "any full-screen root is a sheet" probe FROZE the desktop
# for good on device: SpringBoard permanently carries full-screen windows
# (UITextEffectsWindow, the SystemAperture host, Myrtle/Snapper/FloatingView
# panels - named in the desktop-windows diagnostic). 0.0.130 reverts to the
# exact whitelist and probes ONLY the Control Center window by class - its
# window disappears while closed and its root slides while open.
assert 'if (LMVLockVideoClass(window,@\"SBControlCenterWindow\")) {' in h
assert 'the Control Center sheet is probed EXACTLY, by class' in h
assert 'UIView *root=window.rootViewController.viewIfLoaded;' in h
assert 'if (!root || root.hidden || root.alpha<.01) continue;' in h
assert 'if (rootPresentation && rootPresentation.opacity<0.99) continue;' in h
assert 'if (window.alpha<0.99) continue;' in h, 'a fading Control Center is closing - not a cover'
assert 'CGRect converted=CGRectIntersection([window convertRect:rect toWindow:destination],destination.bounds);' in h
assert 'if (full<=0 || area/full<0.9) continue;' in h
assert 'sheetName' not in h, 'the generalized sheet probe is really gone'
# 0.0.129 diagnostics: the on-screen window class list (changes-only) identifies
# sheet presenters (e.g. the search pull-down) the probe does not know yet.
assert 'desktop-windows %@' in h
assert 'windowListStatus' in h
# Stub only the production diagnostic switch; execute all actual geometry,
# ownership and presentation logic with diagnostics off, as in normal use.
h=h.replace('LMVDiagnosticsEnabled.load()', 'NO')
if platform.system()!='Darwin':
 print('PASS: independent Desktop integration contracts; real manager/QuartzCore/typed IMP execution runs on macOS CI')
 raise SystemExit(0)
# Reuse only the UIKit/Foundation doubles from the existing native lock test;
# never execute that test's logic or copy/reimplement production desktop logic.
tree=ast.parse((r/'tests/lock-video-host.py').read_text());pre=''
for node in tree.body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
 elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
assert pre
if 'NSArray *gestureRecognizers;' not in pre:
 pre=pre.replace('@property(nonatomic) NSUInteger autoresizingMask;', '@property(nonatomic) NSUInteger autoresizingMask;\n@property(nonatomic,strong) NSArray *gestureRecognizers;')
if '- (void)insertSubview:(UIView *)view atIndex:' not in pre:
 pre=pre.replace('- (void)addSubview:(UIView *)view;', '- (void)addSubview:(UIView *)view;\n- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;')
 pre=pre.replace('- (void)layoutSubviews {}', '- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index {[view removeFromSuperview];[self.subviews insertObject:view atIndex:(NSUInteger)index];view.superview=self;[self.layer insertSublayer:view.layer atIndex:(unsigned)index];}\n- (void)layoutSubviews {}')
pre=pre.replace('- (void)viewDidDisappear:(BOOL)animated;', '- (void)viewWillDisappear:(BOOL)animated;\n- (void)viewDidDisappear:(BOOL)animated;')
pre=pre.replace('- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}', '- (void)viewWillDisappear:(BOOL)animated {self.disappearances++;}\n- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}')
pre=pre.replace('@interface UIWindow:UIView\n', '@interface UIWindow:UIView\n- (CGRect)convertRect:(CGRect)rect toWindow:(UIWindow *)window;\n')
pre=pre.replace('- (UIWindow *)window {return self;}','- (UIWindow *)window {return self;}\n- (CGRect)convertRect:(CGRect)rect toWindow:(UIWindow *)window {return [self.layer convertRect:rect toLayer:window.layer];}')
pre=pre.replace('@interface UIApplication:NSObject\n','@interface UIApplication:NSObject\n@property(nonatomic,strong) id frontmost;\n- (id)_frontmostApplication;\n')
pre=pre.replace('@implementation UIApplication\n','@implementation UIApplication\n- (id)_frontmostApplication {return self.frontmost;}\n')
pre=pre.replace('static int LMVBlankToken=1;', 'static int LMVBlankToken=1,LMVLockToken=2;')
pre=pre.replace('static uint64_t screenBlank=0;', 'static uint64_t screenBlank=0,screenLocked=0;')
pre=pre.replace('*state=screenBlank;return 0;', '*state=token==LMVLockToken?screenLocked:screenBlank;return 0;')
pre=pre.replace('self.wantsPlayback=visible;', 'self.wantsPlayback=visible;_frozen=NO;self.renderLayer.hidden=!visible || self.error!=nil || !self.posterLayer.contents;')
# 0.0.91: the double mirrors the production rule, where a frozen (paused)
# surface keeps renderLayer on screen while wantsPlayback is NO.
pre=pre.replace('- (void)setFrozen:(BOOL)frozen {_frozen=frozen;}',
                '- (void)setFrozen:(BOOL)frozen {_frozen=frozen;self.renderLayer.hidden=(!self.wantsPlayback && !self.frozen && !self.posterOnlyVisible) || self.error!=nil || !self.posterLayer.contents;}')
pre=pre.replace('@property NSUInteger builds,clears;', '@property NSUInteger builds,clears,earlyReads;\n@property BOOL persistentPosterEnabled,posterOnlyVisible;\n- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision;\n- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision;\n- (void)showPreparedPoster:(BOOL)visible;\n- (void)applyPreparedPoster:(CGImageRef)image path:(NSString *)path revision:(NSString *)revision;')
pre=pre.replace('@implementation LMVLockVideoPlayback\n', '@implementation LMVLockVideoPlayback\n- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision {}\n- (void)applyPreparedPoster:(CGImageRef)image path:(NSString *)path revision:(NSString *)revision {self.posterLayer.contents=(__bridge id)image;}\n- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision {self.earlyReads++;}\n- (void)showPreparedPoster:(BOOL)visible {self.posterOnlyVisible=visible;self.wantsPlayback=NO;self.renderLayer.hidden=!visible || !self.posterLayer.contents;}\n')
# Reproduce the .077 failure boundary: dyld initializer executes before UIKit.
# Any view/player construction or screen/application query then throws.
pre=pre.replace('#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\nstatic BOOL forbidUIKit;\nstatic NSUInteger viewConstructions,playbackConstructions,screenQueries,appQueries;')
pre=pre.replace('+ (instancetype)mainScreen {static UIScreen *s;', '+ (instancetype)mainScreen {screenQueries++;NSCAssert(!forbidUIKit,@"UIScreen used during loader initialization");static UIScreen *s;')
pre=pre.replace('+ (instancetype)sharedApplication {static UIApplication *app;', '+ (instancetype)sharedApplication {appQueries++;NSCAssert(!forbidUIKit,@"UIApplication used during loader initialization");static UIApplication *app;')
pre=pre.replace('- (instancetype)initWithFrame:(CGRect)rect {if((self=[super init]))', '- (instancetype)initWithFrame:(CGRect)rect {viewConstructions++;NSCAssert(!forbidUIKit,@"UIView created during loader initialization");if((self=[super init]))')
pre=pre.replace('- (instancetype)init {if((self=[super init])){_renderLayer=', '- (instancetype)init {playbackConstructions++;NSCAssert(!forbidUIKit,@"Playback created during loader initialization");if((self=[super init])){_renderLayer=')
pre=pre.replace('@property NSUInteger builds,clears,earlyReads;', '@property NSUInteger builds,clears,earlyReads,layoutCalls,visibleCalls,frozenCalls,resumeCalls;\n- (void)resumeIfNeeded;')
pre=pre.replace('- (void)layoutInBounds:(CGRect)bounds {self.renderLayer.frame=bounds;}', '- (void)layoutInBounds:(CGRect)bounds {self.layoutCalls++;self.renderLayer.frame=bounds;}')
pre=pre.replace('- (void)setVisible:(BOOL)visible {self.wantsPlayback=visible;', '- (void)setVisible:(BOOL)visible {self.visibleCalls++;self.wantsPlayback=visible;')
pre=pre.replace('- (void)setFrozen:(BOOL)frozen {_frozen=frozen;', '- (void)setFrozen:(BOOL)frozen {self.frozenCalls++;_frozen=frozen;')
pre=pre.replace('@implementation LMVLockVideoPlayback\n', '@implementation LMVLockVideoPlayback\n- (void)resumeIfNeeded {self.resumeCalls++;}\n')
# Typed public atomic hold API supplied by shared Playback; do not simulate it
# through setVisible:NO + setFrozen:YES (that intermediate hidden write is tested).
pre=pre.replace('- (void)resumeIfNeeded;', '- (void)resumeIfNeeded;\n- (void)holdCurrentFrame:(BOOL)hold;')
pre=pre.replace('@implementation LMVLockVideoPlayback\n', '@implementation LMVLockVideoPlayback\n- (void)holdCurrentFrame:(BOOL)hold {self.holdCalls++;_frozen=hold;self.wantsPlayback=!hold;self.posterOnlyVisible=NO;self.renderLayer.hidden=self.error!=nil || !self.posterLayer.contents;if(!hold)[self resumeIfNeeded];}\n')
pre=pre.replace('visibleCalls,frozenCalls,resumeCalls;', 'visibleCalls,frozenCalls,resumeCalls,holdCalls;')
pre=pre.replace('@implementation UIView\n', r'''
static BOOL watchFastTransitions;
static __weak UIView *watchedHost,*watchedContent;
static NSUInteger fastHostHiddenWrites,fastRenderHiddenWrites,fastLeaseRestores;
@implementation UIView
- (void)setHidden:(BOOL)hidden {
    if(watchFastTransitions && self==watchedHost && hidden)fastHostHiddenWrites++;
    if(watchFastTransitions && self==watchedContent && !hidden)fastLeaseRestores++;
    _hidden=hidden;self.layer.hidden=hidden;
}
''')
pre=pre.replace('@implementation LMVLockVideoPlayback\n', r'''
@interface MeasuredDesktopLayer:CALayer @end
@implementation MeasuredDesktopLayer
- (void)setHidden:(BOOL)hidden {
    if(watchFastTransitions && hidden)fastRenderHiddenWrites++;
    [super setHidden:hidden];
}
@end
@implementation LMVLockVideoPlayback
''')
pre=pre.replace('_renderLayer=[CALayer layer];', '_renderLayer=[MeasuredDesktopLayer layer];')
pre+=r'''
static NSUInteger fullDesktopPolicies;
static NSDictionary *testPrefs;
static CFPropertyListRef testPreference(CFStringRef key,CFStringRef domain) {return CFBridgingRetain(testPrefs[(__bridge NSString *)key]);}
#define CFPreferencesCopyAppValue testPreference
static NSUInteger posterReads;
static dispatch_queue_t LMVVideoPosterQueue(void) {static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("test.desktop-poster",DISPATCH_QUEUE_SERIAL);});return queue;}
static CGImageRef LMVVideoPosterRead(NSString *path,NSString *revision) {
    posterReads++;CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(NULL,2,2,8,8,color,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(color);
    assert(context);CGContextSetRGBFillColor(context,1,0,0,1);CGContextFillRect(context,CGRectMake(0,0,2,2));CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);return image;
}
static void posterTurn(void) {dispatch_sync(LMVVideoPosterQueue(),^{});[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
@interface SBHomeScreenWindow:UIWindow @end
@implementation SBHomeScreenWindow @end
@interface SBHomeScreenViewController:UIViewController @end
@implementation SBHomeScreenViewController @end
@interface SBIconController:UIViewController @end
@implementation SBIconController @end
@interface PBUIPosterHomeViewController:UIViewController @end
@implementation PBUIPosterHomeViewController @end
@interface PBUIPosterLockViewController:UIViewController @end
@implementation PBUIPosterLockViewController @end
@interface SBFWallpaperView:UIView
@property(nonatomic,strong) UIView *contentView;
@end
@implementation SBFWallpaperView @end
static NSUInteger sharedCalls;
@interface SBWallpaperController:NSObject
@property(nonatomic,strong) UIView *homescreenWallpaperView,*lockscreenWallpaperView;
+ (instancetype)sharedInstance;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {sharedCalls++;static SBWallpaperController *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
@end
@interface TestApplication:NSObject
@property(nonatomic,copy) NSString *bundleIdentifier;
@end
@implementation TestApplication @end
@interface SBAppWindow:UIWindow @end
@implementation SBAppWindow @end
@interface SBControlCenterWindow:UIWindow @end
@implementation SBControlCenterWindow @end
@interface SBMainSwitcherWindow:UIWindow @end
// 1.13/1.15: SBWindow is the surface carrying the application on this device.
@interface SBWindow:UIWindow @end
// 0.0.138: the SpringBoard presentation state is the authority for the switcher
// and the Control Center - these fakes let the calls resolve in the fixture.
@interface SBMainSwitcherControllerCoordinator:NSObject
@property(nonatomic) BOOL isAnySwitcherVisible;
+ (instancetype)sharedInstance;
@end
@implementation SBMainSwitcherControllerCoordinator
static SBMainSwitcherControllerCoordinator *gSwitcher;
+ (instancetype)sharedInstance { if (!gSwitcher) gSwitcher=[self new]; return gSwitcher; }
@end
@interface SBControlCenterController:NSObject
@property(nonatomic) BOOL isVisible;
+ (instancetype)sharedInstance;
@end
@implementation SBControlCenterController
static SBControlCenterController *gControlCenter;
+ (instancetype)sharedInstance { if (!gControlCenter) gControlCenter=[self new]; return gControlCenter; }
@end
@implementation SBMainSwitcherWindow @end
@implementation SBWindow @end
'''
lock=(r/'LMVLockVideo.h').read_text()
# Execute real discovery, geometry and ABI validators needed by Desktop.
helpers=lock[lock.index('static BOOL LMVLockVideoRectValid'):lock.index('@interface LMVLockVideoHost')]
abi=lock[lock.index('static BOOL LMVLockVideoHookMatches'):lock.index('static void LMVLockVideoInstallHooks')]
h=h.replace('- (void)update {', '- (void)update {fullDesktopPolicies++;')
main=r'''
static void originalTree(UIView *parent,NSArray *expected) {
 NSMutableArray *actual=[NSMutableArray new];for(UIView *v in parent.subviews)if(![v isKindOfClass:LMVDesktopVideoHost.class])[actual addObject:v];
 assert([actual isEqual:expected]);for(UIView *v in expected)assert(v.superview==parent && v.layer.superlayer==parent.layer && v.layer.delegate==v);
}
int main(void){@autoreleasepool {
 // Execute the same entry called from the real dylib ctor while all UIKit
 // constructors, screen queries and application queries are forbidden.
 LMVInitialized=YES;LMVLaunchReady=NO;forbidUIKit=YES;
 testPrefs=@{@"DesktopBackgroundEnabled":@YES,@"DesktopVideo":@"library/warm.mov"};
 for(int n=0;n<50;n++)LMVDesktopPrimeEarly();
 assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 assert(![LMVDesktopVideoManager new] && !LMVDesktopEnsureManager());
 LMVDesktopEarlyLayout();posterTurn();
 assert(LMVDesktopSeed.image && posterReads==1 && !viewConstructions && !playbackConstructions && !screenQueries && !appQueries);
 // Disabled early priming also stays data-only and drops the prior seed.
 testPrefs=@{@"DesktopBackgroundEnabled":@NO};LMVDesktopPrimeEarly();posterTurn();assert(!LMVDesktopSeed.image && !LMVDesktopVideo && !viewConstructions && !playbackConstructions && !screenQueries && !appQueries);
 testPrefs=@{@"DesktopBackgroundEnabled":@YES,@"DesktopVideo":@"library/warm.mov"};LMVDesktopPrimeEarly();posterTurn();assert(LMVDesktopSeed.image && posterReads==2);
 forbidUIKit=NO;
 LMVLaunchReady=YES;
 SBHomeScreenWindow *homeWindow=[SBHomeScreenWindow new];UIView *home=[UIView new];[homeWindow addSubview:home];
 SBHomeScreenViewController *controller=[SBHomeScreenViewController new];controller.viewIfLoaded=home;homeWindow.rootViewController=controller;
 SBUIBackgroundView *back=[SBUIBackgroundView new];UIView *icons=[UIView new];UIControl *dock=[UIControl new];[home addSubview:back];[home addSubview:icons];[home addSubview:dock];NSArray *homeOriginal=home.subviews.copy;
 UIWindow *wallWindow=[UIWindow new];SBFWallpaperView *wall=[SBFWallpaperView new];UIView *wallPixels=[UIView new];[wallWindow addSubview:wall];[wall addSubview:wallPixels];wall.contentView=wallPixels;
 NSArray *wallOriginal=wall.subviews.copy;
 SBCoverSheetWindow *nc=[SBCoverSheetWindow new];CSCoverSheetView *cover=[CSCoverSheetView new];UIView *sliding=[UIView new];[nc addSubview:cover];[cover addSubview:sliding];cover.slideableContentView=sliding;sliding.frame=CGRectMake(0,-844,390,844);
 UIWindowScene *scene=[UIWindowScene new];scene.windows=@[homeWindow,wallWindow,nc];UIApplication.sharedApplication.connectedScenes=@[scene];
 LMVDesktopControllers=[NSHashTable weakObjectsHashTable];[LMVDesktopControllers addObject:controller];
 LMVDesktopControllerRecord *record=[LMVDesktopControllerRecord new];record.known=YES;record.visible=YES;objc_setAssociatedObject(controller,&LMVDesktopControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 LMVDesktopExplicitWallpaper=wall;
 LMVDesktopVideoManager *m=[LMVDesktopVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev1";
 m.playback.path=@"movie";m.playback.posterLayer.contents=(id)@"pixel";
 [m update];assert(m.host.superview==wall && [wall.subviews indexOfObject:m.host]==1 && wallPixels.hidden && m.playback.wantsPlayback);
 NSUInteger stableLayouts=m.playback.layoutCalls,stableVisible=m.playback.visibleCalls,stableFrozen=m.playback.frozenCalls;
 for(int n=0;n<500;n++){[m update];assert(m.host.superview==wall && wallPixels.hidden);}
 assert(m.playback.layoutCalls==stableLayouts && m.playback.visibleCalls==stableVisible && m.playback.frozenCalls==stableFrozen);
 assert(m.host.alpha==1 && !m.host.userInteractionEnabled && m.host.accessibilityElementsHidden);originalTree(wall,wallOriginal);originalTree(home,homeOriginal);
 for(int n=0;n<100;n++){[m update];assert(m.host.superview==wall && wallPixels.hidden);originalTree(wall,wallOriginal);}
 // 0.0.91: the app transition freezes the Desktop surface in place instead of
 // tearing it down, so the launch animation never flashes the system wallpaper.
 // 0.0.123: a real app reaching the foreground takes the Home view OUT of the
 // hierarchy (viewDidDisappear -> record.visible=NO), and THAT is the state the
 // launch transition freezes in - no wallpaper, last frame kept. Merely flipping
 // the frontmost probe while the Home view is still on screen is not a launch.
 TestApplication *app=[TestApplication new];app.bundleIdentifier=@"com.apple.mobilesafari";
 UIApplication.sharedApplication.frontmost=app;record.visible=NO;[m update];
 assert(m.host.superview==wall && !m.playback.wantsPlayback && m.playback.frozen && !m.playback.renderLayer.hidden && wallPixels.hidden);
 // The probe flips while the desktop is plainly on screen: the surface must keep
 // playing (this is what used to show the original wallpaper on every app launch).
 record.visible=YES;[m update];
 assert(m.host.superview==wall && m.playback.wantsPlayback && !m.playback.frozen && !m.playback.renderLayer.hidden && wallPixels.hidden);
 // 0.0.124: the desktop is exposed, so the layer MUST be composited - the
 // compositing saving may never take the desktop away while it is on screen.
 assert(!m.host.hidden);
 // 0.0.125: a foreground application IS full cover. While the app window is up
 // the layer must stop being composited and the player must freeze; the instant
 // the window leaves, the desktop is back with the surface still attached (no
 // wallpaper flash, no reattach).
 SBAppWindow *appWindow=[SBAppWindow new];
 scene.windows=@[homeWindow,wallWindow,nc,appWindow];
 record.visible=YES;
 for(CFTimeInterval t=CACurrentMediaTime();CACurrentMediaTime()-t<0.45;)[m update];
 assert(m.host.superview==wall && m.host.hidden && m.playback.frozen);
 // 0.0.126: mid-transition the app no longer covers the desktop (the zoomed
 // presentation frame, here the shrunk model frame). The cover must drop
 // IMMEDIATELY - unhide and resume in the same update, before the app window
 // actually leaves - so the revealed area shows the video, never the wallpaper.
 appWindow.frame=CGRectMake(0,0,390,400);
 [m update];
 assert(m.host.superview==wall && !m.host.hidden && !m.playback.frozen && wallPixels.hidden);
 // 0.0.127: a FADING window (the exit cross-fade keeps the model frame
 // full-screen but drops opacity) is NOT a cover either - same instant unhide
 // and resume while the window is still in the scene.
 appWindow.frame=CGRectMake(0,0,390,844);appWindow.alpha=0.5;
 [m update];
 assert(m.host.superview==wall && !m.host.hidden && !m.playback.frozen && wallPixels.hidden);
 appWindow.alpha=1;
 // 0.0.127: with the window full and opaque again, the freeze follows the
 // frontmost probe: fg==-1 -> pause; fg==1 (desktop evidence, stale window
 // still up) -> RESUME in the same update instead of waiting for removal.
 for(CFTimeInterval t=CACurrentMediaTime();CACurrentMediaTime()-t<0.45;)[m update];
 assert(m.host.hidden && m.playback.frozen);
 // 0.0.128: while hidden the cover watcher is active but silent (still fully
 // covered, app frontmost); the moment the reveal starts it requests one full
 // update and the layer is back WITHOUT waiting for the ~0.4 s cadence.
 assert(m.coverWatch!=nil);
 [m coverWatchTick:nil];
 // still provably covered (fg==-1, full cover): the watcher must NOT fire yet
 assert(m.host.hidden);
 scene.windows=@[homeWindow,wallWindow,nc];
 // The watcher hands over through LMVDesktopRequestUpdate, which drives the
 // GLOBAL manager - point it at this instance so the async update lands here.
 LMVDesktopVideo=m;
 [m coverWatchTick:nil];
 [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(m.host.superview==wall && !m.host.hidden && !m.playback.frozen && m.playback.wantsPlayback);
 // 0.0.137: the watcher is BIDIRECTIONAL and stays running while the surface
 // exists - after firing it restarts and keeps watching for the next cover.
 assert(m.coverWatch!=nil);
 [m update];
 assert(m.host.superview==wall && !m.host.hidden && !m.playback.frozen && wallPixels.hidden);
 // 1.15: the app exit resumes on the PIXELS. The Home controller is still
 // reported away (record.visible=NO) and the frontmost probe still points at the
 // app, but the app window no longer covers anything - the desktop is on screen,
 // so the video AND the sound come back in this very update. Waiting for the
 // Home lifecycle record / frontmost probe was the reported slow resume.
 SBAppWindow *exitWindow=[SBAppWindow new];UIView *exitView=[UIView new];UIViewController *exitC=[UIViewController new];
 [exitWindow addSubview:exitView];exitWindow.rootViewController=exitC;exitC.viewIfLoaded=exitView;
 scene.windows=@[homeWindow,wallWindow,nc,exitWindow];
 record.visible=NO;UIApplication.sharedApplication.frontmost=app;
 for(CFTimeInterval t=CACurrentMediaTime();CACurrentMediaTime()-t<0.45;)[m update];
 assert(m.host.hidden && m.playback.frozen && m.coveredNow);
 assert(m.geometryCoverSeen);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 assert(!m.host.hidden && m.playback.wantsPlayback && !m.playback.frozen && !m.coveredNow && wallPixels.hidden);
 record.visible=YES;UIApplication.sharedApplication.frontmost=nil;[m update];
 // 1.15/1.15: ZERO-delay app exit. The frontmost probe is the signal, so the
 // desktop comes back on the frame the app stops being frontmost - and the video
 // LAYER must be up for the whole release: hiding it while the cover flags were
 // cleared is exactly the wallpaper showing through that the user reported.
 TestApplication *exitApp=[TestApplication new];exitApp.bundleIdentifier=@"com.apple.mobilesafari";
 SBWindow *exitSurface=[SBWindow new];UIView *exitRoot=[UIView new];UIViewController *exitController=[UIViewController new];
 [exitSurface addSubview:exitRoot];exitSurface.rootViewController=exitController;exitController.viewIfLoaded=exitRoot;
 record.visible=YES;UIApplication.sharedApplication.frontmost=exitApp;
 scene.windows=@[homeWindow,wallWindow,nc,exitSurface];
 [m update];
 assert(m.playback.frozen && m.appAway);
 UIApplication.sharedApplication.frontmost=nil;
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 assert(!m.playback.renderLayer.hidden && !m.host.hidden);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.playback.renderLayer.hidden);
 UIApplication.sharedApplication.frontmost=nil;
 [m update];
 // 0.0.129: the Control Center sheet counts as a sheet cover through the
 // generalized root probe. fg==-1 first (freeze, grace not elapsed -> no hide),
 // then fg==1 - the real CC case: still frozen, NEVER hidden, surface attached;
 // closing the sheet resumes playing in the same update.
 // 0.0.130: the CC probe is now EXACT (by class) after the generalized probe
 // froze the desktop behind permanent full-screen tweak/system windows, and a
 // plain full-screen UIWindow with a loaded root must NOT count as a cover.
 SBControlCenterWindow *ccWindow=[SBControlCenterWindow new];
 UIViewController *ccController=[UIViewController new];
 UIView *ccView=[UIView new];
 [ccWindow addSubview:ccView];ccWindow.rootViewController=ccController;ccController.viewIfLoaded=ccView;
 scene.windows=@[homeWindow,wallWindow,nc,ccWindow];
 [m update];
 // 0.0.136: fg!=1 (app probe) with the CC sheet up - the grace has not elapsed
 // and the CC is translucent, so the layer stays visible; the video may be
 // frozen only until the probe evidence resolves.
 assert(m.host.superview==wall && !m.host.hidden);
 // 0.0.137: at fg==1 the Control Center FREEZES the video and the audio
 // (coveredNow) immediately; the layer hides after the grace with the lease
 // kept. Closing the sheet: the watcher fires the moment the cover drops and
 // the resume lands within ~16 ms.
 UIApplication.sharedApplication.frontmost=nil;record.visible=YES;[m update];
 assert(m.host.superview==wall && !m.host.hidden && m.playback.frozen && m.coveredNow);
 assert(m.coverWatch!=nil);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m coverWatchTick:nil];
 [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(m.host.superview==wall && !m.host.hidden && !m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 // 1.15: the watcher fires ONLY when the frozen state actually ends. With a
 // switcher surface on screen at fg==1 it used to match no listed reason and
 // fired EVERY frame, each fire running a full update (device log: 89 updates in
 // 2 s, up to 4.24 ms each, cover-watch-reveal every 8-17 ms).
 SBMainSwitcherWindow *watchSwitcher=[SBMainSwitcherWindow new];
 UIViewController *watchSwitcherController=[UIViewController new];UIView *watchSwitcherView=[UIView new];
 [watchSwitcher addSubview:watchSwitcherView];watchSwitcher.rootViewController=watchSwitcherController;
 watchSwitcherController.viewIfLoaded=watchSwitcherView;
 UIApplication.sharedApplication.frontmost=nil;record.visible=YES;
 scene.windows=@[homeWindow,wallWindow,nc,watchSwitcher];
 [m update];
 assert(m.playback.frozen && m.coveredNow);
 LMVDesktopUpdatePending=NO;
 [m coverWatchTick:nil];
 assert(LMVDesktopUpdatePending==NO);
 [m coverWatchTick:nil];
 assert(LMVDesktopUpdatePending==NO);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m coverWatchTick:nil];
 assert(LMVDesktopUpdatePending==YES);
 LMVDesktopUpdatePending=NO;
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback);
 // 1.15: the Control Center resume follows the PIXELS too. SpringBoard's own flag
 // is still YES while its surface has already left the screen (the flag flips
 // only after the dismiss animation) - the desktop must come back in THIS update.
 [SBControlCenterController sharedInstance].isVisible=YES;
 scene.windows=@[homeWindow,wallWindow,nc,ccWindow];
 [m update];
 assert(m.playback.frozen && m.coveredNow && m.ccSawCover && m.effectiveControlCenterPresented);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 assert(m.effectiveControlCenterPresented==NO);
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow && !m.host.hidden);
 [SBControlCenterController sharedInstance].isVisible=NO;
 [m update];
 // 1.15: the same rule for the app/switcher surface. Its frame stays full-screen
 // while the content shrinks away - the device log showed the cover held for
 // 1.15 s after the app had gone, because only the frame was measured.
 SBMainSwitcherWindow *contentSwitcher=[SBMainSwitcherWindow new];
 UIViewController *contentSwitcherController=[UIViewController new];UIView *contentSwitcherRoot=[UIView new];
 UIView *contentSwitcherBody=[UIView new];contentSwitcherBody.frame=CGRectMake(0,0,390,844);
 [contentSwitcherRoot addSubview:contentSwitcherBody];
 [contentSwitcher addSubview:contentSwitcherRoot];contentSwitcher.rootViewController=contentSwitcherController;
 contentSwitcherController.viewIfLoaded=contentSwitcherRoot;
 UIApplication.sharedApplication.frontmost=nil;record.visible=YES;
 scene.windows=@[homeWindow,wallWindow,nc,contentSwitcher];
 [m update];
 assert(m.playback.frozen && m.coveredNow);
 contentSwitcherBody.frame=CGRectMake(0,-844,390,844);   // content gone, frame kept
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 contentSwitcherBody.frame=CGRectMake(0,0,390,844);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 // 1.15: the Control Center ROOT stays full-screen on dismiss while the content
 // slides away inside it, so the frame must not act as a cover. The SpringBoard
 // flag is left YES on purpose: the pixels decide.
 UIView *ccContent=[UIView new];ccContent.frame=CGRectMake(0,0,390,844);[ccView addSubview:ccContent];
 [SBControlCenterController sharedInstance].isVisible=YES;
 scene.windows=@[homeWindow,wallWindow,nc,ccWindow];
 [m update];
 assert(m.playback.frozen && m.coveredNow);
 ccContent.frame=CGRectMake(0,-844,390,844);   // the modules slide out, the window stays
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 ccContent.frame=CGRectMake(0,0,390,844);
 [SBControlCenterController sharedInstance].isVisible=NO;
 [m update];
 // 0.0.132: the app switcher is NOT an app exit. Covering the desktop with the
 // switcher at fg==1 must FREEZE (and, on device, stop the audio through the
 // wired hook) - the 0.0.127 exit-transition play rule belongs to real app
 // windows only. Removing the switcher resumes.
 SBMainSwitcherWindow *switcherWindow=[SBMainSwitcherWindow new];
 UIViewController *switcherController=[UIViewController new];
 UIView *switcherView=[UIView new];
 [switcherWindow addSubview:switcherView];switcherWindow.rootViewController=switcherController;switcherController.viewIfLoaded=switcherView;
 scene.windows=@[homeWindow,wallWindow,nc,switcherWindow];
 [m update];
 // 0.0.137: fg==1 under the switcher -> the video AND the audio freeze
 // immediately (coveredNow); the layer hides after the grace with the lease
 // kept - no wallpaper through the blur. Removing the switcher: the watcher
 // resumes within ~16 ms.
 assert(m.host.superview==wall && !m.host.hidden && m.playback.frozen && m.coveredNow);
 // 0.0.139: past the hide grace the frozen frame is STILL visible behind the
 // translucent switcher (only an opaque app cover may hide the layer), and the
 // suppress-lease keeps the wallpaper hidden - no original background leaks.
 for(CFTimeInterval t=CACurrentMediaTime();CACurrentMediaTime()-t<0.45;)[m update];
 assert(m.host.superview==wall && !m.host.hidden && m.playback.frozen && wallPixels.hidden);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m coverWatchTick:nil];
 [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(m.host.superview==wall && !m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 // 0.0.138: SpringBoard says the switcher/CC is presented with NO covering
 // window at all - the video freezes and the audio stops anyway (coveredNow).
 scene.windows=@[homeWindow,wallWindow,nc];
 UIApplication.sharedApplication.frontmost=nil;record.visible=YES;[m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 [SBMainSwitcherControllerCoordinator sharedInstance].isAnySwitcherVisible=YES;
 [m update];
 assert(m.host.superview==wall && m.playback.frozen && m.coveredNow && !m.host.hidden);
 [SBMainSwitcherControllerCoordinator sharedInstance].isAnySwitcherVisible=NO;
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 [SBControlCenterController sharedInstance].isVisible=YES;
 [m update];
 assert(m.host.superview==wall && m.playback.frozen && m.coveredNow && !m.host.hidden);
 [SBControlCenterController sharedInstance].isVisible=NO;
 [m update];
 assert(!m.playback.frozen && m.playback.wantsPlayback && !m.coveredNow);
 // 0.0.132: a FADING Control Center window is closing - not a cover. The video
 // keeps playing while the sheet fades out instead of freezing until removal.
 ccWindow.alpha=0.5;
 scene.windows=@[homeWindow,wallWindow,nc,ccWindow];
 [m update];
 assert(m.host.superview==wall && !m.playback.frozen && m.playback.wantsPlayback);
 ccWindow.alpha=1;
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 assert(m.host.superview==wall && m.playback.wantsPlayback);
 // 0.0.130: the 0.0.129 regression guard - a plain UIWindow with a full-screen
 // root (like UITextEffectsWindow / the aperture host / tweak panels) must
 // never become a cover: the desktop keeps PLAYING with it present.
 UIWindow *plainWindow=[UIWindow new];
 UIViewController *plainController=[UIViewController new];
 UIView *plainView=[UIView new];
 [plainWindow addSubview:plainView];plainWindow.rootViewController=plainController;plainController.viewIfLoaded=plainView;
 scene.windows=@[homeWindow,wallWindow,nc,plainWindow];
 [m update];
 assert(m.host.superview==wall && !m.playback.frozen && m.playback.wantsPlayback && wallPixels.hidden);
 scene.windows=@[homeWindow,wallWindow,nc];
 [m update];
 assert(m.host.superview==wall && m.playback.wantsPlayback);
 for(int flip=0;flip<200;flip++) {
  UIApplication.sharedApplication.frontmost=flip%2 ? app : nil;[m update];
  assert(m.host.superview==wall && m.playback.wantsPlayback && !m.playback.frozen && wallPixels.hidden);
 }
 record.visible=YES;UIApplication.sharedApplication.frontmost=nil;[m update];
 assert(m.host.superview==wall && !m.playback.frozen && m.playback.wantsPlayback);
 // Measured fast enter/exit: no intermediate setHidden:YES on render/host,
 // no background lease release, and one retained player through transient zero bounds.
 watchFastTransitions=YES;watchedHost=m.host;watchedContent=wallPixels;
 CALayer *retainedRender=m.playback.renderLayer;id retainedPlayer=m.playback.player;
 CGRect fullBounds=wall.bounds;
 for(int cycle=0;cycle<250;cycle++) {
  UIApplication.sharedApplication.frontmost=app;record.visible=NO;[m update];
  wall.bounds=CGRectZero;[m syncGeometry];[m update];
  assert(m.host.superview==wall && m.playback.frozen && !m.playback.renderLayer.hidden && wallPixels.hidden);
  wall.bounds=fullBounds;record.visible=YES;UIApplication.sharedApplication.frontmost=nil;[m update];
  assert(m.host.superview==wall && m.playback.wantsPlayback && !m.playback.frozen && wallPixels.hidden);
  assert(m.playback.renderLayer==retainedRender && m.playback.player==retainedPlayer);
 }
 watchFastTransitions=NO;
 assert(fastHostHiddenWrites==0 && fastRenderHiddenWrites==0 && fastLeaseRestores==0);
 // App-to-Home lifecycle/geometry can temporarily make every newly discovered
 // container unavailable while the old Home-only surface is still attached.
 // Keep its original content lease even beyond the removed 0.6 s deadline.
 record.visible=NO;wall.hidden=YES;UIApplication.sharedApplication.frontmost=nil;
 m.holdSince=CACurrentMediaTime()-2.0;
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==wall && m.lease && m.lease.content==wallPixels && wallPixels.hidden && m.playback.frozen && !m.playback.renderLayer.hidden);}
 record.visible=YES;wall.hidden=NO;[m update];assert(m.host.superview==wall && m.playback.wantsPlayback);
 // Reachability changes the physical viewport, not the ownership of Home's
 // original content: app-return then a half-height Home still keeps the video.
 CGRect oldHomeBounds=homeWindow.bounds,oldWallBounds=wallWindow.bounds;
 homeWindow.bounds=CGRectMake(0,0,390,422);wallWindow.bounds=CGRectMake(0,0,390,422);
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==wall && m.lease && wallPixels.hidden && !m.playback.renderLayer.hidden);}
 homeWindow.bounds=oldHomeBounds;wallWindow.bounds=oldWallBounds;[m update];
 // Content-only NC pulls do not retarget Home, do not mutate Home frame/alpha,
 // and fully covered NC pauses decoding while retaining the last Desktop frame.
 for(int n=0;n<=100;n++) {
  CGFloat height=844*n/100.0;sliding.frame=CGRectMake(0,-844+height,390,844);screenLocked=n?1:0;[m update];
  // 0.0.137: a partial pull keeps the video playing through the blur (the
  // lease stays); the FULL pull freezes and restores the wallpaper on purpose
  // ("下滑到底才出现原壁纸").
  assert(m.host.superview==wall);originalTree(wall,wallOriginal);originalTree(home,homeOriginal);
  if(n==0){
    // closed sheet: the desktop plays and the lease stays
    assert(m.playback.wantsPlayback && wallPixels.hidden && !m.sheetWallpaperShown && !m.coveredNow);
  } else if(n<100){
    // 1.15: a HALF-pulled sheet is not a cover - the desktop underneath is
    // still on display, so the video stays VISIBLE and keeps PLAYING. Hiding the
    // layer and releasing the lease here is what showed the original wallpaper
    // where the video was supposed to be playing. The SOUND is off from the
    // first pull tick (that part is unchanged).
    assert(m.playback.wantsPlayback && !m.playback.frozen);
    assert(!m.host.hidden && !m.playback.renderLayer.hidden);
    assert(wallPixels.hidden && !m.sheetWallpaperShown && m.lease);
    assert(!m.coveredNow);
  } else {
    // pulled to the bottom: the video AND the sound freeze.
    assert(!m.playback.wantsPlayback);
    assert(!m.playback.renderLayer.hidden);
    assert(m.host.hidden && !wallPixels.hidden && m.sheetWallpaperShown);
    assert(m.coveredNow);
  }
 }
 // Released halfway back: the video is visible and playing again on the spot.
 sliding.frame=CGRectMake(0,-844+422,390,844);[m update];
 assert(!m.host.hidden && m.playback.wantsPlayback && !m.playback.frozen && wallPixels.hidden && !m.sheetWallpaperShown);
 sliding.frame=CGRectMake(0,-844,390,844);screenLocked=0;[m update];assert(m.playback.wantsPlayback);
 // A screen blank invalidates authentication; waking at real lock never draws Desktop.
 screenBlank=1;[m update];assert(!m.host.superview && !m.authenticatedSession && !wallPixels.hidden);
 screenBlank=0;screenLocked=1;sliding.frame=CGRectMake(0,0,390,844);[m update];assert(!m.host.superview && !m.playback.wantsPlayback);
 // Fresh unlock must bind the warm Home frame BEFORE the still-withdrawing
 // CoverSheet reaches zero height. Waiting for an empty cover flashes wallpaper.
 screenLocked=0;sliding.frame=CGRectMake(0,-422,390,844);[m update];
 // The user-visible contract here is the WALLPAPER: a fresh unlock must bind the
 // warm Home frame before the sheet finishes withdrawing (no wallpaper flash).
 // Whether the render layer is already drawn on this exact tick is a timing nit.
 assert(m.authenticatedSession && m.host.superview==wall && wallPixels.hidden);
 sliding.frame=CGRectMake(0,-844,390,844);[m update];assert(m.host.superview==wall);
 // Unknown NC content fails closed; disabled, missing material and errors restore.
 cover.slideableContentView=nil;[m update];assert(!m.host.superview && !wallPixels.hidden);cover.slideableContentView=sliding;
 m.enabled=NO;[m update];assert(!m.host.superview && !m.playback.wantsPlayback && !wallPixels.hidden);m.enabled=YES;m.playback.path=@"movie";
 [m update];m.playback.error=[NSError errorWithDomain:@"test" code:5 userInfo:nil];[m update];assert(!m.lease);m.playback.error=nil;
 // Wallpaper content must stay background-only. Foreground text forbids hiding.
 UILabel *text=[UILabel new];[wallPixels addSubview:text];[m update];assert(!m.lease && !wallPixels.hidden && m.host.superview==home);
 [text removeFromSuperview];[m update];assert(m.host.superview==wall && wallPixels.hidden);
 // Host replacement restores old content before acquiring a new lease.
 SBFWallpaperView *newWall=[SBFWallpaperView new];UIView *newPixels=[UIView new];[wallWindow addSubview:newWall];[newWall addSubview:newPixels];newWall.contentView=newPixels;
 LMVDesktopExplicitWallpaper=newWall;[m update];assert(m.host.superview==newWall && newPixels.hidden && !wallPixels.hidden);originalTree(wall,wallOriginal);
 // Original hidden baseline remains hidden when the plugin releases it.
 [m suspend];assert(!newPixels.hidden && !m.playback.wantsPlayback);m.suspended=NO;newPixels.hidden=YES;[m update];[m suspend];assert(newPixels.hidden);newPixels.hidden=NO;m.suspended=NO;
 // Exact PaperBoard Home variant receives its own video above its background
 // scene/snapshot content; Lock variant is never a candidate.
 LMVDesktopExplicitWallpaper=nil;record.visible=NO;PBUIPosterHomeViewController *poster=[PBUIPosterHomeViewController new];UIView *posterRoot=[UIView new];UIView *snapshot=[UIView new];[wallWindow addSubview:posterRoot];[posterRoot addSubview:snapshot];poster.viewIfLoaded=posterRoot;[LMVDesktopControllers addObject:poster];
 NSArray *posterOriginal=posterRoot.subviews.copy;[m update];assert(m.host.superview==posterRoot && posterRoot.subviews.lastObject==m.host);originalTree(posterRoot,posterOriginal);
 [LMVDesktopControllers removeObject:poster];record.visible=YES;[m update];assert(m.host.superview==home && [home.subviews indexOfObject:m.host]==1);originalTree(home,homeOriginal);
 // Early first layout with a matching still image must draw before launch,
 // with no request to start the player. Transition to ready retains that layer.
 LMVLaunchReady=NO;[m update];assert(m.host.superview==home && !m.playback.wantsPlayback && m.playback.posterOnlyVisible && !m.playback.renderLayer.hidden);
 CALayer *earlyLayer=m.playback.renderLayer;LMVLaunchReady=YES;[m update];assert(m.playback.wantsPlayback && m.playback.renderLayer==earlyLayer && !m.playback.renderLayer.hidden);
 // Typed IMP hooks forward once, record visibility only, and never invoke
 // wallpaper sharedInstance from lifecycle or discovery.
 [m suspend];[m.host removeFromSuperview];
 LMVInitialized=YES;LMVLaunchReady=NO;LMVDesktopUIAvailable=NO;LMVDesktopVideo=nil;
 LMVDesktopVideoInstallHooks();NSUInteger before=sharedCalls;
 // viewDidLoad and arbitrary wallpaper layout do not open the UI creation gate.
 NSUInteger constructed=playbackConstructions;
 [controller viewDidLoad];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 [wall layoutSubviews];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 SBHomeScreenViewController *detached=[SBHomeScreenViewController new];detached.viewIfLoaded=[UIView new];
 [detached viewDidLayoutSubviews];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 // Attached Home original layout has completed: now create one manager and
 // adopt the cache-only seed without starting a video decoder before launch.
 [controller viewDidLayoutSubviews];assert(LMVDesktopUIAvailable && LMVDesktopVideo && playbackConstructions==constructed+1);
 assert(LMVDesktopVideo.playback.posterLayer.contents && LMVDesktopVideo.playback.posterOnlyVisible && !LMVDesktopVideo.playback.wantsPlayback);
 assert(!LMVDesktopVideo.playback.builds && LMVDesktopSeed.image==NULL);
 for(int n=0;n<50;n++)LMVDesktopHostReady(controller);assert(playbackConstructions==constructed+1);
 [controller viewWillAppear:YES];[controller viewDidAppear:YES];[controller viewDidDisappear:NO];
 assert(controller.loads==1 && controller.layouts==1 && controller.appearances==2 && controller.disappearances==1 && sharedCalls==before && !requests);
 [LMVDesktopVideo suspend];[LMVDesktopVideo.host removeFromSuperview];
 // Existing warm desktop resumes synchronously in after-original willAppear,
 // while authenticated unlock is complete but CoverSheet still covers half.
 LMVLaunchReady=YES;screenBlank=0;screenLocked=1;LMVDesktopExplicitWallpaper=wall;
 LMVDesktopVideoScreenChanged();assert(LMVDesktopVideo.suspended && !LMVDesktopVideo.host.superview);
 screenLocked=0;sliding.frame=CGRectMake(0,-422,390,844);
 [controller viewWillAppear:YES];
 assert(!LMVDesktopVideo.suspended && LMVDesktopVideo.authenticatedSession && LMVDesktopVideo.host.superview==wall && wallPixels.hidden && !LMVDesktopVideo.playback.renderLayer.hidden);
 LMVDesktopVideoScreenBlank();assert(LMVDesktopVideo.suspended && !wallPixels.hidden);
 LMVDesktopVideoScreenChanged();assert(!LMVDesktopVideo.suspended && !LMVDesktopVideo.host.hidden);
 sliding.frame=CGRectMake(0,-844,390,844);[LMVDesktopVideo update];
 // 500 after-original layouts: zero global refresh requests and no complete
 // policy pass. The lightweight repair only writes when geometry actually moves.
 LMVDesktopLifecycle(controller,1);[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 LMVDesktopExplicitWallpaper=wall;[LMVDesktopVideo update];assert(LMVDesktopVideo.container==wall);
 NSUInteger beforePolicy=fullDesktopPolicies,beforeGlobal=requests,beforeLayout=LMVDesktopVideo.playback.layoutCalls;
 for(int n=0;n<500;n++){[controller viewDidLayoutSubviews];[wall layoutSubviews];}
 [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 assert(fullDesktopPolicies==beforePolicy && requests==beforeGlobal && LMVDesktopVideo.playback.layoutCalls==beforeLayout);
 CGRect boundsBefore=wall.bounds;wall.bounds=CGRectMake(0,0,390,800);[wall layoutSubviews];
 assert(CGRectEqualToRect(LMVDesktopVideo.host.frame,wall.bounds) && fullDesktopPolicies==beforePolicy);wall.bounds=boundsBefore;[wall layoutSubviews];
 [LMVDesktopVideo suspend];[LMVDesktopVideo.host removeFromSuperview];
 SBWallpaperController *publisher=[SBWallpaperController sharedInstance];publisher.homescreenWallpaperView=wall;publisher.lockscreenWallpaperView=[UIView new];LMVDesktopDiscover();assert(LMVDesktopExplicitWallpaper==wall && sharedCalls==before+1);
 publisher.lockscreenWallpaperView=wall;LMVDesktopDiscover();assert(!LMVDesktopExplicitWallpaper);publisher.lockscreenWallpaperView=[UIView new];
 [m suspend];[m.host removeFromSuperview];
 puts("PASS: production Desktop manager/typed hooks with real QuartzCore: explicit Home wallpaper above content, baseline-aware content restore, app/screen/lock/unknown gates, 101 NC pulls and paused retained frame, fallback below icons/Dock, exact PaperBoard Home variant, replacement/disable/error, no singleton creation or backing detach; separate real AVFoundation test covers decoder independence; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'desktop.m';binary=Path(tmp)/'desktop';source.write_text(pre+helpers+abi+h+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)

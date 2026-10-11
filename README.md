# 锁屏消息视频

面向 iOS 16.5 / Dopamine roothide(rootless 风格) 的锁屏通知视频背景插件工程。

## 功能
- 启用插件开关
- 选择消息背景视频
- 清除消息背景视频
- 选择选项区域视频
- 清除选项区域视频
- 设置面板内从系统相册挑选视频并复制到插件目录

## 视频保存路径
- Filza: `/var/mobile/LockMessageVideo/`
- 默认消息素材: `/var/mobile/LockMessageVideo/message.mov`
- 选项、清除及素材库视频也保存在该目录。

消息、选项、清除背景的透明度开关关闭时完全透明；开启时滑块值按 0.0 到 1.0 作为这些视频背景的 alpha。0.0.76 支持独立锁屏和桌面视频，分别选择素材、默认不透明，不受消息透明度控制。锁屏视频仅在已存在的 CoverSheet 内容范围内显示，首帧未就绪或素材失败时保留系统壁纸；关闭功能移除自有宿主。播放仅使用视频轨道，静音且不激活音频会话，不影响音乐或系统音频。

## 编译
### 本地
```sh
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
```

### GitHub Actions
把整个工程上传到 GitHub 仓库，Actions 会在 `packages/` 产出 deb 并上传 artifact。

## 0.0.95：回退「一下拉就铺满」，改为跟随下拉的渐进显露；诊断扩到三个通道 + 卡顿观测

0.0.92~0.0.94 为了让面板滑动时不露壁纸，把裁剪基准改成「整个窗口可见视口」并把宿主提升
到面板之外。实测结果是**下拉一点点视频就整屏铺开**，与预期相反。

本版把锁屏/通知中心通道**整体回退到 0.0.91 的跟随行为**：

```objc
CGRect clip=LMVLockVideoClip(content,container,content.window);   // 裁剪跟随可滑动内容
[self.host insertSubview:... aboveSubview:anchor];                // 宿主仍在面板内、背景之上
```

即「**下拉多少、视频出来多少**」。0.0.92~0.0.94 引入的提升/视口裁剪代码全部移除。

### 诊断扩展（设置里打开「启用诊断日志」，写入 `/var/mobile/LockMessageVideo/shared-render.log`）

三个通道各输出一行覆盖度量，数值单位为点，按 20pt 分桶，只在跨桶时记录：

```
lock-video cover reveal=266.0 gapTop=0.0 gapBottom=666.0 leakArea=0.715 hostHidden=0 container=CSCoverSheetView ...
desktop-cover    attached=1 revealed=932.0 gapTop=0.0 gapBottom=0.0 visible=1 frozen=0 hostHidden=0 container=UIView
cc-cover         attached=1 revealed=932.0 gapTop=0.0 gapBottom=0.0 visible=1 material=MTMaterialView window=SBControlCenterWindow
```

- `reveal`：该通道视频当前真正铺出的高度
- `gapTop` / `gapBottom`：上下各有多少像素没有视频（漏背景/漏壁纸的量）
- `attached` / `hostHidden` / `visible`：是否挂上、是否被隐藏、是否判定可见
  —— 用来区分「掉背景」（attached=0）和「被挡住」（attached=1 但 gap>0）

### 卡顿观测

每个通道每 2 秒输出一次 `update` 的耗时统计：

```
perf lock    calls=60 max=1.84ms slow=0
perf desktop calls=20 max=0.42ms slow=0
perf cc      calls=20 max=3.91ms slow=1
```

`slow` 是单次 `update` 超过 4ms 的次数。如果卡顿，`max` 会明显抬高，`slow` 会累加，
可直接对应到是哪个通道在拖帧。

## 0.0.94：找到真正可用的槽位（0.0.93 报 promo-no-slot）

0.0.93 日志：

```
lock-video cover CSCoverSheetView>self promo-no-slot top=0 bot=860 ...
```

提升已经找到了能覆盖整屏的祖先（`SBCoverSheetPositionView`），但**面板分支在那个祖先里
排第一个**，下面没有兄弟可插——插进去就等于放到面板**背后**，会被面板自己的背景视图
`SBUIBackgroundView` 挡住。所以 0.0.93 选择放弃。

本版改为：**继续向上找同时满足「覆盖视口」和「面板分支之前有兄弟」的祖先**。
再往上一层（controller 自己的视图，即 `SBFTouchPassThroughView`）里，
面板背景分支 `SBCoverSheetPanelBackgroundContainerView` 与面板分支
`SBCoverSheetPositionView` 是**并列的两个子视图**，正好就是需要的槽位：

```
SBCoverSheetWindow
 └ SBFTouchPassThroughView            ← 提升目标（满屏、不裁剪）
    ├ SBCoverSheetPanelBackgroundContainerView
    ├ ▼ 视频落在这里
    └ SBCoverSheetPositionView       ← 面板内容，仍在其上
```

层级语义正好：**在面板背景之上、在面板内容之下**。日志里会写成
`promo:SBFTouchPassThroughView`（跳过的祖先数会记成 `promo-skipN:...`）。

## 0.0.93：让 0.0.92 的提升真正生效 + 定位漏出方向

设备日志（`shared-render.log`）显示 **312/312 行仍是 `CSCoverSheetView>self`**，
即 0.0.92 的提升从未生效。日志还给出了确切规律：

```
contentClip 起始 y  ≡  -hostInWindow 起始 y
```

也就是「视频的可见区恰好等于面板当前盖住的那一段」——面板一偏移，另一端就露壁纸。

原因：0.0.92 在向上遍历祖先时，遇到第一个 `clipsToBounds` 的祖先就 `break` 返回，
而实际层级里那个祖先确实存在，于是每次都直接放弃提升。

本版修正：

- 遇到会裁剪的祖先改为 `continue` 继续向上找。裁剪与否不影响正确性——
  宿主最终放在**这个祖先里、面板分支之下**，并不会画进那个裁剪视图内部；
  唯一的判据是「该祖先是否覆盖窗口可见视口」。
- 提升原因写入日志（`covers` / `promo:<类名>` / `no-ancestor` / `promo-no-slot`）。

诊断行同时改为输出**屏幕坐标下的两条缝**：

```
lock-video cover CSCoverSheetView>SBFTouchPassThroughView promo:SBFTouchPassThroughView top=0 bot=0
  viewport={{0,0},{430,932}} clip={{0,0},{430,932}} visible={{0,0},{430,932}}
  hostInWindow={{0,0},{430,932}} gapTop=0.0 gapBottom=0.0 leakArea=0.000
```

`gapTop` / `gapBottom` 为 0 表示上下都不漏。

## 0.0.92：修复下拉通知中心过程中顶部露出壁纸

CoverSheet 的层级是：

```
SBCoverSheetWindow
 └ SBFTouchPassThroughView            (controller.view，满屏、不裁剪)
    ├ SBCoverSheetPanelBackgroundContainerView   ← 面板自己的背景/模糊
    └ SBCoverSheetPositionView
       └ SBFTouchPassThroughView   ← 滑动时整体偏移的就是这一层
          └ CSCoverSheetView      └ clipsToBounds=1 ← 视频原本挂在这里
```

视频原本挂在 `CSCoverSheetView` 内、裁剪范围也只算「可滑动内容的可见区」。
面板滑动时整条 `PositionView` 分支被偏移，**面板没盖到的那一段就露出系统壁纸**，
而挂在面板内部的图层无论怎么放大都盖不到面板之外（`clipsToBounds=1`）。

本版做两件事：

1. **提升宿主**：当所在容器没能覆盖窗口可见视口时，把视频层提升到第一个
   「不裁剪 + 覆盖整个可见视口」的祖先（即 `SBFTouchPassThroughView`），
   插在**面板分支之下、面板背景分支之上**，层级关系不变。
2. **扩展裁剪**：提升后裁剪基准改为「窗口可见视口 ∩ 新容器」，视频铺满整屏。

**可见性判定不变**：仍然由可滑动内容的可见区决定，面板收起（内容滑出屏幕）时
`contentClip` 为空 → 视频照旧撤下，不会在解锁后残留。

### 诊断（自带日志，设置里打开「启用诊断日志」）

每次覆盖状态变化时向 `/var/mobile/LockMessageVideo/shared-render.log` 写一行：

```
lock-video cover CSCoverSheetView>SBFTouchPassThroughView top=40 area=0.04
  viewport={{0,0},{430,932}} contentClip={{0,0},{430,266}} clip={{0,0},{430,932}}
  hostInWindow={{0,40},{430,892}} leakTop=40.0 leakArea=0.043
```

`leakTop` / `leakArea` 就是「漏出的壁纸」有多少：`0 / 0.000` 表示完全覆盖。
数值按 20pt / 2% 分桶，只在跨越桶时记录，所以拖一次只写几行。

## 0.0.91：修复打开 App 瞬间视频背景变成原壁纸

打开应用的过渡期间，`LMVDesktopForeground()` 把前台判定为应用（返回 -1），`environment`
随之失效，旧代码走 teardown 分支：

```objc
self.host.hidden=YES;[self.lease restore];self.lease=nil;
[self.host removeFromSuperview];self.container=nil;
```

宿主与抑制租约一起被撤销，于是**整个启动动画期间显示的都是系统静态壁纸**，而不是视频
的当前画面。

本版改为：应用切到前台时**保留宿主、保留租约、只冻结播放**。

- 新增 `-[LMVLockVideoPlayback setFrozen:]`：`wantsPlayback` 为 NO、解码器暂停，但
  `renderLayer` 继续显示当前帧（暂停的 AVPlayerLayer 会保留画面）。
- 桌面通道新增 `appForeground` 分支：不再拆除宿主，改为冻结。应用的窗口都位于
  Home / 壁纸窗口之上，冻结画面被应用挡住，暂停后也不再消耗解码。

真正需要撤下的场景（息屏、锁屏、未知通知内容、功能关闭、解码错误、禁用素材）仍然走
原来的 teardown 分支，行为边界不变。

## 0.0.90：回退到 0.0.84 行为（只保留诊断用图层命名）

0.0.85 ~ 0.0.89 的改动都建立在对设备的推测上，实测反而引入了新的不确定行为。
本版把**产品代码整体回到 0.0.84**（即「控制中心降半屏修复」那个你确认过可用的版本），
0.0.85 / 0.0.86 的锁屏裁剪兜底、0.0.87 的消息卡片可见性改动、0.0.89 的桌面通道改动
**全部撤销**。

保留的唯一改动是**纯命名**（不影响渲染、布局、播控）：

| 图层 | 名称 |
|------|------|
| 消息卡片视频承载视图 | `com.minis.lockmessagevideo.card.surface` |
| 消息卡片视频渲染层 | `com.minis.lockmessagevideo.card.render` |

锁屏 / 桌面 / 控制中心通道原本已有同类命名，至此四个通道一致，外部诊断工具
（`com.minis.lmvdiagnostic` 0.0.3）可以按前缀一次性定位全部视频层，
并逐道核对 `verdict=PASS/FAIL(...)`、祖先链与遮挡情况，从而在**不改产品代码的
前提下**先确定断点位置，再决定要不要动代码。

## 0.0.84：修复控制中心 / 通知中心「降半屏」时视频背景消失

降半屏（面板不再全屏）时 `SBControlCenterWindow` / `SBCoverSheetWindow` 会被系统置为
`hidden=1`，而窗口仍占据整屏。旧代码把这个 `hidden` 当作「不该显示视频」的否决条件：

- `LMVLockVideoRectInTree()`：`window.hidden` + 祖先 `hidden` 遍历 → 几何直接归零
- `LMVCCVisibleViewport()`：祖先 `hidden` 短路 → 同样归零
- `update()`：控制中心通道复用桌面的 `LMVDesktopGeometryVisible()`，同样被 `hidden` 拦下

几何归零后 `LMVCCMaterial()` 首行即 bail、视频层被 `removeFromSuperlayer` 摘除，背景随之消失。
现在改为：**窗口/祖先的 `hidden` 不再作为几何否决条件**，只以 `LMVVideoWindowViewport()`
（窗口真正移出屏幕时返回零）作为几何基准；同时 `LMVCCMaterial()` 的高度判据改为
`MIN(viewport.height, material.height)`，使半高 material 在视口仍为全屏时也能命中。

实测证据（`/var/mobile/Documents/LMVDiagnostic.log`）：控制中心 `SBControlCenterWindow.hidden=1`
出现 16/40 次、通知中心 `SBCoverSheetWindow.hidden=1` 出现 30/40 次，均伴随 `viewport=(invalid)`；
703 次全屏样本、49 次塌零、真正的半屏几何一次都没采到 —— 全被 `hidden` 短路吃掉了。

## 0.0.83：修复消息折叠展开时背景短暂掉落

- 消息卡片在折叠/展开动画中保持原背景替换租约，隐藏、透明或暂时离开可视区域只暂停取帧，不立即恢复系统背景。
- 新消息材质优先即时接入缓存画面，不等待选项/清除的 100ms 批量发现节流。
- 卡片布局变化只同步自有视频层几何，不重新发现、重建播放器或刷新全局状态。
- 新增消息折叠展开、换宿主、复用和原背景恢复回归测试；真机动画仍需安装后验收。

## 0.0.82：首次续播、半屏视频和设置原片导入

- 基于已发布 0.0.81，保留局部卡片合并、稳定宿主复用和桌面/通知中心/控制中心悬浮范围。
- 已选消息、选项、清除素材准备完成后建立暂停的共享播放链，减少第一次下拉或左滑时的现场分配；保留播放器普通暂停后的恢复直接续播，不再每次精确定位。冷缓存新播放器仍按就绪状态恢复保存的时间点。Reader 后备普通暂停恢复保留原 reader/待显示 sample，并补偿暂停时长。
- 通知中心和控制中心的半屏/Reachability 使用实际屏幕转到窗口坐标的视口，窗口 bounds 不再被当成完整屏幕曝光。通知中心视频只裁剪到实际面板内容；控制中心全宽背景材质按可见视口高度识别，进出半屏不重建源，未知/模块材质不作为背景。
- 设置页和另一路相册 picker 改为 Current 原片复制、验证后原子发布，不编码/缩放/降低 FPS，不再执行 ≤5 MiB 压缩。保留 MOV/MP4/M4V 扩展名、文件字节和音轨；单文件 ≤512 MiB、源需为可解码普通文件。现有素材/偏好不重写。
- 实际播放仍使用 video-only composition 并静音，原文件保留音轨不代表背景启用声音。原片可有更高帧率和分辨率，消息显示取帧仍30Hz，不能保证高负荷素材下零掉帧。
- 原生回归检查真实 AVPlayer 直接续播/冷定位/Reader 复用、半屏屏幕偏移和材质识别，以及原片字节/音轨/FPS/尺寸/扩展名保留与导入失败回滚。CI 不代替真机首次曝光、左滑与半屏显示验收。

## 0.0.81：基于正式 0.0.79 的消息下拉优化

- 基线为 CI 已验证的 0.0.79（8b43c0b；1626fbfe 的 revert 后树相同）。未采用 0.0.80 的每卡片 100ms 定时完整更新方案。
- 消息、选项、清除继续使用按素材路径共享的 AVPlayer/VideoOutput 与 Reader 后备链路，帧调度仍为30Hz。没有切换成每卡片多个播放器，也没有提高素材导入帧率。
- 卡片/操作区域布局进入弱引用局部合并队列，同一个回合仅更新相关 owner；不刷新锁屏、桌面和控制中心。全局偏好、屏幕及 CoverSheet 生命周期仍通过启动就绪后的安全队列刷新。
- 已找到且仍属于原卡片的消息材质复用；稳定几何跳过周期完整更新，保留一秒背景完整维护；源/修订/父级/尺寸/可见性变化及时更新。找到宿主后结束发现重试，复用使旧重试失效；诊断关闭时跳过热点日志构造。原背景租约归属/恢复逻辑保留。
- 小彩蛋悬浮图标扩展到解锁后的桌面、通知中心和控制中心；普通应用、真实锁屏、熄屏与安全弹窗隐藏。保留拖动、GIF、输入焦点归还和浮窗原片导入成功提示。
- 原生测试执行局部队列、稳定几何/宿主失效、重试取消和悬浮前台范围。源码/CI通过不等于真机下拉已经零掉帧；使用用户录屏相同通知数量和手势验收。

## 0.0.78：修复注销后启动断言

- 针对 SpringBoard-2026-10-10-204038.ips：插件 arm64e UUID 与 0.0.77 匹配，异常发生在 dyld 加载初始化阶段，桌面提前预备入口创建 UIView 后触发 UIScreen 初始化断言，导致 SIGABRT。
- 加载阶段的桌面预备改为 Foundation 偏好读取及排队读取静态缓存海报，不创建管理器、UIView、CALayer 或播放器，不查询 UIScreen/UIApplication。
- 桌面管理器增加创建门槛和重入保护；仅在已初始化、附着窗口的主屏视图完成原布局/出现回调后，或启动就绪之后创建。普通壁纸 layout 回调不再进入早期发现、屏幕状态查询或 UI 创建。
- 保留同素材海报到动态播放的交接，以及控制中心单开关、深色/浅色独立素材、锁屏、消息和浮窗导入提示。素材数据及偏好不迁移或删除。
- 原生回归新增模拟 UIKit 尚未初始化的禁用阶段，实际执行桌面预备函数并验证零视图/播放器/屏幕/应用访问；验证脱离窗口、普通壁纸 layout 不能开门，附着主屏布局后只创建一套宿主并交接缓存海报。CI 仍不代替 iOS 真机注销启动验收。

## 0.0.77：桌面首屏海报与控制中心深浅色视频

- 基于已发布 0.0.76 修复桌面启动准备过晚的问题：提前预读选中视频的首帧缓存，在明确桌面宿主首次布局时先显示该视频海报，再交接到异步准备的动态播放器。只读取有界的静态缓存图，不在 Hook 内同步解码视频或创建壁纸单例。
- 首帧图保存到 `.background-posters`，按路径和文件修订严格校验，素材替换/删除、缓存损坏时拒绝旧图。首次没有缓存时后台生成；有缓存后注销可提前显示，实际首屏时序需设备验证。
- 新增控制中心背景独立播放器与开关 `ControlCenterBackgroundEnabled`；`ControlCenterDarkVideo` 与 `ControlCenterLightVideo` 分别选择深色和浅色模式素材，按系统外观自动切换，未选对应模式时保留系统背景。设置与浮窗都提供一组开关和两份素材选择。
- 参考 VideoBackground 0.1.0-45 的控制中心覆盖控制器、全屏 MTMaterialView 背景和展开进度路径；仅挂插件自有背景层，不改变原按钮、滑块、材质视图和 backing layer。收回、关闭、熄屏暂停；模式切换清除旧画面，播放器不与锁屏/桌面/消息共享。
- 删除素材同步清理两项控制中心选择；导入不自动分配锁屏、桌面和控制中心。保留原片导入提示、小彩蛋通知中心显示范围、消息背景与现有锁屏功能。
- Actions 运行实际 ImageIO 缓存测试、AVFoundation 缓存到播放交接、QuartzCore 桌面启动与控制中心模式/进度/层级测试，再编译 rootless arm64 + arm64e deb。编译和原生测试不等于 iOS 真机视觉与注销时序验收。

## 0.0.76：独立桌面视频

- 基于已发布 0.0.75 保留锁屏实现，新增 DesktopBackgroundEnabled / DesktopVideo，设置和通知中心浮窗均可选择桌面素材；默认关闭、未选择，导入不自动分配锁屏或桌面。
- 参考 VideoBackground 0.1.0-45 的桌面路径：已存在的 SBWallpaperController 发布 homescreenWallpaperView，视频 UIView 放在 SBFWallpaperView.contentView 上方；只在视频已就绪时隐藏该明确的主屏内容，关闭/离开/换宿主恢复。原 UIKit backing layer 和 sibling 顺序保持。
- iOS 16 PaperBoard 环境可使用明确的 PBUIPosterHomeViewController 纯背景支路；桌面控制器视图作为回退，视频位于背景上方、图标和 Dock 下方。未知共享 Lock/Home 或 CoverSheet 宿主拒绝，不调用 sharedInstance 创建系统单例。
- 锁屏与桌面分别创建视频播放器、AVPlayerLooper、AVPlayerLayer、海报和时间轴，即使选择同文件也不共享状态；素材切换和关闭独立清理，消息缓存保持原逻辑。
- 应用前台、真正锁屏和熄屏暂停；本次已解锁后的部分通知中心下拉保留桌面背景，完全盖住时暂停并保留画面；范围未知隐藏。小彩蛋仍只在解锁后通知中心显示。
- CI 新增真实 QuartzCore 桌面宿主/恢复/101 下拉位置/Hook 检查以及真实 AVFoundation 双实例隔离检查；编译 arm64 + arm64e rootless。真实设备壁纸镜像、Dock 和应用转场效果需验收。

## 0.0.75：独立锁屏视频测试版

- 基于已发布 0.0.74 重新加入 LockScreen 开关和素材选择，设置与通知中心浮窗均可操作；初始默认关闭、未选择素材。主屏视频不加入，消息、选项、清除功能与小彩蛋只在解锁后通知中心显示的范围保留。
- 参考用户提供的 VideoBackground 0.1.0-45 实际锁屏路径：CSCoverSheetViewController 生命周期、独立非交互 UIView、AVQueuePlayer + AVPlayerLooper + AVPlayerLayer。采用独立实现；原私有方法校验 ABI 后 Hook，原实现调用一次，所有策略在启动就绪后的主队列运行。
- 优先将自有视频宿主插入锁屏控制器根视图内，位于已确认的背景支路之上、系统遮罩和时钟/通知/控件之下。滑动内容几何独立裁剪，未知内容不回退全屏窗口；原系统 UIView、backing layer 和原 sibling 顺序保留。
- 锁屏拥有独立播放器、循环队列、素材修订和首帧海报，不进入消息帧缓存，静音并仅加载视频轨道。熄屏暂停、退出隐藏、重复布局复用，素材切换/关闭清理旧队列、观察者、海报和显示层。
- CI 执行原生 AVFoundation 播放及 QuartzCore 层级/曝光/Hook 测试，再构建 rootless arm64 + arm64e deb；真机锁屏、下拉/收回和 portal 转场效果需验收。

## 0.0.74

- 完全移除锁屏/通知中心整屏视频的设置、悬浮面板控制项、渲染、播放器入口和壁纸专用追踪代码；桌面功能继续保持移除。旧素材文件和偏好保留但不用于这些已移除目标。
- 保留 Message/Options/Clear 三类背景视频、素材管理、透明度和原背景的可恢复绘制压制，不再有锁屏播放器向消息公共帧缓存发布画面。
- 小彩蛋仅在本次亮屏已解锁且通知中心滑动内容实际露出时显示。桌面、应用、真正锁屏、熄屏及未知内容范围隐藏；收回后归还输入焦点。保留图片/GIF、拖动、素材选择和大小设置。
- 浮窗相册原片导入成功后使用现有内嵌提示显示“导入成功 / 已保存到素材库”；失败显示原因，取消不提示。结果可跨面板关闭/重开送达，未确认提示保留，不自动选择素材。
- Actions 执行保留功能的源码与 Foundation/AVFoundation/QuartzCore 原生测试，再编译 arm64/arm64e rootless deb。原生 doubles 和成功构建不代替 iOS 通知中心/相册的真机验收。

## 0.0.73

- 按最新需求撤回锁屏/桌面/通知中心壁纸替换实验。锁屏和通知中心改为直接叠加视频：在已有 CoverSheet 内容的系统背景之上、时钟/通知/操作控件之下，放置插件自有的非交互视频层。原壁纸视图、backing layer、alpha 和层级不改。
- 锁屏/通知中心视频固定 opacity=1，完全独立于 VideoOpacityEnabled 与 VideoOpacity；共享透明度仅控制 Message/Options/Clear。下拉裁剪使用同一 model/presentation 树，取消/换素材/关闭时不重新挂旧层。
- 完全移除 Desktop 后台渲染、解码入口、Home/Dock hooks/定时器、设置开关/素材切换和小彩蛋面板对应项。旧偏好与视频文件保留但不再读取或渲染，设备原桌面壁纸由系统正常显示。
- 小彩蛋保持全局悬浮，取消 lockstate 隐藏条件，亮屏锁屏/通知中心也显示；熄屏和实际可见安全弹窗仍隐藏。保留窗口层级、拖动、GIF、键盘焦点归还。
- 去掉小彩蛋图片设置页和设置首页的静态预览；保留图片/GIF导入和图标大小。小彩蛋浮窗里的素材列表改成文字列表，不请求缩略图；设置页素材缩略图不变。
- 增加原生测试验证不透明叠加顺序、101个下拉位置、原背景树完整、无帧/取消/旧状态/关闭，保留播放器和其他背景功能回归。真实 iOS 显示/触控结果仍需测试。

## 0.0.72

- 针对 SpringBoard-2026-10-10-104336.ips：已加载插件 UUID 与 0.0.71 arm64e 完全匹配；这次在 UIKit 的 subviews / content-scroll-view heuristic 遍历及 CoverSheet 下拉定位过程中崩溃，故障栈没有插件帧。报告不能独立证明所有损坏来源。
- 撤回锁屏、桌面和通知中心对 UIView backing layer 的直接 detach。系统视图、父层、子层、delegate 和原顺序保持完整，仅对已确认的原背景做可恢复绘制压制；视频在各自宿主中显示。此变更优先解决层级完整性风险，不等于拦截静态壁纸文件加载。
- 保留独立 Lock/Home 解码源、通知中心露出范围裁剪及透明度设置。本版没有改透明度行为。
- 原生测试令每次 subviews 遍历都检查对应 backing layer 仍在父层，覆盖 500 次刷新、100 个下拉位置、系统绘制值更新、独立关闭/更换及恢复；真机是否不再安全模式仍需确认。

## 0.0.71

- 针对 SpringBoard-2026-10-10-101258.ips（iOS16.5、arm64e）：二进制 UUID 7B7465E3-19CA-33CC-952D-C86DFFF9096C 与 0.0.70 完全匹配；插件偏移 0x2cb20 的调用点在背景安全检查的 layer getter 返回值 retain，调用方来自通知中心壁纸更新。
- 已接管的背景不再重新进入效果视图检查或调用其 layer getter，维护和恢复使用保存的图层/视图身份；诊断也跳过 owned-offline 视图的 layer 读取。此修复移除已定位的重复访问路径，不能单凭报告确认原 getter 返回失效的全部原因。
- 修正 surface dealloc 清理，不向 strong ARC C 函数传递正在析构的 self；保留原图层归属校验与逆序恢复。
- 新测试令已脱层 SBWallpaperEffectView 的 layer getter 抛异常，要求 100 次下拉刷新/显示隔离/关闭恢复零访问，并验证 live-lease surface 析构正确恢复且不复活对象。独立解码和显示范围修复保持。

## 0.0.70

- 修正 0.0.69 下拉/收回通知中心时锁屏视频覆盖露出桌面的问题：不再把背景容器 bounds 当作通知中心露出范围，改用已有 CoverSheet 内容视图及动画中的真实可见矩形。
- 仅裁剪插件自己的通知中心视频层，桌面视频及系统容器的 alpha、transform、frame 和 mask 不改；背景与内容分别移动时也以内容边界裁剪。
- 通知中心视频副本接管显示时抑制插件原 Poster Lock 视频层的重复显示，保持显示归属跨刷新；桌面播放/暂停与独立解码保持不变。
- 原生测试专门模拟背景面板与内容错位，验证 100 个下拉位置的边界外无 Lock 绘制、取消后不覆盖 Home、独立帧发布和原副本恢复。真机 portal 与转场仍需验收。

## 0.0.69

- 针对通知中心整屏背景必须下拉到底才出现的问题，接管已观测的 SBCoverSheetPanelBackgroundContainerView 中 SBWallpaperEffectView/PBUIWallpaperView 背景副本；视频挂到同一个滑动容器内，保留系统位置、变换及前景内容。
- 任何实际露出的背景条带即可激活已有 LockScreen 独立解码源；不再只依赖 CSCoverSheetView 完整显示，不创建第三套播放器，不改通知卡片视频或桌面源。
- 采用 0.0.68 的稳定租约维护，原壁纸副本从父层移除；取消下拉时视频随原滑动容器移出屏幕，禁用、隐藏窗口或系统换宿主时恢复原副本。
- wallpaper-structure.log 中新增 wallpaper-notification 状态，记录 exposed、帧就绪、detach 数量与 panelFrame。真实 QuartzCore 测试覆盖首个露出条带、100 个下拉位置、租约身份、前景保留、Lock-only 帧发布和恢复。真机转场仍需验证。

## 0.0.68

- 修复 0.0.67 锁屏、桌面视频与原壁纸反复切换：已移除的分支按保存的原父层、scope、宿主和视图身份续租，不再用脱层后的 superview 或坐标转换重新判定候选。
- 保留锁屏/桌面独立播放器、解码器、播放时间和各自壁纸容器。关闭或换素材仍恢复有效的原背景；系统真实删除或换父层时放弃旧归属，不复活/抢回系统对象。
- 新回归测试模拟真机“移除 layer 后 superview=nil、坐标转换失效”，连续更新 500 次验证租约和视频层不闪回；同时验证真实删除、换父层、关闭、换素材、换控制器和独立解码。
- 这是层生命周期修复，不拦截系统静态壁纸文件读取；真机 portal/转场结果仍需测试。

## 0.0.67

- 修复下拉通知中心时锁屏视频串到桌面：不再在壁纸窗口根层切换 Lock/Home；按实际 PBUIPosterLockViewController 与 PBUIPosterHomeViewController 分别替换背景绘制分支，保留系统变换、转场和镜像宿主。
- 锁屏、桌面即使选择同一素材也各自创建独立播放器、视频输出、读取器、解码状态和播放时间；暂停/切换一项不会重置另一项。
- 原壁纸背景仍从各自分支移除，视频不是叠加在原静态图片上。分别禁用后恢复各自原层及原顺序；素材替换、root 重建时不沿用旧内容。
- 真实 QuartzCore 双分支测试覆盖部分下拉隔离、暂停帧、独立关闭恢复、素材无帧、原层重挂及控制器更换。CI 不代替真机通知中心/portal 转场验证。

## 0.0.66

- 锁屏与桌面视频直接接管 `_SBWallpaperSecureWindow`：确认的原壁纸分支从父层移除，视频层接管壁纸窗口根层；关闭、切换素材或离开场景时恢复原壁纸对象和原层级。
- 锁屏/桌面内容宿主只保留帧缓存，不再显示叠加视频层；时间、通知、图标和 Dock 保留在各自上层窗口。
- 保留 0.0.65 的预览和壁纸诊断日志，便于验证直接接管是否命中。

## 0.0.65

- 完善锁屏/桌面诊断，保持 0.0.64 的 25 个 ABI 校验透传 hook；记录累计 hits 和本会话 sessionHits，重新开启诊断后重新采样前 12 次调用和前两次调用栈。
- 新增 wallpaper-provider.log：采集实际返回的壁纸提供者、实际回调场景及客户端参数的类、继承链、模块名、相关方法 ABI 和 ivar 声明；不读取 ivar 值或调用未确认私有 getter。Lock/Home 使用实际控制器类标识；远程 PID 未确认时明确 unknown。
- wallpaper-structure.log 改为每启用会话最多 8 份快照，允许晚出现控制器的有界重试。壁纸三类日志分别限额/轮转，每行含版本、PID、会话编号；不修改壁纸渲染。
- 预览全过程日志：匿名素材编号、列表行号、请求/跳过/排队、内存和磁盘缓存、取帧阶段/错误码/耗时、最终显示海报或占位图。SpringBoard 写 thumbnail-preview-springboard.log，设置页写 thumbnail-preview-settings.log；独立串行写入与每分钟额度，不再受播放日志终身额度影响。
- 用法：安装注销后，关闭再打开「启用诊断日志」；无需开启视频。在桌面停留、下拉通知中心、锁屏/解锁；打开悬浮素材列表，滚动到无缩略图项目并停留。提交 wallpaper-call.log、wallpaper-provider.log、wallpaper-structure.log、thumbnail-preview-springboard.log 及存在的 .1；设置页测试另交 thumbnail-preview-settings.log。
- 本版补诊断，不宣称已修复剩余素材预览或已阻止静态壁纸读取。

## 0.0.64

- 基于 0.0.63 增加壁纸调用追踪，不改变原方法返回值、素材预览或壁纸显示逻辑。
- 对 25 个专用候选接口校验真实返回类型及参数 ABI；不匹配/类不存在/方法不存在会记录原因，不强行 hook。
- 单独保存 wallpaper-call.log（256 KiB 轮转）：wallpaper-hook 表示安装状态，wallpaper-call 表示实际调用和返回对象类型，wallpaper-coverage 区分 called 与 not-observed。前两次调用记录模块、偏移和符号调用栈。
- 开启诊断后注销 SpringBoard，不必开启视频；进入桌面、下拉/收回通知中心、锁屏/解锁。若可以，切换一次系统壁纸以触发缓存以外的加载，30 秒后提交 wallpaper-call.log/.1 和 wallpaper-structure.log/.1。
- 仅观测 SpringBoard 进程已确认的接口；方法安装不等于实际调用，也不能证明远程进程的静态图像读取已被观测。本版不拦截、不删除原壁纸。

## 0.0.63

- 修复悬浮素材选择页视频预览：导入时生成首帧海报，旧素材首次打开时补生成，取帧失败不再把蓝色胶片占位图永久当成成功缓存。
- 以 0.0.61 为行为基线，撤回 0.0.62 的壁纸窗口接管实验；本版只修素材预览并增强诊断，不宣称已实现系统壁纸背景源接管。
- 增加有界的壁纸结构诊断：记录壁纸窗口、视图、图层、已加载控制器、场景宿主及可见状态，并记录壁纸类的方法名/类型签名；不调用私有 getter、不读取壁纸文件或通知内容。
- 打开「启用诊断日志」，在桌面停留两秒，下拉通知中心并停留两秒，收回后锁屏/解锁一次。提交 `/var/mobile/LockMessageVideo/wallpaper-structure.log` 和 `shared-render.log`（及 `.1` 轮转文件）。SpringBoard 内的预览错误进入 shared-render.log；设置进程的预览错误另存 thumbnail-preview.log。

## 0.0.61

- 开启后消息、选项、清除、锁屏壁纸、桌面壁纸全部去掉原背景，直接显示视频；关闭或停用恢复原背景（可恢复租约，不销毁系统对象；锁屏/桌面在首帧就绪前保留原壁纸）。
- 小彩蛋图片页移除“启用小彩蛋”开关（设置首页保留）。
- 解锁后下拉通知中心，悬浮彩蛋保持显示在通知中心上方。
- 悬浮面板内切换素材、改名可正常弹出键盘，关闭后归还键盘焦点。

## 0.0.60
- 彩蛋图片设置独立：只显示图片预览、启用开关、图片/GIF 导入和 32–128 点大小设置，不混入五项视频设置。彩蛋视频面板保留 Message、Options、Clear、LockScreen、Desktop 五项开关、素材选择、透明度开关/滑块及底部原视频导入；面板圆角 20 点，高度以可用安全区域的 65% 为上限。
- 素材选择复用共享选择器的导航 push 模式；PHPicker 和素材命名提示由子控制器 containment 管理。系统相册远端服务、权限提示和键盘仍可能显示系统全屏 UI，不能保证所有系统界面都嵌在面板内。
- 解锁状态下，不再因通知中心窗口仅仅存在就隐藏悬浮气泡；锁定、熄屏或确认的安全遮挡仍隐藏。
- Options/Clear 原材质发现扩展到同组 ClearAll 相邻支路。壁纸观察只尝试覆盖目标区域至少 85%、唯一且能确认是纯本地背景的支路；remote/scene/shared 或未知混合层仍 guarded-no-op，不销毁、移动或隐藏系统窗口容器，不承诺所有原壁纸都已消失。
- 保留 0.0.59 的按路径共享视频源、磁盘最后帧、静音、启动门及重入保护、Dock 几何和原背景可恢复租约；现有数据与偏好继续使用。包、偏好 bundle 和诊断版本统一为 0.0.60。
- 生产 macOS 工作流执行全部源码、C 几何/消费策略及 Foundation/QuartzCore/ImageIO 原生回归，再编译 arm64 + arm64e rootless 包。CI 通过与产物检查不等于 iOS 真机验证；冷启动、视觉/触控层级、GIF、通知中心、系统相册权限及资源占用仍需设备验收。

## 0.0.58 TEST：原背景可恢复替换
- 现有 Message、Options、Clear、LockScreen、Desktop 的 BackgroundEnabled 开关控制替换，没有增加 UI 开关。启用且存在合法素材选择后，确认的原背景立即从绘制链路脱离/关闭绘制，不等待首帧；选中但文件丢失、加载失败、decoder 失败、卡顿或透明度为 0 不恢复原背景。暂停保留最后真实帧；冷启动无帧为插件透明层，不主动填黑底。用户取消选择（空字符串）或成功删除素材清空选择、关闭开关才恢复；没有选择且不存在的 legacy 默认文件不当作有效选择。
- Message/Options/Clear：优先对无 delegate、无 mask/子层且有明确 Backdrop 身份的独立绘制叶层执行 retained detach。保留原层对象、原父层弱引用、前后邻层及索引；关闭恢复同一对象。UIKit backing layer 不脱离：仅确认整个 Material/Backdrop 支路没有 UILabel、UIControl、文本、滚动、手势、accessibility 或未知绘制子层时，将该背景支路 layer.opacity 置 0 关闭绘制。材质混有文字时保留其容器，将插件视频放在内容下，只处理可辨认背景叶层；不能确认则 guarded-no-op。
- 原背景 opacity 恢复实际基线（例如 0.37，而非强制 1）；多消费者共享弱 owner 租约，最后释放才恢复。重复布局不乘 alpha、不累加图层。可见性/材质发现使用租约原值，避免 UIView.alpha 映射 layer.opacity 后误判隐藏。复用、宿主更换或目标离开作用域释放旧租约；不会全局 hook UIView/CALayer 或清理其他插件属性。
- LockScreen/Desktop：仅在现有 CSCoverSheetView/SBHomeScreenView 当前可见目标内部识别本地 Wallpaper 绘制叶层/纯背景视图，独立叶层 detach、UIView backing 背景支路关闭绘制。绝不借用、隐藏、移动 _SBWallpaperSecureWindow，也不移除 scene/remote/shared/thumbnail/snapshot 或未知混合支路。若真实原壁纸来自独立共享安全窗口且不能分离，保留原层，诊断 original target=... guarded-no-op:no-local-pure-wallpaper; secure-window-shared-or-unidentified。此测试版不承诺所有 iOS 私有壁纸宿主都已替换。
- 桌面租约只存在于同一桌面宿主绘制范围；真实 App 前台、锁定、熄屏或宿主不可见时释放，回到桌面重新取得，不能影响锁屏共用壁纸。NC 完全遮盖/桌面菜单仅暂停解码时保持本地租约及最后帧。消息/锁屏在屏幕 blank 时保留已绑定且仍附着在同一宿主的租约，暂停帧；宿主移除、隐藏或复用后按作用域回收。系统将叶层移动到新父层时不抢回；离线叶层在旧父层仍存活时按邻层/索引恢复。
- 系统在租约期间更新 mask、contents、corner 等属性不被改写；离线层仍为原对象。支路 suppression 在合并更新时观察新的非零 model opacity，并保存为恢复值。没有全局 setter hook，无法区分系统刻意写 0 与插件已写 0，也不能保证未取消的系统 opacity animation 的 presentation 值即时为零；以最近观察的非零 model 基线恢复。这是测试版兼容边界，需要真机验证。
- 保留 0.57 自有视频 clipping/Dock mask、按路径共享 VideoOutput/Reader、真正最后帧、screen/App/NC 暂停、全部设置/缩略图/重命名/删除/应用提示/Filza/压缩临时源清理及默认关闭的限频诊断；没有音频会话、preroll、亮屏、Live Activity 或阴影控制恢复。设置源码和用户数据目录不变。
- macOS CI 新增真实 QuartzCore CALayer + UIKit view doubles 测试：五目标启用/关闭/离域、cold/error/alpha0 不回退、100 次布局、非 1 基线与系统更新、同一对象/父层/邻序恢复、最后 owner、弱父层、材质锚点发现与混合文字拒绝、shared/remote/thumbnail 安全跳过。源码摘要保护九个 .57 启动/快照/共享源/Dock 函数，继续执行 .55 once 复现、.56 launch gate、.57 mask 与保帧回归。CI 与 doubles 不替代 iOS 真机冷启动、视觉层级、交互及 CPU/内存测试。

## 0.0.57
- 修复 0.56 日志中长按期间 `dockFallback=1` 导致 `draw=0 decode=0` 的整块桌面隐藏：低层级 Dock 只触发局部兼容测量，桌面保持绘制；停留桌面的 Context Menu/Dock overlay 继续消费动态帧。真实 App 前台、NC 完全遮盖、锁屏/熄屏仍优先暂停或释放，保留原有缓存帧、App 返回和 NC 回露恢复。
- 不再把 `SBFloatingDockWindow.bounds` 当裁剪区域。运行时仅有界读取同屏、可见且低于桌面的 Dock 窗口内实际 `SBFloatingDockView`/`SBFloatingDockPlatterView` 或已经加载的具体 Dock 内容控制器宿主；读取一致 presentation 坐标、真实单轮廓 shape mask 或圆形圆角半径。拒绝全屏/超过半屏、离屏、错误屏幕、未知轮廓及不稳定窗口坐标桥；实测阴影仅扩展最多 6pt。
- 仅桌面自有 CALayer 使用一个可复用的 CAShapeLayer even-odd 遮罩，在实际 Dock 区域露出系统背景，其他区域保持视频。无法可靠识别容器/轮廓时不造矩形、不隐藏视频，诊断为 `no-safe-dock-region`，表示该布局的 Dock 兼容尚未完成。用户日志没有 Dock 子节点，不能据此宣称已知真实矩形；连续圆角且没有可读取 shape mask 的布局同样保守保留视频。
- 具体 Dock window/view/platter 原回调只观察并请求 0.56 已有主线程合并更新；启动 gate、非递归保护、notify 锁状态查询保持。没有全局 UIView hook，没有系统窗口 level/frame/transform/hidden/alpha 修改，没有重挂 Dock/壁纸/系统图层。
- 诊断默认关闭，原限频/组数/轮转不变；桌面记录 draw/decode/mask/maskrect/sourcecount 和安全区域原因。新增生产几何函数真实 CALayer 测试，覆盖全屏/未知/图标/离屏/错屏/低透明度拒绝、presentation 桥、真实圆角路径、500 次重复布局与缓存内容。策略测试复现实际 296431.243/296433.339/296435.345 时间序列并验证视频持续可见和动态解码。Foundation/QuartzCore doubles 和编译不替代 iOS/iPadDock 真机验证。
- 保留 0.56 所有五目标设置、素材库/缩略图/重命名/删除、相册重新压缩/临时原素材清理、应用提示、Filza、共享源、透明度与静态最后帧；没有 Live Activity、音频会话、preroll/亮屏控制或恢复已删除的阴影控件。

## 0.0.56
- 修复 0.0.55 启动初始化重入：壁纸窗口初始化触发插件同步桌面策略，策略创建 `SBLockScreenManager`，管理器又请求正在 `dispatch_once` 中创建的壁纸控制器，造成 libdispatch recursive-lock SIGTRAP；不是视频素材错误。已核对 0.0.55 实际包 arm64e UUID 与用户 ips 一致。
- 全部早期窗口/宿主 layout、didMove、hidden/alpha、Dock level 及控制器进度回调只登记弱宿主并请求合并更新。集合先初始化再注册通知和 Logos hooks；只有 `UIApplicationDidFinishLaunchingNotification` 后的主队列任务可以开启启动门，策略在随后主队列任务执行。晚注入采用既有 public application/scene active 或 background 状态证据，inactive 场景不能提前开门；真实 didBecomeActive 事件也可补足晚注入证据。
- 移除创建型锁屏管理器查询，锁状态读取既有 `com.apple.springboard.lockstate` notify state，未知状态保守暂停。桌面关闭或启动未就绪时不捕获系统桌面状态；合并/执行标志防止同步嵌套布局再入，没有任意延迟或异常掩盖。
- 保留 0.0.55 全部设置、五目标、素材管理与临时导入源清理、共享渲染、静音/熄屏策略、诊断默认关闭、已移除的阴影控制结果。桌面部分露出播放、完全遮盖暂停留帧、App 返回恢复及 Dock 低层级仅隐藏插件自有层的策略函数未改；宿主刷新改为下一主队列任务。
- 新增 Foundation doubles 复现旧版锁屏管理器→壁纸 once 递归，并执行实际生产 launch/coalescer/host/desktop-update 函数，断言启动前零策略/零单例创建、启动事件后下一任务合并、嵌套回调不递归、禁用桌面零快照和晚注入状态证据。旧桌面日志时序、NC 遮盖、留帧/时间和 Dock 属性回归继续执行。Actions 编译与 doubles 不能替代 iOS 冷启动、锁定/解锁、NC 和 iPadDock 真机验收。

## 0.0.55
- 对照用户确认可用的 0.53 桌面实现，保留原有 HomeScreen CALayer、按路径共享的视频源及首选 `_accessibilityFrontMostApplication` 查询；真实前台 bundle ID 优先，私有查询均检查对象返回 ABI。0.54 中显示链停用和暂停状态无条件释放桌面源的路径被移除，显示链只读已提交消费状态，不再在同一 tick 重复查询前台。
- 通知中心下滑期间桌面仍有露出则播放，实际 `CSCoverSheetView.slideableContentView/contentView` 的模型/呈现屏幕矩形均完全覆盖桌面后暂停。全屏透明 UIWindow 不作为覆盖证据。保留最后帧与暂停源，重新露出立即恢复；未知转场仅 150ms 防抖，key HomeScreenWindow 且无应用/覆盖/锁定可恢复，不能把未知 UI 对象误当真实应用。
- 真实应用前台立即停止桌面消费，持续离屏 1.25 秒后释放未被其他可见消费者使用的媒体链。锁定/熄屏沿用隐藏与释放策略；临时暂停的 AVPlayer 保留自身时间，不额外精确 seek。冷重建仍复用原有按路径/修订缓存。
- iPadDock 把可见同屏相交的 `SBFloatingDockWindow` 从 25 降到低于 HomeScreenWindow（日志 -3 对 -2）时，只临时隐藏插件自有桌面背景，保留图像与时间，让原壁纸/系统模糊露出。层级恢复后显示回来。这是暂时回退，低层级期间不保证继续显示桌面视频；不改 Dock/window level、alpha、frame、transform、hidden，不创建窗口，不接管锁屏共用壁纸。Dock 的 setWindowLevel 原回调仅调用一次，之后只观察。
- 具体 HomeScreen 控制器出现/消失及 CoverSheet 进度回调触发更新，沿用 0.35 秒兜底计时器。诊断默认关闭，30 组/至少 2 秒/16 窗口限制不变；增加 Dock 优先遍历（最多 12 子视图，每节点最多 4 图层）、opacity/z/frame 和低层级回退原因，原日志轮转限制不变。
- 测试复现实际 0.54 的 source4..7 时间点与 Dock25→-3：转场不反复建源、旧帧与时间保留、通知中心部分/全遮挡/回露、未知 key-home 恢复、真实 App 立即暂停与有界释放、熄屏。Foundation doubles 执行实际桌面更新函数并断言 Dock 属性不变；这些测试和双架构编译不能代替 iOS/iPadDock 真机验收。
- 保留 0.54 的阴影设置移除结果，以及消息/锁屏/桌面/选项/清除完整设置、素材库缩略图/重命名/删除、相册重压缩/临时原素材清理/原素材清空、Filza、透明度、静音与不阻止熄屏策略。

## 0.0.54
- 移除通知堆叠阴影开关、滑块、专用状态/helper/hook 及专用测试；保留原有视频透明度语义。
- 桌面自有层的显示与解码分开：下拉通知中心及长按菜单过程中保留最后真实帧，完整遮挡后暂停桌面解码，收起后恢复。未知前台对象或打开应用时不继续桌面解码。锁定、熄屏或失去合法桌面宿主时隐藏自有层；关闭功能或更换素材时仅移除自有层。
- 通知中心完整遮挡需要 CoverSheet 实际宿主的 model 与 presentation 屏幕矩形都覆盖桌面；不能仅凭一个可见的全屏窗口提前判断动画完成。
- 桌面层只在未挂载时插入；布局和长按过渡不反复 remove/reinsert。浮动 Dock 窗口/控制器属于 SpringBoard 的 UI，不能当作已打开的应用；真实前台应用标识优先。未修改系统 Dock/图标内容布局，不重置其他插件的 alpha、hidden、frame 或 transform。
- 消息、选项、清除和锁屏的共享媒体链保留；桌面与锁屏独立素材选择，素材库缩略图、重命名、删除、当前标记、应用提示、相册导入重新压缩与临时原素材清理、Filza 路径入口及诊断默认关闭均保留。
- 诊断打开后，最多 30 组、间隔至少 2 秒采样，每组最多 16 个窗口与 32 个视图节点，记录窗口类/level/hidden/alpha/key 和 backdrop 父层状态，不采集应用文本。日志仍位于 `/var/mobile/LockMessageVideo/shared-render.log`，沿用 64 KiB 轮转和总记录上限。
- `tests/desktop-consumer.c` 执行实际共享策略的 2048 种状态及通知中心过渡几何、浮动 Dock、真实应用和未知前台判定；`tests/desktop-runtime.py` 在 macOS 执行实际桌面更新/解绑函数的 Foundation doubles，验证暂停保留帧和层级、锁定隐藏、关闭仅移除自有层及无关视图不变。编译与 doubles 不能替代 iPadDock 真机兼容验收。

覆盖安装相同包 ID `com.minis.lockmessagevideo`，保持 rootless 安装路径；不删除 `/var/mobile/LockMessageVideo` 或现有偏好。安装后重新载入 SpringBoard。若 iPadDock 自己在长按时隐藏 Dock，本补丁不强制改写系统窗口状态，需要开启诊断采样并结合真机层级/ips 确认。


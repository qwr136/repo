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

透明度开关关闭时完全透明；开启时滑块值按 0.0 到 1.0 直接作为视频背景 alpha。播放仅使用视频轨道，静音且不激活音频会话，不影响音乐或系统音频。

## 编译
### 本地
```sh
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
```

### GitHub Actions
把整个工程上传到 GitHub 仓库，Actions 会在 `packages/` 产出 deb 并上传 artifact。

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


# 锁屏消息视频

## 0.0.120：桌面视频不再闪（前台探针抖动）＋ 便捷访问改在触摸源头拦截

精确基线119 `9925d82`。真机日志（0.0.119，pid=7792）：

```
12404.573 desktop-video visible=0 home=1 foreground=-1 env=0 teardown=12 hostHidden=1
12405.134 desktop-video visible=1 home=1 foreground=1  env=1 teardown=12 hostHidden=0
12406.419 desktop-video visible=0 home=1 foreground=-1 env=0 teardown=13
12407.969 desktop-video visible=1 home=1 foreground=1  env=1 teardown=13
```

### ① 桌面视频闪一下 / 黑一下 / 变回原壁纸

`home=1`（Home 视图控制器当前可见）全程稳定，但 `foreground` 在 1 与 -1 之间来回跳（窗口列表里出现 `_LNSceneTouchVisualizerWindow`，说明当时在**录屏**——录屏会让 `_frontmostApplication` 指向录制进程），于是 `env` 跟着 0/1 跳，桌面视频被反复隐藏/显示，视觉上就是闪一下、黑一下、落回原壁纸。

门控里 `foreground>=0 &&` 与 `(foreground==1 || homeConfirmed)` 是重复的，却把**旁证**变成了否决权。现在删掉它：**Home 视图可见是"就在桌面上"的直接证据，前台探针不得否决它**。App 真到前台时有其自己的窗口遮住画面，冻结路径仍保留最后一帧，行为与既有设计一致。

### ② 「屏蔽桌面便捷访问」改在触摸源头拦截

0.0.119 的日志显示扩宽到**完整窗口集合（38 个，含系统手势窗与触摸可视化窗）**后依然是 `recognizer=0`：SpringBoard 不通过任何窗口树或 `edges` 值暴露这个手势，`enabled` 这条路在 SpringBoard 上走不通。

改为在**触摸源头**拦截：底部边缘手势无论由哪个类实现，**都起始于屏幕底部条带**——这一步纯几何判定，不需要私有类名、不猜 `edges`。桌面规则成立时把这些触摸**丢弃**（不交给手势状态机），便捷访问就不会启动。

- 作用域极窄：只在**底部条带内**、只在**桌面规则成立时**、且只在 **SpringBoard**（filter plist 只注入 `com.apple.springboard` 一个 bundle，有测试锁定）。左/右边缘手势（返回、控制中心）与底部上滑回主屏（另一套识别器）不受影响。
- 关闭开关时发布的判定为 NO → 一个触摸都不会被吞，行为与之前完全一致。
- 诊断：`reachability touch-guard=installed ... bottom-strip=20pt`；每次吞掉触摸限流 1 秒记一条 `reachability swallow count=N y=...`，可直接确认拦截是否生效。

## 0.0.119：修好「屏蔽桌面便捷访问」（0.0.118 装上是哑的）

精确基线118 `f4882a7`。真机日志一行定性：

```
10696.365 reachability block=1 enabled=1 recognizer=0 nc=0 cc=0
```

`block=1` 说明判定正确（桌面、已解锁、SpringBoard 前台），`enabled=1` 说明开关开着 —— 但 **`recognizer=0`：那个下边缘手势根本没找到**，于是什么都不做，降半屏照旧触发。原因有两层：

- **窗口集合不全**：只遍历了 `UIWindowScene.windows`。SpringBoard 的便捷访问手势挂在**系统手势窗**（`_UISystemGestureWindow`）上，而这扇窗由 **application** 持有、不属于任何 window scene —— 之前的遍历永远到不了它。
- **类判定太窄**：只认 `UIScreenEdgePanGestureRecognizer` 这一个类，私有子类若未继承它就漏掉。

现在：窗口集合 = 各场景窗口 ∪ application 的完整窗口列表（`-windows` 已弃用，通过 `objc_msgSend` 动态调用，不触发弃用警告，本仓库警告即错误）；手势匹配改为**任何暴露 `edges` 且含下边缘位**的手势，其中真正的 `UIScreenEdgePanGestureRecognizer` 优先、私有子类作兜底；递归深度 8 → 32。关闭开关时的恢复走**同一套加宽搜索**，避免兜底手势被永久留在禁用状态。

诊断补齐，一次日志即可收口：

- 找不到时（限流 5 秒一次）输出 `reachability recognizer=missing windows=<数量> <窗口类名前6>`，直接看出可达的窗口集合。
- 切换时输出 `reachability block=%d enabled=%d recognizer=%d nc=%d cc=%d target=<被操作的手势类名> edges=<位>`，证明动的是哪一个手势、没误伤其它边缘手势。

判定规则、设置行位置与键（`BlockDesktopReachability`，默认关）、锁屏与控制中心不屏蔽，全部不变。浮球、视频通道一概未动。

## 0.0.118：录屏不再让球消失（极端层级窗口）＋新增「屏蔽桌面便捷访问」

精确基线117 `d9a98e5`。真机日志（pid=6034）直接给出两个原因：

- `easter-window blocked class=_LNSceneTouchVisualizerWindow level=1.79e308`：录屏时 iOS 会显示触摸可视化窗口，其 `windowLevel` 是 **DBL_MAX**。旧代码要求每个窗口都有可表示的 “+1” 余量，否则 fail-closed 判为拦截 —— 于是**整个录屏期间浮球被隐藏**。现在不可表示层级的窗口既不当拦截、也不参与层级竞争（最终层级仍按有界计算收敛），只有真正的安全弹窗才会隐藏浮球。
- 同一时刻 `fg=-1 nc=0 cc=0 home=0 captured=1`：录屏时前台探测报录制进程（-1）且该窗口持有 key，桌面失去宿主。现在**录屏进行中**（`UIScreen.isCaptured`）只要 Home 窗口已曝光就作为合法宿主，球在录制里可见。
- 「不显示的地方秒消失」保持不变：判定不成立立即隐藏（无保活、无缓冲期），锁屏/控制中心按原策略处理。

新增开关（放在「消息、选项、清除视频透明度」下面）：**屏蔽桌面便捷访问**（`BlockDesktopReachability`，默认关）。
- 只在**桌面**屏蔽 iOS 便捷访问（降半屏）：开启后桌面下拉不再触发降半屏，桌面视频背景不会被顶下去。
- **锁屏与控制中心不屏蔽**（判定规则：开关开 且 屏幕已知未熄 且 锁屏状态已知未锁 且 SpringBoard 在前台 且 无 CoverSheet/控制中心界面）。
- 实现只用**公有 API**：在 SpringBoard 各窗口（含子视图）里找到 `edges` 含下边缘的 `UIScreenEdgePanGestureRecognizer`（SpringBoard 里唯一的下边缘屏幕手势），按判定切换其 `enabled`；关闭开关或判定不成立时**立即恢复**，绝不残留禁用状态。不靠猜私有类名，猜错最多是该功能无效，不会永久禁用其它手势。诊断会记录 `reachability block=… recognizer=found|missing`。

新增回归 `tests/desktop-reachability.py`：纯规则真值表（桌面拦截；锁屏/控制中心/熄屏/未锁未知/前台为 App 一律不拦截）、设置行位置与键默认值、下边缘限定、关闭即恢复、无私有符号猜测。CI 非原生部分不替代真机录屏与降半屏实测。

## 0.0.117：按素材共享播放源、浮球尺寸/预览、立即消失、改名、横屏跟随

精确基线116 `df49ffc`。本轮六项，均按用户逐条要求；其它通道不动。

- **播放源按素材共享**：源注册键由「目标+素材」改为**素材本身**。消息/选项/清除只要选择同一个视频就共用一条链（一个 player、一个时钟、一个 output、一份保留帧），选择不同视频时才各自独立（仍是每类最多一条）。源退休改为按“是否还有任一启用类别选中该素材”判断，卡片帧分发本来就按源身份匹配，因此三类同时显示同一素材时一个解码器驱动三张卡片。相关原生测试已按新契约重写：同素材断言“只有一条链”，独立性覆盖改用三个不同素材。
- **悬浮球尺寸最小 12pt**：滑块下限与取值下界从 32 改为 12（`LMVEasterBoundedSize` 同步 `fmax(12, fmin(128, …))`），上限 128 与默认 64 不变。
- **预览图跟随尺寸**：小彩蛋图片/GIF 页的预览原本固定 140×140，现在按**真实悬浮球尺寸**绘制，拖动大小滑块时实时同步（只改两个约束的常量，不重载单元格，避免拖动被打断）。
- **不在可显示界面立即消失**：取消 0.0.116 的 2 秒保活与录屏例外，宿主/场景判定一旦不成立立即隐藏。0.0.116 的瞬断回归改为在判定本身上修：Home 宿主接受“窗口仍是 key 且已曝光”作为证据（前台探测不可靠、被 NC/录屏指示窗占用时不再误判），真正的 App 前台会持有 key 窗口，所以不会把球显示在 App 之上。
- **改名**：设置页首行改为「启用全局开关」（键 `GlobalEnabled`、默认开、作用范围不变）。
- **横屏跟随**：`LMVEasterRoot`（悬浮窗根控制器，开面板时会成为 key window，方向由它决定）、`LMVEasterPanel`、小彩蛋图片页、素材选择器均声明 `AllButUpsideDown`。此前它们只答竖屏，整个场景（含 SpringBoard）被判为竖屏，关闭方向锁后横屏时悬浮球位置不变；现在窗口随场景旋转、根视图 bounds 变化触发 layout，归一化位置按新的拖动区域重算，球跟着走。
- 诊断：浮球宿主缺失记录附带 `fg/nc/cc/home/captured` 字段（0.0.116 起 `easter-window` 记录不占日志配额）。

新增/更新回归：源按素材共享与不同素材独立、退休按真实需求、尺寸下限 12 与预览约束跟随、立即消失（无 `host-missing-keep`/`captured-keep`）、Home 宿主 key 判定、四个控制器的方向声明、设置页首行名称。CI 非原生部分不替代真机录屏/横屏实测。

## 0.0.116：宿主探测瞬断不再让浮球消失（真机日志定位）

精确基线115 `88194d8`。只动浮球这条线，其余不动。

- 真机依据（115 日志，pid=5367）：6294.423 `easter-window home-nc-cc host=SBCoverSheetWindow level=10000012`（球挂在 NC 窗口、层级在录屏窗 10000011 之上），随后 6299.135 `easter-window home-nc-cc:not-visible-or-locked` —— 球在 NC 收起、回到桌面那一瞬被隐藏。原因是**宿主探测（nc/cc/home 三路）在场景切换时同时返回空**，旧逻辑一帧就隐藏；日志里没有 `blocked`，说明与安全拦截无关（113/114 的按类名豁免方向不对）。
- 修复：宿主为空时不再立刻隐藏。①录屏进行中（`UIScreen.isCaptured`）永不因宿主缺失隐藏；②否则只要浮球**当前呈现**且宿主缺失**不足 2 秒**，保持原样并继续探测，记录 `host-missing-keep fg=… nc=… cc=… home=… captured=… for=…`；③宿主持续缺失超过 2 秒才按原逻辑隐藏（日志仍为 `home-nc-cc:not-visible-or-locked`，并附上 `fg/nc/cc/home/captured/for` 字段，下一次可直接判定是哪一路探测为空）。
- 诊断字段：策略分支的 `blocked …`/`not-visible-or-locked` 也带同一组字段；`easter-window` 记录在 115 起已不计入 1200 条配额。
- 未录屏、宿主正常时行为与 115 一致；关闭总开关/小彩蛋仍立即隐藏。

新增回归：宿主瞬断保活（`captured || (presented && missing<2.0)`）、`hostMissingSince` 复位、诊断字段与策略分支 captured-keep 的源码契约。CI 非原生部分不替代真机录屏实测。

## 0.0.115：录屏期间浮球保活 + 浮球日志不再被挤掉

精确基线114 `77ee7d4`。只动浮球这条线，其余（三类卡片、总开关、整页背景、CC/桌面/长按菜单、声音、排序、720、素材库）不动。

- 真机排查依据：0.0.114 的 shared-render.log 里**一条 `easter-window` 都没有**，说明两件事同时存在 —— ①浮球日志被高频通道挤掉了，②有几条隐藏路径根本不写日志。
- 日志保留：`LMVDiagnostic` 每轮 1200 条上限会把浮球的记录丢光（卡片/锁屏通道每秒 10～150 条）。现在 `easter-window` 开头的记录**不计入配额**，任何一次浮球判定都必然落盘。
- 不再静默隐藏：`recordScreenBlank`（熄屏/blank）现在先记录 `hide:screen-blank` 再隐藏；窗口场景切换记录 `hide:window-scene`。此前这两条都是无声消失，正是“球没了但日志什么都没有”的来源。
- 录屏期间保活（用户要求）：录屏进行中（`UIScreen.isCaptured`）且浮球**已经呈现**时，宿主判定或安全判定即使误判也不再隐藏，只记录 `captured-keep host-missing` / `captured-keep blocked class=… ` / `captured-keep not-visible-or-locked`，浮球保持原样。未录屏时判定与 114 完全一致；关闭总开关/关闭小彩蛋仍然立即隐藏。

新增回归：`recordScreenBlank` 必须先记录原因再隐藏（原生断言 reason=`hide:screen-blank`）、录屏保活三分支与场景切换上报的源码契约、`easter-window` 优先级配额。CI 非原生部分不替代真机录屏实测。

## 0.0.114：设置页顶部总开关

精确基线113 `e24d04d`。113 已被真机日志确认：`card-pipeline` 变为 `attached=1 ownerModel=1 surfaceVisible=1 active=1 source=1 requested=1`，`published` 持续增长，`card-exposure ... playing=1`，三类卡片通道恢复正常；本轮只加总开关，其它逻辑不动。

- 设置页最顶部新增「总开关」分组与一行「启用全部视频背景与悬浮球」（`GlobalEnabled`）。
- 生效范围：五个目标（消息/选项/清除/锁屏/桌面）、控制中心、桌面长按菜单，以及悬浮球（小彩蛋）。关闭后各通道与悬浮球立即停止，各单项开关的取值保留，重新打开即恢复原配置。
- 缺省策略：prefs 里**没有这个键时按“启用”处理**（tweak 侧 `LMVGlobalEnabled()` 与设置页 `default=YES` 一致），所以升级到本版不会改变任何已有配置；只有显式写入 `false` 才会整体停用。
- 实现点：`Tweak.xm` 的 `LMVGlobalEnabled()` 为唯一判定源，卡片通道在 `LMVLoadPreferences` 里与单项开关取与，锁屏/控制中心/桌面（两处）/长按菜单四处读取点同样取与，小彩蛋在 `apply` 里把总开关并入 `EasterEggEnabled`。设置页沿用既有 `setEnabled:`/`enabled:` 读写与 `preferencesChanged` 刷新链，关闭后无需注销即可立刻生效。

原生/静态回归新增：设置页首行必须是总开关且 `default=YES`、`GlobalEnabled` 行必须排在第一个目标分组之前、四个通道源码都必须取与总开关（桌面两处）、小彩蛋必须并入总开关；设置页顺序与属性表哈希同步更新。CI 的非原生部分不替代真机 UI 实测。

## 0.0.113：卡片附着契约（真机日志定位）、录屏期间浮球保活

精确基线112 `8f6f4ff`，只继续修这两处，其余不动。

- 三类卡片不播放（真机112日志定位）：`card-pipeline` 同一行出现 `ownerCAWindow=1`（图层链确实到达 window.layer）而 `attached=0 ownerModel=0 ownerShown=0`，且 overlay 尺寸/透明度正常（surfaceSize=295.3x108.7 surfaceHidden=0 surfaceOpacity=1.000）。说明失败在**附着判定**：旧 `LMVCardAttached` 要求一个 32 层以内的 superview 遍历必须终止在 window 对象上、且每层都报告同一个 window —— 真机 CoverSheet 内容经 portal/scene host 桥接，这个遍历不成立（中间层没有 window，或层数超预算），于是 owner/anchor/host/overlay 全部被判未附着，卡片永远不成为消费方。现在以 UIKit 自己的答案为准：`view.window` 非空时必须等于目标窗口；`view.window` 为空时只认“该 view 的 layer 确实在目标窗口的 layer 树内”这一渲染树证据。搬到别的窗口的卡片仍被拒绝，跨窗保护不变。112 的私有中间层不否决判定保留。
- 录屏时悬浮球被隐藏（用户复报）：112 只按类名豁免采集指示面，仍可能被“隐私措辞”命中。现在录屏进行中（`UIScreen.isCaptured`）**必须**有结构性证据才允许拦下浮球——安全命名的窗口/控制器类、可见的前景控件（UIControl）、或 UIAlertView/UIActionSheet/UIAlertController；仅一个视图类名撞上隐私词不再隐藏浮球。未录屏时原判定完全不变。采集指示面本身继续只参与层级竞争（球仍在其之上）。

原生回归新增：桥接层 `-window` 返回 nil 时按渲染树证据接受、真正搬到其它窗口仍拒绝（卡片附着）；录屏中纯隐私词视图不拦截、录屏中安全命名窗口带前景控件仍拦截（浮球优先级）。CI native/doubles 不等于真机合成与录屏实测。

## 0.0.112：三类卡片准入修正、录屏指示不再隐藏浮球

精确基线111 `28f840e`，独立112分支，只改这两处，其余（整页背景、CC/桌面/长按菜单、声音音量、设置顺序、720、素材库/导入、录制浮球层级）一律不动。

- 通知/选项/清除不播放（用户报111）：卡片准入按“UIView 契约 + 几何”判定，不再让**非视图直连的私有 CA 层**（UIKit 自己插入的材质/portal/backdrop 中间层）用自身的 hidden/opacity/mask/masksToBounds 否决整棵子树。111 把这层当成“受保护渲染子树”，真机上每个 NC 卡片都会在其中一段被判为不可见，于是从未成为消费方（日志里只有 discovery visible=0、完全没有 card-exposure/sourcephase/firstpublished），三类自然一个都不播。现在：视图直连层（UIView.hidden/alpha/clipsToBounds）与真实裁剪几何仍然是否决项，离屏/撤回/异窗/熄屏照旧暂停；呈现快照读不到时（含提交竞态）改为回落到契约判定，而不是直接判不可见。私有中间层的裁剪几何仍然参与求交。
- 录屏时悬浮球被隐藏（用户报）：系统录屏/隐私指示窗的类名带 Privacy/Recording，被安全审计当成密码/权限弹窗拦下（apply 报 blocked class=…），整个录屏期间不显示。现在录屏/采集指示面（Recording/ScreenCapture/CaptureIndicator/PrivacyIndicator/Broadcast/Replay/Mirroring，以及录屏进行中且类名含 Indicator/Capture 的窗口）不再充当 blocker，只参与层级竞争，球依旧在其之上；真正的密码、认证、权限、隐私授权与 UIAlertController 仍照旧拦下，其他窗口判定不变。

原生回归新增：私有中间层 hidden/opacity 不再否决而视图直连祖先仍否决（卡片准入），录屏指示窗不再拦截而隐私措辞但非采集类的提示仍然拦截（浮球优先级）。CI 的 native/doubles 不等于真机合成与录屏实测；请装 112 后注销一次，同次录屏验证下拉三类立即播放、录屏期间球常驻。

## 0.0.111：三类可见消费兼容、原系统背景保留、独立开关与录屏浮球

精确基线110 `c4f57bc4215e2bb29a4f184861bfbb2c2690cc52`，94files逐blob核验。用户最新要求优先三类视频真正播放；其它已正常背景/声音/桌面/设置/720等冻结。

同次110日志 `session=1 pid=30536` 97538.347～97561.066，共334事件：三类enabled/selected/assetready=1，8条同窗NC discovery scope=1但visible=0；两次Options/Clear也发现candidate。无card-exposure/sourcephase/firstpublished，提示应先查绑定准入和显示链调度，尚不能据此判定decoder坏或唯一根因。原displaylink/original/loadsource事件会去重，bind日志先检查后赋值从不输出，111修正这些诊断盲区，任何绑定/缺父时也可限流记录门槛，不依赖tick已启动。

- 仅三类可见判定：UIView.window+实时owner/anchor/host归属严格保留，放松“所有系统backing必须直连window.layer”的不受UIKit契约保证的条件。仅模型树通过内部render/portal根桥接而没有window.layer祖先时，使用公开UIView同窗坐标、实际hidden/alpha/clips校验；完整呈现快照若明确撤回/hidden/clip仍拒绝，不用model强行复活。离屏卡片初次进入真实窗口不再当作旧窗口转移；新附着无animationKeys仍有一次有界.6s曝光观察，但未实际可见前不启动解码。真实foreign/detach/blank仍停止。
- 按用户明确新政策：消息、选项、清除开启时只叠加自己的video overlay，不隐藏系统材质、不置opacity0、不detach原绘制层；升级/绑定维护会恢复旧自有租约。关闭Message只移除Message叠加层和停止Message源；Options/Clear各自同理，不影响其它类别或整页NC，原系统背景一直保留。文本/按钮原层不改。
- VideoOpacityEnabled控制是否使用自定义alpha：关闭时自有视频alpha1且继续播放，开启时仅调整三个视频overlay alpha；真正alpha0不消费不可见视频，原系统背景保留。修掉99已有“透明度调节开关关闭却兼任三类播放总开关”的错误语义。
- 录屏浮球：监听UIScreenCapturedDidChangeNotification开始/结束即重查真实层级；double CGFloat允许高于24位float人为上限的实际录屏窗口+1，仍有可表示数值边界、不竞赛自身、不改其它窗。屏幕blank排队回调读取最新notify值，拒过时blank误隐藏。普通录屏指示不阻挡，密码/权限/真实系统UIAlert仍保护；录屏是否实际触发旧上限尚未知，当前日志只有正常NC球体显示和收回，不声称已设备验证。

同类卡片共享一个类别播放器，三类各自独立；原AVPlayer/reader/cache转换继续复用110成功native代码，不再盲换decoder。新增回归验证portal模型根、无动画冷曝光、系统背景全部属性/层次稳定、关闭一类其它仍playing、透明度调节关闭仍active、录屏高窗层级和陈旧blank保护。CI/native并非设备合成/录屏实测；交付包需要同次111真机检验。以下历史说明保留。

## 0.0.110：回查三类停播、独立可见声音、手势弹窗优先级与桌面保帧

基线正式109 `4b0589cbd8f6fb6a78dcdc7b9501b0246a120767`，91files与交付源码ZIP逐blob核验。保留108已真机成功的LMVLockVideo.h通知整页几何，CC/Menu视频布局不变。独立110分支，不改main/109。

### 旧版三类静止的源码原因（不等于真机唯一根因）
- 079/082认可attached NCNotification祖先，107～109收窄为CoverSheet/NotificationCenter而删掉NC owner证据；真实NCNotificationListCell若挂在其它普通UIWindow，scope=0导致active/source不启动。110恢复精确NCNotificationListCell类型身份，不把任意App窗口变成通知中心，原Secure/CC排除和samewindow归属保留。回归现在执行生产scope，不再用模拟CoverSheet-window谓词替代。
- 呈现曝光混用了model UIView clipsToBounds；model已裁剪而显示快照未裁剪时可能误判看不见。110呈现分支只用本树masksToBounds；window model hidden不再凭UIView animationKeys拒绝完整真实曝光，实际samplehidden/clip/opacity/撤回照旧拒绝。不盲删modelLayer归属校验。
- 缓存有效PTS+item失败/Unknown/seek长期未完成，restoreOnStart/restoringTime旧门槛会同时挡正常启动和reader fallback。110已请求的独立source使用有界no-progress恢复，失败直接恢复、不ready/seek超时可转既有reader，保lastframe/time、代际拒旧完成。并非整套decoder重写，三类仍独立，同类卡片复用1源。无真机109日志，不能认定三个原因都在用户设备同时触发。

### 用户新增声音音量（不是画面大小）
主设置/悬浮窗口每种Message/Options/Clear/LockScreen/Desktop/HomeMenu及CC深/浅素材下增加独立声音开关和0～100%音量。默认OFF、音量50%，normalized keys TargetSoundEnabled/TargetVolume。视频视觉composition仍video-only，独立audio-only源按真实可见消费，隐藏/frozen/熄屏/关闭暂停。Ambient+MixWithOthers，不duck或独占，不接管外部音乐remote command，不在pause时setActive:NO。音频无轨道的素材不会凭空发声。iOS与其它音乐App实际混音/权限仍需真机验收，macOS只可验证策略和独立音轨生命周期。

### 浮球与快速桌面转场
109最高level+1只对透明/小HUD生效，普通第三方手势弹窗只要有controls/实质绘制仍被当成block而主动hide。110移除这项generic highlevel blocker，使球也在这些普通弹窗之上；明确密码/认证/隐私/授权/权限和UIAlertController/UIActionSheet安全模态仍隐藏，不猜鱿鱼class绕过安全名。实际鱿鱼未提供classdump/版本，不能宣称真机兼容已通过。
桌面已拥有Home-only宿主通过原子holdCurrentFrame暂停保帧，不先setVisible:NO使render隐藏再setFrozen:YES；临时零尺寸不清自有layerframe/租约，exactparent/window/原content归属仍严格，真正off/blank/lock/detach/replace/error恢复。快速进入退出App不新建player，稳定layout去重保持。

新增原生回归覆盖scope/两个树裁剪不同步/缓存超时、八类audio-only可见pause和默认静音、250次快速转场hiddenwrite/lease测量及UI路由。编译、native/doubles不能代替用户设备合成/后台音乐/鱿鱼/CPU验证。安装后注销一次，保留设置素材。以下历史发布说明保留。

## 0.0.109：消息/选项/清除各类独立播放器、可见即播与悬浮球优先级

准确基线108 `d85a89672e48104be84ab4553e2f3ceb7a058173`，90文件与成功交付ZIP逐blob核验。用户已真机验收通知中心整页下拉背景成功，因此冻结LMVLockVideo.h/Playback和Desktop/CC/HomeMenu，不动已成功路径。

- Message、Options、Clear各自按target+path注册独立AVPlayer/VideoOutput/reader/时钟和最后帧；同类别全部卡片复用这一源，即使三者选择同一素材也不共享播放器。底层immutable素材准备仍按文件缓存，避免重复素材验证。旧类别关闭或改选择会退休其旧source，卡片数不增加decoder数量；每类最多当前一条。
- 已验证素材或磁盘缓存完成时预建各选中类别的暂停源，卡片出现不在手势路径重新构建播放器。布局后的O(existingbindings)同步协调真实自有surface曝光，曝光就请求rate1播放；同类只要还有一张卡曝光就保持，最后一张消失则暂停保留当前帧/时间，再出现warm续播不强制seek。没有帧时仍可显示预览，但不把静态预览当成视频已播放；完全冷启动/系统解码尚未ready不能承诺绝对零等待。
- 原材质是被替换绘制，不再要求它自身hidden/alpha同时可见才允许自有sibling视频播放。附着owner/anchor/host身份仍严格检查。已有真实presentation快照时以该surface实际呈现曝光为准，model位于屏内但视频正在撤回的状态不能继续消费。三类统一CommonModes30Hz调度，无全局每卡片decoder/每帧discover。
- 悬浮球在允许Home/CC/NC/已选Lock场景里采用当前非安全窗口的最高有界level+1，排除自身且不递增竞赛。普通透明/小绘制手势HUD不再因高于Alert阈值而误隐藏；不按“鱿鱼”猜类名绕过。真实密码/认证/权限/UIAlert/前景控件与高位实质内容继续隐藏，ordinaryApp/blank等原scope不变。最高是对普通窗口的优先级，不绕过系统安全层。

全部UI设置、素材目录/导入替换/GIF预览、720上限、开面板旋转和包简短Description保留。CI原生/doubles不是用户设备的下拉解码/鱿鱼插件兼容/CPU验收；提供实际109包后需真机验证三类下拉立即续播和消失暂停。保留以下历史说明。

## 0.0.108：三类消息停播回归、完整通知背景随动、彩蛋预览与替换

准确基线为已交付107 `800f6a8c0a364ba5a09a1849d54a136e60c60c45`，88文件与源码ZIP逐blob核验，独立108分支，不改其它版本/main。

- 消息/选项/清除：107把UIView父关系误当成backing CALayer直接父关系，UIKit中间材质/变换层会被拒绝。108保持同窗口owner/anchor/overlay身份、安全screen gate，同时沿真实有界CA ancestry检查实际曝光与隐藏、opacity及clips；presentation使用单个实际快照链，不拿独立getter返回的parent指针要求相等。保持单path sharedsource/reader/cache/30HzCommonModes，不新增每卡player。加三target中间layer/独立快照/真实cliphiddennegative回归，以及限流card-exposure日志含published。
- 整体下拉通知中心：原panel内已验证纯背景宿主不再把当帧presentation viewport上沿烘焙进下一次model mask。完整本地视频随原parent层一起滑动，真实window/祖先clip照旧、panel/半屏下沿保留；promoted/root未知路径仍原保守策略，没有无条件放大整窗或盖前景。新增60-frame between-callback parent move regression和lock-actualgeometry真实model/presentation诊断。该源码时序缺陷可复现，但无本版设备录像不能断言它是用户唯一根因。
- 启用小彩蛋总开关紧移到小彩蛋显示设置上方，原key/default不变。
- 小彩蛋图片/GIF页在相册导入行上方增加当前素材预览。后台bounded decode、代际拒陈旧结果，GIF只在页面和预览行可见时跑，退页/相册弹出停止，导入/图标大小/旋转路由重排不混。
- 新图片/GIF验证+发布+持久偏好成功后只删除旧选中的受控图片文件；不扫整个素材库，不删视频/其它引用/新文件，不跟symlink/路径逃逸。失败/取消/陈旧导入保旧，失败新拷贝清理。旧版小彩蛋图片目录也仅限图片扩展的当前引用。
- 旋转速度范围5…720度/秒，720为半秒一圈；保留原默认45与已有设置、相位连续及窗口展开旋转行为。

所有native/doubles并非设备CPU/合成或UIKit相册实测。安装后注销，保留素材/偏好；如仍异常提供108同次录屏和开启诊断日志。包Description继续只用用户短句。以下历史说明保留。

## 0.0.107：下拉通知中心透底/消息续播、两处设置排序、展开窗口旋转

精确基线为104成功交付提交 `0ace15d2650e47d8033888d5f184d98505f778dc`，83个源文件与交付ZIP逐Git blob核验一致，在独立工作区修改。main、104和其它发布分支不动。包详情保留“锁屏消息通知视频背景与独立素材库插件。”。

- 用户已澄清是下拉通知中心顶部透出下面壁纸，不是未覆盖的一条矩形边。104两段日志262条gapTop=0/hostHidden=0不足以证明最终合成不透明。107针对父背景容器淡入路径：仅在same CoverSheet窗口、已曝光原背景、无未知前景/系统mask/filter等安全条件下，将同一个视频宿主挂到较近不透明祖先的原前景支路下面；不改系统alpha/transform/mask，不建新window或新player。仍先在原空间计算物理clip、panel/半屏下沿，保留完整视频画幅后转换，原纯背景租约隐藏并在撤回恢复baseline。未知路径保持原处理，不盲目整窗盖住。诊断默认关，开启限流记录实际祖先model/presentation opacity、有效opacity、maskModel/maskShown和租约对象实际状态。
- 消息续播场景是手指整体下拉/收回通知中心，不是通知列表内部滚动，也不是整页锁屏播放器。保持单path共享消息视频源、缓存/reader及30Hz CommonModes；针对整体动画中的model/presentation可见性边界维护真实曝光消费者，offscreen/关闭/熄屏/异窗仍暂停。原帧转换/媒体内容不改。
- 悬浮素材窗口、主设置中的桌面长按菜单开关与素材选择移到控制中心深/浅素材选择下面；主设置的小彩蛋显示设置也紧跟。偏好key/default/素材选择删除路由不变。
- 开启旋转时，打开/关闭悬浮素材窗口不再停止或重启图片子层旋转；改速度保留当前相位。hidden/无图片/关旋转/关总开关/熄屏仍停止；父容器与拖动命中区域不转，GIF/权限安全门槛保留。

新增回归执行生产函数/CA层和UIKit替身，不等于真机合成或AVFoundation实时解码验收。安装后注销一次；不清素材/偏好。若仍透底，用107开启诊断的同次下拉录屏及shared-render.log配对，不能拿gapTop=0单独认定画面正常。以下历史发布说明保留原样。

## 0.0.104：参考0.1.3最终通知遮罩并集、彩蛋场景/旋转和图标菜单

精确源码基线为103提交 `cdff0425b923fcf48789e382d194e713e4b10fff`，保留原生RootHide、102桌面低开销、正常控制中心及103三类原背景隐藏。没有拿普通rootless参考包替换整个工程。

### 通知修复参考范围

用户提供 `LockMessageVideo_0.1.3.deb`，SHA256 `86e3ac4a20c4af8ac6dceb895cdfa61ce372edd8f690676ec2e5a76ba9aee850`。与原0.0.99实际dylib相同尺寸/双UUID逐字节对照：arm64 `0x21c94`、arm64e `0x1ebe0` 的最终局部clip与容器bounds调用从CGRectIntersection改为CGRectUnion。只移植这项NC源码语义，不复制它其余模块补丁、头字段或签名。

104最终遮罩使用已确认曝光宿主容器bounds与local区域并集（包括可见owner瞬时派生clip空），不是仅上游背景曝光并集。仍遵守实际screen/clip、partial入场底边、关闭/熄屏/未知/撤回的安全门槛，不能在收回后继续盖应用。只有有效通知宿主拥有这项并集，未知root不凭永存窗口出现而显示。用户报告参考包效果正常；104需要设备上同场景验收，不能只凭说明/二进制相似声称已验证。

### 彩蛋显示与旋转

- 小彩蛋总开关照旧。图片设置内增加锁屏、控制中心、桌面三个独立显示开关；缺省锁屏关，CC/桌面开，保持升级前默认。已解锁通知中心沿用原显示，不让普通App全局出现。
- 真实锁屏显示须开启锁屏项且已曝光CoverSheet/屏幕状态可信；密码/认证/权限弹窗仍隐藏。锁屏彩蛋仅展示、拖动，不从锁屏打开素材管理或相册。
- 图片旋转开关默认关；速度5…180度/秒，默认45（8秒一圈）。仅旋转图片子层CABasicAnimation，bubble命中/拖动尺寸不转；可见才跑，开面板/隐藏/熄屏/关闭停止。GIF与原动画保持，稳定审计不反复重建动画，无新增逐帧timer。

### 桌面长按图标菜单视频背景

- 独立HomeMenuBackgroundEnabled默认关、HomeMenuVideo默认未选。小彩蛋主设置和浮窗加开关/切换素材，原片素材库/catalog/rename/delete复用；删除选中素材只清该引用不改enable。
- 仅SpringBoard已解锁Home图标作为sourcePreview的活动UIKit菜单，精确 `_UIContextMenuListView` / `_UIContextMenuPresentationController` 已核对公开iOS16 header与runtime ABI后安装Hook；未知类/方法/签名/前景/背景拒绝，不套猜测全局UIView Hook。
- 独立video-only播放器，在已验证UIVisualEffect纯背景上方/菜单集合内容下方放自有宿主；真实视频首帧未到保留系统材质，不把海报冒充视频。关闭/消失/离Home/路径变/错误/熄屏恢复baseline；自有变换与同父材质匹配，不隐藏文字或按钮。

本地源契约和macOS原生回归覆盖旧功能与新增开关/动画/菜单消费者。iOS私有层级随系统/其它插件变化，运行时gate跳过会保留系统背景；真机菜单/下拉/锁屏效果、CPU未验收时不报“完全解决”或性能数字。安装后注销一次，不清用户素材/偏好。以下历史说明保留。

## 0.0.103：顶部绘制层级/布局时序与三类原背景隐藏

准确基线为已交付102、`6960b065f09dcf8bb4059e76c6b47fdf5aa0e762`。用户反馈其余行为已正常：冻结Desktop/CC/Playback/Easter和设置、素材、导入功能，不改102布局/并集/空mask/半屏关闭策略。

- 通知顶部：102的并集并不证明最终可见顶条一定由遮罩引起。补可复现绘制顺序场景：薄原壁纸捕获条位于视频容器祖先的上方兄弟层，旧同容器扫描看不到，旧30%最小高度过滤掉薄条。103只在已拥有同窗NC范围内有界扫描这些已命名、纯背景且实际曝光的捕获/副本层；文本控件/手势/未知混合内容拒绝隐藏。弱父归属租约在关/熄屏/撤回/移走恢复baseline，所有UIKit backing保持附着。
- 原有CSCoverSheetViewController after-original layout在该事务返回前修复已有视频遮罩和新重绘捕获层，不再仅排队等下一帧；这不是新增全局UIView/CALayer Hook，也不无条件扩大整个窗口覆盖。
- 消息/选项/清除：恢复启用且素材已选后原背景隐藏。没有contents/backgroundColor/sublayers的纯材质仍可能通过delegate绘制：不能把它当空背景跳过；保持backing附着、用原租约opacity抑制。三类替换按附着owner归属而非video alpha、ready或暂hidden/offscreen；关闭/清选择/复用恢复。选项/清除已有租约在原布局结束同事务维护，稳定布局不重新发现背景树。消息正文/按钮不隐藏。
- 诊断默认关闭；开启时顶条坐标按真实图层变换测量，增加0.5pt gap精度以区分裁小与上层覆盖，不记录通知文本。

新增原生回归执行实际生产时序/薄条/祖先租约与三类透明视频/cold/repaint/disable/reuse路径。没有设备录屏/实时层级 trace，不能把上述源码缺陷当成你真机唯一根因，更不能声称顶条已完全消除。若这版同场景仍出现顶条，需设置开启诊断、同一段下拉录屏和 `shared-render.log` 对照，不继续盲目扩矩形。包安装后注销一次，不清素材偏好。

## 0.0.102：桌面刷新风暴收敛、通知并集遮罩与CC半屏实际覆盖

精确基线为已交付101、`a0de0c1f189ac70e7a15e1b937d078694fe34ee5`，保留原生 RootHide 和全部设置/素材/功能。不动 main、100、101 发布分支。

- 桌面CPU：移除101 wallpaper layout 的同步完整策略＋排队全局刷新双路径；稳定原布局只同步已拥有宿主的变化几何。控制器实际身份/可见性变化走桌面局部主回合合并，初次解锁仍即时交接。完整维护仍有界0.2s，壁纸纯度单次扫描，尺寸/hidden/alpha/播放/冻结状态未变不重复写入。
- 播放呈现：稳定状态不反复通知宿主、不重复CoreAnimation事务；真实首帧、素材代际、错误、播放可见性变化仍通知；意外paused实际续播保留。回归对500次稳定更新与500次Home/壁纸layout统计策略/布局/状态setter调用，而不是编造真机CPU降幅。
- 通知顶部：在内容拥有的纯背景空间改为容器与已识别背景并集，避免先交集把顶部内缩继承到遮罩。相同已附着/实际曝光owner在非裁剪root短暂空布局时不因空交集整层撤掉；物理screen/真实clips、关闭/熄屏/撤回及未知owner仍收紧。已正常通知半屏下沿保持。
- CC底部：检测经过所有祖先裁剪后的有效覆盖，而不只测试视频层的bounding box。短小且clipping的CC root切掉视频时，把同一实时视频层放到现有SBControlCenterWindow背景插槽、同一CC前景支路下面；仅临时隐藏确认纯背景材质，关闭/消失/失效/暂停恢复其baseline。无新窗口、无第二播放器/AVPlayerLayer、无静态海报替代视频、不改系统clip/mask、不detach系统backing。身份/前景不明确时不提升。

新增回归包含Home/App两组122半屏中间帧有效裁剪、租约/单播放器/前景排序和撤回恢复。未有真机CPU profile和合成录像；编译/原生回归不等于所有设备/素材下已验收。安装新二进制后注销一次，保留素材偏好；用同一视频、同一桌面/下拉序列对照101与102 CPU和画面。

## 0.0.101：100 真机反馈的转场续播与顶部/底部补齐

精确基线为已交付原生隐根 `0.0.100`、提交 `e7f74964fb0f411c8f13a299e06a5efeb38c11ec`，未切换回099/rootless。用户确认通知降半屏已经正常，本次保持其可见性/生命周期门槛和底部范围，只修通知下拉顶部漏原壁纸。

- 通知顶部：纯背景若比内容横向更宽且完整包住已准入区域，允许补齐其已绘制顶部；不再要求两边 x 恰好相同，也不把真实顶带重新裁回非裁剪根的内缩边界。保持空内容/完全撤回隐藏，保留原半屏底边及安全恢复。
- 控制中心半屏动画：已验证材质的 model/presentation 曝光在各自图层树转换，覆盖自有背景范围；曝光期间轻量几何 display link 及原 layout 后同步，避免100毫秒轮询在动画中落后造成底部透明。只改自有层，不更改系统 clip/mask，不盖按钮。
- 控制中心下拉不播放：局部出现/布局通知重新唤醒已有 suspended 管理器；共享播放类区分 wantsPlayback 意图和实际 rate/timeControlStatus，已请求且意外暂停时续播，不重建源，不把 frozen/hidden/error 状态强行播放。
- 解锁桌面：明确 unlocked 即可在 CoverSheet 退场过程中挂回已有 warm Home 画面，Home willAppear/layout 及解锁状态回调同步接管，不等 cover 变空。排队屏幕通知在 UI 主回合重新取最新值，避免过时 blank 事件隐藏刚解锁桌面。
- SpringBoard 变 inactive 不等于正在显示的 NC/CC 消失：仅实际屏幕不允许播放时全局 suspend；其它情况由各独立宿主决定。

包 ID、用户素材/缓存目录、设置、卡片共享帧链、小彩蛋和浮窗均保留。没有新的私有 Hook；新增调用仍在现有 after-original/layout/公开 AVFoundation KVO 边界。新增原生回归执行真实生产几何/状态机，但不能代替设备上的合成/解锁动画验收。冷启动没有有效 cached/poster 时仍可能有视频首帧等待，不能承诺任何素材任何场景零闪。

## 0.0.100：上传 0.0.99 基线的原生 RootHide 修复版

本版严格基于用户上传的 `LockMessageVideo-0.0.99-src.zip`（SHA256 `a2fe1b75f1a08fae2d10bef4a7a584f26d32e97246bc9ebeb0b1c06ad62147b1`）。已核对远端 0.0.99 提交 `653a6294ea6153eb560771ccdd78bd12b2452686` 的全部 70 个文件与上传版一致，不使用旧工作区替代基线。

- 原生隐根：RootHide Theos、`THEOS_PACKAGE_SCHEME=roothide`、包架构 `iphoneos-arm64e`，真实编译 arm64/arm64e，不修改 CPU subtype 冒充。
- 保留全部设置、素材、消息/选项/清除、锁屏、桌面、控制中心深浅色、小彩蛋与浮窗。包 ID 不变，用户数据仍在 `/var/mobile/LockMessageVideo`；只对安装资源调用 `jbroot()`。
- 桌面：短暂宿主可见性丢失时，保持仍有效的 Home-only 附着和原背景租约，暂停保帧而不因旧 0.6 秒期限恢复原壁纸。锁屏、熄屏、关闭、错误或真实归属变化仍恢复。
- 播放器：同一代已显示的 AVPlayerLayer 在 `readyForDisplay` 短暂下降时不主动隐藏；替换/clear/error 不续用旧帧。
- 控制中心：独立视频图层覆盖实际曝光视口，纯背景材质偏短时补齐底部；材质裁剪时仅把自有 CALayer 放到背景之上、按钮之下，不拆系统 UIView backing layer。
- 稳定滚动复用已验证材质，局部刷新合并，不让 CC 生命周期反复驱动全局消息和素材刷新。常规使用关闭诊断时跳过状态字符串、覆盖几何和性能日志准备。

CI/原生测试只是工程验证，不等于设备合成效果已验收。真机回归：NC 从顶部慢拉/快速收回、NC 降半屏、App 打开/返回后马上降半屏、CC 半屏底部、CC 中浮窗素材列表滚动、关闭各开关与熄屏恢复。新二进制安装后注销一次；不要求先卸载或清除素材。

以下历史说明保留作为版本沿革；旧版本 rootless 的构建说明不适用于本版原生 RootHide。

面向 iOS 16.5 / 原生 Dopamine RootHide 的锁屏通知视频背景插件工程。

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

## 0.0.99：系统在视频之上又画了一遍原壁纸 → 临时抑制那两个「重画壁纸」的层

设备日志显示 `gapTop` / `sampledGapTop` 在所有样本里都是 `0.0`，`above` 里也只剩时钟
与通知列表这类非背景视图——即**几何与 z 序都已就位**。把 `SBCoverSheetWindow` 的完整
层级展开后，找到了压在我们之上的两个「重画原壁纸」的层：

```
CSCoverSheetView
 └ SBFTouchPassThroughView（可滑动内容）
    ├ SBDashBoardWallpaperEffectView   ← 面板背景（我们已在其上）
    ├ UIVisualEffectView
    ├ ▼ LMVLockVideoHost（0.0.98 起的落点）
    ├ UIView → SBFLockScreenDateView    ← 时钟
    ├ SBFTouchPassThroughView
    │   └ PBUIPosterFloatingLayerReplica → _UIPortalView   ← ① 壁纸浮动层实时门户
    └ CSScrollView
        └ CSMainPageView → CSCoverSheetViewBase
            ├ NCMaterialDisplayingCaptureOnlyViewControllerView  ← ② 通知中心「捕获壁纸」底板
            └ 通知列表
```

两者都在视频**之上**：① 是壁纸浮动层的实时门户，② 是通知中心捕获的壁纸底板。
从下方无法盖住它们，因此本版改为**临时抑制（lease）**：视频在屏时把它们 `hidden=YES`，
撤下时**原样恢复**（不摘除、不改结构，系统始终持有这些视图）。

抑制范围有严格限定，避免误伤：

- 命中类名：`NCMaterialDisplayingCaptureOnly`、`PBUIPosterFloatingLayerReplica`、
  `PBUIPosterFloatingView`、`PBUISnapshotReplica`、`SBDashBoardWallpaper*`、
  `*WallpaperEffectView`、`PBUIWallpaperView`；
- 尺寸必须覆盖面板（宽 ≥ 容器一半、高 ≥ 三成），所以通知卡片自身的磨砂底板不受影响；
- 只扫描**视频之上**的兄弟子树（下方的系统壁纸分支保持不动，关掉视频即恢复原样）。

日志新增 `leasedPaint=[...]`，直接列出本次抑制了哪些类。**若某次下拉仍露壁纸，
`leasedPaint` 为空就说明另有其层，`above=[...]` 会同时给出它的类名。**

## 0.0.98：下拉露出的原壁纸来自面板自己画的背景；切换 App 时画面不再闪掉

### 顶部/面板区域露出原壁纸

设备日志给出了决定性事实：`gapTop` 与 `sampledGapTop` 在 **209/209** 个样本里都是 `0.0`
——几何上视频一直盖住该区域。所以露出的是**绘制顺序**问题：

```
CSCoverSheetView
 ├ SBUIBackgroundView          ← 宿主原本插在它上面
 ├ SBFStatusBarLegibilityView
 ├ LMVLockVideoHost            ← 0.0.97 及以前在这里
 └ SBFTouchPassThroughView     ← 可滑动内容（sublayers=6）
    ├ SBDashBoardWallpaperEffectView   ← 面板自己再画一遍壁纸
    ├ UIVisualEffectView
    ├ ▼ ▼ ▼ 视频应该在这里
    ├ UIView / SBFTouchPassThroughView
    ├ CSScrollView              ← 时钟与通知列表
    └ CSFixedFooterView
```

可滑动内容自己画了面板背景（`SBDashBoardWallpaperEffectView` / `UIVisualEffectView`），
而它在 z 序上位于 `controller.view` **之上**，挂在 `controller.view` 里的表面永远盖不住它
——这就是下拉时看到的原壁纸。

本版改为：**当可滑动内容以一段"背景绘制"子视图开头时，把宿主放进该内容内部、就在这段
之后**（壁纸绘制之上、时钟与通知列表之下）。没有这种结构时，仍沿用原来的
`controller.view` 摆放，逐字节不变。

### 切换 App 时视频背景闪掉再恢复

`updatePresentation` 原来有一条 `(!ready && !posterLayer.contents)` —— 播放器一旦
`readyForDisplay` 瞬时变假（**冻结后恢复播放、解码器重新预热**正是这种时刻），就把
`renderLayer` 隐藏，于是露出系统壁纸，等就绪再恢复。

本版新增 `everReady`：**只要这一层已经显示过画面，就永远保留最后一帧**，`!ready` 只对
"从未显示过任何东西"的表面生效。

### 诊断

- `lock-video cover` 新增 `hostSuper=`（宿主落在哪个父视图）与 `above=[...]`（**宿主之上
  还在绘制的可见兄弟**列表）；`container=` 与它们一起构成完整的层级证据。
- `desktop-video` 新增 `hostHidden=` / `poster=` / `shown=`，用于区分"视频是被我们自己
  藏了"还是"被别的东西盖住"。

## 0.0.97：下拉不再漏壁纸；打开/退出 App 不再卡顿

### 顶部漏原壁纸（下拉通知中心）

面板由系统按屏幕刷新率驱动，而本插件的几何是**按显示链采样**的（0.0.96 起 60fps），
所以可滑动内容的"露出版面"边缘最多会比面板**慢一帧**——这一条窄带就是下拉时看到的
原壁纸。

本版给**正在移动的那条边加一帧前瞻**：用上一次采样到现在的位移，把该边沿运动方向
再推出一帧（上限 60pt）。只在版面**变大**时生效；版面变小时不加，所以面板收起仍然
照常撤下视频。日志相应新增 `lead`（本次前瞻量）与 `sampledGapTop` / `sampledGapBottom`
（**前瞻之前**本来会露出的量）：`sampledGapTop>0` 而 `gapTop=0` 即说明这一帧漏出已被
前瞻补掉。

### 桌面通道：打开/退出 App 时卡顿

退出 App 的过渡里，`_frontmostApplication` 可能有一帧读不到 bundle id（返回 0＝未知），
而 Home 的几何也在 App 窗口动画期间抖动。旧代码只把**明确的 -1** 当作"应用在前台"，
于是那一帧直接走了拆除分支（还原租约 + 摘掉宿主），下一帧再重新挂上——看到的正是
"卡一下"。

本版改为：**只要不是确定性原因（息屏／锁屏／通知内容未知／功能关闭／解码错误），
瞬时不可见一律保住宿主并冻结**，并给出 0.6s 的宽限窗口，让过渡中的抖动不再触发
拆除—重建。日志新增 `held=`（已保持多久）与 `teardown=`（累计真正拆除次数）：
`teardown` 不再增长即说明卡顿源头已被消除。

## 0.0.96：视频跟随提速到 60fps；桌面掉背景可直接读日志定位

设备日志（0.0.95）显示几何本身是干净的：下拉时 `reveal` 随下拉递减、`gapTop` 恒为 0。
但拖动过程中仍然会「顶部漏一点」，说明是**跟随速度**问题——视频几何跑在
`CADisplayLink` 的 30fps 上，而面板动画是 60/120fps，领先边因此滞后一帧露出壁纸。

本版把锁屏通道的显示链提高到 **60fps**：

```objc
self.link.preferredFramesPerSecond=60;
```

### 桌面「掉背景」诊断

`desktop-video` 一行补齐了全部决策输入，掉背景时可以直接看出是哪一项否掉的：

```
desktop-video visible=0 frozen=0 home=1 host=none path=1 layer=0 contentHidden=0
  foreground=1 cover=0 blank=0 locked=0 session=1 covered=0 env=1 geo=0
```

- `env` / `geo` / `session`：环境判定、几何可见性、已认证会话
- `covered`：是否被通知中心完全覆盖（此时保留静帧而不是撤下）
- `foreground`：1=SpringBoard、-1=有应用在前台、0=取不到

`visible=0` 时对照这几项即可判断是「几何不可见」「环境未通过」还是「被覆盖」。

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


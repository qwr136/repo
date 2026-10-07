# 锁屏背景视频诊断 0.0.3

基于 qwr136/repo 生产版 0.0.22 (189d05fe6d0c545107716e67156a69aff958cf80)，独立诊断目录、包标识及 dylib。目标为用户自己的 iPhone 14 Pro Max，iOS 16.2/16.5，Dopamine roothide（沿用当前生产仓库的 Theos rootless 打包方式）。

## 安装与采集

1. 安装 com.minis.lockmessagevideo.diagnostic 的 deb 并重启 SpringBoard。可与 com.minis.lockmessagevideo 并存；没有生产包文件重叠或依赖。生产插件仍保留自身行为；诊断插件自身绝不注入背景或创建播放器。
2. 播放音乐，锁屏后点亮屏幕，使播放器保持可见数秒。再显示实际 Live Activity，分别采集展开、收起等需要检查的状态。
3. 用 Filza 读取或分享 /var/mobile/LockMessageVideo/media-live-tree.log。
4. 采集结束卸载“锁屏背景视频诊断”，重启 SpringBoard。日志为运行时生成，卸载不会自动删除；可手动删除上述日志。不要删除共享的 LockMessageVideo 目录或生产媒体。

默认启用，没有设置面板。可用 Filza 创建/修改 /var/mobile/Library/Preferences/com.minis.lockmessagevideo.diagnostic.plist：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Enabled</key><false/></dict></plist>
```

false 关闭，true 启用；删除文件恢复默认启用。约 3 秒内生效，不必改生产偏好。

## 边界与限制

仅 SpringBoard 注入；只 hook 已由 NSClassFromString 查到的 CSCoverSheetViewController (viewDidAppear/viewDidLayoutSubviews) 与 NCNotificationListView (layoutSubviews)，所有原方法照常执行。不 hook 全局 UIView，不链接 AVFoundation、不创建 AVPlayer、不更改音频会话、不增加或修改任何 UI。

主线程读取 UIKit。布局/出现后延迟 350ms 合并扫描；定时器每 3 秒触发，所有实际扫描至少间隔 3 秒，限额检查在窗口枚举和可见性检查之前。仅屏幕点亮且可见 SBCoverSheetWindow/锁屏控制器时转储，支持锁屏及下拉通知中心，不因 SpringBoard applicationState 错误地漏扫。新增仅对已存在 SBCoverSheetWindow 的 layoutSubviews 钩子，无全局 UIView 钩子。窗口来源合并精确钩子观察、锁屏控制器、connectedScenes 与 UIApplication.windows，弱引用保留，不调用未知私有选择器。

优先完整转储 SBCoverSheetWindow/锁屏控制器所在窗口，不依赖叶子类名匹配。其后只发现其他窗口中的 NowPlaying、Media、MRU、Activity、LiveActivity、CHUIS、SBMedia 相关根，桌面窗口最后，不默认转储全部窗口。锁屏子树保留 hidden/alpha=0 分支元数据，不以父节点暂时不可见剪枝。深度 32，快照共 6000 节点、约 1MiB 文本，其他窗口发现限额每窗 6000 节点/24 根/32 层，最多 16 个可见窗口。COVERAGE 显式记录深度截断分支数、节点/大小/发现预算耗尽及未处理窗口；ENUM 列出包括不可见窗口的类名、来源、frame、hidden、alpha 和层级。达到预算时快照并不完整，不能以未出现类推断播放器不存在。

日志保留原有 WINDOW、ROOT ancestry、树形格式与 diagnostic=0.0.3 标记；节点增加 windowFrame、masks、visible、parent、标准 nextResponder 链中控制器类名。RUNTIME 的 NSClassFromString 存在性检查仅代表类已载入，明确标注不是实际树中观测。FNV-1a 状态哈希去重，同状态每 60 秒最多写一次。单代约 1MiB，保留 media-live-tree.log 和 .log.1 两代，合计约 2MiB；只轮转这两个诊断文件，绝不清除共享目录。串行后台写盘，当前日志权限 0600。

只输出时间、原因、类名及几何/可见性状态，无标签文字、通知正文、音乐标题、图片或网络上传。远程渲染内容可能只有宿主视图，不能透过跨进程渲染恢复媒体或 Widget 内部树。截图只能确认播放器可见，不能确认实际私有类名。当前版本尚未设备实测；采集时让播放器保持可见 5-10 秒，分享 log 与存在时的 log.1。

当前环境未连接目标越狱设备，构建与包结构验证不等于设备实测。若 roothide 要求 iphoneos-arm64e 原生包而非该仓库的 iphoneos-arm64 rootless 包，请使用现有 roothide rootless 转换机制；不要强制忽略包管理器架构错误。AOD 的系统息屏通知若为 blank，本包会跳过，需点亮屏幕后采集。

## 构建

独立分支 diagnostic/media-live-tree，独立 Actions 工作流 build-diagnostic-deb，仅执行 diagnostic/ 下 make clean package FINALPACKAGE=1，不修改生产 Makefile、Tweak.xm、control、过滤器或工作流。依赖 UIKit、Foundation 与系统 libnotify，安装仅独立 dylib/filter。

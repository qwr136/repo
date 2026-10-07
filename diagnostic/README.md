# 锁屏背景视频诊断 0.0.2

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

主线程读取 UIKit。布局/出现后延迟 350ms 合并扫描；定时器每 3 秒触发，息屏或锁屏/通知容器不可见时不遍历相关子树。扫描至少间隔 1 秒。匹配 NowPlaying、Media、MRU、Activity、LiveActivity、CHUIS、SBMedia；Widget、CoverSheet、Notification 作为发现锚点，不整棵转储这些泛用容器。只输出可见相关根、简要祖先类名和所在窗口元信息。类名匹配为启发式，不保证每个私有 iOS 版本都暴露相同类。

每个相关子树深度最多 18，快照最多 500 节点，发现每窗口最多 3000 节点/12 根/24 深度，最多 16 个可见窗口。快照文本约 100KB 上限，FNV-1a 状态哈希去重，相同状态每 60 秒最多再记录一次。文件约 1MiB 上限，达到上限即以新快照替换，不额外生成轮转文件。串行后台写盘，文件权限 0600。

输出只含时间、原因、类名、frame、hidden、alpha、window level，无标签文字、通知正文、音乐标题、图片或网络上传。Live Activity 的远程渲染内容可能只能看到宿主视图，不能透过跨进程渲染恢复 Widget 内部树。点亮锁屏无匹配也会记录一次 no-match 状态。

当前环境未连接目标越狱设备，构建与包结构验证不等于设备实测。若 roothide 要求 iphoneos-arm64e 原生包而非该仓库的 iphoneos-arm64 rootless 包，请使用现有 roothide rootless 转换机制；不要强制忽略包管理器架构错误。AOD 的系统息屏通知若为 blank，本包会跳过，需点亮屏幕后采集。

## 构建

独立分支 diagnostic/media-live-tree，独立 Actions 工作流 build-diagnostic-deb，仅执行 diagnostic/ 下 make clean package FINALPACKAGE=1，不修改生产 Makefile、Tweak.xm、control、过滤器或工作流。依赖 UIKit、Foundation 与系统 libnotify，安装仅独立 dylib/filter。

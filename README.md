# 消息背景诊断 0.0.2

独立于 `com.minis.lockmessagevideo` 生产包的 SpringBoard 诊断插件。包标识为 `com.minis.lockmessagevideo.message-diagnostic`，不会修改生产插件、视频播放、AVPlayer 或音频行为。

## 安装与设置

安装 `LockMessageVideoMessageDiagnostic_0.0.2_iphoneos-arm64.deb` 后重启 SpringBoard。PreferenceLoader 中会显示“消息背景诊断”，其中的“启用消息背景诊断”开关使用 CFPreferences 域 `com.minis.lockmessagevideo.message-diagnostic` 的 `Enabled` 键。缺少该键时默认为启用；显式关闭后，通知生命周期记录停止。设置 bundle、PreferenceLoader 入口和诊断 dylib 使用独立名称，可与生产包共存。

日志路径：`/var/mobile/LockMessageVideo/message-diagnostic.log`。

插件加载到 SpringBoard 后会先写入 `event=loaded enabled=1 version=0.0.2`。随后记录 `NCNotificationListCell` 的 attach/detach、reuse 和 layout 生命周期，以及非内容的类名、几何、层级和图层元数据。日志目录自动创建为 0700，日志文件为 0600，达到 1 MiB 时保留 `.log.1`。日志只在 SpringBoard 注入，过滤器为 `com.apple.springboard`。

## 构建

```sh
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
```

输出包架构是 `iphoneos-arm64`，rootless 安装路径为 `/var/jb/Library/MobileSubstrate/DynamicLibraries`、`/var/jb/Library/PreferenceBundles` 和 `/var/jb/Library/PreferenceLoader/Preferences`。卸载诊断包不会删除日志；可在采集后手动删除日志文件。

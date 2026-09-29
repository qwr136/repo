# WetypeToolbarPlus — 微信输入法工具栏增强

Theos 越狱插件。针对微信输入法（wxkb，`com.tencent.wetype` / `com.tencent.wetype.keyboard`）：

1. **解除工具栏按钮最多 7 个的数量限制**，上限可调（1-20）
2. **自定义按钮之间的间距、工具栏左右边距**（0 表示保持原版）
3. **设置面板**：安装后在「设置 → 微信输入法工具栏增强」，改动实时生效，无需重启
4. 诊断日志开关：输出内部类名/方法名，方便后续版本精确适配

## 注入进程（filter）

- `com.tencent.wetype.keyboard`（wxkb_plugin，键盘扩展进程）
- `com.tencent.wetype`（wxkb，主 App）

## 目录结构

```
Makefile                     # tweak + 子项目聚合
control                      # deb 包信息
WetypeToolbarPlus.plist      # MobileSubstrate filter（注入目标）
Tweak.x                      # 插件主逻辑（Logos）
layout/Library/PreferenceLoader/Preferences/wetypeplus.plist  # 设置入口
wetypeprefs/                 # PreferenceBundle 设置面板 → /Library/PreferenceBundles
```

## 编译

```bash
export THEOS=~/theos   # 或 /opt/theos
make package FINALPACKAGE=1
```

产物：`packages/*.deb`（iphoneos-arm，rootful；rootless 环境请改 `THEOS_PACKAGE_SCHEME=rootless`）。

## 安装

1. 把 deb 传到手机（AirDrop / Filza / scp 均可），用 Filza 打开安装；
2. 注销或重启（键盘扩展会自动重载）；
3. 设置 → 微信输入法工具栏增强 里调整按钮数上限 / 间距 / 边距；
4. 收起再展开键盘工具栏即可看到效果。

## 工作原理与适配说明

- 间距/边距：钩住键盘进程里满足“工具栏特征”（横向、高度 22-96pt）的 `UIStackView` / `UICollectionViewFlowLayout`，写入自定义 spacing 与 layoutMargins。
- 数量限制：运行时扫描类名含 `tool`/`panel` 的类，把其中返回值为 7 的无参 `max/limit` 整型方法改为用户设置的上限（只动 max/limit 命名的方法，不碰普通 getter，避免误伤）。
- 如果微信输入法后续版本类名变化导致启发式未命中，打开设置里的「诊断日志」，用 idevicesyslog 抓取 `[WetypeToolbarPlus]` 输出，反馈后可在 `Tweak.x` 中精确定点挂钩。

## 偏好域

`CFPreferences` 域：`com.wetypeplus`（键：`enabled` `maxButtons` `hSpacing` `leftMargin` `rightMargin` `debugLog`）

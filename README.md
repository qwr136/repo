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
Makefile                     # tweak 主包 + before-all 钩子编 App
control                      # deb 包信息
WetypeToolbarPlus.plist      # MobileSubstrate filter（注入目标）
Tweak.x                      # 插件主逻辑（Logos）
build_app.sh                 # 打包前编译并拷入独立设置 App
wetypeapp/                   # 独立越狱 App「微信输入法自定义」(UIKit)
  Makefile                   #   application.mk
  entitlements.plist         #   platform-application + 无容器（写全局 CFPreferences）
  Resources/Info.plist       #   显示名「微信输入法自定义」
  src/                       #   main / AppDelegate / SettingsViewController
layout/Library/PreferenceLoader/Preferences/wetypeplus.plist  # 设置内偏好项兜底入口（零代码）
layout/Applications/WetypeCustomApp.app  # 由 build_app.sh 现编现拷，不进版本库
```

## 已构建版本

- **`wetype-toolbar-plus-rootless.deb`** — ⭐ 推荐，rootless 布局（`/var/jb/...`），适配 Dopamine 2 / palera1n rootless，iPhone 14 Pro Max + iOS 16.5（arm64）。
  内含两部分：
  1. `WetypeToolbarPlus.dylib` + filter plist → `/var/jb/Library/MobileSubstrate/...`（注入微信输入法）
  2. **独立 App「微信输入法自定义」** → `/var/jb/Applications/WetypeCustomApp.app`（桌面设置面板）
- `packages/com.wetypeplus.toolbarplus_1.0.5_iphoneos-arm64.deb` — 同上 rootless 包（GitHub Actions 自动构建产物）。
- 旧 rootful 包（传统 `/Library/...`，适配 unc0ver/checkra1n）已不再保留，按需用 `make package` 重打。

## 编译

```bash
export THEOS=~/theos   # 或 /opt/theos

# rootless（Dopamine 2 / palera1n rootless）
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# rootful（传统越狱）
make package FINALPACKAGE=1
```

产物：`packages/*.deb`（arm64 切片，rootless）。

## 安装（rootless 越狱）

1. 把 `wetype-toolbar-plus-rootless.deb` 传到手机（Filza / Sileo 导入 / scp 均可），用 Filza 打开安装；
2. 安装后**刷新图标缓存**：Sileo 会自动 `uicache`；Filza 装完建议 `ldrestart` 或 `uicache` 一次，让桌面出现「微信输入法自定义」图标；
3. 打开桌面 **「微信输入法自定义」** App 调整：启用开关 / 最大按钮数(1-20) / 按钮间距 / 左右边距 / 诊断日志；
   （若 App 暂未出现，也可进 **设置 → 微信输入法工具栏增强** 调整，二者写同一偏好域、互相同步）
4. 收起再展开键盘工具栏即可看到效果（修改即时写入，键盘下次弹出时 Tweak 自动读取）。

## 工作原理与适配说明

- 间距/边距：钩住键盘进程里满足“工具栏特征”（横向、高度 22-96pt）的 `UIStackView` / `UICollectionViewFlowLayout`，写入自定义 spacing 与 layoutMargins。
- 数量限制：运行时扫描类名含 `tool`/`panel` 的类，把其中返回值为 7 的无参 `max/limit` 整型方法改为用户设置的上限（只动 max/limit 命名的方法，不碰普通 getter，避免误伤）。
- 如果微信输入法后续版本类名变化导致启发式未命中，打开设置里的「诊断日志」，用 idevicesyslog 抓取 `[WetypeToolbarPlus]` 输出，反馈后可在 `Tweak.x` 中精确定点挂钩。

## 偏好域

`CFPreferences` 域：`com.wetypeplus`（键：`enabled` `maxButtons` `hSpacing` `leftMargin` `rightMargin` `debugLog`）

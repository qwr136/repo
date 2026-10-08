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

## 0.0.54
- 移除通知堆叠阴影开关、滑块、专用状态/helper/hook 及专用测试；保留原有视频透明度语义。
- 桌面自有层的显示与解码分开：下拉通知中心及长按菜单过程中保留最后真实帧，完整遮挡后暂停桌面解码，收起后恢复。未知前台对象或打开应用时不继续桌面解码。锁定、熄屏或失去合法桌面宿主时隐藏自有层；关闭功能或更换素材时仅移除自有层。
- 通知中心完整遮挡需要 CoverSheet 实际宿主的 model 与 presentation 屏幕矩形都覆盖桌面；不能仅凭一个可见的全屏窗口提前判断动画完成。
- 桌面层只在未挂载时插入；布局和长按过渡不反复 remove/reinsert。浮动 Dock 窗口/控制器属于 SpringBoard 的 UI，不能当作已打开的应用；真实前台应用标识优先。未修改系统 Dock/图标内容布局，不重置其他插件的 alpha、hidden、frame 或 transform。
- 消息、选项、清除和锁屏的共享媒体链保留；桌面与锁屏独立素材选择，素材库缩略图、重命名、删除、当前标记、应用提示、相册导入重新压缩与临时原素材清理、Filza 路径入口及诊断默认关闭均保留。
- 诊断打开后，最多 30 组、间隔至少 2 秒采样，每组最多 16 个窗口与 32 个视图节点，记录窗口类/level/hidden/alpha/key 和 backdrop 父层状态，不采集应用文本。日志仍位于 `/var/mobile/LockMessageVideo/shared-render.log`，沿用 64 KiB 轮转和总记录上限。
- `tests/desktop-consumer.c` 执行实际共享策略的 2048 种状态及通知中心过渡几何、浮动 Dock、真实应用和未知前台判定；`tests/desktop-runtime.py` 在 macOS 执行实际桌面更新/解绑函数的 Foundation doubles，验证暂停保留帧和层级、锁定隐藏、关闭仅移除自有层及无关视图不变。编译与 doubles 不能替代 iPadDock 真机兼容验收。

覆盖安装相同包 ID `com.minis.lockmessagevideo`，保持 rootless 安装路径；不删除 `/var/mobile/LockMessageVideo` 或现有偏好。安装后重新载入 SpringBoard。若 iPadDock 自己在长按时隐藏 Dock，本补丁不强制改写系统窗口状态，需要开启诊断采样并结合真机层级/ips 确认。


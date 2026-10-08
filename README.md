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
- Filza: `/var/jb/var/mobile/LockMessageVideo/`
- 默认消息素材: `/var/jb/var/mobile/LockMessageVideo/message.mov`
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

## 0.0.45 视频背景架构
- 同一标准化素材路径只创建一个静音、仅含视频轨道的 `AVPlayer` / `AVPlayerItemVideoOutput`；Message、Options、Clear 选择同路径时自然复用，不再按卡片建立播放器或 looper。
- 输出帧经复用 `CIContext` 在串行后台队列生成一次不可变 `CGImage`，再在主线程广播到各自独立的普通 `CALayer.contents`，每张卡片独立裁剪，不共享 `AVPlayerLayer`。
- 显示更新上限为 30 FPS，最大共享帧边长 960；仅在可见消费者存在时使用 common-mode display link。只复制新像素缓冲，全局至多一个转换任务在途；不代表源视频编码帧率或码率保证。
- 熄屏、通知中心隐藏或无可见消费者时暂停共享源，保留最后真实解码帧和对应播放时间，重新下拉直接显示缓存帧并恢复，不生成无关的首帧海报；移除旧的 0.10 秒人为起播延迟。
- 背景范围使用 `anchor.bounds` 转换到模型 host 坐标；插件拥有自己的连续圆角剪裁，不复制系统复合遮罩，不调整宿主 frame、约束或文字层级。
- 修复根 `UIWindow` 没有 `superview` 导致误暂停的判断。只 hook 通知卡片、动作呈现器及 CoverSheet 类，无全局 UIView hook。
- 保留 0.0.44 设置、相册导入/原素材保存、压缩、Filza、透明度语义、独立选项和清除区域；不扩展到 Live Activity。

编译和静态结构验证不能代替真机验证。不同 iOS 私有视图层级、异形系统圆角/素材、循环接缝、首次冷启动解码时间、CPU/GPU 和滚动流畅度仍需设备实测，不能保证完全不卡顿。

## 注意
- 当前实现按 iOS 16 锁屏通知常见类名做了候选挂载，不同小版本可能需要再微调。
- 修改视频后建议注销或重启 SpringBoard。
- 若 roothide 环境有特殊 PreferenceLoader 路径差异，可按你的环境微调 layout。

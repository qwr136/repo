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
- `/var/jb/var/mobile/Library/LockMessageVideo/message.mov`
- `/var/jb/var/mobile/Library/LockMessageVideo/options.mov`

## 编译
### 本地
```sh
export THEOS=/path/to/theos
make clean package FINALPACKAGE=1
```

### GitHub Actions
把整个工程上传到 GitHub 仓库，Actions 会在 `packages/` 产出 deb 并上传 artifact。

## 注意
- 当前实现按 iOS 16 锁屏通知常见类名做了候选挂载，不同小版本可能需要再微调。
- 修改视频后建议注销或重启 SpringBoard。
- 若 roothide 环境有特殊 PreferenceLoader 路径差异，可按你的环境微调 layout。

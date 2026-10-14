# 用户参考包：只移植通知中心遮罩修改

输入：`LockMessageVideo_0.1.3.deb`，SHA256 `86e3ac4a20c4af8ac6dceb895cdfa61ce372edd8f690676ec2e5a76ba9aee850`。

用户说明该包下拉过程不漏原壁纸；这是用户真机反馈，不是本助手设备验证。

## 准确同源对照

从已知0.0.99提交 `653a6294ea6153eb560771ccdd78bd12b2452686` 的成功Actions `38284339499` 下载原包，与参考包主dylib逐字节对比。

- 两者主dylib均 `1051456` 字节；fat arm64 offset `0x8000`、arm64e offset `0x88000`。
- 两者UUID相同：arm64 `23B8D04C-FFAF-37BE-9992-A8F29A44F5BC`，arm64e `AECA983B-F882-3A52-9BCE-BA7FF2B9AAF0`。这只支持相同构建基底，不代表当前103偏移也一样。
- 普通rootless包架构 `iphoneos-arm64`、`var/jb`布局，不能当原生RootHide包直接合并。

## 通知修复的真实调用点

arm64 `LMVLockVideoManager update` 起点 `0x20ecc`；局部clip helper已内联。

在 slice-relative `0x21c94`，两份上下文完全相同，唯一分支指令目标从：

```text
BL CGRectIntersection
```

变为：

```text
BL CGRectUnion
```

紧接此调用后验证CGRect，再按容器bounds原点offset、构造mask path。第二个参数来自同一container的 `bounds` getter，而不是新增播放器或根窗口。

arm64e对应调用点 `0x1ebe0` 同样从Intersection改为Union。只记录上述与NC有关的修改；参考包其他模块差异不移植，避免回退已正常的Desktop/CC/Playback。

## 104源码移植

`LMVLockVideoFinalMask(local, container, physical, owned)` 在最终遮罩生成环节使用container/local并集，确认NC宿主处于实际曝光时可保留container下的瞬时空派生区域。物理screen/真实clips、关闭/熄屏/withdraw/未知ownership仍约束实际绘制。保持部分下拉的已准入底边，不能因为永存root.bounds而盖住收回后的桌面/App。

回归包括实际production C helper及UIKit/QuartzCore native宿主测试。重编译真实arm64/arm64e源项目并正常签名；不把旧二进制补丁偏移套新包，不修改CPU subtype冒充，不用参考包替换整套工程。

`1.txt`包含操作叙述，缺具体offset；以上offset来自实际上传包与同源99的只读分析。录屏是8.435秒、886×1920的设备场景，不包含代码。104是否等同用户参考包的实际观感仍需要用户同场景安装验证。

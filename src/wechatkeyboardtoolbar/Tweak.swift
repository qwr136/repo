// WeChatKeyboardToolbar.swift
// 微信键盘工具栏增强（纯 Swift 重写版）
//
// 功能：
//   1. 自定义工具栏按钮数量（解除原版最多 7 个限制）；
//   2. 自定义工具栏左右边距；
//   3. 配套系统设置面板（PreferenceLoader 的 Root.plist），两个数值输入框：
//      按钮数量（最小 1）、工具栏左右边距（最小 0pt），配置持久化，
//      插件读取配置修改 UI，并对数值做上下限钳制防止 UI 崩溃。
//
// ⚠️ 关于「符号」：微信键盘是闭源第三方输入法扩展，其内部工具栏视图类 /
//    数据源方法名无法预先得知。因此本插件采用「运行时发现」策略：
//   - 边距：按类名模式（Toolbar/ToolBar/Bar 等）在键盘视图树里找工具栏容器，
//           直接改它的 layoutMargins / 内容容器 contentInset，通用且无需知道精确类；
//   - 数量：需要覆盖真实数据源方法（一般藏在 UICollectionView / UIStackView 的
//           numberOfItems 里）。开启「调试日志」后插件会把工具栏里的
//           collectionView 的 dataSource 类名 + 方法列表打到 syslog，你据此把
//           真实方法名填进 wkOverrideCount() 即可生效（见文件末尾示例）。
//
// 包名 / 偏好域 / 通知名统一为：com.xiaofei.wechatkeyboardtoolbar

import UIKit
import Foundation
import ObjectiveC

// MARK: - 常量
let WK_DOMAIN = "com.xiaofei.wechatkeyboardtoolbar" as CFString
let WK_NOTI   = "com.xiaofei.wechatkeyboardtoolbar/preferences.changed" as CFString

// MARK: - 偏好读取（rootless：CFPreferences 自动走 /var/jb/var/mobile/Library/Preferences）
func wkPrefInt(_ key: String, default d: Int) -> Int {
    guard let v = CFPreferencesCopyAppValue(key as CFString, WK_DOMAIN) else { return d }
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String, let i = Int(s) { return i }   // PSNumberCell 偶尔存字符串
    return d
}
func wkPrefBool(_ key: String, default d: Bool) -> Bool {
    guard let v = CFPreferencesCopyAppValue(key as CFString, WK_DOMAIN) else { return d }
    if let n = v as? NSNumber { return n.boolValue }
    return d
}
func wkPrefString(_ key: String, default d: String) -> String {
    guard let v = CFPreferencesCopyAppValue(key as CFString, WK_DOMAIN) else { return d }
    if let s = v as? String { return s }
    return d
}

// MARK: - 数值校验 / 钳制（防 UI 崩溃）
func wkClampCount(_ raw: Int) -> Int {
    // 最小 1；上限 50（过大数会导致 collectionView / stack 在布局时崩溃）
    return max(1, min(50, raw))
}
func wkClampMargin(_ raw: Double) -> Double {
    // 最小 0pt；上限 200pt
    return max(0, min(200, raw))
}

// MARK: - 全局配置缓存
var gCount: Int = 7
var gMargin: Double = 0
var gDebug: Bool = false

func wkReloadPrefs() {
    gCount  = wkClampCount(wkPrefInt("ToolbarButtonCount", default: 7))
    gMargin = wkClampMargin(Double(wkPrefInt("ToolbarMargin", default: 0)))
    gDebug  = wkPrefBool("DebugLog", default: false)
}

// MARK: - 偏好变更实时生效（PreferenceLoader / Cephei 会发 Darwin 通知）
func wkObservePrefs() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let cb: CFNotificationCallback = { _, _, _, _, _ in wkReloadPrefs() }
    CFNotificationCenterAddObserver(center, nil, cb, WK_NOTI, nil, .deliverImmediately)
}

// MARK: - swizzle 工具（与 ReturnKeyColor 验证过的写法一致）
func wkSwizzle(cls: AnyClass, sel: Selector, block: Any) -> IMP? {
    guard let m = class_getInstanceMethod(cls, sel) else { return nil }
    let origIMP = method_getImplementation(m)
    let newIMP = imp_implementationWithBlock(block)
    let types = method_getTypeEncoding(m)
    var added = false
    if let t = types { added = class_addMethod(cls, sel, newIMP, t) }
    if !added { method_setImplementation(m, newIMP) }
    return origIMP
}

// MARK: - 主入口 hook：键盘 InputViewController 即将出现
var gOrigViewWillAppear: ((AnyObject, Selector, Bool) -> Void)?
func wkHookInputViewController() {
    // 注：微信键盘的主 VC 是 UIInputViewController 的子类。这里 hook 基类
    // viewWillAppear:；若其子类重写了该方法，基类 hook 不一定命中——调试日志会
    // 打印真实 VC 类名，必要时把 hook 目标换成精确子类即可。
    let sel = #selector(UIInputViewController.viewWillAppear(_:))
    let imp = wkSwizzle(cls: UIInputViewController.self, sel: sel, block: { (me: AnyObject, animated: Bool) in
        gOrigViewWillAppear?(me, sel, animated)   // 先调原始实现
        wkOnKeyboardAppear(me)
    } as Any)
    if let imp = imp {
        gOrigViewWillAppear = unsafeBitCast(imp, to: ((AnyObject, Selector, Bool) -> Void).self)
    }
}

func wkOnKeyboardAppear(_ me: AnyObject) {
    wkReloadPrefs()
    // 延迟一拍，等键盘视图树真正建好再遍历
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard let vc = me as? UIInputViewController else { return }
        if gDebug { wkDumpHierarchy(vc.view) }
        if let tb = wkFindToolbar(in: vc.view) {
            wkApplyMargin(to: tb)
            wkApplyCountHint(tb)
        } else if gDebug {
            NSLog("[WKTB] 未找到工具栏视图（按 Toolbar/ToolBar/Bar 模式）。可在设置里填精确类名 ToolbarClassName。")
        }
    }
}

// MARK: - 工具栏发现（运行时，按类名模式 / 可选精确类名）
func wkFindToolbar(in view: UIView?) -> UIView? {
    guard let view = view else { return nil }
    let exact = wkPrefString("ToolbarClassName", default: "").trimmingCharacters(in: .whitespaces)
    if !exact.isEmpty {
        if let f = wkDeepFirst(view, where: { String(describing: type(of: $0)) == exact }) { return f }
    }
    let patterns = ["Toolbar", "ToolBar", "CandidateBar", "AccessoryBar", "TopBar", "Tool"]
    for p in patterns {
        if let f = wkDeepFirst(view, where: { String(describing: type(of: $0)).contains(p) }) { return f }
    }
    return nil
}

func wkDeepFirst(_ view: UIView, where pred: (UIView) -> Bool) -> UIView? {
    if pred(view) { return view }
    for s in view.subviews {
        if let r = wkDeepFirst(s, where: pred) { return r }
    }
    return nil
}

func wkFirstDescendant<T: UIView>(_ view: UIView, of cls: T.Type) -> T? {
    if let m = view as? T { return m }
    for s in view.subviews {
        if let r = wkFirstDescendant(s, of: cls) { return r }
    }
    return nil
}

// MARK: - 功能 2：左右边距（通用，无需精确类）
func wkApplyMargin(to tb: UIView) {
    let m = CGFloat(gMargin)
    tb.layoutMargins = UIEdgeInsets(top: tb.layoutMargins.top,
                                   left: m,
                                   bottom: tb.layoutMargins.bottom,
                                   right: m)
    // 内容容器若是滚动视图，一并调 contentInset，否则只改 layoutMargins 可能不生效
    if let scroll = wkFirstDescendant(tb, of: UIScrollView.self) {
        var ins = scroll.contentInset
        ins.left = m; ins.right = m
        scroll.contentInset = ins
        scroll.scrollIndicatorInsets = ins
    }
    tb.setNeedsLayout()
    tb.layoutIfNeeded()
    if gDebug { NSLog("[WKTB] 已应用左右边距 = \(m)pt 到 \(String(describing: type(of: tb)))") }
}

// MARK: - 功能 1：按钮数量（需要真实数据源符号，这里给出发现 + 占位覆盖）
func wkApplyCountHint(_ tb: UIView) {
    guard gDebug else {
        // 非调试模式：留空。知道真实符号后，把覆盖逻辑写进 wkOverrideCount() 并在
        // wkOnKeyboardAppear 里调用它即可（见文件末尾示例）。
        return
    }
    if let cv = wkFirstDescendant(tb, of: UICollectionView.self), let ds = cv.dataSource {
        let cls = type(of: ds)
        let n = cv.numberOfItems(inSection: 0)
        NSLog("[WKTB] 找到 UICollectionView，dataSource 类 = \(cls)，当前 item 数 ≈ \(n)")
        wkDumpMethods(of: cls)
    }
    if let sv = wkFirstDescendant(tb, of: UIStackView.self) {
        NSLog("[WKTB] 找到 UIStackView，当前 arrangedSubviews 数 = \(sv.arrangedSubviews.count)")
    }
}

// 示例：等你在调试日志里确认真实类 / 方法后，取消注释并改成真实实现
/*
func wkOverrideCount(_ tb: UIView) {
    // 假设工具栏里是 UICollectionView，且 dataSource 有个返回按钮数组的方法
    guard let cv = wkFirstDescendant(tb, of: UICollectionView.self),
          let ds = cv.dataSource else { return }
    // 用 method_exchangeImplementations / rkSwizzle 把
    // collectionView(_:numberOfItemsInSection:) 改成 return gCount
    // 即可解除 7 个上限。具体方法名以调试日志为准。
}
*/

// MARK: - 调试日志（默认关闭，开启后把视图树 / 数据源方法打到 syslog）
func wkDumpHierarchy(_ view: UIView?, indent: String = "") {
    guard let view = view else { return }
    let cls = String(describing: type(of: view))
    NSLog("[WKTB] \(indent)\(cls) frame=\(String(describing: view.frame))")
    for s in view.subviews { wkDumpHierarchy(s, indent: indent + "  ") }
}

func wkDumpMethods(of cls: AnyClass?) {
    guard let cls = cls else { return }
    var count: UInt32 = 0
    if let list = class_copyMethodList(cls, &count) {
        for i in 0..<Int(count) {
            let sel = method_getName(list[i])
            NSLog("[WKTB]   method: \(String(describing: sel))")
        }
        free(list)
    }
}

// MARK: - 入口（由 Tweak.m 的 constructor 调用）
@_cdecl("WKSetup")
func WKSetup() {
    wkReloadPrefs()
    // 注入自检：开「调试日志」后可在 syslog 看到插件实际注入到哪个 bundle
    NSLog("[WKTB] 插件已加载，进程 bundle id = \(Bundle.main.bundleIdentifier ?? "(nil)")，DebugLog=\(gDebug)")
    wkHookInputViewController()
    wkObservePrefs()
}

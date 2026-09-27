import UIKit
import Foundation
import ObjectiveC
import CoreGraphics

// 键盘回车键同色 — 诊断版（Swift 重写）
//
// 目标：回车键（发送 / 搜索 / 换行 / 前往 / GO…）背景 = 123 键的灰，
//       字体大小 / 文字颜色 / 排版 100% 保持原生。
//
// 说明：displayType 整包替换能变色但会连字体一起变大（已废弃）。
//       本版只在键帽位图绘制瞬间把蓝色像素换成 123 键的灰（alpha 不动）。
//       同时堵三个绘制入口，并用弹窗报告「到底哪个入口命中」，便于一次性定位真实绘制路径。
//       诊断弹窗默认开启（不需要手动加 plist），每次进程启动弹一次。

// MARK: - 全局状态
var gFuncColor: UIColor? = nil
var gFuncColorStyle: UIUserInterfaceStyle = .unspecified
var gLayerHooksReady = false
var gKeyViewCls: AnyClass? = nil
var gDiag: [String] = []
var gDiagShown = false
var gCurReturnKey: AnyObject? = nil
var gDiagWindow: UIWindow? = nil
var gFails = 0

// 诊断默认开启（这是诊断版）
let gDiagEnabled = true

// 原方法实现（hook 后调用）
var gOrigDisplayLayer: ((AnyObject, Selector, CALayer) -> Void)?
var gOrigDrawLayer: ((AnyObject, Selector, CALayer, CGContext?) -> Void)?
var gOrigDidMove: ((AnyObject, Selector) -> Void)?
var gOrigLayout: ((AnyObject, Selector) -> Void)?
var gOrigLayerDrawCtx: ((AnyObject, Selector, CGContext?) -> Void)?

let kRKPremulLastBig: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

var kRKGenKey: UInt8 = 0

// MARK: - 开关 / 环境
func rkIsAppExtension() -> Bool {
    if let info = Bundle.main.infoDictionary, info["NSExtension"] != nil { return true }
    let ext = (Bundle.main.bundlePath as NSString).pathExtension
    if !ext.isEmpty, ext == "appex" { return true }
    return false
}

func rkEnabled() -> Bool {
    struct S { static var checked = false; static var ext = false }
    if !S.checked { S.ext = rkIsAppExtension(); S.checked = true }
    if S.ext { return false }
    return true
}

func rkDiag(_ s: String) {
    guard gDiagEnabled else { return }
    gDiag.append(s)
}

func currentStyle() -> UIUserInterfaceStyle {
    return UITraitCollection.current.userInterfaceStyle
}

func rkRGBStr(_ c: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "(%.2f,%.2f,%.2f,%.2f)", r, g, b, a)
}

// MARK: - 判定
func rkHas(_ hay: String, _ needle: String) -> Bool {
    let h = hay.lowercased(), n = needle.lowercased()
    guard !n.isEmpty else { return false }
    return h.contains(n)
}

func rkTextOf(_ obj: Any?, depth: Int = 0) -> String? {
    guard let obj = obj as? NSObject, depth <= 3 else { return nil }
    let ks = ["displayString", "stringRepresentation", "representedString", "name", "title", "text"]
    for k in ks {
        if let v = obj.value(forKey: k) as? String, !v.isEmpty { return v }
    }
    if let sub = obj.value(forKey: "key") as? NSObject, sub !== obj {
        return rkTextOf(sub, depth: depth + 1)
    }
    return nil
}

func rkTreeName(_ obj: Any?) -> String? {
    guard let obj = obj as? NSObject else { return nil }
    var tree: NSObject = obj
    if let k = obj.value(forKey: "key") as? NSObject { tree = k }
    return tree.value(forKey: "name") as? String
}

func rkIsReturn(_ obj: Any?) -> Bool {
    guard let obj = obj else { return false }
    if let nm = rkTreeName(obj), rkHas(nm, "return") { return true }
    guard let t = rkTextOf(obj), !t.isEmpty else { return false }
    let words = ["发送","搜索","前往","回车","换行","确认","确定","完成","加入",
                 "send","search","go","return","next","done","join"]
    let low = t.lowercased()
    for w in words { if low == w || low.hasPrefix(w) { return true } }
    return false
}

func rkIsMore(_ obj: Any?) -> Bool {
    guard let obj = obj else { return false }
    if let nm = rkTreeName(obj), nm.caseInsensitiveCompare("More-Key") == .orderedSame { return true }
    guard let t = rkTextOf(obj), !t.isEmpty else { return false }
    let low = t.lowercased()
    return low == "123" || low == "#+=" || low == "abc"
}

func rkIsBluePixel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Bool {
    return b > 0.45 && (b - r) > 0.28 && (b - g) > 0.12
}

func rkIsBlue(_ c: UIColor?) -> Bool {
    guard let c = c else { return false }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if !c.getRed(&r, green: &g, blue: &b, alpha: &a) { return false }
    return rkIsBluePixel(r, g, b)
}

// 避免 Swift 对 CGImage(CF 类型) 的条件下转报 "always succeeds"：先转 NSObject 再用 CFGetTypeID 判断
func rkAsCGImage(_ v: Any?) -> CGImage? {
    guard let obj = v as? NSObject else { return nil }
    if CFGetTypeID(obj as CFTypeRef) != CGImage.typeID { return nil }
    return (obj as! CGImage)
}

// MARK: - 位图工具
func rkModeColor(buf: UnsafeMutablePointer<UInt8>, n: Int) -> UIColor? {
    var freq: [String: Int] = [:]
    var samp: [String: [Int]] = [:]
    for i in 0..<n {
        let a = buf[i * 4 + 3]
        if a < 250 { continue }
        let key = "\(buf[i * 4] / 8)_\(buf[i * 4 + 1] / 8)_\(buf[i * 4 + 2] / 8)"
        freq[key, default: 0] += 1
        if samp[key] == nil { samp[key] = [Int(buf[i * 4]), Int(buf[i * 4 + 1]), Int(buf[i * 4 + 2])] }
    }
    var best: String? = nil, bn = 0
    for (k, v) in freq { if v > bn { bn = v; best = k } }
    guard let b = best, let c = samp[b] else { return nil }
    return UIColor(red: CGFloat(c[0]) / 255.0, green: CGFloat(c[1]) / 255.0, blue: CGFloat(c[2]) / 255.0, alpha: 1.0)
}

func rkReplaceBlue(buf: UnsafeMutablePointer<UInt8>, n: Int, tr: CGFloat, tg: CGFloat, tb: CGFloat) -> Bool {
    var hits = 0
    for i in 0..<n {
        let a = buf[i * 4 + 3]
        if a == 0 { continue }
        let af = CGFloat(a) / 255.0
        if af <= 0 { continue }
        let r = (CGFloat(buf[i * 4]) / 255.0) / af
        let g = (CGFloat(buf[i * 4 + 1]) / 255.0) / af
        let b = (CGFloat(buf[i * 4 + 2]) / 255.0) / af
        if rkIsBluePixel(r, g, b) {
            buf[i * 4] = UInt8(tr * CGFloat(a))
            buf[i * 4 + 1] = UInt8(tg * CGFloat(a))
            buf[i * 4 + 2] = UInt8(tb * CGFloat(a))
            hits += 1
        }
    }
    return hits > 0
}

func rkImageFromBuf(_ buf: UnsafeMutablePointer<UInt8>, w: Int, h: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: kRKPremulLastBig)
    return ctx?.makeImage()
}

func rkRecolorContext(ctx: CGContext, target: UIColor) {
    guard let img = ctx.makeImage() else {
        rkDiag("drawLayer ctx.makeImage()=nil（无法从此 ctx 取图）")
        return
    }
    let w = Int(img.width), h = Int(img.height)
    guard w > 0, h > 0, w * h <= 900000 else { return }
    let bpr = w * 4
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
    memset(buf, 0, bpr * h)
    defer { buf.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs, bitmapInfo: kRKPremulLastBig) else { return }
    c.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
    guard target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) else { return }
    let changed = rkReplaceBlue(buf: buf, n: w * h, tr: tr, tg: tg, tb: tb)
    if changed {
        if let out = rkImageFromBuf(buf, w: w, h: h) {
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            ctx.draw(out, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            ctx.restoreGState()
        }
    } else {
        rkDiag("drawLayer 命中但键帽上已无蓝色像素（主方案已生效）")
    }
}

func rkModeColorFromCtx(_ ctx: CGContext) -> UIColor? {
    guard let img = ctx.makeImage() else { return nil }
    let w = Int(img.width), h = Int(img.height)
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
    memset(buf, 0, bpr * h)
    defer { buf.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs, bitmapInfo: kRKPremulLastBig) else { return nil }
    c.draw(img, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    return rkModeColor(buf: buf, n: w * h)
}

// MARK: - 取色
func rkVisualColor(view: UIView) -> UIColor? {
    let sz = view.bounds.size
    guard sz.width >= 6, sz.height >= 6 else { return nil }
    let W = 8, H = 8
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: W * H * 4)
    memset(buf, 0, W * H * 4)
    defer { buf.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                              space: cs, bitmapInfo: kRKPremulLastBig) else { return nil }
    ctx.scaleBy(x: CGFloat(W) / sz.width, y: CGFloat(H) / sz.height)
    view.layer.render(in: ctx)
    return rkModeColor(buf: buf, n: W * H)
}

func rkColorFromLayerTree(layer: CALayer?, depth: Int) -> UIColor? {
    guard let layer = layer, depth <= 4 else { return nil }
    if let c = rkAsCGImage(layer.contents) {
        let w = Int(c.width), h = Int(c.height)
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
        memset(buf, 0, bpr * h)
        defer { buf.deallocate() }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: cs, bitmapInfo: kRKPremulLastBig) else { return nil }
        ctx.draw(c, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        if let col = rkModeColor(buf: buf, n: w * h) { return col }
    }
    for sub in layer.sublayers ?? [] {
        if let col = rkColorFromLayerTree(layer: sub, depth: depth + 1) { return col }
    }
    return nil
}

func rkRecolorLayerTree(layer: CALayer?, target: UIColor, depth: Int) {
    guard let layer = layer, depth <= 5 else { return }
    if let c = rkAsCGImage(layer.contents) {
        let w = Int(c.width), h = Int(c.height)
        if w > 0, h > 0, w * h <= 600000 {
            let bpr = w * 4
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
            memset(buf, 0, bpr * h)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                      space: cs, bitmapInfo: kRKPremulLastBig) else { buf.deallocate(); return }
            ctx.draw(c, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            if target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta) {
                if rkReplaceBlue(buf: buf, n: w * h, tr: tr, tg: tg, tb: tb) {
                    if let out = rkImageFromBuf(buf, w: w, h: h) {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        layer.contents = out
                        CATransaction.commit()
                    }
                }
            }
            buf.deallocate()
        }
    }
    for sub in layer.sublayers ?? [] { rkRecolorLayerTree(layer: sub, target: target, depth: depth + 1) }
}

// MARK: - swizzle 工具
func rkSwizzle(cls: AnyClass, sel: Selector, block: Any) -> IMP? {
    guard let m = class_getInstanceMethod(cls, sel) else { return nil }
    let origIMP = method_getImplementation(m)
    let newIMP = imp_implementationWithBlock(block)
    let types = method_getTypeEncoding(m)
    var added = false
    if let t = types { added = class_addMethod(cls, sel, newIMP, t) }
    if !added { method_setImplementation(m, newIMP) }
    return origIMP
}

// MARK: - 各入口 hook
func rkHookDisplayLayer(cls: AnyClass) {
    let sel = Selector(("displayLayer:"))
    let imp = rkSwizzle(cls: cls, sel: sel, block: { (me: AnyObject, layer: CALayer) in
        gOrigDisplayLayer?(me, sel, layer)
        guard rkEnabled(), let color = gFuncColor, rkIsReturn(me) else { return }
        gCurReturnKey = me
        rkRecolorLayerTree(layer: layer, target: color, depth: 0)
        rkDiag("命中 UIKBKeyView.displayLayer:")
        gCurReturnKey = nil
    } as Any)
    if let imp = imp { gOrigDisplayLayer = unsafeBitCast(imp, to: ((AnyObject, Selector, CALayer) -> Void).self) }
}

func rkHookDrawLayer(cls: AnyClass) {
    let sel = Selector(("drawLayer:inContext:"))
    let imp = rkSwizzle(cls: cls, sel: sel, block: { (me: AnyObject, layer: CALayer, ctx: CGContext?) in
        gCurReturnKey = me
        gOrigDrawLayer?(me, sel, layer, ctx)
        guard rkEnabled() else { gCurReturnKey = nil; return }
        if rkIsMore(me), let c = ctx, gFuncColor == nil {
            if let col = rkModeColorFromCtx(c), !rkIsBlue(col) {
                gFuncColor = col
                gFuncColorStyle = currentStyle()
                rkDiag("取色(123键绘制中)=\(rkRGBStr(col))")
            }
        }
        if rkIsReturn(me), let c = ctx, let color = gFuncColor {
            rkRecolorContext(ctx: c, target: color)
            rkDiag("命中 UIKBKeyView.drawLayer:inContext:")
        }
        gCurReturnKey = nil
    } as Any)
    if let imp = imp { gOrigDrawLayer = unsafeBitCast(imp, to: ((AnyObject, Selector, CALayer, CGContext?) -> Void).self) }
}

func rkHookDidMoveToWindow(cls: AnyClass) {
    let sel = #selector(UIView.didMoveToWindow)
    let imp = rkSwizzle(cls: cls, sel: sel, block: { (me: AnyObject) in
        gOrigDidMove?(me, sel)
        if let v = me as? UIView, v.window != nil { rkTintFromKey(v) }
    } as Any)
    if let imp = imp { gOrigDidMove = unsafeBitCast(imp, to: ((AnyObject, Selector) -> Void).self) }
}

func rkHookLayoutSubviews(cls: AnyClass) {
    let sel = #selector(UIView.layoutSubviews)
    let imp = rkSwizzle(cls: cls, sel: sel, block: { (me: AnyObject) in
        gOrigLayout?(me, sel)
        if let v = me as? UIView { rkTintFromKey(v) }
    } as Any)
    if let imp = imp { gOrigLayout = unsafeBitCast(imp, to: ((AnyObject, Selector) -> Void).self) }
}

func rkHookDrawInContext(cls: AnyClass) {
    let sel = Selector(("drawInContext:"))
    let imp = rkSwizzle(cls: cls, sel: sel, block: { (me: AnyObject, ctx: CGContext?) in
        gOrigLayerDrawCtx?(me, sel, ctx)
        guard rkEnabled(), let color = gFuncColor, let c = ctx else { return }
        var kv: AnyObject? = nil
        if let d = (me as? CALayer)?.delegate, let kvc = gKeyViewCls, d.isKind(of: kvc) { kv = d }
        if kv == nil {
            var p = (me as? CALayer)?.superlayer
            while let pp = p {
                if let kvc = gKeyViewCls, pp.isKind(of: kvc) { kv = pp; break }
                p = pp.superlayer
            }
        }
        if kv == nil, let cur = gCurReturnKey { kv = cur }
        if let k = kv, rkIsReturn(k) {
            rkRecolorContext(ctx: c, target: color)
            rkDiag("命中 \(String(cString: class_getName(cls))).drawInContext:（delegate=UIKBKeyView）")
        }
    } as Any)
    if let imp = imp { gOrigLayerDrawCtx = unsafeBitCast(imp, to: ((AnyObject, Selector, CGContext?) -> Void).self) }
}

func rkInstallLayerHooks() {
    guard !gLayerHooksReady else { return }
    gLayerHooksReady = true
    guard rkEnabled() else { return }
    gKeyViewCls = NSClassFromString("UIKBKeyView") as? AnyClass
    var count: UInt32 = 0
    let list = objc_copyClassList(&count)
    guard list != nil else { return }
    let ptr = list!
    let layerCls = CALayer.self
    for i in 0..<Int(count) {
        let c = ptr[i]
        let nm = String(cString: class_getName(c))
        if !(nm.contains("KeyView") || nm.contains("KBKey")) { continue }
        if !(c.isSubclass(of: layerCls)) { continue }
        if c == layerCls { continue }
        if let kvc = gKeyViewCls, c == kvc { continue }
        rkHookDrawInContext(cls: c)
    }
    free(unsafeBitCast(ptr, to: UnsafeMutableRawPointer.self))
}

func rkInstallKeyViewHooks() {
    guard let cls = NSClassFromString("UIKBKeyView") as? AnyClass else { return }
    gKeyViewCls = cls
    rkHookDisplayLayer(cls: cls)
    rkHookDrawLayer(cls: cls)
    rkHookDidMoveToWindow(cls: cls)
    rkHookLayoutSubviews(cls: cls)
    rkInstallLayerHooks()
    rkDiag("已安装 UIKBKeyView 4 个 hook + 私有键帽图层 hook")
}

// MARK: - 诊断弹窗（独立 window，不依赖任何 rootViewController）
func rkShowDiagIfNeeded() {
    guard gDiagEnabled, !gDiagShown else { return }
    gDiagShown = true
    let body = gDiag.isEmpty ? "(无命中记录)" : gDiag.joined(separator: "\n")
    let msg = body + "\n123键色=" + (gFuncColor.map { rkRGBStr($0) } ?? "(nil)")
    DispatchQueue.main.async {
        let alert = UIAlertController(title: "键盘同色诊断", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        let screen = UIScreen.main ?? UIScreen()
        let win = UIWindow(frame: screen.bounds)
        win.rootViewController = UIViewController()
        win.windowLevel = .alert
        win.makeKeyAndVisible()
        gDiagWindow = win
        win.rootViewController?.present(alert, animated: true, completion: nil)
    }
}

// MARK: - 键收集 / 主流程
func rkCollectKeys(root: UIView) -> [UIView] {
    guard let kvc = gKeyViewCls else { return [] }
    var out: [UIView] = []
    var stack: [UIView] = [root]
    var guardCount = 0
    while !stack.isEmpty, guardCount < 4000 {
        guardCount += 1
        let v = stack.removeLast()
        if v.isKind(of: kvc) { out.append(v); continue }
        for s in v.subviews { stack.append(s) }
    }
    return out
}

func rkKeyboardRoot(_ key: UIView) -> UIView? {
    var v: UIView? = key
    while let cv = v {
        if NSStringFromClass(type(of: cv)).hasPrefix("UIKeyboardLayout") { return cv }
        v = cv.superview
    }
    return key.window
}

func rkForceRedraw(root: UIView) {
    var stack: [UIView] = [root]
    var g = 0
    while !stack.isEmpty, g < 3000 {
        g += 1
        let v = stack.removeLast()
        v.setNeedsDisplay()
        for s in v.subviews { stack.append(s) }
    }
    root.setNeedsLayout()
}

func rkTintFromKey(_ key: UIView) {
    guard rkEnabled() else { return }
    guard let root = rkKeyboardRoot(key) else { return }
    let now = Date.timeIntervalSinceReferenceDate
    let last = objc_getAssociatedObject(root, &kRKGenKey) as? NSNumber
    if let l = last, now - l.doubleValue < 0.4 { return }
    objc_setAssociatedObject(root, &kRKGenKey, NSNumber(value: now), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    DispatchQueue.main.async { rkTintKeyboard(root: root) }
}

func rkTintKeyboard(root: UIView) {
    guard rkEnabled() else { return }
    let keys = rkCollectKeys(root: root)
    guard !keys.isEmpty else { return }
    rkInstallLayerHooks()

    let style = currentStyle()
    if let _ = gFuncColor, gFuncColorStyle != style { gFuncColor = nil }

    if gFuncColor == nil {
        for kv in keys {
            guard rkIsMore(kv) else { continue }
            var c = rkVisualColor(view: kv)
            if c == nil { c = rkColorFromLayerTree(layer: kv.layer, depth: 0) }
            if let col = c, !rkIsBlue(col) {
                gFuncColor = col
                gFuncColorStyle = style
                rkDiag("取色(123键)=\(rkRGBStr(col))")
                break
            }
        }
    }
    if gFuncColor == nil {
        gFails += 1
        if gFails > 20 {
            gFuncColor = (style == .dark)
                ? UIColor(red: 0.357, green: 0.373, blue: 0.392, alpha: 1.0)
                : UIColor(red: 0.671, green: 0.690, blue: 0.729, alpha: 1.0)
            gFuncColorStyle = style
            rkDiag("取色失败改用兜底灰")
        } else {
            rkDiag("123键取色暂未成功(fails=\(gFails))")
            rkShowDiagIfNeeded()
            return
        }
    }

    let hasReturn = keys.contains { rkIsReturn($0) }
    let hasMore = keys.contains { rkIsMore($0) }
    rkDiag("keys=\(keys.count) 123键找到=\(hasMore) 回车键找到=\(hasReturn)")
    if let ret = keys.first(where: { rkIsReturn($0) }) {
        let dt = (ret as? NSObject)?.value(forKeyPath: "key.displayType")
        rkDiag("回车键 displayType=\(dt ?? "nil")")
    }
    if let ret = keys.first(where: { rkIsReturn($0) }) as? UIView, let lay = ret.layer as CALayer? {
        rkDiag("回车键 layer.contents=\((rkAsCGImage(lay.contents) != nil ? "有图" : "nil"))")
    }

    if let _ = gFuncColor {
        DispatchQueue.main.async { rkForceRedraw(root: root) }
    }
    rkShowDiagIfNeeded()
}

// MARK: - 入口（由 Tweak.m 的 constructor 调用）
@_cdecl("RKSetup")
func RKSetup() {
    rkInstallKeyViewHooks()
    NotificationCenter.default.addObserver(forName: UIApplication.didFinishLaunchingNotification,
                                          object: nil, queue: .main) { _ in
        rkInstallKeyViewHooks()
    }
}

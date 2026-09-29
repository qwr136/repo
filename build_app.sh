#!/usr/bin/env bash
# 构建独立设置 App（微信输入法自定义）并拷进 layout/Applications/，
# 使其随 Tweak 一起被打进同一个 rootless deb（/var/jb/Applications/WetypeCustomApp.app）。
set -euo pipefail

THEOS="${THEOS:-/opt/theos}"
export THEOS

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE="${1:-build}"

if [ "$MODE" = "clean" ]; then
    make -C wetypeapp clean >/dev/null 2>&1 || true
    rm -rf layout/Applications
    echo "cleaned standalone app"
    exit 0
fi

# 1) 编译 App（application.mk 会编译并 ldid 签名，entitlements 见 wetypeapp/entitlements.plist）
make -C wetypeapp FINALPACKAGE=1

# 2) 找到编译产物 .app（arm64 单切片，obj/ 或 obj/arm64/）
APPDIR=$(find wetypeapp/.theos -name "WetypeCustomApp.app" -type d | head -n1)
if [ -z "$APPDIR" ]; then
    echo "ERROR: WetypeCustomApp.app 编译后未找到" >&2
    exit 1
fi

# 3) 拷进 layout/Applications，stage 阶段会随 layout 一起打进 deb
rm -rf "layout/Applications/WetypeCustomApp.app"
mkdir -p "layout/Applications"
rsync -a "$APPDIR/" "layout/Applications/WetypeCustomApp.app/"
echo "staged app -> layout/Applications/WetypeCustomApp.app"

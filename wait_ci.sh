#!/bin/bash
# 轮询直到远端 build.log 的 RUN_SHA 等于期望的提交 SHA（避免 CI 多次运行交错导致的陈旧日志）
EXPECTED="$1"
if [ -z "$EXPECTED" ]; then echo "用法: $0 <期望的 git SHA>"; exit 2; fi
cd /tmp/repo
git fetch origin main >/dev/null 2>&1
for i in $(seq 1 40); do
  git fetch origin main >/dev/null 2>&1
  CUR=$(git log origin/main --oneline | grep -i "build log" | head -1 | awk '{print $1}')
  if [ -n "$CUR" ]; then
    # 看该 build-log 提交对应的 build.log 首行 RUN_SHA
    SHA=$(git show origin/main:build.log 2>/dev/null | head -1 | grep -E "^RUN_SHA=" | cut -d= -f2)
    if [ "$SHA" = "$EXPECTED" ]; then
      echo ">>> 检测到匹配期望 SHA($EXPECTED) 的 build-log 提交: $CUR"
      git pull --rebase origin main >/dev/null 2>&1
      echo ">>> 已拉取。提取关键结果："
      grep -nE "RUN_SHA|Xcode iPhoneOS SDK|_Concurrency|_StringProcessing|已复制|未找到|Assertion failed|signal |error:|packages/|\.deb|Making all|Compiling Tweak|Lipo" build.log | head -50
      echo "------ build.log 尾部（最后 30 行）------"
      tail -30 build.log
      exit 0
    fi
  fi
  echo "$(date +%H:%M:%S) 第 $i 次轮询：最新 build-log 的 RUN_SHA=$SHA（期望 $EXPECTED），等待 20s..."
  sleep 20
done
echo ">>> 超时：未出现匹配期望 SHA 的 build-log 提交"
git log origin/main --oneline -5
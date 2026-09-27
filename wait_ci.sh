#!/bin/bash
# 轮询等待 CI 把带诊断信息的 build.log 提交回仓库，然后拉取并打印关键诊断段
cd /tmp/repo
for i in $(seq 1 24); do
  git fetch origin main >/dev/null 2>&1
  # 看远端是否有比本地新的 "CI: build log" 提交
  NEWLOG=$(git log origin/main --oneline --since="5 minutes ago" 2>/dev/null | grep -i "build log" | head -1)
  if [ -n "$NEWLOG" ]; then
    echo ">>> 检测到新的 build.log 提交: $NEWLOG"
    git pull --rebase origin main >/dev/null 2>&1
    echo ">>> 已拉取，提取诊断信息："
    echo "============================================"
    sed -n '1,200p' build.log
    echo "============================================"
    exit 0
  fi
  echo "$(date +%H:%M:%S) 第 $i 次轮询：尚未出现 build.log 提交，等待 30s..."
  sleep 30
done
echo ">>> 超时：未检测到 build.log 提交"
git fetch origin main >/dev/null 2>&1
git log origin/main --oneline -5

#!/bin/bash
# 一键引导 StillEvolving 工作树
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# 找 Python：Windows 上可能是 python3 / py -3 / python，Linux 上通常只有 python3
PY=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done
if [ -z "$PY" ] && command -v py >/dev/null 2>&1; then
    PY="py -3"
fi
if [ -z "$PY" ]; then
    echo "ERROR: 找不到 Python 解释器（试过 python3 / python / py -3）" >&2
    exit 1
fi

echo "==> 初始化 submodule"
# 注意：绝不带 --recursive（会触发 reference 的 25 GB 递归拉取）
git submodule update --init

echo "==> 校验四仓一致性"
$PY scripts/check_consistency.py

echo "==> 完成"
echo "按需拉第三方库: bash scripts/fetch-reference.sh --tier core"

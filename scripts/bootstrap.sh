#!/bin/bash
# 一键引导 StillEvolving 工作树
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> 初始化 submodule"
# 注意：绝不带 --recursive（会触发 reference 的 25 GB 递归拉取）
git submodule update --init

echo "==> 校验四仓一致性"
python scripts/check_consistency.py

echo "==> 完成"
echo "按需拉第三方库: bash scripts/fetch-reference.sh --tier core"

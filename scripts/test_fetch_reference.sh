#!/bin/bash
# fetch-reference.sh 的行为契约测试
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FETCH="$SCRIPT_DIR/fetch-reference.sh"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# 用假 git 拦截，验证脚本不会真的去 clone
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<'GITEOF'
#!/bin/bash
# 记录调用并模拟成功
echo "git $@" >> "$GIT_CALL_LOG"
case "$*" in
  *"rev-parse HEAD"*) echo "${FAKE_HEAD:-}" ;;
esac
exit 0
GITEOF
chmod +x "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"
export GIT_CALL_LOG="$TMP/git-calls.log"
: > "$GIT_CALL_LOG"

echo "== T1: --check 不执行任何 git 操作 =="
OUT="$("$FETCH" --check 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "退出码 0" || bad "退出码 $RC，应为 0"
[ ! -s "$GIT_CALL_LOG" ] && ok "未调用 git" || bad "调用了 git: $(cat "$GIT_CALL_LOG")"

echo "== T2: broken 条目被跳过并告警 =="
OUT="$("$FETCH" --name druid 2>&1)"; RC=$?
echo "$OUT" | grep -qi "skip\|跳过\|pin.*broken\|broken" && ok "输出含 broken 告警" || bad "无告警: $OUT"
echo "$OUT" | grep -qi "druid" && ok "输出提到 druid" || bad "输出未提到 druid"

echo "== T3: --all 需要 --yes 二次确认 =="
OUT="$("$FETCH" --all 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "无 --yes 时拒绝执行" || bad "--all 竟然直接执行了"

echo "== T4: 未 init 的条目走 submodule init + 浅克隆，并校验是否落到 pinned commit =="
# 用临时的 reference 仓根，避免测试写脏真实仓（AUDIT.md）
FAKE_REF="$TMP/refroot"
mkdir -p "$FAKE_REF/reference/embedded/boltdb"
cp "${REFERENCE_ROOT:-$SCRIPT_DIR/../../reference}/reference/catalog.yml" "$FAKE_REF/reference/catalog.yml"

: > "$GIT_CALL_LOG"
export FAKE_HEAD="fd01fc79c553a8e99d512a07e8e0c63d4a3ccfc5"   # boltdb 的 pin
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name boltdb 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "落到 pin 时退出码 0" || bad "退出码 $RC，应为 0：$OUT"
echo "$OUT" | grep -qi "boltdb" && ok "输出提到 boltdb" || bad "输出未提到 boltdb"
grep -q "submodule init" "$GIT_CALL_LOG" && ok "调用了 submodule init" || bad "未调用 submodule init: $(cat "$GIT_CALL_LOG")"
grep -q "submodule update --depth 1" "$GIT_CALL_LOG" && ok "submodule update 带 --depth 1" || bad "submodule update 未带 --depth 1: $(cat "$GIT_CALL_LOG")"
grep -q "submodule.reference/embedded/boltdb.url https://github.com/boltdb/bolt.git" "$GIT_CALL_LOG" \
    && ok "submodule 的 url 被改成 catalog 的 clone_url" || bad "未改 clone_url: $(cat "$GIT_CALL_LOG")"

# HEAD 落到别的 commit 上时必须报失败 —— 证明脚本真的在校验 pin
: > "$GIT_CALL_LOG"
export FAKE_HEAD="0000000000000000000000000000000000000000"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name boltdb 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "未落到 pin 时退出码非 0" || bad "未落到 pin 却报成功：$OUT"
echo "$OUT" | grep -qi "pinned commit" && ok "报出未落到 pinned commit" || bad "未报 pin 不符：$OUT"
[ -f "$FAKE_REF/reference/AUDIT.md" ] && ok "失败已记入 AUDIT.md" || bad "失败未记入 AUDIT.md"

echo "== T5: 脚本内不含递归 submodule 初始化（G1：会拉 25 GB） =="
if grep -q -- "--recursive" "$FETCH"; then
    bad "脚本里出现了 --recursive"
else
    ok "脚本里没有 --recursive"
fi
if grep -q "update --init" "$FETCH"; then
    bad "脚本里出现了 update --init"
else
    ok "脚本里没有 update --init"
fi

echo
echo "通过 $PASS，失败 $FAIL"
[ $FAIL -eq 0 ]

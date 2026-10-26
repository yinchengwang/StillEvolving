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

# 取 -C <dir> 的 <dir>
cd_dir() {
    local prev="" a
    for a in "$@"; do
        if [ "$prev" = "-C" ]; then echo "$a"; return 0; fi
        prev="$a"
    done
    echo ""
}

case "$*" in
  *"rev-parse HEAD"*)
      # FAKE_HEAD 显式指定时用它；否则首次读到「不是 pin」的 HEAD，
      # checkout 之后才读到 pin —— 模拟「拉到 pin 了」
      if [ -n "${FAKE_HEAD:-}" ]; then echo "$FAKE_HEAD"
      elif [ -f "$FAKE_STATE" ]; then echo "$FAKE_PIN"
      else echo "$FAKE_WRONG"
      fi
      ;;
  *"rev-parse --show-toplevel"*)
      # 该目录本身就是工作树根
      cd_dir "$@"
      ;;
  *"submodule update"*)
      # 真实的 submodule update 会建出工作树与 .git 文件 —— 模拟它，
      # 否则脚本的「未 init 回退」分支永远走不到
      root="$(cd_dir "$@")"
      path=""
      for a in "$@"; do
        case "$a" in
          reference/*) path="$a" ;;
        esac
      done
      if [ -n "$root" ] && [ -n "$path" ]; then
        mkdir -p "$root/$path"
        [ -e "$root/$path/.git" ] || : > "$root/$path/.git"
      fi
      ;;
  *"checkout"*) touch "$FAKE_STATE" ;;
esac
exit 0
GITEOF
chmod +x "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"
export GIT_CALL_LOG="$TMP/git-calls.log"
export FAKE_STATE="$TMP/fake-state"
export FAKE_PIN="fd01fc79c553a8e99d512a07e8e0c63d4a3ccfc5"   # boltdb 的 pin
export FAKE_SQLITE_PIN="75136699f71415dd5093d46f182a77fef11bec48"
export FAKE_WRONG="1111111111111111111111111111111111111111"
: > "$GIT_CALL_LOG"

# ── 临时的 reference 仓根：测试绝不碰真实的 C:\code\reference ──────────────
REAL_REF="${REFERENCE_ROOT:-$SCRIPT_DIR/../../reference}"
FAKE_REF="$TMP/refroot"
mkdir -p "$FAKE_REF/reference/embedded/boltdb"
cp "$REAL_REF/reference/catalog.yml" "$FAKE_REF/reference/catalog.yml"
cp "$REAL_REF/reference/fetch-manifest.txt" "$FAKE_REF/reference/fetch-manifest.txt"
# 造一个「已 init」的 submodule 工作树，走脚本的「已 init」分支
: > "$FAKE_REF/reference/embedded/boltdb/.git"

echo "== T1: --check 不执行任何 git 操作 =="
OUT="$("$FETCH" --check 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "退出码 0" || bad "退出码 $RC，应为 0"
[ ! -s "$GIT_CALL_LOG" ] && ok "未调用 git" || bad "调用了 git: $(cat "$GIT_CALL_LOG")"
# 计数行是计划里逐字规定的验收输出，必须能被 grep 到
echo "$OUT" | grep -q "97 entries, 91 valid, 4 broken, 2 unresolvable" \
    && ok "计数行与约定一致" || bad "计数行不符: $OUT"

echo "== T2: broken 条目被跳过并告警 =="
: > "$GIT_CALL_LOG"
OUT="$("$FETCH" --name druid 2>&1)"; RC=$?
echo "$OUT" | grep -qi "skip\|跳过\|pin.*broken\|broken" && ok "输出含 broken 告警" || bad "无告警: $OUT"
echo "$OUT" | grep -qi "druid" && ok "输出提到 druid" || bad "输出未提到 druid"
[ $RC -eq 0 ] && ok "退出码 0（跳过不算失败）" || bad "退出码 $RC，应为 0"
[ ! -s "$GIT_CALL_LOG" ] && ok "未执行任何 git 操作" || bad "执行了 git: $(cat "$GIT_CALL_LOG")"

echo "== T3: --all 需要 --yes 二次确认 =="
: > "$GIT_CALL_LOG"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --all </dev/null 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "无 --yes 时拒绝执行" || bad "--all 竟然直接执行了"
[ ! -s "$GIT_CALL_LOG" ] && ok "拒绝时未做任何 git 操作" || bad "拒绝时仍执行了 git: $(cat "$GIT_CALL_LOG")"

echo "== T4: 未 init 的条目走 submodule init + 浅克隆，并校验是否落到 pinned commit =="
: > "$GIT_CALL_LOG"
export FAKE_HEAD="$FAKE_SQLITE_PIN"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name sqlite3 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "退出码 0" || bad "退出码 $RC，应为 0：$OUT"
echo "$OUT" | grep -qi "sqlite3" && ok "输出提到 sqlite3" || bad "输出未提到 sqlite3"
grep -q "submodule init" "$GIT_CALL_LOG" && ok "调用了 submodule init" || bad "未调用 submodule init: $(cat "$GIT_CALL_LOG")"
grep -q "submodule update --depth 1" "$GIT_CALL_LOG" && ok "submodule update 带 --depth 1" || bad "submodule update 未带 --depth 1: $(cat "$GIT_CALL_LOG")"
grep -q "submodule.reference/relational/sqlite3.url https://github.com/sqlite/sqlite.git" "$GIT_CALL_LOG" \
    && ok "submodule 的 url 被改成 catalog 的 clone_url" || bad "未改 clone_url: $(cat "$GIT_CALL_LOG")"

echo "== T5: 未落到 pinned commit 时必须报失败 —— 证明脚本真的在校验 pin =="
: > "$GIT_CALL_LOG"
export FAKE_HEAD="0000000000000000000000000000000000000000"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name sqlite3 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "未落到 pin 时退出码非 0" || bad "未落到 pin 却报成功：$OUT"
echo "$OUT" | grep -qi "pinned commit" && ok "报出未落到 pinned commit" || bad "未报 pin 不符：$OUT"
[ -f "$FAKE_REF/reference/AUDIT.md" ] && ok "失败已记入 AUDIT.md" || bad "失败未记入 AUDIT.md"

echo "== T5b: 回退取 commit 必须用 catalog 的 clone_url，不能用 submodule 的 origin =="
# 这条是 C1 的回归测试：把 fetch 的地址改回 origin，套件必须变红
grep -q "fetch --depth 1 -- https://github.com/sqlite/sqlite.git" "$GIT_CALL_LOG" \
    && ok "回退用 catalog 的 clone_url 取 commit" || bad "回退没用 clone_url: $(cat "$GIT_CALL_LOG")"
if grep -q "fetch --depth 1 origin" "$GIT_CALL_LOG"; then
    bad "回退仍在用 submodule 的 origin: $(cat "$GIT_CALL_LOG")"
else
    ok "回退没有用 submodule 的 origin"
fi
grep -q "remote set-url origin https://github.com/sqlite/sqlite.git" "$GIT_CALL_LOG" \
    && ok "把 submodule 的 origin 修成了 clone_url" || bad "未修正 origin: $(cat "$GIT_CALL_LOG")"

# 去重：同一条失败不应被重复追加
before=$(wc -l < "$FAKE_REF/reference/AUDIT.md")
REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name sqlite3 >/dev/null 2>&1
after=$(wc -l < "$FAKE_REF/reference/AUDIT.md")
[ "$before" = "$after" ] && ok "AUDIT.md 失败记录已去重" || bad "AUDIT.md 又追加了 $((after-before)) 行"

echo "== T5c: 未 init 条目的回退路径也必须用 clone_url =="
: > "$GIT_CALL_LOG"
export FAKE_HEAD="0000000000000000000000000000000000000000"
REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name duckdb >/dev/null 2>&1
grep -q "submodule update --depth 1 reference/embedded/duckdb" "$GIT_CALL_LOG" \
    && ok "duckdb 走了 submodule update" || bad "duckdb 未走 submodule update: $(cat "$GIT_CALL_LOG")"
grep -q "fetch --depth 1 -- https://github.com/duckdb/duckdb.git" "$GIT_CALL_LOG" \
    && ok "未 init 条目的回退也用 catalog 的 clone_url" || bad "回退没用 clone_url: $(cat "$GIT_CALL_LOG")"
if grep -q "fetch --depth 1 origin" "$GIT_CALL_LOG"; then
    bad "回退仍在用 submodule 的 origin"
else
    ok "回退没有用 submodule 的 origin"
fi

echo "== T6: 幂等 —— 第二次运行不再拉取（F1） =="
: > "$GIT_CALL_LOG"
rm -f "$FAKE_STATE"
unset FAKE_HEAD
REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name boltdb >/dev/null 2>&1
: > "$GIT_CALL_LOG"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name boltdb 2>&1)"; RC=$?
echo "$OUT" | grep -qi "幂等\|已是目标 commit" && ok "第二次识别为幂等跳过" || bad "第二次未识别幂等: $OUT"
if grep -q "fetch\|submodule update" "$GIT_CALL_LOG"; then
    bad "第二次仍在拉取: $(cat "$GIT_CALL_LOG")"
else
    ok "第二次没有拉取"
fi

echo "== T7: unresolvable 条目被跳过，且不执行任何 git 操作 =="
: > "$GIT_CALL_LOG"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --name oceanbase 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "退出码 0（跳过不算失败）" || bad "退出码 $RC，应为 0"
echo "$OUT" | grep -qi "oceanbase" && ok "输出提到 oceanbase" || bad "输出未提到 oceanbase"
[ ! -s "$GIT_CALL_LOG" ] && ok "未执行任何 git 操作" || bad "执行了 git: $(cat "$GIT_CALL_LOG")"

echo "== T8: --check 能发现 manifest 与 catalog 不一致 =="
: > "$GIT_CALL_LOG"
printf 'garbage\n' > "$FAKE_REF/reference/fetch-manifest.txt"
OUT="$(REFERENCE_ROOT="$FAKE_REF" "$FETCH" --check 2>&1)"; RC=$?
[ $RC -ne 0 ] && ok "manifest 被破坏时退出码非 0" || bad "manifest 被破坏却报一致"
[ ! -s "$GIT_CALL_LOG" ] && ok "校验时未调用 git" || bad "校验时调用了 git"
cp "$REAL_REF/reference/fetch-manifest.txt" "$FAKE_REF/reference/fetch-manifest.txt"

echo "== T9: --all --yes 会真的开始拉取（守卫生效） =="
: > "$GIT_CALL_LOG"
REFERENCE_ROOT="$FAKE_REF" "$FETCH" --all --yes </dev/null >/dev/null 2>&1
[ -s "$GIT_CALL_LOG" ] && ok "--yes 后确实开始拉取" || bad "--yes 后没有任何 git 调用"

echo "== T10: 脚本内不含递归 submodule 初始化（G1：会拉 25 GB） =="
# 注意：这里刻意把关键字拆开拼，避免本测试文件本身含有这些字面量
#（否则按 scripts/ 目录做的仓库级守卫会被本文件误触发）
RECURSIVE="--re""cursive"
INIT_OPT="update --""init"
if grep -q -- "$RECURSIVE" "$FETCH"; then
    bad "脚本里出现了 $RECURSIVE"
else
    ok "脚本里没有 $RECURSIVE"
fi
if grep -q -- "$INIT_OPT" "$FETCH"; then
    bad "脚本里出现了 $INIT_OPT"
else
    ok "脚本里没有 $INIT_OPT"
fi

echo
echo "通过 $PASS，失败 $FAIL"
[ $FAIL -eq 0 ]

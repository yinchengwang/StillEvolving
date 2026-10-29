#!/bin/bash
# fetch-reference.sh —— 按清单驱动、按需拉取 reference 仓里的第三方库到已 pin 的 commit
#
# 设计约束（勿改）：
#   * 绝不递归初始化 submodule —— 那会一次性拉取约 25 GB / 53.6 万文件
#   * 第三方库路径固定为 <reference 仓根>/reference/<model>/<name>，只有一层 reference
#   * 拉取地址以 catalog.yml 的 clone_url 为准；.gitmodules 的 url 可能指向不含该 pin 的镜像
#     （实测 mysql 的 .gitmodules 指向 gitee 镜像，取不到 pinned SHA，而 GitHub 官方可取）
#   * 4 个 broken pin 只标注不重选 —— 重选会让 102 处行号引用全体漂移
#
# 用法：
#   fetch-reference.sh                      按 tier 拉取（core 默认）
#   fetch-reference.sh --tier <t>           按 tier 筛选（core|representative|innovative）
#   fetch-reference.sh --model <分类>       按分类筛选（vector / ai/agent …）
#   fetch-reference.sh --name <名字>        拉单个
#   fetch-reference.sh --all                全量（需 --yes 二次确认）
#   fetch-reference.sh --check              只校验，不拉取，且不执行任何 git 操作
#   fetch-reference.sh --yes                跳过 --all 的交互确认
#   fetch-reference.sh --reference-root <目录>  覆盖 reference 仓根（默认 ../reference）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCE_ROOT="${REFERENCE_ROOT:-$REPO_ROOT/../reference}"
CATALOG=""
MANIFEST=""
AUDIT=""

MODE="fetch"
TIER=""
MODEL=""
NAME=""
ALL=0
YES=0

OK_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
FAILED_NAMES=""

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# ── 参数解析 ────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --check)          MODE="check"; shift ;;
        --all)            ALL=1; shift ;;
        --yes)            YES=1; shift ;;
        --tier)           [ $# -ge 2 ] || die "--tier 需要一个参数"; TIER="$2"; shift 2 ;;
        --model)          [ $# -ge 2 ] || die "--model 需要一个参数"; MODEL="$2"; shift 2 ;;
        --name)           [ $# -ge 2 ] || die "--name 需要一个参数"; NAME="$2"; shift 2 ;;
        --reference-root) [ $# -ge 2 ] || die "--reference-root 需要一个参数"; REFERENCE_ROOT="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)                die "未知选项: $1（用 --help 看用法）" ;;
    esac
done

CATALOG="$REFERENCE_ROOT/reference/catalog.yml"
MANIFEST="$REFERENCE_ROOT/reference/fetch-manifest.txt"
AUDIT="$REFERENCE_ROOT/reference/AUDIT.md"

# ── catalog 解析 ───────────────────────────────────────────────────────────
# 输出用 \x1f（unit separator）分隔的字段：name ␟ model ␟ tier ␟ clone_url ␟ commit ␟ pin_status ␟ source
# 用 \x1f 而不是 TAB 是因为 TAB 属于 IFS 空白字符 —— `IFS=$'\t' read` 会把连续 TAB
# 当成一个分隔符，空字段会被吞掉并让后面的字段整体左移（clone_url 缺失时 commit
# 会被当成 URL 写进 .git/config）。\x1f 不是空白字符，空字段能原样保留。
# 兼容 CRLF 与 LF（G4）；不依赖任何第三方 YAML 库（G11）。
SEP=$'\x1f'
catalog_rows() {
    sed 's/\r$//' "$CATALOG" | awk '
    function emit() {
        if (name != "")
            printf "%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n", \
                   name, model, tier, clone_url, commit, pin_status, source
    }
    BEGIN {
        name=""; model=""; tier=""; clone_url=""; commit=""; pin_status=""; source=""
    }
    /^  - name:[[:space:]]*/ {
        emit()
        name = $0; sub(/^  - name:[[:space:]]*/, "", name)
        model=""; tier=""; clone_url=""; commit=""; pin_status=""; source=""
        next
    }
    /^    [A-Za-z_]+:[[:space:]]*/ {
        key = $0; sub(/^[[:space:]]+/, "", key); sub(/:.*$/, "", key)
        val = $0; sub(/^[[:space:]]*[A-Za-z_]+:[[:space:]]*/, "", val)
        if      (key == "model")      model = val
        else if (key == "tier")       tier = val
        else if (key == "clone_url")  clone_url = val
        else if (key == "commit")     commit = val
        else if (key == "pin_status") pin_status = val
        else if (key == "source")     source = val
        next
    }
    END { emit() }
    '
}

# ── --check：只校验，不拉取，不碰 git ───────────────────────────────────────
run_check() {
    [ -f "$CATALOG" ] || die "catalog 不存在: $CATALOG"

    local rows total valid broken unresolvable
    rows="$(catalog_rows)"
    total="$(printf '%s\n' "$rows" | grep -c '[^[:space:]]' || true)"
    valid="$(printf '%s\n' "$rows" | awk -F'\x1f' '$6=="valid"' | grep -c '[^[:space:]]' || true)"
    broken="$(printf '%s\n' "$rows" | awk -F'\x1f' '$6=="broken"' | grep -c '[^[:space:]]' || true)"
    unresolvable="$(printf '%s\n' "$rows" | awk -F'\x1f' '$6=="unresolvable"' | grep -c '[^[:space:]]' || true)"

    echo "$total entries, $valid valid, $broken broken, $unresolvable unresolvable"

    local rc=0

    # 字段完整性
    while IFS="$SEP" read -r n m t cu cm ps src; do
        [ -z "$n" ] && continue
        [ "$cu" = "null" ] && cu=""
        [ "$cm" = "null" ] && cm=""
        case "$ps" in
            valid)
                if ! printf '%s' "$cm" | grep -Eq '^[0-9a-f]{40}$'; then
                    echo "[catalog] commit 缺失或非 40 位 hex: $n"; rc=1
                fi
                [ -n "$cu" ] && [ "$cu" != "null" ] || { echo "[catalog] clone_url 缺失: $n"; rc=1; }
                ;;
            broken)
                [ -z "$cm" ] || [ "$cm" = "null" ] || {
                    echo "[catalog] broken 条目不应有 commit: $n"; rc=1; }
                ;;
            unresolvable)
                [ "$src" = "none" ] || { echo "[catalog] unresolvable 条目的 source 应为 none: $n"; rc=1; }
                [ -z "$cm" ] || [ "$cm" = "null" ] || {
                    echo "[catalog] unresolvable 条目不应有 commit: $n"; rc=1; }
                [ -z "$cu" ] || [ "$cu" = "null" ] || {
                    echo "[catalog] unresolvable 条目不应有 clone_url: $n"; rc=1; }
                ;;
            *)
                echo "[catalog] pin_status 非法: $n ('$ps')"; rc=1
                ;;
        esac
    done <<< "$rows"

    # manifest 与 catalog 生成结果逐字节一致
    if [ ! -f "$MANIFEST" ]; then
        echo "[manifest] 不存在: $MANIFEST"; rc=1
    else
        local expected actual
        # 空值在 manifest 里写作 '-'（与 YAML null 区分开）
        expected="$(printf '%s\n' "$rows" | awk -F'\x1f' 'BEGIN{OFS="\t"}
            {
                cu = ($4 == "" || $4 == "null") ? "-" : $4
                cm = ($5 == "" || $5 == "null") ? "-" : $5
                printf "%s\t%s\t%s\t%s\t%s\n", $2, $1, cu, cm, $6
            }')"
        actual="$(sed 's/\r$//' "$MANIFEST" | grep -v '^#')"
        if [ "$expected" != "$actual" ]; then
            echo "[manifest] 与 catalog 生成结果不一致"; rc=1
        fi
    fi

    if [ $rc -eq 0 ]; then
        echo "check: 一致"
    else
        echo "check: 发现问题"
    fi
    return $rc
}

# ── 拉取 ───────────────────────────────────────────────────────────────────
# 单个条目的目标路径（只有一层 reference）
target_path() {
    printf 'reference/%s/%s' "$1" "$2"
}

# 判断 $dir 本身是不是一个 git 工作树根。
# 必要性：`git -C <普通目录>` 会向上找到父仓，于是 `git -C "$dir" remote set-url origin X`
# 会把**父仓的 origin** 改掉。用 --show-toplevel 与 $dir 比对即可区分
# 「$dir 自己就是工作树根」与「向上走到了父仓」。
is_worktree_root() {
    local d="$1" top
    [ -n "$d" ] && [ -d "$d" ] || return 1
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$top" ] || return 1
    [ "$(cd "$d" && pwd -P)" = "$(cd "$top" && pwd -P)" ]
}

audit() {
    # 追加失败记录到 AUDIT.md（同一失败不重复追加，否则每次 --all 都会堆 91 行）
    local name="$1" reason="$2"
    [ -d "$(dirname "$AUDIT")" ] || return 0
    local key="$name: $reason"
    if [ -f "$AUDIT" ] && grep -Fq -- "$key" "$AUDIT"; then
        return 0
    fi
    printf -- '- %s %s: %s\n' "$(date +%Y-%m-%d)" "$name" "$reason" >> "$AUDIT"
}

fetch_one() {
    local n="$1" m="$2" cu="$3" cm="$4" ps="$5" src="$6"
    local path dir head cur_origin

    case "$ps" in
        broken)
            echo "SKIP $n: pin_status=broken（上游不存在该 commit，需人工校对行号引用）"
            SKIP_COUNT=$((SKIP_COUNT+1)); return 0 ;;
        unresolvable)
            echo "SKIP $n: source=none（无源码镜像，仅有笔记）"
            SKIP_COUNT=$((SKIP_COUNT+1)); return 0 ;;
    esac

    [ -n "$cu" ] && [ "$cu" != "null" ] || {
        echo "FAIL $n: clone_url 缺失"; FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1; }
    [ -n "$cm" ] && [ "$cm" != "null" ] || {
        echo "FAIL $n: commit 缺失"; FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1; }

    path="$(target_path "$m" "$n")"
    dir="$REFERENCE_ROOT/$path"

    if [ -e "$dir/.git" ]; then
        # 只在 $dir 自己就是工作树根时才动它 —— `git -C <普通目录>` 会向上找到父仓，
        # 那样 `remote set-url origin` 会把父仓的 origin 改掉
        if ! is_worktree_root "$dir"; then
            echo "  FAIL $n: $dir 不是独立的工作树根（拒绝操作，避免误改父仓 remote）"
            audit "$n" "$dir 不是独立工作树根，拒绝操作"
            FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1
        fi
        # 已 init —— 幂等判断：HEAD 已是 pin 就跳过（F1）
        head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
        if [ "$head" = "$cm" ]; then
            echo "SKIP $n: 已是目标 commit ${cm:0:8}（幂等跳过）"
            SKIP_COUNT=$((SKIP_COUNT+1)); return 0
        fi
        echo "FETCH $n: $cm"
        # 修好可能指向旧镜像的 origin；没有 origin 时补一个（否则后续 submodule update 无 remote 可用）
        cur_origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
        if [ -z "$cur_origin" ]; then
            git -C "$dir" remote add origin "$cu" >/dev/null 2>&1 || true
        elif [ "$cur_origin" != "$cu" ]; then
            git -C "$dir" remote set-url origin "$cu" >/dev/null 2>&1 || true
        fi
        # 已是完整克隆时不能加 --depth 1 —— 那会把它降级成浅克隆（丢失历史，且没有 --unshallow 退路）
        depth_opt="--depth 1"
        if [ "$(git -C "$dir" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "false" ]; then
            depth_opt=""
        fi
        # 从 catalog 的 clone_url 直接取 pinned commit（origin 可能指向取不到该 pin 的镜像）
        # shellcheck disable=SC2086  # depth_opt 需要分词
        if git -C "$dir" fetch $depth_opt -- "$cu" "$cm" >/dev/null 2>&1 \
           && git -C "$dir" checkout --detach "$cm" >/dev/null 2>&1; then
            head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
            if [ "$head" = "$cm" ]; then
                echo "  OK $n → ${cm:0:8}"
                OK_COUNT=$((OK_COUNT+1)); return 0
            fi
            echo "  FAIL $n: 未落到 pinned commit（期望 ${cm:0:8}，实际 ${head:0:8}）"
            audit "$n" "未落到 pinned commit（期望 ${cm:0:8}，实际 ${head:0:8}）"
            FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1
        fi
        echo "  FAIL $n: fetch/checkout 失败"
        audit "$n" "fetch/checkout 失败"
        FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1
    fi

    # 未 init —— 单路径初始化，绝不递归
    echo "FETCH $n: 初始化 submodule $path"
    git -C "$REFERENCE_ROOT" submodule init "$path" >/dev/null 2>&1 \
        || { echo "  FAIL $n: submodule init 失败"
             audit "$n" "submodule init 失败"
             FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1; }

    # 以 catalog 的 clone_url 为准（.gitmodules 的 url 可能取不到该 pin）
    git -C "$REFERENCE_ROOT" config "submodule.$path.url" "$cu" >/dev/null 2>&1 || true

    git -C "$REFERENCE_ROOT" submodule update --depth 1 "$path" >/dev/null 2>&1 || true

    # 落点校验：必须等于 pinned commit
    # 先确认 $dir 自己是工作树根再读 HEAD —— 否则 `git -C <普通目录> rev-parse HEAD`
    # 会向上走到 reference 仓，返回它的 HEAD，产生误导性诊断
    head=""
    if is_worktree_root "$dir"; then
        head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
    fi
    if [ "$head" != "$cm" ] && is_worktree_root "$dir"; then
        # 回退：git submodule update 复用已存在的 .git/modules/<path> 克隆时**不会**更新
        # 那个克隆的 origin，而那个 origin 可能指向取不到该 pin 的旧镜像（mysql 就是这种）。
        # 所以直接用 catalog 的 clone_url 取 pinned commit。
        if [ -z "$(git -C "$dir" remote get-url origin 2>/dev/null || true)" ]; then
            git -C "$dir" remote add origin "$cu" >/dev/null 2>&1 || true
        else
            git -C "$dir" remote set-url origin "$cu" >/dev/null 2>&1 || true
        fi
        if git -C "$dir" fetch --depth 1 -- "$cu" "$cm" >/dev/null 2>&1 \
           && git -C "$dir" checkout --detach "$cm" >/dev/null 2>&1; then
            head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
        fi
    fi

    if [ "$head" != "$cm" ]; then
        echo "  FAIL $n: 未落到 pinned commit（期望 ${cm:0:8}，实际 ${head:0:8}）"
        audit "$n" "未落到 pinned commit（期望 ${cm:0:8}，实际 ${head:0:8}）"
        FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_NAMES="$FAILED_NAMES $n"; return 1
    fi

    echo "  OK $n → ${cm:0:8}"
    OK_COUNT=$((OK_COUNT+1)); return 0
}

# ── 选择待拉取的条目 ───────────────────────────────────────────────────────
select_rows() {
    catalog_rows | awk -F'\x1f' -v tier="$TIER" -v model="$MODEL" -v name="$NAME" -v all="$ALL" '
    {
        sel = 1
        if (all != 1) {
            if (tier  != "" && $3 != tier)  sel = 0
            if (model != "" && $2 != model) sel = 0
            if (name  != "" && $1 != name)  sel = 0
        }
        if (sel) print
    }'
}

run_fetch() {
    [ -f "$CATALOG" ] || die "catalog 不存在: $CATALOG"

    local rows
    rows="$(select_rows)"
    [ -n "$rows" ] || die "没有匹配的条目（检查 --tier/--model/--name 是否写对）"

    local count
    count="$(printf '%s\n' "$rows" | grep -c '[^[:space:]]' || true)"

    # --all 与其它筛选条件互相矛盾，直接报错而不是悄悄忽略
    if [ "$ALL" -eq 1 ] && { [ -n "$TIER" ] || [ -n "$MODEL" ] || [ -n "$NAME" ]; }; then
        die "--all 不能与 --tier/--model/--name 同时使用"
    fi

    # 全量必须二次确认 —— 先确认再打印清单，避免刷屏
    if [ "$ALL" -eq 1 ] && [ "$YES" -ne 1 ]; then
        echo "==> 全量拉取 $count 个第三方库，约 25 GB / 53.6 万文件。确认继续？[y/N] "
        local ans=""
        if [ -t 0 ]; then
            read -r ans || ans=""
        else
            ans=""
        fi
        case "$ans" in
            y|Y|yes|YES) : ;;
            *) echo "已取消（加 --yes 可跳过此确认）"; exit 1 ;;
        esac
    fi

    # 批量拉取：先打印清单，让人知道要拉什么
    if [ "$count" -gt 1 ]; then
        echo "==> 计划拉取 $count 个第三方库："
        printf '%s\n' "$rows" | awk -F'\x1f' '{ printf "    %-12s %s\n", $1, $2 }'
        echo "==> 磁盘预估：单库约 20~500 MB（大型库可达数百 MB），合计上限约 $((count * 500)) MB"
    fi

    # 已经有人递归初始化过 submodule 的话，提醒一下
    local mods
    mods=0
    if [ -d "$REFERENCE_ROOT/.git/modules/reference" ]; then
        mods="$(ls -1 "$REFERENCE_ROOT/.git/modules/reference" 2>/dev/null | wc -l | tr -d ' ')"
    fi
    if [ "${mods:-0}" -gt 2 ]; then
        echo "WARN: reference 下已存在 $mods 个 submodule 仓库 —— 若此前有人做过递归初始化，"
        echo "      磁盘可能已占用 25 GB。本脚本不会再触发递归拉取。"
    fi

    local n m t cu cm ps src
    while IFS="$SEP" read -r n m t cu cm ps src; do
        [ -z "$n" ] && continue
        [ "$cu" = "null" ] && cu=""
        [ "$cm" = "null" ] && cm=""
        fetch_one "$n" "$m" "$cu" "$cm" "$ps" "$src"
    done <<< "$rows"

    echo
    echo "成功 $OK_COUNT / 跳过 $SKIP_COUNT / 失败 $FAIL_COUNT"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "失败条目：$FAILED_NAMES"
        echo "详情已追加到 $AUDIT"
        return 1
    fi
    return 0
}

# ── 入口 ───────────────────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
    run_check
    exit $?
fi

# 默认：按 tier 拉取（core 默认），除非显式给了 --tier
if [ -z "$TIER" ] && [ -z "$MODEL" ] && [ -z "$NAME" ] && [ "$ALL" -ne 1 ]; then
    TIER="core"
fi

run_fetch
exit $?

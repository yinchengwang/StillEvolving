#!/usr/bin/env python3
"""四仓一致性校验：repos.yaml ↔ 实际目录 ↔ catalog.yml ↔ .gitmodules。

设计要点
--------
* 只用标准库（G11：环境无 PyYAML），repos.yaml 结构规整，手写解析足够。
* 跨仓加载 reference 仓的 sync_catalog.py 时**按文件路径加载**
  （``importlib.util.spec_from_file_location``）—— 不同仓不在同一 sys.path 上。
* Ruling 20：``upstream.manifest`` / ``upstream.lockfile`` 相对 **reference 仓根**解析；
  ``upstream.script`` 相对 **父仓根**解析。同级三个字段的路径基准不同，靠代码消歧。
* ``must_contain`` 是**子集断言**：列出的每一项都必须存在，仓里多出的不算违规。
* catalog 条目数是 97，但其中 oceanbase / pklite 无源码镜像（``source: none``）——
  校验用 ``source: mirror`` 的计数（95），不是总数（G16）。

退出码：0 = 全部一致；1 = 有问题。
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

PIN_STATUSES = ("valid", "broken", "unresolvable")
SOURCES = ("mirror", "none")


# ── YAML 子集解析 ─────────────────────────────────────────────────────────
def _scalar(raw):
    """标量值 -> 字符串（YAML null 记为 None）。"""
    value = raw.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    if value in ("null", "Null", "NULL", "~", ""):
        return None
    return value


def _inline_list(raw):
    """解析行内列表 ``[a, b, c]``。"""
    body = raw.strip()
    if body.startswith("["):
        body = body[1:]
    if body.endswith("]"):
        body = body[:-1]
    items = []
    for part in body.split(","):
        part = part.strip()
        if part:
            items.append(_scalar(part))
    return items


def _parse_nodes(lines, i, indent):
    """解析从第 i 行起、缩进 >= indent 的节点。

    返回 (值, 下一行索引)。值是 dict 或 list。
    """
    result = None
    while i < len(lines):
        raw = lines[i]
        if not raw.strip() or raw.lstrip().startswith("#"):
            i += 1
            continue
        ind = len(raw) - len(raw.lstrip())
        if ind < indent:
            break
        s = raw.strip()

        # 列表项：- key: value  或  - 标量
        if s.startswith("- "):
            if result is None:
                result = []
            if not isinstance(result, list):
                break
            item_text = s[2:].strip()
            i += 1
            if ":" in item_text:
                key, _, val = item_text.partition(":")
                item = {key.strip(): _scalar(val.strip())}
                sub, i = _parse_nodes(lines, i, ind + 2)
                if isinstance(sub, dict):
                    item.update(sub)
                result.append(item)
            else:
                result.append(_scalar(item_text))
            continue

        # 映射项：key: value
        if result is None:
            result = {}
        if not isinstance(result, dict):
            break
        key, _, val = s.partition(":")
        key, val = key.strip(), val.strip()
        if val == "":
            i += 1
            sub, i = _parse_nodes(lines, i, ind + 1)
            result[key] = sub if sub is not None else {}
        elif val in ("|", ">"):
            i += 1
            buf = []
            while i < len(lines):
                row = lines[i]
                if not row.strip():
                    buf.append("")
                    i += 1
                    continue
                if len(row) - len(row.lstrip()) <= ind:
                    break
                buf.append(row.strip())
                i += 1
            result[key] = "\n".join(buf).strip("\n")
        elif val.startswith("["):
            result[key] = _inline_list(val)
            i += 1
        else:
            result[key] = _scalar(val)
            i += 1
    return result, i


def parse_repos(text):
    """解析 repos.yaml，返回仓列表。

    必须能处理行内列表 ``must_contain: [a, b, c]``、嵌套映射（``upstream:``）、
    列表（``known_duplication:``）、块标量（``notes: |``），
    并保留 ``path`` 的 ``../`` 前缀（reference 用的就是 ``../reference``）。
    """
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    doc, _ = _parse_nodes(lines, 0, 0)
    if not isinstance(doc, dict):
        return []
    repos = doc.get("repos")
    return repos if isinstance(repos, list) else []


def check_must_contain(repo_path, must):
    """检查 repo_path 下 must 列出的每一项都存在，返回缺失项列表。

    子集断言：repo_path 下多出的其他目录不算违规。
    隐藏文件（以 . 开头）也算存在 —— 目录名如 .ai 需被检查。
    """
    missing = []
    for name in must or []:
        if not os.path.exists(os.path.join(repo_path, name)):
            missing.append(name)
    return missing


# ── 跨仓加载 reference 的 sync_catalog.py ─────────────────────────────────
def load_sync_catalog(reference_root):
    """按**文件路径**加载 ``<reference root>/scripts/sync_catalog.py``。

    不能用 ``import sync_catalog`` —— 不同仓，不在同一 sys.path 上。
    """
    path = os.path.join(reference_root, "scripts", "sync_catalog.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("reference_sync_catalog", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ── .gitmodules ───────────────────────────────────────────────────────────
def parse_gitmodules(text):
    """解析 .gitmodules，返回 path -> url 映射。"""
    urls = {}
    path = None
    for line in text.replace("\r\n", "\n").split("\n"):
        s = line.strip()
        m = re.match(r'^\[submodule\s+"([^"]+)"\]$', s)
        if m:
            path = m.group(1)
            continue
        if s.startswith("path") and "=" in s:
            _, _, val = s.partition("=")
            path = val.strip()
            continue
        if s.startswith("url") and "=" in s and path:
            _, _, val = s.partition("=")
            urls[path] = val.strip()
            path = None
    return urls


def check_clone_url_divergence(entries, gitmodules_urls, model_of):
    """找出 catalog 的 clone_url 与 .gitmodules 的 url 不一致的条目。

    两者职责不同（.gitmodules 是 git 原生记录，clone_url 是实测可按 SHA 拉到的地址），
    所以这是**告警不是错误**（设计文档 §11 决定 33）。
    返回分歧条目的 name 列表。
    """
    divergent = []
    for entry in entries:
        name = entry.get("name")
        model = model_of.get(name, entry.get("model"))
        if not name or not model:
            continue
        clone_url = entry.get("clone_url")
        git_url = gitmodules_urls.get("reference/%s/%s" % (model, name))
        if not clone_url or not git_url:
            continue
        if clone_url.rstrip("/") != git_url.rstrip("/"):
            divergent.append(name)
    return sorted(divergent)


# ── Ruling 20：upstream.* 的路径基准 ──────────────────────────────────────
def resolve_upstream_paths(repo_entry, parent_root):
    """解析 upstream.* 的绝对路径。

    ``manifest`` / ``lockfile`` 相对 **reference 仓根**；
    ``script`` 相对 **父仓根**。
    """
    upstream = repo_entry.get("upstream") or {}
    ref_root = os.path.normpath(os.path.join(parent_root, repo_entry.get("path") or ""))
    out = {}
    for key in ("manifest", "lockfile"):
        value = upstream.get(key)
        if value:
            out[key] = os.path.normpath(os.path.join(ref_root, value))
    script = upstream.get("script")
    if script:
        out["script"] = os.path.normpath(os.path.join(parent_root, script))
    return out


# ── 子模块初始化状态 ─────────────────────────────────────────────────────
def submodule_status(parent_root):
    """返回 ``git submodule status`` 的输出（失败时返回空串）。"""
    try:
        proc = subprocess.run(["git", "-C", parent_root, "submodule", "status"],
                              capture_output=True, text=True)
    except FileNotFoundError:
        return ""
    return proc.stdout or ""


def uninitialized_submodules(parent_root):
    """列出未初始化（前缀为 '-'）的 submodule 路径。"""
    out = []
    for line in submodule_status(parent_root).split("\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("-"):
            parts = line.split()
            if len(parts) >= 2:
                out.append(parts[1])
    return out


# ── 主校验 ───────────────────────────────────────────────────────────────
def check_all(parent_root):
    """跑全部一致性检查，返回 (问题列表, 告警列表)。"""
    problems = []
    warnings = []

    repos_path = os.path.join(parent_root, "repos.yaml")
    if not os.path.exists(repos_path):
        return ["[repos.yaml] 不存在: %s" % repos_path], warnings
    with open(repos_path, "r", encoding="utf-8", newline="") as fh:
        repos = parse_repos(fh.read())
    if not repos:
        problems.append("[repos.yaml] 解析不出任何仓")
        return problems, warnings

    # 2/3/4 —— 每个仓的目录、git 状态、must_contain
    uninit = uninitialized_submodules(parent_root)
    for repo in repos:
        name = repo.get("name") or "<未命名>"
        rel = repo.get("path") or ""
        repo_path = os.path.normpath(os.path.join(parent_root, rel))
        if not os.path.exists(repo_path):
            problems.append("[%s] 仓目录不存在: %s" % (name, repo_path))
            continue
        if repo.get("fetch") == "submodule":
            if not os.path.isdir(os.path.join(repo_path, ".git")) and \
               not os.path.isfile(os.path.join(repo_path, ".git")):
                problems.append("[%s] 不是有效的 git 仓: %s" % (name, repo_path))
            if rel in uninit:
                problems.append("[%s] submodule 未初始化: %s" % (name, rel))
        elif repo.get("fetch") == "manifest":
            if not os.path.isdir(os.path.join(repo_path, "reference")):
                problems.append("[%s] 缺少源码层目录 reference/: %s" % (name, repo_path))
        for missing in check_must_contain(repo_path, repo.get("must_contain")):
            problems.append("[%s] 缺失顶层项: %s" % (name, missing))

    # 5/6/6b/7 —— reference 仓的 catalog / manifest / .gitmodules
    for repo in repos:
        if repo.get("fetch") != "manifest":
            continue
        name = repo.get("name") or "<未命名>"
        upstream_paths = resolve_upstream_paths(repo, parent_root)
        manifest_path = upstream_paths.get("manifest")
        lockfile_path = upstream_paths.get("lockfile")
        script_path = upstream_paths.get("script")

        if not manifest_path or not os.path.exists(manifest_path):
            problems.append("[%s] catalog 不存在: %s" % (name, manifest_path))
            continue
        if script_path and not os.path.exists(script_path):
            problems.append("[%s] 拉取脚本不存在: %s" % (name, script_path))

        sync = load_sync_catalog(repo.get("path") and
                                 os.path.normpath(os.path.join(parent_root, repo["path"])))
        if sync is None:
            problems.append("[%s] 找不到 sync_catalog.py，无法校验 catalog" % name)
            continue
        with open(manifest_path, "r", encoding="utf-8", newline="") as fh:
            entries = sync.parse_catalog(fh.read())

        # 6 —— pin_status 合法
        for entry in entries:
            if entry.get("pin_status") not in PIN_STATUSES:
                problems.append("[%s] pin_status 非法: %s = %r" % (
                    name, entry.get("name"), entry.get("pin_status")))
            if entry.get("source") not in SOURCES:
                problems.append("[%s] source 非法: %s = %r" % (
                    name, entry.get("name"), entry.get("source")))

        # 5 —— source: mirror 的条目数 == upstream.total（不是总数 97）
        total = (repo.get("upstream") or {}).get("total")
        if total is not None:
            mirror = sum(1 for e in entries if e.get("source") == "mirror")
            if mirror != int(total):
                problems.append("[%s] catalog 中 source=mirror 的条目数 %d != repos.yaml 声明的 %s" % (
                    name, mirror, total))

        # 6b —— clone_url 与 .gitmodules url 分歧：只告警
        gitmodules_path = os.path.join(
            os.path.normpath(os.path.join(parent_root, repo["path"])), ".gitmodules")
        if os.path.exists(gitmodules_path):
            with open(gitmodules_path, "r", encoding="utf-8", newline="") as fh:
                gitmodules_urls = parse_gitmodules(fh.read())
            model_of = {e.get("name"): e.get("model") for e in entries}
            for divergent in check_clone_url_divergence(entries, gitmodules_urls, model_of):
                warnings.append("[%s] clone_url 与 .gitmodules url 分歧: %s" % (name, divergent))

        # 7 —— fetch-manifest.txt 与 catalog 生成结果一致
        if not lockfile_path or not os.path.exists(lockfile_path):
            problems.append("[%s] manifest 不存在: %s" % (name, lockfile_path))
        else:
            with open(lockfile_path, "r", encoding="utf-8", newline="") as fh:
                on_disk = fh.read()
            expected = sync.render_manifest(entries)
            if on_disk.replace("\r\n", "\n") != expected.replace("\r\n", "\n"):
                problems.append("[%s] fetch-manifest.txt 与 catalog 生成结果不一致" % name)

    return problems, warnings


def main(argv=None):
    parser = argparse.ArgumentParser(description="四仓一致性校验")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="父仓根目录（默认取脚本所在仓的根）")
    args = parser.parse_args(argv)

    parent_root = os.path.abspath(args.root)
    problems, warnings = check_all(parent_root)

    for line in warnings:
        print("WARN " + line)
    if problems:
        print("发现 %d 处问题：" % len(problems))
        for line in problems:
            print("  " + line)
        return 1
    print("四仓一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())

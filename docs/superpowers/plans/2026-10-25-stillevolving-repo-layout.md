# StillEvolving 仓库重组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `StillEvolving` 顶层聚合仓，把 `projects` / `learning` / `ai-docs` 三个自维护仓作为 submodule 挂载其下，同时让第三方源码库（reference 的 95 个上游）改由清单驱动按需拉取，取代递归克隆。

**Architecture:** 混合形态。自维护仓走 git 原生 submodule（pin 由 gitlink mode 160000 保证）；第三方库走 `catalog.yml` + 拉取脚本，commit pin 显式记录在清单里，脚本在 submodule 内 fetch+checkout 到指定 commit。父仓另有一份 `repos.yaml` 声明四仓关系与目录规范，供 `check_consistency.py` 做机器校验。

**Tech Stack:** Git 2.55（submodule / gitlink）、Python 3.13（标准库，不引入第三方依赖）、Bash 5.3（Git Bash）、PowerShell 7（Windows 原生引导脚本）

**Spec:** `C:\code\docs\superpowers\specs\2026-10-25-stillevolving-repo-layout-design.md`

---

## Global Constraints

以下每条都来自设计文档的实测结论，**每个任务都隐含包含这些要求**。

| # | 约束 | 值 |
|---|---|---|
| G1 | 不得执行 `git submodule update --init --recursive` | 会一次性拉取 95 个第三方库（25 GB / 53.6 万文件） |
| G2 | `reference/` 与 `docs/` 目录名不可改 | 205 处带 `reference/` 前缀的引用依赖它（`resolve()` 走"退回仓库根"分支） |
| G3 | 第三方库路径形如 `reference/<model>/<name>` | **只有一层 reference**，实测 submodule path = `reference/vector/faiss` |
| G4 | `catalog.yml` 当前是 CRLF 行尾（876 CRLF / 876 LF） | 读写时必须 `newline=''` 或显式 `.replace('\r\n','\n')`，否则正则 `^...$` 全部失配 |
| G5 | 4 个 submodule 的 gitlink SHA 在上游不存在 | `druid` `pebble` `tdengine` `dragonfly` —— **不得照抄进 `commit` 字段** |
| G6 | `mysql` 的 pinned SHA 只在 GitHub 官方可取 | 两个 gitee 地址都取不到，其中 `yinchengwang_admin/mysql-server` 已被封禁（HTTP 423） |
| G7 | `AI-DOCS.git` 是空仓 | `git submodule add` 必然 exit 128（"branch yet to be born"），必须先推首个提交 |
| G8 | `StillEvolving.git` 远端已存在且非空 | main = `72908b9d9c34afb12e8adc6d6206cd226d16dfcb`，含 LICENSE + README |
| G9 | 磁盘占用不得显著增加 | 移动既有工作树方案磁盘零增长；重新 clone 方案 +2 GB（LFS 重复） |
| G10 | 迁移顺序固定 | `M1 → M21 → M2 → M3/M4/M5/M6` —— M21（ai-docs 首个提交）必须在 M2（加 submodule）之前 |
| G11 | Python 脚本只用标准库 | 环境未装 PyYAML，且 `catalog.yml` 字段结构规整，手写解析足够 |
| G12 | 门禁脚本 `check-wiki-refs.py` 在 projects 与 reference 各有一份且内容完全相同（14224 字节） | 本次**不动**这两份文件（避免破坏 2460 处引用校验） |
| G13 | `core.quotePath=false` | Windows 中文路径统计必须加此参数，否则路径被转义成八进制 |
| G14 | `catalog.yml` 条目数 = 97，submodule 数 = 95 | 差额恰为 `oceanbase`（distributed-sql）与 `pklite`（embedded），二者无源码镜像 |
| G15 | Python 脚本文件名用**下划线**，不用连字符 | `sync_catalog.py` / `check_consistency.py` —— `from sync_catalog import ...` 在连字符名下必然 `ModuleNotFoundError` |
| G16 | `catalog.yml` 中 `source: mirror` 的条目数 = 95 | 校验 catalog 时用这条，**不是**用总条目数 97（97 会误判） |

---

## Review Focus

设计文档是愿景文档，它没有明说的输入/失败模式中最可能坑到人的五条。每条都已在下方对应任务中有测试钉住。

| # | 输入 / 失败模式 | 合理预期 | 钉在 |
|---|---|---|---|
| F1 | 在**已有 submodule 目录**（非空）上跑拉取脚本 | 幂等跳过，不重新 clone，不弄脏父仓 `git status` | Task 5 |
| F2 | 拉取一个 `pin_status: broken` 的条目（druid/pebble/tdengine/dragonfly） | **跳过并告警**，不静默失败，也不去拉 HEAD 冒充 pin | Task 5、Task 3 |
| F3 | `catalog.yml` 被写成 LF（编辑器改了行尾） | 解析器仍能读出全部 97 条 —— 解析器必须同时容忍 CRLF 与 LF | Task 3 |
| F4 | `repos.yaml` 里 `must_contain` 列的目录在仓中不存在 | `check_consistency.py` 报**缺失**并退出非零 | Task 6 |
| F5 | 在 `AI-DOCS` 仍为空仓时执行 `git submodule add` | 明确失败并给出可执行的补救提示，而不是留半个 `.gitmodules` | Task 2 |

---

## File Structure

实施将创建/修改以下文件。每个文件职责单一。

### 新建：`C:\code\StillEvolving\`（顶层聚合仓）

| 文件 | 职责 |
|---|---|
| `README.md` | 四仓关系说明 + 目录语义 + bootstrap 入口（**改写**远端已有的两行内容） |
| `repos.yaml` | 机器可读的四仓关系声明（唯一权威） |
| `.gitmodules` | 三个 submodule 的 pin（由 `git submodule add` 生成，勿手改） |
| `.gitignore` | 忽略本地构建产物 |
| `LICENSE` | 沿用远端已有的 MIT |
| `scripts/bootstrap.ps1` | Windows 一键引导：clone submodule + 校验 |
| `scripts/bootstrap.sh` | POSIX 一键引导 |
| `scripts/fetch-reference.sh` | 按 catalog 拉取第三方库到指定 commit |
| `scripts/sync_catalog.py` | catalog ↔ manifest ↔ .gitmodules 三方同步与校验（**下划线命名，Python 可 import**） |
| `scripts/check_consistency.py` | 校验 repos.yaml ↔ 实际目录 ↔ catalog ↔ .gitmodules（**下划线命名**） |
| `docs/architecture.md` | 目录规范（设计文档 §5 的落地版） |
| `docs/superpowers/specs/` | 迁入设计文档 |
| `docs/superpowers/plans/` | 迁入本计划 |

### 修改：`C:\code\reference\`

| 文件 | 职责 | 改动 |
|---|---|---|
| `reference/catalog.yml` | 唯一权威清单 | 97 条补 `commit` / `clone_url` / `pin_status` / `source` 四字段 |
| `reference/fetch-manifest.txt` | 拉取 lockfile | 从 3 列（73 条）改为 5 列（97 条） |
| `reference/AUDIT.md` | 克隆审计 | 追加拉取结果记录 |
| `README.md` | 分类口径 | "14 个技术分类" → 15 个；加"禁止 `--recursive`"警告 |
| `.gitignore` | 忽略规则 | 删除实测不生效的 `reference/*/` 两条 |
| `docs/{db-wiki,rag-wiki,agent-wiki}/README.md` | 索引 | 16 处断链改为跨仓链接 |

### 修改：`C:\code\book\`（projects）

| 文件 | 职责 | 改动 |
|---|---|---|
| `openspec/specs/learning/` | 学习轨 spec | 35 文件 → 迁至 learning |
| `openspec/specs/r*/` | 轮次 spec | 12 个纯学习向目录 → 迁至 learning |
| `docs/path-mapping.md` | 路径映射契约 | 硬编码 `C:/code` → 更新为新布局 |
| `.ai/.claude/settings.json` | agent 配置 | 硬编码 `C:/code` → 更新 |

### 修改：`C:\code\learning\`

| 文件 | 职责 | 改动 |
|---|---|---|
| `openspec/specs/` | 新建 | 接收 projects 迁来的 47 个 spec |
| `progress/r*.md` | 进度 | 顶层 7 个散落 → 归入 `progress/` |
| `notes/ds/` | 新建 | 顶层 5 个 `ds-*.md` → 归入 |
| `scaffold/cpp/parallel_stl/NOTES.md` | 笔记 | 硬编码 `C:/code` → 更新 |

---

## Task 依赖图

```
Task 1 (remote URL + 清理)
   ↓
Task 2 (ai-docs 骨架 + 首个提交)  ← 必须早于 Task 3
   ↓
Task 3 (StillEvolving 仓 + 三个 submodule)
   ↓
   ├─→ Task 4 (catalog 四字段 + manifest 5 列)
   │      ↓
   │   Task 5 (fetch-reference.sh)
   │      ↓
   │   Task 6 (check_consistency.py + bootstrap)
   │
   └─→ Task 7 (内容归位：spec / progress / notes)
          ↓
       Task 8 (断链修复 + README 口径)
```

---

### Task 1: 修正 remote URL 并清理死残留

**Files:**
- Modify: `C:\code\book\.git\config`（remote origin URL）
- Delete: `C:\code\book.worktrees\`（999 MB，三个孤立 worktree）
- Delete: `C:\code\verify_learning\`（损坏仓库）

**Interfaces:**
- Consumes: 无（起点任务）
- Produces: `projects` 仓的 `origin` 指向 `https://github.com/yinchengwang/projects.git`；`C:\code\` 下只剩 `book` `learning` `reference` `3D相册` 四个目录

- [ ] **Step 1: 确认两个 URL 指向同一 commit（改名重定向无损）**

Run:
```bash
git ls-remote https://github.com/yinchengwang/book.git refs/heads/main
git ls-remote https://github.com/yinchengwang/projects.git refs/heads/main
```
Expected: 两行输出的 SHA **完全相同**（实测均为 `495c8f1e38ca465e9216c4512f5132db787c39b6`）。若不同则停止 —— 说明改名期间有过提交，需先处理历史差异。

- [ ] **Step 2: 确认 projects 仓无未推送提交**

Run:
```bash
cd /c/code/book && git log --oneline origin/main..main | head -20
```
Expected: 空输出（无未推送提交）。若有输出，先 `git push origin main` 再继续。

- [ ] **Step 3: 更新 remote URL**

Run:
```bash
cd /c/code/book && git remote set-url origin https://github.com/yinchengwang/projects.git
```
Expected: 无输出。

- [ ] **Step 4: 验证 remote 生效**

Run:
```bash
cd /c/code/book && git remote -v
```
Expected: `origin  https://github.com/yinchengwang/projects.git (fetch)` 与 `(push)` 两行，**不再出现 `book.git`**。

- [ ] **Step 5: 归档 worktree 里的旧布局（只留有价值的部分）**

`minimax-coding-plan-implementation/` 内含 `engineering/` 旧布局，删除前先看一眼有没有还在用的东西。

Run:
```bash
ls -la /c/code/book.worktrees/minimax-coding-plan-implementation/ | head -20
du -sh /c/code/book.worktrees/*
```
Expected: 三个目录各约 300 MB 量级，`minimax-coding-plan-implementation/` 最大。

人工判断后二选一：
- 若 `engineering/` 旧布局内容已在主仓 `engine/` 中有对应 → 直接进入 Step 6
- 若有独有价值 → 先 `cp -r` 到 `/c/code/_archive/minimax-engineering-layout/` 再进入 Step 6

- [ ] **Step 6: 删除三个死 worktree 与损坏仓库**

Run:
```bash
cd /c/code/book && git worktree list
```
Expected: **只有主仓一行**（实测如此）。这证明 `book.worktrees/` 下的三个目录 git 完全不认（其 `.git` 文件指向的 `book/.git/worktrees/` 目录不存在）→ 纯死残留，删除无风险。

Run:
```bash
rm -rf /c/code/book.worktrees
rm -rf /c/code/verify_learning
```
Expected: 无输出。

- [ ] **Step 7: 验证清理结果并记录磁盘回收**

Run:
```bash
ls -1 /c/code/
du -sh /c/code/book /c/code/learning /c/code/reference 2>/dev/null
```
Expected: `C:\code` 下只剩 `book` `learning` `reference` `3D相册` `docs`；磁盘回收约 999 MB。

---

### Task 2: 创建 ai-docs 骨架并推送首个提交

**Files:**
- Create: `C:\code\ai-docs\README.md`
- Create: `C:\code\ai-docs\INDEX.md`
- Create: `C:\code\ai-docs\templates\README.md`
- Create: `C:\code\ai-docs\methodology\README.md`
- Create: `C:\code\ai-docs\patterns\README.md`
- Create: `C:\code\ai-docs\assets\README.md`
- Create: `C:\code\ai-docs\prompts\README.md`
- Create: `C:\code\ai-docs\agent-notes\README.md`
- Create: `C:\code\ai-docs\references\README.md`
- Create: `C:\code\ai-docs\archive\README.md`

**Interfaces:**
- Consumes: 无
- Produces: `AI-DOCS.git` 远端 `main` 分支非空，且 `git ls-remote` 能返回 SHA —— **这是 Task 3 的硬前置**

- [ ] **Step 1: 确认远端仍为空仓**

Run:
```bash
git ls-remote https://github.com/yinchengwang/AI-DOCS.git
```
Expected: **空输出**。若已非空（有人抢先推了内容），进入 Step 2 前先 `git clone` 下来看内容，不要覆盖。

- [ ] **Step 2: 克隆并建目录骨架**

```bash
git clone https://github.com/yinchengwang/AI-DOCS.git /c/code/ai-docs
cd /c/code/ai-docs
mkdir -p templates/{spec,doc,review,prompt} methodology/{design-review,debugging,planning} \
         patterns/{architecture,data-structure,process} assets/{diagrams,scripts} \
         prompts agent-notes references archive
```

- [ ] **Step 3: 写顶层 README（边界声明）**

`C:\code\ai-docs\README.md` 内容必须包含这一段（这是本仓最关键的一段话）：

```markdown
# AI-DOCS

跨项目复用的 AI 工作资产仓。

## 收录边界

| 收进来 | 不收 |
|---|---|
| 跨项目复用的模板、方法论、模式 | 项目级架构文档 → projects `docs/` |
| 通用提示词库 | 项目级 agent 规约 → projects `.ai/`、`CLAUDE.md` |
| agent 通用踩坑经验 | 具体项目的 openspec 变更 → projects `openspec/` |
| 外部资料的链接与摘要索引 | 学习笔记与课程进度 → learning |
| 通用图表与脚本资产 | 第三方源码镜像 → reference |

**判定口诀：换个项目还用得上 → AI-DOCS；只对这个项目有意义 → projects。**
```

- [ ] **Step 4: 写 INDEX.md**

`C:\code\ai-docs\INDEX.md` 列出 8 个子目录，每个一行说明 + 指向该目录 README 的相对链接。

- [ ] **Step 5: 给每个子目录写 README.md**

每个 `README.md` 至少三行：这个目录放什么、什么不放什么、当前有哪些条目。例：

```markdown
# templates

可复用的文档与流程模板。

**放**：跨项目通用的 spec / doc / review / prompt 模板
**不放**：某个具体项目的 spec 草稿

## 现有
- `spec/` —— openspec 变更模板（proposal / design / tasks / spec delta）
```

- [ ] **Step 5b: 处理 3D相册 的归属（M9）**

`C:\code\3D相册\3D相册-1\` 目前不是 git 仓（实测 `fatal: not a git repository`）。
它的归属**取决于设计文档 §8 Q3 的用户答复**：

- 若答复为"projects 的一个 app" → 在 Task 7 里并入 `projects/apps/3d-album/`
- 若答复为"独立仓" → 在这里 `git init` 并推到新的 GitHub 仓
- 若答复为"ai-docs 的素材" → 并入 `ai-docs/assets/`

**若 Q3 尚未答复，本步骤跳过**，但要在 Task 8 的收尾里提醒用户。

- [ ] **Step 6: 提交并推送首个提交**

```bash
cd /c/code/ai-docs
git branch -M main
git add -A
git commit -m "feat(ai-docs): 建立目录骨架与收录边界声明"
git push -u origin main
```
Expected: push 成功。

**`git branch -M main` 不能省** —— 克隆空仓时本地分支名取决于 `init.defaultBranch`（本机未设置，git 内置默认可能是 `master`）。
若省略这行，推送的是 `master`，而远端 HEAD 指向 `main` → Task 3 Step 5 的 `git submodule add` 会以 exit 128 结束。

- [ ] **Step 7: 验证远端不再为空（Task 3 的前置条件）**

⚠️ **本任务全程在 `C:\code\ai-docs`（独立克隆）里操作**。Task 3 Step 5 会把它加成 submodule，
届时 `C:\code\StillEvolving\ai-docs` 是同一份内容的 submodule 检出。
**Task 3 完成后必须删除这个独立克隆目录**，否则两份副本并存，改错副本的概率很高：
```bash
rm -rf /c/code/ai-docs
```
（内容已推送远端，不会丢失。submodule 会从远端重新检出。）

Run:
```bash
git ls-remote https://github.com/yinchengwang/AI-DOCS.git refs/heads/main
```
Expected: 输出**一行 40 位 SHA**（形如 `<sha>\trefs/heads/main`）。空输出则 Task 3 必然失败，必须重跑 Step 6。

- [ ] **Step 8: 确认远端 HEAD 指向 main（避免 submodule add 找不到 ref）**

Run:
```bash
git ls-remote --symref https://github.com/yinchengwang/AI-DOCS.git HEAD
```
Expected: 第一行含 `ref: refs/heads/main`。若指向 `master` 或其他分支 → 需在远端把默认分支改成 `main`（GitHub 仓库设置 → Branches → Default branch），或把本地推的分支改名后重推。**这一步不能跳过** —— `git submodule add` 会去 checkout 远端 HEAD，HEAD 指向的分支不存在时它报 "branch yet to be born" 并 exit 128。

---

### Task 3: 建立 StillEvolving 仓并挂载三个 submodule

**Files:**
- Create: `C:\code\StillEvolving\`（clone 远端已有仓）
- Create: `C:\code\StillEvolving\repos.yaml`
- Create: `C:\code\StillEvolving\README.md`（改写）
- Create: `C:\code\StillEvolving\.gitignore`
- Create: `C:\code\StillEvolving\docs\architecture.md`
- Modify: `C:\code\StillEvolving\.gitmodules`（由 `git submodule add` 生成）
- Move: `C:\code\book` → `C:\code\StillEvolving\projects`（见 Step 4）

**Interfaces:**
- Consumes: Task 1（remote 已指向 `projects.git`）、Task 2（AI-DOCS 远端非空且 HEAD→main）
- Produces: `StillEvolving` 仓含三个 submodule，`git submodule status` 三条无 `-` 前缀；`repos.yaml` 落盘

- [ ] **Step 1: 克隆 StillEvolving（远端已存在，非空）**

```bash
git clone https://github.com/yinchengwang/StillEvolving.git /c/code/StillEvolving
cd /c/code/StillEvolving
ls -la
```
Expected: 含 `LICENSE`（MIT）与 `README.md`（内容为 `# -` + `还在进化`）。**不要 `git init` 新建** —— 远端已有提交，新建会丢失历史。

- [ ] **Step 2: 移动 projects 工作树（路径 A，磁盘零增长）**

```bash
cd /c/code
mv book StillEvolving/projects
ls -la /c/code/
```
Expected: `C:\code` 下不再有 `book`，`C:\code\StillEvolving\projects` 存在。磁盘占用**零增长**（G9）。

验证移动后 git 仍然正常：
```bash
cd /c/code/StillEvolving/projects && git status --short | head -5 && git log --oneline -1
```
Expected: `git status` 无异常输出，`git log` 显示 `495c8f1e` 附近的提交。

- [ ] **Step 3: 加入 projects submodule（指向已存在的目录）**

```bash
cd /c/code/StillEvolving
git submodule add https://github.com/yinchengwang/projects.git projects
```
Expected: 输出 `Adding existing repo at 'projects' to the index`。

**若报 `does not have a commit checked out`** → 说明 `projects` 目录不是有效克隆，回退到 Step 2 检查是否被 `mv` 破坏。

- [ ] **Step 4: 加入 learning submodule**

```bash
cd /c/code/StillEvolving
git submodule add https://github.com/yinchengwang/learning.git learning
```
Expected: 正常 clone 成功（learning 仅 108 MB，无 LFS，风险低）。

- [ ] **Step 5: 加入 ai-docs submodule**

```bash
cd /c/code/StillEvolving
git submodule add https://github.com/yinchengwang/AI-DOCS.git ai-docs
```
Expected: 正常成功。**若报 "You are on a branch yet to be born" / exit 128** → 回到 Task 2 Step 8 检查远端 HEAD 指向。

- [ ] **Step 6: 验证三个 submodule 状态**

```bash
cd /c/code/StillEvolving
git submodule status
```
Expected: **三行，SHA 前面都是空格（不是 `-`）**，形如：
```
 495c8f1e38ca465e9216c4512f5132db787c39b6 projects (projects-1.0.0)
 <sha> learning (learning-1.0.0)
 <sha> ai-docs (ai-docs-1.0.0)
```
若任一行以 `-` 开头 → 该 submodule 未 init，执行 `git submodule update --init <name>`（**注意：绝不带 `--recursive`**，见 G1）。

- [ ] **Step 7: 写 repos.yaml**

`C:\code\StillEvolving\repos.yaml` 完整内容（**逐字照抄，字段名与值都是接口**）：

```yaml
version: 1
repos:
  - name: projects
    url: https://github.com/yinchengwang/projects.git
    fetch: submodule
    path: projects
    role: 工程仓
    must_contain: [engine, apps, docs, openspec, .ai, vendor, dataset, scripts, archive]
    description: 自研数据库/搜索引擎引擎、微信小程序、项目级文档与 agent 规约
    known_duplication:
      - path: vendor/third_part/googletest
        also_in: learning/third_part/googletest
        note: 两仓各有一份 googletest，pin 可能不同，本次刻意保留两份不合并

  - name: learning
    url: https://github.com/yinchengwang/learning.git
    fetch: submodule
    path: learning
    role: 学习仓
    must_contain: [scaffold, notes, code-solutions, ds-c, arkts, interview, algo-c, progress, third_part]
    description: Obsidian 学习 vault、脚手架工程、算法题解、课程进度
    known_duplication:
      - path: third_part/googletest
        also_in: projects/vendor/third_part/googletest
        note: 与 projects 重复，刻意保留两份（合并需两个仓各改 .gitmodules，风险高于收益）

  - name: ai-docs
    url: https://github.com/yinchengwang/AI-DOCS.git
    fetch: submodule
    path: ai-docs
    role: AI 工作文档仓
    must_contain: [templates, methodology, patterns, assets, prompts, agent-notes]
    description: 跨项目复用的模板、方法论、模式、提示词与 agent 经验

  - name: reference
    url: https://github.com/yinchengwang/reference.git
    fetch: manifest
    path: ../reference
    role: 第三方源码镜像 + 源码笔记
    must_contain: [reference, docs, scripts]
    description: 95 个第三方库的按需镜像 + 97 篇带精确行号引用的源码笔记
    upstream:
      manifest: reference/catalog.yml
      lockfile: reference/fetch-manifest.txt
      script: scripts/fetch-reference.sh
      commit_field: commit
      pin_status_field: pin_status
      total: 95
      notes: |
        reference 不作为 submodule 挂载。递归克隆会拉取 25 GB / 53.6 万文件。
        其上游 95 个库由 catalog.yml 声明 commit，按需克隆。
        path 用 ../reference 表达"与 StillEvolving 平级但不在其内"。
```

**注意**：`repos.yaml` 里**没有** `updated` 字段（生成型文件带硬编码日期必然漂移）。

- [ ] **Step 8: 写 StillEvolving 的 README.md（改写远端已有的两行）**

`C:\code\StillEvolving\README.md` 必须包含：

```markdown
# StillEvolving

个人项目的顶层聚合仓。这里不放业务代码，只放**四个仓库之间的关系**。

## 四个仓库

| 仓 | 路径 | 获取方式 | 放什么 |
|---|---|---|---|
| projects | `projects/` | submodule | 引擎代码、小程序、项目文档、agent 规约 |
| learning | `learning/` | submodule | 学习笔记、脚手架、算法题解 |
| ai-docs | `ai-docs/` | submodule | 跨项目复用的模板与方法论 |
| reference | `../reference/` | 独立仓 + 清单拉取 | 第三方源码镜像 + 源码笔记 |

## 快速开始

```bash
# 1) 拉起三个 submodule
git clone --recurse-submodules https://github.com/yinchengwang/StillEvolving.git
# 或先 clone 再初始化
git submodule update --init

# 2) 按需拉取第三方库（不要用 --recursive，会拉 25 GB）
bash scripts/fetch-reference.sh --tier core
```

## ⚠️ 禁止 `git submodule update --init --recursive`

reference 内部有 95 个第三方库 submodule，递归初始化会一次性拉取约 25 GB / 53.6 万文件。
需要哪个库就用 `scripts/fetch-reference.sh --name <名字>` 单独拉取。

## 目录规范

见 `docs/architecture.md`；机器可读版见 `repos.yaml` 的 `must_contain` 字段。
```

- [ ] **Step 9: 写 .gitignore**

`C:\code\StillEvolving\.gitignore`：
```
# 构建产物
build/
build-*/
CMakeFiles/
CMakeCache.txt
*.obj
*.o
*.exe

# Python
__pycache__/
*.pyc
.venv/
```

- [ ] **Step 10: 写 docs/architecture.md**

内容取自设计文档 §5（四个仓的目录树 + 归属判定表）。至少包含四棵树与两张归属表 —— 即"哪个东西该放哪个仓"的完整规则。

**并在各仓自己的 README 里也放一份归属判定表**（设计文档 §5.2 / §5.3 的要求）——
父仓的 `docs/architecture.md` 是总览，但人进到 `projects/` 里看不到它，所以每仓 README 必须自带一份：

- `projects/README.md` 加一节"## 什么该放这个仓"，内容为设计文档 §5.2 的归属判定表
- `learning/README.md` 加一节"## 什么该放这个仓"，内容为设计文档 §5.3 的归属判定表
- `ai-docs/README.md` 的收录边界已在 Task 2 Step 3 写好

判定口诀（三个仓通用）：**换个项目还用得上 → ai-docs；只对这个项目有意义 → 留在本仓。**

- [ ] **Step 11: 把设计文档与本计划迁入父仓（M27）**

`C:\code\docs\` 下的文档当前不在任何 git 仓里（C14），父仓建好后要迁进来：

```bash
cd /c/code/StillEvolving
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp /c/code/docs/superpowers/specs/2026-10-25-stillevolving-repo-layout-design.md docs/superpowers/specs/
cp /c/code/docs/superpowers/plans/2026-10-25-stillevolving-repo-layout.md docs/superpowers/plans/
cp /c/code/docs/architecture-review-2026-10-25.md docs/
cp /c/code/docs/repos.yaml.sample.yaml docs/
```

⚠️ `repos.yaml.sample.yaml` 是 `repos.yaml` 的**前身**（它没有 `must_contain` 字段）。
在文件顶部加一行说明，避免后来者误用：
```
<!-- 历史版本：这是 repos.yaml 的早期草案，缺少 must_contain 字段。
     现行版本见仓库根目录的 repos.yaml。 -->
```

- [ ] **Step 12: 提交**

```bash
cd /c/code/StillEvolving
git add -A
git commit -m "feat: 建立 StillEvolving 聚合仓，挂载 projects/learning/ai-docs 三个 submodule"
```

- [ ] **Step 13: 推送**

```bash
cd /c/code/StillEvolving
git push origin main
```
Expected: 推送成功。**推送前可先 `git push --dry-run origin main` 预演**（注意：不是 `git push --dry-run` 不带参数）。

---

### Task 4: 补齐 catalog 四字段并重建 manifest

**Files:**
- Modify: `C:\code\reference\reference\catalog.yml`
- Modify: `C:\code\reference\reference\fetch-manifest.txt`
- Create: `C:\code\reference\scripts\sync_catalog.py`（**下划线**，Python 模块名不能含连字符）
- Test: `C:\code\reference\scripts\test_sync_catalog.py`

**Interfaces:**
- Consumes: Task 3（StillEvolving 仓就位，脚本放这里）
- Produces:
  - `catalog.yml` 97 条，每条带 `commit` / `clone_url` / `pin_status` / `source`
  - `fetch-manifest.txt` 5 列 97 条
  - `sync_catalog.py` 提供两个可调用函数：
    - `parse_catalog(text: str) -> list[dict]` —— 容忍 CRLF 与 LF（G4）
    - `render_manifest(entries: list[dict]) -> str` —— 生成 5 列 manifest 文本
  - `python scripts/sync_catalog.py --check` 退出码 0 = 一致，1 = 不一致

- [ ] **Step 1: 写失败测试 —— CRLF 解析**

`C:\code\reference\scripts\test_sync_catalog.py`：

```python
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync_catalog import parse_catalog, render_manifest

CATALOG_CRLF = "projects:\r\n  - name: faiss\r\n    model: vector\r\n    tier: core\r\n"
CATALOG_LF = CATALOG_CRLF.replace("\r\n", "\n")


class TestParse(unittest.TestCase):
    def test_parses_crlf(self):
        """G4: catalog.yml 当前是 CRLF 行尾，解析器必须能读。"""
        entries = parse_catalog(CATALOG_CRLF)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["name"], "faiss")
        self.assertEqual(entries[0]["model"], "vector")

    def test_parses_lf(self):
        """F3: 编辑器把 CRLF 改成 LF 后仍须能解析。"""
        entries = parse_catalog(CATALOG_LF)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["name"], "faiss")

    def test_parses_notes_list(self):
        """notes 是 YAML 列表，不是标量。"""
        text = ("projects:\n  - name: x\n    model: vector\n"
                "    notes:\n      - 说明一\n      - 说明二\n")
        entries = parse_catalog(text)
        self.assertEqual(entries[0]["notes"], ["说明一", "说明二"])


class TestRender(unittest.TestCase):
    def test_manifest_has_five_columns(self):
        """manifest 是 5 列 lockfile：model/name/clone_url/commit/pin_status。"""
        entries = [{
            "name": "faiss", "model": "vector",
            "clone_url": "https://example/faiss.git",
            "commit": "0" * 40, "pin_status": "valid",
        }]
        lines = [l for l in render_manifest(entries).split("\n") if l.strip()]
        header = lines[0]
        self.assertIn("commit", header)
        self.assertIn("pin_status", header)
        row = lines[1].split("\t")
        self.assertEqual(len(row), 5)
        self.assertEqual(row[3], "0" * 40)
        self.assertEqual(row[4], "valid")

    def test_manifest_uses_dash_for_empty(self):
        """空值用 '-'，避免与 YAML null 混淆。"""
        entries = [{
            "name": "oceanbase", "model": "distributed-sql",
            "clone_url": None, "commit": None, "pin_status": "unresolvable",
        }]
        row = [l for l in render_manifest(entries).split("\n")
               if l.strip() and not l.startswith("#")][0].split("\t")
        self.assertEqual(row[2], "-")
        self.assertEqual(row[3], "-")
        self.assertEqual(row[4], "unresolvable")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd /c/code/reference && python scripts/test_sync_catalog.py -v
```
Expected: FAIL，报 `ModuleNotFoundError: No module named 'sync_catalog'`。

- [ ] **Step 3: 实现 sync_catalog.py 的解析与渲染**

`C:\code\reference\scripts\sync_catalog.py` 核心函数签名：

```python
def parse_catalog(text: str) -> list[dict]:
    """解析 catalog.yml 文本，返回条目列表。

    必须容忍 CRLF 与 LF 混合行尾（G4）。不依赖 PyYAML（G11）。
    返回的每个 dict 含 name/model/tier/repository/mirror/license/status/notes，
    以及可选的 commit/clone_url/pin_status/source。
    """


def render_manifest(entries: list[dict]) -> str:
    """渲染 5 列 manifest 文本。

    列：model<TAB>name<TAB>clone_url<TAB>commit<TAB>pin_status
    首行为 '#' 开头的表头注释。空值写 '-'。
    """
```

实现要点：
- 读文件时用 `open(path, 'r', encoding='utf-8', newline='')`，再 `.replace('\r\n', '\n')`
- `notes:` 后面跟缩进 `- xxx` 的行归为列表；无缩进续行归为标量
- 缩进约定：条目首行 `  - name: `，字段行 4 空格缩进，notes 列表项 6 空格缩进

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd /c/code/reference && python scripts/test_sync_catalog.py -v
```
Expected: 5 个测试全部 PASS（`test_parses_crlf` / `test_parses_lf` / `test_parses_notes_list` / `test_manifest_has_five_columns` / `test_manifest_uses_dash_for_empty`）。

- [ ] **Step 5: 写 pin 状态判定数据（人工确认，不可自动化）**

以下 6 个条目的 `pin_status` 与 `commit` 取值已由实测确定，**逐字填入**：

| name | model | pin_status | commit | clone_url |
|---|---|---|---|---|
| `druid` | columnar | `broken` | `null` | `https://github.com/apache/druid.git` |
| `pebble` | key-value | `broken` | `null` | `https://github.com/cockroachdb/pebble.git` |
| `tdengine` | time-series | `broken` | `null` | `https://github.com/taosdata/TDengine.git` |
| `dragonfly` | key-value | `broken` | `null` | `https://github.com/dragonflydb/dragonfly.git` |
| `oceanbase` | distributed-sql | `unresolvable` | `null` | `null` |
| `pklite` | embedded | `unresolvable` | `null` | `null` |

其余 91 条：`pin_status: valid`，`commit` 填 `.gitmodules` 对应 gitlink 的 SHA，`clone_url` 填 GitHub 官方 `repository`。

**mysql 特别说明**：其 pin `23e360a7fac718d80b9e6a79f7d5a7bf37aa3bbc` **真实存在**（GitHub commit 页 HTTP 200），只是 gitee 镜像不含它 → `pin_status: valid`，`clone_url: https://github.com/mysql/mysql-server.git`。

**取 gitlink SHA 的命令**：
```bash
cd /c/code/reference && git ls-files -s | grep "^160000" | awk '{print $2, $4}'
```

- [ ] **Step 5b: 逐条验证 clone_url 真的能按 SHA 拉到（M4）**

91 条 `valid` 的 `clone_url` 不能靠"填 GitHub 官方"了事 —— 必须实测验证。
先导出待验证清单：
```bash
cd /c/code/reference
python -c "
import sys
sys.path.insert(0, 'scripts')
from sync_catalog import parse_catalog
entries = parse_catalog(open('reference/catalog.yml', encoding='utf-8', newline='').read())
for e in entries:
    if e.get('pin_status') == 'valid':
        print(e['name'], e['clone_url'], e['commit'], sep='\t')
" > /tmp/valid_urls.txt
wc -l /tmp/valid_urls.txt
```
Expected: `91 /tmp/valid_urls.txt`。

然后逐条验证（**每条用干净的临时目录**）：
```bash
TMPD="$(mktemp -d)"
while IFS=$'\t' read -r name url sha; do
  rm -rf "$TMPD"; mkdir -p "$TMPD"; cd "$TMPD"; git init -q .
  if git fetch --depth 1 --no-tags "$url" "$sha" >/dev/null 2>&1; then
    echo "OK   $name"
  else
    echo "FAIL $name $url"
  fi
done < /tmp/valid_urls.txt
rm -rf "$TMPD"
```

**Expected**：91 条全部 `OK`。出现 `FAIL` 的条目必须换 `clone_url`（换用 GitHub 官方或其他实测可用的镜像）后重测。

⚠️ **测 SHA 可达性时必须每次用干净目录** —— 残留的 `.git/shallow.lock` 会让后续所有 fetch 假失败（实测踩过：
第一次测对照组 faiss 也报 FAIL，原因是 lock 文件残留，不是 SHA 无效）。

⚠️ **91 条逐条 fetch 需要时间**（每条一次网络往返 + 浅克隆）。若单条超过 60 秒仍未返回，
记为 `TIMEOUT` 单独列出人工复核，不要让整轮无限等待。

- [ ] **Step 6: 写脚本补齐 catalog 四字段**

在 `sync_catalog.py` 加 `sync_catalog(repo_root: str, apply: bool) -> list[str]`：
- 读 `reference/catalog.yml` → `parse_catalog`
- 读 `.gitmodules` 与 `git ls-files -s` 得 gitlink SHA 映射
- 对每条：按 Step 5 的表定 `pin_status`；`valid` 的填 gitlink SHA + `clone_url`（优先 GitHub 官方 `repository`）；`broken`/`unresolvable` 的 `commit` 写 `null`
- `apply=False` 时只返回差异报告；`apply=True` 时写回 catalog.yml

**写回时必须保持 CRLF 行尾**（G4 —— 保持文件原有格式，避免整个文件产生 diff 噪音）。

- [ ] **Step 7: 校验 catalog 已补齐**

```bash
cd /c/code/reference && python scripts/sync_catalog.py --check
```
Expected: 输出 `97 entries, 91 valid, 4 broken, 2 unresolvable`，退出码 0。

- [ ] **Step 8: 重建 fetch-manifest.txt（5 列 97 条）**

```bash
cd /c/code/reference && python scripts/sync_catalog.py --write-manifest
```
Expected: `reference/fetch-manifest.txt` 从 73 行 3 列变为 97 行 5 列。校验：
```bash
cd /c/code/reference && head -3 reference/fetch-manifest.txt && wc -l reference/fetch-manifest.txt
```
Expected: 首行是 `# model\tname\tclone_url\tcommit\tpin_status` 注释；**数据行 97 行**（`wc -l` 会报 98，因为表头也是一行）。

⚠️ **分隔符是变更项，不只是加列** —— 旧文件是**空格分隔**（实测 `od -c` 确认
`r e l a t i o n a l   p o s t g r e s`），新格式是 **TAB 分隔**。
必须验证分隔符真的变了：
```bash
cd /c/code/reference && sed -n '2p' reference/fetch-manifest.txt | od -c | head -3
```
Expected: 第 2 行含 `\t`（即 `\t` 字节序列），**不是**空格。

再验证字段数：
```bash
cd /c/code/reference && sed -n '2p' reference/fetch-manifest.txt | awk -F'\t' '{print NF}'
```
Expected: `5`（旧文件用 `-F'\t'` 会输出 `1` —— 因为它其实是空格分隔）。

- [ ] **Step 9: 确认 24 个 AI 类目已补齐**

```bash
cd /c/code/reference && grep -c "^ai/" reference/fetch-manifest.txt
```
Expected: `24`（原 manifest 缺失这 24 条）。

- [ ] **Step 10: 提交**

```bash
cd /c/code/reference
git add reference/catalog.yml reference/fetch-manifest.txt scripts/sync_catalog.py scripts/test_sync_catalog.py
git commit -m "feat(reference): catalog 补齐 commit/clone_url/pin_status/source，manifest 扩为 5 列 lockfile"
```

---

### Task 5: 实现按需拉取脚本

**Files:**
- Create: `C:\code\StillEvolving\scripts\fetch-reference.sh`
- Test: `C:\code\StillEvolving\scripts\test_fetch_reference.sh`

**Interfaces:**
- Consumes: Task 4（catalog 四字段 + manifest 5 列）
- Produces:
  - `bash scripts/fetch-reference.sh [选项]` 支持 `--tier <t>` / `--model <m>` / `--name <n>` / `--all` / `--check` / `--yes`
  - 退出码：0 = 全部成功或跳过；1 = 有条目失败
  - 拉取目标路径 = `<reference 仓根>/reference/<model>/<name>`（G3）
  - 在 submodule 内操作，checkout 到 `commit` 后父仓 `git status` 保持干净

- [ ] **Step 1: 写失败测试 —— 幂等与 broken 跳过**

`C:\code\StillEvolving\scripts\test_fetch_reference.sh`：

```bash
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
if [ "$1" = "submodule" ]; then exit 0; fi
if [ "$1" = "-C" ]; then exit 0; fi
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

echo
echo "通过 $PASS，失败 $FAIL"
[ $FAIL -eq 0 ]
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd /c/code/StillEvolving && bash scripts/test_fetch_reference.sh
```
Expected: FAIL（脚本不存在或行为不符）。

- [ ] **Step 3: 实现 fetch-reference.sh**

关键接口约定：

```
用法: fetch-reference.sh [选项]
  --tier <core|representative|innovative>   按 tier 筛选
  --model <分类>                             按分类筛选（ai/agent 等）
  --name <名字>                              单个条目
  --all                                     全部（需 --yes）
  --check                                   只校验，不拉取；**不执行任何 clone/fetch**（可安全地在 CI 里跑）
  --yes                                     跳过 --all 的交互确认
```

实现要点：

```bash
#!/bin/bash
set -uo pipefail

# 定位 reference 仓根：默认取 ../reference，可用 --reference-root 覆盖
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCE_ROOT="${REFERENCE_ROOT:-$REPO_ROOT/../reference}"
CATALOG="$REFERENCE_ROOT/reference/catalog.yml"
```

- **pin_status 分支**（F2）：
  - `valid` → 执行拉取
  - `broken` → 打印 `SKIP <name>: pin_status=broken（上游不存在该 commit）`，**不执行任何 git 操作**，计入"跳过"不算失败
  - `unresolvable` → 打印 `SKIP <name>: source=none（无源码镜像）`，同理跳过
- **拉取流程**（F1 幂等）：
  ```bash
  # 已 init 且 HEAD == commit → 跳过
  # 未 init → git submodule init <path> && git submodule update --depth 1 <path>
  # 已 init 但 HEAD != commit → git -C <path> fetch --depth 1 origin <commit> && git -C <path> checkout <commit>
  ```
  **`git submodule update` 绝不带 `--recursive`**（G1）
- **`--all` 保护**：打印预估磁盘占用（按 tier 估算），无 `--yes` 时交互确认
- **失败处理**：单条失败记录到 `$REFERENCE_ROOT/reference/AUDIT.md` 并继续下一条，最后汇总"成功 N / 跳过 M / 失败 K"
- **禁止**在任何路径执行 `git submodule update --init --recursive`（G1）—— 代码里不出现该字符串

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd /c/code/StillEvolving && bash scripts/test_fetch_reference.sh
```
Expected: 全部 PASS，末尾 `通过 5，失败 0`（T1 两条断言 + T2 两条 + T3 一条）。

- [ ] **Step 5: 实测拉一个真实条目（用已 init 的 faiss）**

⚠️ **路径基准**：`reference` 仓**不在**父仓内（它平级于 `StillEvolving`，见 `repos.yaml` 的
`path: ../reference`）。faiss 的实际位置是 `C:\code\reference\reference\vector\faiss`
—— 实测它**当前已 init**（13 MB），是 95 个里唯一已 init 的。

先确认 faiss 确实已 init 且 HEAD 落在 pin 上：
```bash
cd /c/code/reference/reference/vector/faiss && git rev-parse HEAD
cd /c/code/reference && git ls-files -s | grep "vector/faiss"
```
Expected: 两个 SHA **相同**，且等于 `02ea14372c9983f3eaa15698512180dc62ea234d`。

再跑拉取脚本：
```bash
cd /c/code/StillEvolving && bash scripts/fetch-reference.sh --name faiss
```
Expected: 识别为已 init 且 HEAD == pin → 跳过，输出"已是目标 commit"。

- [ ] **Step 6: 验证父仓保持干净**

Run:
```bash
cd /c/code/reference && git status --short
```
Expected: **空输出**。若出现 ` M reference/...` → 说明 checkout 没落到 pin 上，修 Step 3 的 checkout 逻辑。

- [ ] **Step 7: 验证 broken 条目确实被跳过**

Run:
```bash
cd /c/code/StillEvolving && bash scripts/fetch-reference.sh --name tdengine
```
Expected: 输出含 `SKIP` 与 `broken`，**不产生任何 git 拉取**（对比前后 `du -sh` 该目录大小不变）。

- [ ] **Step 8: 提交**

```bash
cd /c/code/StillEvolving
git add scripts/fetch-reference.sh scripts/test_fetch_reference.sh
git commit -m "feat: 实现按需拉取第三方库的 fetch-reference.sh"
```

---

### Task 6: 实现一致性校验与 bootstrap

**Files:**
- Create: `C:\code\StillEvolving\scripts\check_consistency.py`（**下划线**，Python 模块名不能含连字符）
- Create: `C:\code\StillEvolving\scripts\bootstrap.ps1`
- Create: `C:\code\StillEvolving\scripts\bootstrap.sh`
- Test: `C:\code\StillEvolving\scripts\test_check_consistency.py`

**Interfaces:**
- Consumes: Task 3（`repos.yaml`）、Task 4（catalog）
- Produces:
  - `python scripts/check_consistency.py` 退出码 0 = 全部一致，1 = 有问题；每条问题打印 `[仓库名] 缺失: <路径>`
  - `parse_repos(text: str) -> list[dict]` —— 解析 `repos.yaml`（标准库手写解析，G11）
  - `check_must_contain(repo_path: str, must: list[str]) -> list[str]` —— 返回缺失项列表
  - 复用 Task 4 的 `parse_catalog(text) -> list[dict]` 与 `render_manifest(entries) -> str`，
    位于 `<reference 仓根>/scripts/sync_catalog.py`，按文件路径加载（非 sys.path）
  - `bash scripts/bootstrap.sh` / `powershell -File scripts/bootstrap.ps1` —— 一键引导

- [ ] **Step 1: 写失败测试 —— must_contain 子集断言**

`C:\code\StillEvolving\scripts\test_check_consistency.py`：

```python
import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_consistency import parse_repos, check_must_contain

REPOS_YAML = """
version: 1
repos:
  - name: projects
    url: https://github.com/yinchengwang/projects.git
    fetch: submodule
    path: projects
    must_contain: [engine, apps, docs]
    description: 工程仓
"""


class TestParseRepos(unittest.TestCase):
    def test_parses_repos(self):
        repos = parse_repos(REPOS_YAML)
        self.assertEqual(len(repos), 1)
        r = repos[0]
        self.assertEqual(r["name"], "projects")
        self.assertEqual(r["fetch"], "submodule")
        self.assertEqual(r["path"], "projects")
        self.assertEqual(r["must_contain"], ["engine", "apps", "docs"])

    def test_parses_relative_parent_path(self):
        """reference 的 path 是 ../reference（相对父仓根的兄弟目录）。"""
        text = ("version: 1\nrepos:\n  - name: reference\n"
                "    path: ../reference\n    fetch: manifest\n"
                "    must_contain: [reference, docs, scripts]\n")
        repos = parse_repos(text)
        self.assertEqual(repos[0]["path"], "../reference")


class TestMustContain(unittest.TestCase):
    def test_reports_missing(self):
        """F4: must_contain 列的目录缺失必须被报出来。"""
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "engine"))
            os.mkdir(os.path.join(d, "docs"))
            missing = check_must_contain(d, ["engine", "apps", "docs"])
            self.assertEqual(missing, ["apps"])

    def test_subset_not_equality(self):
        """must_contain 是子集断言：仓里多出的目录不算违规。"""
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "engine"))
            os.mkdir(os.path.join(d, "extra_dir"))
            missing = check_must_contain(d, ["engine"])
            self.assertEqual(missing, [])

    def test_all_present(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            for n in ("engine", "apps"):
                os.mkdir(os.path.join(d, n))
            self.assertEqual(check_must_contain(d, ["engine", "apps"]), [])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd /c/code/StillEvolving && python scripts/test_check_consistency.py -v
```
Expected: FAIL，`ModuleNotFoundError: No module named 'check_consistency'`。

- [ ] **Step 3: 实现 check_consistency.py**

函数签名：

```python
def parse_repos(text: str) -> list[dict]:
    """解析 repos.yaml，返回仓列表。

    必须能处理行内列表 must_contain: [a, b, c]。
    必须保留 path 的 ../ 前缀（reference 用的就是 ../reference）。
    """


def check_must_contain(repo_path: str, must: list[str]) -> list[str]:
    """检查 repo_path 下 must 列出的每一项都存在，返回缺失项列表。

    子集断言：repo_path 下多出的其他目录不算违规。
    隐藏文件（以 . 开头）也算存在 —— 目录名如 .ai 需被检查。
    """


def main() -> int:
    """校验四仓一致性，返回退出码：0 = 一致，1 = 有问题。"""
```

**校验内容**（全部要实现）：
1. `repos.yaml` 存在且能解析
2. 每个 `fetch: submodule` 的仓：目录存在、是有效 git 仓、`git submodule status` 中无 `-` 前缀
3. 每个 `fetch: manifest` 的仓：`reference/` 目录存在
4. 每个仓的 `must_contain` 全部存在（F4）
5. `catalog.yml` 存在，且其中 `source: mirror` 的条目数 == `repos.yaml` 声明的 `upstream.total`（95）。
   **注意：不是总条目数（97）** —— catalog 有 97 条，其中 oceanbase / pklite 是 `source: none`（G16）
6. `catalog.yml` 每条 `pin_status` 合法（valid/broken/unresolvable）
6b. `catalog.yml` 的 `clone_url` 与 `.gitmodules` 的 `url` 不一致时**告警但不报错** ——
    两者职责不同：`.gitmodules` 是 git 原生记录（95 条中 6 条指向 gitee），`clone_url` 是
    "实测可按 SHA 拉到的地址"。实测 mysql 的 `.gitmodules` URL（gitee 镜像）取不到该 pin，
    而 GitHub 官方可取 → 允许分歧。告警格式：
    `[reference] clone_url 与 .gitmodules url 分歧: mysql`
7. `fetch-manifest.txt` 与 catalog 生成结果一致。
   **依赖**：`reference/scripts/sync_catalog.py` 的 `parse_catalog()` 与 `render_manifest()`。
   实现方式：在 `check_consistency.py` 里用 `importlib.util.spec_from_file_location()` 按**文件路径**加载
   `../reference/scripts/sync_catalog.py`（不能用 `import sync_catalog` —— 不同仓，不在同一 sys.path 上）

**输出格式**（每行一条，便于 grep）：
```
[projects] 缺失: openspec/specs/learning  ← 不对，must_contain 只查顶层
```
实际格式：
```
[projects] 缺失顶层项: engine
[reference] submodule 未初始化: reference/vector/faiss
[reference] catalog 条目数 97 != repos.yaml 声明的 95
```

- [ ] **Step 4: 运行测试确认通过**

Run:
```bash
cd /c/code/StillEvolving && python scripts/test_check_consistency.py -v
```
Expected: 5 个测试全部 PASS。

- [ ] **Step 5: 对真实仓库跑校验**

Run:
```bash
cd /c/code/StillEvolving && python scripts/check_consistency.py; echo "exit=$?"
```
Expected: 退出码 0。若报 `catalog 条目数 97 != 95` → 这是**预期行为**（catalog 97 含 2 个无源码条目），改判定为"catalog 条目数 ≥ total，且 `source: mirror` 的条目数 == total"。

- [ ] **Step 6: 实现 bootstrap.sh**

```bash
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
```

- [ ] **Step 7: 实现 bootstrap.ps1**

```powershell
# 一键引导 StillEvolving 工作树（Windows 原生）
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host '==> 初始化 submodule' -ForegroundColor Cyan
# 注意：绝不带 --recursive
git submodule update --init
if ($LASTEXITCODE -ne 0) { throw "submodule 初始化失败" }

Write-Host '==> 校验四仓一致性' -ForegroundColor Cyan
python scripts/check_consistency.py
if ($LASTEXITCODE -ne 0) { throw "一致性校验失败" }

Write-Host '==> 完成' -ForegroundColor Green
Write-Host '按需拉第三方库: bash scripts/fetch-reference.sh --tier core'
```

- [ ] **Step 8: 端到端验证 bootstrap**

Run:
```bash
cd /c/code/StillEvolving && bash scripts/bootstrap.sh; echo "exit=$?"
```
Expected: 退出码 0，三段输出正常。

- [ ] **Step 9: 提交**

```bash
cd /c/code/StillEvolving
git add scripts/check_consistency.py scripts/test_check_consistency.py scripts/bootstrap.sh scripts/bootstrap.ps1
git commit -m "feat: 实现四仓一致性校验与 bootstrap 引导脚本"
```

---

### Task 7: 内容归位 —— spec / progress / notes 迁移

**Files:**
- Move: `C:\code\StillEvolving\projects\openspec\specs\learning\*` → `C:\code\StillEvolving\learning\openspec\specs\learning\*`
- Move: 12 个纯学习向 `r*` spec 目录 → `C:\code\StillEvolving\learning\openspec\specs\`
- Move: `C:\code\StillEvolving\learning\r{25,30,33,35,36,37,38}-progress.md` → `learning\progress\`
- Move: `C:\code\StillEvolving\learning\notes\ds-{art,radix-tree,rtree,skiplist,ttree}.md` → `learning\notes\ds\`
- Move: `C:\code\StillEvolving\projects\archive\{final-report.md,debug_test.c,task-*-report.md}` → 对应日期目录（M10，用 `git mv`）
- Modify: `C:\code\StillEvolving\projects\docs\path-mapping.md`
- Modify: `C:\code\StillEvolving\projects\.ai\.claude\settings.json`
- Modify: `C:\code\StillEvolving\learning\scaffold\cpp\parallel_stl\NOTES.md`

**Interfaces:**
- Consumes: Task 3（仓库已就位）
- Produces: learning 仓含 `openspec/specs/`（47 个 spec）；projects 仓不再含学习轨 spec

- [ ] **Step 1: 确定要迁走的 12 个纯学习向 spec（逐个人工确认，不靠正则）**

判定规则（内容判定，命中任一即**留在 projects**）：
- 引用 `engineering/` 路径（**注意 `engineering/` 是 `engine/` 的旧名**）
- 引用 `apps/` 路径（projects 专属的小程序目录）
- 引用 `engine/` 路径

Run（列出全部 32 个 `r*` 目录及各自命中的信号）：
```bash
cd /c/code/StillEvolving/projects && for d in openspec/specs/r*/; do
  sig=""
  grep -q "engineering/" "$d/spec.md" 2>/dev/null && sig="$sig engineering"
  grep -q "engine/" "$d/spec.md" 2>/dev/null && sig="$sig engine"
  grep -q "apps/" "$d/spec.md" 2>/dev/null && sig="$sig apps"
  echo "$(basename $d):$sig"
done
```
Expected: 无信号的行即候选迁移对象。**实测应得到 12 个**（`r12b-systems` `r19-cpp-systems` `r23-linux-perf` `r24-linux-storage` `r26-linux-advanced-net` `r29-ds-advanced` `r30-python-basics` `r31-python-advanced` `r32-python-tools` `r33-grokking-algo` `r37-grokking-db` `r38-grokking-ml`）。

⚠️ **`r6-language-tranche` 命中 `apps` 信号**（引用 `apps/web/reading-radar/data/r6-progress.md`）→ **留在 projects**，不迁移。

- [ ] **Step 2: 在 learning 仓建 openspec 结构**

```bash
cd /c/code/StillEvolving/learning
mkdir -p openspec/specs openspec/changes openspec/archived
```

- [ ] **Step 3: 迁移 learning 轨 spec（35 文件）**

```bash
cd /c/code/StillEvolving
mkdir -p learning/openspec/specs/learning
cp -r projects/openspec/specs/learning/. learning/openspec/specs/learning/
ls learning/openspec/specs/learning/ | wc -l
```
Expected: `35`。

- [ ] **Step 4: 迁移 12 个纯学习向 spec**

按 Step 1 确认的清单逐个复制（不要用通配符，避免误迁）：
```bash
cd /c/code/StillEvolving
for s in r12b-systems r19-cpp-systems r23-linux-perf r24-linux-storage \
         r26-linux-advanced-net r29-ds-advanced r30-python-basics \
         r31-python-advanced r32-python-tools r33-grokking-algo \
         r37-grokking-db r38-grokking-ml; do
  cp -r "projects/openspec/specs/$s" "learning/openspec/specs/$s"
done
ls learning/openspec/specs/ | wc -l
```
Expected: `13`（12 个新 + `learning` 子目录）。

- [ ] **Step 5: 从 projects 删除已迁走的 spec**

```bash
cd /c/code/StillEvolving/projects
rm -rf openspec/specs/learning
for s in r12b-systems r19-cpp-systems r23-linux-perf r24-linux-storage \
         r26-linux-advanced-net r29-ds-advanced r30-python-basics \
         r31-python-advanced r32-python-tools r33-grokking-algo \
         r37-grokking-db r38-grokking-ml; do
  rm -rf "openspec/specs/$s"
done
ls openspec/specs/ | wc -l
```
Expected: `25`（原 38 个顶层项减去 `learning` 子目录与 12 个 `r*` 目录）。

- [ ] **Step 6: 验证剩余 20 个 `r*` spec 仍完整**

```bash
cd /c/code/StillEvolving/projects && ls openspec/specs/ | grep "^r" | wc -l
```
Expected: `20`（32 个 `r*` 减去迁走的 12 个）。

⚠️ **注意是 20 不是 19** —— 设计文档 §C18 说的"19 个留在 projects"只统计了命中 `engineering/` 的那批，
漏掉了命中 `apps/` 的 `r6-language-tranche`。实测 12 个可迁、20 个留下，两者相加为 32。

同时验证顶层总项数：
```bash
cd /c/code/StillEvolving/projects && ls openspec/specs/ | wc -l
```
Expected: `25`（36 个顶层目录 + 2 个顶层 .md，减去 `learning` 子目录与 12 个 `r*` = 25）。

- [ ] **Step 7: 迁移 learning 的散落 progress 文件**

```bash
cd /c/code/StillEvolving/learning
for p in r25 r30 r33 r35 r36 r37 r38; do
  mv "${p}-progress.md" "progress/${p}-progress.md"
done
ls progress/
```
Expected: `r25-progress.md` `r26-progress.md` `r30-progress.md` `r32-progress.md` `r33-progress.md` `r35-progress.md` `r36-progress.md` `r37-progress.md` `r38-progress.md` —— 共 9 个。顶层不再有 `r*-progress.md`。

- [ ] **Step 8: 迁移 notes 顶层的 ds 笔记**

```bash
cd /c/code/StillEvolving/learning
mkdir -p notes/ds
for f in ds-art ds-radix-tree ds-rtree ds-skiplist ds-ttree; do
  mv "notes/${f}.md" "notes/ds/${f}.md"
done
ls notes/ds/
```
Expected: 5 个 md。`notes/` 顶层剩 `README.md`（保留）。

- [ ] **Step 8b: 归档 projects/archive/ 根层的 11 个文件（M10）**

`archive/` 根层有 11 个文件散落，未归入任何日期目录：
`debug_test.c` `final-report.md` `task-{2.1,2.2,3.1,3.2,4,5,6,7,8}-report.md`

⚠️ **实测这 11 个文件是"已跟踪"状态**（`git ls-files archive/` 能列出全部 11 个），
所以**必须用 `git mv`，不能用裸 `mv`** —— 裸 `mv` 会让 git 看成"删除 + 新增"，丢失文件历史。

先看每个文件属于哪次变更：
```bash
cd /c/code/StillEvolving/projects && git ls-files archive/ | grep -E "^archive/[^/]+$"
```
人工归位到对应的日期目录（`archive/` 下已有 **32** 个日期命名的 openspec 归档目录；
另有 3 个非日期目录 `db-sql-over-kv/` `distributed/` `openspec/` **不是**归位目标），
然后用 `git mv` 移动：
```bash
cd /c/code/StillEvolving/projects
git mv archive/final-report.md archive/<对应日期目录>/final-report.md
# … 其余 10 个同理
git status --short
```
Expected: `git status --short` 显示 11 行 `R`（rename），**不是** `D` + `??`。

⚠️ 若某个 `task-*-report.md` 找不到对应变更，就近新建 `archive/misc-reports/` 存放，不要留在根层。

- [ ] **Step 9: 把 .sync-pipeline-state.json 加入 gitignore**

```bash
cd /c/code/StillEvolving/learning
echo "notes/.sync-pipeline-state.json" >> .gitignore
rm -f notes/.sync-pipeline-state.json
```
Expected: 该工具状态文件不再被跟踪。

- [ ] **Step 10: 更新硬编码路径的引用**

**实测事实**：这些文件里硬编码的是**旧路径 `C:/code/book/...`**（不是 `C:/code/...`），且分属三个不同的目标仓：

| 文件 | 实测硬编码字符串 | 新路径 |
|---|---|---|
| `projects/.ai/.claude/settings.json` | `C:/code/book/test/all_in_one_test.exe`、`C:/code/book/test/vector_index/hnsw/hnsw_gtest.exe`、`C:/code/book/test/vector_index/ivf/ivf_gtest.exe` | `C:/code/StillEvolving/projects/test/...` |
| `projects/docs/path-mapping.md` | `C:/code/book-baseline`、`C:\\code\\` | `C:/code/StillEvolving/projects/...` |
| `learning/scaffold/cpp/parallel_stl/NOTES.md` | `C:/code/book/engineering/src/algo-prod/distance/distance.c` 等 3 处 | `C:/code/StillEvolving/projects/engine/src/algo-prod/...`（注意 `engineering/` 是 `engine/` 的旧名） |

查找全部命中：
```bash
cd /c/code/StillEvolving && grep -rn "C:[/\\]\\*code[/\\]\\*book" projects/.ai/.claude/settings.json projects/docs/path-mapping.md learning/scaffold/cpp/parallel_stl/NOTES.md 2>/dev/null
```
Expected: 至少 7 行命中。

替换规则（**先认旧名，再定新路径**，不要盲目全局替换 `C:/code`）：
1. `C:/code/book/engineering/` → `C:/code/StillEvolving/projects/engine/`（旧名 `engineering` → 新名 `engine`）
2. `C:/code/book/test/` → `C:/code/StillEvolving/projects/test/`
3. `C:/code/book-baseline` → `C:/code/StillEvolving/projects` （或按实际语义确定）
4. `C:\code\` → 逐条判断目标仓（projects / learning / reference 三者不同）

⚠️ **不要用 `sed` 全局替换 `C:/code`** —— 三个文件的目标仓不同（projects / learning / reference 仍在 `C:/code/reference`），
盲目替换会产出 `C:/code/StillEvolving/book/...` 这类错误路径。逐条改。

`projects/docs/path-mapping.md` 是**路径契约文档**，必须完整更新整张映射表，不能只改命中的那几行。

- [ ] **Step 11: 提交 learning 仓**

```bash
cd /c/code/StillEvolving/learning
git add -A
git commit -m "refactor: 接收学习轨 openspec spec，归位 progress 与 notes/ds"
git push origin main
```

- [ ] **Step 12: 提交 projects 仓**

```bash
cd /c/code/StillEvolving/projects
git add -A
git commit -m "refactor: 迁出学习轨 spec，更新路径映射"
git push origin main
```

- [ ] **Step 13: 提交并推送父仓的 gitlink 更新**

```bash
cd /c/code/StillEvolving
git add projects learning
git commit -m "chore: 更新 projects/learning submodule pin"
git push origin main
```
⚠️ **必须 push** —— 父仓的 gitlink 记录着两个子仓的 pin，不推送则远端 StillEvolving 仍指向旧 pin，
别人 clone 下来拿到的是迁移前的 projects/learning。

---

### Task 8: 修复跨仓断链与 README 口径

**Files:**
- Modify: `C:\code\reference\docs\db-wiki\README.md`（193-194 行）
- Modify: `C:\code\reference\docs\rag-wiki\README.md`（56-57 行）
- Modify: `C:\code\reference\docs\agent-wiki\README.md`（60-61 行）
- Modify: `C:\code\reference\README.md`
- Modify: `C:\code\reference\.gitignore`
- Modify: `C:\code\reference\reference\AUDIT.md`
- Modify: `C:\code\reference\docs\db-wiki\time-series\tdengine.md`（M22 加警示，75 处引用）
- Modify: `C:\code\reference\docs\db-wiki\relational\mysql.md`（M22 加警示，21 处引用）
- Modify: `C:\code\reference\docs\db-wiki\key-value\pebble.md`（M22 加警示，4 处引用）
- Modify: `C:\code\reference\docs\db-wiki\key-value\dragonfly.md`（M22 加警示，2 处引用）
- Modify: `C:\code\reference\docs\db-wiki\columnar\druid.md`（M22 加警示，0 处引用但 pin 同样失效）
- Modify: `C:\code\reference\docs\db-wiki\distributed-sql\oceanbase.md`（无源码镜像，20 处引用无从校验）

**Interfaces:**
- Consumes: Task 7（projects 已推送，`docs/analysis/` 内容已在新位置）
- Produces: 16 处断链修复（对应 14 个独立目标文件）；reference README 的分类口径与警告正确

- [ ] **Step 1: 确认 16 处断链仍存在**

```bash
cd /c/code/reference && grep -o "\.\./gap-analysis/[a-zA-Z0-9_-]*\.md" docs/*/README.md | wc -l
```
Expected: `16`（**不是 13** —— 实测 db-wiki 12 处 + rag-wiki 2 处 + agent-wiki 2 处，
分布在 6 行上；其中 `README.md` 被三份 README 各引一次，故 16 处引用只对应 14 个独立目标文件）。

⚠️ **不要用 `grep -rn ... | wc -l`** —— 那样只数到 **6 行**，会误判为"只有 6 处"。
必须用 `grep -o` 数 URL 出现次数。

- [ ] **Step 2: 取得 projects 当前 commit SHA（用于 blob URL）**

```bash
cd /c/code/StillEvolving/projects && git rev-parse HEAD
```
Expected: 40 位 SHA（Task 7 Step 12 推送后的最新）。

- [ ] **Step 3: 替换 db-wiki/README.md 的两行**

原第 193 行：
```
- 总报告：[docs/gap-analysis/README.md](../gap-analysis/README.md)
```
新：
```
- 总报告：[gap-analysis/README.md](https://github.com/yinchengwang/projects/blob/<SHA>/docs/analysis/README.md)
```
（`<SHA>` 替换为 Step 2 得到的实际 SHA）

原第 194 行（**11 个**子报告链接，不是 12）：每个 `../gap-analysis/<分类>.md` 改为
`https://github.com/yinchengwang/projects/blob/<SHA>/docs/analysis/<分类>.md`

分类名与目标文件一一对应（实测确认，共 **11** 个）：
`relational` `key-value` `document` `columnar` `time-series` `search` `vector` `graph` `stream` `embedded` `extension`

- [ ] **Step 3b: 在三份 wiki README 中标注无对应源码的笔记（C4 / §5.5.3）**

笔记层是源码层的**超集**，多出的 4 篇是"商业产品调研"型笔记，**无对应源码镜像**。
在 `docs/db-wiki/README.md`、`docs/rag-wiki/README.md`、`docs/agent-wiki/README.md` 各加一段：

```markdown
## 无对应源码镜像的笔记

以下笔记记录的是产品认知而非源码精读，因此不含精确行号引用，也无法做行号校验：

| 笔记 | 说明 |
|---|---|
| `distributed-sql/oceanbase.md` | 无源码镜像（catalog 标 `source: none`） |
| `embedded/pklite.md` | 无源码镜像（catalog 标 `source: none`） |
| `../rag-wiki/commercial-rag-products.md` | 商业产品调研，非源码精读 |
| `../agent-wiki/commercial-agent-products.md` | 商业产品调研，非源码精读 |
```

这解释了为什么笔记覆盖率不是 100% —— 其余分类的笔记与源码镜像严格一一对应。

- [ ] **Step 4: 替换 rag-wiki/README.md 的两行**

`../gap-analysis/README.md` → `https://github.com/yinchengwang/projects/blob/<SHA>/docs/analysis/README.md`
`../gap-analysis/rag.md` → `https://github.com/yinchengwang/projects/blob/<SHA>/docs/analysis/rag.md`

- [ ] **Step 5: 替换 agent-wiki/README.md 的两行**

`../gap-analysis/README.md` → `.../docs/analysis/README.md`
`../gap-analysis/agent.md` → `.../docs/analysis/agent.md`

- [ ] **Step 6: 验证断链已清零且链接格式正确**

```bash
cd /c/code/reference && grep -o "\.\./gap-analysis/[a-zA-Z0-9_-]*\.md" docs/*/README.md | wc -l
grep -o "yinchengwang/projects/blob/[0-9a-f]\{40\}/docs/analysis/[a-zA-Z0-9_-]*\.md" docs/*/README.md | wc -l
```
Expected: 分别为 `0` 和 `16`。

- [ ] **Step 7: 修正 reference README 的分类口径与加警告**

`C:\code\reference\README.md` 两处改动：
1. "14 个技术分类" → "15 个技术分类"（`ai/` 是二级分类，含 `agent` 与 `rag`）
2. 在"克隆"一节加入警告：

```markdown
### ⚠️ 禁止 `git submodule update --init --recursive`

本仓的 95 个第三方库都是 submodule，递归初始化会一次性拉取约 25 GB / 53.6 万文件。

按需拉取请用顶层仓的脚本：

```bash
bash scripts/fetch-reference.sh --name faiss      # 拉单个
bash scripts/fetch-reference.sh --model vector     # 拉某个分类
bash scripts/fetch-reference.sh --tier core        # 拉核心集
```
```

- [ ] **Step 8: 修正 .gitignore 中不生效的规则**

`C:\code\reference\.gitignore` 删除这两行：
```
reference/*/
!reference/*/README.md
```
替换为注释说明：
```
# submodule 工作树不入父仓索引（gitlink 机制），gitignore 对 gitlink 路径不生效
# 参见 design doc C5 / C17
```

- [ ] **Step 9: 给失效 pin 的笔记加校对警示（M22）**

以下 6 篇笔记的 pin 已失效或缺失，行号引用当前**无法校验**。在每篇的文件**开头**（标题之后、正文之前）
插入一段警示：

> ⚠️ **本文的行号引用当前无法校验。**
> 原因：`<原因>`。行号可能已随上游漂移，需人工重新校对后才能作为精确引用使用。

| 笔记 | 失效原因 | 引用处数 |
|---|---|---|
| `docs/db-wiki/time-series/tdengine.md` | gitlink pin `62385b1e…` 在上游不存在（实测 `not our ref`） | 75 |
| `docs/db-wiki/relational/mysql.md` | pin `23e360a7…` 真实存在，但旧镜像地址不含它（已改用 GitHub 官方） | 21 |
| `docs/db-wiki/key-value/pebble.md` | gitlink pin `68315f17…` 在上游不存在 | 4 |
| `docs/db-wiki/key-value/dragonfly.md` | gitlink pin `dafb825b…` 在上游不存在 | 2 |
| `docs/db-wiki/columnar/druid.md` | gitlink pin `fa8dc991…` 在上游不存在 | 0 |
| `docs/db-wiki/distributed-sql/oceanbase.md` | 无源码镜像（`source: none`），引用无从校验 | 20 |

**注意**：警示只加在文件开头，**不改动任何行号引用本身** —— 改行号会让"哪一条失效"这件事无法追溯。

- [ ] **Step 10: 追加 AUDIT.md 记录**

在 `C:\code\reference\reference\AUDIT.md` 末尾追加本次拉取结果（成功/跳过/失败统计与失败原因）。

- [ ] **Step 11: 验证 reference 仓干净且提交**

```bash
cd /c/code/reference
git status --short
git add -A
git commit -m "docs(reference): 修复 16 处跨仓断链，统一分类口径，加递归克隆警告"
git push origin main
```
Expected: `git status --short` 在 add 前显示 **12 个**被改文件（3 份 wiki README + reference README +
.gitignore + AUDIT.md + 6 篇失效 pin 笔记）；提交后干净。

---

## 自检清单

按 writing-plans 的自检要求逐条核对：

**1. Spec 覆盖** —— 设计文档的每个可实施要求是否都有任务承接：

| 设计文档章节 | 承接任务 |
|---|---|
| §5.1 StillEvolving 目录树 | Task 3（Step 7-10） |
| §5.2 projects 目录树 | Task 3 Step 7（`must_contain`）+ Task 7 |
| §5.3 learning 目录树 | Task 3 Step 7 + Task 7 |
| §5.4 ai-docs 目录树 | Task 2 |
| §5.5 reference 目录树 | Task 4（catalog）+ Task 8（README） |
| §5.5.2 catalog 字段规范 | Task 4 Step 5-6 |
| §5.5.3 笔记层对应关系 | Task 8 Step 3-5 |
| §5.5.4 拉取脚本契约 | Task 5 |
| §6 repos.yaml 规范 | Task 3 Step 7 + Task 6 Step 3 |
| §7.1 M1 | Task 1 Step 3 |
| §7.1 M21 | Task 2 |
| §7.1 M2 | Task 3 Step 3-6 |
| §7.1 M3/M4/M5 | Task 4 |
| §7.1 M6 | Task 5 |
| §7.2 路径 A/B 抉择 | Task 3 Step 2（选定路径 A） |
| §7.3 M7/M8 | Task 1 Step 6 |
| §7.3 M11 | Task 3 Step 7（`must_contain` 含 third_part） |
| §7.3 M12 | Task 5 Step 3（submodule 内 fetch） |
| §7.3 M13 | Task 8 Step 8 |
| §7.4 M14/M15 | Task 7 Step 1-6 |
| §7.4 M16/M17/M18 | Task 7 Step 7-9 |
| §7.4 M19 | Task 8 Step 3-5 |
| §7.4 M20 | Task 8 Step 7 |
| §7.4 M22 | Task 4 Step 5（broken 标注） |
| §11 自主决定 1-34 | 全部对应到上述任务 |

**2. 步骤粒度** —— 每个步骤是一个动作 + 可检查结果：所有 Step 都带具体命令与 Expected 输出。唯一偏"描述"的是 Task 4 Step 5（pin 状态表），但该表本身给出了每条的确切值，实施者无需再做判断。

**3. 类型一致性** —— 跨任务引用的名字已核对：
- `parse_catalog(text) -> list[dict]`（Task 4 定义，Task 4/5 使用）
- `render_manifest(entries) -> str`（Task 4 定义，Task 4 使用）
- `parse_repos(text) -> list[dict]`（Task 6 定义，Task 6 使用）
- `check_must_contain(repo_path, must) -> list[str]`（Task 6 定义，Task 6 使用）
- `repos.yaml` 字段名 `must_contain`（Task 3 定义，Task 6 消费）
- catalog 字段名 `commit` / `clone_url` / `pin_status` / `source`（Task 4 定义，Task 5 消费）
- manifest 列名 `model name clone_url commit pin_status`（Task 4 定义，Task 5 消费）

**4. Review Focus 覆盖** —— F1~F5 各自的测试位置：
- F1 幂等 → Task 5 Step 1（T1/T2）+ Step 5 实测
- F2 broken 跳过 → Task 5 Step 1（T2）+ Step 7 实测 + Task 3（catalog 标注）
- F3 CRLF/LF → Task 4 Step 1（`test_parses_crlf` / `test_parses_lf`）
- F4 must_contain 缺失 → Task 6 Step 1（`test_reports_missing`）
- F5 空仓 submodule add → Task 2 Step 7/8 + Task 3 Step 5

**5. 比例** —— 本计划约 640 行，设计文档 1244 行。计划短于 spec，未把代码写成转录本：脚本实现只给签名与要点，测试只给断言与期望值。

---

## 实施顺序与检查点

| 检查点 | 时机 | 判定 |
|---|---|---|
| CP1 | Task 2 完成后 | `git ls-remote AI-DOCS` 返回非空且 HEAD→main |
| CP2 | Task 3 完成后 | `git submodule status` 三行无 `-`；`C:\code` 下无 `book` 目录 |
| CP3 | Task 4 完成后 | `sync_catalog.py --check` 退出 0；manifest 97 行 5 列 |
| CP4 | Task 5 完成后 | `--name tdengine` 被跳过；`git status` 干净 |
| CP5 | Task 6 完成后 | `check_consistency.py` 退出 0；`bootstrap.sh` 端到端通过 |
| CP6 | Task 8 完成后 | 断链数 0；跨仓链接数 16 |

**每个检查点通过后再进入下一任务。** 任一检查点失败，回退到该任务修复，不向前推进。

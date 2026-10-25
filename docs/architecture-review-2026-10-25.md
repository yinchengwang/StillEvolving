# 四仓重组架构评审 —— 2026-10-25

> 评审对象：`C:\code` 下的仓库重组方案
> 目标形态：`StillEvolving`（顶层）+ `projects` / `learning` / `reference` / `AI-DOCS`
> 结论摘要：**拆分轴正确，超级仓形态需调整**——推荐「B · 混合」形态

---

## 一、现状实测

评审前先把四个仓的真实状态跑了一遍（`.gitmodules`、`submodule status`、
体积、`git ls-files` 跟踪状态），下面所有数字都是实测值，不是估算。

| 仓 | 跟踪文件 | .git | 工作树 | 关键构成 |
|---|---|---|---|---|
| `book` → projects | 5 730 | 1.7 GB | 5.3 GB | `build/` 2.9 GB（未跟踪）、`dataset/` 692 MB（LFS 673 MB）、`docs/` 268 md、`.ai/` 202 文件 / 98 SKILL.md |
| `learning` | 2 162 | 12 MB | 108 MB | `notes/` 230 篇、`third_part/googletest` submodule |
| `reference` | — | 6.8 MB | 24 MB | `reference/` 下 **95 个 submodule，94 个未 init**，仅 `vector/faiss` 已 init |

其它事实：

- `book` 已自带 2 个 submodule：`vendor/third_part/googletest`、`engine/third_part/uthash`
- `book/.ai/` 有 202 个受跟踪文件、98 个 `SKILL.md`；`skills-lock.json` 里 38 个 skill
  全部来自 `mattpocock/skills` 一个来源
- `book/.workbuddy-ai/` **0 个文件受跟踪**（`.gitignore` 第 156 行忽略整个目录）
- CI 只有 projects 有：`.github/workflows/ci.yml` + `asan.yml`；learning / reference 无 CI
- `book` 根 `CMakeLists.txt` 已是「工程调度器」，`learning/` 分支已移除
- `learning/CMakeLists.txt` 内有 `guard_no_cross_track_reference("engineering/")` 双轨守卫，
  且守卫仅在 `${CMAKE_CURRENT_LIST_DIR}/../cmake/dual-track-guard.cmake` 存在时启用
  —— 说明独立仓布局已被显式支持
- 磁盘：C: 927 G 总量 / 657 G 已用 / **271 G 可用**

---

## 二、方案评审

### 2.1 拆分轴：正确，保留

`projects / learning / reference / AI-DOCS` 的分界是**内容性质**，不是时间线也不是团队：

- 每个仓都能独立 clone、独立演进、独立发布
- `book` 的 README 已经写明「学习轨与参考轨已切出为独立仓」，把切分成果按用途归拢是顺理成章
- `learning/CMakeLists.txt` 已内建双轨守卫、显式支持独立仓布局 —— 拆分在代码层面已经落地

**结论：四仓划分本身不需要动。**

### 2.2 问题一：reference 进 submodule 树 = 三层嵌套，25 GB 成本

`reference/.gitmodules` 有 95 条 submodule 记录，**当前 94 个未 init**（只有 `vector/faiss`
拉下来了）。这说明上游镜像机制实际已半废弃：

- reference 的**真资产**是 `docs/`（5 MB wiki，75+ 篇带精确源码行号的笔记）
  + `reference/catalog.yml` + `reference/fetch-manifest.txt`
- 那 95 份上游源码属**可再生缓存**，随时可重拉

若把 reference 作为 StillEvolving 的 submodule，层级变成
`StillEvolving → reference → 95 个上游仓`，`git clone --recursive` 会去拉
**≈ 25 GB / 53.6 万文件**。而 `book/.workbuddy-ai/memory/MEMORY.md` 里刚记着
「2026-10-25 切仓回收约 25 GB」——这个成本会原样再付一次。

**约束（不能忽略）**：`reference/docs/` 里的引用是精确到行的
（如 `faiss/index_factory.cpp:1227`），现在靠 submodule pin 保证上游 commit 不漂。
改成脚本拉取时，**必须在 `catalog.yml` 为每个上游补 `commit` 字段**，否则行号引用会随
上游漂移而失效。`scripts/check-wiki-refs.py` 的模式 A（子模块已 init）恰好依赖这个 pin，
模式 B 只做零行号兜底 —— pin 一丢，模式 A 就永久失效。

### 2.3 问题二：AI-DOCS 的边界必须切在「跨项目」而非「跟 AI 有关」

`projects` 里的 AI 产物是**两类**，整体搬走会出事：

| 留在 projects（项目级上下文） | 进 AI-DOCS（跨项目复用） |
|---|---|
| `.ai/` 202 文件 / 98 个 SKILL.md | 通用 skill 源（跨项目复用的模板） |
| `CLAUDE.md` 17 KB、`AGENTS.md` 4.6 KB | AI 工作方法论、流程与规约 |
| `openspec/`（archived / changes / specs） | 跨项目的分析报告、复盘 |
| `skills-lock.json` | — |
| `.workbuddy-ai/`（本就被 gitignore） | — |

左列是 agent 在仓内干活时**读的规约**。搬到独立仓后，agent 在 projects 里就找不到
`.ai/` 和 `CLAUDE.md` 了 —— 它会退化成没有上下文的裸模型。左列必须留在仓内。

右列才是「所有 AI 的工作文档」的正主。

### 2.4 问题三：迁移动作清单里的残留与坑

| 项 | 状态 | 处理 |
|---|---|---|
| `book` → `projects` 改名后本地 remote | 仍指向 `.../book.git`（GitHub 301 重定向可用但有 warning） | `git remote set-url origin https://github.com/yinchengwang/projects.git` |
| `3D相册/` | **根本不是 git 仓**（纯 html/css/img，无 `.git`） | 要进仓先 `git init` |
| `verify_learning/` | 坏掉的残留 clone（branch broken，remote 指向 learning.git） | 直接删 |
| `book.worktrees/` 3 个目录（999 MB） | **全是孤立 worktree**：`.git` 文件指向 `C:/code/book/.git/worktrees/<name>`，但主仓 `.git/worktrees/` 不存在，`git worktree list` 只列主仓一条 → git 完全不认 | 确认内容已回主仓后删除；`minimax-coding-plan-implementation/`（942 MB）还留着 `engineering/` 旧布局 + shell 转义事故残留目录 `'[{type:` / `0` / `0"` |
| googletest 重复 | `projects/vendor/third_part/` 与 `learning/third_part/` 各一份 | submodule 生态下冲突风险上升，可考虑统一到上层 |
| CI 覆盖 | 只有 projects 有（`ci.yml` + `asan.yml`） | learning / reference 需不需要 CI，取决于是否要跑测试 |
| `projects/build/` 2.9 GB | 未跟踪，`.gitignore` 已覆盖 | 无影响 |

---

## 三、三种超级仓形态

### A · 纯 submodule（四仓全部进树）

- 层级 3 层，`clone --recursive` ≈ 25 GB
- 父仓每次 bump 子模块指针都是一次提交，多仓并行开发时噪音大
- 优点：心智模型最简单，`git clone --recursive` 一条命令全到位

### B · 混合（推荐）

- `projects` / `learning` / `AI-DOCS` 三个自有仓走 submodule → 层级 2 层
- `reference` 降级为**清单驱动**：`repos.yaml` + bootstrap 脚本按需拉取，不进子模块树
- `catalog.yml` 补 `commit` pin，保住 wiki 精确行号引用
- 父仓职责收敛为：**版本锚点 + 一键初始化 + 索引**，不装内容
- `clone --recursive` ≈ 200 MB（三个自有仓），reference 按需拉

### C · 纯索引仓

- 父仓只有 `README.md` + `repos.yaml` + `bootstrap` 脚本，不装任何内容
- 层级 0 层，clone 几 MB
- 缺点：失去版本锚点能力，需要自写脚本维护

### 推荐：B

理由：自有仓之间需要版本锚定（子模块指针能锁住「这一组代码是配套的」），
而 reference 与其它三仓**没有版本耦合**，它只是可再生的参考材料。把它塞进
submodule 树换来的是 25 GB 和三层嵌套，换不回任何东西。

---

## 四、推荐目标结构

```
StillEvolving/                      # 顶层：索引 + 版本锚点，不装内容
├── README.md                       # 全景索引：四仓职责一句话 + 当前状态
├── repos.yaml                      # 清单：URL / 角色 / pin / 拉取策略
├── .gitmodules                     # 只含 projects / learning / ai-docs
├── scripts/
│   ├── bootstrap.ps1               # 一键初始化（Windows）
│   └── fetch-reference.sh          # 按 catalog.yml 拉上游镜像（带 commit pin）
├── projects/                       # submodule → yinchengwang/projects
├── learning/                       # submodule → yinchengwang/learning
└── ai-docs/                        # submodule → yinchengwang/AI-DOCS
```

克隆成本：25 GB / 53.6 万文件 → **约 200 MB**。

---

## 五、待定决策（下一步）

1. 是否采纳形态 B？若采纳，`reference` 的 95 个 submodule 是否从 `.gitmodules`
   迁到 `catalog.yml` 的 commit pin + 脚本拉取？
2. AI-DOCS 的具体收录边界：右列哪些优先迁？
3. `book.worktrees/` 那 999 MB 残留（其中 942 MB 是旧 `engineering/` 布局）是否已
   回主仓，可否直接删除？
4. learning / reference 是否需要补 CI？

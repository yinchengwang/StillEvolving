# StillEvolving 目录规范

本文是四个仓库的目录树与归属判定规则总览。机器可读版见仓库根目录的 `repos.yaml`（`must_contain` 字段）。

- 设计文档原件：[`superpowers/specs/2026-10-25-stillevolving-repo-layout-design.md`](superpowers/specs/2026-10-25-stillevolving-repo-layout-design.md) §5
- 父仓只放**关系**，不放业务代码。

---

## 1. 四个仓库总览

| 仓 | 获取方式 | 路径 | 角色 |
|---|---|---|---|
| projects | submodule | `projects/` | 工程仓（引擎 + 小程序 + 项目级文档 + agent 规约） |
| learning | submodule | `learning/` | 学习仓（笔记 + 脚手架 + 题解 + 进度） |
| ai-docs | submodule | `ai-docs/` | AI 工作文档仓（跨项目复用的模板与方法论） |
| reference | 独立仓 + 清单拉取 | `../reference/` | 第三方源码镜像 + 源码笔记（**不进 submodule 树**） |

**为什么 `reference/` 不在 StillEvolving 的目录树里**：它内部有 95 个第三方库 submodule，嵌套进去会让 `git clone --recurse-submodules` 一次性拉取 25 GB / 53.6 万文件。因此 reference 作为独立仓独立 clone，位置由使用者决定（推荐 `C:\code\reference`，与三个 submodule 平级但**不在** StillEvolving 内），其上游 95 个库由 `reference/reference/catalog.yml` 声明 commit、按需克隆。

---

## 2. 目录树

### 2.1 StillEvolving（顶层聚合仓）

```
StillEvolving/
├── README.md                    # 这是一家人：四个仓的关系、各自职责、bootstrap 入口
├── repos.yaml                   # 机器可读的四仓清单（唯一权威的"关系"定义）
├── .gitmodules                  # 三个自维护 submodule 的 pin
├── .gitignore
├── LICENSE
├── docs/
│   ├── architecture.md          # 本文：目录规范总览
│   └── superpowers/specs/        # 设计与计划文档
├── scripts/                     # Task 5/6 创建，届时才有内容
│   ├── bootstrap.ps1            # Task 6：Windows：一键拉起三个 submodule + 校验
│   ├── bootstrap.sh             # Task 6：POSIX 同上
│   ├── fetch-reference.sh       # Task 5：按 catalog.yml 拉取第三方库到指定 commit
│   └── check_consistency.py     # Task 6：校验四仓关系与 catalog 一致性（下划线命名，Python 可 import）
└── projects/                    # submodule → yinchengwang/projects.git
├── learning/                    # submodule → yinchengwang/learning.git
└── ai-docs/                     # submodule → yinchengwang/AI-DOCS.git
```

**为什么 `repos.yaml` 与 `.gitmodules` 并存**：`.gitmodules` 是 git 的原生机制，但表达不了 `fetch: manifest` 这种策略，也放不了"这个仓该放什么"的语义说明。`repos.yaml` 承载语义，`.gitmodules` 承载 git 事实。两者由 `check_consistency.py` 保证不漂移。

### 2.2 projects（工程仓）

```
projects/
├── engine/                      # ★ 核心：自研数据库/搜索引擎引擎
│   ├── src/
│   │   ├── db/                  # 存储引擎、索引、事务
│   │   ├── include/             # 公共头文件
│   │   ├── algo-prod/           # 生产级算法
│   │   ├── sdk/                 # 对外 SDK
│   │   ├── redis/               # Redis 协议兼容层
│   │   ├── ds/                  # 数据结构
│   │   └── cpp/                 # C++ 基础设施
│   ├── test/                    # 测试
│   ├── tools/                   # 工具
│   ├── docs/                    # 引擎内文档
│   ├── third_part/uthash/       # submodule（gitee mirrors）
│   ├── cmake/  drivers/  proto/  sdk/  include/  scripts/  test_data/
│   └── .superpowers/
├── apps/                        # ★ 应用层：微信小程序
│   ├── knowledge-hub/
│   ├── programmer-workbench/
│   ├── games/
│   ├── trip-log/
│   └── .archive/
├── docs/                        # ★ 文档层
│   ├── process/                 # 流程与规范
│   ├── diagrams/                # 图表
│   ├── arch/                    # 架构设计
│   ├── analysis/                # 差距分析（★ 见 links 修复）
│   ├── storage/                 # 存储设计
│   └── (root)                   # 顶层文档
├── openspec/                    # ★ 变更与规格
│   ├── specs/                   # 38 个顶层条目（32 个 r* 目录 + 2 个非 r* 目录 + engineering/ + learning/ + 2 个 .md）
│   │   ├── engineering/         # 工程轨
│   │   ├── learning/            # ★ 学习轨残留，待迁出
│   │   └── (32 个 r* 目录)
│   ├── changes/                 # 8 个进行中变更
│   ├── archived/
│   └── config.yaml
├── .ai/                         # ★ agent 规约 — 禁止搬走
│   ├── .agents/
│   ├── .claude/
│   ├── .opencode/
│   └── .vscode/
├── vendor/third_part/googletest/  # submodule — 与 learning 重复，刻意保留两份
├── vendor/cmake/
├── dataset/                     # 数据集（含 LFS 对象）
├── scripts/
├── archive/                     # 历史归档（日期命名的 openspec 归档 + 非日期归档）
├── .github/workflows/           # ci.yml, asan.yml — 唯一有 CI 的仓
├── AGENTS.md                    # ★ agent 规约
├── CLAUDE.md                    # ★ agent 规约
├── skills-lock.json             # ★ 38 个 skill 锁定
├── CMakeLists.txt  LICENSE  README.md
└── .gitignore  .gitattributes  .gitmodules
```

### 2.3 learning（学习仓）

```
learning/
├── scaffold/                   # 脚手架工程（最大目录）
├── notes/                      # Obsidian vault
│   ├── .obsidian/              # Obsidian 配置（含 Blue Topaz 主题、插件）
│   ├── language/               # 语言基础
│   ├── DB/  neo4j/  vectordb/
│   ├── _index/                 # 索引页
│   ├── excerpt/                # 摘录
│   ├── learn_deep/  LLM/
│   ├── _templates/  _scripts/
│   ├── Redis/  test/
│   ├── HardWare/  _dashboard/  _meta/  diary/  linux/  paper/  sqlite/
│   └── (顶层：README.md、各 ds-*.md 笔记、.sync-pipeline-state.json)
├── code-solutions/             # 算法题解
├── ds-c/                       # 数据结构 C 实现
├── arkts/                      # ArkTS
├── include/
├── interview/
├── algo-c/
├── playground/
├── blog/  exam/  misc/  tools/
├── progress/                   # r26-progress.md, r32-progress.md
├── scripts/
├── third_part/googletest/      # submodule — 与 projects 重复，刻意保留两份
├── articles/
├── r25-progress.md … r38-progress.md   # ★ 散落待归入 progress/
├── CMakeLists.txt  LICENSE  README.md
└── .gitignore  .gitmodules
```

### 2.4 ai-docs（AI 工作文档仓）

```
ai-docs/
├── README.md                   # 这个仓收什么、不收什么 —— 边界声明放最显眼处
├── INDEX.md                    # 总索引，按主题分列
├── templates/                  # 可复用模板
│   ├── spec/                   # openspec 模板（proposal / design / tasks / spec delta）
│   ├── doc/                    # 技术文档模板
│   ├── review/                 # 评审记录模板
│   └── prompt/                 # 提示词模板
├── methodology/                # 方法论与工作流
│   ├── design-review/
│   ├── debugging/
│   └── planning/
├── patterns/                   # 可复用模式
│   ├── architecture/
│   ├── data-structure/
│   └── process/
├── assets/                     # 通用资产
│   ├── diagrams/
│   ├── templates/
│   └── scripts/
├── prompts/                    # 沉淀的提示词库
├── agent-notes/                # agent 交互经验与踩坑记录
├── references/                 # 外部资料索引（不存副本，只存链接与摘要）
└── archive/                    # 已废弃文档归档
```

### 2.5 reference（第三方库仓，独立于本仓）

```
reference/                      ← 仓库根
├── README.md                   # 概览 + 分类表 + 克隆方式 + 门禁说明
├── LICENSE                     # MIT（各 submodule 遵循上游许可）
├── .gitignore
├── .gitmodules                 # 95 条 submodule 定义
├── scripts/
│   ├── check-wiki-refs.py      # 引用校验门禁
│   └── sync_catalog.py         # Task 4：从 .gitmodules 的 gitlink 重新生成 catalog 的 commit 字段（下划线命名，Python 可 import）
├── docs/                       # ★ 笔记层
│   ├── db-wiki/                # 数据库源码笔记（分类索引 + gap-analysis 链接）
│   ├── rag-wiki/               # RAG 框架笔记
│   └── agent-wiki/             # Agent 框架笔记
└── reference/                  # ★ 源码层（第二层 reference）
    ├── catalog.yml             # ★ 权威清单（含 commit pin）
    ├── fetch-manifest.txt      # 拉取清单
    ├── AUDIT.md                # 克隆审计记录
    ├── README.md               # 目录语义说明
    ├── ai/                     # agent/ 13 个 + rag/ 11 个
    ├── benchmark/  columnar/  distributed-sql/  document/
    ├── embedded/  extension/  graph/  key-value/
    ├── relational/  search/  stream/  time-series/  vector/
```

源码层 15 个分类（`ai/` 为二级分类，含 `agent` 与 `rag`），合计 95 个上游库。

**路径约定（G3）**：第三方库路径形如 `reference/<model>/<name>` —— **只有一层 reference**。仓库根下的 `reference/` 是源码层，`reference/docs/` 是笔记层。

---

## 3. 归属判定表

### 3.1 projects 仓：什么该放这个仓

| 内容 | 归属 |
|---|---|
| 可运行的工程代码、测试、构建脚本 | projects |
| 项目级架构文档、流程文档 | projects |
| **项目级** agent 规约（`.ai/`、`CLAUDE.md`、`AGENTS.md`、`openspec/`、`skills-lock.json`） | projects |
| 项目专属数据（`dataset/`） | projects |
| 第三方源码镜像 | reference |
| **跨项目**通用笔记、模板、方法论文档 | ai-docs |
| 学习笔记、课程进度、算法题解 | learning |
| 学习轨的 spec（`openspec/specs/learning/`） | learning（待迁） |

### 3.2 learning 仓：什么该放这个仓

| 内容 | 归属 |
|---|---|
| 学习笔记、课程进度、算法题解、Obsidian vault | learning |
| 学习轨的 openspec spec（从 projects 迁出） | learning `openspec/specs/` |
| 工程代码、测试 | projects |
| 学习中产出的**可复用**方法论、模板 | ai-docs |

### 3.3 ai-docs 仓：收录边界（硬规则）

| ✅ 收进 ai-docs | ❌ 不收 |
|---|---|
| 跨项目复用的模板、方法论、模式 | 项目级架构文档（→ projects `docs/`） |
| 通用提示词库 | 项目级 agent 规约（→ projects `.ai/`、`CLAUDE.md`） |
| agent 通用踩坑经验 | 具体项目的 openspec 变更（→ projects `openspec/`） |
| 外部资料的链接与摘要索引 | 学习笔记与课程进度（→ learning） |
| 通用图表与脚本资产 | 第三方源码镜像（→ reference） |

---

## 4. 判定口诀

**换个项目还用得上 → ai-docs；只对这个项目有意义 → 留在本仓。**

各仓 README 内也各带一份归属判定表（人进到 `projects/` 里看不到父仓的 `docs/architecture.md`，所以每仓 README 必须自带一份）。

---

## 5. 已知重复（刻意保留，不合并）

| 重复项 | 出现在 | 处理 |
|---|---|---|
| `googletest` | `projects/vendor/third_part/googletest` 与 `learning/third_part/googletest` | 两仓各有一份，pin 可能不同，**本次刻意保留两份不合并**（合并需两个仓各改 `.gitmodules`，风险高于收益） |

---

## 6. 操作红线

> ⚠️ **禁止 `git submodule update --init --recursive`**
>
> **作用域是 `../reference` 仓。** reference 内部有 95 个第三方库 submodule，递归初始化会一次性拉取约 25 GB / 53.6 万文件。
>
> 需要哪个库就用 `scripts/fetch-reference.sh --name <名字>` 单独拉取。
>
> 在 StillEvolving 本仓内递归是安全的：本仓 `.gitmodules` 只有 3 条（projects / learning / ai-docs），
> 且不含 `reference`。
>
> `git submodule add` 与 `git submodule status` **不带** `--recursive` 是安全的。

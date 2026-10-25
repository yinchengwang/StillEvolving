# StillEvolving 仓库布局设计

- 日期：2026-10-25
- 状态：待批准（未实现）
- 形态：B（混合方案 —— 父仓 + submodule + 清单驱动拉取）
- 关联前置输入：`docs/architecture-review-2026-10-25.md`、`docs/repos.yaml.sample.yaml`

---

## 1. 意图与背景

### 1.1 要解决的问题

当前 `C:\code` 下有四个互不相干的 Git 仓库，外加三个残留目录：

| 目录                  | GitHub 现状                                                        | 本地事实                                               | 角色            |
| ------------------- | ---------------------------------------------------------------- | -------------------------------------------------- | ------------- |
| `book/`             | 已改名为 `projects.git`                                              | 5.3 GB 工作树 / 1.7 GB `.git` / 5730 跟踪文件             | 主工程仓          |
| `learning/`         | 独立仓                                                              | 2162 文件 / `.git` 12 MB                             | 学习仓           |
| `reference/`        | 独立仓                                                              | 24 MB / `.git` 6.8 MB / 95 个 submodule（94 个未 init） | 第三方源码镜像 + 笔记层 |
| `AI-DOCS.git`       | **空仓**（`ls-remote` 无输出）                                          | 本地不存在                                              | AI 工作文档仓      |
| `StillEvolving.git` | **非空** —— `main` = `72908b9d`，含 LICENSE + README（`# -` / `还在进化`） | 本地不存在                                              | 顶层聚合仓         |

问题在于：这些仓库之间的关系只存在于人的记忆里，没有任何机器可读的形式表达。新机器克隆、换电脑、给同事看，都只能靠口述"先 clone 这个，再 clone 那个，然后 init 那些 submodule"。

### 1.2 目标形态

建一个顶层聚合仓 `StillEvolving`，把四个仓库的**关系**编码进去：

- 三个自己维护的仓库（projects / learning / ai-docs）作为 **submodule** 挂在 `StillEvolving` 下 → 版本 pin 由 git 原生机制（gitlink mode 160000）保证，clone 时自动对上。
- 第三方源码库（reference 的 95 个上游）**不进 submodule 树**，改由 `catalog.yml` 清单 + 脚本按需拉取 → 避免 3 层嵌套递归克隆（实测 25 GB / 53.6 万文件）。

### 1.3 为什么不是"全部塞进一个仓"

四类内容的**变更节奏与体积**差异巨大：

- projects：每天都在改，5.3 GB，含 LFS 数据集 → 必须独立仓 + 独立 CI
- learning：每周改，108 MB → 独立仓
- ai-docs：随时改，纯文本 → 独立仓
- reference 源码：一年动几次，25 GB 全量 → 只能按需拉

合成一个大仓会让 CI 每次都跑全量；拆成互相独立的四个仓又丢失了"它们是一家人"的关系表达。`StillEvolving` 正是补上这层关系。

---

## 2. 目标 / 非目标 / 反目标

### 2.1 目标

1. **一条命令得到可用工作树**：在 `StillEvolving` 下执行 bootstrap 后，projects / learning / ai-docs 三个仓自动 clone 到正确 commit。
2. **目录语义自解释**：任何人打开任一仓库，都清楚"这个目录放什么、不放什么"，且这条规则写进了受版本控制的文档，不只是口头约定。
3. **第三方库按需取**：不 clone 全量也能开始工作；需要哪个库，命令拉哪个库，且拉到**已 pin 的 commit**（保证 wiki 里的行号引用仍然有效）。
4. **零改动迁移**：现有 5730 + 2162 + 102 个跟踪文件的历史与路径全部保留，不重写历史、不改目录名。

### 2.2 非目标

1. 不做 monorepo 式的"所有代码一个仓"。四个仓保持独立 git 历史。
2. 不做 CI 编排平台。`StillEvolving` 只提供 bootstrap 与一致性检查脚本，不接管各仓 CI。
3. 不在本轮迁移中重构 projects 的 `engine/` 内部结构、learning 的 `scaffold/` 内容、reference 的源码镜像内容。
4. 不做跨仓的共享代码依赖管理（projects 与 learning 各自维护 vendor / third_part）。

### 2.3 反目标（做到即视为失败）

1. **反目标 A：单次 clone 拉下 25 GB**。任何让 `git clone --recursive` 触发 reference 全量拉取的方案都算失败。
2. **反目标 B：丢失 wiki 的精确行号引用能力**。wiki 里 2460 处 `faiss/index_factory.cpp:1227` 形式的引用必须继续可校验。如果 pin 丢了、路径前缀变了、目录改名了，导致 `check-wiki-refs.py` 模式 A 永久失效 —— 算失败。
3. **反目标 C：agent 变成无上下文裸模型**。`.ai/`、`CLAUDE.md`、`AGENTS.md`、`openspec/`、`skills-lock.json` 是 agent 在仓内读的规约，搬走 projects 会让 agent 失去项目上下文 —— 算失败。
4. **反目标 D：磁盘占用回升**。任何让 `C:\code` 总占用显著高于当前基线的方案都算失败。

---

## 3. 约束

以下每条都是**实测得出的硬约束**，不是假设。

### C0 — 4 个 submodule 的 gitlink SHA 是伪造的，上游不存在

**实测方法**（可复现）：`git init` 空目录 → `git fetch --depth 1 --no-tags <upstream> <sha>`，并用 GitHub commit 页面 HTTP 状态码交叉验证。

对照组：`faiss`（唯一已 init 的库）按其 pin 拉取 **✅ 成功** —— 证明测试方法有效。

| 条目                     | gitlink SHA                                | 上游 fetch               | GitHub commit 页                                      | 结论                         |
| ---------------------- | ------------------------------------------ | ---------------------- | ---------------------------------------------------- | -------------------------- |
| `columnar/druid`       | `fa8dc9912637a2f729eef9f55356621fec18d40e` | ❌ `not our ref`        | HTTP 404                                             | **伪造 pin**                 |
| `key-value/pebble`     | `68315f176d9e328a233ace29b7579a829f89879f` | ❌ `not our ref`        | HTTP 404                                             | **伪造 pin**                 |
| `time-series/tdengine` | `62385b1e2f1b36e99c4ff8201c7aa86716f64709` | ❌ `not our ref`        | HTTP 404                                             | **伪造 pin**                 |
| `key-value/dragonfly`  | `dafb825b0e5c6f0d8ce2836e1252a568fee639ff` | ❌ `not our ref`        | HTTP 404                                             | **伪造 pin**                 |
| `relational/mysql`     | `23e360a7fac718d80b9e6a79f7d5a7bf37aa3bbc` | ❌ gitee 镜像 not our ref | **HTTP 200**（`Bug#39857308: Harden GitHub Actions…`） | **SHA 真实存在，但 gitee 镜像不含它** |

补充：这 5 个 SHA 在父仓中也**不存在**（`git cat-file -t` 全部报 "could not get object info"）—— 说明它们从未被真实检出过，是当初手填进去的。

**受影响的笔记行号引用**（这些引用现在就是坏的，不是迁移弄坏的）：

| 笔记                                          | 引用处数 | 对应条目                  |
| ------------------------------------------- | ---- | --------------------- |
| `docs/db-wiki/time-series/tdengine.md`      | 75   | tdengine（伪造 pin）      |
| `docs/db-wiki/relational/mysql.md`          | 21   | mysql（gitee 镜像缺该 SHA） |
| `docs/db-wiki/key-value/pebble.md`          | 4    | pebble（伪造 pin）        |
| `docs/db-wiki/key-value/dragonfly.md`       | 2    | dragonfly（伪造 pin）     |
| `docs/db-wiki/columnar/druid.md`            | 0    | druid（伪造 pin，但无引用）    |
| `docs/db-wiki/distributed-sql/oceanbase.md` | 20   | oceanbase（无源码镜像）      |

**推论**：catalog 的 `commit` 字段**不能一律取 gitlink SHA** —— 对这 5 个条目照抄就是复刻坏 pin。必须引入 pin 状态字段（见 §5.5.2）。

### C1 — wiki 引用依赖 submodule pin，且依赖相对子模块根的路径格式

`reference/docs/` 下 97 篇笔记里的源码行号引用，实测统计（正则 `路径:行号`，扩展名 cpp/cc/c/h/hpp/py/go/rs/java/md/sh/sql/ts/js）：

| 类别                             | 数量       | 形态                                                                   |
| ------------------------------ | -------- | -------------------------------------------------------------------- |
| 总引用数                           | **3371** | —                                                                    |
| **相对子模块根**（不带 `reference/` 前缀） | **3166** | `index_factory.cpp:1227`、`CMakeLists.txt:119`                        |
| **带 `reference/` 前缀**（相对仓库根）   | **205**  | `reference/distributed-sql/tidb/pkg/planner/cascades/cascades.go:29` |

带前缀的 205 处**只集中在 7 个文件**：

| 文件                                           | 引用数 |
| -------------------------------------------- | --- |
| `docs/db-wiki/graph/nebula.md`               | 72  |
| `docs/db-wiki/distributed-sql/tidb.md`       | 56  |
| `docs/db-wiki/relational/openGauss.md`       | 20  |
| `docs/db-wiki/document/mongodb.md`           | 19  |
| `docs/db-wiki/distributed-sql/yugabytedb.md` | 17  |
| `docs/db-wiki/relational/postgres.md`        | 12  |
| `docs/db-wiki/relational/mysql.md`           | 9   |

`scripts/check-wiki-refs.py` 的 `resolve()` 实测行为：

```python
# 1) 优先挂到每个子模块根下（wiki 路径的标准语义是「相对子模块根」）
for name, sub in prefix_map.items():
    cand = os.path.join(repo_root, sub, path)
    if os.path.isfile(cand): return cand, name
# 2) 再退回仓库根（学习层 / 根级文件，如 docs/... 、cmake/...）
cand = os.path.join(repo_root, path)
if os.path.isfile(cand): return cand, None
```

**关键结论**：带 `reference/` 前缀的 205 处走的是**第 2 条分支**（退回仓库根）。它能解析成功，当且仅当**从仓库根算起的 `reference/...` 路径存在** —— 也就是 `reference/` 目录名不能变。**这 205 处对"路径写法"无要求，只对"目录名"有要求。**

**推论**：

- `catalog.yml` 必须补 `commit` 字段，且值必须与当前 gitlink（mode 160000）一致。
- `reference/` 目录名不能改，`docs/` 目录名不能改（`MEMORY.md` 已记载："wiki 目录不要改名""保留 `reference/` 目录名"）。
- 拉取脚本必须支持"精确 checkout 到 pin 的 commit"，而非"拉 master 最新"。
- **不需要**为了统一引用写法去批量改 205 处笔记 —— 那是无谓的 churn，且会引入新的错误风险。

### C2 — reference 有 95 个 submodule，但只有 1 个已 init

`git submodule status` 实测：94 个带 `-` 前缀（未初始化），仅 `reference/vector/faiss` 已 init。

`.gitmodules` 里 95 条的 URL 来源：86 条用 catalog 的 `mirror`、4 条用 `repository`、5 条两者皆非（elasticsearch / chroma / milvus / neo4j / mysql 直接指向 `gitee.com/mirrors/*`）。

**推论**：URL 优先级必须在清单里显式建模，不能靠脚本猜。

### C3 — 三份清单互相不一致

| 清单                   | 条目数 | 位置                             |
| -------------------- | --- | ------------------------------ |
| `catalog.yml`        | 97  | `reference/catalog.yml`        |
| `.gitmodules`        | 95  | `reference/.gitmodules`        |
| `fetch-manifest.txt` | 73  | `reference/fetch-manifest.txt` |

差异明细：

- **24 个 AI 类目**（`ai/agent` 13 个 + `ai/rag` 11 个）在 catalog 和 submodule 里都有，但**不在 fetch-manifest**。
- `oceanbase`、`pklite` 在 catalog 里但无对应 submodule。
- `fetch-manifest` 里没有任何条目是 catalog 之外的（无孤儿）。

**推论**：必须有单一权威清单（catalog），其余两份降级为生成物。

### C4 — wiki 目录结构与源码分类结构错位

- `docs/db-wiki/` 有 12 个分类目录，其中 `distributed-sql/` 下有 `oceanbase.md`、`embedded/` 下有 `pklite.md` —— 但这两者在 `reference/` 源码层**没有对应 submodule**。
- `docs/rag-wiki/` 13 篇对应 `ai/rag` 11 个库（多 `commercial-rag-products.md`）。
- `docs/agent-wiki/` 15 篇对应 `ai/agent` 13 个库（多 `commercial-agent-products.md`）。
- `db-wiki/` 若干分类带 `.gitkeep`（columnar / distributed-sql / document / key-value / relational / time-series），部分不带（embedded / extension / graph / search / stream / vector）。

**推论**：笔记层允许比源码层多出笔记（调研型笔记合法），但必须在 README 中说明"哪些笔记没有对应源码"。

### C5 — reference 的三层目录嵌套

真实布局是 `reference/<category>/<name>`（**只有一层 reference**，submodule path 实测为 `reference/vector/faiss`、`reference/ai/agent/agents`）：

```
reference/                      ← 仓库根
├── docs/                       ← 笔记层
├── scripts/check-wiki-refs.py
└── reference/                  ← 源码层（第二层 reference）
    ├── catalog.yml
    ├── fetch-manifest.txt
    ├── AUDIT.md
    ├── README.md
    ├── ai/{agent,rag}/
    ├── benchmark/  columnar/  distributed-sql/  document/
    ├── embedded/   extension/  graph/  key-value/
    ├── relational/ search/  stream/  time-series/  vector/
```

`.gitignore` 里 `reference/*/` + `!reference/*/README.md` 两条规则**实际不生效**（`git check-ignore -v reference/vector/faiss` 返回空）—— gitlink 目录本身就不进父仓索引，不靠 gitignore 排除。`.gitignore` 这条规则是冗余的误导。

### C6 — learning 的双轨守卫显式支持独立仓布局

`learning/CMakeLists.txt`：

```cmake
set(_dual_track_guard "${CMAKE_CURRENT_LIST_DIR}/../cmake/dual-track-guard.cmake")
if(EXISTS "${_dual_track_guard}")
    guard_no_cross_track_reference("engineering/")
endif()
```

守卫只在 `../cmake/dual-track-guard.cmake` 存在时启用 —— 即**独立仓布局下守卫自动关闭**。

**推论**：learning 与 projects 可以彻底独立，不需要为了守卫而保持某种父子路径关系。

### C7 — projects 里的学习轨 spec 残留

`projects/openspec/specs/` 共 38 个 spec，其中 `learning/` 子目录有 35 个文件（`adaptive-learning-roadmap`、`five-year-learning-layer`、`five-year-plan-integration`、`h5-vite-build`、`illustrate-series` 等），`engineering/` 子目录 59 个文件。

顶层还有 12 个单文件 spec（`r10-c-finale.md`、`r13-db-index-system.md` … `r38-grokking-ml.md`）—— 这些是**学习轨命名**（r10~r38 轮次），但住在 projects 仓。

learning 仓则完全没有 `openspec/` 对应物。

### C8 — reference 的 wiki 存在跨仓断链

`reference/docs/{db-wiki,rag-wiki,agent-wiki}/README.md` 共 3 个文件、**16 处**引用 `../gap-analysis/*.md`（db-wiki 12 + rag-wiki 2 + agent-wiki 2，  
分布在 6 行上；对应 14 个独立目标文件），但 `reference/docs/gap-analysis/` **不存在**。实际内容在 `projects/docs/analysis/`（27 个文件，含 `agent.md`、`rag.md`、`obsidian-setup.md`）。

### C9 — goolgetest 重复

- `projects/vendor/third_part/googletest`（submodule）
- `learning/third_part/googletest`（submodule）

两者指向同一个上游 `https://github.com/google/googletest.git`。

### C10 — CI 覆盖缺口

只有 projects 有 `.github/workflows/{ci.yml, asan.yml}`。learning 与 reference 无 CI。

### C11 — projects 内有 git 死残留

`C:\code\book.worktrees\` 下 3 个目录，每个含 `.git` 文件指向 `C:/code/book/.git/worktrees/<name>`，但主仓 `book/.git/worktrees/` 目录**不存在**，`git worktree list` 只列主仓一条 —— git 完全不认这三个目录。合计 **999 MB**，其中一个（`minimax-coding-plan-implementation/`）还留着 `engineering/` 旧布局与 shell 转义事故残留（`'[{type:` / `0` / `0"`）。

### C12 — verify_learning 是损坏仓库

`C:\code\verify_learning\.git\HEAD` 内容为 `ref: refs/heads/.invalid`，`refs/heads/` 为空 → `git branch -a` 报 "failed to resolve HEAD as a valid ref"。远端指向 `learning.git`。

### C13 — 3D相册 尚未初始化 git

`C:\code\3D相册\3D相册-1/` 非 git 仓。

### C14 — C:\code 根目录不是 git 仓

`git rev-parse` 报 "not a git repository"。所以设计文档本身当前无处提交（见 §9 落盘位置）。

### C15 — StillEvolving 远端非空，AI-DOCS 远端为空仓

实测 `git ls`**`-`**`remote`：

| 远端                               | 状态                                                                                                                     |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `yinchengwang/StillEvolving.git` | **非空** —— `refs/heads/main` = `72908b9d`，含 `LICENSE`（MIT, Copyright 2026 yinchengwang）与 `README.md`（内容 `# -` + `还在进化`） |
| `yinchengwang/AI-DOCS.git`       | **空仓** —— `git ls-remote` 无任何输出                                                                                        |
| `yinchengwang/projects.git`      | `refs/heads/main` = `495c8f1e`                                                                                         |
| `yinchengwang/book.git`          | `refs/heads/main` = `495c8f1e`（**旧 URL 仍可达**，GitHub 改名自动重定向）                                                           |


**推论**：

- StillEvolving 仓**已存在**，M2 应为"在已有仓上加 submodule"，不是"新建"。已有的 LICENSE 与 README 保留，README 按 §5.1 扩写。
- AI-DOCS 是空仓 → `git submodule add` 会因"远端 HEAD 无对应 ref"而**直接失败**（退出码 128，`.gitmodules` 不生成）。**必须先推送 AI-DOCS 的首个提交**，且分支名需与远端 HEAD 一致。
- M1（改 remote URL）风险极低 —— 旧 URL 与新 URL 指向同一 commit。但 M1 必须在 M2 之前，因为 `submodule add` 会用 `.gitmodules` 里写的 URL 去 clone。

### C16 — catalog 的 mirror 字段与 .gitmodules 的实际 URL 不一致，且含已被封禁的仓

实测 `.gitmodules` 中指向 `gitee.com/yinchengwang_admin/*` 的 6 个条目：

| 条目               | `.gitmodules` URL                        | catalog `mirror`                                | 实测                      |
| ---------------- | ---------------------------------------- | ----------------------------------------------- | ----------------------- |
| `redis`          | `gitee.com/yinchengwang_admin/redis.git` | 同                                               | 仓可访问，但**不含 pinned SHA** |
| `elasticsearch`  | 同                                        | 同                                               | 同上                      |
| `faiss`          | 同                                        | 同                                               | 同上                      |
| `pgvector`       | 同                                        | 同                                               | 同上                      |
| `ann-benchmarks` | 同                                        | 同                                               | 同上                      |
| `mysql`          | `gitee.com/mirrors/mysql-server.git`     | `gitee.com/yinchengwang_admin/mysql-server.git` | **两个地址都取不到 pinned SHA** |

对 `mysql` 的 pinned SHA `23e360a7…`：

- `gitee.com/mirrors/mysql-server.git` → ❌ `not our ref`
- `gitee.com/yinchengwang_admin/mysql-server.git` → 该仓已被 Gitee **封禁**（HTTP 423 "The Repository has been blocked"）
- `github.com/mysql/mysql-server.git` → ✅ SHA 真实存在且可按 SHA 拉取

**推论**：文档原先设计的 `clone_url > mirror > repository` 优先级**与实际可用性正好相反** —— 排最后的 `repository`（GitHub 官方）恰恰是唯一能用的。字段必须重新设计（见 §5.5.2）。

### C17 — reference 内部 95 个目录的身份二义（submodule vs 普通 clone）

形态 B 说 reference 不进父仓 submodule 树，"其内是脚本拉的独立 clone"。但 §5.5.4 的拉取目标路径 `reference/<model>/<name>` **正是那 95 个 gitlink 占据的路径**。实测两种终态：

- 脚本按 §5.5.4 流程拉取后（`clone --filter=blob:none --no-checkout` → `fetch --depth 1` → `checkout <commit>`）：父仓 `git status` **干净**，`git submodule status` 显示已 init ✅ —— 因为新克隆的 HEAD 恰好等于 gitlink SHA。
- 若目标目录已存在但 HEAD ≠ pin（幂等判断只覆盖"HEAD 已等于 commit"的情形）：父仓立刻出现 ` M reference/vector/chroma` —— **父仓被污染**。

另外：`.gitignore` 的 `reference/*/` 规则对 gitlink 路径**实测不生效**（`git check-ignore -v reference/vector/faiss` 返回空）—— 父仓索引里就是 gitlink，不靠 gitignore 排除。

**推论**：必须明确这 95 个目录的权威身份，否则任何人一次 `git submodule update --init --recursive` 就能把 25 GB 拉下来，或反过来让脚本把父仓搞脏。**已定案，见 §7.3 M12。**

**身份定案：保留 submodule 语义。** 理由：

| 方案                   | 父仓洁净性                     | pin 一致性   | 25 GB 风险                |
| -------------------- | ------------------------- | --------- | ----------------------- |
| **保留 submodule**（采纳） | ✅ 永远干净（gitlink 机制保证）      | ✅ 永远一致    | ⚠️ 需警告不要用 `--recursive` |
| 改为普通 clone           | ❌ 可能出现 ` M reference/...` | ❌ 需脚本自行维持 | ✅ 消除                    |

普通 clone 方案有个致命细节：`.gitignore` 的 `reference/*/` 规则**对 gitlink 路径不生效**（实测 `git check-ignore -v` 返回空）—— 父仓索引里就是 gitlink 条目，改不动。改普通 clone 等于要让父仓索引与磁盘状态长期不一致。

**结论**：`.gitmodules` 保留 95 条不动，这 95 个目录**继续是 submodule**。脚本的行为相应调整（不是 clone 新仓，而是"在 submodule 内 fetch + checkout"）：见 §5.5.4 与 §7.3 M12。

**给使用者的硬警告**（必须写进 reference README 与脚本输出）：

> ⚠️ **禁止执行 `git submodule update --init --recursive`** —— 会一次性拉取 95 个第三方库（约 25 GB / 53.6 万文件）。>   
> 需要哪个库，用 `fetch-reference.sh --name <名字>` 单独拉取。

### C18 — openspec/specs 顶层是 36 个目录，不是 12 个文件

实测 `openspec/specs/` 顶层：

- **32 个 `r*` 目录**（`r6-language-tranche` … `r38-grokking-ml`），每个含 1 个 `spec.md`
- 2 个非 `r*` 目录：`learning-card-rigor`、`kanban-statuses-json`
- 2 个顶层 `.md` 文件：`README.md`、`2026-07-14-multimodal-index-redesign.md`
- 2 个子目录：`engineering/`（59 文件）、`learning/`（35 文件）

**原设计文档写"顶层 12 个单文件 spec（`r10-c-finale.md` …）"是错的** —— 那些是目录。

更要紧的是**轨道归属不能按 `r*` 命名判定**。实测 32 个 `r*` spec 中：

| 类别                     | 数量     | 判定                          |
| ---------------------- | ------ | --------------------------- |
| 内容引用 `engineering/` 路径 | **19** | 跨轨依赖工程轨，**不可单独搬到 learning** |
| 不引用 `engineering/`     | 13     | 纯学习向，可搬                     |

引用 `engineering/` 的 19 个：`r7-ds-algo`、`r8-engineering-tooling`、`r9-language-systems-bridge`、`r10-c-finale`、`r12c-perf`、`r12d-net`、`r13-db-index-system`、`r15-db-executor`、`r16-db-redis`、`r17-db-vector`、`r18-cpp-modern`、`r20-cpp-patterns`、`r21-linux-basics`、`r22-linux-kernel`、`r25-linux-net`、`r27-ds-basics`、`r34-grokking-system`、`r35-grokking-patterns`、`r36-grokking-concurrency`。

典型例证 —— `r8-engineering-tooling/spec.md` 的要求原文：

> **NOTES.md 工程对照**：`learning/scaffold/<card-id>/NOTES.md` 含"工程对照"段，中文内容 ≥100 字符，至少引用一个 `engineering/` 路径

这类 spec **本身就在描述学习轨与工程轨的对照关系**，搬走后 `engineering/` 引用会指向不存在的路径。

### C19 — 硬编码 C:/code 路径的文件

实测（排除 `archive/` 与 `build/`）：`projects` 侧 `.ai/.claude/settings.json` 等含 `C:/code`；`learning` 侧 `scaffold/cpp/parallel_stl/NOTES.md` 含 `C:/code`。`build/` 下是 CMake 缓存产物（可忽略、可重建）。

`projects/docs/path-mapping.md` 这个文件名本身说明它是一份**路径映射契约文档** —— 迁移工作树时必须同步更新。

**推论**：若采用"移动既有工作树"路径（见 §7.1 M2a），这些引用需同步处理。

---

## 4. Approaches（形态对比）

用户已选定形态 B。本节保留完整对比与选择理由，供后续回看。

### 形态 A — 纯 submodule 树

```
StillEvolving/
├── projects/   (submodule)
├── learning/   (submodule)
├── ai-docs/    (submodule)
└── reference/  (submodule) → 95 个 submodule → 上游仓库
```

| 维度       | 评估                                                                  |
| -------- | ------------------------------------------------------------------- |
| clone 成本 | **25 GB / 53.6 万文件**（reference 已 init 的 faiss 单个就 13 MB+，95 个按实测比例） |
| 嵌套层数     | 3 层（StillEvolving → reference → 上游）                                 |
| pin 机制   | 原生 gitlink，最优雅                                                      |
| 磁盘       | 与当前 `C:\code` 基线持平（当前也是全量在盘）                                        |
| 致命问题     | 违反反目标 A、D；`git clone --recursive` 对新用户是灾难                           |

### 形态 B — 混合：自维护仓走 submodule，第三方库走清单 ✅

```
StillEvolving/
├── projects/   (submodule)   ← 自维护
├── learning/   (submodule)   ← 自维护
├── ai-docs/    (submodule)   ← 自维护
└── reference/  (manifest)    ← 清单驱动，按需拉取
```

| 维度       | 评估                                                |
| -------- | ------------------------------------------------- |
| clone 成本 | **约 200 MB**（三个 submodule）+ reference 仓 24 MB 骨架  |
| 嵌套层数     | 2 层（reference 不再是 submodule，其内是脚本拉的独立 clone）      |
| pin 机制   | 自维护仓用 gitlink；第三方库用 `catalog.yml` 的 `commit` 字段   |
| 磁盘       | 可控，按需增长                                           |
| 代价       | 需要一个拉取脚本；catalog 需人工维护 commit 字段（可从 gitlink 自动生成） |

### 形态 C — 纯索引仓（无 submodule，只记录 URL + commit）

```
StillEvolving/
├── repos.yaml      ← 全部 4 个仓的 URL + commit
└── scripts/bootstrap.ps1
```

| 维度       | 评估                                                                                    |
| -------- | ------------------------------------------------------------------------------------- |
| clone 成本 | 同 B                                                                                   |
| 关系表达     | 弱 —— git 原生看不出这是一个家，只是一个 YAML                                                         |
| pin 机制   | 全靠 YAML，与 git 生态脱节                                                                    |
| 优点       | 结构最简单，脚本最少                                                                            |
| 致命问题     | 放弃 git 原生 submodule 能力，与用户"其他所有仓库作为他的 submodule"的原始意图相悖；且自维护仓用 submodule 时可获得更可靠的 pin |

### 为什么选 B

1. **符合原始意图**：用户明确要求"其他所有仓库作为他的 submodule"。B 满足这一条对"自维护仓库"的解读，同时对"第三方库"这一特殊类别做例外。
2. **保住反目标 A 与 D**：25 GB 是实测数字，不是猜测。
3. **保住反目标 B**：`catalog.yml` 的 `commit` 字段直接来自当前 gitlink SHA，值完全一致，pin 能力不丢。
4. **可自动化**：commit 字段可以从 gitlink 自动生成（`git ls-files -s | grep ^160000`），人工维护成本趋近于零。

---

## 5. 目录规范

本章是设计的核心。用户要求"把目录啥的都分清楚，第三方库仓库里面的目录也要分清楚"。

### 5.1 StillEvolving（顶层聚合仓）

```
StillEvolving/
├── README.md                    # 这是一家人：四个仓的关系、各自职责、bootstrap 入口
├── repos.yaml                   # 机器可读的四仓清单（唯一权威的"关系"定义）
├── .gitmodules                  # 三个自维护 submodule 的 pin
├── .gitignore
├── LICENSE
├── docs/
│   ├── architecture.md          # 指向 §5.2~§5.5 的目录规范
│   └── superpowers/specs/        # 设计与计划文档
├── scripts/
│   ├── bootstrap.ps1            # Windows：一键拉起三个 submodule + 校验
│   ├── bootstrap.sh             # POSIX 同上
│   ├── fetch-reference.sh        # 按 catalog.yml 拉取第三方库到指定 commit
│   ├── sync-catalog.py          # 从 .gitmodules 的 gitlink 重新生成 catalog 的 commit 字段
│   └── check-consistency.py      # 校验四仓关系与 catalog 一致性
└── projects/                    # submodule → yinchengwang/projects.git
├── learning/                    # submodule → yinchengwang/learning.git
└── ai-docs/                     # submodule → yinchengwang/AI-DOCS.git
```

**为什么 `repos.yaml` 与 `.gitmodules` 并存**：`.gitmodules` 是 git 的原生机制，但表达不了 `fetch: manifest` 这种策略，也放不了"这个仓该放什么"的语义说明。`repos.yaml` 承载语义，`.gitmodules` 承载 git 事实。两者由 `check-consistency.py` 保证不漂移。

**为什么 `reference/` 不出现在 StillEvolving 的目录树里**：形态 B 的核心就是它不进 submodule 树。reference 作为独立仓独立 clone，其位置由使用者决定（推荐 `C:\code\reference`，与三个 submodule 平级但**不在** StillEvolving 内）。

### 5.2 projects（工程仓）

```
projects/
├── engine/                      # ★ 核心：自研数据库/搜索引擎引擎（1859 文件）
│   ├── src/
│   │   ├── db/                  # 669 文件 — 存储引擎、索引、事务
│   │   ├── include/             # 497 文件 — 公共头文件
│   │   ├── algo-prod/           # 34 文件 — 生产级算法
│   │   ├── sdk/                 # 36 文件 — 对外 SDK
│   │   ├── redis/               # 8 文件 — Redis 协议兼容层
│   │   ├── ds/                  # 2 文件 — 数据结构
│   │   └── cpp/                 # 4 文件 — C++ 基础设施
│   ├── test/                    # 447 文件 — 测试
│   ├── tools/                   # 53 文件 — 工具
│   ├── docs/                    # 43 文件 — 引擎内文档
│   ├── third_part/uthash/       # submodule（gitee mirrors）
│   ├── cmake/                   # 4 文件
│   ├── drivers/                 # 9 文件
│   ├── proto/                   # 1 文件
│   ├── sdk/                     # 23 文件
│   ├── include/  scripts/  test_data/
│   └── .superpowers/
├── apps/                        # ★ 应用层：微信小程序（325 文件）
│   ├── knowledge-hub/           # 132 文件
│   ├── programmer-workbench/    # 130 文件
│   ├── games/                   # 37 文件
│   ├── trip-log/                # 24 文件
│   └── .archive/
├── docs/                        # ★ 文档层（318 文件）
│   ├── process/                 # 106 文件 — 流程与规范
│   ├── diagrams/                # 89 文件 — 图表
│   ├── arch/                    # 66 文件 — 架构设计
│   ├── analysis/                # 27 文件 — 差距分析（★ 见下）
│   ├── storage/                 # 12 文件 — 存储设计
│   └── (root)                   # 18 文件 — 顶层文档
├── openspec/                    # ★ 变更与规格（162 文件）
│   ├── specs/                   # 38 个 spec
│   │   ├── engineering/         # 59 文件 — 工程轨
│   │   ├── learning/            # 35 文件 — ★ 学习轨残留，待迁出
│   │   └── (12 个单文件 spec)   # r10-c-finale … r38-grokking-ml
│   ├── changes/                 # 8 个进行中变更
│   │   ├── p1a-vector-wal-complete/
│   │   ├── p1b-checkpoint-manager/
│   │   ├── p1c-chaos-recovery/
│   │   ├── c9-1-housekeeping/
│   │   ├── c9-2-known-limitations/
│   │   ├── c9-3-subsystems/
│   │   ├── gap-analysis-roadmap/
│   │   └── 22c-monitoring-deployment/
│   ├── archived/                # 3 文件
│   └── config.yaml
├── .ai/                         # ★ agent 规约（202 文件）— 禁止搬走
│   ├── .agents/                 # 85 文件
│   ├── .claude/                 # 91 文件
│   ├── .opencode/               # 22 文件
│   └── .vscode/                 # 4 文件
├── vendor/third_part/googletest/  # submodule — 见 C9 重复处理
├── vendor/cmake/                # 2 文件
├── dataset/                     # 37 文件 — 数据集（含 LFS 对象）
├── scripts/                     # 7 文件
├── archive/                     # 158 文件 — 历史归档（见下）
├── .github/workflows/           # ci.yml, asan.yml — 唯一有 CI 的仓
├── AGENTS.md                    # ★ agent 规约
├── CLAUDE.md                    # ★ agent 规约（17 KB）
├── skills-lock.json             # ★ 38 个 skill 锁定（全部来自 mattpocock/skills）
├── CMakeLists.txt  LICENSE  README.md
└── .gitignore  .gitattributes  .gitmodules
```


**`archive/` 的 158 个文件构成（46 个二级项）**：

| 类型                                  | 数量                            | 说明                                                                            |
| ----------------------------------- | ----------------------------- | ----------------------------------------------------------------------------- |
| 日期命名的 openspec 归档                   | 34 项（2026-08-27 ~ 2026-08-28） | 每项含 design.md / proposal.md / specs / tasks.md                                |
| `db-sql-over-kv/`                   | 10 文件                         | 非日期归档                                                                         |
| `distributed/`                      | 8 文件                          | 非日期归档（C 源码）                                                                   |
| `openspec/review-cpp-stl-scaffold/` | 5 文件                          | 非日期归档                                                                         |
| `.superpowers/`                     | 3 文件                          | 工具产物                                                                          |
| 散落未跟踪文件                             | 11 个                          | `debug_test.c`、`final-report.md`、`task-{2.1,2.2,3.1,3.2,4,5,6,7,8}-report.md` |

**projects 目录归属判定规则**（写进 projects/README.md）：

| 内容                                                                              | 归属                |
| ------------------------------------------------------------------------------- | ----------------- |
| 可运行的工程代码、测试、构建脚本                                                                | projects          |
| 项目级架构文档、流程文档                                                                    | projects          |
| **项目级** agent 规约（`.ai/`、`CLAUDE.md`、`AGENTS.md`、`openspec/`、`skills-lock.json`） | projects          |
| 项目专属数据（`dataset/`）                                                              | projects          |
| 第三方源码镜像                                                                         | reference         |
| **跨项目**通用笔记、模板、方法论文档                                                            | ai-docs           |
| 学习笔记、课程进度、算法题解                                                                  | learning          |
| 学习轨的 spec（`openspec/specs/learning/`）                                           | learning（待迁，见 §7） |

### 5.3 learning（学习仓）

```
learning/
├── scaffold/                   # 1554 文件 — 脚手架工程（最大目录）
├── notes/                      # 230 文件 — Obsidian vault
│   ├── .obsidian/              # 18 文件 — Obsidian 配置（含 Blue Topaz 主题、插件）
│   ├── language/               # 100 文件 — 语言基础
│   ├── DB/                     # 29 文件
│   ├── neo4j/                  # 14 文件
│   ├── vectordb/               # 10 文件
│   ├── _index/                 # 8 文件 — 索引页
│   ├── excerpt/                # 14 文件 — 摘录
│   ├── learn_deep/             # 6 文件
│   ├── LLM/                    # 5 文件
│   ├── _templates/             # 4 文件
│   ├── _scripts/               # 3 文件
│   ├── Redis/  test/           # 3 / 2 文件
│   ├── HardWare/  _dashboard/  _meta/  diary/  linux/  paper/  sqlite/  # 各 1 文件
│   └── (顶层 7 个)             # README.md, ds-art.md, ds-radix-tree.md, ds-rtree.md,
│                               # ds-skiplist.md, ds-ttree.md, .sync-pipeline-state.json
├── code-solutions/             # 85 文件
├── ds-c/                       # 78 文件 — 数据结构 C 实现
├── arkts/                      # 77 文件 — ArkTS
├── include/                    # 44 文件
├── interview/                  # 22 文件
├── algo-c/                     # 21 文件
├── playground/                 # 15 文件
├── blog/                       # 8 文件
├── exam/                       # 4 文件
├── misc/  tools/               # 3 文件 各
├── progress/                   # 2 文件 — r26-progress.md, r32-progress.md
├── scripts/                    # 2 文件
├── third_part/googletest/      # submodule — 见 C9
├── articles/                   # 1 文件
├── r25-progress.md  r30-progress.md  r33-progress.md  r35-progress.md  # ★ 散落待归入 progress/
├── r36-progress.md  r37-progress.md  r38-progress.md                   # ★
├── CMakeLists.txt  LICENSE  README.md
└── .gitignore  .gitmodules
```

**learning 目录归属判定规则**：

| 内容                                | 归属                         |
| --------------------------------- | -------------------------- |
| 学习笔记、课程进度、算法题解、Obsidian vault     | learning                   |
| 学习轨的 openspec spec（从 projects 迁出） | learning `openspec/specs/` |
| 工程代码、测试                           | projects                   |
| 学习中产出的**可复用**方法论、模板               | ai-docs                    |

**⚠️ C6 提示**：learning 的 `CMakeLists.txt` 双轨守卫依赖 `../cmake/dual-track-guard.cmake` 存在才启用。独立仓布局下该守卫自动关闭 —— 这是**预期行为**，不需要为保持守卫而把 learning 塞回 projects 底下。

### 5.4 ai-docs（AI 工作文档仓，目标树）

**当前状态**：GitHub 上是空仓，本地不存在。这是四个仓中唯一需要**从零创建目录结构**的。

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
│   ├── design-review/          # 设计评审方法
│   ├── debugging/              # 系统化调试流程
│   └── planning/               # 规划与拆解方法
├── patterns/                   # 可复用模式
│   ├── architecture/           # 架构模式
│   ├── data-structure/         # 数据结构选型
│   └── process/                # 流程模式
├── assets/                     # 通用资产
│   ├── diagrams/               # 通用图表源文件
│   ├── templates/              # 文档模板（与 templates/ 合并或分开，见下）
│   └── scripts/                # 通用脚本
├── prompts/                    # 沉淀的提示词库
├── agent-notes/                # agent 交互经验与踩坑记录
├── references/                 # 外部资料索引（不存副本，只存链接与摘要）
└── archive/                    # 已废弃文档归档
```

**收录边界（硬规则）**：

| ✅ 收进 ai-docs    | ❌ 不收                                        |
| --------------- | ------------------------------------------- |
| 跨项目复用的模板、方法论、模式 | 项目级架构文档（→ projects `docs/`）                 |
| 通用提示词库          | 项目级 agent 规约（→ projects `.ai/`、`CLAUDE.md`） |
| agent 通用踩坑经验    | 具体项目的 openspec 变更（→ projects `openspec/`）   |
| 外部资料的链接与摘要索引    | 学习笔记与课程进度（→ learning）                       |
| 通用图表与脚本资产       | 第三方源码镜像（→ reference）                        |

**判定口诀**：**"换个项目还用得上" → ai-docs；"只对这个项目有意义" → projects。**


### 5.5 reference（第三方库仓）★ 重点章节

用户明确要求"第三方库仓库里面的目录也要分清楚"。本节完整展开。

```
reference/                      ← 仓库根
├── README.md                   # 概览 + 14 分类表 + 克隆方式 + 门禁说明
├── LICENSE                     # MIT（各 submodule 遵循上游许可）
├── .gitignore
├── .gitmodules                 # 95 条 submodule 定义
├── scripts/
│   └── check-wiki-refs.py      # 引用校验门禁
├── docs/                       # ★ 笔记层（103 文件）
│   ├── db-wiki/                # 75 篇 — 数据库源码笔记
│   │   ├── README.md           # 分类索引 + gap-analysis 链接
│   │   ├── vector/             # 9 篇
│   │   ├── key-value/          # 8 篇（含 .gitkeep）
│   │   ├── relational/         # 8 篇（含 .gitkeep）
│   │   ├── columnar/           # 6 篇（含 .gitkeep）
│   │   ├── distributed-sql/    # 5 篇（含 .gitkeep）★ oceanbase.md 无对应源码
│   │   ├── document/           # 6 篇（含 .gitkeep）
│   │   ├── extension/          # 6 篇
│   │   ├── graph/              # 6 篇
│   │   ├── search/             # 6 篇
│   │   ├── time-series/        # 6 篇（含 .gitkeep）
│   │   ├── embedded/           # 4 篇 ★ pklite.md 无对应源码
│   │   └── stream/             # 4 篇
│   ├── rag-wiki/               # 13 篇 — RAG 框架笔记
│   │   ├── README.md
│   │   ├── commercial-rag-products.md   # ★ 调研型笔记，无对应源码
│   │   ├── langchain.md  llama-index.md  haystack-ai.md  txtai.md
│   │   ├── embedchain.md  verba.md  cognita.md  r2r.md
│   │   └── quivr.md  private-gpt.md  qanything.md
│   └── agent-wiki/             # 15 篇 — Agent 框架笔记
│       ├── README.md
│       ├── commercial-agent-products.md # ★ 调研型笔记，无对应源码
│       ├── agents.md  agentscope.md  agentverse.md  agixt.md
│       ├── autogen.md  chatdev.md  crewai.md  langgraph.md
│       ├── letta.md  metagpt.md  open-interpreter.md
│       └── openai-agents.md  swarm.md
└── reference/                  # ★ 源码层（第二层 reference，见 C5）
    ├── catalog.yml             # ★ 权威清单（97 条目）
    ├── fetch-manifest.txt      # 拉取清单（73 条目）— 待改为生成物
    ├── AUDIT.md                # 克隆审计记录
    ├── README.md               # 目录语义说明
    ├── ai/
    │   ├── README.md
    │   ├── agent/              # 13 个 submodule + README.md
    │   │   ├── agents  agentscope  agentverse  agixt  autogen
    │   │   ├── chatdev  crewai  langgraph  letta  metagpt
    │   │   ├── open-interpreter  openai-agents  swarm
    │   │   └── README.md
    │   └── rag/                # 11 个 submodule + README.md
    │       ├── cognita  embedchain  haystack-ai  langchain  llama-index
    │       ├── private-gpt  qanything  quivr  r2r  txtai  verba
    │       └── README.md
    ├── benchmark/              # 5 个
    │   └── ann-benchmarks  db-bench  tpcds  tpch  vectordbbench
    ├── columnar/               # 5 个
    │   └── clickhouse  doris  druid  pinot  starrocks
    ├── distributed-sql/        # 3 个
    │   └── cockroachdb  tidb  yugabytedb
    ├── document/               # 5 个
    │   └── couchbase  couchdb  ferretdb  mongodb  ravendb
    ├── embedded/               # 3 个
    │   └── boltdb  duckdb  lmdb
    ├── extension/              # 6 个
    │   └── arrow  datafusion  hnswlib  lance  pgvector  velox
    ├── graph/                  # 6 个
    │   └── arangodb  janusgraph  kuzu  memgraph  nebula  neo4j
    ├── key-value/              # 7 个
    │   └── badger  dragonfly  foundationdb  leveldb  pebble  redis  rocksdb
    ├── relational/             # 7 个
    │   └── firebird  h2  mariadb  mysql  openGauss  postgres  sqlite3
    ├── search/                 # 6 个
    │   └── elasticsearch  meilisearch  opensearch  quickwit  tantivy  typesense
    ├── stream/                 # 4 个
    │   └── kafka  nats  pulsar  redpanda
    ├── time-series/            # 5 个
    │   └── influxdb  iotdb  questdb  tdengine  victoriametrics
    └── vector/                 # 9 个
        └── chroma  faiss  lancedb  milvus  qdrant  usearch  vald  vespa  weaviate
```

#### 5.5.1 源码层分类语义（14 个分类 + ai 二级）

| 分类                 | 语义边界                          | 数量     |
| ------------------ | ----------------------------- | ------ |
| `ai/agent/`        | Agent 框架、多智能体编排、工具调用框架        | 13     |
| `ai/rag/`          | RAG 检索增强生成工具链                 | 11     |
| `benchmark/`       | 性能基准套件（ANN、TPC-H/DS、vectordb） | 5      |
| `columnar/`        | 列式分析存储与 OLAP 引擎               | 5      |
| `distributed-sql/` | 分布式事务型、NewSQL、HTAP            | 3      |
| `document/`        | 文档数据库                         | 5      |
| `embedded/`        | 嵌入式存储与本地分析引擎                  | 3      |
| `extension/`       | 数据库扩展、索引库、存储插件                | 6      |
| `graph/`           | 图数据库                          | 6      |
| `key-value/`       | 键值存储与 LSM 系统                  | 7      |
| `relational/`      | 传统 RDBMS + 嵌入式关系型             | 7      |
| `search/`          | 搜索引擎与全文检索引擎                   | 6      |
| `stream/`          | 事件流与流数据库                      | 4      |
| `time-series/`     | 时序数据库                         | 5      |
| `vector/`          | 向量数据库与向量检索库                   | 9      |
| **合计**             |                               | **95** |

分类粒度原则：

- `extension/` 与 `benchmark/` 属于**生态项目**，不计入"完整数据库产品数量"（`reference/README.md` 已有此约定，设计文档予以确认）。
- `stream/` 中的系统不应被误算为传统数据库产品（同上）。
- `ai/` 是**唯一的二级分类**（`ai/agent` + `ai/rag`），因为它们的共同属性是"AI 应用层框架"而非"数据存储形态"。

#### 5.5.2 三份清单的职责划分（修复 C3）

| 清单                             | 新角色          | 说明                                                                         |
| ------------------------------ | ------------ | -------------------------------------------------------------------------- |
| `reference/catalog.yml`        | **唯一权威**     | 97 条目；新增 `commit` / `clone_url` / `pin_status` / `source` 字段               |
| `reference/fetch-manifest.txt` | **生成物**      | 由 `sync-catalog.py` 从 catalog 生成；**格式从 3 列扩到 5 列**（见下）                     |
| `reference/.gitmodules`        | **保持手写，不生成** | 95 条现状不动。理由：oceanbase / pklite 无源码，无 submodule 可指；且生成它会覆盖手写的 mirror URL 选择 |

**catalog.yml 字段规范（修订版）**：

```yaml
projects:
  # ── 正常条目：pin 可用 ──
  - name: faiss
    model: vector                  # 15 个合法值之一，见 5.5.1
    tier: core                     # core | representative | innovative
    repository: https://github.com/facebookresearch/faiss.git   # 上游官方（可靠）
    mirror: https://gitee.com/yinchengwang_admin/faiss.git       # 镜像（可能不含 pin）
    clone_url: https://github.com/facebookresearch/faiss.git    # ★ 实测可按 SHA 拉到
    commit: 02ea14372c9983f3eaa15698512180dc62ea234d
    pin_status: valid              # ★ valid | broken | unresolvable
    source: mirror                 # ★ mirror | none
    license: MIT
    status: active
    notes:
      - 向量检索库

  # ── 无源码镜像条目（oceanbase / pklite）──
  - name: oceanbase
    model: distributed-sql
    tier: representative
    repository: https://github.com/oceanbase/oceanbase.git
    mirror: null
    clone_url: null
    commit: null
    pin_status: unresolvable       # ★ 无源码 → 无 pin
    source: none                   # ★ 无源码镜像
    license: Apache-2.0
    status: active
    notes:
      - 无源码镜像，仅笔记；笔记中 20 处行号引用无法校验

  # ── 伪造 pin 条目（druid / pebble / tdengine / dragonfly）──
  - name: tdengine
    model: time-series
    tier: representative
    repository: https://github.com/taosdata/TDengine.git
    mirror: https://gitee.com/mirrors/TDengine.git
    clone_url: https://github.com/taosdata/TDengine.git
    commit: null                   # ★ 现有 gitlink SHA 是伪造的，不照抄
    pin_status: broken             # ★ gitlink SHA 上游不存在
    source: mirror
    license: AGPL-3.0
    status: active
    notes:
      - 现有 gitlink SHA fa8dc991… 在上游不存在（实测 not our ref + GitHub 404）
      - 笔记 tdengine.md 的 75 处行号引用当前已失效，需人工校对
```

**字段语义**：

| 字段           | 必填                      | 语义                                                                   |
| ------------ | ----------------------- | -------------------------------------------------------------------- |
| `name`       | ✅                       | 目录名                                                                  |
| `model`      | ✅                       | 15 个合法值之一；`model` + `/` + `name` 必须等于 submodule path                 |
| `tier`       | ✅                       | `core`(25) / `representative`(56) / `innovative`(16)                 |
| `repository` | ✅                       | 上游官方地址（最可靠的 fallback）                                                |
| `mirror`     |                         | 镜像地址 —— **允许与实际可拉地址不一致**，仅作记录                                        |
| `clone_url`  | `source: mirror` 时必填    | **实测可按 SHA 拉到的地址**（见下方选择规则）                                          |
| `commit`     | `pin_status: valid` 时必填 | 40 位 SHA                                                             |
| `pin_status` | ✅                       | `valid`（可按 SHA 拉到）/ `broken`（gitlink SHA 上游不存在）/ `unresolvable`（无源码） |
| `source`     | ✅                       | `mirror`（有源码镜像）/ `none`（仅笔记，无源码）                                     |
| `license`    | ✅                       | 开源许可证                                                                |
| `status`     | ✅                       | `active` / `maintained` / `legacy`                                   |
| `notes`      |                         | 技术亮点与用途说明（含已知问题）                                                     |

**`clone_url` 的选择规则（修正 C16 —— 原设计的优先级与实际可用性相反）**：

原设计写 `clone_url > mirror > repository`，但实测表明 `mirror` 恰恰是最不可靠的一档。修正后的选择逻辑：

1. **首选 GitHub 官方 `repository`** —— 实测 5 个可疑条目中，mysql 的 pinned SHA 在 `github.com/mysql/mysql-server.git` 可按 SHA 拉通，在两个 gitee 地址都取不到。
2. **次选实测可达且含该 SHA 的镜像** —— 必须逐条用 `git fetch --depth 1 <url> <sha>` 验证过才算数。
3. **禁止使用已被封禁的地址** —— `gitee.com/yinchengwang_admin/mysql-server` 实测 HTTP 423 "The Repository has been blocked"。

**`mirror` 字段的处理**：catalog 现有 6 条 `mirror` 与 `.gitmodules` 实际 URL 指向不同主机，其中 mysql 的 mirror 指向已封禁仓。**`mirror` 保留原值作为"镜像意图"的记录**（它同时是 §5.5.3 manifest 生成的输入之一），但**不再是拉取依据** —— 拉取只看 `clone_url`。`sync-catalog.py` 生成 manifest 时输出 `clone_url` 而非 `mirror`。

**一致性校验规则（`check-consistency.py`）**：

1. 每个条目必须有非空 `pin_status`，取值在 {valid, broken, unresolvable} 内。
2. `pin_status: valid` → `commit` 必须非空、40 位 hex，且 `commit` 必须与 `.gitmodules` 中同名 submodule 的 gitlink SHA 一致。
3. `pin_status: broken` → `commit` 允许为 null，但必须在 `notes` 中说明失效原因与受影响的笔记。
4. `pin_status: unresolvable` → `source` 必须为 `none`，`commit` 与 `clone_url` 必须为 null。
5. `source: mirror` → `clone_url` 必须非空。
6. `model` + `/` + `name` 必须等于 `.gitmodules` 中该 submodule 的 path（若该条目有 submodule）。
7. catalog 中有条目但 `.gitmodules` 无对应 → 仅当 `source: none` 时合法（当前：`oceanbase`、`pklite`），否则报错。
8. `.gitmodules` 中有条目但 catalog 无 → 错误（当前无此情况）。
9. `fetch-manifest.txt` 必须与 catalog 生成结果逐字节一致（`--check` 模式）。

**`fetch-manifest.txt` 新格式（从 3 列扩到 5 列）**：

原格式为 `model name mirror`（实测 73 行，无 header、无 commit）。作为 lockfile 它**必须含 pin**，否则拉取脚本无从 pin —— 这是原设计的漏洞。改为：

```
# model	name	clone_url	commit	pin_status
relational	postgres	https://github.com/postgres/postgres.git	8f3f1e2a...	valid
embedded	boltdb	https://github.com/benbjohnson/boltdb.git	1f0c2d3e...	valid
vector	faiss	https://github.com/facebookresearch/faiss.git	02ea1437...	valid
time-series	tdengine	https://github.com/taosdata/TDengine.git	-	broken
distributed-sql	oceanbase	-	-	unresolvable
```

**用 `-` 表示空值**，避免 YAML 的 `null` 与空字符串混淆。文件同时补齐 24 个缺失的 AI 类目（73 → 97）。

#### 5.5.3 笔记层与源码层的对应关系

| 笔记目录                            | 篇数 | 对应源码分类                  | 覆盖率                                        |
| ------------------------------- | -- | ----------------------- | ------------------------------------------ |
| `docs/db-wiki/vector/`          | 9  | `vector/`（9 个）          | 9/9 = 100%                                 |
| `docs/db-wiki/key-value/`       | 7  | `key-value/`（7 个）       | 7/7 = 100%                                 |
| `docs/db-wiki/relational/`      | 7  | `relational/`（7 个）      | 7/7 = 100%                                 |
| `docs/db-wiki/columnar/`        | 5  | `columnar/`（5 个）        | 5/5 = 100%                                 |
| `docs/db-wiki/document/`        | 5  | `document/`（5 个）        | 5/5 = 100%                                 |
| `docs/db-wiki/time-series/`     | 5  | `time-series/`（5 个）     | 5/5 = 100%                                 |
| `docs/db-wiki/extension/`       | 6  | `extension/`（6 个）       | 6/6 = 100%                                 |
| `docs/db-wiki/graph/`           | 6  | `graph/`（6 个）           | 6/6 = 100%                                 |
| `docs/db-wiki/search/`          | 6  | `search/`（6 个）          | 6/6 = 100%                                 |
| `docs/db-wiki/stream/`          | 4  | `stream/`（4 个）          | 4/4 = 100%                                 |
| `docs/db-wiki/embedded/`        | 4  | `embedded/`（3 个）        | 3/3 = 100% + `pklite` 无源码                  |
| `docs/db-wiki/distributed-sql/` | 4  | `distributed-sql/`（3 个） | 3/3 = 100% + `oceanbase` 无源码               |
| `docs/rag-wiki/`                | 12 | `ai/rag/`（11 个）         | 11/11 = 100% + `commercial-rag-products`   |
| `docs/agent-wiki/`              | 14 | `ai/agent/`（13 个）       | 13/13 = 100% + `commercial-agent-products` |

**规律**：笔记层严格是源码层的**超集**，多出的 3 篇全是"商业产品调研"型笔记（`commercial-rag-products.md`、`commercial-agent-products.md`、`oceanbase.md`、`pklite.md`）。这类笔记合法 —— 它们记录的是**产品认知**而非源码精读，因此不能用精确行号引用（`check-wiki-refs.py` 模式 B 对它们不做行号要求）。

`docs/*/README.md` 中必须显式标注这 4 篇为"无对应源码镜像"，供后来者理解覆盖率不是 100%。

#### 5.5.4 拉取脚本行为契约

`scripts/fetch-reference.sh` 的行为必须满足：

```
用法：
  fetch-reference.sh                        # 按 tier 拉取（core 默认）
  fetch-reference.sh --tier core            # 只拉 core
  fetch-reference.sh --model vector         # 拉某个分类全部
  fetch-reference.sh --name faiss           # 拉单个
  fetch-reference.sh --all                  # 全量（危险，需 --yes 二次确认）
  fetch-reference.sh --check                # 只校验，不拉取
```

**每个条目的拉取流程**：

1. 从 catalog 读 `clone_url`、`commit`、`pin_status`、`model`。
2. 目标路径 = `reference/<model 映射>/<name>`。
   - `model` 到目录的映射：`ai/agent` → `reference/ai/agent`，`ai/rag` → `reference/ai/rag`，其余直接同名。
3. **按 `pin_status` 分支**：
   | `pin_status`   | 行为                                                   |
   | -------------- | ---------------------------------------------------- |
   | `valid`        | 正常拉取（见下方流程）                                          |
   | `broken`       | **跳过拉取**，告警"gitlink SHA 上游不存在"，并在 `AUDIT.md` 记录待人工校对 |
   | `unresolvable` | 跳过（`source: none`，本就没有源码）                            |
   `valid` 条目的拉取流程（**在 submodule 内操作，不新建独立 clone**，见 C17 定案）：
   - 若该 submodule 尚未 init（目录为空）→ 先 `git submodule init <path>` 建立 `.git/modules/` 内的仓库，再 `git submodule update --depth 1 <path>` 拉取 **gitlink 指定的 pin**。
     - 注意：这一步**只针对单个路径**，绝不带 `--recursive`。
   - 若已 init 但 HEAD ≠ `commit` → `git -C <path> fetch --depth 1 origin <commit>`，再 `git -C <path> checkout <commit>`。
   - 若已 init 且 HEAD 已等于 `commit` → 跳过（幂等）。
   - `--depth 1` + 指定 SHA 是关键：避免拉全历史。
   - 失败时记录到 `reference/AUDIT.md` 并继续处理下一个，不中断整体。
4. **父仓洁净性保证**（C17）：
   - 因为这 95 个目录是真正的 submodule（gitlink），checkout 到 gitlink SHA 后父仓 `git status` **必然干净** —— 这是选 submodule 语义的主要收益。
   - 若检测到父仓出现 ` M reference/...`（HEAD 漂移），脚本必须**自动纠正**：`git -C <path> checkout <commit>`。
   - 脚本**绝不**执行 `git submodule update --init --recursive`（会触发 25 GB 递归拉取，违反反目标 A）。脚本启动时应显式检查并警告该命令已被使用者手动执行过。
5. **幂等性**：脚本可重复执行，已拉取且 pin 一致的条目直接跳过。

**磁盘预估**：单库典型 20~500 MB（faiss 13 MB 已 init，clickhouse / milvus 等大型库可达数百 MB）。`--all` 前脚本打印预估并要求交互确认。

---

## 6. repos.yaml 字段规范

`StillEvolving/repos.yaml` 是"这四个仓是什么关系"的唯一权威声明。

```yaml
version: 1
repos:
  - name: projects
    url: https://github.com/yinchengwang/projects.git
    fetch: submodule              # submodule | manifest
    path: projects                # 相对 StillEvolving 根
    role: 工程仓
    must_contain: [engine, apps, docs, openspec, .ai, vendor, dataset, scripts, archive]
    description: 自研数据库/搜索引擎引擎、微信小程序、项目级文档与 agent 规约

  - name: learning
    url: https://github.com/yinchengwang/learning.git
    fetch: submodule
    path: learning
    role: 学习仓
    must_contain: [scaffold, notes, code-solutions, ds-c, arkts, interview, algo-c, progress, third_part]
    description: Obsidian 学习 vault、脚手架工程、算法题解、课程进度

  - name: ai-docs
    url: https://github.com/yinchengwang/AI-DOCS.git
    fetch: submodule
    path: ai-docs
    role: AI 工作文档仓
    must_contain: [templates, methodology, patterns, assets, prompts, agent-notes]
    description: 跨项目复用的模板、方法论、模式、提示词与 agent 经验

  - name: reference
    url: https://github.com/yinchengwang/reference.git
    fetch: manifest               # ★ 不进 submodule 树
    path: ../reference             # ★ 相对 StillEvolving 根的兄弟目录
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
        path 用 ../reference 表达"与 StillEvolving 平级但不在其内"，
        使 check-consistency.py 能从父仓根解析到它，无需硬编码绝对路径。
```

**字段说明**：

| 字段             | 必填                    | 说明                                             |
| -------------- | --------------------- | ---------------------------------------------- |
| `name`         | ✅                     | 仓名，与 GitHub 仓库名对应                              |
| `url`          | ✅                     | clone URL                                      |
| `fetch`        | ✅                     | `submodule` = git 原生挂载；`manifest` = 脚本按需拉取     |
| `path`         | ✅                     | 相对 StillEvolving 根的路径。允许 `../` 前缀（reference 用） |
| `role`         |                       | 一句话定位                                          |
| `must_contain` |                       | **必须存在的**顶层目录/文件 —— 子集断言                       |
| `description`  |                       | 详细说明                                           |
| `upstream`     | `fetch: manifest` 时必填 | 上游清单描述                                         |

**`must_contain` 是子集断言，不是相等断言**（修正原设计）：

原设计写"验证每个仓的实际顶层目录是否与 `contains` 声明**一致**"，但实测四仓的实际顶层项数远多于任何合理的声明：

| 仓         | 实际顶层受跟踪项                                                                                                                                                                                                                 | `must_contain` 声明数 |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------ |
| projects  | 20 项（`.ai .github .gitattributes .gitignore .gitmodules .obsidianignore .playwright-mcp AGENTS.md CLAUDE.md CMakeLists.txt LICENSE README.md apps archive dataset docs engine openspec scripts skills-lock.json vendor`） | 9                  |
| learning  | 17 个目录 + 7 个 `r*-progress.md` + 4 个根文件                                                                                                                                                                                   | 10                 |
| reference | 7 项（`.gitignore .gitmodules LICENSE README.md docs reference scripts`）                                                                                                                                                   | 3                  |

相等断言会**对四仓全部失败**。改为子集断言后语义清晰且可执行：

> **`must_contain` 列出的每一项都必须在该仓中存在。仓中多出的其他顶层项不算违规。**

这样既能防止"engine/ 被误删""docs/ 被搬走"这类漂移，又不要求穷举每个点文件。`check-consistency.py` 实现：解析 `must_contain` → 列出该仓实际顶层受跟踪项 → 报告缺失项（缺失 = 错误）。

**`path` 用 `../reference` 的理由**：原设计说 reference"不在 StillEvolving 目录树里"，但 `repos.yaml` 又写 `path: reference`，而字段语义定义 `path` 是"在 StillEvolving 下的路径" —— 校验器无法从父仓根定位它，只能硬编码 `C:\code\reference`（不可移植）。改用 `../reference` 表达"与 StillEvolving 平级的兄弟目录"，既符合实际布局，又让校验器能用相对路径解析，保持"换个项目还用得上"的自解释目标。

**关于 `updated` 字段**：原设计写 `updated: 2026-10-25`（硬编码日期）。生成型文件带硬编码日期必然漂移 —— 每次改内容都要手改。**已移除该字段**。若后续需要记录更新时间，由 `sync-catalog.py` 自动写入生成物，不放在手写的 `repos.yaml` 里。

---

## 7. 迁移动作清单

### 7.0 依赖顺序（修正 —— 原设计 M2 与 M21 顺序颠倒）

实测确认：`AI-DOCS.git` 是**空仓**（`git ls-remote` 无输出）。空仓执行 `git submodule add` 会失败：

```
warning: You appear to have cloned an empty repository.
fatal: You are on a branch yet to be born
fatal: unable to checkout submodule 'ai-docs'      ← 退出码 128
```

失败后 `.gitmodules` **不会生成**，父仓只留下一个未跟踪的 `ai-docs/` 目录。根因是 `submodule add` 需要 checkout 远端 HEAD —— 空仓没有对应 ref。

**因此 M2 依赖 M21 的产物，顺序必须调整**：

```
M1  →  M21  →  M2  →  M3/M4/M5/M6
（改 remote）（建 ai-docs 骨架并推送首个提交）（加 submodule）（catalog 与脚本）
```

正确顺序：**M1 → M21 → M2 → M3~M6**。原设计把 M21 归在"内容归位级"排在 M2 之后，顺序错误。

### 7.1 阻塞级（必须先做，严格按序）

| #   | 动作                                                                | 涉及                      | 验收标准                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --- | ----------------------------------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| M1  | 更新 projects 的 remote URL                                          | `book` → `projects.git` | `git remote -v` 显示 `yinchengwang/projects.git`。**风险极低** —— 实测 `book.git` 与 `projects.git` 都可达且指向同一 commit `495c8f1e`（GitHub 改名自动重定向）。验收用 `git ls-remote` 对比两者 SHA 一致                                                                                                                                                                                                                                                                 |
| M21 | **ai-docs 从零创建目录结构并推送首个提交**                                       | AI-DOCS                 | 按 §5.4 目标树建目录 + 各目录 README + `INDEX.md`；`git push` 后 `git ls-remote` 返回非空、且分支名与远端 HEAD 一致。**必须在 M2 之前**                                                                                                                                                                                                                                                                                                                              |
| M2  | 在已有的 StillEvolving 仓上加三个 submodule                                | StillEvolving           | 仓已存在（C15），含 LICENSE 与 README → **保留并扩写 README**。`git submodule status` 三条无 `-` 前缀                                                                                                                                                                                                                                                                                                                                                    |
| M3  | catalog.yml 补 `commit` / `clone_url` / `pin_status` / `source` 字段 | reference               | 97 条全部带 `pin_status` 与 `source`。分布：**91 条 `valid`**（commit 为 40 位 hex 且与 gitlink 一致）+ **4 条 `broken`**（druid / pebble / tdengine / dragonfly）+ **2 条 `unresolvable`**（oceanbase / pklite，无源码镜像，`source: none`，`commit` 与 `clone_url` 为 null）。**91 + 4 + 2 = 97**。<br />注：mysql 曾被初判为 `broken`（SHA 真实存在、只是 gitee 镜像不含它），改 `clone_url` 为 GitHub 官方后即可正常拉取，故 mysql 计入 `valid`。<br />4 条 `broken` 的 `commit` 为 null 且 notes 写明失效原因与受影响笔记 |
| M4  | 逐条实测确定 `clone_url`                                                | reference               | 每条 `source: mirror` 的 `clone_url` 都经 `git fetch --depth 1 <url> <sha>` 验证通过。**优先 GitHub 官方 `repository`**；mysql 必须改用 `github.com/mysql/mysql-server.git`（两个 gitee 地址都取不到）                                                                                                                                                                                                                                                            |
| M5  | 重建 fetch-manifest.txt（97 条，5 列）                                   | reference               | 补齐 24 个 AI 类目（73 → 97）；加 `commit` 与 `pin_status` 列；`check-consistency.py --check` 逐字节一致                                                                                                                                                                                                                                                                                                                                              |
| M6  | 编写 `scripts/fetch-reference.sh`                                   | StillEvolving           | `--name faiss` 能拉到 pin 的 commit 且幂等；`--name tdengine`（broken）跳过并告警                                                                                                                                                                                                                                                                                                                                                                   |

### 7.2 M2 的两条实施路径（需在实现前选定）

`C:\code\book` 已是完整的 5.3 GB 工作树、本地 `main` 与 `origin/main` 同步。要把它变成 `StillEvolving/projects/`，有两条路：

**路径 A — 迁移既有工作树（推荐）**

1. `C:\code\book` → `C:\code\StillEvolving\projects`（移动，零新增磁盘占用）
2. 在 `StillEvolving` 下 `git submodule add <url> projects` —— 对已有正常 HEAD 的目录，git 会输出 `Adding existing repo at 'projects' to the index` 并成功
3. 处理硬编码路径：`projects/docs/path-mapping.md`（本身是路径映射契约文档）、`.ai/.claude/settings.json`、`learning/scaffold/cpp/parallel_stl/NOTES.md`（C19）

- 优点：**零新增磁盘占用**（满足反目标 D）、保留本地未推送状态、不需重拉 1.7 GB `.git` + 673 MB LFS
- 代价：`C:\code\book` 路径消失，需同步更新硬编码引用

**路径 B — 重新 clone**

1. `git submodule add <url> projects` 让 git 自己 clone
2. **实测风险**：普通 clone 出现过 `fatal: fetch-pack: invalid index-pack output`（大仓 + Windows + LFS 场景）。**该错误为偶发** —— 复检时重试同类大仓（postgres）即成功，因此不能断定路径 B 必然失败
3. `--filter=blob:none` 可把工作树压到 91 MB；需 `git lfs pull` 补 673 MB LFS 对象

- 优点：目录结构最干净，无历史残留
- 代价：**+2 GB 磁盘占用**（LFS 与 `.git` 重复），与反目标 D 直接冲突。这是路径 B 的**决定性**代价，而非 clone 失败

> **我的建议：路径 A。** 决定性理由是反目标 D —— 路径 A 的磁盘占用**完全不变**，路径 B 至少多 2 GB（LFS 与 `.git` 重复）。clone 失败是偶发的，不作为主要依据。路径 A 的代价（硬编码路径）只涉及 3 个文件，且 `docs/path-mapping.md` 本来就要改。

### 7.3 清理级（可并行）

| #   | 动作                                                 | 收益            | 风险                                                                                                                                                                                                                                                       |
| --- | -------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M7  | 删除 `C:\code\book.worktrees\`                       | **回收 999 MB** | 低 —— git 完全不认这三个目录（C11），纯死残留。但含 `minimax-coding-plan-implementation/` 的旧 `engineering/` 布局，删除前先归档有价值部分                                                                                                                                                   |
| M8  | 删除 `C:\code\verify_learning\`                      | 消除损坏仓干扰（C12）  | 低 —— HEAD 指向 `.invalid`，refs 为空，无任何可恢复内容；是 learning 的重复克隆且已损坏                                                                                                                                                                                            |
| M9  | `C:\code\3D相册\3D相册-1\` 执行 `git init`               | 让它进入版本控制（C13） | 低 —— 但需先确认它要归入哪个仓（见 §8 待确认 Q2）                                                                                                                                                                                                                           |
| M10 | 清理 projects `archive/` 的 11 个散落未跟踪文件               | 目录整洁          | 中 —— `task-*-report.md` 可能有价值，建议先归入 `archive/` 对应日期目录再删散落位置                                                                                                                                                                                              |
| M11 | googletest 去重                                      | 省一份 clone     | 中 —— projects 用 `vendor/third_part/googletest`，learning 用 `third_part/googletest`。**建议保留两份**（各自 pin 不同版本可能性存在），只在 `repos.yaml` 注释中记录重复事实；如要统一，需两个仓各改 `.gitmodules`，风险高于收益                                                                                |
| M12 | reference 内部 95 个目录保留 submodule 语义（**已定案**，修复 C17） | 防止父仓被污染       | **已定案**：`.gitmodules` 95 条不动，这 95 个目录继续是 submodule。脚本改为"在 submodule 内 `init` + `fetch --depth 1 <sha>` + `checkout <sha>`"。父仓永远干净、pin 永远一致。代价：`git submodule update --init --recursive` 仍会拉 25 GB → **必须在 reference README 与脚本输出中明确警告不要用 `--recursive`** |
| M13 | reference `.gitignore` 的 `reference/*/` 规则         | 消除误导          | 低 —— 该规则实测不生效（C5/C17），删除并加注释说明"gitlink 目录不进父仓索引，不靠 gitignore"                                                                                                                                                                                            |

### 7.4 内容归位级（需决策，见 §8）

| #    | 动作                                                                   | 说明                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M14  | `projects/openspec/specs/learning/`（35 文件）→ learning                 | 学习轨 spec 不该在工程仓（C7）。learning 仓需新建 `openspec/specs/` 结构                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| M15  | `projects/openspec/specs/` 的 32 个 `r*` 目录 → learning（**按内容判定，不按命名**） | **修正**：不是 12 个文件，是 32 个目录（C18）。判定信号见 M15a。**建议：19 个留在 projects，12~13 个纯学习向的搬走**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| M15a | **判定信号**（内容判定，非命名判定）                                                 | 三类信号，任一命中即**留在 projects**：<br />① 引用 `engineering/` 路径 —— 实测 19 个 spec 命中。**注意 `engineering/` 是 `engine/` 的旧名**（当前仓库只有 `engine/`，无 `engineering/`），这些 spec 引用的是过时路径（`engineering/src/db/storage/page/disk.c` 等）。它们描述的正是"学习卡 ↔ 工程实现"的对照关系（如 `r8-engineering-tooling` 要求 NOTES.md"至少引用一个 `engineering/` 路径"），搬走会让引用彻底悬空<br />② 引用 projects 专属路径 `apps/` —— 实测 `r6-language-tranche`（`apps/web/reading-radar/data/r6-progress.md`）与 `r7-ds-algo` 命中，`apps/` 是 projects 的小程序目录<br />③ 引用 `engine/` 或其他 projects 专属路径<br /><br />**无 projects 路径引用的 13 个**：`r12b-systems`、`r19-cpp-systems`、`r23-linux-perf`、`r24-linux-storage`、`r26-linux-advanced-net`、`r29-ds-advanced`、`r30-python-basics`、`r31-python-advanced`、`r32-python-tools`、`r33-grokking-algo`、`r37-grokking-db`、`r38-grokking-ml`、`r6-language-tranche`<br />⚠️ **`r6-language-tranche` 需人工复核** —— 它命中信号②（引用 `apps/web/reading-radar/`），实际应**留在 projects**。这说明纯靠正则列举不够稳，实施时须逐个确认。**M15 的实际可搬走数量是 12，不是 13** |
| M16  | `projects/docs/analysis/`（27 文件）留在 projects，reference 的断链改为跨仓链接      | **文件名映射干净**：`projects/docs/analysis/` 里的 `README.md` + 12 个分类名（`relational.md` `key-value.md` `document.md` `columnar.md` `time-series.md` `search.md` `vector.md` `graph.md` `stream.md` `embedded.md` `extension.md`）+ `rag.md` + `agent.md` 与 reference 3 份 README 的 16 处引用**一一对应**（C8 实测；14 个独立目标文件）。`01-`~`10-` 编号版是并列的另一套，不影响映射                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| M17  | learning 的 7 个 `r*-progress.md` 归入 `progress/`                       | 顶层散落 → `progress/r25-progress.md` 等（与已有 `progress/r26-progress.md`、`r32-progress.md` 一致）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| M18  | learning `notes/` 顶层 7 个散落文件归位                                       | `ds-art.md` / `ds-radix-tree.md` / `ds-rtree.md` / `ds-skiplist.md` / `ds-ttree.md` → 新建 `notes/ds/`（**不建议塞进已有的 `notes/DB/`** —— 该目录已有 29 个文件且以数据库笔记为主，数据结构笔记单列更清晰）；`README.md` 留顶层；`.sync-pipeline-state.json` 是工具状态 → 加 gitignore                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| M19  | reference 的 `oceanbase` / `pklite` 在 catalog 中标 `source: none`       | 消除 C3 的两处不一致（oceanbase 20 处引用、pklite 引用同样无法校验）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| M20  | reference 三份 README 的 `../gap-analysis/*.md` 断链（16 处）→ 跨仓链接          | **需先定链接形式**（见 §8 Q4）。文件名映射一一对应，改起来不难                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| M26  | reference README 的"14 个技术分类"表述                                       | 实际是 15 个分类（`ai` 为二级，展开为 `ai/agent` + `ai/rag` 则为 16 个叶子分类）。需统一口径                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| M22  | 处理 4 个 `pin_status: broken` 条目的笔记                                    | `tdengine.md`（75 处）、`mysql.md`（21 处）、`pebble.md`（4 处）、`dragonfly.md`（2 处）共 102 处行号引用当前已失效。**需人工校对** —— 重选上游 commit 会让行号全体漂移。**我的建议：保留现状并标注**，在笔记顶部加"本文行号引用基于失效 pin，需重新校对"的警示                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### 7.5 增强级（可选）

| #   | 动作                                             | 价值                                                                                                                                                                   |
| --- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M23 | learning 加最小 CI                                | 当前只有 projects 有 CI（C10）。learning 的 C/C++ 代码值得加一个编译冒烟                                                                                                                 |
| M24 | reference 加 wiki 引用门禁 CI                       | 模式 B 的合规性检查（10 篇）可自动化，PR 门禁                                                                                                                                          |
| M25 | `StillEvolving` 加 `check-consistency.py` 接入 CI | 校验 repos.yaml ↔ .gitmodules ↔ catalog ↔ 实际目录                                                                                                                         |
| M27 | 把 `C:\code\docs/` 三个文件迁入 StillEvolving         | `architecture-review-2026-10-25.md`、`repos.yaml.sample.yaml`、本设计文档 —— 当前都不在任何 git 仓里（C14）。`repos.yaml.sample.yaml` 是 §6 的前身（**它没有 `must_contain` 字段**），应一并更新或标注为历史版本 |

---

## 8. 待确认决策（需用户回答）

以下五点会改变实际要建的东西，无法由我单方面判定。按重要性排序。

### Q1（最重要）：4 个失效 pin 的 102 处行号引用怎么处理？

实测发现 4 个 submodule 的 gitlink SHA 在上游根本不存在（C0）。受影响的笔记引用共 102 处：

| 笔记             | 引用数 | 状态                                |
| -------------- | --- | --------------------------------- |
| `tdengine.md`  | 75  | pin 伪造，引用当前已失效                    |
| `mysql.md`     | 21  | SHA 真实，但 gitee 镜像不含它；换 GitHub 可拉到 |
| `pebble.md`    | 4   | pin 伪造，引用当前已失效                    |
| `dragonfly.md` | 2   | pin 伪造，引用当前已失效                    |
| `druid.md`     | 0   | pin 伪造，但无引用                       |
| `oceanbase.md` | 20  | 无源码镜像，引用无法校验                      |

三种做法：

| 方案          | 做法                                               | 后果                                        |
| ----------- | ------------------------------------------------ | ----------------------------------------- |
| **A（我的建议）** | 保留现状 SHA 并标注 `pin_status: broken`，笔记顶部加"需重新校对"警示 | 现状不恶化，102 处引用明确标记为待校对；拉取脚本降级为"拉 HEAD 并告警" |
| B           | 重新选一个上游 commit 并接受行号漂移                           | 这 102 处引用**全体错位**，需要逐条重新核对 —— 工作量大但根治     |
| C           | 把这 4 篇笔记从 `mode B` 门禁清单移出，不再校验                   | 放弃校验，但立刻"绿"                               |

**需要你确认：选 A / B / C？** 我倾向 A —— 因为 B 意味着 102 处人工校对，C 意味着放弃门禁。也可以先 A 后 B（标注出来，排期慢慢校）。

### Q2：projects 工作树是"移动"还是"重新 clone"？

`C:\code\book` 是 5.3 GB 完整工作树。变成 `StillEvolving/projects/` 有两条路（详见 §7.2）：

- **路径 A（我的建议）**：移动既有工作树 → **零新增磁盘占用**（磁盘基线完全不变），保留本地未推送状态与构建缓存；代价是 `C:\code\book` 路径消失，需更新 3 个硬编码 `C:/code` 的文件（含 `docs/path-mapping.md` 这份路径映射契约文档）
- **路径 B**：重新 clone → 目录最干净，无历史残留；但需重拉 1.7 GB `.git` + 673 MB LFS 对象（**+2 GB 磁盘占用**，与反目标 D 冲突），且**实测存在偶发失败**（`fatal: fetch-pack: invalid index-pack output`）

> **关于 clone 失败的重要澄清**：复检时发现 `invalid index-pack output` 是**偶发**的 —— 重试同一类大仓（postgres）即成功。**因此不能把"clone 会失败"当作路径 B 的决定性理由。**
>
> 路径 B 的真正代价是**磁盘**：+2 GB（LFS 与 `.git` 重复），而反目标 D 明文要求"任何让 `C:\code` 总占用显著高于当前基线的方案都算失败"。路径 A 磁盘占用**完全不变**。
>
> 若你更在意"目录干净、无历史残留"而不在意磁盘，可选路径 B；若你更在意磁盘与已有状态，选路径 A。**我仍建议 A。**

**需要你确认：走 A 还是 B？**

### Q3：`3D相册` 归到哪里？

`C://code//3D相册//3D相册-1//` 目前不是 git 仓。它是：projects 的一个 app？ai-docs 的一份素材？还是独立仓？

### Q4：reference 的 16 处断链改成什么形式的链接？

`reference/docs/{db-wiki,rag-wiki,agent-wiki}/README.md` 共 16 处引用 `../gap-analysis/*.md`，但 `reference/docs/gap-analysis/` 不存在；实际内容在 `projects/docs/analysis/`，且**文件名一一对应**（`README.md` + 11 个分类名 + `rag.md` + `agent.md` = 14 个独立目标文件，全部对得上）。

三种形式：

| 形式          | 例子                                                                                                             | 代价                                          |
| ----------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **A（我的建议）** | GitHub blob URL 带 **commit SHA**：`https://github.com/yinchengwang/projects/blob/<SHA>/docs/analysis/vector.md` | 链接稳定不漂移，但 projects 每次提交后这 13 个 SHA 都要手工更新   |
| B           | 用分支名 `main`：`https://github.com/yinchengwang/projects/blob/main/docs/analysis/vector.md`                       | 免维护，但内容会随仓库演进漂移（正是反目标 B 要避免的）               |
| C           | 在 reference 仓内放一份 gap-analysis 笔记副本                                                                            | 链接保持仓内相对路径，但**内容变成两份**，与 M16"留在 projects"冲突 |

**需要你确认：A / B / C？** 我倾向 A。

### Q5：AI-DOCS 收什么、不收什么，与 projects 的 `docs/` 边界如何划？

现状是 `projects/docs/` 有 318 个文件、`openspec/` 有 162 个文件、`.ai/` 有 202 个文件 —— 如果 AI-DOCS 是"所有 AI 的工作文档"，那理论上 projects 的 `docs/arch/`（66 篇架构设计）、`docs/process/`（106 篇流程）也该搬过去。但这会直接违反反目标 C（agent 失去项目上下文）。

我的建议：**AI-DOCS 只收跨项目复用的资产**（模板、方法论、通用模式、提示词、agent 经验），projects 的 `docs/` 与 `openspec/` 全部原地保留。判定口诀："换个项目还用得上 → AI-DOCS；只对这个项目有意义 → projects"。

**需要你确认：这条边界对吗？还是你原本设想的是"projects 的 docs/ 也搬"？**

---

## 9. 设计文档落盘位置

**当前约束**：`C:\code` 根目录不是 git 仓（C14），`StillEvolving` 仓尚未创建 → 本文档暂时放在 `C:\code\docs\superpowers\specs\`，等 StillEvolving 建好后迁入 `StillEvolving/docs/superpowers/specs/`。

（brainstorming skill 规定软件仓内应放 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` 并提交。落盘位置待 §8 的 Q1 确认后一并处理。）

---

## 10. 留给实现者的事项

以下留给实现者，不在本文档定死：

1. `bootstrap.ps1` / `bootstrap.sh` 的具体交互（是否检查 git 版本、是否自动装 LFS、是否检查 Python 依赖）。
2. `fetch-reference.sh` 的并发策略（串行 vs 限制并发数）—— 上游服务器可能限流。
3. `catalog.yml` 的 `tier` 阈值调优（core 25 个是否太大）。
4. `check-consistency.py` 用什么 YAML 解析库（PyYAML 依赖 vs 手写解析）。
5. bootstrap 是否支持 Windows / macOS / Linux 全平台，或先只做 Windows + Git Bash。

---

## 11. 我做的自主决定（My Call）

以下是我自行判定并写入文档的，实现时按此执行，评审时重点看这几条。标 ⚠️ 的条目是 builder check 后新增或修正的。

| #  | 决定                                                                                           | 理由                                                                                                                                                                     |
| -- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1  | reference **不进** StillEvolving 的 submodule 树                                                 | 形态 B 的定义；避免 25 GB / 3 层嵌套                                                                                                                                              |
| 2  | reference 仓位置保持在 `C:/code/reference`，与三个 submodule 平级但不在 StillEvolving 内                     | 不强绑工作目录布局                                                                                                                                                              |
| 3  | `catalog.yml` 为唯一权威清单，`fetch-manifest.txt` 降级为生成物                                            | 消除 C3 的三份清单不一致                                                                                                                                                         |
| 4  | ⚠️ **对 4 个伪造 pin 条目，`commit` 不照抄 gitlink**                                                   | C0 实测：`druid` / `pebble` / `tdengine` / `dragonfly` 的 SHA 在上游不存在（`not our ref` + GitHub 404），父仓也不持有这些对象。照抄就是复刻坏 pin                                                    |
| 5  | ⚠️ **catalog 引入 `pin_status`（valid/broken/unresolvable）与 `source`（mirror/none）两个状态字段**       | C0/C3：6 个条目没有合法 commit 值可填，但校验规则要求 commit 非空 —— 需要状态字段让规则自洽                                                                                                            |
| 6  | ⚠️ **`clone_url` 优先用 GitHub 官方 `repository`，而非 mirror**                                      | C16 实测：原设计的 `clone_url > mirror > repository` 优先级与实际可用性正好相反。mysql 的 pinned SHA 在两个 gitee 地址都取不到，在 GitHub 官方可拉通                                                         |
| 7  | ⚠️ **`mirror` 字段保留原值但不再作为拉取依据**                                                              | C16：catalog 的 6 条 mirror 与 `.gitmodules` 实际 URL 指向不同主机，其中 mysql 的 mirror 指向已被 Gitee 封禁的仓（HTTP 423）。mirror 作为"镜像意图"记录保留                                                 |
| 8  | ⚠️ **`.gitmodules` 保持手写不生成**                                                                 | oceanbase / pklite 无源码，submodule 无从指向；且生成它会覆盖手写的 mirror URL 选择                                                                                                         |
| 9  | ⚠️ **`fetch-manifest.txt` 从 3 列扩到 5 列**（加 `commit` + `pin_status`）                           | 作为 lockfile 必须含 pin，否则拉取脚本无从 pin —— 这是原设计的漏洞                                                                                                                           |
| 10 | ⚠️ **`must_contain` 是子集断言，不是相等断言**                                                           | 实物测：projects 实际顶层 20 项、learning 24 项、reference 7 项，相等断言会对四仓全部失败                                                                                                        |
| 11 | ⚠️ **reference 的 `path` 写 `../reference`**                                                   | 校验器需从父仓根解析到它；硬编码绝对路径不可移植                                                                                                                                               |
| 12 | ⚠️ **M21（ai-docs 骨架）提到阻塞级，排在 M2 之前**                                                         | C15 实测：AI-DOCS 是空仓，`git submodule add` 直接退出 128（"branch yet to be born"），`.gitmodules` 不生成                                                                             |
| 13 | ⚠️ **M2 走"移动既有工作树"（路径 A），不重新 clone**                                                         | 反目标 D 要求不增加磁盘占用；实测普通 clone 在 5.3 GB 仓上失败（`invalid index-pack output`），成功则 +2 GB LFS 重复                                                                                 |
| 14 | ⚠️ **M15 按 spec 内容判定轨道，不按 `r*` 命名**                                                          | C18 实测：32 个 `r*` 目录中 19 个引用 `engineering/` 路径（如 `r8-engineering-tooling` 要求 NOTES.md "至少引用一个 `engineering/` 路径"）。按命名批量搬会打断跨轨依赖                                         |
| 15 | ⚠️ **reference 内部 95 个目录保留 submodule 语义**                                                    | C17：保留 gitlink 身份，父仓永远干净、pin 永远一致；代价是必须在 README 与脚本中警告不要用 `git submodule update --init --recursive`                                                                    |
| 16 | ⚠️ **`repos.yaml` 移除硬编码的 `updated` 字段**                                                      | 生成型文件带硬编码日期必然漂移                                                                                                                                                        |
| 17 | ⚠️ **`learning` 的数据结构笔记新建 `notes/ds/`，不塞进 `notes/DB/`**                                      | `notes/DB/` 已有 29 个数据库笔记；数据结构笔记单列更清晰                                                                                                                                   |
| 18 | `repos.yaml` 加 `must_contain` 做机器可读的目录断言                                                     | 让"目录规范"可被 CI 校验，防漂移                                                                                                                                                    |
| 19 | projects 的 `.ai/`、`CLAUDE.md`、`AGENTS.md`、`openspec/`、`skills-lock.json` **全部原地保留**          | 反目标 C                                                                                                                                                                  |
| 20 | `projects/docs/analysis/` 留在 projects，reference 的断链改为跨仓链接                                    | 断链是链接写法问题，不是内容归属问题；且文件名映射一一对应，改起来不难                                                                                                                                    |
| 21 | learning 的 7 个 `r*-progress.md` 归入 `progress/`                                               | 与已有 `progress/r26-progress.md`、`notes/DB/` 惯例一致                                                                                                                        |
| 22 | googletest 保留两份，不去重                                                                          | 统一 pin 需改两个仓 `.gitmodules`，风险 > 收益；改为在 `repos.yaml` 注释记录                                                                                                               |
| 23 | `book.worktrees/`（999 MB）直接删除，`minimax-coding-plan-implementation/` 中的 `engineering/` 旧布局先归档 | git 不认这些目录（C11），但旧布局含历史信息                                                                                                                                              |
| 24 | `verify_learning/` 直接删除                                                                      | HEAD 指向 `.invalid`，refs 为空，无可恢复内容（C12）                                                                                                                                 |
| 25 | `reference/.gitignore` 的 `reference/*/` 规则删除                                                 | 实测不生效，保留误导（C5/C17）                                                                                                                                                     |
| 26 | 目录分类口径统一为"15 个分类，`ai` 为二级分类"                                                                 | README 现写"14 个"与实际不符（M26）                                                                                                                                              |
| 27 | `oceanbase` / `pklite` 保留在 catalog，标 `source: none`                                          | 笔记有价值，不删（C4）；但其 20+ 处引用明确标注为无法校验                                                                                                                                       |
| 28 | ⚠️ **带 `reference/` 前缀的 205 处引用不做批量改写**                                                      | 复检实测：`check-wiki-refs.py` 的 `resolve()` 对带前缀路径走"退回仓库根"分支，只要 `reference/` 目录名不变就能解析。205 处只集中在 7 个文件，改写是无谓 churn 且会引入新错误                                                 |
| 29 | ⚠️ **reference 内部 95 个目录保留 submodule 语义**（已定案）                                               | C17：gitlink 机制保证父仓永远干净、pin 永远一致；改普通 clone 需让父仓索引与磁盘长期不一致。代价是必须警告不要用 `git submodule update --init --recursive`                                                          |
| 30 | ⚠️ **M15 判定信号：`engineering/`（旧名）+ `apps/` + `engine/` 三类**                                   | 复检实测：`engineering/` 是 `engine/` 的旧名（当前只有 `engine/`），19 个 spec 引用的是过时路径 —— 这比"是否引用 engineering/"更能识别出"这些 spec 描述的是学习卡 ↔ 工程实现的对照关系"。另 `r6`/`r7` 引用 projects 专属的 `apps/`  |
| 31 | ⚠️ **Q2 的论证基础改为磁盘，而非 clone 失败**                                                              | 复检发现 `invalid index-pack output` 是偶发（重试 postgres 即成功），不能作为决定性理由。决定性代价是路径 B 的 +2 GB（LFS 重复）直接违反反目标 D                                                                    |
| 32 | ⚠️ **`fetch-manifest.txt` 用 `-` 表示空值**                                                       | 避免 YAML `null` 与空字符串在 5 列 TSV 中混淆                                                                                                                                      |
| 33 | ⚠️ **`.gitmodules` 的 `url` 与 catalog 的 `clone_url` 允许分歧**                                    | 复检实测：mysql 的 `.gitmodules` URL（gitee mirrors）实测取不到该 pin，而 GitHub 官方可取。两者职责不同 —— `.gitmodules` 是 git 原生记录，`clone_url` 是"实测可用的拉取地址"。分歧必须在 `check-consistency.py` 中告警而非报错 |
| 34 | ⚠️ **M15 实际可搬走数量定为 12（非 13）**                                                                | `r6-language-tranche` 引用 `apps/web/reading-radar/`，属 projects 专属路径，应留在 projects                                                                                        |

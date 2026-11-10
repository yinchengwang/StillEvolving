# 算法能力提升计划 App —— 设计文档

> 日期：2026-11-10
> 状态：设计已确认，待写实施计划
> 归属仓：`projects`（工程产物） + `learning`（学习数据）

---

## 0. 一句话

一个跑在本机的 Web 应用，把「练什么、怎么判、什么时候复习、哪里薄弱」这条闭环管起来：
本地静态题库打底，LLM 做增强，判题走真实编译执行，进度与错题写回 learning 仓进 git。

---

## 1. 需求与约束（已确认的决策）

### 1.1 四项核心能力（全部要做，构成闭环）

| # | 能力 | 含义 |
|---|---|---|
| 1 | **每天告诉我该练什么** | 排程 + 推送 |
| 2 | **练完帮我记住** | 间隔重复 + 错题沉淀 |
| 3 | **检验我的真实水平** | 限时答题 + 自动判题 + 弱项诊断 |
| 4 | **统筹整个算法学习路线** | 全局路线图 + 进度可视化 |

四者不是并列的四个功能，而是一条闭环：**排程(1) → 练/测(3) → 复习(2) → 全局进度(4)**。

### 1.2 载体

**本地 Web 应用**（浏览器访问本机服务）。选它而不是小程序，是因为它能直接接上 `engine/db` 的
向量检索与 RAG；且判题需要真实编译执行，原生小程序做不到。

### 1.3 内容来源

**本地静态题库 + LLM 辅助 + LLM 实时出题**，三样都要。**不使用** `engine/db` 作为检索层
（db 内核仍在 v1.1 步骤 4，现在接入是为未来的自己挖坑）。

### 1.4 判题方式

**本地服务端真实编译真实执行**：C/C++ 走 `g++`，Python 走 `python3`。

### 1.5 目标（四条轨道，全部覆盖）

| track | 含义 |
|---|---|
| `interview` | 面试算法岗（套路题、限时、中等难度为主） |
| `fundamentals` | 底层基本功（数据结构 + 经典算法手写实现） |
| `advanced` | 算法设计与分析进阶（图论、DP、贪心、字符串、数学等） |
| `engineering` | 工程向算法（存储引擎、B+tree/LSM、HNSW/IVF、并发与调度） |

### 1.6 节奏形态

**轮次制 + 事件驱动**：

- **轮次制**定义「学什么」—— 一个主题轮次拆成题目/卡片清单，逐项打勾（沿用 `learning/progress/rXX-*.md` 既有格式）
- **事件驱动**定义「现在做什么」—— 不排死表，打开 app 时从当前轮次与待办池里推下一题

### 1.7 数据落点

**双层，按读写频率分**：

| 内容 | 落点 | 理由 |
|---|---|---|
| 轮次清单、知识点状态、错题订正与心得 | **learning 仓（git）** | 低频、人要看、要 review |
| 每次作答流水、耗时、判题结果、SM-2 调度状态 | **app 的 SQLite** | 高频、机器读写、无需 review |
| 两侧连接 | **稳定题目 ID 互链** | `id` 是唯一连接键 |

一句话：**人读的内容进 git，机器调度的内容进库。**

### 1.8 判题语言

**C / C++、Python**。

### 1.9 技术约束

- **零 npm 依赖**：只用 Node 内置模块（`node:http` / `node:sqlite` / `node:child_process` / `node:test`）
- **零构建**：前端原生 JS，无打包步骤
- 无 Docker、无外部数据库、无服务端部署

---

## 2. 架构

### 2.1 进程模型

一个 Node 进程，同时承担六件事：

```
node apps/algo-plan/server/main.js
  ├─ HTTP 服务（node:http）        → 同时托管 web/ 静态页
  ├─ SQLite（node:sqlite）         → 作答流水 / 复习调度 / 题库缓存
  ├─ 题库 provider（可插拔）        → 读 learning 仓 + 本地静态题库
  ├─ git/md 读写器                  → 回写 learning 仓的进度与错题
  ├─ 判题执行器                     → spawn g++ / python3 子进程
  └─ LLM 客户端                     → fetch 调 ARK / Anthropic（可配、可关）
```

### 2.2 目录结构

```
projects/apps/algo-plan/
├── core/                 纯逻辑层（无 IO 副作用，可 Node 下直接单测）
│   ├── bank/             题库模型：Problem、md 解析/序列化、provider 接口
│   ├── scheduler/        推下一题：候选动作 + 优先级 + 配额
│   ├── review/           SM-2 间隔重复（复用 knowledge-hub 的 review.js）
│   ├── mastery/          掌握度模型与诊断
│   ├── judge-spec/       判题契约：测试用例格式、输出比对规则
│   └── llm/              提示词构造与响应解析（纯函数）
├── server/               HTTP 路由 + 静态托管 + SQLite + git/md 读写
├── judge/                判题执行器：g++ / python3 子进程管理
├── web/                  原生 JS 单页（无构建）
├── tools/                导入器：复活死脚本、导入存量题解
└── tests/                node:test 测试 + run-all.js 入口
```

### 2.3 目录归属原则

沿用既有口诀「换个项目还用得上 → ai-docs；是这次学习的产物 → learning；是跑这个 app 需要的代码 → projects」。

| 路径 | 内容 |
|---|---|
| `projects/apps/algo-plan/` | 服务端、判题器、前端、测试 |
| `learning/progress/rXX-*.md` | 轮次清单与完成状态 |
| `learning/notes/` | 知识点笔记、错题订正 |
| `learning/bank/`（新增） | 题目本体：题面、测试用例、参考解法 |

**判题契约**（`core/judge-spec/`）从长期看属于「换个项目还用得上 → ai-docs」，但第一版先留在
`projects/apps/algo-plan/`，等出现第二套判题器时再上提——避免为假想的复用提前拆仓。

### 2.4 与 learning 仓的边界

app **不硬编码** learning 仓路径。启动时通过环境变量 `ALGO_PLAN_LEARNING_ROOT`（或父仓
`repos.yaml` 解析）取得路径；**缺失时降级为「纯本地模式」**——只有 SQLite，没有笔记同步。
这样 `projects` 仓不依赖 `learning` 仓的相对位置，单独 clone 也能跑。

---

## 3. 数据模型

### 3.1 四类实体

| 实体 | 落点 | 生命周期 |
|---|---|---|
| **Problem** 题目 | `learning/bank/<track>/<id>.md`（git） | 低频 |
| **Round** 轮次 | `learning/progress/rXX-progress.md`（git） | 低频 |
| **Attempt** 作答流水 | SQLite | 高频 |
| **ReviewCard** 复习调度 | SQLite | 高频 |

### 3.2 Problem 的文件格式

markdown + frontmatter，与 `learning/notes/_meta/schema.md` 同一套思路，人和 agent 都能直接编辑：

```markdown
---
id: lc-00001
source: leetcode        # leetcode | nowcoder | jz | self | llm
title: 两数之和
difficulty: easy
topics: [哈希表, 数组]
tracks: [interview, fundamentals]
status: todo            # todo | in-progress | done
needs_fill: false        # true = 题面或测试用例缺失，待补
created: 2026-11-10
updated: 2026-11-10
---
## 题面
...

## 测试用例
| input | expect |
|---|---|
| `[2,7,11,15], 9` | `[0,1]` |

## 参考解法
```cpp
...
```
```

**测试用例用 markdown 表格而非 JSON** —— 人能读能改，agent 也能改，解析简单。

### 3.3 SQLite 表

```sql
CREATE TABLE attempts (
  id            INTEGER PRIMARY KEY,
  problem_id    TEXT NOT NULL,
  ts            TEXT NOT NULL,          -- ISO8601
  language      TEXT NOT NULL,          -- cpp | python
  code          TEXT NOT NULL,
  verdict       TEXT NOT NULL,          -- pass|wrong_answer|timeout|compile_error|runtime_error
  passed_cases  INTEGER,
  total_cases   INTEGER,
  duration_ms   INTEGER,
  mode          TEXT NOT NULL           -- solve | review | probe
);
CREATE INDEX attempts_problem ON attempts(problem_id);
CREATE INDEX attempts_ts ON attempts(ts);

CREATE TABLE review_cards (
  problem_id     TEXT PRIMARY KEY,
  easiness       REAL NOT NULL,         -- SM-2
  interval_days  INTEGER NOT NULL,
  repetitions    INTEGER NOT NULL,
  last_quality   INTEGER,
  last_at        TEXT,
  next_review_at TEXT NOT NULL,
  lapses         INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE topics (
  id         TEXT PRIMARY KEY,
  first_pass INTEGER,     -- 首次通过数
  attempts   INTEGER,     -- 总尝试数
  last_at    TEXT,
  lapses     INTEGER
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

### 3.4 稳定 ID

`id` 格式 `<平台前缀>-<编号>`：`lc-00001` / `jz-00015` / `self-0007` / `llm-<内容哈希>`。

它是 git 侧与 SQLite 侧的唯一连接键。**没有稳定 ID，双层设计立刻塌。**

**topic（知识点标签）的 key 就是标签文本本身**（如 `哈希表`、`动态规划`），不另建映射表——
中文标签直接可用，代价是标签写法必须统一（同一知识点只能有一种写法，导入器负责归一化）。

### 3.5 题库四路来源

| 路 | 来源 | 怎么进库 |
|---|---|---|
| A 静态题库 | `learning/bank/` 下的题 | 直接读 |
| B 复活死代码 | `projects/scripts/` 的 `gen-practice-data.js` / `expand-practice.js` / `split-practice-data.js` 里**已有现成题目清单**（题号、难度、标签、重复标记），但指向已删除的 `project/reading-radar/` | 改写成导入器，生成 bank 文件 |
| C 存量题解 | `learning/code-solutions/c/`、`learning/algo-c/problems/` | 解析成 Problem；**题面与用例常缺**，缺的标 `needs-fill`，由你补或让 LLM 补 |
| D LLM 现造 | 按 track + topics + 难度生成 | 生成后**落盘进 bank**（`source: llm`），不是一次性玩具 |

四路产出同一套 `Problem` 结构，混用。LLM 造的题不特殊对待——一样过判题、一样进复习。

### 3.6 题库 provider 接口

```js
// core/bank/provider.js
/**
 * @typedef {{list: (filter: object) => Promise<Problem[]>,
 *            get: (id: string) => Promise<Problem|undefined>,
 *            put: (problem: Problem) => Promise<void>}} Provider
 */
```

现在只有 `FileProvider`（读写 `learning/bank/*.md`）。将来想换成 `DbProvider`（查 `engine/db`）
就加一个实现，上层一行不用改。**接口留、实现不写。**

---

## 4. 核心算法

### 4.1 推下一题：候选动作 + 优先级

每次请求「下一题」时运行，**当下**挑一个动作：

| 优先级 | 动作 | 挑选规则 | 配额 |
|---|---|---|---|
| 1 | 到期复习 | `next_review_at <= now` 的卡片，按逾期时长倒序 | 单日上限（默认 10 题 / 20 分钟），超了让位给新题 |
| 2 | 轮次推进 | 当前 active 轮次里未完成的题 | 无上限 |
| 3 | 主动探索（非默认） | 从 bank 抽未做过的题，可按 track/topic 筛 | 用户显式触发才走 |

**复习排第一**：间隔重复的全部意义是「在忘之前回顾」。新题永远有，复习一旦被挤就永远轮不上。
但也要防复习饿死新题——所以有配额，配额用完立刻切新题。

**配额语义**：单日复习配额为「10 题 **或** 20 分钟」，**取先到者**（题数用完，或估算耗时累计
用满 20 分钟）。估算耗时按卡片上次用时与当前题难度推。配额值存在 SQLite 的 `settings` 表
（键 `review.daily_quota_questions` / `review.daily_quota_minutes`），可在「设置」页调整。

**多个 active 轮次是允许的**（不同 track 可以并行推进）。挑选时**优先最近创建的 active 轮次**，
「今日」页顶部可手动切换当前轮次；没有 active 轮次时，退回到「主动探索」分支。

**轮次内挑哪一题**：先按「掌握度最低的 topic 优先」补短板，同一 topic 内按题号顺序保连续性。

**每次只给一个动作**，并显示「这一步大约 15 分钟」（按题目难度 × 该难度历史平均用时估）。
不做「今天 5 道题」的死表。

### 4.2 复习：复用 SM-2

`apps/knowledge-hub/core/review.js` 已是逐字保留的 SM-2 纯函数（带 Node 单测），**搬过来复用**，
只加一层「判题结果 → quality」映射：

| 这次的表现 | quality | SM-2 后果 |
|---|---|---|
| 一次通过，用时低于该难度中位数 | 5 | 间隔 ×2.5 |
| 一次通过，但偏慢 | 4 | 间隔 ×2 |
| 一次通过，参照了自己的旧解 | 3 | 间隔不变 |
| 失败一次后自己改对 | 2 | **重置间隔** |
| 失败，没改对 | 1 | 重置 |
| 直接抄参考答案 | 0 | 重置 |

### 4.3 诊断：掌握度模型

每个 topic 维护一个**可解释**的分数：

```
首次通过率 = 首次尝试就过的比例          ← 反复重试通过不算掌握
遗忘因子   = 0.5 ^ (距上次练习天数 / 14)  ← 半衰期 14 天
掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
```

配套**覆盖度**（该 topic 练过几题 vs 期望题量）。两维度组合出四种状态：

| 掌握度 | 覆盖度 | 诊断 | app 的动作 |
|---|---|---|---|
| 低 | 低 | **薄弱且练得少** | 轮次里优先排这类题 |
| 低 | 高 | **练过但总错** | 提示回去看概念，而不是继续刷题 |
| 高 | 低 | **偶然会，没练透** | 安排复习巩固 |
| 高 | 高 | **掌握** | 不再主动排 |

「练过但总错」这一档很重要——它区分「题做得少」和「概念没懂」，两者处方完全不同
（前者多做题，后者先读笔记）。

### 4.4 写回 learning 仓

| 动作 | 写回什么 | 落在哪 |
|---|---|---|
| 轮次里勾选完成 | 状态 + 完成时间 + commit SHA | `progress/rXX-progress.md` 表格对应行 |
| 写错题订正 | 新建/追加一篇 | `notes/practice/<id>-订正.md`（带 frontmatter） |

**三条硬规则**：

1. **防并发**：写回前检查 learning 仓 `git status --porcelain`，不干净就**拒绝写回并明确指出哪个文件被动过**
2. **只改目标行**：读-改-写，不整文件重排
3. **绝不自动 commit** —— commit 是用户的决定，不是 app 的。写回后展示 diff，由用户决定是否提交

---

## 5. 判题契约

### 5.1 流程

每次一题一个独立临时目录，判完即删：

1. 写源文件 → 2. 编译（Python 跳过）→ 3. 逐用例执行：喂 stdin，捕 stdout + exit code + 耗时 → 4. 比对

C/C++：`g++ -std=c++17 -O2`（不加 `-Werror`——用户的题解代码不该因 warning 判错）
Python：`python3`

### 5.2 verdict 分类

| verdict | 含义 | 面板显示 |
|---|---|---|
| `pass` | 全部用例通过 | 用例数 + 耗时 |
| `wrong_answer` | 编译过了但输出不符 | **第几个用例挂的、期望 vs 实际**（截断到合理长度） |
| `timeout` | 超时 | 跑了多久后被杀 |
| `compile_error` | 编译失败 | 编译器原文 + 行号 |
| `runtime_error` | 运行时异常 / 非零退出 | stderr 原文 |

### 5.3 比对规则

默认「去首尾空白后精确匹配，忽略末尾空行」。数值题要容差时，用例行可加第三列标记
（如 `| ... | ... | tol=1e-6`），解析时读取。

### 5.4 资源限制与安全边界

- 超时默认 2s/用例
- Windows 用 `taskkill /T /F` 杀整棵进程树；POSIX 用进程组 kill
- 内存精确限制在 Windows 上做不到，靠超时兜底
- 编译产物不留在工作区，临时目录判完即删

**这不是安全沙箱。** 用户的代码以自己的用户权限、在临时目录里跑。它防的是
「跑飞、死循环、爆内存、编译出一堆垃圾」，**不防恶意代码**。要真隔离得上 Docker
或受限账号——那是另一个项目，不塞进这里。

---

## 6. LLM 接入

### 6.1 硬要求

**把 LLM 关掉，app 仍然完整可用。** 排程、判题、复习、进度一项不少。API 会挂、会限流、
账户会没钱——这些都不该让工具瘫痪。

### 6.2 场景

| 场景 | LLM 干什么 | 触发时机 |
|---|---|---|
| 讲解 | 讲「为什么这么想」，先思路后代码 | 点「讲解」 |
| 分级求助 | 方向 → 思路 → 伪码 → 代码，四档逐级解锁 | 点「求助」并选档位 |
| 批改思路 | 判定写的解题思路对不对（伪代码模式） | 提交思路而非代码 |
| 现造新题 | 按 track + topic + 难度生成题面 + 用例 + 参考解法 | 点「来一题新的」 |
| 补全缺口 | 从存量题解反推题面和测试用例 | 题目标了 `needs-fill` 时 |

### 6.3 两条纪律

1. **不主动泄题** —— 除非显式点到「直接给代码」那一档，否则讲解只到思路层
2. **产出全部可追溯** —— 生成的题落盘进 `learning/bank/`（`source: llm`），讲解记 model + prompt 摘要

### 6.4 提示词是纯函数

`core/llm/` 里：`buildPrompt(context) → string` 与 `parseResponse(text) → structured`。
提示词改动能用 Node 单测钉住，不需要联网测。

### 6.5 provider 接口

```js
/**
 * @typedef {{complete: ({system: string, user: string, temperature?: number})
 *            => Promise<string>}} LlmClient
 */
```

实现三个：`ArkClient`（火山方舟）、`AnthropicClient`、`NullClient`（关闭态）。默认从环境变量读
provider 与密钥。

### 6.6 成本护栏

单次会话请求上限 + 每日请求上限，超了直接停并提示「今天用完了」，不继续烧钱。

---

## 7. 界面与接口

### 7.1 七个页面

| 页 | 作用 |
|---|---|
| 今日 | 主界面。下一题卡片（题面摘要、所属轮次、预计耗时、按钮组）+「到期复习 N 题」+「今日进度」 |
| 作答 | 题面 + 代码框 + 语言选择 + 提交 + 结果面板（verdict、失败用例的期望 vs 实际、编译错误原文） |
| 复习 | 到期卡片队列，评分用直觉文案（「完全忘了 / 想很久 / 有点印象 / 秒答」），背后映射到 SM-2 quality |
| 轮次 | 现有 `rXX-progress.md` 的可视化：清单、勾选、进度条 |
| 诊断 | 掌握度雷达、弱项榜、每日题量曲线、知识点覆盖 |
| 题库 | 题目列表与筛选、`needs-fill` 标记、LLM 造题入口 |
| 设置 | LLM provider 与开关、判题超时与容差、每日配额、learning 仓路径、导出导入 |

**代码编辑器用 `<textarea>` + 行号 gutter**，不引 Monaco/CodeMirror——引了就得 npm 装或
vendored 一份，违背零依赖。第一版够用：Tab 键缩进、等宽字体、字号可调。
智能补全/语法高亮以后再说。

### 7.2 API 契约

```
GET   /api/next                     → 下一个动作（题面摘要、预计耗时、复习队列长度）
GET   /api/problem/:id              → 题面全文 + 用例
POST  /api/attempt                  → 提交代码 → 判题 → verdict + attempt 记录
POST  /api/review/:id/grade         → {quality} → 更新 SM-2
GET   /api/rounds                   → 轮次清单（解析自 learning/progress/*.md）
PATCH /api/rounds/:id/items/:itemId → 勾选完成 → 写回 md（返回 diff）
GET   /api/insights                 → 掌握度 / 弱项 / 曲线
GET   /api/bank?track=&topic=...    → 题库
POST  /api/bank/llm-generate        → LLM 造题 → 落盘
GET/PUT /api/settings
```

**一条防作弊规则**：题面接口默认只返回**前 1-2 个样例用例 + 用例总数**，不给全部用例、
不给参考答案。「看全部用例」是显式按钮。这样没法把答案硬编码进提交——跟真实 OJ 一个样。

---

## 8. 学习仓同步契约

- **读**：`progress/*.md` 的现有表格格式（基本信息表 + 卡片清单表）、`bank/**/*.md` 的
  frontmatter + 正文——**格式不改**，app 只是能读能写它
- **读的时候要容错**：`rXX-progress.md` 的表头列名是中文且可能缺列（如「完成时间」写成「完成日期」）。
  解析器按**列名关键词**匹配而非列序，缺列按空值处理，解析不了的行跳过并计入「解析告警」，
  由 UI 展示告警数——绝不因为一行看不懂就整体报错
- **写**：只改目标行不动其它行；写前查 `git status --porcelain`，不干净就拒绝并指出是哪个文件
  被动过；写后返回 diff；**绝不自动 commit**

---

## 9. 测试策略

| 层 | 测什么 | 怎么测 |
|---|---|---|
| `core/` 纯函数 | 排程（复习优先/配额/轮次挑题）、掌握度衰减、题库 md ↔ Problem 往返、提示词构造与响应解析、输出比对规则 | `node:test`，零依赖 |
| 判题器 | verdict 五分类、超时能杀掉、输出比对（空白/容差） | fixture 题目，真实 g++/python3 |
| 端到端 | `/api/next` → `/api/attempt` → `PATCH` 轮次 → 断言 md 改对了 | 起服务打接口 |
| 同步契约 | 读 → 写 → 再读等价；脏工作区时拒绝写 | learning 仓的临时副本 |

沿用 `apps/*/tests/run-all.js` 入口习惯——一个命令跑全部。

---

## 10. 分期

| 阶段 | 交付 | 说明 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | 地基 |
| M2 题库 | 复活三个死脚本 + 存量题解导入（**不含 LLM 造题**，那需要 M6 的 provider） | 没题就没得练，**必须排在 M3 前** |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | 核心体验 |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | **第一个能天天用的版本** |
| M5 诊断 | 掌握度模型 + 诊断页 | 看得见才有动力 |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | 锦上添花，可后置 |

M4 是「愿意每天打开」的临界点。前三期做完之前不加新花样。

**实施计划以里程碑为单位逐个生成与执行**：M1–M4 是主线（M4 结束即达成「可天天用」），
M5–M6 是增强，可延后。M2 必须先于 M3（没题没法判）。

---

## 11. 明确不做（YAGNI）

- 多用户、账号、服务端部署 —— 这是本机工具，不是产品
- 云同步、协作
- 任何 npm 依赖（含测试框架，用内置 `node:test`）
- 移动端适配 —— 本地浏览器打开，不追求手机可用
- 智能补全 / 语法高亮 —— 第一版 textarea 够用
- 安全沙箱 —— 判题只防跑飞，不防恶意代码
- `engine/db` 集成 —— 只留 provider 接口，不写实现

---

## 12. 风险与已知代价

| 风险 | 缓解 |
|---|---|
| 判题不是安全沙箱 | 已在 §5.4 明示；临时目录隔离 + 超时杀进程树 |
| 题库导入后 `needs-fill` 占比高 | M2 先只导入用例完备的；LLM 补全（M6）按需触发 |
| learning 仓跨会话并发写入 | 写回前查工作区，脏就拒绝（§4.4） |
| SQLite 与 git 侧状态漂移 | 题目 ID 是唯一连接键；轮次完成状态以 git 侧为准，SQLite 只存调度态 |
| 零依赖导致判题/前端能力受限 | 接受限制；先用着，等真的卡住再评估 |
| LLM 造题质量不稳定 | 生成的题照样过真实判题，编不过的题自己暴露出来 |

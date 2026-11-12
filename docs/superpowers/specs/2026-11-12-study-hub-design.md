# 学习中枢 App（study-hub）—— 设计文档

> 日期：2026-11-12
> 状态：设计已确认，待写实施计划
> 归属仓：`projects`（工程产物） + `learning`（学习数据）
> 前身：`projects/apps/algo-plan`（算法能力提升计划 App，M1–M6 已完成），本轮改名并扩为三轨合一

---

## 0. 一句话

一个跑在本机的 Web 应用，把「数据库、算法、AI」三条学习轨统一到一套引擎里：
一个「学习单元」模型贯穿三轨，会话按**次数**而非天数编排，LLM 补内容缺口，**真实编译执行**做质检员，
进度与错题写回 learning 仓进 git。

---

## 1. 需求与约束（已确认的决策）

### 1.1 三轨合一，而非三个应用

算法、数据库、AI 三个方向本质是同一件事：**知识点 + 练习 + 判题/自测 + 复习 + 弱项诊断**。
因此不做「三个 app + 一个门户」，而是**一个应用、三条轨道、一套引擎**。
`algo-plan` 作为算法轨的代码基座整体迁入，抽象泛化。

### 1.2 检验方式：讲解 + 自测双层

| 轨 | 现状 | 本轮补齐 |
|---|---|---|
| 算法 | `learning/bank/` 689 题**全是空骨架**（687 个 `needs_fill: true`）；真正填满的只有 `algo-plan/bank/` 的 51 道 Codeforces | 题面 + 测试用例 + 参考解法 + 负例 |
| 数据库 | grokking 14 张 Python 卡（`main.py` 全部落盘，约 2870 行）+ `scaffold/db` 51 个 C 目录（内核实现级）+ notes 29 篇 + 面试题 105KB | 断言脚本 + 讲解正文 |
| AI | grokking 14 张 numpy 卡（约 2490 行，MLP/CNN/RNN/SVM 全手写） | 断言脚本 + **讲解正文**（现有 `NOTES.md` 仅提纲级，AI 轨缺的是文档层而非代码层） |

三轨的缺口是**同一个形状**：内容都在，可验证层不在。因此统一引擎只需统一「单元 + 断言」这一层。

**关键判断**：DB/AI 的"检验"本来就是断言而非输出比对（"这个索引有没有走"、"梯度下降收敛了吗"），
硬套 stdout 比对会失真。断言写在**独立文件**里，不动 `main.py` 原文，教学资产零污染。

### 1.3 跨轨统一编排

首页只有一个"这次该学什么"，可以给出「今天 DB 一张卡 + 算法一道题」这样的**混合计划**；
掌握度与复习跨轨统一统计，三轨在诊断页可横向比较。
若各轨各排各的，统一的就只剩外壳——跨轨混合是别处得不到的价值。

### 1.4 按次数，不按天数

用户不是每天学习，是「点开了就开始学」。因此：

- **没有 `today` 视图，只有 `session`（会话）**。会话长度按**单元数**计（默认 3，可调 1–10）。
- 不做日历打卡、不做"连续 N 天"这类指标。
- 会话队列落库，「点开 → 学两个 → 关掉 → 三天后回来接着学」原生支持。
- SM-2 复习到期采用**双触发**（见 §4.3）。

### 1.5 内容供给：LLM 生成 + 执行器反向校验 + 人工抽检

不用相信 LLM，用执行器验它：

1. **生成**：LLM 依缺口产出题面/用例/解法/负例（算法）、断言脚本 + 讲解正文（DB/AI）。
2. **校验**：真实编译执行。算法题跑参考解法须全 AC、跑负例须被拒；DB/AI 跑断言脚本须 `exit 0`，
   并做**变异测试**（改坏被测逻辑，断言必须失败）证明断言有效。
3. **入库**：通过则 `draft → verified`；不通过进 `rejected` 队列。人工按每轨 10% 抽检。

### 1.6 载体与落位

| 项 | 值 |
|---|---|
| 载体 | 本地 Web 应用（浏览器访问本机服务） |
| 落位 | `projects/apps/study-hub/`（由 `git mv apps/algo-plan` 迁入，git 记为重命名，历史可追） |
| 端口 | `5173` |
| 判题运行环境 | 系统 `python3` + `g++`；启动时检测 numpy，缺失则 DB/AI 轨标"环境缺失"并跳过，不阻塞算法轨 |
| 环境变量 | `STUDY_HUB_LEARNING_ROOT`（替代 `ALGO_PLAN_LEARNING_ROOT`）、`STUDY_HUB_LOCAL_BANK`（替代 `ALGO_PLAN_LOCAL_BANK`）、`PORT`、`ARK_API_KEY` / `ANTHROPIC_API_KEY` 等 |

### 1.7 技术约束

- **零 npm 依赖**：只用 Node 内置模块（`node:http` / `node:sqlite` / `node:child_process` / `node:test` / `fetch`）
- **零构建**：前端原生 JS，无打包步骤，不引入前端框架
- **零第三方图表库**：`charts.js` 手绘 SVG 纯函数层沿用
- 无 Docker、无外部数据库、无服务端部署

---

## 2. 架构

### 2.1 进程模型

一个 Node 进程，承担八件事：

```
node apps/study-hub/server/main.js
  ├─ HTTP 服务（node:http）        → 同时托管 web/ 静态页
  ├─ SQLite（node:sqlite）         → 作答流水 / 复习调度 / 会话 / 队列 / 掌握度
  ├─ 单元 provider（可插拔）        → 三类来源解析成同一个 Unit
  ├─ 断言校验器                     → output / exit / contains / file 四种断言
  ├─ 执行器（node:child_process）   → spawn python3 / g++ / c
  ├─ git/md 读写器                  → 回写 learning 仓的进度与勾选
  ├─ LLM 客户端                     → fetch 调 ARK / Anthropic（可配、可关）
  └─ 供给流水线（离线批处理）        → 生成 → 反向校验 → 入库（由 tools/ 触发）
```

### 2.2 单元模型：唯一的学习单元

三轨共用一个 `Unit` 类型。下游（scheduler / judge / mastery / LLM / UI）**完全不感知来源轨道**。
这是本设计的核心抽象——它让跨轨统计、跨轨排程、跨轨复习成为自然结果，而不是三套并行实现。

```js
Unit {
  id          string        // 稳定 ID，唯一连接键，如 "db:mvcc" / "algo:lc-00007"
  track       "algorithm" | "database" | "ai"
  kind        "problem" | "card"     // problem=要写答案；card=读+跑+断言
  title       string
  statement   string        // 讲解正文（题面 或 README+NOTES）
  entry       Entry
  asserts     Assert[]
  topics      string[]
  difficulty  "easy" | "medium" | "hard"
  source      "leetcode" | "nowcoder" | "self" | "grokking" | "scaffold" | "generated"
  status      "todo" | "draft" | "verified" | "rejected"
  reviewed    boolean       // 人工抽检结果
  reviewed_at string
}

Entry {
  demo      ?string   // 可运行演示入口（相对 learning 仓根），可选
  reference ?string   // 参考解法入口（供给流水线校验用），可选
  graded    "user" | "script"   // 判题入口来自用户提交 还是 单元自带脚本
  script    ?string   // graded === "script" 时必填
}
```

`kind` 只影响 UI 呈现与"作答"的含义（problem 要用户写代码；card 是读讲解 + 跑 demo + 过断言），
**不影响判题路径**。

### 2.3 三类内容源与 loader

| loader | 源 | 物理位置 | 映射方式 |
|---|---|---|---|
| **A** | 算法题 | `learning/bank/{track}/lc-*.md`（689） | 读既有三段式（题面 / 测试用例表 / 参考解法），**存量文件原地不动**（护住 git 历史） |
| **B** | DB/AI 卡 | `learning/scaffold/grokking/<card>/`（**28 张 Python 卡** = db 14 + ml 14） | 以卡为单位：讲解 = `README.md` + `NOTES.md`，demo = `main.py`，脚本 = 生成的 `<stem>.assert.py` |
| **C** | 新生成单元 | `learning/units/{track}/*.md`（新目录） | 统一格式 md + 同目录断言脚本；**新内容的唯一落点** |

loader A/B/C 产出同一个 `Unit` 对象。生成的新算法题也落 `learning/units/algorithm/`，
存量 `learning/bank/` 原地读——**不做 689 个文件的搬迁**。

**不在本轮范围**：`learning/scaffold/db/` 的 51 个 C 目录（btree / lsm / wal / mvcc / 2pc / hnsw / ivf 等
数据库内核实现）是三轨里唯一"实现级"的深度资产。执行器已支持 `g++`，接入成本不高，
但断言脚本要用 C 编写、变异测试的手法也不同，**列为本轮之后的扩展**，不纳入 P0–P5。

**ID 规范**：`Unit.id` 形如 `<trackCode>:<stem>`，全局唯一。
算法轨由存量 frontmatter 的 `lc-00007` **在内存层规范化为** `algo:lc-00007`（存量文件里的 `id` 字段不改）；
DB/AI 轨用 `db:mvcc`、`ai:cnn`。文件名为 `<stem>.md`，断言脚本为同目录的 `<stem>.assert.py`。
`Unit.track` 字段与 ID 前缀冗余但都保留——字段供代码直接读取，前缀供人眼在日志与 git 历史里辨认归属。

### 2.4 目录结构

```
projects/apps/study-hub/
├── core/
│   ├── unit/          Unit 模型、loader A/B/C、断言规格
│   ├── track/         轨道定义、权重、会话配额配置
│   ├── scheduler/     会话编排：跨轨配额 → 单元队列
│   ├── review/        SM-2 双触发（日期 或 次数）
│   ├── mastery/       跨轨统一掌握度（单元级 / 知识点级 / 轨道级）
│   ├── judge-spec/    判题契约（沿用 + 扩断言类型）
│   ├── llm/           沿用 M6 + 扩「内容供给」场景与轨道模板
│   └── sync/          learning 仓写回（沿用）
├── server/            路由 + SQLite + 装配
├── judge/             执行器 + 沙箱 + 断言校验
├── web/               原生 JS SPA（沿用 ui.js / charts.js 的界面层次）
├── tools/             供给流水线 CLI：plan / generate / verify / review / report
└── tests/             node:test，run-all.js 一键跑
```

`git mv` 之后，原有 `core/bank|mastery|review|scheduler|sync|judge-spec|llm`、`server/*`、
`judge/*`、`web/*`、`tools/*`、`tests/*` **原地继承**，只做增量改造。

### 2.5 目录归属原则

沿用既有口诀「换个项目还用得上 → ai-docs；是这次学习的产物 → learning；是跑这个 app 需要的代码 → projects」。

| 路径 | 内容 |
|---|---|
| `projects/apps/study-hub/` | 服务端、执行器、前端、测试、供给流水线工具 |
| `learning/units/<track>/*.md` | 统一单元文件：讲解 + 入口 + 断言集（新内容的唯一落点） |
| `learning/units/<track>/*.assert.py` | 断言脚本，与单元 md 同目录成对 |
| `learning/bank/` | 存量算法题（原地不动，loader A 读取） |
| `learning/scaffold/` | 教学 demo 源码（`main.py` 等，不被本 app 修改） |
| `learning/progress/rXX-*.md` | 轮次清单与勾选状态（沿用现有格式） |
| `learning/notes/` | 笔记、错题订正 |

---

## 3. 数据模型

### 3.1 `Assert` —— 四种断言，一种判题路径

```js
Assert =
  | { type: "output",   input?, expect, cmp }   // stdout 比对，cmp: exact|trim|json|lines
  | { type: "exit",     expect: 0 }             // 进程退出码
  | { type: "contains", text }                  // stdout 包含
  | { type: "file",     path, expect }          // 产物文件内容
```

**判题器只有一条路径**：`跑入口进程 → 收集 stdout / exit code / 产物文件 → 逐条校验断言集`。

| 单元种类 | 判题入口（graded） | 断言集来源 |
|---|---|---|
| `kind: problem` | `"user"` —— 用户提交的代码 | 测试用例表转成 `output` 型断言 |
| `kind: card` | `"script"` —— 单元自带断言脚本 `<id>.assert.py` | `exit:0` + 若干 `contains`（校验 demo 的关键结论出现在输出里） |

断言脚本内部 `import` 被测模块并跑断言，失败则非零退出并打印原因。
`exit` 型断言在这里是**契约**（脚本必须失败时报错），不是把断言逻辑塞进断言集里。

### 3.2 统一单元文件格式（loader C）

```markdown
---
id: db:mvcc
track: database
kind: card
title: MVCC：版本链与 ReadView
difficulty: medium
topics: [事务, 并发]
source: grokking
language: python
demo: scaffold/grokking/mvcc/main.py
graded: script
script: units/database/mvcc.assert.py
status: verified
reviewed: true
reviewed_at: 2026-11-20
---

## 讲解

（Markdown 正文，由 LLM 基于 main.py + README.md + NOTES.md 生成初稿，人工抽检）

## 关联

- 轮次：R37 Grokking 数据库
- 上游单元：`db:transaction`
- 工程对照：`engineering/src/db/sql/`
```

断言脚本与单元 md **同目录成对**（`units/database/mvcc.md` + `units/database/mvcc.assert.py`），
这样在 git 里一眼能看出哪个断言配哪个单元。

### 3.3 SQLite 表

| 表 | 相对 algo-plan 的变化 |
|---|---|
| `attempts` | `problem_id` → **`unit_id`**；新增 `track`、`assert_total`、`assert_passed` |
| `review_cards` | 新增 **`units_since`**（次数触发计数）；`problem_id` → `unit_id` |
| `topics` | 新增 `track`；掌握度按 `(track, topic)` 聚合 |
| `settings` | 不变；新增会话长度、轨权重、SM-2 次数阈值 K 等配置键 |
| `units`（新） | 单元索引缓存：`id / track / kind / title / path / status / topics / difficulty / updated` —— 跨轨搜索与统计靠它，不每次扫盘 |
| `sessions`（新） | `id / started_at / ended_at / planned_count / done_count / tracks` |
| `session_queue`（新） | `session_id / unit_id / seq / state` —— **队列落库，中断不丢** |
| `mastery`（新） | `scope("unit"|"topic"|"track") / scope_id / level / updated_at` |

### 3.4 双层落点原则（沿用，不变）

| 内容 | 落点 | 理由 |
|---|---|---|
| 单元内容、轮次清单、知识点状态、错题订正与心得 | **learning 仓（git）** | 低频、人要看、要 review |
| 每次作答流水、耗时、判题结果、SM-2 调度状态、会话与队列、掌握度派生 | **app 的 SQLite** | 高频、机器读写、无需 review |
| 两侧连接 | **稳定单元 ID 互链**（`Unit.id` 是唯一连接键） | — |

一句话：**人读的内容进 git，机器调度的内容进库。**

---

## 4. 核心算法

### 4.1 跨轨配额分配（最大余数法）

输入：会话长度 `N`（默认 3）、每轨权重 `w`（默认 algorithm 0.4 / database 0.3 / ai 0.3）、
每轨候选池大小 `C`、每轨复习到期数 `due`。

**候选池 `C[t]` 的定义**：该轨当前**可学**的单元数 = 未完成且 `status` 为 `verified` 的单元
+ 已到期待复习的单元（同一单元不重复计数）。
`draft` / `rejected` 状态的单元不进候选池——供给流水线没验过的内容不拿去上课。

```
1. 需求度   demand[t]  = 1 + min(1, due[t] / 5)          复习积压多的轨加权
2. 有效权重 w'[t]      = w[t] × demand[t]
3. 配额     n[t]       = floor(N × w'[t] / Σw')           最大余数法补齐到 Σn = N
4. 回收     若 C[t] < n[t]，多余配额按 w' 比例分给仍有候选的轨
5. 兜底     若 ΣC = 0 → 返回「需要新题」信号（转 §6 供给流水线）
```

最大余数法（Hare quota）**确定性、可单测**，且不会出现"某轨 0 个"的空计划。

### 4.2 队列成形

轨内按优先级排（沿用 `next-action.js` 的思路，参数化轨维度）：

```
到期复习 > 未完成的当前轮次单元 > 轮次里的下一个 > 新单元
```

再跨轨**交错**成一条队列（round-robin），避免连续三个都是数据库。
交错时权重高的轨可以先出，但不超过自己配额的两倍连续。

### 4.3 SM-2 双触发（日期 或 次数）

`review_cards` 加一列 `units_since`。**任何轨**完成一个单元，所有卡 `units_since += 1`。

```
到期 ⟺ next_review_at <= now   （日期通道）
     ∨ units_since >= K         （次数通道，K 默认 5，可配置）
```

触发后统一走 SM-2 更新（`easiness` / `interval_days` / `lapses`），`units_since` 归零。

**边界说明**：`interval_days` 的增长仍按**日期**计算（间隔重复的本质是时间间隔），
次数通道只决定"**什么时候提醒**"，不改变间隔算法。否则会出现"狂学一天把间隔拉成 30 天"的荒谬结果。

### 4.4 掌握度（三层聚合）

| 层级 | 键 | 用途 |
|---|---|---|
| 单元级 | `unit_id` | 这个题/这张卡我掌握到什么程度 |
| 知识点级 | `(track, topic)` | 「事务」这个知识点在数据库轨的掌握度 |
| 轨道级 | `track` | 诊断页三轨对比：算法 62% / 数据库 41% / AI 18% |

单元级掌握度的更新因子：断言通过率、是否一次通过、耗时、距上次练习的间隔。
**三轨用同一套公式**——算法题与 DB 卡的判题结果都归一成"通过率"，所以可比。

---

## 5. 判题契约

### 5.1 单路径

```
断言集 → 选入口（用户提交 / 单元脚本）→ 沙箱执行 → 收集 stdout/exit/产物 → 逐条校验 → verdict
```

`kind: problem` 与 `kind: card` 走**同一条代码路径**，差异只在「入口从哪来」与「断言集怎么构造」。

### 5.2 verdict 分类

沿用 `judge/runner.js` 的五类 verdict（不新增、不改名）：

| verdict | 含义 |
|---|---|
| `pass` | 全部断言通过 |
| `wrong_answer` | 跑起来了，但断言未过（output 不匹配 / exit 非 0 / 产物不符） |
| `runtime_error` | 崩溃 / 越界 / 非零异常退出 |
| `timeout` | 超时被杀 |
| `compile_error` | 编译或语法错（C/C++ 走 `g++`；Python 走语法检查） |

`kind: card` 的断言脚本跑失败时归到 `runtime_error` 或 `wrong_answer`，与 `kind: problem` 共用同一套判定。

### 5.3 沙箱与资源限制

沿用 `judge/sandbox.js`：临时目录、输入探测、超时上限、杀进程树。
新增 `assert` 模式下对**产物文件**的读取也要走沙箱目录，禁止越出临时目录。

---

## 6. 内容供给流水线

### 6.1 三阶段

```
生成(LLM) → 校验(执行器反向) → 入库
```

| 轨 | 缺口 | LLM 产出 | 落点 |
|---|---|---|---|
| 算法 | 689 题的题面 + 用例 + 参考解法 + 负例 | 依据 `url` + `title` + `topics` 生成 | `learning/units/algorithm/` |
| DB | 28 张卡的断言脚本 + 讲解正文 | 依据 `main.py` + `README.md` + `NOTES.md` 生成 | `learning/units/database/` |
| AI | 14 张卡的断言脚本 + 讲解正文（NOTES 太薄，必须补） | 同上 | `learning/units/ai/` |

产物先落 `status: draft`，同目录落断言脚本。

### 6.2 反向校验：执行器做质检员

| 轨 | 校验动作 | 通过条件 |
|---|---|---|
| 算法 | 跑参考解法 × 全部用例 | 全部 AC |
| 算法 | 跑生成的负例（错解） | 必须被拒绝（防止"全绿"的假判题器） |
| DB/AI | 跑断言脚本 | `exit 0` |
| DB/AI | **变异测试**：改坏被测逻辑（改一个条件 / 删一个分支） | 断言必须失败 |

变异测试不可省：`exit 0` 只证明"没崩"，一个 `assert True` 也能过；变异测试才证明断言有效。

### 6.3 工具链

```bash
node tools/supply.js plan                 # 缺口清单：哪些单元 needs_fill / 缺断言 / 缺讲解
node tools/supply.js generate --track db --limit 20
node tools/supply.js verify --all          # 执行器校验：draft → verified / rejected
node tools/supply.js review --sample 5     # 人工抽检（渲染可读页，人点通过 / 打回）
node tools/supply.js report --track ai     # 还欠着什么
```

`verify` 跑**真实编译执行**，与判题器同一套执行器与沙箱——供给侧与消费侧共用一个可信判读机制。

### 6.4 人工抽检

`tools/supply.js review --sample 5` 随机抽 5 个 verified 单元，渲染成可读页面
（含题面、断言、执行记录），人点「通过 / 打回」，结果写回 frontmatter `reviewed` + `reviewed_at`。

比例：**每轨 10%**。人工是最后一道闸，不是主力。

### 6.5 降级

供给流水线是**离线批处理**，与会话内 LLM 共用同一客户端与成本护栏。
**LLM 关掉时**：供给流水线不可用，但 app 照常可用——已有 verified 单元照学照判。
无密钥也能跑全部测试（注入假客户端）。

---

## 7. LLM 接入

### 7.1 场景

| # | 场景 | 在线/离线 | 三轨差异 |
|---|---|---|---|
| 1 | 讲这个单元 | 在线 | 算法讲"这题的思路"；DB/AI 讲"这个概念的原理与工程含义" |
| 2 | 分级求助 | 在线 | 提示层级逐级放开：思路 → 关键点 → 完整解法 |
| 3 | 批改思路 / 笔记 | 在线 | 三轨共用 |
| 4 | 现造新题 | 在线 | 三轨共用 |
| 5 | 深挖概念 | 在线 | **新增**，主要为 DB/AI 卡服务 |
| 6 | 生成题面 / 用例 / 解法 | 离线 | 算法轨 689 题 |
| 7 | 生成断言脚本 | 离线 | DB/AI 28 张卡 |
| 8 | 生成讲解正文 | 离线 | AI 轨（现有 NOTES 太薄） |

### 7.2 轨道模板是数据，不是代码

不做 `if (track === 'db')` 的硬分支。`core/llm/prompts.js` 维护「按轨的模板表」，
组装时按 `unit.track` 取模板 + 拼单元上下文（题面、断言、知识点、掌握度）。
模板是纯数据，可直接单测；新增一条轨只要加一条模板。

### 7.3 纪律（沿用 M6）

- 密钥只从环境变量 / `.env` 读，**已存在的环境变量优先，`.env` 不覆盖**
- 成本护栏：单次会话请求上限（20）、每日请求上限（100）
- LLM 关掉后 app 照常可用
- 提示词是纯函数（`core/llm/prompts.js`），响应解析可单测

---

## 8. 界面与接口

### 8.1 页面

沿用 algo-plan 的**单一暗色主题**与 `web/ui.js` 的四层信息层次
（页头 `.page-head` / 主卡 `.panel.hero` / 普通卡 `.panel` / 静默卡 `.panel.quiet`），
以及 `tests/ui-hierarchy.test.js` 的回归闸门——新页面同样要过。

| 页面 | 形态 | 来源 |
|---|---|---|
| `#/` | **会话队列首页**：当前会话的单元清单 + 进度 + 继续 | 新建 |
| `#/unit/:id` | **单元学习页**：左讲解 / 右操作 | 由 algo-plan 的 answer 页改造 |
| `#/diagnose` | **诊断页**：A 主视图 + B 雷达 tab + C 热力图 tab | 扩展 algo-plan 的 diagnose 页 |
| `#/library` | 单元库：按轨浏览 / 搜索全部单元 | 新建（吸收 rounds 页的一部分） |
| `#/supply` | 供给状态 + 人工抽检入口（薄页，重活在 CLI） | 新建 |
| `#/llm` | LLM 工作台 | 沿用 `web/llm.js` |
| `#/settings` | 配额、轨权重、LLM 开关、环境自检 | 新建 |

### 8.2 三个已定版式

**首页（会话队列式）**：当前会话清单透明可预期——已完成的打勾、当前的标黄、未开始的置灰，
下方三轨掌握度小块作背景；顶部提示"上次还有 2 个没做完"。

**单元学习页（左读右做，两栏）**：左栏讲解（Markdown 渲染 + 「问 LLM」入口），
右栏操作区（demo 输出 / 代码编辑区 + 断言结果 + 重新运行 / 完成本单元）。
算法题在同一框架下把右栏换成代码编辑区与判题结果。

**诊断页**：主视图 A = 三轨并列条形图 + 点轨下钻知识点明细；
B = 六轴雷达（算法/数据库/AI/C/C++/Python/SQL）+ 弱项清单与建议；
C = 会话热力图（横轴会话序号、纵轴三轨、格子为当次结果）。

### 8.3 API 契约（新增部分）

```
POST   /api/session/start          { n }        → 建会话，排队列
GET    /api/session                 → 当前会话（含未完成提示）
GET    /api/session/next            → 下一个单元
POST   /api/session/pause
POST   /api/session/submit          { unitId, code? }  → 跑断言、记账、出队
GET    /api/units?track=&q=         → 单元库查询
GET    /api/units/:id
GET    /api/diagnose?view=mastery|radar|heatmap
GET    /api/supply/status?track=
POST   /api/supply/review/:id       { passed }   → 人工抽检结果写回
```

沿用 algo-plan 既有路由（`/api/today` → `/api/session`、`/api/problems` → `/api/units`、
`/api/rounds`、`/api/insights`、`/api/llm/*`）。

---

## 9. 测试策略

零依赖，`node:test`，一个命令跑全部。

| 层 | 覆盖 |
|---|---|
| `core/` 纯函数 | loader A/B/C 解析、断言规格、**配额算法**（最大余数法；边界：候选池不足 / 全空 / 单轨）、SM-2 双触发、掌握度公式、提示词组装与响应解析 |
| `judge/` 集成 | fixtures 跑真实编译执行；ML 卡相关 fixture 在无 numpy 时**明确 skip 并给出原因**（不静默跳过） |
| `server/` API | 路由、错误码、会话生命周期 |
| `web/` UI 层次 | 沿用 `tests/ui-hierarchy.test.js`，新页面同样受约束 |
| 供给流水线端到端 | 假 LLM 产出 → 执行器校验 → 覆盖 `draft → verified` 与 `draft → rejected` 两条路径 |
| 降级路径 | LLM 关闭、无密钥、无 numpy 三种情况各一条 |

**全程不联网**：LLM 全部注入假客户端（沿用 M6 做法）。

---

## 10. 分期

| 期 | 内容 | 交付后能用吗 |
|---|---|---|
| **P0** | `git mv` 改名 study-hub；Unit 模型 + loader A/B/C；轮次解析复用 | 现有算法功能不回归 |
| **P1** | 会话队列：跨轨配额 + 队列持久化 + 首页（队列式） | 首页能列队列、可开始 |
| **P2** | 三轨内容接入（loader B）+ 断言校验器 + 单元学习页（左读右做） | DB/AI 卡能读能跑能判 |
| **P3** | 诊断页三视图 + 跨轨掌握度 | 三轨能横比 |
| **P4** | 供给流水线：LLM 生成 + 反向校验 + 变异测试 + 人工抽检 | 内容缺口能自动补 |
| **P5** | 算法轨 689 题批量生成与校验 | 算法题库填满 |

**降级路径**（防 P1 风险）：跨轨配额若排期紧张，先上"按权重静态分配 + 统一队列视图"，
再叠加需求度加权。P1 的核心产出（队列持久化 + 会话生命周期）不依赖这一步。

**实施计划的粒度**：本设计是整体蓝图，实施计划**按期分批写**。
第一批为 **P0–P2**（改名与单元模型 → 会话队列与首页 → 三轨接入与单元页），
这批做完 app 就已经是一个可用的三轨学习中枢；P3–P5 在其后按批次推进。
每批一个独立计划，各自可验证、可交付。

---

## 11. 明确不做（YAGNI）

- 不做移动端 / 小程序端（`knowledge-hub`、`programmer-workbench` 已是小程序，不扩）
- 不做账号体系、多用户、云同步
- 不做社交（排行、评论、分享）
- 不做通用 CMS / 富文本编辑器
- **不引入前端框架与构建**（保持零构建）
- 不引入第三方图表库（`charts.js` 手绘 SVG）
- 不手工填那 689 题（靠 §6 流水线 + 抽检）
- 不做 IDE 级代码补全 / 在线调试器
- **不引入向量检索层**（RAG 检索是以后的事；algo-plan 原设计亦明确不用 `engine/db`）

---

## 12. 风险与已知代价

1. **供给质量**：LLM 生成的题面与断言不可能 100% 正确，靠执行器反向校验 + 10% 人工抽检兜底，
   残留错误会存在。变异测试能挡住"假通过"，但挡不住"断言写对了但考的不是重点"。
2. **P1 调度器重构**是本轮最大技术风险点（`core/scheduler/next-action.js` 542 行要参数化跨轨），
   靠 §10 的降级路径兜。
3. **成本**：689 题 + 28 张卡的生成要真实调 LLM，有护栏但仍是一笔开销。
4. **环境依赖**：DB/AI 卡依赖 numpy；缺 numpy 时该轨不可用（不阻塞算法轨）。
5. **端口**：5173 若被上一版服务占着，重启前需手动关掉旧进程。
6. **历史包袱**：`learning/notes/` 存在重复目录（`notes/DB/` 与顶层同名目录内容相同）、
   `notes/vectordb/vectordb.md` 几乎为空、`interview/database/SQL.md` 是 0 字节空文件——
   本轮不清理，但供给流水线遇到这些会标"问题条目"而非静默通过。

---

## 附录 A：已确认决策清单

| # | 决策 | 结论 |
|---|---|---|
| 1 | 三轨关系 | 三轨合一，一个应用共用一套引擎（而非门户聚合） |
| 2 | DB/AI 的检验方式 | 讲解 + 自测双层，断言写在独立文件不动 `main.py` |
| 3 | 排程粒度 | 全局跨轨编排，首页给混合计划 |
| 4 | 计量单位 | 按次数，不按天数；无 `today` 视图，只有 `session` |
| 5 | 会话定义 | 会话 = 固定 N 个单元（默认 3，可调 1–10），中断不丢 |
| 6 | SM-2 到期 | **丙**：日期或次数先到者触发；`interval_days` 仍按日期算 |
| 7 | 内容供给 | LLM 生成 + 执行器反向校验 + 人工抽检；AI 轨讲解也走 LLM |
| 8 | 落位与命名 | `git mv` → `projects/apps/study-hub/`；端口 5173 |
| 9 | 运行环境 | 系统 `python3` + `g++`，启动时检测 numpy，缺失则跳过 DB/AI 轨 |
| 10 | 单元抽象 | 统一为「讲解 + 入口 + 断言集」，判题器单路径 |
| 11 | 首页版式 | 会话队列式 |
| 12 | 单元页版式 | 左读右做（两栏） |
| 13 | 诊断页版式 | A 三轨并列下钻（主视图）+ B 雷达 + C 会话热力图 |
| 14 | verdict 集合 | 沿用 `judge/runner.js` 的五类（`pass` / `wrong_answer` / `runtime_error` / `timeout` / `compile_error`），不新增 |
| 15 | 本轮内容范围 | DB/AI 轨 = grokking 28 张 Python 卡；`scaffold/db` 的 51 个 C 目录**不在本轮**，留作扩展 |

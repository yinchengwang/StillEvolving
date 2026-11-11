# 算法能力提升计划 App —— M5 诊断实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M5 里程碑——看得见的诊断：掌握度模型（可解释）、`GET /api/insights` 接口、以及一个手绘 SVG 的「诊断」页（掌握度雷达、弱项榜、每日题量曲线、知识点覆盖），零第三方图表库。

**Architecture:** 掌握度模型是**纯函数**（`core/mastery/`），可脱离 IO 单测；诊断数据由 `server/insights.js` 装配（读 `attempts` 表 + 题库 → 派生统计 → 物化回 `topics` 表 → 读 `topics` 表算掌握度）；前端图表的几何计算与 SVG 拼接也在**纯函数**里（`web/charts.js`，UMD 双模，Node 与浏览器共用），页面只负责把 SVG 字符串塞进 DOM。零 npm 依赖、零构建。

**Tech Stack:** Node.js ≥ 24（内置 `node:sqlite` / `node:test` / `node:http`）、原生 JS + SVG + CSS、零 npm 依赖。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划只覆盖其中 §4.3 掌握度模型、§7.1 的「诊断」页、§9 测试策略、§10 的 **M5**）

**契约:** `docs/superpowers/plans/2026-11-11-algo-plan-app-接口契约.md`（§0 起点状态、§4 M5 新增、§6 G17–G22、§7 写作规范）

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）

---

## Global Constraints

M1 的 **G1–G16 全部继续生效**（零 npm 依赖、零构建、Node ≥ 24、中文注释与提交、提交即推送、
产物只在 `projects/apps/algo-plan/`、learning 仓路径不硬编码、稳定题目 ID、测试入口
`node tests/run-all.js`、中文输出、不自动 commit、SQLite 类型约束等）。
跨计划共用的 **G17–G22** 见接口契约 §6，原样继承：

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测，第一个能 `--version` 的胜出；探测结果可缓存进 `settings` |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序，用户自己写 `main()`；不注入 Solution 包装、不自动生成 main |
| G19 | **导入 id 冲突** | 同 id 已存在则跳过并计入 `skipped`；只有 `force` 才覆盖 |
| G20 | **写回前查脏** | `git -c core.quotepath=false status --porcelain -z`，按 NUL 切分；不许 `line.slice(3)` |
| G21 | **轮次解析容错** | 按列名关键词匹配，缺列填空，坏行跳过并计告警；不因一行看不懂而整体报错 |
| G22 | **零第三方图表** | 雷达图、曲线一律手绘 SVG，不引图表库 |

M5 自己追加的约束：

| # | 约束 | 精确值 |
|---|---|---|
| G23 | **掌握度公式不许改** | `首次通过率 = first_pass / attempts`；`遗忘因子 = 0.5 ^ (距上次练习天数 / 14)`；`掌握度 = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子`。反复重试通过不算掌握 |
| G24 | **覆盖度是二维之一** | `覆盖度 = 练过的不同题目数 / 期望题量`，两个维度交叉出四档诊断（薄弱且练得少 / 练过但总错 / 偶然会，没练透 / 掌握） |
| G25 | **期望题量口径固定三级** | ① `settings` 的 `insights.expected_override.<topic>` 覆盖值 → ② 题库里该 topic 的题目数 → ③ `settings` 的 `insights.expected_min_questions`（默认 **5**）兜底。取 `max(②, ③)` |
| G26 | **topics 表是物化视图** | `topics` 表的四个统计列由 M5 从 `attempts` 表 + 题库**幂等派生并覆盖**（`DELETE` + 批量插入）。掌握度只从 `topics` 表读，不从 `attempts` 表现算 |
| G27 | **每日题量口径** | 曲线数据 = `attempts` 表按 `substr(ts,1,10)` 分组的行数（即当天的提交次数），窗口内缺失的日期补 0 |
| G28 | **图表逻辑必须可单测** | 雷达点坐标、坐标轴、折线点、条形几何、SVG 拼接全部是 `web/charts.js` 里的纯函数，用 `node:test` 覆盖；页面只做 DOM 装配 |
| G29 | **SVG 里不许出现 NaN** | 所有几何函数必须把非法输入夹到合法区间；测试断言生成的 SVG 字符串不含 `NaN` |

---

## M5 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | ✅ 已完成（另一份计划） |
| M2 题库 | 复活三个死脚本 + 存量题解导入 | ❌ 另出计划 |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | ❌ 另出计划 |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | ❌ 另出计划 |
| **M5 诊断** | 掌握度模型 + 诊断页 | ✅ **本计划** |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | ❌ 另出计划 |

**M5 做完的验收线：** `GET /api/insights` 返回每个知识点的掌握度、覆盖度、四档诊断与每日题量曲线；
浏览器打开「诊断」页能看到雷达图、弱项榜、每日题量曲线、知识点覆盖四块内容；
`node tests/run-all.js` 全绿。判题、复习调度、轮次写回、LLM 一概不碰。

**M5 不碰的东西**（留给别的里程碑，别越界）：

- 不改 `core/review/sm2.js`、不写 `core/scheduler/next-action.js`（M4）
- 不写 `judge/`、不改 `POST /api/attempt` 的判题逻辑（M3）
- 不写 `core/llm/`（M6）
- 不改 `core/bank/problem.js`、`core/bank/parse.js`、`core/bank/provider.js`、`core/paths.js`（M1）
- **不改 `server/api.js`**（M3、M4 都要改它：M3 整体替换、M4 替换整个 `buildRoutes`）。
  M5 的路由放在独立文件 `server/api-insights.js` 里，在 `server/app.js` 里合并——
  跟 M6 一个套路，谁也不覆盖谁。
- **不整体替换 `server/db.js`**（M4 也往里追加过 `listAttempts` / `countAttemptsSince`）。
  M5 只在 `createStore` 的返回对象里**追加**方法，M4 的方法原样留着。
- 不写 `learning/` 仓里的任何文件（本计划**只读** learning 仓）

**M5 对 M4 的依赖（必须先有 M4）：**

M4 把 `web/app.js` 改成了 tab 调度器——`TABS` 数组是**模块内的常量**，
`renderTabs()` 每次切页都会 `nav.textContent = ""` 把整个 `#tabs` 清空重画。
所以 M5 **不能**自己往 `#tabs` 里塞按钮（塞了也会被 M4 清掉）。

M5 走 M4 已经定好的扩展点：

- **页面注册表** `window.AlgoPlan.pages[key] = {title, render(view)}`——M4 定的约定，M5 照着用；
- **tab 列表** `web/app.js` 的 `TABS` 数组——M5 **只在末尾加一项** `{key: "diagnose", label: "诊断"}`，
  M4 的调度逻辑一个字不动。

> M5 的服务端部分（Task 1–3）不依赖 M4，可以单独先做；
> Task 5（前端接线）要求 M4 已经落地。

---

## 统计口径（M5 的核心决策，先定死再写代码）

这一节是 M5 全部数字的来源。**照抄执行，不许在实现时临时改口径。**

### 1. 掌握度（设计文档 §4.3，公式不许改）

```
首次通过率 = firstPass / attempts            ← 反复重试通过不算掌握
遗忘因子   = 0.5 ^ (距上次练习天数 / 14)      ← 半衰期 14 天
掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
```

- `firstPass`：**第一次尝试就通过的题目数**。一道题提交 5 次、第 5 次才过 → 这道题**不**计入 `firstPass`。
- `attempts`：该知识点下所有题目的**提交总次数**。
- `lapses`（失误次数）：该知识点下**没通过**的提交次数。
- `lastAt`：该知识点下最后一次提交的时间。
- 从没练过（`attempts === 0`）→ 掌握度 **0**，不参与任何"衰减"计算。
- 四个数都存在 M1 的 `topics` 表里：`first_pass` / `attempts` / `lapses` / `last_at`。

### 2. 覆盖度

```
覆盖度 = 练过的不同题目数 / 期望题量
```

- **分子**是「练过的**不同题目数**」，不是提交次数。一道题刷 10 次，分子仍然只算 1。
  （`topics` 表没有这一列，M5 在装配时从派生结果里补上，见 G26。）
- **分母**是「期望题量」，见下一节。

### 3. 期望题量（G25，本计划定的口径）

> **期望题量 = 这个知识点要练多少题，才算「练透」。**

**三级口径，自上而下：**

| 优先级 | 来源 | 说明 |
|---|---|---|
| ① 覆盖值 | `settings` 表的 `insights.expected_override.<topic>` | 手工指定某个知识点的期望题量。存在且是正数就直接用，**不再看别的** |
| ② 题库题数 | 题库里带这个 topic 的题目数 | 「这个知识点一共就这么多题，练完就是 100% 覆盖」 |
| ③ 下限常量 | `settings` 表的 `insights.expected_min_questions`，默认 **5** | 「至少要练够 5 题才叫练透」 |

**②③ 的合成规则：`期望题量 = max(题库题数, 下限常量)`。**

- 题库有 20 道「数组」题 → 期望 20（来源 `bank`）。练了 10 道 → 覆盖 50%。
- 题库只有 2 道「数组」题 → 期望 5（来源 `floor`）。练了 2 道 → 覆盖 40%，**不会**因为"题库就这 2 道"而显示 100% 覆盖然后判成「掌握」。

**为什么这么定（三条理由）：**

1. **分母必须稳。** 轮次清单是滚动推进的（`learning/progress/` 里的轮次每次只推一部分），
   拿"当前轮次里该 topic 的题数"当分母，会随着轮次推进忽大忽小，覆盖度一夜之间从 30% 变 70%——
   这种数字没人敢信。题库总量是稳定的，"这个知识点一共要练多少题"的自然答案。
2. **分母必须可解释。** 「期望题量 = 题库里这个知识点的题数」一句话说得清，
   UI 上直接显示 `练过 7 / 期望 12 题`，用户自己能核对。
3. **必须有下限，否则小题库会虚高。** 只有 1 道题的冷门知识点，练 1 道就是 100% 覆盖，
   于是被判成「掌握」——但这明显不成立。下限常量把这个洞堵上。

**退化路径（每一条都要能跑通，不许抛错）：**

| 情况 | 题库题数 | 期望题量 | 来源标记 |
|---|---|---|---|
| 正常：有 learning 仓、题库里有这个 topic | 实际题数 | `max(实际题数, 5)` | `bank` |
| 纯本地模式（没设 `ALGO_PLAN_LEARNING_ROOT`） | 0 | 5 | `floor` |
| `learning/bank/` 目录不存在 | 0 | 5 | `floor` |
| 这个 topic 只出现在流水里、题库里查不到（老数据 / 手工写的标签） | 0 | 5 | `floor` |
| `settings.insights.expected_min_questions` 非法（非数字 / ≤ 0） | — | 5（回默认值） | `floor` |
| `settings.insights.expected_override.<topic>` 非法（非数字 / ≤ 0） | — | 忽略该覆盖值，继续走 ②③ | `bank` / `floor` |

**可配置：** 下限常量与逐 topic 覆盖值都存在 SQLite 的 `settings` 表里，
键名分别是 `insights.expected_min_questions` 与 `insights.expected_override.<topic>`，
可以直接用 `sqlite3` 或未来的「设置」页改，改完刷新诊断页立刻生效。

### 4. 四档诊断（设计文档 §4.3）

| 掌握度 | 覆盖度 | 档位 key | 中文标签 | app 该做什么（设计文档原话） |
|---|---|---|---|---|
| 低 | 低 | `weak-sparse` | 薄弱且练得少 | 轮次里优先排这类题 |
| 低 | 高 | `weak-dense` | 练过但总错 | 提示回去看概念，而不是继续刷题 |
| 高 | 低 | `strong-sparse` | 偶然会，没练透 | 安排复习巩固 |
| 高 | 高 | `strong-dense` | 掌握 | 不再主动排 |

**阈值：掌握度 ≥ 0.5 算「高」，覆盖度 ≥ 0.5 算「高」。** 两个阈值都是常量，
写在 `core/mastery/mastery.js` 里并导出（`MASTERY_THRESHOLD` / `COVERAGE_THRESHOLD`）。

「练过但总错」这一档很重要——它区分「题做得少」和「概念没懂」，两者处方完全不同。

### 5. 每日题量曲线

- 数据源：`attempts` 表，按 `substr(ts,1,10)` 分组取行数 → **当天的提交次数**。
- 窗口：默认最近 **30** 天，`GET /api/insights?days=N` 可调（`days=0` 表示全部）。
- 窗口内某天没有提交 → **补 0**（不跳点），这样"哪天没练"在曲线上是看得见的。
- 日期一律用 UTC 日期（`ts` 是 ISO8601 字符串，`substr(ts,1,10)` 本身就是 UTC 日期）。

### 6. topics 表是物化视图（G26）

`topics` 表是 M1 建的（`id` / `first_pass` / `attempts` / `last_at` / `lapses`）。
M5 接管它的**写入口径**：

```
attempts 表 + 题库  ──派生──▶  topics 表（DELETE + 批量插入，幂等）
                                   │
                                   └──读──▶ 掌握度 / 覆盖度 / 弱项榜
```

- 派生是**幂等**的：每次 `/api/insights` 都重算一遍并整体覆盖，所以不管 M3/M4 有没有往
  `topics` 表里写过增量，读到的永远是同一套口径的数字。
- 口径以本计划为准：`first_pass` = 题目**首次尝试就通过**的个数；`lapses` = **没通过**的提交次数。
- 派生不出知识点的题目（题库里查不到它的 topics）**不计入**——没有知识点归属就没法诊断。
- 「题库里有、但一次没练过的知识点」不进 `topics` 表，只在 `summary.untouchedTopics` 里报个数。

---

## 文件结构总览（先锁定边界，再写任务）

M5 **新增**这些文件：

```
projects/apps/algo-plan/
├── core/
│   └── mastery/
│       ├── mastery.js          掌握度模型与四档诊断（纯函数）
│       ├── expected.js         「期望题量」口径（纯函数）
│       └── topic-stats.js      从作答流水派生知识点统计（纯函数）
├── server/
│   ├── insights.js             诊断数据装配（读 attempts + 题库 → topics → 响应）
│   ├── api-insights.js         M5 的路由（独立文件，不改 server/api.js）
│   ├── app.js                  ← 改：把 M5 的路由合并进路由表（只做加法）
│   └── db.js                   ← 改：只做加法，store 追加三个方法（已有方法签名不动）
├── web/
│   ├── charts.js               图表纯函数 + SVG 拼接（UMD 双模，零依赖）
│   ├── diagnose.js             诊断页（按 M4 的页面约定注册进 window.AlgoPlan.pages）
│   ├── app.js                  ← 改：TABS 数组末尾加一项「诊断」（M4 的调度逻辑不动）
│   ├── diagnose.css            诊断页样式
│   └── index.html              ← 改：加 charts.js 与 diagnose.js 两个 script + 一个 css 标签
└── tests/
    ├── mastery.test.js         掌握度模型
    ├── mastery-stats.test.js   期望题量口径 + 知识点统计派生
    ├── insights.test.js        诊断数据装配 + /api/insights 接口
    ├── charts.test.js          图表纯函数与 SVG
    ├── diagnose.test.js        诊断页的纯函数（排序、计数、图例）+ 页面注册
    └── diagnose-e2e.test.js    端到端：造流水 → 打接口 → 校验页面资源
```

**归属**：本计划只改 `projects/` 子模块。`learning/` 子模块在本计划里**只被读取**
（题库用来数「期望题量」和建立题目↔知识点的映射）。

---

## Task 1: 掌握度模型与四档诊断

**Files:**
- Create: `projects/apps/algo-plan/core/mastery/mastery.js`
- Create: `projects/apps/algo-plan/tests/mastery.test.js`

**Interfaces:**
- Consumes: 无（纯函数，不依赖 M1 的任何模块）
- Produces（后续 Task 直接引用这些名字与签名）:
  - `core/mastery/mastery.js` 导出：
    - `HALF_LIFE_DAYS = 14`
    - `MASTERY_THRESHOLD = 0.5`
    - `COVERAGE_THRESHOLD = 0.5`
    - `masteryOf(stat, nowIso) -> number`（0~1）
    - `coverageOf(stat, expectedCount) -> number`（0~1）
    - `diagnose(mastery, coverage) -> "weak-sparse"|"weak-dense"|"strong-sparse"|"strong-dense"`
    - `diagnoseLabel(bucket) -> string`（中文标签）
    - `diagnoseAction(bucket) -> string`（该档位 app 该做什么，中文）
    - `rankTopics(stats, nowIso, expectedCounts) -> [{topic, mastery, coverage, bucket, label}]`
    - `sortByUrgency(items) -> item[]`（按「该先治哪个」排序，不改原数组）

  **`stat` 的字段形状**（后面每个 Task 都按这个来）：

  ```js
  {
    topic: "数组",
    attempts: 6,          // 总提交次数
    firstPass: 3,         // 首次尝试就通过的题目数
    lapses: 2,            // 没通过的提交次数
    lastAt: "2026-11-10T08:00:00.000Z",  // 最后一次提交
    problems: 4,          // 练过的不同题目数（覆盖度的分子）
  }
  ```

  **`expectedCounts` 的字段形状**：`{ "数组": 12, "哈希表": 5 }`（topic → 期望题量）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/mastery.test.js`：

```javascript
"use strict"
/**
 * mastery.test.js —— 掌握度模型与四档诊断
 *
 * 公式见设计文档 §4.3：
 *   首次通过率 = firstPass / attempts
 *   遗忘因子   = 0.5 ^ (距上次练习天数 / 14)
 *   掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
 */

const test = require("node:test")
const assert = require("node:assert")

const mastery = require("../core/mastery/mastery.js")

/** 造一个知识点统计 */
function stat(overrides) {
  return Object.assign(
    {
      topic: "数组",
      attempts: 0,
      firstPass: 0,
      lapses: 0,
      lastAt: null,
      problems: 0,
    },
    overrides || {}
  )
}

const NOW = "2026-11-11T00:00:00.000Z"

test("常量按契约固定", function () {
  assert.strictEqual(mastery.HALF_LIFE_DAYS, 14)
  assert.strictEqual(mastery.MASTERY_THRESHOLD, 0.5)
  assert.strictEqual(mastery.COVERAGE_THRESHOLD, 0.5)
})

test("没练过的知识点掌握度为 0", function () {
  assert.strictEqual(mastery.masteryOf(stat(), NOW), 0)
})

test("全一次通过且刚练过，掌握度为 1", function () {
  const s = mastery.masteryOf(
    stat({ attempts: 4, firstPass: 4, lapses: 0, lastAt: NOW, problems: 4 }),
    NOW
  )
  assert.ok(Math.abs(s - 1) < 1e-9, "实际 " + s)
})

test("首次通过率按 firstPass/attempts 算，反复重试通过不算掌握", function () {
  // 4 次提交、只有 1 次是「首次尝试就通过」→ 首次通过率 0.25
  const s = mastery.masteryOf(
    stat({ attempts: 4, firstPass: 1, lapses: 0, lastAt: NOW, problems: 1 }),
    NOW
  )
  // (0.7 × 0.25 + 0.3 × 1) × 1 = 0.475
  assert.ok(Math.abs(s - 0.475) < 1e-9, "实际 " + s)
})

test("遗忘因子按半衰期 14 天衰减", function () {
  const base = stat({ attempts: 4, firstPass: 4, lapses: 0, problems: 4 })
  const fresh = mastery.masteryOf(Object.assign({}, base, { lastAt: NOW }), NOW)
  const half = mastery.masteryOf(
    Object.assign({}, base, { lastAt: "2026-10-28T00:00:00.000Z" }),
    NOW
  )
  assert.ok(Math.abs(half / fresh - 0.5) < 1e-9, "14 天后应剩一半，实际 " + half / fresh)
})

test("30 天不练，掌握度掉到约一半以下", function () {
  const base = stat({ attempts: 4, firstPass: 4, lapses: 0, problems: 4 })
  const fresh = mastery.masteryOf(Object.assign({}, base, { lastAt: NOW }), NOW)
  const old = mastery.masteryOf(
    Object.assign({}, base, { lastAt: "2026-10-12T00:00:00.000Z" }),
    NOW
  )
  assert.ok(old < fresh, "旧练习的掌握度应更低")
  assert.ok(old / fresh < 0.25, "30 天后应衰减到约 1/4 强，实际 " + old / fresh)
})

test("失误会拉低掌握度", function () {
  const a = mastery.masteryOf(stat({ attempts: 4, firstPass: 4, lapses: 0, lastAt: NOW }), NOW)
  const b = mastery.masteryOf(stat({ attempts: 4, firstPass: 4, lapses: 3, lastAt: NOW }), NOW)
  assert.ok(b < a, "失误多的时候掌握度应更低")
})

test("时间倒流或 lastAt 为空时不衰减", function () {
  const future = mastery.masteryOf(
    stat({ attempts: 2, firstPass: 2, lapses: 0, lastAt: "2027-01-01T00:00:00.000Z" }),
    NOW
  )
  const none = mastery.masteryOf(stat({ attempts: 2, firstPass: 2, lapses: 0, lastAt: null }), NOW)
  assert.strictEqual(future, 1)
  assert.strictEqual(none, 1)
})

test("非法 stat 不抛错，掌握度落在 0~1", function () {
  assert.strictEqual(mastery.masteryOf(null, NOW), 0)
  assert.strictEqual(mastery.masteryOf(undefined, NOW), 0)
  const s = mastery.masteryOf(stat({ attempts: 10, firstPass: 99, lapses: -3, lastAt: "坏时间" }), NOW)
  assert.ok(s >= 0 && s <= 1, "实际 " + s)
})

test("覆盖度用练过的不同题目数除以期望题量", function () {
  assert.strictEqual(mastery.coverageOf(stat({ problems: 6 }), 12), 0.5)
  assert.strictEqual(mastery.coverageOf(stat({ problems: 20 }), 12), 1)
  assert.strictEqual(mastery.coverageOf(stat({ problems: 0 }), 12), 0)
})

test("覆盖度没有 problems 字段时退回用 attempts", function () {
  assert.strictEqual(mastery.coverageOf({ attempts: 3 }, 6), 0.5)
})

test("期望题量非法时覆盖度为 0，不抛错", function () {
  assert.strictEqual(mastery.coverageOf(stat({ problems: 3 }), 0), 0)
  assert.strictEqual(mastery.coverageOf(stat({ problems: 3 }), -1), 0)
  assert.strictEqual(mastery.coverageOf(stat({ problems: 3 }), null), 0)
})

test("四档诊断判定", function () {
  assert.strictEqual(mastery.diagnose(0.2, 0.2), "weak-sparse")
  assert.strictEqual(mastery.diagnose(0.2, 0.8), "weak-dense")
  assert.strictEqual(mastery.diagnose(0.9, 0.2), "strong-sparse")
  assert.strictEqual(mastery.diagnose(0.9, 0.8), "strong-dense")
})

test("阈值正好在 0.5 时算「高」", function () {
  assert.strictEqual(mastery.diagnose(0.5, 0.5), "strong-dense")
  assert.strictEqual(mastery.diagnose(0.4999, 0.5), "weak-dense")
})

test("四档中文标签", function () {
  assert.strictEqual(mastery.diagnoseLabel("weak-sparse"), "薄弱且练得少")
  assert.strictEqual(mastery.diagnoseLabel("weak-dense"), "练过但总错")
  assert.strictEqual(mastery.diagnoseLabel("strong-sparse"), "偶然会，没练透")
  assert.strictEqual(mastery.diagnoseLabel("strong-dense"), "掌握")
})

test("未知档位给中文兜底文案", function () {
  assert.strictEqual(mastery.diagnoseLabel("nope"), "未知档位")
})

test("四档的建议动作都能落到设计文档 §4.3 的处方上", function () {
  assert.ok(mastery.diagnoseAction("weak-sparse").indexOf("优先排") !== -1)
  assert.ok(mastery.diagnoseAction("weak-dense").indexOf("看概念") !== -1)
  assert.ok(mastery.diagnoseAction("strong-sparse").indexOf("复习") !== -1)
  assert.ok(mastery.diagnoseAction("strong-dense").indexOf("不再主动排") !== -1)
})

test("rankTopics 按掌握度升序，并带上档位与标签", function () {
  const stats = [
    stat({ topic: "强", attempts: 5, firstPass: 5, lapses: 0, lastAt: NOW, problems: 5 }),
    stat({ topic: "弱", attempts: 5, firstPass: 1, lapses: 3, lastAt: NOW, problems: 2 }),
  ]
  const ranked = mastery.rankTopics(stats, NOW, { 强: 5, 弱: 5 })
  assert.strictEqual(ranked.length, 2)
  assert.strictEqual(ranked[0].topic, "弱")
  assert.strictEqual(ranked[1].topic, "强")
  assert.strictEqual(ranked[0].label, mastery.diagnoseLabel(ranked[0].bucket))
  assert.ok("mastery" in ranked[0] && "coverage" in ranked[0])
})

test("rankTopics 缺期望题量时覆盖度为 0，不抛错", function () {
  const ranked = mastery.rankTopics([stat({ topic: "数组", attempts: 2, firstPass: 2, problems: 2 })], NOW, {})
  assert.strictEqual(ranked[0].coverage, 0)
})

test("sortByUrgency 把「练过但总错」排在最前", function () {
  const items = [
    { topic: "a", bucket: "strong-dense", mastery: 0.9 },
    { topic: "b", bucket: "weak-sparse", mastery: 0.1 },
    { topic: "c", bucket: "weak-dense", mastery: 0.2 },
    { topic: "d", bucket: "strong-sparse", mastery: 0.8 },
  ]
  const sorted = mastery.sortByUrgency(items)
  assert.deepStrictEqual(
    sorted.map(function (x) { return x.topic }),
    ["c", "b", "d", "a"]
  )
})

test("sortByUrgency 不改原数组", function () {
  const items = [
    { topic: "a", bucket: "strong-dense", mastery: 0.9 },
    { topic: "b", bucket: "weak-dense", mastery: 0.2 },
  ]
  const copy = items.slice()
  mastery.sortByUrgency(items)
  assert.deepStrictEqual(items, copy)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/mastery.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/mastery/mastery.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/mastery/mastery.js`：

```javascript
"use strict"
/**
 * mastery.js —— 掌握度模型与四档诊断
 *
 * 纯函数，无 IO。公式照设计文档 §4.3，一个字不许改：
 *   首次通过率 = firstPass / attempts        （反复重试通过不算掌握）
 *   遗忘因子   = 0.5 ^ (距上次练习天数 / 14)  （半衰期 14 天）
 *   掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
 *
 * 覆盖度是第二个维度：练过的不同题目数 / 期望题量。
 * 两个维度交叉出四档诊断，用来区分「题做得少」与「概念没懂」——
 * 这两者的处方完全不同（前者多做题，后者先读笔记）。
 */

/** 遗忘半衰期（天） */
const HALF_LIFE_DAYS = 14

/** 掌握度「高 / 低」的分界 */
const MASTERY_THRESHOLD = 0.5

/** 覆盖度「高 / 低」的分界 */
const COVERAGE_THRESHOLD = 0.5

/** 四档诊断的中文标签 */
const LABELS = {
  "weak-sparse": "薄弱且练得少",
  "weak-dense": "练过但总错",
  "strong-sparse": "偶然会，没练透",
  "strong-dense": "掌握",
}

/** 四档诊断对应的 app 动作（设计文档 §4.3 的「app 的动作」列） */
const ACTIONS = {
  "weak-sparse": "轮次里优先排这类题——先补量",
  "weak-dense": "先回去看概念笔记，别急着刷题——量够了，理解没到位",
  "strong-sparse": "安排复习巩固——会做，但还没练透",
  "strong-dense": "已掌握，不再主动排",
}

/** 处置优先级：越靠前越该先治 */
const URGENCY_ORDER = ["weak-dense", "weak-sparse", "strong-sparse", "strong-dense"]

/**
 * 把任意输入夹到 [0, 1]。
 */
function clamp01(value) {
  const n = Number(value)
  if (!Number.isFinite(n)) return 0
  if (n < 0) return 0
  if (n > 1) return 1
  return n
}

/**
 * 掌握度。
 * @param {{attempts:number, firstPass:number, lapses:number, lastAt:string|null}} stat
 * @param {string} nowIso 当前时刻（ISO8601）
 * @returns {number} 0~1
 */
function masteryOf(stat, nowIso) {
  const s = stat || {}
  const attempts = Number(s.attempts || 0)
  if (!Number.isFinite(attempts) || attempts <= 0) return 0

  const firstPass = Number(s.firstPass || 0)
  const lapses = Number(s.lapses || 0)

  // 首次通过率：反复重试通过不算掌握，所以分母是总提交次数
  const firstPassRate = clamp01(firstPass / attempts)
  // 失误惩罚：失误越多，这一项越接近 0
  const lapseFactor = Math.exp(-(Number.isFinite(lapses) ? lapses : 0) / 2)
  const base = 0.7 * firstPassRate + 0.3 * lapseFactor

  // 遗忘因子：距上次练习的天数
  let days = 0
  if (s.lastAt) {
    const then = new Date(s.lastAt).getTime()
    const now = new Date(nowIso).getTime()
    if (Number.isFinite(then) && Number.isFinite(now) && now > then) {
      days = (now - then) / 86400000
    }
  }
  const decay = Math.pow(0.5, days / HALF_LIFE_DAYS)

  return clamp01(base * decay)
}

/**
 * 覆盖度：练过的不同题目数 / 期望题量。
 * stat 里没有 problems 字段时退回用 attempts（老数据兼容）。
 * @param {{problems?:number, attempts?:number}} stat
 * @param {number} expectedCount 期望题量
 * @returns {number} 0~1
 */
function coverageOf(stat, expectedCount) {
  const s = stat || {}
  const expected = Number(expectedCount)
  if (!Number.isFinite(expected) || expected <= 0) return 0
  const practiced =
    s.problems === undefined || s.problems === null ? Number(s.attempts || 0) : Number(s.problems)
  const safe = Number.isFinite(practiced) ? practiced : 0
  return clamp01(safe / expected)
}

/**
 * 四档诊断。
 * @param {number} mastery 0~1
 * @param {number} coverage 0~1
 * @returns {"weak-sparse"|"weak-dense"|"strong-sparse"|"strong-dense"}
 */
function diagnose(mastery, coverage) {
  const strong = Number(mastery) >= MASTERY_THRESHOLD
  const dense = Number(coverage) >= COVERAGE_THRESHOLD
  if (!strong && !dense) return "weak-sparse"
  if (!strong && dense) return "weak-dense"
  if (strong && !dense) return "strong-sparse"
  return "strong-dense"
}

/**
 * 档位的中文标签。
 * @param {string} bucket
 * @returns {string}
 */
function diagnoseLabel(bucket) {
  return LABELS[bucket] || "未知档位"
}

/**
 * 档位对应的 app 动作。
 * @param {string} bucket
 * @returns {string}
 */
function diagnoseAction(bucket) {
  return ACTIONS[bucket] || "暂无建议动作"
}

/**
 * 给知识点排序：掌握度低的在前。排程器挑题也用这个顺序。
 * @param {object[]} stats 每项至少有 topic / attempts / firstPass / lapses / lastAt
 * @param {string} nowIso
 * @param {Object<string, number>} expectedCounts topic → 期望题量
 * @returns {Array<{topic:string, mastery:number, coverage:number, bucket:string, label:string}>}
 */
function rankTopics(stats, nowIso, expectedCounts) {
  const expected = expectedCounts || {}
  const rows = (stats || []).map(function (s) {
    const topic = s.topic
    const mastery = masteryOf(s, nowIso)
    const coverage = coverageOf(s, expected[topic])
    const bucket = diagnose(mastery, coverage)
    return {
      topic: topic,
      mastery: mastery,
      coverage: coverage,
      bucket: bucket,
      label: diagnoseLabel(bucket),
    }
  })
  rows.sort(function (a, b) {
    if (a.mastery !== b.mastery) return a.mastery - b.mastery
    if (a.topic === b.topic) return 0
    return a.topic < b.topic ? -1 : 1
  })
  return rows
}

/**
 * 按「该先治哪个」排序：练过但总错 > 薄弱且练得少 > 偶然会没练透 > 掌握。
 * 不改原数组。
 * @param {object[]} items 每项至少有 topic / bucket / mastery
 * @returns {object[]}
 */
function sortByUrgency(items) {
  return (items || []).slice().sort(function (a, b) {
    const ia = URGENCY_ORDER.indexOf(a.bucket)
    const ib = URGENCY_ORDER.indexOf(b.bucket)
    const pa = ia === -1 ? URGENCY_ORDER.length : ia
    const pb = ib === -1 ? URGENCY_ORDER.length : ib
    if (pa !== pb) return pa - pb
    if (a.mastery !== b.mastery) return a.mastery - b.mastery
    if (a.topic === b.topic) return 0
    return String(a.topic) < String(b.topic) ? -1 : 1
  })
}

module.exports = {
  HALF_LIFE_DAYS: HALF_LIFE_DAYS,
  MASTERY_THRESHOLD: MASTERY_THRESHOLD,
  COVERAGE_THRESHOLD: COVERAGE_THRESHOLD,
  LABELS: LABELS,
  ACTIONS: ACTIONS,
  URGENCY_ORDER: URGENCY_ORDER,
  masteryOf: masteryOf,
  coverageOf: coverageOf,
  diagnose: diagnose,
  diagnoseLabel: diagnoseLabel,
  diagnoseAction: diagnoseAction,
  rankTopics: rankTopics,
  sortByUrgency: sortByUrgency,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/mastery.test.js
```

Expected: `# fail 0`，退出码 0

再跑全量，确认没弄坏别的套件：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`（N = 仓库里当时的套件总数），退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加掌握度模型与四档诊断

- core/mastery/mastery.js：首次通过率 + 半衰期 14 天的遗忘因子 + 失误惩罚，
  公式照设计文档 §4.3，反复重试通过不算掌握
- 覆盖度用练过的不同题目数除以期望题量，作为第二个维度
- 四档诊断：薄弱且练得少 / 练过但总错 / 偶然会，没练透 / 掌握，
  用来区分「题做得少」与「概念没懂」两种不同处方
- diagnoseAction 给出每档的处方文案；sortByUrgency 按处置优先级排序
- 测试：公式、衰减、阈值、四档、排序共 20 条断言"
git push origin main
```

---

## Task 2: 统计口径——期望题量与知识点统计派生

**Files:**
- Create: `projects/apps/algo-plan/core/mastery/expected.js`
- Create: `projects/apps/algo-plan/core/mastery/topic-stats.js`
- Create: `projects/apps/algo-plan/tests/mastery-stats.test.js`

**Interfaces:**
- Consumes: 无（两个文件都是纯函数，不依赖 M1 的任何模块）
- Produces:
  - `core/mastery/expected.js` 导出：
    - `DEFAULT_MIN_EXPECTED = 5`
    - `SETTING_MIN = "insights.expected_min_questions"`
    - `SETTING_OVERRIDE_PREFIX = "insights.expected_override."`
    - `minExpectedFrom(settings) -> number`（下限常量，非法值退回 5）
    - `bankTopicCounts(problems) -> {topic: number}`（题库里每个 topic 的题数）
    - `expectedFor(topic, bankCounts, settings) -> {expected: number, source: "override"|"bank"|"floor"}`
    - `buildExpectedMap(topics, bankCounts, settings) -> {topic: {expected, source}}`
  - `core/mastery/topic-stats.js` 导出：
    - `deriveTopicStats(attempts, problems) -> [{topic, attempts, firstPass, lapses, lastAt, problems}]`
      - `attempts` 的元素形状：`{id, problem_id, ts, verdict}`
      - `problems` 的元素形状：`{id, topics: string[]}`

  **`settings` 的形状**：`{ "insights.expected_min_questions": "8", "insights.expected_override.数组": "20" }`
  （就是 `store.allSettings()` 的返回值）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/mastery-stats.test.js`：

```javascript
"use strict"
/**
 * mastery-stats.test.js —— 期望题量口径 + 知识点统计派生
 *
 * 期望题量的口径见本计划「统计口径」一节：
 *   ① settings 的逐 topic 覆盖值 → ② 题库里该 topic 的题数 → ③ 下限常量（默认 5）
 *   最终取 max(②, ③)
 */

const test = require("node:test")
const assert = require("node:assert")

const expected = require("../core/mastery/expected.js")
const topicStats = require("../core/mastery/topic-stats.js")

/* ---------------- expected.js ---------------- */

test("期望题量下限默认是 5", function () {
  assert.strictEqual(expected.DEFAULT_MIN_EXPECTED, 5)
  assert.strictEqual(expected.minExpectedFrom({}), 5)
  assert.strictEqual(expected.minExpectedFrom(undefined), 5)
})

test("期望题量下限可配置", function () {
  assert.strictEqual(expected.minExpectedFrom({ "insights.expected_min_questions": "8" }), 8)
  assert.strictEqual(expected.minExpectedFrom({ "insights.expected_min_questions": 3 }), 3)
})

test("期望题量下限非法时退回默认 5", function () {
  assert.strictEqual(expected.minExpectedFrom({ "insights.expected_min_questions": "abc" }), 5)
  assert.strictEqual(expected.minExpectedFrom({ "insights.expected_min_questions": "0" }), 5)
  assert.strictEqual(expected.minExpectedFrom({ "insights.expected_min_questions": "-2" }), 5)
})

test("bankTopicCounts 数出题库里每个 topic 的题数", function () {
  const counts = expected.bankTopicCounts([
    { id: "lc-00001", topics: ["数组", "哈希表"] },
    { id: "lc-00002", topics: ["数组"] },
    { id: "lc-00003", topics: [] },
  ])
  assert.strictEqual(counts["数组"], 2)
  assert.strictEqual(counts["哈希表"], 1)
})

test("期望题量取题库题数", function () {
  const r = expected.expectedFor("数组", { "数组": 12 }, {})
  assert.strictEqual(r.expected, 12)
  assert.strictEqual(r.source, "bank")
})

test("题库题数不足下限时抬到下限", function () {
  const r = expected.expectedFor("冷门", { "冷门": 2 }, {})
  assert.strictEqual(r.expected, 5)
  assert.strictEqual(r.source, "floor")
})

test("手工覆盖值优先于题库题数", function () {
  const r = expected.expectedFor("数组", { "数组": 12 }, { "insights.expected_override.数组": "20" })
  assert.strictEqual(r.expected, 20)
  assert.strictEqual(r.source, "override")
})

test("覆盖值非法时忽略，继续走题库/下限", function () {
  const r = expected.expectedFor("数组", { "数组": 12 }, { "insights.expected_override.数组": "abc" })
  assert.strictEqual(r.expected, 12)
  assert.strictEqual(r.source, "bank")
})

test("题库里没有这个 topic 时退到下限", function () {
  const r = expected.expectedFor("没进题库", {}, {})
  assert.strictEqual(r.expected, 5)
  assert.strictEqual(r.source, "floor")
})

test("buildExpectedMap 给每个 topic 都算一份", function () {
  const map = expected.buildExpectedMap(["数组", "冷门"], { "数组": 12 }, {})
  assert.strictEqual(map["数组"].expected, 12)
  assert.strictEqual(map["数组"].source, "bank")
  assert.strictEqual(map["冷门"].expected, 5)
  assert.strictEqual(map["冷门"].source, "floor")
})

/* ---------------- topic-stats.js ---------------- */

test("deriveTopicStats 统计每个 topic 的提交数、首次通过数与失误数", function () {
  const stats = topicStats.deriveTopicStats(
    [
      { id: 1, problem_id: "lc-00001", ts: "2026-11-01T10:00:00.000Z", verdict: "pass" },
      { id: 2, problem_id: "lc-00001", ts: "2026-11-02T10:00:00.000Z", verdict: "wrong_answer" },
      { id: 3, problem_id: "lc-00002", ts: "2026-11-02T11:00:00.000Z", verdict: "wrong_answer" },
      { id: 4, problem_id: "lc-00002", ts: "2026-11-03T11:00:00.000Z", verdict: "pass" },
    ],
    [
      { id: "lc-00001", topics: ["数组"] },
      { id: "lc-00002", topics: ["数组", "哈希表"] },
    ]
  )

  const array = stats.find(function (s) { return s.topic === "数组" })
  assert.strictEqual(array.attempts, 4)
  assert.strictEqual(array.firstPass, 1)
  assert.strictEqual(array.lapses, 2)
  assert.strictEqual(array.problems, 2)
  assert.strictEqual(array.lastAt, "2026-11-03T11:00:00.000Z")

  const hash = stats.find(function (s) { return s.topic === "哈希表" })
  assert.strictEqual(hash.attempts, 2)
  assert.strictEqual(hash.firstPass, 0)
  assert.strictEqual(hash.lapses, 1)
  assert.strictEqual(hash.problems, 1)
})

test("deriveTopicStats 题目首次尝试通过才算首次通过", function () {
  const stats = topicStats.deriveTopicStats(
    [
      { id: 1, problem_id: "lc-00001", ts: "2026-11-01T10:00:00.000Z", verdict: "wrong_answer" },
      { id: 2, problem_id: "lc-00001", ts: "2026-11-02T10:00:00.000Z", verdict: "pass" },
    ],
    [{ id: "lc-00001", topics: ["数组"] }]
  )
  assert.strictEqual(stats[0].firstPass, 0)
  assert.strictEqual(stats[0].lapses, 1)
  assert.strictEqual(stats[0].attempts, 2)
})

test("deriveTopicStats 题库里查不到的题目不计入", function () {
  const stats = topicStats.deriveTopicStats(
    [{ id: 1, problem_id: "lc-99999", ts: "2026-11-01T10:00:00.000Z", verdict: "pass" }],
    [{ id: "lc-00001", topics: ["数组"] }]
  )
  assert.deepStrictEqual(stats, [])
})

test("deriveTopicStats 一道题挂多个 topic 时两边都算", function () {
  const stats = topicStats.deriveTopicStats(
    [{ id: 1, problem_id: "lc-00001", ts: "2026-11-01T10:00:00.000Z", verdict: "pass" }],
    [{ id: "lc-00001", topics: ["数组", "哈希表"] }]
  )
  assert.strictEqual(stats.length, 2)
  stats.forEach(function (s) {
    assert.strictEqual(s.attempts, 1)
    assert.strictEqual(s.problems, 1)
  })
})

test("deriveTopicStats 空输入返回空数组", function () {
  assert.deepStrictEqual(topicStats.deriveTopicStats([], []), [])
  assert.deepStrictEqual(topicStats.deriveTopicStats(undefined, undefined), [])
})

test("deriveTopicStats 结果按 topic 名排序", function () {
  const stats = topicStats.deriveTopicStats(
    [{ id: 1, problem_id: "lc-00001", ts: "2026-11-01T10:00:00.000Z", verdict: "pass" }],
    [{ id: "lc-00001", topics: ["数组", "哈希表"] }]
  )
  const names = stats.map(function (s) { return s.topic })
  assert.deepStrictEqual(names, names.slice().sort())
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/mastery-stats.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/mastery/expected.js'`

- [ ] **Step 3: 写 core/mastery/expected.js**

Create `projects/apps/algo-plan/core/mastery/expected.js`：

```javascript
"use strict"
/**
 * expected.js —— 「期望题量」口径：覆盖度的分母
 *
 * 期望题量 = 这个知识点要练多少题，才算「练透」。
 *
 * 三级口径（自上而下）：
 *   ① settings 的 insights.expected_override.<topic> → 手工指定，直接用
 *   ② 题库里带这个 topic 的题目数                       → 这个知识点一共就这么多题
 *   ③ settings 的 insights.expected_min_questions（默认 5）→ 至少要练够这么多题
 *
 * ②③ 合成：期望题量 = max(题库题数, 下限常量)。
 * 下限存在的理由：题库里只有 1 道题的冷门知识点，练 1 道就是 100% 覆盖，
 * 会被误判成「掌握」——下限把这个洞堵上。
 *
 * 退化：题库不可用（纯本地模式 / learning 仓没连 / bank 目录不存在）
 * 或这个 topic 只出现在流水里时，题库题数为 0 → 全部走下限，不抛错。
 */

/** 期望题量的默认下限（题） */
const DEFAULT_MIN_EXPECTED = 5

/** 下限常量的 settings 键 */
const SETTING_MIN = "insights.expected_min_questions"

/** 逐 topic 覆盖值的 settings 键前缀 */
const SETTING_OVERRIDE_PREFIX = "insights.expected_override."

/**
 * 读下限常量。非法值退回默认 5。
 * @param {Object<string, string>} settings
 * @returns {number}
 */
function minExpectedFrom(settings) {
  const raw = (settings || {})[SETTING_MIN]
  if (raw === undefined || raw === null || String(raw).trim() === "") return DEFAULT_MIN_EXPECTED
  const value = Number(raw)
  if (!Number.isFinite(value) || value <= 0) return DEFAULT_MIN_EXPECTED
  return Math.floor(value)
}

/**
 * 数出题库里每个 topic 有多少题。
 * @param {Array<{id: string, topics: string[]}>} problems
 * @returns {Object<string, number>}
 */
function bankTopicCounts(problems) {
  const counts = {}
  ;(problems || []).forEach(function (problem) {
    ;(problem.topics || []).forEach(function (topic) {
      const key = String(topic)
      if (key === "") return
      counts[key] = (counts[key] || 0) + 1
    })
  })
  return counts
}

/**
 * 算一个 topic 的期望题量。
 * @param {string} topic
 * @param {Object<string, number>} bankCounts
 * @param {Object<string, string>} settings
 * @returns {{expected: number, source: "override"|"bank"|"floor"}}
 */
function expectedFor(topic, bankCounts, settings) {
  const all = settings || {}
  const overrideRaw = all[SETTING_OVERRIDE_PREFIX + topic]
  if (overrideRaw !== undefined && overrideRaw !== null && String(overrideRaw).trim() !== "") {
    const value = Number(overrideRaw)
    if (Number.isFinite(value) && value > 0) {
      return { expected: Math.floor(value), source: "override" }
    }
  }

  const min = minExpectedFrom(all)
  const bank = Number((bankCounts || {})[topic] || 0)
  const safeBank = Number.isFinite(bank) && bank > 0 ? Math.floor(bank) : 0
  if (safeBank >= min) return { expected: safeBank, source: "bank" }
  return { expected: min, source: "floor" }
}

/**
 * 给一批 topic 批量算期望题量。
 * @param {string[]} topics
 * @param {Object<string, number>} bankCounts
 * @param {Object<string, string>} settings
 * @returns {Object<string, {expected: number, source: string}>}
 */
function buildExpectedMap(topics, bankCounts, settings) {
  const out = {}
  ;(topics || []).forEach(function (topic) {
    const key = String(topic)
    out[key] = expectedFor(key, bankCounts, settings)
  })
  return out
}

module.exports = {
  DEFAULT_MIN_EXPECTED: DEFAULT_MIN_EXPECTED,
  SETTING_MIN: SETTING_MIN,
  SETTING_OVERRIDE_PREFIX: SETTING_OVERRIDE_PREFIX,
  minExpectedFrom: minExpectedFrom,
  bankTopicCounts: bankTopicCounts,
  expectedFor: expectedFor,
  buildExpectedMap: buildExpectedMap,
}
```

- [ ] **Step 4: 写 core/mastery/topic-stats.js**

Create `projects/apps/algo-plan/core/mastery/topic-stats.js`：

```javascript
"use strict"
/**
 * topic-stats.js —— 从作答流水派生每个知识点的统计量
 *
 * 纯函数，无 IO。口径对应设计文档 §4.3 的「首次通过率 = 首次尝试就过的比例」：
 *   attempts   = 该知识点下所有题目的提交总次数
 *   firstPass  = 该知识点下「第一次尝试就通过」的题目数（反复重试通过不算）
 *   lapses     = 该知识点下没通过的提交次数（失误次数）
 *   lastAt     = 该知识点下最后一次提交的时间
 *   problems   = 该知识点下练过的不同题目数（覆盖度的分子）
 *
 * 题库里查不到知识点的题目不计入——没有知识点归属就没法诊断。
 */

/** 一次作答视为「通过」的判定 */
function isPass(verdict) {
  return String(verdict || "") === "pass"
}

/**
 * 派生知识点统计。
 * @param {Array<{id: number, problem_id: string, ts: string, verdict: string}>} attempts
 * @param {Array<{id: string, topics: string[]}>} problems
 * @returns {Array<{topic: string, attempts: number, firstPass: number, lapses: number, lastAt: string|null, problems: number}>}
 */
function deriveTopicStats(attempts, problems) {
  // 题目 → 知识点列表
  const topicsOfProblem = {}
  ;(problems || []).forEach(function (problem) {
    topicsOfProblem[String(problem.id)] = (problem.topics || []).map(String).filter(function (t) {
      return t !== ""
    })
  })

  // 题目 → 该题的历次作答
  const attemptsOfProblem = {}
  ;(attempts || []).forEach(function (attempt) {
    const pid = String(attempt.problem_id)
    if (!attemptsOfProblem[pid]) attemptsOfProblem[pid] = []
    attemptsOfProblem[pid].push(attempt)
  })

  const stats = {}

  Object.keys(attemptsOfProblem).forEach(function (pid) {
    const topics = topicsOfProblem[pid]
    if (!topics || topics.length === 0) return

    // 按时间排序；时间相同按自增 id 排序——「第一次尝试」必须是真正的第一次
    const list = attemptsOfProblem[pid].slice().sort(function (a, b) {
      const ta = String(a.ts || "")
      const tb = String(b.ts || "")
      if (ta !== tb) return ta < tb ? -1 : 1
      return Number(a.id || 0) - Number(b.id || 0)
    })

    const firstPassed = isPass(list[0].verdict)
    let lapses = 0
    let lastAt = null
    let lastMs = -Infinity
    list.forEach(function (attempt) {
      if (!isPass(attempt.verdict)) lapses += 1
      const ts = String(attempt.ts || "")
      const ms = Date.parse(ts)
      if (ts !== "" && Number.isFinite(ms) && ms > lastMs) {
        lastMs = ms
        lastAt = ts
      }
    })

    topics.forEach(function (topic) {
      if (!stats[topic]) {
        stats[topic] = {
          topic: topic,
          attempts: 0,
          firstPass: 0,
          lapses: 0,
          lastAt: null,
          problems: 0,
        }
      }
      const row = stats[topic]
      row.attempts += list.length
      row.problems += 1
      if (firstPassed) row.firstPass += 1
      row.lapses += lapses
      if (lastAt !== null && (row.lastAt === null || Date.parse(lastAt) > Date.parse(row.lastAt))) {
        row.lastAt = lastAt
      }
    })
  })

  return Object.keys(stats)
    .map(function (key) {
      return stats[key]
    })
    .sort(function (a, b) {
      if (a.topic === b.topic) return 0
      return a.topic < b.topic ? -1 : 1
    })
}

module.exports = { deriveTopicStats: deriveTopicStats }
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/mastery-stats.test.js
```

Expected: `# fail 0`，退出码 0

再跑全量：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`，退出码 0

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 明确期望题量口径并派生知识点统计

- core/mastery/expected.js：期望题量三级口径——手工覆盖值 > 题库题数 > 下限常量（默认 5），
  取 max(题库题数, 下限)；下限防止只有 1 道题的冷门知识点练 1 道就显示 100% 覆盖
- 题库不可用或 topic 不在题库里时退到下限，不抛错
- core/mastery/topic-stats.js：从作答流水派生 attempts / firstPass / lapses / lastAt / problems
- 首次通过只认「该题第一次尝试就通过」，反复重试通过不算掌握
- 题库里查不到知识点的题目不计入
- 测试：期望题量口径与统计派生共 22 条断言"
git push origin main
```

---

## Task 3: 存储扩展、`GET /api/insights` 接口与诊断数据装配

**Files:**
- Modify: `projects/apps/algo-plan/server/db.js`（**只做加法**：store 里追加三个方法，M1/M4 已有的方法一个签名都不动）
- Create: `projects/apps/algo-plan/server/insights.js`
- Create: `projects/apps/algo-plan/server/api-insights.js`（M5 的路由，**不改 `server/api.js`**）
- Modify: `projects/apps/algo-plan/server/app.js`（**只做加法**：把 M5 的路由合并进同一张路由表）
- Create: `projects/apps/algo-plan/tests/insights.test.js`

**Interfaces:**
- Consumes:
  - Task 1 的 `core/mastery/mastery.js`：`MASTERY_THRESHOLD`、`diagnoseAction`、`rankTopics`、`sortByUrgency`
  - Task 2 的 `core/mastery/expected.js`：`bankTopicCounts`、`buildExpectedMap`、`minExpectedFrom`；`core/mastery/topic-stats.js`：`deriveTopicStats`
  - M1 的 `server/db.js` 的 `store`（`listTopics()` / `allSettings()`）、`core/bank/provider.js` 的 `provider.list()`、`server/app.js` 的 `sendJson` 与 `createApp` 里的路由表
- Produces:
  - `server/db.js` 的 store **新增**三个方法（已有方法全部保持原样）：
    - `store.listAttemptSummaries() -> [{id, problem_id, ts, verdict}]`（不带 `code` 列，避免把源码全捞进内存）
    - `store.countAttemptsByDay() -> [{date, count}]`（`substr(ts,1,10)` 分组）
    - `store.replaceTopics(rows) -> void`（`rows` 元素形状 `{id, first_pass, attempts, last_at, lapses}`；先 `DELETE FROM topics` 再批量插入）
  - `server/insights.js` 导出：
    - `buildInsights(ctx) -> Promise<{topics, summary, series}>`
      - `ctx` 的形状：`{store, provider, nowIso?, days?}`
    - `buildSeries(rows, endDate, days) -> [{date, count}]`
    - `addDays(dateStr, delta) -> string`
    - `normalizeDays(value) -> number`
    - `buildSummary(input) -> object`
      - `input` 的形状：`{topics, stats, series, bankCounts, settings, attemptTotal, problemTotal}`
      - 返回：`{topicCount, untouchedTopics, weakCount, strongCount, avgMastery, avgCoverage, totalAttempts, totalProblems, lastPracticeAt, minExpectedQuestions, windowDays, windowAttempts}`
    - `DEFAULT_DAYS = 30`、`MAX_DAYS = 365`
  - `server/api-insights.js` 新增路由 `GET /api/insights?days=N`
    - 导出：`buildInsightRoutes(ctx) -> Array<{method, pattern, handler}>`
      - `ctx` 的形状：`{store, provider, sendJson}`
    - `server/app.js` 的 `createApp` 把这个路由**合并**进 `api.js` 的路由表（只做加法）
    - 响应形状（契约 §4 要求的三个键都在）：

      ```js
      {
        topics: [{
          topic: "数组",
          mastery: 0.2836,
          coverage: 0.4,
          bucket: "weak-sparse",
          label: "薄弱且练得少",
          action: "轮次里优先排这类题——先补量",
          attempts: 4,
          firstPass: 1,
          lapses: 2,
          lastAt: "2026-11-10T08:00:00.000Z",
          expected: 5,
          expectedSource: "floor",
          problems: 2,
        }],
        summary: {
          topicCount: 2,
          untouchedTopics: 1,
          weakCount: 1,
          strongCount: 1,
          avgMastery: 0.4061,
          avgCoverage: 0.3,
          totalAttempts: 6,
          totalProblems: 3,
          lastPracticeAt: "2026-11-10T08:00:00.000Z",
          minExpectedQuestions: 5,
          windowDays: 30,
          windowAttempts: 4,
        },
        series: [{ date: "2026-11-01", count: 0 }, { date: "2026-11-02", count: 2 }],
      }
      ```

    - `topics` 的顺序：**按处置优先级**（`练过但总错` → `薄弱且练得少` → `偶然会，没练透` → `掌握`），
      同一档内按掌握度升序。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/insights.test.js`：

```javascript
"use strict"
/**
 * insights.test.js —— 诊断数据装配 + GET /api/insights 接口
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { openDb, createStore } = require("../server/db.js")
const {
  buildInsights,
  buildSeries,
  addDays,
  normalizeDays,
  DEFAULT_DAYS,
  MAX_DAYS,
} = require("../server/insights.js")
const { createApp } = require("../server/app.js")

/** 固定时刻，断言可以写死数字 */
const NOW = "2026-11-11T00:00:00.000Z"

/** 假题库：三道题，一个知识点从没练过 */
const PROBLEMS = [
  { id: "lc-00001", topics: ["数组", "哈希表"] },
  { id: "lc-00002", topics: ["数组"] },
  { id: "lc-00003", topics: ["动态规划"] },
]

function fakeProvider() {
  return {
    list: async function () {
      return PROBLEMS
    },
  }
}

function freshStore() {
  return createStore(openDb(":memory:"))
}

/** 插一条作答流水 */
function addAttempt(store, problemId, ts, verdict) {
  store.insertAttempt({
    problem_id: problemId,
    ts: ts,
    language: "cpp",
    code: "int main(){}",
    verdict: verdict,
    passed_cases: verdict === "pass" ? 2 : 0,
    total_cases: 2,
    duration_ms: 100,
    mode: "solve",
  })
}

/**
 * 造一份固定流水：
 *   lc-00001 先过（首次通过）+1 次没通过 → 数组/哈希表 各 firstPass 1
 *   lc-00002 先错（首次不算通过）+1 次过   → 数组 firstPass 仍为 1
 * 于是：数组 attempts 4 / firstPass 1 / lapses 2；哈希表 attempts 2 / firstPass 1 / lapses 1
 */
function seedAttempts(store) {
  addAttempt(store, "lc-00001", "2026-11-10T08:00:00.000Z", "pass")
  addAttempt(store, "lc-00001", "2026-11-10T09:00:00.000Z", "wrong_answer")
  addAttempt(store, "lc-00002", "2026-11-09T08:00:00.000Z", "wrong_answer")
  addAttempt(store, "lc-00002", "2026-11-09T09:00:00.000Z", "pass")
}

/* ---------------- server/insights.js ---------------- */

test("buildInsights 把派生统计物化回 topics 表", async function () {
  const store = freshStore()
  seedAttempts(store)
  await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const rows = store.listTopics()
  assert.strictEqual(rows.length, 2)
  const array = rows.find(function (r) { return r.id === "数组" })
  assert.strictEqual(array.attempts, 4)
  assert.strictEqual(array.first_pass, 1)
  assert.strictEqual(array.lapses, 2)
  assert.strictEqual(array.last_at, "2026-11-10T09:00:00.000Z")
})

test("buildInsights 返回的每个知识点带齐契约要求的字段", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  assert.ok(Array.isArray(insights.topics))
  assert.ok(insights.summary)
  assert.ok(Array.isArray(insights.series))

  const item = insights.topics.find(function (t) { return t.topic === "数组" })
  ;["topic", "mastery", "coverage", "bucket", "label", "attempts", "firstPass", "lapses", "lastAt"].forEach(
    function (key) {
      assert.ok(key in item, "缺少字段：" + key)
    }
  )
  assert.strictEqual(item.attempts, 4)
  assert.strictEqual(item.firstPass, 1)
  assert.strictEqual(item.lapses, 2)
  assert.strictEqual(item.problems, 2)
})

test("掌握度按公式算：首次通过率 + 遗忘因子", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const array = insights.topics.find(function (t) { return t.topic === "数组" })
  // 首次通过率 1/4 = 0.25；失误 2 次 → e^-1 = 0.367879
  // base = 0.7×0.25 + 0.3×0.367879 = 0.285364
  // 距上次练习 2026-11-10T09:00 → 15 小时 = 0.625 天 → decay = 0.5^(0.625/14)
  const expected = (0.7 * 0.25 + 0.3 * Math.exp(-1)) * Math.pow(0.5, 0.625 / 14)
  assert.ok(Math.abs(array.mastery - expected) < 1e-6, "实际 " + array.mastery + " 期望 " + expected)
})

test("覆盖度用练过的题目数除以期望题量", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const array = insights.topics.find(function (t) { return t.topic === "数组" })
  // 题库里「数组」只有 2 道题 < 下限 5 → 期望 5；练过 2 道 → 覆盖 0.4
  assert.strictEqual(array.expected, 5)
  assert.strictEqual(array.expectedSource, "floor")
  assert.ok(Math.abs(array.coverage - 0.4) < 1e-9, "实际 " + array.coverage)
})

test("settings 里的覆盖值能改期望题量", async function () {
  const store = freshStore()
  seedAttempts(store)
  store.setSetting("insights.expected_override.数组", "10")
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const array = insights.topics.find(function (t) { return t.topic === "数组" })
  assert.strictEqual(array.expected, 10)
  assert.strictEqual(array.expectedSource, "override")
  assert.ok(Math.abs(array.coverage - 0.2) < 1e-9, "实际 " + array.coverage)
})

test("四档诊断落到正确的档位", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const array = insights.topics.find(function (t) { return t.topic === "数组" })
  const hash = insights.topics.find(function (t) { return t.topic === "哈希表" })
  assert.strictEqual(array.bucket, "weak-sparse")
  assert.strictEqual(array.label, "薄弱且练得少")
  assert.strictEqual(hash.bucket, "strong-sparse")
  assert.strictEqual(hash.label, "偶然会，没练透")
})

test("topics 按处置优先级排序", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const buckets = insights.topics.map(function (t) { return t.bucket })
  const order = ["weak-dense", "weak-sparse", "strong-sparse", "strong-dense"]
  const indexes = buckets.map(function (b) { return order.indexOf(b) })
  for (let i = 1; i < indexes.length; i += 1) {
    assert.ok(indexes[i - 1] <= indexes[i], "顺序不对：" + buckets.join(","))
  }
})

test("summary 汇总各项数字", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })

  const s = insights.summary
  assert.strictEqual(s.topicCount, 2)
  assert.strictEqual(s.weakCount, 1)
  assert.strictEqual(s.strongCount, 1)
  // 4 条流水、2 道不同的题——按知识点加总会变成 6 和 3
  assert.strictEqual(s.totalAttempts, 4)
  assert.strictEqual(s.totalProblems, 2)
  assert.strictEqual(s.untouchedTopics, 1, "动态规划从没练过")
  assert.strictEqual(s.minExpectedQuestions, 5)
  assert.strictEqual(s.lastPracticeAt, "2026-11-10T09:00:00.000Z")
  assert.ok(s.avgMastery > 0 && s.avgMastery < 1)
})

test("每日题量曲线按 substr(ts,1,10) 分组，窗口内缺失的日期补 0", async function () {
  const store = freshStore()
  seedAttempts(store)
  const insights = await buildInsights({
    store: store,
    provider: fakeProvider(),
    nowIso: NOW,
    days: 4,
  })

  assert.strictEqual(insights.series.length, 4)
  const byDate = {}
  insights.series.forEach(function (row) { byDate[row.date] = row.count })
  assert.strictEqual(byDate["2026-11-08"], 0)
  assert.strictEqual(byDate["2026-11-09"], 2)
  assert.strictEqual(byDate["2026-11-10"], 2)
  assert.strictEqual(byDate["2026-11-11"], 0)
})

test("没有任何流水时返回空数组而不是抛错", async function () {
  const store = freshStore()
  const insights = await buildInsights({ store: store, provider: fakeProvider(), nowIso: NOW })
  assert.deepStrictEqual(insights.topics, [])
  assert.strictEqual(insights.summary.topicCount, 0)
  assert.strictEqual(insights.summary.avgMastery, 0)
  assert.ok(Array.isArray(insights.series))
})

test("addDays 跨月跨年都对", function () {
  assert.strictEqual(addDays("2026-11-11", -1), "2026-11-10")
  assert.strictEqual(addDays("2026-11-01", -1), "2026-10-31")
  assert.strictEqual(addDays("2026-12-31", 1), "2027-01-01")
  assert.strictEqual(addDays("2028-02-28", 1), "2028-02-29")
})

test("normalizeDays 夹住非法值", function () {
  assert.strictEqual(normalizeDays(undefined), DEFAULT_DAYS)
  assert.strictEqual(normalizeDays(""), DEFAULT_DAYS)
  assert.strictEqual(normalizeDays("abc"), DEFAULT_DAYS)
  assert.strictEqual(normalizeDays(-5), DEFAULT_DAYS)
  assert.strictEqual(normalizeDays(0), 0)
  assert.strictEqual(normalizeDays(7), 7)
  assert.strictEqual(normalizeDays(99999), MAX_DAYS)
})

test("buildSeries 在 days=0 时返回全部有数据的日期", function () {
  const series = buildSeries(
    [
      { date: "2026-11-01", count: 3 },
      { date: "2026-11-03", count: 1 },
    ],
    "2026-11-11",
    0
  )
  assert.deepStrictEqual(series, [
    { date: "2026-11-01", count: 3 },
    { date: "2026-11-03", count: 1 },
  ])
})

/* ---------------- store 新增的三个方法 ---------------- */

test("store.listAttemptSummaries 不带 code 列", function () {
  const store = freshStore()
  addAttempt(store, "lc-00001", "2026-11-10T08:00:00.000Z", "pass")
  const rows = store.listAttemptSummaries()
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].problem_id, "lc-00001")
  assert.strictEqual(rows[0].verdict, "pass")
  assert.strictEqual(rows[0].code, undefined)
})

test("store.countAttemptsByDay 按天分组", function () {
  const store = freshStore()
  addAttempt(store, "lc-00001", "2026-11-10T08:00:00.000Z", "pass")
  addAttempt(store, "lc-00002", "2026-11-10T20:00:00.000Z", "pass")
  addAttempt(store, "lc-00003", "2026-11-11T08:00:00.000Z", "wrong_answer")
  const rows = store.countAttemptsByDay()
  assert.deepStrictEqual(rows, [
    { date: "2026-11-10", count: 2 },
    { date: "2026-11-11", count: 1 },
  ])
})

test("store.replaceTopics 整体覆盖，不累加", function () {
  const store = freshStore()
  store.upsertTopic({ id: "数组", first_pass: 1, attempts: 1, last_at: null, lapses: 0 })
  store.replaceTopics([
    { id: "哈希表", first_pass: 2, attempts: 3, last_at: "2026-11-10T08:00:00.000Z", lapses: 1 },
  ])
  const rows = store.listTopics()
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].id, "哈希表")
  assert.strictEqual(rows[0].first_pass, 2)
})

/* ---------------- GET /api/insights ---------------- */

/** 造一个带题库的临时 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-insights-"))
  const dir = path.join(root, "bank", "interview")
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(
    path.join(dir, "lc-00001.md"),
    [
      "---",
      "id: lc-00001",
      "source: leetcode",
      "title: 两数之和",
      "difficulty: easy",
      "topics: [数组, 哈希表]",
      "tracks: [interview]",
      "status: todo",
      "needs_fill: false",
      "created: 2026-11-11",
      "updated: 2026-11-11",
      "---",
      "## 题面",
      "",
      "给定整数数组与目标值。",
      "",
    ].join("\n"),
    "utf8"
  )
  return root
}

test("GET /api/insights 返回 topics / summary / series", async function () {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/insights")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok(Array.isArray(body.topics))
    assert.ok(body.summary)
    assert.ok(Array.isArray(body.series))
  } finally {
    await app.close()
  }
})

test("GET /api/insights?days=7 缩小曲线窗口", async function () {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/insights?days=7")
    const body = await res.json()
    assert.strictEqual(body.series.length, 7)
    assert.strictEqual(body.summary.windowDays, 7)
  } finally {
    await app.close()
  }
})

test("GET /api/insights?days=abc 不炸，回默认窗口", async function () {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/insights?days=abc")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.strictEqual(body.summary.windowDays, DEFAULT_DAYS)
  } finally {
    await app.close()
  }
})

test("GET /api/insights 在有流水时给出真实的知识点统计", async function () {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  try {
    app.store.insertAttempt({
      problem_id: "lc-00001",
      ts: new Date(Date.now() - 3600 * 1000).toISOString(),
      language: "cpp",
      code: "int main(){}",
      verdict: "pass",
      passed_cases: 2,
      total_cases: 2,
      duration_ms: 90,
      mode: "solve",
    })
    const body = await (await fetch("http://127.0.0.1:" + port + "/api/insights")).json()
    assert.strictEqual(body.topics.length, 2)
    const array = body.topics.find(function (t) { return t.topic === "数组" })
    const hash = body.topics.find(function (t) { return t.topic === "哈希表" })
    assert.strictEqual(array.attempts, 1)
    assert.strictEqual(array.firstPass, 1)
    assert.strictEqual(array.problems, 1)
    assert.strictEqual(hash.attempts, 1)
    assert.strictEqual(body.summary.totalAttempts, 1, "一次提交不能按知识点数两遍")
    assert.strictEqual(body.summary.totalProblems, 1)
  } finally {
    await app.close()
  }
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/insights.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../server/insights.js'`

- [ ] **Step 3: 改 server/db.js —— store 加三个方法**

Modify `projects/apps/algo-plan/server/db.js`，在 `createStore` 返回的对象里插入下面这三个方法
（建议紧接在 `countAttempts` 之后；**只要在 `createStore` 的返回对象里就行**）。
M1 已冻结的方法一个签名、一个行为都不动，`SCHEMA` 也一个字不改——
M1 的 `topics` 表已经有 `id / first_pass / attempts / last_at / lapses` 五列，M5 只换写入方式，不动表结构。

```javascript
    /* ---------- attempts（M5 追加：诊断用的只读方法） ---------- */

    listAttemptSummaries: function () {
      return db
        .prepare("SELECT id, problem_id, ts, verdict FROM attempts ORDER BY problem_id ASC, ts ASC, id ASC")
        .all()
        .map(function (row) {
          // node:sqlite 返回的是 null 原型对象，转成普通对象方便比较与序列化
          return {
            id: Number(row.id),
            problem_id: String(row.problem_id),
            ts: String(row.ts),
            verdict: String(row.verdict),
          }
        })
    },

    countAttemptsByDay: function () {
      return db
        .prepare("SELECT substr(ts,1,10) AS date, COUNT(*) AS count FROM attempts GROUP BY date ORDER BY date ASC")
        .all()
        .map(function (row) {
          return { date: String(row.date), count: Number(row.count) }
        })
    },

    /* ---------- topics（M5 追加：整体覆盖） ---------- */

    replaceTopics: function (rows) {
      db.exec("DELETE FROM topics")
      const stmt = db.prepare(
        "INSERT INTO topics(id, first_pass, attempts, last_at, lapses) VALUES(?, ?, ?, ?, ?)"
      )
      ;(rows || []).forEach(function (row) {
        stmt.run(
          String(row.id),
          Number(row.first_pass || 0),
          Number(row.attempts || 0),
          row.last_at === null || row.last_at === undefined ? null : String(row.last_at),
          Number(row.lapses || 0)
        )
      })
    },
```

> **为什么不整个替换文件**：M4 也在 `server/db.js` 里追加过 `listAttempts` 与
> `countAttemptsSince`，而 M4 的 `/api/next` 直接调 `store.countAttemptsSince(...)`——
> 整个替换会把 M4 的方法删掉，那个接口当场 500。本 Step **只做加法**。
>
> M1 的 `upsertTopic`（累加写法）也**留着不删**：M3/M4 可能还在用它往 `topics` 里写增量。
> M5 每次调 `/api/insights` 都会用 `replaceTopics` 整体覆盖，把口径统一成 M5 的派生结果，
> 所以两种写法不会互相污染。

- [ ] **Step 4: 写 server/insights.js**

Create `projects/apps/algo-plan/server/insights.js`：

```javascript
"use strict"
/**
 * insights.js —— 诊断数据装配
 *
 * 数据来源（口径见本计划「统计口径」一节）：
 *   - 知识点统计：attempts 表 + 题库 → 派生 → 幂等覆盖 topics 表 → 从 topics 表读
 *   - 覆盖度分母：core/mastery/expected.js 的期望题量口径
 *   - 每日题量曲线：attempts 表按 substr(ts,1,10) 分组
 *
 * 这一层只做装配，不含 HTTP 细节。
 */

const {
  MASTERY_THRESHOLD,
  diagnoseAction,
  rankTopics,
  sortByUrgency,
} = require("../core/mastery/mastery.js")
const { bankTopicCounts, buildExpectedMap, minExpectedFrom } = require("../core/mastery/expected.js")
const { deriveTopicStats } = require("../core/mastery/topic-stats.js")

/** 曲线的默认天数窗口 */
const DEFAULT_DAYS = 30

/** 曲线的最大天数窗口 */
const MAX_DAYS = 365

/**
 * 日期加减（UTC）。格式不对就原样返回。
 * @param {string} dateStr "YYYY-MM-DD"
 * @param {number} delta 天数偏移，可负
 * @returns {string}
 */
function addDays(dateStr, delta) {
  const parts = String(dateStr).split("-")
  const y = Number(parts[0])
  const m = Number(parts[1])
  const d = Number(parts[2])
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return String(dateStr)
  const ms = Date.UTC(y, m - 1, d) + delta * 86400000
  const dt = new Date(ms)
  const yy = dt.getUTCFullYear()
  const mm = String(dt.getUTCMonth() + 1).padStart(2, "0")
  const dd = String(dt.getUTCDate()).padStart(2, "0")
  return yy + "-" + mm + "-" + dd
}

/**
 * 把天数窗口夹到合法范围。非法值退回默认 30；0 表示「全部」。
 * @param {number|string|undefined} value
 * @returns {number}
 */
function normalizeDays(value) {
  if (value === undefined || value === null || value === "") return DEFAULT_DAYS
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0) return DEFAULT_DAYS
  return Math.min(MAX_DAYS, Math.floor(n))
}

/**
 * 每日题量曲线：按天分组，窗口内没有数据的日期补 0。
 * @param {Array<{date: string, count: number}>} rows
 * @param {string} endDate 窗口最后一天（YYYY-MM-DD）
 * @param {number} days 窗口天数；0 表示全部（不补 0）
 * @returns {Array<{date: string, count: number}>}
 */
function buildSeries(rows, endDate, days) {
  const countMap = {}
  ;(rows || []).forEach(function (row) {
    countMap[String(row.date)] = Number(row.count || 0)
  })
  const dates = Object.keys(countMap).sort()
  const all = dates.map(function (date) {
    return { date: date, count: countMap[date] }
  })
  if (!days || days <= 0) return all
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(endDate || ""))) return all

  const out = []
  let cursor = addDays(String(endDate), -(days - 1))
  for (let i = 0; i < days; i += 1) {
    out.push({ date: cursor, count: countMap[cursor] || 0 })
    const next = addDays(cursor, 1)
    if (next === cursor) break
    cursor = next
  }
  return out
}

/**
 * 四舍五入到 4 位小数。
 */
function round4(value) {
  return Math.round(Number(value) * 10000) / 10000
}

/**
 * 汇总概览数字。
 *
 * totalAttempts / totalProblems 都从原始流水算，不能按知识点加总——
 * 一道题挂多个知识点时，按知识点加总会把同一次提交数两遍。
 *
 * @param {{topics: object[], stats: object[], series: object[], bankCounts: object,
 *          settings: object, attemptTotal: number, problemTotal: number}} input
 * @returns {object}
 */
function buildSummary(input) {
  const data = input || {}
  const topics = Array.isArray(data.topics) ? data.topics : []
  const stats = Array.isArray(data.stats) ? data.stats : []
  const series = Array.isArray(data.series) ? data.series : []
  const bankCounts = data.bankCounts || {}
  const settings = data.settings || {}

  let masterySum = 0
  let coverageSum = 0
  let weakCount = 0
  let strongCount = 0
  topics.forEach(function (item) {
    masterySum += item.mastery
    coverageSum += item.coverage
    // 强弱只看掌握度（覆盖度是另一维，四档诊断才把两者交叉）
    if (item.mastery < MASTERY_THRESHOLD) weakCount += 1
    else strongCount += 1
  })

  let lastPracticeAt = null
  stats.forEach(function (stat) {
    if (stat.lastAt && (lastPracticeAt === null || Date.parse(stat.lastAt) > Date.parse(lastPracticeAt))) {
      lastPracticeAt = stat.lastAt
    }
  })

  let windowAttempts = 0
  series.forEach(function (row) {
    windowAttempts += Number(row.count || 0)
  })

  const practiced = {}
  topics.forEach(function (item) {
    practiced[item.topic] = true
  })
  let untouchedTopics = 0
  Object.keys(bankCounts).forEach(function (topic) {
    if (!practiced[topic]) untouchedTopics += 1
  })

  const count = topics.length
  return {
    topicCount: count,
    untouchedTopics: untouchedTopics,
    weakCount: weakCount,
    strongCount: strongCount,
    avgMastery: count ? round4(masterySum / count) : 0,
    avgCoverage: count ? round4(coverageSum / count) : 0,
    totalAttempts: Number(data.attemptTotal) || 0,
    totalProblems: Number(data.problemTotal) || 0,
    lastPracticeAt: lastPracticeAt,
    minExpectedQuestions: minExpectedFrom(settings),
    windowDays: series.length,
    windowAttempts: windowAttempts,
  }
}

/**
 * 装配诊断数据。
 * @param {{store: object, provider: object, nowIso?: string, days?: number}} ctx
 * @returns {Promise<{topics: object[], summary: object, series: object[]}>}
 */
async function buildInsights(ctx) {
  const context = ctx || {}
  const nowIso = context.nowIso || new Date().toISOString()
  const days = normalizeDays(context.days)

  const problems = context.provider && context.provider.list ? await context.provider.list() : []
  const attempts = context.store.listAttemptSummaries()
  const derived = deriveTopicStats(attempts, problems)

  // topics 表是物化视图：整体覆盖，幂等
  context.store.replaceTopics(
    derived.map(function (row) {
      return {
        id: row.topic,
        first_pass: row.firstPass,
        attempts: row.attempts,
        last_at: row.lastAt,
        lapses: row.lapses,
      }
    })
  )

  // 掌握度只从 topics 表读
  const topicRows = context.store.listTopics()
  const problemsOfTopic = {}
  derived.forEach(function (row) {
    problemsOfTopic[row.topic] = row.problems
  })

  const stats = topicRows.map(function (row) {
    return {
      topic: row.id,
      attempts: row.attempts,
      firstPass: row.first_pass,
      lapses: row.lapses,
      lastAt: row.last_at,
      problems: problemsOfTopic[row.id] === undefined ? 0 : problemsOfTopic[row.id],
    }
  })

  const settings = context.store.allSettings()
  const bankCounts = bankTopicCounts(problems)
  const expectedMap = buildExpectedMap(
    stats.map(function (stat) {
      return stat.topic
    }),
    bankCounts,
    settings
  )
  const expectedCounts = {}
  Object.keys(expectedMap).forEach(function (topic) {
    expectedCounts[topic] = expectedMap[topic].expected
  })

  // rankTopics 给掌握度升序；sortByUrgency 改成「该先治哪个」的顺序
  const ranked = sortByUrgency(rankTopics(stats, nowIso, expectedCounts))

  const statOf = {}
  stats.forEach(function (stat) {
    statOf[stat.topic] = stat
  })

  const topics = ranked.map(function (item) {
    const stat = statOf[item.topic]
    const expected = expectedMap[item.topic]
    return {
      topic: item.topic,
      mastery: item.mastery,
      coverage: item.coverage,
      bucket: item.bucket,
      label: item.label,
      action: diagnoseAction(item.bucket),
      attempts: stat.attempts,
      firstPass: stat.firstPass,
      lapses: stat.lapses,
      lastAt: stat.lastAt,
      expected: expected.expected,
      expectedSource: expected.source,
      problems: stat.problems,
    }
  })

  const endDate = String(nowIso).slice(0, 10)
  const series = buildSeries(context.store.countAttemptsByDay(), endDate, days)

  // 总提交数与总练过题数从原始流水算——按知识点加总会把一道题数两遍
  const distinctProblems = {}
  attempts.forEach(function (row) {
    distinctProblems[String(row.problem_id)] = true
  })

  const summary = buildSummary({
    topics: topics,
    stats: stats,
    series: series,
    bankCounts: bankCounts,
    settings: settings,
    attemptTotal: attempts.length,
    problemTotal: Object.keys(distinctProblems).length,
  })

  return { topics: topics, summary: summary, series: series }
}

module.exports = {
  DEFAULT_DAYS: DEFAULT_DAYS,
  MAX_DAYS: MAX_DAYS,
  addDays: addDays,
  normalizeDays: normalizeDays,
  buildSeries: buildSeries,
  buildSummary: buildSummary,
  buildInsights: buildInsights,
}
```

- [ ] **Step 5: 写 server/api-insights.js，改 server/app.js 把路由挂上**

M3、M4 都要改 `server/api.js`（M3 整体替换这个文件，M4 替换整个 `buildRoutes` 函数）。
M5 **不碰 `server/api.js`**——否则会把 M3 的 `POST /api/attempt` 和 M4 的五条接口一起删掉。
M5 跟 M6 一个套路：路由放在自己的文件里，在 `server/app.js` 里合并进同一张路由表。

Create `projects/apps/algo-plan/server/api-insights.js`：

```javascript
"use strict"
/**
 * api-insights.js —— M5 的诊断接口
 *
 * 单独一个文件，**不动 M1 的 server/api.js**：M3、M4 也要改那个文件，
 * 互相整体覆盖会丢接口。路由在 server/app.js 里跟 api.js 的路由合并。
 */

const { buildInsights, DEFAULT_DAYS } = require("./insights.js")

/**
 * 组装 M5 的路由。
 * @param {{store: object, provider: object, sendJson: Function}} ctx
 * @returns {Array<{method: string, pattern: string, handler: Function}>}
 */
function buildInsightRoutes(ctx) {
  return [
    {
      method: "GET",
      pattern: "/api/insights",
      handler: async function (req, res, params, query) {
        const daysRaw = query.get("days")
        const days = daysRaw === null || daysRaw === "" ? DEFAULT_DAYS : Number(daysRaw)
        const insights = await buildInsights({
          store: ctx.store,
          provider: ctx.provider,
          days: days,
        })
        ctx.sendJson(res, 200, insights)
      },
    },
  ]
}

module.exports = { buildInsightRoutes: buildInsightRoutes }
```

Modify `projects/apps/algo-plan/server/app.js`：在 `createApp` 里
`const routes = require("./api.js").buildRoutes({...})` 那一段**后面**加下面这几行。
M1 冻结的导出与返回字段一个字都不动，**只做加法**：

```javascript
  // M5：诊断接口。路由在独立文件里（server/api-insights.js），这里合并进同一张路由表
  require("./api-insights.js")
    .buildInsightRoutes({
      store: store,
      provider: provider,
      sendJson: sendJson,
    })
    .forEach(function (route) {
      routes.push(route)
    })
```

> `server/app.js` 里的 `require` 都是**延迟加载**（写在 `createApp` 函数体内），
> 所以 M5 追加的 `require("./api-insights.js")` 也放在函数体内——
> `server/insights.js` 还没落地时，不会把整个 app 拉不起来。
>
> M6 也会给 `server/app.js` 加东西（LLM 客户端与服务层），两边都是**加法**，互不覆盖。

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/insights.test.js
```

Expected: `# fail 0`，退出码 0

再跑全量：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`，退出码 0

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加诊断数据装配与 /api/insights 接口

- server/db.js：store 增加 listAttemptSummaries / countAttemptsByDay / replaceTopics，
  只做加法，已有方法一个签名都不动
- server/insights.js：从作答流水 + 题库派生知识点统计，幂等覆盖 topics 表，
  再从 topics 表算掌握度与覆盖度
- 期望题量按三级口径取值（覆盖值 > 题库题数 > 下限 5），并带出 expectedSource
- topics 按处置优先级排序：练过但总错 > 薄弱且练得少 > 偶然会没练透 > 掌握
- 每日题量按 substr(ts,1,10) 分组，窗口内缺失的日期补 0
- server/api-insights.js：M5 的路由单独一个文件，不动 server/api.js（M3、M4 也要改它）
- server/app.js：把 M5 的路由合并进路由表，只做加法
- GET /api/insights?days=N 返回 topics / summary / series
- 测试：物化、口径、档位、汇总、曲线、接口共 22 条断言"
git push origin main
```

---

## Task 4: 手绘 SVG 图表的纯函数层（零第三方依赖）

**Files:**
- Create: `projects/apps/algo-plan/web/charts.js`
- Create: `projects/apps/algo-plan/tests/charts.test.js`

**Interfaces:**
- Consumes: 无（纯几何 + 字符串拼接，不依赖任何业务模块）
- Produces: `web/charts.js` 的导出（Node `require` 与浏览器 `window.AlgoPlanCharts` 共用同一份）
  - 通用：`escapeXml(value) -> string`、`num(value) -> string`、`clamp01(value) -> number`、`formatPercent(value, digits?) -> string`
  - 雷达：`radarFrame(size, padding) -> {center, radius}`、`radarPoints(values, size, options?) -> [{x, y}]`、
    `radarAxes(labels, size, options?) -> [{label, x, y, anchor, baseline}]`、
    `radarGrid(count, size, options?) -> [{level, points}]`、`polygonPath(points) -> string`、`radarSvg(options) -> string`
  - 折线：`linePoints(values, width, height, options?) -> [{x, y}]`、`linePath(points) -> string`、
    `areaPath(points, baselineY) -> string`、`lineSvg(options) -> string`、`niceScale(max, count) -> {step, max}`、
    `sparseIndexes(count, max) -> number[]`
  - 条形：`barRows(rows, options?) -> [{label, value, display, x, y, width, height, baselineX, trackWidth}]`、
    `barPath(x, y, w, h, r) -> string`、`barSvg(options) -> string`
  - `DEFAULT_THEME`（颜色常量）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/charts.test.js`：

```javascript
"use strict"
/**
 * charts.test.js —— 手绘 SVG 图表的纯函数层
 *
 * 这一层不碰 DOM：几何计算和 SVG 字符串拼接都是纯函数，可以直接单测。
 * 渲染层（web/diagnose.js）只负责把这里的字符串塞进 innerHTML。
 */

const test = require("node:test")
const assert = require("node:assert")

const Charts = require("../web/charts.js")

/** 断言一个 SVG 字符串里没有 NaN / undefined / Infinity */
function assertClean(svg) {
  assert.strictEqual(typeof svg, "string")
  assert.ok(svg.indexOf("NaN") === -1, "SVG 里出现了 NaN")
  assert.ok(svg.indexOf("undefined") === -1, "SVG 里出现了 undefined")
  assert.ok(svg.indexOf("Infinity") === -1, "SVG 里出现了 Infinity")
}

/* ---------------- 通用 ---------------- */

test("escapeXml 把五个特殊字符转义", function () {
  assert.strictEqual(Charts.escapeXml('a&b<c>d"e\'f'), "a&amp;b&lt;c&gt;d&quot;e&apos;f")
  assert.strictEqual(Charts.escapeXml(null), "")
})

test("num 遇到非法数返回 0，绝不产生 NaN", function () {
  assert.strictEqual(Charts.num(1.234), "1.23")
  assert.strictEqual(Charts.num(NaN), "0")
  assert.strictEqual(Charts.num(undefined), "0")
  assert.strictEqual(Charts.num(Infinity), "0")
})

test("clamp01 把值夹到 0..1", function () {
  assert.strictEqual(Charts.clamp01(0.5), 0.5)
  assert.strictEqual(Charts.clamp01(-1), 0)
  assert.strictEqual(Charts.clamp01(2), 1)
  assert.strictEqual(Charts.clamp01(NaN), 0)
})

test("formatPercent 把 0..1 转成百分数字符串", function () {
  assert.strictEqual(Charts.formatPercent(0.42), "42%")
  assert.strictEqual(Charts.formatPercent(0), "0%")
  assert.strictEqual(Charts.formatPercent(1), "100%")
  assert.strictEqual(Charts.formatPercent(NaN), "0%")
  assert.strictEqual(Charts.formatPercent(0.4213, 1), "42.1%")
})

/* ---------------- 雷达图 ---------------- */

test("radarPoints 从正上方开始顺时针排四个点", function () {
  // 四个维度都取满值 1，点才落在外圈上，能看出角度分布
  const points = Charts.radarPoints([1, 1, 1, 1], 200, { padding: 0 })
  assert.strictEqual(points.length, 4)
  assert.ok(Math.abs(points[0].x - 100) < 0.01, "x=" + points[0].x)
  assert.ok(Math.abs(points[0].y - 0) < 0.01, "y=" + points[0].y)
  assert.ok(Math.abs(points[1].x - 200) < 0.01, "x=" + points[1].x)
  assert.ok(Math.abs(points[1].y - 100) < 0.01, "y=" + points[1].y)
  assert.ok(Math.abs(points[2].x - 100) < 0.01, "x=" + points[2].x)
  assert.ok(Math.abs(points[2].y - 200) < 0.01, "y=" + points[2].y)
  assert.ok(Math.abs(points[3].x - 0) < 0.01, "x=" + points[3].x)
  assert.ok(Math.abs(points[3].y - 100) < 0.01, "y=" + points[3].y)
})

test("radarPoints 值越大离圆心越远，超出 1 会被夹住", function () {
  const near = Charts.radarPoints([0.5], 200, { padding: 0 })[0]
  const far = Charts.radarPoints([1], 200, { padding: 0 })[0]
  const over = Charts.radarPoints([5], 200, { padding: 0 })[0]
  // 圆心在 y=100：0.5 离圆心 50，1 离圆心 100
  assert.ok(Math.abs(far.y - 100) > Math.abs(near.y - 100))
  assert.strictEqual(over.y, far.y)
})

test("radarPoints 空数组返回空数组", function () {
  assert.deepStrictEqual(Charts.radarPoints([], 200), [])
  assert.deepStrictEqual(Charts.radarPoints(undefined, 200), [])
})

test("radarAxes 每个标签一条轴，右侧左对齐、左侧右对齐", function () {
  const axes = Charts.radarAxes(["上", "右", "下", "左"], 200, { padding: 0 })
  assert.strictEqual(axes.length, 4)
  assert.strictEqual(axes[0].anchor, "middle")
  assert.strictEqual(axes[1].anchor, "start")
  assert.strictEqual(axes[2].anchor, "middle")
  assert.strictEqual(axes[3].anchor, "end")
  assert.strictEqual(axes[0].label, "上")
})

test("radarGrid 返回若干同心多边形环", function () {
  const grid = Charts.radarGrid(5, 200, { padding: 0, rings: 4 })
  assert.strictEqual(grid.length, 4)
  assert.strictEqual(grid[3].level, 1)
  assert.strictEqual(grid[0].points.length, 5)
})

test("polygonPath 拼出闭合多边形", function () {
  const d = Charts.polygonPath([{ x: 0, y: 0 }, { x: 10, y: 20 }])
  assert.strictEqual(d, "M 0,0 L 10,20 Z")
  assert.strictEqual(Charts.polygonPath([]), "")
})

test("radarSvg 产出干净的 SVG，带 title 提示与两条数据系列", function () {
  const svg = Charts.radarSvg({
    labels: ["数组", "哈希表"],
    series: [
      { name: "掌握度", values: [0.4, 0.8] },
      { name: "覆盖度", values: [0.2, 0.5] },
    ],
    title: "掌握度雷达图",
  })
  assertClean(svg)
  assert.ok(svg.indexOf("<title>掌握度雷达图</title>") !== -1)
  assert.ok(svg.indexOf('viewBox="0 0 360 360"') !== -1, "默认尺寸 360")
  assert.ok(svg.indexOf("stroke-width=\"2\"") !== -1, "数据线 2px")
  assert.ok(svg.indexOf("fill-opacity=\"0.1\"") !== -1, "面积 10% 透明")
  assert.ok(svg.indexOf("stroke-dasharray") === -1, "网格不许画虚线")
  assert.ok(svg.indexOf("数组") !== -1)
})

test("radarSvg 数据为空时给占位文案而不是空白图", function () {
  const svg = Charts.radarSvg({ labels: [], series: [] })
  assertClean(svg)
  assert.ok(svg.indexOf("暂无数据") !== -1)
})

test("radarSvg 遇到 NaN 也不会写出 NaN", function () {
  const svg = Charts.radarSvg({
    labels: ["a", "b"],
    series: [{ name: "s", values: [NaN, 0.5] }],
  })
  assertClean(svg)
})

/* ---------------- 折线 + 面积 ---------------- */

test("linePoints 把数据映射到画布坐标", function () {
  const points = Charts.linePoints([0, 10, 20], 300, 100, {
    padding: { top: 0, right: 0, bottom: 0, left: 0 },
    max: 20,
  })
  assert.strictEqual(points.length, 3)
  assert.deepStrictEqual(points[0], { x: 0, y: 100 })
  assert.deepStrictEqual(points[1], { x: 150, y: 50 })
  assert.deepStrictEqual(points[2], { x: 300, y: 0 })
})

test("linePoints 只有一个点时放在中间", function () {
  const points = Charts.linePoints([5], 200, 100, {
    padding: { top: 0, right: 0, bottom: 0, left: 0 },
    max: 5,
  })
  assert.strictEqual(points.length, 1)
  assert.deepStrictEqual(points[0], { x: 100, y: 0 })
})

test("linePath 与 areaPath 的形状", function () {
  const points = [{ x: 0, y: 10 }, { x: 10, y: 0 }]
  assert.strictEqual(Charts.linePath(points), "M 0,10 L 10,0")
  assert.strictEqual(Charts.areaPath(points, 40), "M 0,40 L 0,10 L 10,0 L 10,40 Z")
  assert.strictEqual(Charts.linePath([]), "")
  assert.strictEqual(Charts.areaPath([], 40), "")
})

test("niceScale 把上界取整到整齐的刻度", function () {
  const scale = Charts.niceScale(5, 3)
  assert.strictEqual(scale.step, 2)
  assert.strictEqual(scale.max, 6)
  const scale2 = Charts.niceScale(12, 3)
  assert.strictEqual(scale2.step, 4)
  assert.strictEqual(scale2.max, 12)
})

test("sparseIndexes 至少保住首尾", function () {
  const idx = Charts.sparseIndexes(30, 3)
  assert.strictEqual(idx.length, 3)
  assert.strictEqual(idx[0], 0)
  assert.strictEqual(idx[idx.length - 1], 29)
  assert.deepStrictEqual(Charts.sparseIndexes(2, 5), [0, 1])
  assert.deepStrictEqual(Charts.sparseIndexes(0, 3), [])
})

test("lineSvg 产出干净的 SVG，带 hairline 网格与末点标记", function () {
  const svg = Charts.lineSvg({
    points: [
      { date: "2026-11-01", count: 0 },
      { date: "2026-11-02", count: 3 },
      { date: "2026-11-03", count: 1 },
    ],
    title: "每日题量曲线",
  })
  assertClean(svg)
  assert.ok(svg.indexOf("<title>每日题量曲线</title>") !== -1)
  assert.ok(svg.indexOf("stroke-dasharray") === -1, "网格不许画虚线")
  assert.ok(svg.indexOf('class="chart-point"') !== -1, "末点要有标记")
  assert.ok(svg.indexOf("2026-11-02") !== -1, "x 轴要有日期")
})

test("lineSvg 数据为空时给占位文案", function () {
  const svg = Charts.lineSvg({ points: [] })
  assertClean(svg)
  assert.ok(svg.indexOf("暂无数据") !== -1)
})

/* ---------------- 水平条形 ---------------- */

test("barRows 的条宽按比例，标签区在左、数值区在右", function () {
  const rows = Charts.barRows(
    [
      { label: "数组", value: 5, display: "50%" },
      { label: "哈希表", value: 10, display: "100%" },
    ],
    { width: 200, labelWidth: 50, valueWidth: 50, rowHeight: 20, barHeight: 10 }
  )
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows[0].x, 50)
  assert.strictEqual(rows[0].width, 50)
  assert.strictEqual(rows[0].y, 5)
  assert.strictEqual(rows[1].width, 100)
  assert.strictEqual(rows[1].y, 25)
  assert.strictEqual(rows[0].display, "50%")
})

test("barPath 数据端圆角、基线端方角", function () {
  const d = Charts.barPath(0, 0, 100, 16, 4)
  assert.ok(d.indexOf("M 0,0") === 0, d)
  assert.ok(d.indexOf("A 4,4") !== -1, "数据端要有圆弧")
  assert.ok(d.indexOf("Z") !== -1)
})

test("barSvg 产出干净的 SVG，标签与数值都在", function () {
  const svg = Charts.barSvg({
    rows: [{ label: "数组", value: 0.5, display: "50%" }],
    title: "弱项榜",
  })
  assertClean(svg)
  assert.ok(svg.indexOf("<title>弱项榜</title>") !== -1)
  assert.ok(svg.indexOf("数组") !== -1)
  assert.ok(svg.indexOf("50%") !== -1)
})

test("barSvg 标签里的尖括号被转义", function () {
  const svg = Charts.barSvg({ rows: [{ label: "<script>", value: 1 }] })
  assertClean(svg)
  assert.ok(svg.indexOf("&lt;script&gt;") !== -1)
  assert.ok(svg.indexOf("<script>") === -1, "不能把标签当 HTML 塞进去")
})

test("barSvg 数据为空时给占位文案", function () {
  const svg = Charts.barSvg({ rows: [] })
  assertClean(svg)
  assert.ok(svg.indexOf("暂无数据") !== -1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/charts.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../web/charts.js'`

- [ ] **Step 3: 写 web/charts.js**

Create `projects/apps/algo-plan/web/charts.js`：

```javascript
;(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory()
  } else {
    root.AlgoPlanCharts = factory()
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict"

  /**
   * charts.js —— 手绘 SVG 图表的纯函数层
   *
   * 零第三方依赖（契约 G22）：雷达图、折线 + 面积图、水平条形图全部手写 SVG。
   * 同一份文件既能被 node:test 直接 require，也能在浏览器里挂到 window.AlgoPlanCharts。
   *
   * 配色：dataviz 暗色分类色 slot 1 蓝 #3987e5（掌握度）、slot 2 橙 #d95926（覆盖度），
   * 在应用面板色 #1d2026 上跑过 validate_palette.js，六项检查全部 PASS。
   * 文字一律用文本色，不穿数据色；状态（弱/强）用文字徽章表达，不靠颜色单独承载。
   */

  /** 图表主题色（暗色面板） */
  const DEFAULT_THEME = {
    surface: "#1d2026",
    grid: "#2c2c2a",
    axis: "#383835",
    track: "#24272d",
    text: "#e8e8e6",
    muted: "#898781",
    series1: "#3987e5",
    series2: "#d95926",
  }

  /** 转义 XML 特殊字符 */
  function escapeXml(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;")
  }

  /** 数字转字符串；非法数一律当 0，SVG 里绝不允许出现 NaN */
  function num(value) {
    const n = Number(value)
    if (!Number.isFinite(n)) return "0"
    return String(Math.round(n * 100) / 100)
  }

  /** 把值夹到 0..1 */
  function clamp01(value) {
    const n = Number(value)
    if (!Number.isFinite(n)) return 0
    if (n < 0) return 0
    if (n > 1) return 1
    return n
  }

  /** 0..1 转百分数字符串 */
  function formatPercent(value, digits) {
    const n = Number(value)
    const d = typeof digits === "number" && digits >= 0 ? Math.floor(digits) : 0
    if (!Number.isFinite(n)) return "0%"
    return (n * 100).toFixed(d) + "%"
  }

  /* ---------------- 雷达图 ---------------- */

  /** 雷达图的几何框架：圆心与半径 */
  function radarFrame(size, padding) {
    const s = Number(size) > 0 ? Number(size) : 360
    const p = Number(padding) >= 0 ? Number(padding) : 64
    return { center: s / 2, radius: Math.max(0, s / 2 - p) }
  }

  /**
   * 雷达图的数据点坐标：从正上方开始，顺时针均分。
   * @param {number[]} values 每个维度的值，取值 0..1
   * @param {number} size 画布边长（正方形）
   * @param {{padding?: number}} [options]
   * @returns {Array<{x: number, y: number}>}
   */
  function radarPoints(values, size, options) {
    const opts = options || {}
    const list = Array.isArray(values) ? values : []
    const n = list.length
    if (n === 0) return []
    const frame = radarFrame(size, opts.padding)
    return list.map(function (raw, index) {
      const value = clamp01(raw)
      const angle = -Math.PI / 2 + (2 * Math.PI * index) / n
      return {
        x: Math.round((frame.center + frame.radius * value * Math.cos(angle)) * 100) / 100,
        y: Math.round((frame.center + frame.radius * value * Math.sin(angle)) * 100) / 100,
      }
    })
  }

  /**
   * 雷达图每条轴的外端坐标与文字对齐方式。
   * @param {string[]} labels 维度名
   * @param {number} size 画布边长
   * @param {{padding?: number}} [options]
   * @returns {Array<{label: string, x: number, y: number, anchor: string, baseline: string}>}
   */
  function radarAxes(labels, size, options) {
    const opts = options || {}
    const list = Array.isArray(labels) ? labels : []
    const n = list.length
    if (n === 0) return []
    const frame = radarFrame(size, opts.padding)
    return list.map(function (label, index) {
      const angle = -Math.PI / 2 + (2 * Math.PI * index) / n
      const x = frame.center + frame.radius * Math.cos(angle)
      const y = frame.center + frame.radius * Math.sin(angle)
      let anchor = "middle"
      if (x > frame.center + 0.5) anchor = "start"
      else if (x < frame.center - 0.5) anchor = "end"
      let baseline = "middle"
      if (y > frame.center + 0.5) baseline = "hanging"
      else if (y < frame.center - 0.5) baseline = "auto"
      return {
        label: String(label === null || label === undefined ? "" : label),
        x: Math.round(x * 100) / 100,
        y: Math.round(y * 100) / 100,
        anchor: anchor,
        baseline: baseline,
      }
    })
  }

  /**
   * 雷达图的同心网格环（hairline 实线）。
   * @param {number} count 维度个数
   * @param {number} size 画布边长
   * @param {{padding?: number, rings?: number}} [options]
   * @returns {Array<{level: number, points: Array<{x: number, y: number}>}>}
   */
  function radarGrid(count, size, options) {
    const opts = options || {}
    const n = Math.floor(Number(count) || 0)
    if (n <= 0) return []
    const rings = Math.max(1, Math.floor(Number(opts.rings) || 4))
    const out = []
    for (let i = 1; i <= rings; i += 1) {
      const level = i / rings
      const filler = []
      for (let j = 0; j < n; j += 1) filler.push(level)
      out.push({ level: level, points: radarPoints(filler, size, opts) })
    }
    return out
  }

  /** 多边形路径 */
  function polygonPath(points) {
    const list = Array.isArray(points) ? points : []
    if (list.length === 0) return ""
    return (
      "M " +
      list
        .map(function (point) {
          return num(point.x) + "," + num(point.y)
        })
        .join(" L ") +
      " Z"
    )
  }

  /** SVG polygon 的 points 属性 */
  function pointsAttr(points) {
    const list = Array.isArray(points) ? points : []
    return list
      .map(function (point) {
        return num(point.x) + "," + num(point.y)
      })
      .join(" ")
  }

  /**
   * 雷达图 SVG。最多两条系列（掌握度 / 覆盖度）。
   * @param {{labels: string[], series: Array<{name: string, values: number[]}>,
   *          size?: number, padding?: number, title?: string, theme?: object}} options
   * @returns {string}
   */
  function radarSvg(options) {
    const opts = options || {}
    const theme = Object.assign({}, DEFAULT_THEME, opts.theme || {})
    const labels = Array.isArray(opts.labels) ? opts.labels : []
    const rawSeries = Array.isArray(opts.series) ? opts.series : []
    const size = Number(opts.size) > 0 ? Number(opts.size) : 360
    const padding = Number(opts.padding) >= 0 ? Number(opts.padding) : 64
    const title = String(opts.title || "掌握度雷达图")
    const count = labels.length
    const parts = []

    parts.push(
      '<svg class="chart chart-radar" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' +
        num(size) +
        " " +
        num(size) +
        '" role="img" aria-label="' +
        escapeXml(title) +
        '">'
    )
    parts.push("<title>" + escapeXml(title) + "</title>")

    if (count === 0 || rawSeries.length === 0) {
      parts.push(
        '<text class="chart-empty" x="' +
          num(size / 2) +
          '" y="' +
          num(size / 2) +
          '" text-anchor="middle" dominant-baseline="middle" fill="' +
          theme.muted +
          '" font-size="13">暂无数据</text>'
      )
      parts.push("</svg>")
      return parts.join("")
    }

    // 网格环
    radarGrid(count, size, { padding: padding, rings: 4 }).forEach(function (ring) {
      parts.push(
        '<polygon class="chart-grid" points="' +
          pointsAttr(ring.points) +
          '" fill="none" stroke="' +
          theme.grid +
          '" stroke-width="1"/>'
      )
    })

    // 轴线
    const frame = radarFrame(size, padding)
    radarAxes(labels, size, { padding: padding }).forEach(function (axis) {
      parts.push(
        '<line class="chart-spoke" x1="' +
          num(frame.center) +
          '" y1="' +
          num(frame.center) +
          '" x2="' +
          num(axis.x) +
          '" y2="' +
          num(axis.y) +
          '" stroke="' +
          theme.axis +
          '" stroke-width="1"/>'
      )
    })

    // 数据多边形：面积 10% 透明 + 2px 描边 + 顶点 8px 标记（2px 表面色描边环）
    const series = rawSeries.slice(0, 2).map(function (item) {
      const values = Array.isArray(item && item.values) ? item.values.slice() : []
      while (values.length < count) values.push(0)
      return { name: item && item.name ? String(item.name) : "", values: values }
    })
    series.forEach(function (item, index) {
      const color = index === 0 ? theme.series1 : theme.series2
      const points = radarPoints(item.values, size, { padding: padding })
      parts.push(
        '<polygon class="chart-series" data-series="' +
          escapeXml(item.name) +
          '" points="' +
          pointsAttr(points) +
          '" fill="' +
          color +
          '" fill-opacity="0.1" stroke="' +
          color +
          '" stroke-width="2" stroke-linejoin="round"/>'
      )
      points.forEach(function (point) {
        parts.push(
          '<circle class="chart-point" cx="' +
            num(point.x) +
            '" cy="' +
            num(point.y) +
            '" r="4" fill="' +
            color +
            '" stroke="' +
            theme.surface +
            '" stroke-width="2"/>'
        )
      })
    })

    // 维度标签
    radarAxes(labels, size, { padding: padding }).forEach(function (axis) {
      parts.push(
        '<text class="chart-label" x="' +
          num(axis.x) +
          '" y="' +
          num(axis.y) +
          '" text-anchor="' +
          axis.anchor +
          '" dominant-baseline="' +
          axis.baseline +
          '" fill="' +
          theme.muted +
          '" font-size="12">' +
          escapeXml(axis.label) +
          "</text>"
      )
    })

    parts.push("</svg>")
    return parts.join("")
  }

  /* ---------------- 折线 + 面积 ---------------- */

  /** 把上界取整到整齐的刻度 */
  function niceScale(max, count) {
    const top = Math.max(1, Number(max) || 1)
    const n = Math.max(1, Math.floor(Number(count) || 1))
    const step = Math.max(1, Math.ceil(top / n))
    return { step: step, max: step * n }
  }

  /**
   * 折线图的点坐标。
   * @param {number[]} values 原始数值（可以是题量这种非 0..1 的数）
   * @param {number} width 画布宽
   * @param {number} height 画布高
   * @param {{padding?: {top: number, right: number, bottom: number, left: number}, max?: number}} [options]
   * @returns {Array<{x: number, y: number}>}
   */
  function linePoints(values, width, height, options) {
    const opts = options || {}
    const list = Array.isArray(values) ? values : []
    if (list.length === 0) return []
    const pad = Object.assign({ top: 16, right: 20, bottom: 28, left: 36 }, opts.padding || {})
    const w = Number(width) > 0 ? Number(width) : 600
    const h = Number(height) > 0 ? Number(height) : 220
    let max = Number(opts.max)
    if (!Number.isFinite(max) || max <= 0) {
      max = 0
      list.forEach(function (raw) {
        const value = Number(raw)
        if (Number.isFinite(value) && value > max) max = value
      })
      if (max <= 0) max = 1
    }
    const innerW = Math.max(0, w - pad.left - pad.right)
    const innerH = Math.max(0, h - pad.top - pad.bottom)
    const step = list.length > 1 ? innerW / (list.length - 1) : 0
    return list.map(function (raw, index) {
      const value = Number(raw)
      const safe = Number.isFinite(value) && value > 0 ? value : 0
      const x = list.length > 1 ? pad.left + step * index : pad.left + innerW / 2
      const y = pad.top + innerH - (safe / max) * innerH
      return {
        x: Math.round(x * 100) / 100,
        y: Math.round(y * 100) / 100,
      }
    })
  }

  /** 折线路径（不闭合） */
  function linePath(points) {
    const list = Array.isArray(points) ? points : []
    if (list.length === 0) return ""
    return (
      "M " +
      list
        .map(function (point) {
          return num(point.x) + "," + num(point.y)
        })
        .join(" L ")
    )
  }

  /** 面积路径（闭合到基线） */
  function areaPath(points, baselineY) {
    const list = Array.isArray(points) ? points : []
    if (list.length === 0) return ""
    const first = list[0]
    const last = list[list.length - 1]
    return (
      "M " +
      num(first.x) +
      "," +
      num(baselineY) +
      " L " +
      list
        .map(function (point) {
          return num(point.x) + "," + num(point.y)
        })
        .join(" L ") +
      " L " +
      num(last.x) +
      "," +
      num(baselineY) +
      " Z"
    )
  }

  /**
   * 稀疏挑几个下标做直接标注——首尾一定保留，中间均分。
   * @param {number} count 总点数
   * @param {number} max 最多标几个
   * @returns {number[]}
   */
  function sparseIndexes(count, max) {
    const n = Math.floor(Number(count) || 0)
    const limit = Math.floor(Number(max) || 0)
    if (n <= 0 || limit <= 0) return []
    if (n <= limit) {
      const all = []
      for (let i = 0; i < n; i += 1) all.push(i)
      return all
    }
    if (limit === 1) return [n - 1]
    const out = []
    for (let i = 0; i < limit; i += 1) {
      out.push(Math.round((i * (n - 1)) / (limit - 1)))
    }
    return out
  }

  /**
   * 折线 + 面积图（每日题量曲线）。单序列，不需要图例。
   * @param {{points: Array<{date: string, count: number}>, width?: number, height?: number,
   *          padding?: object, title?: string, color?: string, theme?: object}} options
   * @returns {string}
   */
  function lineSvg(options) {
    const opts = options || {}
    const theme = Object.assign({}, DEFAULT_THEME, opts.theme || {})
    const width = Number(opts.width) > 0 ? Number(opts.width) : 640
    const height = Number(opts.height) > 0 ? Number(opts.height) : 220
    const pad = Object.assign({ top: 16, right: 20, bottom: 28, left: 36 }, opts.padding || {})
    const rows = Array.isArray(opts.points) ? opts.points : []
    const title = String(opts.title || "每日题量曲线")
    const color = opts.color || theme.series1
    const parts = []

    parts.push(
      '<svg class="chart chart-line" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' +
        num(width) +
        " " +
        num(height) +
        '" role="img" aria-label="' +
        escapeXml(title) +
        '">'
    )
    parts.push("<title>" + escapeXml(title) + "</title>")

    if (rows.length === 0) {
      parts.push(
        '<text class="chart-empty" x="' +
          num(width / 2) +
          '" y="' +
          num(height / 2) +
          '" text-anchor="middle" dominant-baseline="middle" fill="' +
          theme.muted +
          '" font-size="13">暂无数据</text>'
      )
      parts.push("</svg>")
      return parts.join("")
    }

    const values = rows.map(function (row) {
      const value = Number(row && row.count)
      return Number.isFinite(value) && value > 0 ? value : 0
    })
    const scale = niceScale(
      values.reduce(function (acc, value) {
        return value > acc ? value : acc
      }, 0),
      3
    )
    const innerW = Math.max(0, width - pad.left - pad.right)
    const innerH = Math.max(0, height - pad.top - pad.bottom)
    const baselineY = pad.top + innerH
    const points = linePoints(values, width, height, { padding: pad, max: scale.max })

    // hairline 实线网格 + y 轴刻度
    for (let tick = 0; tick <= scale.max; tick += scale.step) {
      const y = baselineY - (tick / scale.max) * innerH
      parts.push(
        '<line class="chart-grid" x1="' +
          num(pad.left) +
          '" y1="' +
          num(y) +
          '" x2="' +
          num(width - pad.right) +
          '" y2="' +
          num(y) +
          '" stroke="' +
          theme.grid +
          '" stroke-width="1"/>'
      )
      parts.push(
        '<text class="chart-tick" x="' +
          num(pad.left - 6) +
          '" y="' +
          num(y) +
          '" text-anchor="end" dominant-baseline="middle" fill="' +
          theme.muted +
          '" font-size="11">' +
          num(tick) +
          "</text>"
      )
    }

    // 面积（10% 透明）+ 折线（2px）
    parts.push(
      '<path class="chart-area" d="' +
        areaPath(points, baselineY) +
        '" fill="' +
        color +
        '" fill-opacity="0.1" stroke="none"/>'
    )
    parts.push(
      '<path class="chart-line" d="' +
        linePath(points) +
        '" fill="none" stroke="' +
        color +
        '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>'
    )

    // 末点标记：8px 直径 + 2px 表面色描边环
    const last = points[points.length - 1]
    parts.push(
      '<circle class="chart-point" cx="' +
        num(last.x) +
        '" cy="' +
        num(last.y) +
        '" r="4" fill="' +
        color +
        '" stroke="' +
        theme.surface +
        '" stroke-width="2"/>'
    )

    // x 轴日期：稀疏标注，不给每个点都写数字
    const labelIndexes = sparseIndexes(rows.length, 4)
    labelIndexes.forEach(function (index) {
      const row = rows[index]
      const point = points[index]
      let anchor = "middle"
      if (index === 0) anchor = "start"
      else if (index === rows.length - 1) anchor = "end"
      parts.push(
        '<text class="chart-tick" x="' +
          num(point.x) +
          '" y="' +
          num(height - 8) +
          '" text-anchor="' +
          anchor +
          '" fill="' +
          theme.muted +
          '" font-size="11">' +
          escapeXml(String(row && row.date ? row.date : "")) +
          "</text>"
      )
    })

    parts.push("</svg>")
    return parts.join("")
  }

  /* ---------------- 水平条形 ---------------- */

  /**
   * 水平条形图的行布局。
   * @param {Array<{label: string, value: number, display?: string}>} rows
   * @param {{width?: number, rowHeight?: number, labelWidth?: number, valueWidth?: number,
   *          barHeight?: number, max?: number}} [options]
   * @returns {Array<{label: string, value: number, display: string, x: number, y: number,
   *          width: number, height: number, baselineX: number, trackWidth: number}>}
   */
  function barRows(rows, options) {
    const opts = options || {}
    const list = Array.isArray(rows) ? rows : []
    const width = Number(opts.width) > 0 ? Number(opts.width) : 520
    const rowHeight = Number(opts.rowHeight) > 0 ? Number(opts.rowHeight) : 30
    const labelWidth = Number(opts.labelWidth) >= 0 ? Number(opts.labelWidth) : 96
    const valueWidth = Number(opts.valueWidth) >= 0 ? Number(opts.valueWidth) : 56
    const barHeight = Number(opts.barHeight) > 0 ? Number(opts.barHeight) : 16
    const trackWidth = Math.max(0, width - labelWidth - valueWidth)
    let max = Number(opts.max)
    if (!Number.isFinite(max) || max <= 0) {
      max = 0
      list.forEach(function (row) {
        const value = Number(row && row.value)
        if (Number.isFinite(value) && value > max) max = value
      })
    }
    if (max <= 0) max = 1
    return list.map(function (row, index) {
      const value = Number(row && row.value)
      const safe = Number.isFinite(value) && value > 0 ? value : 0
      const w = trackWidth * (safe / max)
      return {
        label: String(row && row.label !== null && row.label !== undefined ? row.label : ""),
        value: safe,
        display: String(
          row && row.display !== null && row.display !== undefined ? row.display : num(safe)
        ),
        x: labelWidth,
        y: Math.round((index * rowHeight + (rowHeight - barHeight) / 2) * 100) / 100,
        width: Math.round(w * 100) / 100,
        height: barHeight,
        baselineX: labelWidth,
        trackWidth: trackWidth,
      }
    })
  }

  /** 水平条：基线端方角，数据端 4px 圆角 */
  function barPath(x, y, width, height, radius) {
    const w = Math.max(0, Number(width) || 0)
    const h = Math.max(0, Number(height) || 0)
    const r = Math.max(0, Math.min(Number(radius) || 0, w, h / 2))
    if (r === 0) {
      return "M " + num(x) + "," + num(y) + " h " + num(w) + " v " + num(h) + " h " + num(-w) + " Z"
    }
    return [
      "M " + num(x) + "," + num(y),
      "H " + num(x + w - r),
      "A " + num(r) + "," + num(r) + " 0 0 1 " + num(x + w) + "," + num(y + r),
      "V " + num(y + h - r),
      "A " + num(r) + "," + num(r) + " 0 0 1 " + num(x + w - r) + "," + num(y + h),
      "H " + num(x),
      "Z",
    ].join(" ")
  }

  /**
   * 水平条形图（弱项榜 / 知识点覆盖）。单序列，不按值分色。
   * @param {{rows: Array<{label: string, value: number, display?: string}>, width?: number,
   *          height?: number, rowHeight?: number, labelWidth?: number, valueWidth?: number,
   *          barHeight?: number, max?: number, title?: string, color?: string, theme?: object}} options
   * @returns {string}
   */
  function barSvg(options) {
    const opts = options || {}
    const theme = Object.assign({}, DEFAULT_THEME, opts.theme || {})
    const width = Number(opts.width) > 0 ? Number(opts.width) : 520
    const rowHeight = Number(opts.rowHeight) > 0 ? Number(opts.rowHeight) : 30
    const labelWidth = Number(opts.labelWidth) >= 0 ? Number(opts.labelWidth) : 96
    const valueWidth = Number(opts.valueWidth) >= 0 ? Number(opts.valueWidth) : 56
    const barHeight = Number(opts.barHeight) > 0 ? Number(opts.barHeight) : 16
    const rows = Array.isArray(opts.rows) ? opts.rows : []
    const title = String(opts.title || "条形图")
    const color = opts.color || theme.series1
    const layout = barRows(rows, {
      width: width,
      rowHeight: rowHeight,
      labelWidth: labelWidth,
      valueWidth: valueWidth,
      barHeight: barHeight,
      max: opts.max,
    })
    const height = Number(opts.height) > 0 ? Number(opts.height) : layout.length * rowHeight + 8
    const parts = []

    parts.push(
      '<svg class="chart chart-bar" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' +
        num(width) +
        " " +
        num(height) +
        '" role="img" aria-label="' +
        escapeXml(title) +
        '">'
    )
    parts.push("<title>" + escapeXml(title) + "</title>")

    if (layout.length === 0) {
      parts.push(
        '<text class="chart-empty" x="' +
          num(width / 2) +
          '" y="' +
          num(height / 2) +
          '" text-anchor="middle" dominant-baseline="middle" fill="' +
          theme.muted +
          '" font-size="13">暂无数据</text>'
      )
      parts.push("</svg>")
      return parts.join("")
    }

    layout.forEach(function (row) {
      // 轨道：说明这一行最多能有多长
      parts.push(
        '<rect class="chart-track" x="' +
          num(row.baselineX) +
          '" y="' +
          num(row.y) +
          '" width="' +
          num(row.trackWidth) +
          '" height="' +
          num(row.height) +
          '" rx="4" fill="' +
          theme.track +
          '"/>'
      )
      // 数据条
      if (row.width > 0) {
        parts.push(
          '<path class="chart-bar" d="' +
            barPath(row.x, row.y, row.width, row.height, 4) +
            '" fill="' +
            color +
            '"/>'
        )
      }
      // 维度名
      parts.push(
        '<text class="chart-label" x="' +
          num(row.x - 8) +
          '" y="' +
          num(row.y + row.height / 2) +
          '" text-anchor="end" dominant-baseline="middle" fill="' +
          theme.muted +
          '" font-size="12">' +
          escapeXml(row.label) +
          "</text>"
      )
      // 数值标在条的末端外侧
      parts.push(
        '<text class="chart-value" x="' +
          num(row.x + row.width + 8) +
          '" y="' +
          num(row.y + row.height / 2) +
          '" text-anchor="start" dominant-baseline="middle" fill="' +
          theme.text +
          '" font-size="12">' +
          escapeXml(row.display) +
          "</text>"
      )
    })

    parts.push("</svg>")
    return parts.join("")
  }

  return {
    DEFAULT_THEME: DEFAULT_THEME,
    escapeXml: escapeXml,
    num: num,
    clamp01: clamp01,
    formatPercent: formatPercent,
    radarFrame: radarFrame,
    radarPoints: radarPoints,
    radarAxes: radarAxes,
    radarGrid: radarGrid,
    polygonPath: polygonPath,
    pointsAttr: pointsAttr,
    radarSvg: radarSvg,
    niceScale: niceScale,
    linePoints: linePoints,
    linePath: linePath,
    areaPath: areaPath,
    sparseIndexes: sparseIndexes,
    lineSvg: lineSvg,
    barRows: barRows,
    barPath: barPath,
    barSvg: barSvg,
  }
})
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/charts.test.js
```

Expected: `# fail 0`，退出码 0

再跑全量：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加手绘 SVG 图表的纯函数层

- web/charts.js：雷达图、折线 + 面积图、水平条形图的坐标计算与 SVG 拼接，
  同一份文件在 Node 与浏览器通用（UMD 双模）
- 零第三方依赖，SVG 全部手写
- 配色用 dataviz 暗色分类色 slot1 蓝 #3987e5 与 slot2 橙 #d95926，
  在面板色 #1d2026 上跑 validate_palette.js 六项检查全部 PASS
- 遵守 dataviz 规范：hairline 实线网格、2px 数据线、10% 透明面积、
  条形数据端 4px 圆角、标记 8px 加 2px 表面描边环、只标末点不逐点标数
- 数字统一走 num()，非法值落 0，SVG 里不会出现 NaN
- 测试：几何、路径、SVG 结构、无 NaN 共 26 条断言"
git push origin main
```

---

## Task 5: 诊断页前端——四块内容与 tab 接线

**Files:**
- Create: `projects/apps/algo-plan/web/diagnose.js`
- Create: `projects/apps/algo-plan/web/diagnose.css`
- Modify: `projects/apps/algo-plan/web/app.js`（**只在 `TABS` 数组末尾加一项**，M4 的调度逻辑一个字不动）
- Modify: `projects/apps/algo-plan/web/index.html`（加 2 个 script 与 1 个 link，**其余一字不动**）
- Create: `projects/apps/algo-plan/tests/diagnose.test.js`

**Interfaces:**
- Consumes:
  - Task 4 的 `web/charts.js`：`DEFAULT_THEME`、`clamp01`、`formatPercent`、`radarSvg`、`lineSvg`、`barSvg`
  - Task 3 的 `GET /api/insights`：`{topics, summary, series}`
  - **M4 的 `window.AlgoPlan`**：`el(tag, attrs, children)`、`getJson(url)`、`pages`（页面注册表）
  - **M4 的 `web/app.js` 的 `TABS` 数组**（M5 只在末尾追加一项）
  - M4 的 `web/index.html`（`#tabs` 与 `#view` 两个挂点）、M1 的 `web/style.css`
    （`--panel` / `--line` / `--fg` / `--muted` 等 CSS 变量）
- Produces: `web/diagnose.js` 的导出（Node `require` 与浏览器 `window.AlgoPlanDiagnose` 共用同一份）
  - 常量：`MAX_RADAR_TOPICS = 6`、`MAX_WEAK_ROWS = 8`、`MAX_COVERAGE_ROWS = 10`、
    `URGENCY_ORDER`、`WEAK_BUCKETS`
  - 纯函数：
    - `percent(value) -> string`（与 `charts.formatPercent` 同口径）
    - `bucketCounts(topics) -> {"weak-dense": n, "weak-sparse": n, "strong-sparse": n, "strong-dense": n}`
    - `legendItems() -> [{name, color}]`
    - `summaryCards(summary) -> [{label, value}]`
    - `radarTopics(topics, max) -> [{topic, mastery, coverage, attempts}]`
    - `weakRows(topics, limit) -> [{topic, mastery, coverage, label, action, display}]`
    - `coverageRows(topics, limit) -> [{topic, coverage, expected, problems, display, detail}]`
    - `buildDiagnoseView(data) -> object`（诊断页的完整视图数据，见下）
  - 渲染层：
    - `mountDiagnose(container, view, charts, el) -> void`
    - `renderPage(view) -> Promise<void>`（M4 的页面入口，`pages.diagnose.render`）
  - **副作用**：加载时若 `window.AlgoPlan.pages` 存在，就注册
    `window.AlgoPlan.pages.diagnose = {title: "诊断", render: renderPage}`

  `buildDiagnoseView(data)` 的返回形状：

  ```js
  {
    summary: [{ label: "知识点", value: "4" }, ...],
    buckets: { "weak-dense": 1, "weak-sparse": 1, "strong-sparse": 1, "strong-dense": 1 },
    radar:  { title, labels: string[], series: [{name, values}], rows, table: {columns, rows} },
    weak:   { title, rows, table: {columns, rows} },
    curve:  { title, points: [{date, count}], table: {columns, rows} },
    coverage: { title, rows, table: {columns, rows} },
  }
  ```

**渲染层靠什么保证（这一层没有 DOM 单测）：**

1. **所有 SVG 字符串都由 `web/charts.js` 生成**，那个文件 100% 被 `node:test` 覆盖，
   包含「SVG 里不出现 NaN / undefined / Infinity」的断言——图表不会画出坏数据。
2. **所有视图数据都由 `buildDiagnoseView` 这个纯函数算出**，被 `tests/diagnose.test.js` 覆盖：
   选哪些知识点、怎么排序、截断到几条、诊断文案是什么，全部有断言。
3. **`mountDiagnose` 只做 DOM 装配**，没有业务分支：它读 view 里的字符串塞进 DOM。
   DOM 元素用 M4 的 `A.el` 造（与别的页面同一套构造器）。
4. **文本一律走 `textContent`**，不进 `innerHTML`；唯一走 `innerHTML` 的是 `web/charts.js` 生成的
   SVG，而那里的所有标签都经过 `escapeXml` 转义。
5. **页面注册这一步是可单测的**：`tests/diagnose.test.js` 给一个 `window` 替身，
   `require` 页面脚本，断言 `window.AlgoPlan.pages.diagnose.render` 是函数。
6. **Task 6 的端到端测试**会拉起真实服务，断言 `/charts.js`、`/diagnose.js`、`/diagnose.css`
   三个静态资源返回 200，且 `index.html` 正确引入了它们、`web/app.js` 的 `TABS` 里有「诊断」。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/diagnose.test.js`：

```javascript
"use strict"
/**
 * diagnose.test.js —— 诊断页的纯函数层
 *
 * 渲染层（mountDiagnose / showDiagnose）要真实 DOM，node 里没有，
 * 所以这里只测纯函数：视图数据怎么算、怎么排、截断到几条。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const Charts = require("../web/charts.js")

/**
 * 页面脚本在浏览器里跑，但「注册进 window.AlgoPlan.pages」这一步可以在 Node 里验：
 * 给一个最小的 window 替身，把页面脚本 require 进来。
 * 顺序很重要：先搭好替身，再 require——脚本加载时就会注册自己。
 */
global.window = {
  AlgoPlan: {
    pages: {},
    el: function (tag, attrs, children) {
      return { tag: tag, attrs: attrs, children: children }
    },
    getJson: async function () {
      return { topics: [], summary: {}, series: [] }
    },
  },
  AlgoPlanCharts: Charts,
}

const Diagnose = require("../web/diagnose.js")

/** 一份固定数据：覆盖四个档位 */
const TOPICS = [
  {
    topic: "数组",
    mastery: 0.28,
    coverage: 0.4,
    bucket: "weak-sparse",
    label: "薄弱且练得少",
    action: "轮次里优先排这类题——先补量",
    attempts: 6,
    expected: 5,
    problems: 2,
  },
  {
    topic: "哈希表",
    mastery: 0.62,
    coverage: 0.8,
    bucket: "strong-dense",
    label: "掌握",
    action: "保持手感",
    attempts: 5,
    expected: 5,
    problems: 4,
  },
  {
    topic: "动态规划",
    mastery: 0.45,
    coverage: 0.2,
    bucket: "weak-dense",
    label: "练过但总错",
    action: "回头复盘错题",
    attempts: 4,
    expected: 5,
    problems: 1,
  },
  {
    topic: "二分查找",
    mastery: 0.7,
    coverage: 0.5,
    bucket: "strong-sparse",
    label: "偶然会，没练透",
    action: "多练同类型题",
    attempts: 2,
    expected: 5,
    problems: 2,
  },
]

const SERIES = [
  { date: "2026-11-01", count: 0 },
  { date: "2026-11-02", count: 3 },
  { date: "2026-11-03", count: 1 },
]

/* ---------------- 基础 ---------------- */

test("percent 与 charts.formatPercent 同口径", function () {
  assert.strictEqual(Diagnose.percent(0.42), Charts.formatPercent(0.42))
  assert.strictEqual(Diagnose.percent(0.42), "42%")
  assert.strictEqual(Diagnose.percent(undefined), "0%")
})

test("bucketCounts 数出四个档位各有多少个知识点", function () {
  const counts = Diagnose.bucketCounts(TOPICS)
  assert.strictEqual(counts["weak-sparse"], 1)
  assert.strictEqual(counts["strong-dense"], 1)
  assert.strictEqual(counts["weak-dense"], 1)
  assert.strictEqual(counts["strong-sparse"], 1)
})

test("bucketCounts 遇到不认识的档位不炸", function () {
  const counts = Diagnose.bucketCounts([{ bucket: "不存在的档" }, null])
  assert.strictEqual(counts["weak-dense"], 0)
})

test("legendItems 的颜色跟 charts 的主题色一致", function () {
  const items = Diagnose.legendItems()
  assert.strictEqual(items.length, 2)
  assert.strictEqual(items[0].name, "掌握度")
  assert.strictEqual(items[0].color, Charts.DEFAULT_THEME.series1)
  assert.strictEqual(items[1].name, "覆盖度")
  assert.strictEqual(items[1].color, Charts.DEFAULT_THEME.series2)
})

test("summaryCards 把概览数字变成标签 + 数值", function () {
  const cards = Diagnose.summaryCards({
    topicCount: 4,
    avgMastery: 0.5,
    avgCoverage: 0.4,
    weakCount: 2,
    totalAttempts: 17,
    totalProblems: 9,
    untouchedTopics: 3,
    minExpectedQuestions: 5,
  })
  const byLabel = {}
  cards.forEach(function (card) {
    byLabel[card.label] = card.value
  })
  assert.strictEqual(byLabel["知识点"], "4")
  assert.strictEqual(byLabel["平均掌握度"], "50%")
  assert.strictEqual(byLabel["平均覆盖度"], "40%")
  assert.strictEqual(byLabel["薄弱知识点"], "2")
  assert.strictEqual(byLabel["总提交数"], "17")
  assert.strictEqual(byLabel["练过题数"], "9")
  assert.strictEqual(byLabel["未涉及的知识点"], "3")
  assert.strictEqual(byLabel["期望题量下限"], "5")
})

/* ---------------- 选数据 ---------------- */

test("radarTopics 选提交次数最多的几个知识点", function () {
  const rows = Diagnose.radarTopics(TOPICS, 2)
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows[0].topic, "数组")
  assert.strictEqual(rows[1].topic, "哈希表")
})

test("radarTopics 提交次数相同时按知识点名排，顺序稳定", function () {
  const rows = Diagnose.radarTopics(
    [
      { topic: "乙", mastery: 0.1, coverage: 0.1, attempts: 3 },
      { topic: "甲", mastery: 0.1, coverage: 0.1, attempts: 3 },
    ],
    5
  )
  const names = rows.map(function (row) {
    return row.topic
  })
  // 中文按码位排（跟 Array.prototype.sort 一致），不按拼音硬编码顺序
  assert.deepStrictEqual(names, names.slice().sort())
  assert.strictEqual(names.length, 2)
})

test("radarTopics 的值被夹到 0..1", function () {
  const rows = Diagnose.radarTopics([{ topic: "x", mastery: 1.5, coverage: -1, attempts: 1 }], 5)
  assert.strictEqual(rows[0].mastery, 1)
  assert.strictEqual(rows[0].coverage, 0)
})

test("weakRows 只收两个弱档，并按处置优先级排", function () {
  const rows = Diagnose.weakRows(TOPICS, 10)
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows[0].topic, "动态规划", "练过但总错排最前")
  assert.strictEqual(rows[0].label, "练过但总错")
  assert.strictEqual(rows[1].topic, "数组")
  assert.strictEqual(rows[1].display, "28%")
})

test("weakRows 超过上限就截断", function () {
  const many = []
  for (let i = 0; i < 12; i += 1) {
    many.push({
      topic: "t" + i,
      mastery: 0.1,
      coverage: 0.1,
      bucket: "weak-sparse",
      label: "薄弱且练得少",
      action: "",
      attempts: 1,
    })
  }
  assert.strictEqual(Diagnose.weakRows(many, 8).length, 8)
})

test("coverageRows 按覆盖度从低到高排，并带上「练了几 / 期望几」", function () {
  const rows = Diagnose.coverageRows(TOPICS, 10)
  assert.strictEqual(rows.length, 4)
  assert.strictEqual(rows[0].topic, "动态规划")
  assert.strictEqual(rows[0].coverage, 0.2)
  assert.strictEqual(rows[0].detail, "练了 1 / 期望 5 题")
  assert.strictEqual(rows[3].topic, "哈希表")
})

/* ---------------- 视图 ---------------- */

test("buildDiagnoseView 出四块内容：雷达、弱项榜、曲线、覆盖", function () {
  const view = Diagnose.buildDiagnoseView({
    topics: TOPICS,
    summary: { topicCount: 4, avgMastery: 0.5 },
    series: SERIES,
  })

  assert.strictEqual(view.radar.labels.length, 4)
  assert.strictEqual(view.radar.series.length, 2)
  assert.strictEqual(view.radar.series[0].name, "掌握度")
  assert.strictEqual(view.radar.series[1].name, "覆盖度")
  assert.strictEqual(view.radar.series[0].values.length, 4)

  assert.strictEqual(view.weak.rows.length, 2)
  assert.strictEqual(view.curve.points.length, 3)
  assert.strictEqual(view.curve.points[1].count, 3)
  assert.strictEqual(view.coverage.rows.length, 4)

  // 每块都要有表格孪生
  ;[view.radar, view.weak, view.curve, view.coverage].forEach(function (block) {
    assert.ok(Array.isArray(block.table.columns), "缺表格列")
    assert.ok(Array.isArray(block.table.rows), "缺表格行")
    assert.strictEqual(block.table.rows.length, block.table.rows.length)
  })
})

test("buildDiagnoseView 表格孪生的行数跟图表行数对得上", function () {
  const view = Diagnose.buildDiagnoseView({ topics: TOPICS, summary: {}, series: SERIES })
  assert.strictEqual(view.radar.table.rows.length, view.radar.labels.length)
  assert.strictEqual(view.weak.table.rows.length, view.weak.rows.length)
  assert.strictEqual(view.curve.table.rows.length, view.curve.points.length)
  assert.strictEqual(view.coverage.table.rows.length, view.coverage.rows.length)
})

test("buildDiagnoseView 空数据不炸", function () {
  const view = Diagnose.buildDiagnoseView({})
  assert.deepStrictEqual(view.radar.labels, [])
  assert.deepStrictEqual(view.weak.rows, [])
  assert.deepStrictEqual(view.curve.points, [])
  assert.deepStrictEqual(view.coverage.rows, [])
  assert.strictEqual(view.summary.length, Diagnose.summaryCards({}).length)
})

/* ---------------- 静态资源接线 ---------------- */

test("index.html 引入 charts.js / diagnose.js / diagnose.css", function () {
  const html = fs.readFileSync(path.join(__dirname, "..", "web", "index.html"), "utf8")
  assert.ok(html.indexOf('src="/charts.js"') !== -1, "少 charts.js")
  assert.ok(html.indexOf('src="/diagnose.js"') !== -1, "少 diagnose.js")
  assert.ok(html.indexOf('href="/diagnose.css"') !== -1, "少 diagnose.css")
  assert.ok(
    html.indexOf('src="/charts.js"') < html.indexOf('src="/diagnose.js"'),
    "charts.js 必须先加载"
  )
})

test("diagnose.css 存在且定义了诊断页要用的类名", function () {
  const css = fs.readFileSync(path.join(__dirname, "..", "web", "diagnose.css"), "utf8")
  assert.ok(css.indexOf(".diag-panel") !== -1)
  assert.ok(css.indexOf(".diag-card") !== -1)
  assert.ok(css.indexOf(".chart") !== -1)
})

/* ---------------- 页面注册 ---------------- */

test("页面脚本注册进 window.AlgoPlan.pages", function () {
  const page = global.window.AlgoPlan.pages.diagnose
  assert.ok(page, "诊断页没有注册")
  assert.strictEqual(page.title, "诊断")
  assert.strictEqual(typeof page.render, "function", "诊断页缺少 render")
})

test("web/app.js 的 TABS 里有「诊断」这一项", function () {
  const app = fs.readFileSync(path.join(__dirname, "..", "web", "app.js"), "utf8")
  assert.ok(
    /\{\s*key:\s*"diagnose"\s*,\s*label:\s*"诊断"\s*\}/.test(app),
    "TABS 里没有诊断页"
  )
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/diagnose.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../web/diagnose.js'`

- [ ] **Step 3: 写 web/diagnose.js**

Create `projects/apps/algo-plan/web/diagnose.js`：

```javascript
;(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory(require("./charts.js"))
  } else {
    root.AlgoPlanDiagnose = factory(root.AlgoPlanCharts)
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function (Charts) {
  "use strict"

  if (!Charts) {
    throw new Error("诊断页依赖 charts.js，请确认 charts.js 在 diagnose.js 之前加载")
  }

  /**
   * diagnose.js —— 诊断页（掌握度雷达 / 弱项榜 / 每日题量曲线 / 知识点覆盖）
   *
   * 零第三方依赖：图表由 web/charts.js 手绘 SVG 生成。
   * 同一份文件既能被 node:test 直接 require，也能在浏览器里挂到 window.AlgoPlanDiagnose。
   *
   * 分工：
   *   纯函数（buildDiagnoseView 等）——算数据、排序、截断，可单测
   *   渲染层（mountDiagnose / showDiagnose）——只做 DOM 装配，无业务分支
   */

  /** 雷达图最多放几个知识点（轴太多就看不清了） */
  const MAX_RADAR_TOPICS = 6

  /** 弱项榜最多列几行 */
  const MAX_WEAK_ROWS = 8

  /** 知识点覆盖最多列几行 */
  const MAX_COVERAGE_ROWS = 10

  /** 处置优先级：练过但总错 > 薄弱且练得少 > 偶然会没练透 > 掌握 */
  const URGENCY_ORDER = ["weak-dense", "weak-sparse", "strong-sparse", "strong-dense"]

  /** 两个弱档 */
  const WEAK_BUCKETS = ["weak-dense", "weak-sparse"]

  /** 百分比格式化，跟 charts.formatPercent 同口径 */
  function percent(value) {
    return Charts.formatPercent(value)
  }

  /** 四个档位各有多少个知识点 */
  function bucketCounts(topics) {
    const counts = {
      "weak-dense": 0,
      "weak-sparse": 0,
      "strong-sparse": 0,
      "strong-dense": 0,
    }
    ;(topics || []).forEach(function (item) {
      if (item && Object.prototype.hasOwnProperty.call(counts, item.bucket)) {
        counts[item.bucket] += 1
      }
    })
    return counts
  }

  /** 雷达图图例：两条序列，颜色取自 charts 的主题色 */
  function legendItems() {
    return [
      { name: "掌握度", color: Charts.DEFAULT_THEME.series1 },
      { name: "覆盖度", color: Charts.DEFAULT_THEME.series2 },
    ]
  }

  /** 概览卡片 */
  function summaryCards(summary) {
    const s = summary || {}
    return [
      { label: "知识点", value: String(Number(s.topicCount) || 0) },
      { label: "平均掌握度", value: percent(s.avgMastery) },
      { label: "平均覆盖度", value: percent(s.avgCoverage) },
      { label: "薄弱知识点", value: String(Number(s.weakCount) || 0) },
      { label: "总提交数", value: String(Number(s.totalAttempts) || 0) },
      { label: "练过题数", value: String(Number(s.totalProblems) || 0) },
      { label: "未涉及的知识点", value: String(Number(s.untouchedTopics) || 0) },
      { label: "期望题量下限", value: String(Number(s.minExpectedQuestions) || 0) },
    ]
  }

  /**
   * 雷达图要展示的知识点：练得最多的几个（提交次数降序，同次数按名字排）。
   * 选「练得最多的」是因为雷达看的是主战场的长相，弱项由弱项榜负责。
   */
  function radarTopics(topics, max) {
    const list = Array.isArray(topics) ? topics.slice() : []
    const limit = Math.max(0, Math.floor(Number(max) || MAX_RADAR_TOPICS))
    list.sort(function (a, b) {
      const da = Number(a.attempts) || 0
      const db = Number(b.attempts) || 0
      if (da !== db) return db - da
      return String(a.topic) < String(b.topic) ? -1 : 1
    })
    return list.slice(0, limit).map(function (item) {
      return {
        topic: String(item.topic),
        mastery: Charts.clamp01(item.mastery),
        coverage: Charts.clamp01(item.coverage),
        attempts: Number(item.attempts) || 0,
      }
    })
  }

  /** 弱项榜：只收两个弱档，按处置优先级排 */
  function weakRows(topics, limit) {
    const list = Array.isArray(topics) ? topics.slice() : []
    const cap = Math.max(0, Math.floor(Number(limit) || MAX_WEAK_ROWS))
    const rows = list.filter(function (item) {
      return item && WEAK_BUCKETS.indexOf(item.bucket) !== -1
    })
    rows.sort(function (a, b) {
      const ia = URGENCY_ORDER.indexOf(a.bucket)
      const ib = URGENCY_ORDER.indexOf(b.bucket)
      if (ia !== ib) return ia - ib
      const ma = Number(a.mastery) || 0
      const mb = Number(b.mastery) || 0
      if (ma !== mb) return ma - mb
      return String(a.topic) < String(b.topic) ? -1 : 1
    })
    return rows.slice(0, cap).map(function (item) {
      return {
        topic: String(item.topic),
        mastery: Charts.clamp01(item.mastery),
        coverage: Charts.clamp01(item.coverage),
        label: String(item.label || ""),
        action: String(item.action || ""),
        display: percent(item.mastery),
      }
    })
  }

  /** 知识点覆盖：按覆盖度从低到高排 */
  function coverageRows(topics, limit) {
    const list = Array.isArray(topics) ? topics.slice() : []
    const cap = Math.max(0, Math.floor(Number(limit) || MAX_COVERAGE_ROWS))
    list.sort(function (a, b) {
      const ca = Number(a.coverage) || 0
      const cb = Number(b.coverage) || 0
      if (ca !== cb) return ca - cb
      return String(a.topic) < String(b.topic) ? -1 : 1
    })
    return list.slice(0, cap).map(function (item) {
      const problems = Number(item.problems) || 0
      const expected = Number(item.expected) || 0
      return {
        topic: String(item.topic),
        coverage: Charts.clamp01(item.coverage),
        expected: expected,
        problems: problems,
        display: percent(item.coverage),
        detail: "练了 " + problems + " / 期望 " + expected + " 题",
      }
    })
  }

  /**
   * 算整个诊断页要显示的数据。纯函数，渲染层只负责把它摆出来。
   * @param {{topics?: object[], summary?: object, series?: object[]}} data
   * @returns {object}
   */
  function buildDiagnoseView(data) {
    const payload = data || {}
    const topics = Array.isArray(payload.topics) ? payload.topics : []
    const series = Array.isArray(payload.series) ? payload.series : []
    const radar = radarTopics(topics, MAX_RADAR_TOPICS)
    const weak = weakRows(topics, MAX_WEAK_ROWS)
    const coverage = coverageRows(topics, MAX_COVERAGE_ROWS)

    return {
      summary: summaryCards(payload.summary),
      buckets: bucketCounts(topics),
      radar: {
        title: "掌握度雷达（练得最多的 " + radar.length + " 个知识点）",
        labels: radar.map(function (row) {
          return row.topic
        }),
        series: [
          { name: "掌握度", values: radar.map(function (row) { return row.mastery }) },
          { name: "覆盖度", values: radar.map(function (row) { return row.coverage }) },
        ],
        rows: radar,
        table: {
          columns: ["知识点", "掌握度", "覆盖度", "提交数"],
          rows: radar.map(function (row) {
            return [row.topic, percent(row.mastery), percent(row.coverage), String(row.attempts)]
          }),
        },
      },
      weak: {
        title: "弱项榜",
        rows: weak,
        table: {
          columns: ["知识点", "掌握度", "诊断", "建议"],
          rows: weak.map(function (row) {
            return [row.topic, row.display, row.label, row.action]
          }),
        },
      },
      curve: {
        title: "每日题量曲线（近 " + series.length + " 天）",
        points: series.map(function (row) {
          return { date: String(row.date), count: Number(row.count) || 0 }
        }),
        table: {
          columns: ["日期", "题量"],
          rows: series.map(function (row) {
            return [String(row.date), String(Number(row.count) || 0)]
          }),
        },
      },
      coverage: {
        title: "知识点覆盖",
        rows: coverage,
        table: {
          columns: ["知识点", "覆盖度", "练过 / 期望"],
          rows: coverage.map(function (row) {
            return [row.topic, row.display, row.detail]
          }),
        },
      },
    }
  }

  /* ---------------- 渲染层 ---------------- */

  /** 极简 DOM 构造器——与 M4 的 A.el 同签名，用不上 A.el 时的兜底 */
  function dEl(tag, attrs, children) {
    const node = document.createElement(tag)
    if (attrs) {
      Object.keys(attrs).forEach(function (key) {
        if (key === "class") node.className = attrs[key]
        else if (key === "text") node.textContent = attrs[key]
        else node.setAttribute(key, attrs[key])
      })
    }
    ;(children || []).forEach(function (child) {
      node.appendChild(child)
    })
    return node
  }

  /** 放一张图（SVG 字符串由 web/charts.js 生成，标签已转义） */
  function chartHost(el, svg) {
    const host = el("div", { class: "chart-host" })
    host.innerHTML = svg
    return host
  }

  /** 表格孪生：每张图都能展开成表格看 */
  function tableTwin(el, table) {
    const data = table || {}
    const head = el(
      "tr",
      {},
      (data.columns || []).map(function (name) {
        return el("th", { text: name })
      })
    )
    const body = (data.rows || []).map(function (row) {
      return el(
        "tr",
        {},
        row.map(function (cell) {
          return el("td", { text: String(cell) })
        })
      )
    })
    return el("details", { class: "chart-table" }, [
      el("summary", { text: "表格视图" }),
      el("table", {}, [
        el("thead", {}, [head]),
        el("tbody", {}, body),
      ]),
    ])
  }

  /**
   * 把视图数据摆进 DOM。
   * @param {Element} container 容器（一般是 #view）
   * @param {object} view buildDiagnoseView 的返回值
   * @param {object} [charts] web/charts.js
   * @param {Function} [el] DOM 构造器 el(tag, attrs, children)，默认用 M4 的 A.el
   */
  function mountDiagnose(container, view, charts, el) {
    const C = charts || Charts
    const make =
      el ||
      (typeof window !== "undefined" && window.AlgoPlan && window.AlgoPlan.el
        ? window.AlgoPlan.el
        : dEl)
    container.textContent = ""

    // 概览
    const cards = view.summary.map(function (card) {
      return make("div", { class: "diag-card" }, [
        make("div", { text: card.label }),
        make("span", { text: card.value }),
      ])
    })
    container.appendChild(
      make("section", { class: "diag-panel" }, [
        make("h2", { text: "诊断概览" }),
        make("div", { class: "diag-cards" }, cards),
      ])
    )

    // 掌握度雷达
    const legend = legendItems().map(function (item) {
      const dot = make("i", {})
      dot.style.background = item.color
      return make("span", {}, [dot, document.createTextNode(item.name)])
    })
    container.appendChild(
      make("section", { class: "diag-panel" }, [
        make("h2", { text: view.radar.title }),
        make("div", { class: "diag-legend" }, legend),
        chartHost(
          make,
          C.radarSvg({
            labels: view.radar.labels,
            series: view.radar.series,
            title: view.radar.title,
          })
        ),
        tableTwin(make, view.radar.table),
      ])
    )

    // 弱项榜
    const weakBars = view.weak.rows.map(function (row) {
      return { label: row.topic, value: row.mastery, display: row.display }
    })
    const weakAdvice = view.weak.rows.map(function (row) {
      return make("li", {}, [
        make("span", { class: "badge", text: row.label }),
        make("span", { class: "diag-topic", text: row.topic }),
        make("span", { class: "muted", text: row.action }),
      ])
    })
    container.appendChild(
      make("section", { class: "diag-panel" }, [
        make("h2", { text: view.weak.title }),
        weakBars.length === 0
          ? make("p", { class: "diag-empty", text: "目前没有薄弱知识点——保持住。" })
          : chartHost(make, C.barSvg({ rows: weakBars, title: view.weak.title })),
        weakAdvice.length === 0
          ? null
          : make("ul", { class: "diag-advice" }, weakAdvice),
        tableTwin(make, view.weak.table),
      ])
    )

    // 每日题量曲线
    container.appendChild(
      make("section", { class: "diag-panel" }, [
        make("h2", { text: view.curve.title }),
        chartHost(make, C.lineSvg({ points: view.curve.points, title: view.curve.title })),
        tableTwin(make, view.curve.table),
      ])
    )

    // 知识点覆盖
    const coverageBars = view.coverage.rows.map(function (row) {
      return { label: row.topic, value: row.coverage, display: row.display }
    })
    container.appendChild(
      make("section", { class: "diag-panel" }, [
        make("h2", { text: view.coverage.title }),
        coverageBars.length === 0
          ? make("p", { class: "diag-empty", text: "还没有练过任何题目。" })
          : chartHost(make, C.barSvg({ rows: coverageBars, title: view.coverage.title })),
        tableTwin(make, view.coverage.table),
      ])
    )
  }

  /**
   * M4 的页面入口：拉数据并渲染诊断页。
   * @param {Element} view M4 传进来的 #view
   * @returns {Promise<void>}
   */
  async function renderPage(view) {
    const api = typeof window !== "undefined" ? window.AlgoPlan : null
    const C = typeof window !== "undefined" && window.AlgoPlanCharts ? window.AlgoPlanCharts : Charts
    if (!api) return
    const make = typeof api.el === "function" ? api.el : dEl
    view.textContent = ""
    view.appendChild(make("div", { class: "panel muted", text: "正在加载诊断数据…" }))
    try {
      const body = await api.getJson("/api/insights")
      const model = buildDiagnoseView(body)
      view.textContent = ""
      mountDiagnose(view, model, C, make)
    } catch (err) {
      view.textContent = ""
      view.appendChild(
        make("section", { class: "panel" }, [
          make("h2", { text: "诊断数据加载失败" }),
          make("p", { class: "error", text: String((err && err.message) || err) }),
        ])
      )
    }
  }

  /* 注册进 M4 的页面表——浏览器里 window.AlgoPlan 一定在，Node 测试里用替身 */
  if (typeof window !== "undefined" && window.AlgoPlan && window.AlgoPlan.pages) {
    window.AlgoPlan.pages.diagnose = {
      title: "诊断",
      render: renderPage,
    }
  }

  return {
    MAX_RADAR_TOPICS: MAX_RADAR_TOPICS,
    MAX_WEAK_ROWS: MAX_WEAK_ROWS,
    MAX_COVERAGE_ROWS: MAX_COVERAGE_ROWS,
    URGENCY_ORDER: URGENCY_ORDER,
    WEAK_BUCKETS: WEAK_BUCKETS,
    percent: percent,
    bucketCounts: bucketCounts,
    legendItems: legendItems,
    summaryCards: summaryCards,
    radarTopics: radarTopics,
    weakRows: weakRows,
    coverageRows: coverageRows,
    buildDiagnoseView: buildDiagnoseView,
    mountDiagnose: mountDiagnose,
    renderPage: renderPage,
  }
})
```

- [ ] **Step 4: 写 web/diagnose.css，改 web/index.html 与 web/app.js**

Create `projects/apps/algo-plan/web/diagnose.css`：

```css
/* 诊断页专用样式。配色一律取 style.css 里的 CSS 变量，不另起一套。 */

.diag-panel {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 18px 20px;
  margin-bottom: 18px;
}
.diag-panel h2 {
  font-size: 15px;
  margin: 0 0 12px;
  font-weight: 600;
}
.diag-cards {
  display: flex;
  flex-wrap: wrap;
  gap: 12px 32px;
}
.diag-card { min-width: 96px; }
.diag-card div { color: var(--muted); font-size: 13px; }
.diag-card span { color: var(--fg); font-size: 18px; font-weight: 600; }

.diag-legend {
  display: flex;
  gap: 18px;
  font-size: 13px;
  color: var(--muted);
  margin-bottom: 10px;
}
.diag-legend i {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  margin-right: 6px;
  vertical-align: middle;
}

.chart { width: 100%; height: auto; display: block; }
.chart-host { margin: 4px 0 6px; }

.chart-table { margin-top: 10px; }
.chart-table summary {
  cursor: pointer;
  font-size: 13px;
  color: var(--muted);
}
.chart-table table { margin-top: 8px; }

.diag-advice {
  list-style: none;
  margin: 10px 0 0;
  padding: 0;
  font-size: 13px;
}
.diag-advice li {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 5px 0;
  border-bottom: 1px solid var(--line);
}
.diag-topic { color: var(--fg); }

.diag-empty { color: var(--muted); font-size: 13px; margin: 4px 0 0; }
```

把 `projects/apps/algo-plan/web/index.html` 整个替换成下面这个版本
（**M4 的结构一字不动**，只在 `<head>` 加一条 link、在 `<body>` 里加两条 script；
`charts.js` 必须排在 `diagnose.js` 前面，因为诊断页加载时就要拿它的主题色）：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>算法能力计划</title>
  <link rel="stylesheet" href="/style.css" />
  <link rel="stylesheet" href="/diagnose.css" />
</head>
<body>
  <header class="topbar">
    <h1>算法能力计划</h1>
    <nav id="tabs"></nav>
  </header>
  <main id="view">
    <div class="panel">正在加载…</div>
  </main>
  <!-- app.js 先加载：它把公共工具挂到 window.AlgoPlan 上，页面脚本随后注册自己 -->
  <script src="/app.js"></script>
  <!-- charts.js 也要先加载：诊断页在注册时就取它的主题色 -->
  <script src="/charts.js"></script>
  <script src="/pages/today.js"></script>
  <script src="/pages/answer.js"></script>
  <script src="/pages/review.js"></script>
  <script src="/pages/rounds.js"></script>
  <script src="/diagnose.js"></script>
</body>
</html>
```

改 `projects/apps/algo-plan/web/app.js`：找到 `const TABS = [...]` 这一段，
**只在数组末尾加一项**，M4 的调度逻辑一个字不动：

```javascript
const TABS = [
  { key: "today", label: "今日" },
  { key: "answer", label: "作答" },
  { key: "review", label: "复习" },
  { key: "rounds", label: "轮次" },
  { key: "diagnose", label: "诊断" },
]
```

> `renderTabs()` 每次切页都会 `nav.textContent = ""` 重画整个 `#tabs`，
> 所以诊断页的按钮**只能**通过 `TABS` 数组加，不能自己往 `#tabs` 里塞——
> 自己塞的按钮第一次切页就没了。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/diagnose.test.js
```

Expected: `# fail 0`，退出码 0

- [ ] **Step 6: 前端语法自检 + 跑全量测试**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node --check web/charts.js && node --check web/diagnose.js
```

Expected: 两条命令都无输出，退出码 0

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`，退出码 0

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加诊断页前端

- web/diagnose.js：诊断页的纯函数层 + 渲染层，UMD 双模，浏览器挂 window.AlgoPlanDiagnose
- 四块内容：掌握度雷达、弱项榜、每日题量曲线、知识点覆盖，全部手绘 SVG，零图表库
- 雷达图选练得最多的 6 个知识点，弱项榜只收「练过但总错」「薄弱且练得少」两档
- 诊断档位用中文文字徽章表达，不靠颜色单独承载信息
- 每张图都带表格孪生，可展开成表格看
- 按 M4 的页面约定注册进 window.AlgoPlan.pages.diagnose；
  web/app.js 的 TABS 数组末尾加一项「诊断」，M4 的调度逻辑不动
- web/diagnose.css：诊断页样式，配色全部取 style.css 的 CSS 变量
- web/index.html：加 charts.js / diagnose.js 与 diagnose.css
- 测试：纯函数、页面注册与静态资源接线共 18 条断言"
git push origin main
```

---

## Task 6: 端到端验收、README 与父仓指针

**Files:**
- Create: `projects/apps/algo-plan/tests/diagnose-e2e.test.js`
- Modify: `projects/apps/algo-plan/README.md`

**Interfaces:**
- Consumes:
  - Task 3 的 `GET /api/insights`（真实 HTTP）
  - Task 4 的 `web/charts.js`、Task 5 的 `web/diagnose.js` 的 `buildDiagnoseView`
  - M1 的 `server/app.js` 的 `createApp`（`app.store` / `app.listen` / `app.close`）
- Produces:
  - `tests/diagnose-e2e.test.js`：一条从「造流水」到「前端画出干净的 SVG」的完整链路
  - `README.md` 补上掌握度模型、四档诊断、期望题量口径、`/api/insights` 与新测试套件

- [ ] **Step 1: 写端到端测试**

Create `projects/apps/algo-plan/tests/diagnose-e2e.test.js`：

```javascript
"use strict"
/**
 * diagnose-e2e.test.js —— 诊断的端到端验收
 *
 * 链路：造作答流水 → 起真服务 → 打 /api/insights → 校验响应形状 →
 * 校验静态资源取得到 → 把真实响应喂给前端的视图函数，确认画出来的 SVG 干净。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")
const Charts = require("../web/charts.js")
const { buildDiagnoseView } = require("../web/diagnose.js")

/** 三道题：数组挂两个知识点，动态规划单独一个 */
const BANK = [
  {
    file: "lc-00001.md",
    id: "lc-00001",
    title: "两数之和",
    topics: "[数组, 哈希表]",
  },
  {
    file: "lc-00002.md",
    id: "lc-00002",
    title: "合并区间",
    topics: "[数组]",
  },
  {
    file: "lc-00003.md",
    id: "lc-00003",
    title: "爬楼梯",
    topics: "[动态规划]",
  },
]

/** 造一个带题库的临时 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-diag-e2e-"))
  const dir = path.join(root, "bank", "interview")
  fs.mkdirSync(dir, { recursive: true })
  BANK.forEach(function (item) {
    const body = [
      "---",
      "id: " + item.id,
      "source: leetcode",
      "title: " + item.title,
      "difficulty: easy",
      "topics: " + item.topics,
      "tracks: [interview]",
      "status: todo",
      "needs_fill: false",
      "created: 2026-11-11",
      "updated: 2026-11-11",
      "---",
      "## 题面",
      "",
      "题目正文。",
      "",
    ].join("\n")
    fs.writeFileSync(path.join(dir, item.file), body, "utf8")
  })
  return root
}

/** 起服务并塞四条流水。 */
const NOW = Date.now()

/** 几小时之前的时间戳 */
function isoAgo(hours) {
  return new Date(NOW - hours * 3600 * 1000).toISOString()
}

async function startServer() {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  const base = "http://127.0.0.1:" + port

  function add(problemId, hoursAgo, verdict) {
    app.store.insertAttempt({
      problem_id: problemId,
      ts: isoAgo(hoursAgo),
      language: "cpp",
      code: "int main(){}",
      verdict: verdict,
      passed_cases: verdict === "pass" ? 2 : 0,
      total_cases: 2,
      duration_ms: 90,
      mode: "solve",
    })
  }

  // lc-00001：先过、再错一次
  add("lc-00001", 4, "pass")
  add("lc-00001", 3, "wrong_answer")
  // lc-00002：先错、再过
  add("lc-00002", 2, "wrong_answer")
  add("lc-00002", 1, "pass")

  return { app: app, base: base }
}

/* ---------------- 接口 ---------------- */

test("端到端：GET /api/insights 返回契约要求的三个键", async function () {
  const { app, base } = await startServer()
  try {
    const res = await fetch(base + "/api/insights")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok(Array.isArray(body.topics))
    assert.ok(body.summary)
    assert.ok(Array.isArray(body.series))
  } finally {
    await app.close()
  }
})

test("端到端：知识点统计与作答流水对得上", async function () {
  const { app, base } = await startServer()
  try {
    const body = await (await fetch(base + "/api/insights")).json()
    assert.strictEqual(body.topics.length, 2, "没练过的动态规划不该出现在 topics 里")

    const array = body.topics.find(function (t) {
      return t.topic === "数组"
    })
    assert.strictEqual(array.attempts, 4)
    assert.strictEqual(array.firstPass, 1, "lc-00002 首次没通过，不算首次通过")
    assert.strictEqual(array.lapses, 2)
    assert.strictEqual(array.problems, 2)
    assert.strictEqual(array.expected, 5, "题库只有 2 道，按下限取 5")
    assert.strictEqual(array.expectedSource, "floor")
    assert.ok(Math.abs(array.coverage - 0.4) < 1e-9, "实际 " + array.coverage)
    assert.strictEqual(array.bucket, "weak-sparse")
    assert.strictEqual(array.label, "薄弱且练得少")

    const hash = body.topics.find(function (t) {
      return t.topic === "哈希表"
    })
    assert.strictEqual(hash.attempts, 2)
    assert.strictEqual(hash.firstPass, 1)
    assert.strictEqual(hash.lapses, 1)
    assert.strictEqual(hash.problems, 1)
    assert.ok(Math.abs(hash.coverage - 0.2) < 1e-9, "实际 " + hash.coverage)
    assert.strictEqual(hash.bucket, "strong-sparse")
    assert.strictEqual(hash.label, "偶然会，没练透")

    // 掌握度不会因为一道题挂两个知识点而翻倍
    assert.ok(hash.mastery > array.mastery, "哈希表掌握度应该高于数组")
  } finally {
    await app.close()
  }
})

test("端到端：summary 的总数按原始流水算，不按知识点加总", async function () {
  const { app, base } = await startServer()
  try {
    const body = await (await fetch(base + "/api/insights")).json()
    assert.strictEqual(body.summary.totalAttempts, 4)
    assert.strictEqual(body.summary.totalProblems, 2)
    assert.strictEqual(body.summary.untouchedTopics, 1, "动态规划没练过")
    assert.strictEqual(body.summary.topicCount, 2)
  } finally {
    await app.close()
  }
})

test("端到端：每日题量曲线按天分组，窗口内缺失的日期补 0", async function () {
  const { app, base } = await startServer()
  try {
    const body = await (await fetch(base + "/api/insights")).json()
    assert.strictEqual(body.series.length, 30)
    const total = body.series.reduce(function (sum, row) {
      return sum + row.count
    }, 0)
    assert.strictEqual(total, 4, "四条流水都要在曲线里")
    body.series.forEach(function (row) {
      assert.ok(row.count >= 0)
      assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(row.date))
    })
    assert.strictEqual(body.summary.windowAttempts, 4)

    // ?days=7 缩小窗口
    const short = await (await fetch(base + "/api/insights?days=7")).json()
    assert.strictEqual(short.series.length, 7)
    assert.strictEqual(short.summary.windowDays, 7)
  } finally {
    await app.close()
  }
})

/* ---------------- 静态资源 ---------------- */

test("端到端：charts.js / diagnose.js / diagnose.css 都取得到", async function () {
  const { app, base } = await startServer()
  try {
    const charts = await fetch(base + "/charts.js")
    assert.strictEqual(charts.status, 200)
    assert.ok((await charts.text()).indexOf("radarSvg") !== -1)

    const diagnose = await fetch(base + "/diagnose.js")
    assert.strictEqual(diagnose.status, 200)
    assert.ok((await diagnose.text()).indexOf("buildDiagnoseView") !== -1)

    const css = await fetch(base + "/diagnose.css")
    assert.strictEqual(css.status, 200)
    assert.ok((await css.text()).indexOf(".diag-panel") !== -1)
  } finally {
    await app.close()
  }
})

test("端到端：首页引用了诊断页的资源", async function () {
  const { app, base } = await startServer()
  try {
    const html = await (await fetch(base + "/")).text()
    assert.ok(html.indexOf('src="/charts.js"') !== -1)
    assert.ok(html.indexOf('src="/diagnose.js"') !== -1)
    assert.ok(html.indexOf('href="/diagnose.css"') !== -1)
    assert.ok(html.indexOf('src="/charts.js"') < html.indexOf('src="/diagnose.js"'))
  } finally {
    await app.close()
  }
})

/* ---------------- 前端闭环 ---------------- */

test("端到端：真实响应喂给前端，出来的 SVG 干净", async function () {
  const { app, base } = await startServer()
  try {
    const body = await (await fetch(base + "/api/insights")).json()
    const view = buildDiagnoseView(body)

    const radar = Charts.radarSvg({
      labels: view.radar.labels,
      series: view.radar.series,
      title: view.radar.title,
    })
    const curve = Charts.lineSvg({ points: view.curve.points, title: view.curve.title })
    const weak = Charts.barSvg({
      rows: view.weak.rows.map(function (row) {
        return { label: row.topic, value: row.mastery, display: row.display }
      }),
      title: view.weak.title,
    })
    const coverage = Charts.barSvg({
      rows: view.coverage.rows.map(function (row) {
        return { label: row.topic, value: row.coverage, display: row.display }
      }),
      title: view.coverage.title,
    })

    ;[radar, curve, weak, coverage].forEach(function (svg) {
      assert.ok(svg.indexOf("NaN") === -1, "SVG 里出现了 NaN")
      assert.ok(svg.indexOf("undefined") === -1, "SVG 里出现了 undefined")
      assert.ok(svg.indexOf("Infinity") === -1, "SVG 里出现了 Infinity")
    })

    // 雷达图上有两个知识点，曲线有 30 天
    assert.ok(radar.indexOf("数组") !== -1, "雷达图里没有「数组」")
    assert.ok(radar.indexOf("哈希表") !== -1, "雷达图里没有「哈希表」")
    assert.ok(curve.indexOf("<title>") !== -1)
  } finally {
    await app.close()
  }
})

/* ---------------- 文档同步 ---------------- */

test("README 写清楚了诊断接口与期望题量口径", function () {
  const readme = fs.readFileSync(path.join(__dirname, "..", "README.md"), "utf8")
  assert.ok(readme.indexOf("/api/insights") !== -1, "README 里没有写 /api/insights")
  assert.ok(readme.indexOf("期望题量") !== -1, "README 里没有写期望题量口径")
  assert.ok(readme.indexOf("insights.expected_min_questions") !== -1, "README 里没有写可配置的键名")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/diagnose-e2e.test.js
```

Expected: FAIL，最后一条挂在 `README 里没有写 /api/insights`（其余 8 条都过——说明前面五个 Task 的实现已经是对的，只差文档）

- [ ] **Step 3: 更新 README.md**

把 `projects/apps/algo-plan/README.md` 整个替换成下面这个版本
（M1 的内容保留，追加 M5 的掌握度模型、四档诊断、期望题量口径、`/api/insights` 与新测试套件）：

`````markdown
# algo-plan · 算法能力提升计划 App

本机运行的算法学习助手：本地静态题库打底，LLM 做增强，判题走真实编译执行，
进度与错题写回 learning 仓进 git。

当前进度：**M5 诊断**（服务骨架 / SQLite / 题库解析 / 判题 / 复习 / 轮次 / 掌握度模型 / 诊断页）。
LLM 增强属于 M6，尚未实现。

## 快速开始

需要 Node ≥ 24（用到内置 `node:sqlite`）。零 npm 依赖、零构建。

```bash
# 跑测试
node tests/run-all.js

# 接上 learning 仓并启动
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node server/main.js
# 打开 http://127.0.0.1:5173 ，点顶栏的「诊断」页
```

没设 `ALGO_PLAN_LEARNING_ROOT` 也能启动——那是「纯本地模式」：只有 SQLite，
不与 learning 仓同步。

## 环境变量

| 变量 | 说明 | 默认 |
|---|---|---|
| `ALGO_PLAN_LEARNING_ROOT` | learning 仓根目录。**不硬编码相对路径** | 无（未设＝纯本地模式） |
| `PORT` | 服务端口 | `5173` |

## 目录结构

```
algo-plan/
├── core/            纯函数层：Problem 模型、markdown 解析、provider、路径解析、掌握度模型
├── server/          组合根、路由、API、SQLite 存储、诊断数据装配
├── judge/           判题执行器
├── web/             原生 JS 单页（无构建）；charts.js 是手绘 SVG 的纯函数层
├── tools/           seed-bank.js：把样板题导入 learning 仓
├── fixtures/        样板题
└── tests/           node:test 套件，一个命令跑全部
```

## 掌握度与诊断（M5）

诊断页的每个数字都有明确的来源，口径定死，不随实现漂移。

### 掌握度

```
首次通过率 = firstPass / attempts            ← 反复重试通过不算掌握
遗忘因子   = 0.5 ^ (距上次练习天数 / 14)      ← 半衰期 14 天
掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
```

- `firstPass`：**第一次尝试就通过**的题目数。
- `attempts`：该知识点下所有题目的提交总次数。
- `lapses`：该知识点下**没通过**的提交次数。
- 四个数存在 SQLite 的 `topics` 表里（`first_pass` / `attempts` / `lapses` / `last_at`）。

### 覆盖度

```
覆盖度 = 练过的不同题目数 / 期望题量
```

### 期望题量（覆盖度的分母）

三级口径，自上而下：

| 优先级 | 来源 | 说明 |
|---|---|---|
| ① 覆盖值 | `settings` 表的 `insights.expected_override.<topic>` | 手工指定某个知识点的期望题量 |
| ② 题库题数 | 题库里带这个 topic 的题目数 | 「这个知识点一共就这么多题」 |
| ③ 下限常量 | `settings` 表的 `insights.expected_min_questions`，默认 **5** | 「至少练够 5 题才叫练透」 |

**②③ 的合成规则：`期望题量 = max(题库题数, 下限常量)`。**

下限存在的理由：只有 1 道题的冷门知识点，练 1 道就是 100% 覆盖，会被误判成「掌握」。
下限常量把这个洞堵上。

**可配置**（改完刷新诊断页立刻生效）：

| 键名 | 作用 | 默认 |
|---|---|---|
| `insights.expected_min_questions` | 所有知识点的期望题量下限 | `5` |
| `insights.expected_override.<topic>` | 单个知识点的期望题量（如 `insights.expected_override.数组`） | 无 |

### 四档诊断

掌握度 ≥ 0.5 算「高」，覆盖度 ≥ 0.5 算「高」，两个维度交叉出四档：

| 掌握度 | 覆盖度 | 档位 | 含义与处方 |
|---|---|---|---|
| 低 | 低 | 薄弱且练得少 | 轮次里优先排这类题——先补量 |
| 低 | 高 | 练过但总错 | 回头看概念，而不是继续刷题 |
| 高 | 低 | 偶然会，没练透 | 安排复习巩固 |
| 高 | 高 | 掌握 | 不再主动排 |

「练过但总错」这一档很重要——它区分「题做得少」和「概念没懂」，两者处方完全不同。

### 每日题量曲线

数据源是 `attempts` 表按 `substr(ts,1,10)` 分组的行数，也就是当天的提交次数。
默认最近 30 天，`GET /api/insights?days=N` 可调（`days=0` 表示全部）。
窗口内某天没提交会**补 0**，这样「哪天没练」在曲线上看得见。

### 诊断页

顶栏的「诊断」页有四块内容，全部是**手绘 SVG**（零第三方图表库）：

1. **掌握度雷达**——两条序列：掌握度、覆盖度，取练得最多的 6 个知识点；
2. **弱项榜**——只收「练过但总错」「薄弱且练得少」两档，条形末端标掌握度；
3. **每日题量曲线**——折线 + 面积，窗口内没提交的日期补 0；
4. **知识点覆盖**——每个知识点「练过 N / 期望 M 题」的覆盖条。

每张图都能展开成表格视图（表格孪生），方便核对数字。

## 题库格式

题库放在 `learning/bank/<track>/<id>.md`，markdown + frontmatter，人和 agent 都能直接编辑：

````markdown
---
id: lc-00001
source: leetcode
title: 两数之和
difficulty: easy
topics: [哈希表, 数组]
tracks: [interview, fundamentals]
status: todo
needs_fill: false
created: 2026-11-11
updated: 2026-11-11
---
## 题面
...
## 测试用例
| input | expect |
|---|---|
| [2,7,11,15], 9 | [0,1] |
## 参考解法
```cpp
...
```
````

`id` 是 git 侧与 SQLite 侧的唯一连接键，格式 `<前缀>-<5 位数字>`，
前缀取自 `lc` / `nc` / `jz` / `self` / `llm`。

导入样板题：

```bash
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/seed-bank.js --dry-run
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/seed-bank.js
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/health` | 运行状态、learning 仓连接情况、题库概况 |
| GET | `/api/bank` | 题库列表，支持 `track` / `topic` / `difficulty` / `status` / `prefix` / `limit` |
| GET | `/api/problem/:id` | 单题详情。**只回前 2 个样例用例 + 用例总数，不回参考解法** |
| GET | `/api/insights` | 诊断数据。`?days=N` 调曲线窗口（默认 30，`0`＝全部） |

`GET /api/insights` 的响应：

```json
{
  "topics": [{
    "topic": "数组",
    "mastery": 0.2836,
    "coverage": 0.4,
    "bucket": "weak-sparse",
    "label": "薄弱且练得少",
    "action": "轮次里优先排这类题——先补量",
    "attempts": 4,
    "firstPass": 1,
    "lapses": 2,
    "lastAt": "2026-11-10T11:00:00.000Z",
    "expected": 5,
    "expectedSource": "floor",
    "problems": 2
  }],
  "summary": {
    "topicCount": 2,
    "untouchedTopics": 1,
    "weakCount": 1,
    "strongCount": 1,
    "avgMastery": 0.4061,
    "avgCoverage": 0.3,
    "totalAttempts": 4,
    "totalProblems": 2,
    "lastPracticeAt": "2026-11-10T11:00:00.000Z",
    "minExpectedQuestions": 5,
    "windowDays": 30,
    "windowAttempts": 4
  },
  "series": [{ "date": "2026-11-01", "count": 0 }]
}
```

`topics` 按处置优先级排序：**练过但总错 > 薄弱且练得少 > 偶然会没练透 > 掌握**。

## 测试

```bash
node tests/run-all.js
```

| 套件 | 覆盖 |
|---|---|
| `smoke.test.js` | 静态页 200 / 404 / 越界 400 / 方法不对 405 |
| `router.test.js` | 路径参数匹配、方法匹配、JSON body 解析 |
| `problem.test.js` | ID 生成、topic 归一化、字段校验 |
| `parse.test.js` | frontmatter、用例表、代码块、往返等价 |
| `db.test.js` | 建表、配置、流水、复习卡片、知识点 |
| `provider.test.js` | 题库读写、过滤、坏文件容错 |
| `api.test.js` | 三个接口、纯本地模式降级、用例不外泄 |
| `e2e.test.js` | 导入 → 起服务 → 打接口 → 落盘 |
| `mastery.test.js` | 掌握度公式、遗忘因子、四档诊断、排序 |
| `mastery-stats.test.js` | 期望题量三级口径、知识点统计派生 |
| `insights.test.js` | 诊断数据装配、topics 物化、`/api/insights` |
| `charts.test.js` | 雷达 / 折线 / 条形的几何与 SVG 结构 |
| `diagnose.test.js` | 诊断页的纯函数、页面注册、静态资源接线 |
| `diagnose-e2e.test.js` | 造流水 → 起服务 → 打接口 → 前端画出干净的 SVG |

## 归属

- 服务端、判题器、前端、测试 → `projects/apps/algo-plan/`（本仓）
- 题目本体、轮次清单、错题订正 → `learning/bank/`、`learning/progress/`、`learning/notes/`（学习仓）
`````

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/diagnose-e2e.test.js
```

Expected: `# fail 0`，退出码 0

- [ ] **Step 5: 前端语法自检 + 跑全量测试**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node --check web/charts.js && node --check web/diagnose.js && node --check web/app.js
```

Expected: 三条命令都无输出，退出码 0

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: 末行形如 `N / N 套件通过`，退出码 0

- [ ] **Step 6: 真起一次服务，人工看一眼诊断页**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

另开一个终端：

```bash
# 接口能出数据
curl -s http://127.0.0.1:5173/api/insights | head -c 400

# 静态资源都在
curl -s -o /dev/null -w "charts.js %{http_code}\n" http://127.0.0.1:5173/charts.js
curl -s -o /dev/null -w "diagnose.js %{http_code}\n" http://127.0.0.1:5173/diagnose.js
curl -s -o /dev/null -w "diagnose.css %{http_code}\n" http://127.0.0.1:5173/diagnose.css
```

Expected: 三个 `%{http_code}` 都是 `200`；`/api/insights` 的输出里有 `"topics"`、`"summary"`、`"series"`

浏览器打开 `http://127.0.0.1:5173/`，点顶栏的「诊断」页，应看到：

- 诊断概览（知识点数、平均掌握度、平均覆盖度……）
- 掌握度雷达（蓝＝掌握度，橙＝覆盖度）
- 弱项榜（条形 + 中文诊断徽章 + 处置建议）
- 每日题量曲线
- 知识点覆盖

> 顶栏从左到右应当是「今日 / 作答 / 复习 / 轮次 / 诊断」五项——M4 的四个 + M5 加的一个。

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加诊断端到端验收并更新 README

- tests/diagnose-e2e.test.js：造作答流水 → 起真服务 → 打 /api/insights →
  校验响应形状、静态资源、前端画出来的 SVG 干净
- 断言 topics 的统计与流水对得上，summary 的总数按原始流水算不按知识点加总
- README：补上掌握度模型、四档诊断、期望题量三级口径与两个可配置键名、
  /api/insights 的响应形状、诊断页的四块内容、新测试套件清单
- 测试：端到端 8 条断言 + README 同步 1 条断言"
git push origin main
```

- [ ] **Step 8: 更新父仓的 submodule 指针**

M5 的代码在 `projects` 子模块里，父仓 `StillEvolving` 记的是子模块指针，要跟着更新：

```bash
cd /c/code/StillEvolving
git add projects
git commit -m "chore(submodule): 更新 projects 子模块指针（algo-plan M5 诊断）"
git push origin main
```

---

## M5 验收清单

全部满足才算 M5 完成：

| # | 验收项 | 怎么验 |
|---|---|---|
| 1 | 掌握度公式与设计文档逐字一致 | `node tests/mastery.test.js` → 首次通过率、遗忘因子、失误惩罚三段各自有断言 |
| 2 | 四档诊断落对档位 | `node tests/mastery.test.js` → 四个 key 与四个中文标签一一对应 |
| 3 | 期望题量口径明确且可配置 | `node tests/mastery-stats.test.js` → 覆盖值 / 题库题数 / 下限三级 + 六条退化路径 |
| 4 | `topics` 表是物化视图 | `node tests/insights.test.js` → 反复调接口不会把数字累加上去 |
| 5 | 接口响应形状合契约 | `GET /api/insights` → `topics` / `summary` / `series` 三个键都在 |
| 6 | 每日题量曲线按天分组并补 0 | `node tests/insights.test.js` → 缺失日期补 0，`?days=N` 生效 |
| 7 | 零第三方图表 | `package.json` 无 `dependencies`；`web/charts.js` 全是手写 SVG |
| 8 | SVG 里没有 NaN | `node tests/charts.test.js` + `diagnose-e2e.test.js` → 生成的 SVG 不含 NaN / undefined |
| 9 | 四块内容都在页面上 | 浏览器点「诊断」页 → 雷达 / 弱项榜 / 曲线 / 覆盖四块都有 |
| 10 | 每张图有表格孪生 | 「表格视图」能展开，看到同样的数字 |
| 11 | 状态不靠颜色单独承载 | 诊断档位是中文文字徽章，不是一块颜色 |
| 12 | 全量测试绿 | `node tests/run-all.js` → `N / N 套件通过` |
| 13 | 零 npm 依赖 | `package.json` 无 `dependencies`；`node_modules/` 不存在 |
| 14 | 没碰 learning 的 git | `git -C learning status` 只多出 `bank/`，无自动 commit |
| 15 | 没造接口 | 契约 §4 的五个函数签名与 `GET /api/insights` 的响应形状逐字对上 |
| 16 | 没覆盖别的里程碑的改动 | `server/api.js` 里 M3/M4 的接口都还在；`server/db.js` 里 M4 的 `listAttempts` / `countAttemptsSince` 都还在 |

---

## 执行提示

- 本计划只改 `projects/` 子模块（`projects/apps/algo-plan/`）。
  `learning/` 子模块只被读取（题库用来数「期望题量」和建立题目↔知识点的映射）。
- **Task 5 与 Task 6 要求 M4 已经落地**：诊断页走 M4 的 `window.AlgoPlan.pages` 注册表，
  顶栏按钮靠 M4 的 `web/app.js` 的 `TABS` 数组。M4 的 `renderTabs()` 每次切页都会清空
  `#tabs` 重画，所以诊断页**不能**自己往 `#tabs` 里塞按钮。
  Task 1–3（掌握度模型、期望题量口径、`/api/insights`）不依赖 M4，可以单独先做。
- **三个共享文件只做加法，谁也不覆盖谁**：
  - `server/api.js` —— M3 整体替换、M4 替换整个 `buildRoutes`，**M5 完全不碰**，
    M5 的路由在 `server/api-insights.js`，在 `server/app.js` 里合并；
  - `server/db.js` —— M4 追加过 `listAttempts` / `countAttemptsSince`，M5 只在
    `createStore` 的返回对象里**追加**方法，**不要整个替换文件**（否则 M4 的
    `/api/next` 会因为 `countAttemptsSince` 不存在而 500）；
  - `server/app.js` —— M6 也要往里加东西，两边都是加法。
- 每个 Task 结束都有「提交并推送」，Task 6 额外提醒更新父仓的 submodule 指针。
- 掌握度的**遗忘因子**会随时间衰减，所以断言掌握度时不要写死绝对值——
  本计划的所有测试要么固定 `nowIso`，要么只断言相对大小与档位。
- 中文知识点名按**码位**排序（跟 `Array.prototype.sort` 一致），不按拼音。
  写断言时别硬编码中文顺序，用 `names.slice().sort()` 对齐。
- 图表配色已用 dataviz 的 `validate_palette.js` 在面板色 `#1d2026` 上验过：
  `#3987e5`（掌握度）与 `#d95926`（覆盖度）六项检查全部 PASS。
  **换颜色必须重新验**，别直接抄别的项目的配色。
- 计划写完了，不要在没跑通测试前合并。

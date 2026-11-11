# 算法能力提升计划 App —— M4 闭环实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M4 里程碑——第一个「愿意每天打开」的版本：打开 app 就知道该练哪一题，答完能进间隔重复队列，复习完把轮次进度与错题订正写回 learning 仓。

**Architecture:** 单个 Node 进程（`node:http` + `node:sqlite`），零 npm 依赖、零构建。M4 在 M1 的地基上补三块纯逻辑：`core/review/sm2.js`（SM-2 逐字搬运 + 判题结果→quality 映射）、`core/scheduler/next-action.js`（复习 > 轮次 > 探索的优先级 + 单日配额）、`core/sync/rounds.js`（轮次解析 / 勾选写回 / 错题订正 / 查脏）。数据双层照设计文档 §1.7：轮次进度与错题订正进 `learning` 仓（git），调度态与作答流水进 SQLite，靠稳定题目 ID 互链。**写回 learning 仓后绝不自动 commit**——只返回 diff，由用户决定。

**Tech Stack:** Node.js ≥ 24（内置 `node:sqlite` / `node:test` / `node:http` / `node:child_process`）、原生 JS + CSS、零 npm 依赖。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划覆盖其中 §4.1 推下一题、§4.2 SM-2 与 quality 映射、§4.3 掌握度（**只做不含遗忘因子的近似值**，四档诊断属 M5）、§4.4 写回三条硬规则、§7.1 的「今日 / 作答 / 复习 / 轮次」四页、§8 学习仓同步契约、§10 的 **M4**）

**接口契约:** `docs/superpowers/plans/2026-11-11-algo-plan-app-接口契约.md`（§0 M1 已冻结的导出签名、§3 M4 新增、§6 G17–G22、§7 写作规范）。**本计划的模块名、函数签名、接口路径与响应字段一律照该契约，不许另起炉灶。**

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）

---

## Global Constraints

M1 的 **G1–G16 全部继续生效**（零 npm 依赖、零构建、Node ≥ 24、中文注释与提交、提交即推送、产物只在 `projects/apps/algo-plan/`、learning 仓路径不硬编码、稳定题目 ID、测试入口 `node tests/run-all.js`、中文输出、不自动 commit、SQLite 类型约束等）。下面是 M4 追加的条目——**G17–G22 是跨计划共用的，编号沿用接口契约 §6，不重新编号**。

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测，第一个能 `--version` 的胜出；探测结果可缓存进 `settings`。（M4 只在作答页消费 M3 的判题结果，不自己实现解释器探测） |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序，用户自己写 `main()`；不注入 Solution 包装、不自动生成 main（M4 的作答页照这个契约展示结果） |
| G19 | **导入 id 冲突** | 同 id 已存在则跳过并计入 `skipped`；只有 `force` 才覆盖。（M4 不做导入，保留此约束供 M2/M6） |
| G20 | **写回前查脏** | `git -c core.quotepath=false status --porcelain -z`，**按 NUL 切分**；不许 `line.slice(3)` 硬切 |
| G21 | **轮次解析容错** | 按列名关键词匹配，缺列填空，坏行跳过并计告警；不因一行看不懂而整体报错 |
| G22 | **零第三方图表** | 雷达图、曲线一律手绘 SVG，不引图表库（M4 只画进度条，原生 CSS 即可） |
| G23 | **SM-2 公式逐字搬运** | `core/review/sm2.js` 的 ease/interval/repetitions 公式逐字搬自 `projects/apps/knowledge-hub/core/review.js`：easiness 下限 1.3；`quality < 3` → 间隔重置为 1、repetitions 归 0；`repetitions === 0` → 间隔 1；`=== 1` → 间隔 6；否则 `间隔 × easiness`（四舍五入） |
| G24 | **单日配额取先到者** | 复习配额是「10 题 **或** 20 分钟」，任一先到即停。配额键 `review.daily_quota_questions` / `review.daily_quota_minutes` 存 `settings` 表 |
| G25 | **写回只改目标行** | 读-改-写：只替换目标行的目标单元格，其余行逐字节保持原样；写后返回 diff；**绝不自动 commit** |
| G26 | **纯本地模式可降级** | 没接上 learning 仓时，`GET /api/rounds` 返回 `{rounds: [], warnings: []}`，`GET /api/next` 只走复习/探索分支，不抛错 |

---

## M4 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | ❌ 另出计划（已完成） |
| M2 题库 | 复活三个死脚本 + 存量题解导入 | ❌ 另出计划 |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | ❌ 另出计划 |
| **M4 闭环** | **轮次 + 推下一题 + SM-2 复习 + 写回 md** | ✅ **本计划** |
| M5 诊断 | 掌握度模型 + 诊断页 | ❌ 另出计划 |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | ❌ 另出计划 |

**M4 做完的验收线：** 打开首页就看到「下一步该干什么」和「这一步大约 N 分钟」；复习页能用「完全忘了 / 想很久 / 有点印象 / 秒答」四个按钮给一张到期卡片评分；轮次页能勾选一个条目并看到 learning 仓里那一行被改了、返回一段 diff；错题订正能落到 `learning/notes/practice/<id>-订正.md`。**诊断与 LLM 一概不碰。**

**M4 与 M2/M3 的耦合**：M4 消费 M2 产出的题库（`learning/bank/<track>/<id>.md`）与 M3 产出的判题接口（`POST /api/attempt`）。若 M2/M3 尚未执行，M4 的四个页面要**优雅降级**（题库为空 → 轮次动作没有对应题目；`/api/attempt` 404 → 作答页给出中文提示），不能白屏。这是本计划的硬要求。

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── core/
│   ├── review/
│   │   └── sm2.js                SM-2（公式逐字搬自 knowledge-hub）+ quality 映射
│   ├── scheduler/
│   │   └── next-action.js        候选动作优先级 + 单日配额 → 下一个动作
│   └── sync/
│       └── rounds.js             轮次解析 / 勾选写回 / 错题订正 / 工作区查脏
├── server/
│   ├── api.js                    Modify：加 5 个 M4 接口（契约 §3）
│   └── db.js                     Modify：加 2 个仓储方法（不改动 M1 已有方法）
├── web/
│   ├── index.html                Modify：tab 栏 + 页面脚本引用
│   ├── app.js                    Modify：改成 tab 调度 + 公共工具（el/getJson/postJson）
│   ├── style.css                 Modify：轮次表 / 评分按钮 / 进度条样式
│   └── pages/                    新建：四个页面各一个文件（无构建，靠 <script> 标签）
│       ├── today.js              今日页：下一题卡片 + 到期复习数 + 今日进度
│       ├── answer.js             作答页：题面 + 代码框 + 提交 + 结果面板
│       ├── review.js             复习页：四个直觉评分按钮 → SM-2 quality
│       └── rounds.js             轮次页：清单可视化 + 勾选写回
└── tests/
    ├── sm2.test.js               SM-2 公式、quality 映射、到期与排序
    ├── rounds-parse.test.js      7 种真实表头 + 缺列 + 坏行
    ├── sync-write.test.js        临时副本上跑：查脏 / 勾选写回 / 错题订正
    ├── next-action.test.js       优先级、配额、多轮次、轮次内挑题
    ├── api-m4.test.js            5 个新接口的端到端断言
    ├── pages.test.js             四个页面注册 + 评分文案映射
    ├── fixtures-m4.js            M4 各测试共用的临时 learning 仓（不是测试套件）
    └── e2e-m4.test.js            下一题 → 写回 → 订正 → 评分，且不自动提交
```

**归属**：本计划的代码全部在 `projects` 子模块里。**唯一一次改 learning 仓的源码**是 Task 3 Step 5（编辑）与 Step 7（提交）——在 `learning/notes/_meta/schema.md` 登记「错题订正」这个新笔记惯例（契约 §3 硬约定要求）。app 在运行时对 learning 仓的写入（勾选写回、错题订正）由用户触发，**app 与本计划都不碰 learning 的 git 历史**（G11）。

**M4 明确不做的两件小事**：设计文档 §7.1 提到代码框可以配「行号 gutter」，M4 的作答页用**纯 `<textarea>`**（等宽字体、无 gutter），这一版够用；「设置」页的每日配额可调在 M4 由 `settings` 表的 `review.daily_quota_questions` / `review.daily_quota_minutes` 两个键承担，**先不做设置界面**（M6 的设置页再暴露）。

---

## Task 1: SM-2 间隔重复与判题结果映射

**Files:**
- Create: `projects/apps/algo-plan/core/review/sm2.js`
- Create: `projects/apps/algo-plan/tests/sm2.test.js`

**Interfaces:**
- Consumes: 无（纯函数，不依赖 M1 任何模块）
- Produces（后续 Task 直接引用这些名字与签名）：
  - `core/review/sm2.js` 导出：
    - `DEFAULT_EASE = 2.5`
    - `MIN_EASE = 1.3`
    - `grade(card, quality, nowIso) -> card`：`card` 用 M1 的 `review_cards` 表形状（snake_case：`problem_id` / `easiness` / `interval_days` / `repetitions` / `last_quality` / `last_at` / `next_review_at` / `lapses`），返回同形状的新卡片
    - `qualityFromOutcome(outcome) -> number`：0~5 的整数
    - `isDue(card, nowIso) -> boolean`
    - `sortByOverdue(cards, nowIso) -> card[]`
  - `qualityFromOutcome` 的 `outcome` 形状：
    ```js
    {
      passed: boolean,          // 最终是否通过
      durationMs: number,       // 本次用时（毫秒）
      medianMs: number|null,    // 该难度的历史中位用时（毫秒）；没有就 null
      usedOldSolution: boolean, // 是否参照了自己的旧解
      copiedReference: boolean, // 是否直接抄参考答案
      failedFirst: boolean      // 是否失败过一次之后自己改对
    }
    ```

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/sm2.test.js`：

```javascript
"use strict"
/**
 * sm2.test.js —— SM-2 间隔重复：公式、quality 映射、到期判断与排序
 */

const test = require("node:test")
const assert = require("node:assert")

const sm2 = require("../core/review/sm2.js")

/** 造一张卡片（snake_case，与 M1 的 review_cards 表同形） */
function card(overrides) {
  return Object.assign(
    {
      problem_id: "lc-00001",
      easiness: 2.5,
      interval_days: 1,
      repetitions: 0,
      last_quality: null,
      last_at: null,
      next_review_at: "2026-11-11T00:00:00.000Z",
      lapses: 0,
    },
    overrides || {}
  )
}

test("DEFAULT_EASE 是 2.5，下限是 1.3", function () {
  assert.strictEqual(sm2.DEFAULT_EASE, 2.5)
  assert.strictEqual(sm2.MIN_EASE, 1.3)
})

test("quality=5：repetitions 0→1，间隔保持 1，easiness 上升", function () {
  const out = sm2.grade(card(), 5, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.repetitions, 1)
  assert.strictEqual(out.interval_days, 1)
  assert.ok(out.easiness > 2.5, "easiness 应上升")
  assert.strictEqual(out.last_quality, 5)
})

test("quality=4：repetitions 1→2，间隔跳到 6", function () {
  const out = sm2.grade(card({ easiness: 2.6, repetitions: 1 }), 4, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.repetitions, 2)
  assert.strictEqual(out.interval_days, 6)
})

test("quality=5 且 repetitions=2：间隔 = round(间隔 × easiness)", function () {
  const out = sm2.grade(card({ easiness: 2.6, interval_days: 6, repetitions: 2 }), 5, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.repetitions, 3)
  assert.strictEqual(out.interval_days, Math.round(6 * out.easiness))
})

test("quality=1（忘了）：间隔重置为 1、repetitions 归 0、lapses 加 1", function () {
  const out = sm2.grade(card({ easiness: 2.8, interval_days: 30, repetitions: 5, lapses: 2 }), 1, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.interval_days, 1)
  assert.strictEqual(out.repetitions, 0)
  assert.strictEqual(out.lapses, 3)
})

test("quality=2 也是重置分支（间隔 1、repetitions 0）", function () {
  const out = sm2.grade(card({ interval_days: 20, repetitions: 4 }), 2, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.interval_days, 1)
  assert.strictEqual(out.repetitions, 0)
})

test("easiness 不低于 1.3", function () {
  const out = sm2.grade(card({ easiness: 1.3 }), 0, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.easiness, 1.3)
})

test("grade 保留 problem_id 并按间隔推进下次复习时间", function () {
  const out = sm2.grade(card({ problem_id: "lc-00042" }), 5, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.problem_id, "lc-00042")
  assert.strictEqual(out.last_at, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.next_review_at, "2026-11-12T00:00:00.000Z")
})

test("grade 拒绝 0~5 以外的评分", function () {
  assert.throws(function () { sm2.grade(card(), 6, "2026-11-11T00:00:00.000Z") })
  assert.throws(function () { sm2.grade(card(), -1, "2026-11-11T00:00:00.000Z") })
  assert.throws(function () { sm2.grade(card(), 3.5, "2026-11-11T00:00:00.000Z") })
  assert.throws(function () { sm2.grade(card(), "好", "2026-11-11T00:00:00.000Z") })
})

test("grade 接受空卡片并补默认值", function () {
  const out = sm2.grade({ problem_id: "self-00001" }, 5, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(out.easiness, sm2.DEFAULT_EASE)
  assert.strictEqual(out.interval_days, 1)
  assert.strictEqual(out.repetitions, 1)
})

test("qualityFromOutcome：抄参考答案 → 0", function () {
  assert.strictEqual(
    sm2.qualityFromOutcome({ passed: true, copiedReference: true, durationMs: 10, medianMs: 100 }),
    0
  )
})

test("qualityFromOutcome：失败没改对 → 1", function () {
  assert.strictEqual(sm2.qualityFromOutcome({ passed: false }), 1)
})

test("qualityFromOutcome：失败一次后自己改对 → 2", function () {
  assert.strictEqual(sm2.qualityFromOutcome({ passed: true, failedFirst: true }), 2)
})

test("qualityFromOutcome：一次通过但参照旧解 → 3", function () {
  assert.strictEqual(sm2.qualityFromOutcome({ passed: true, usedOldSolution: true }), 3)
})

test("qualityFromOutcome：一次通过但偏慢 → 4", function () {
  assert.strictEqual(
    sm2.qualityFromOutcome({ passed: true, durationMs: 900, medianMs: 300 }),
    4
  )
})

test("qualityFromOutcome：一次通过且快于中位 → 5", function () {
  assert.strictEqual(
    sm2.qualityFromOutcome({ passed: true, durationMs: 100, medianMs: 300 }),
    5
  )
})

test("qualityFromOutcome：没有中位用时参考时按通过处理 → 5", function () {
  assert.strictEqual(sm2.qualityFromOutcome({ passed: true, durationMs: 100, medianMs: null }), 5)
})

test("isDue：到期与未到期", function () {
  assert.strictEqual(sm2.isDue(card({ next_review_at: "2026-11-10T00:00:00.000Z" }), "2026-11-11T00:00:00.000Z"), true)
  assert.strictEqual(sm2.isDue(card({ next_review_at: "2026-11-12T00:00:00.000Z" }), "2026-11-11T00:00:00.000Z"), false)
})

test("sortByOverdue：逾期最久的排最前，且不改动原数组", function () {
  const cards = [
    card({ problem_id: "b", next_review_at: "2026-11-11T00:00:00.000Z" }),
    card({ problem_id: "a", next_review_at: "2026-11-01T00:00:00.000Z" }),
    card({ problem_id: "c", next_review_at: "2026-11-10T00:00:00.000Z" }),
  ]
  const out = sm2.sortByOverdue(cards, "2026-11-11T00:00:00.000Z")
  assert.deepStrictEqual(out.map(function (c) { return c.problem_id }), ["a", "c", "b"])
  assert.strictEqual(cards[0].problem_id, "b", "原数组不应被改动")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/review/sm2.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/review/sm2.js`：

```javascript
"use strict"
/**
 * sm2.js —— SM-2 间隔重复（公式逐字搬自 projects/apps/knowledge-hub/core/review.js）
 *
 * 公式来源：knowledge-hub/core/review.js 的 calculateNextReview(record, quality)。
 * 逐字搬运的部分（G23）：
 *   easiness = max(1.3, easiness + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
 *   quality < 3        → repetitions = 0, interval = 1
 *   quality >= 3 且 repetitions === 0 → interval = 1
 *   quality >= 3 且 repetitions === 1 → interval = 6
 *   否则                → interval = round(interval * easiness)
 *
 * 唯一的一处刻意改动：原版用 `nextDate.setDate(nextDate.getDate() + interval)`
 * （本地日历日），本模块用 `setUTCDate`（UTC 日历日）——日历日语义相同，
 * 但不随机器时区/夏令时漂移，测试可断言确定的日期。
 *
 * 卡片字段用 M1 的 review_cards 表形状（snake_case），因为它要直接进 SQLite。
 */

const DEFAULT_EASE = 2.5
const MIN_EASE = 1.3
const QUALITY_MIN = 0
const QUALITY_MAX = 5

/**
 * 把卡片补成 SM-2 需要的完整形状。
 * @param {object} card
 * @returns {object}
 */
function normalizeCard(card) {
  const src = card || {}
  return {
    problem_id: String(src.problem_id || ""),
    easiness: src.easiness === null || src.easiness === undefined ? DEFAULT_EASE : Number(src.easiness),
    interval_days: src.interval_days === null || src.interval_days === undefined ? 1 : Number(src.interval_days),
    repetitions: src.repetitions === null || src.repetitions === undefined ? 0 : Number(src.repetitions),
    last_quality: src.last_quality === null || src.last_quality === undefined ? null : Number(src.last_quality),
    last_at: src.last_at === null || src.last_at === undefined ? null : String(src.last_at),
    next_review_at: src.next_review_at ? String(src.next_review_at) : new Date().toISOString(),
    lapses: src.lapses === null || src.lapses === undefined ? 0 : Number(src.lapses),
  }
}

/**
 * SM-2 核心：按回忆质量算下一次的间隔与难度因子。
 * @param {object} card 卡片（snake_case）
 * @param {number} quality 0~5 的整数
 * @param {string} nowIso 本次复习时间（ISO）；不传用当前时间
 * @returns {object} 新卡片（snake_case）
 */
function grade(card, quality, nowIso) {
  const q = Number(quality)
  if (!Number.isInteger(q) || q < QUALITY_MIN || q > QUALITY_MAX) {
    throw new Error("评分 quality 必须是 0~5 的整数，收到：" + String(quality))
  }
  const now = nowIso ? new Date(nowIso).toISOString() : new Date().toISOString()
  const current = normalizeCard(card)

  // 更新难度因子（记忆容易度），下限 1.3
  let easiness = Math.max(
    MIN_EASE,
    current.easiness + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
  )

  let interval = current.interval_days
  let repetitions = current.repetitions

  if (q < 3) {
    // 质量低于 3，判定未记住：重置间隔与重复计数
    repetitions = 0
    interval = 1
  } else {
    // 质量 >= 3，增加间隔
    if (repetitions === 0) {
      interval = 1
    } else if (repetitions === 1) {
      interval = 6
    } else {
      interval = Math.round(interval * easiness)
    }
    repetitions += 1
  }

  // 下次复习日期：日历日 + interval 天（UTC 日历日，避免时区漂移）
  const nextDate = new Date(now)
  nextDate.setUTCDate(nextDate.getUTCDate() + interval)

  return {
    problem_id: current.problem_id,
    easiness: easiness,
    interval_days: interval,
    repetitions: repetitions,
    last_quality: q,
    last_at: now,
    next_review_at: nextDate.toISOString(),
    lapses: current.lapses + (q < 3 ? 1 : 0),
  }
}

/**
 * 判题结果 → SM-2 quality（设计文档 §4.2 的表格）。
 * @param {{passed?:boolean, durationMs?:number, medianMs?:number|null,
 *          usedOldSolution?:boolean, copiedReference?:boolean, failedFirst?:boolean}} outcome
 * @returns {number} 0~5
 */
function qualityFromOutcome(outcome) {
  const o = outcome || {}
  if (o.copiedReference === true) return 0
  if (o.passed !== true) return o.failedFirst === true ? 2 : 1
  if (o.usedOldSolution === true) return 3
  if (typeof o.durationMs === "number" && typeof o.medianMs === "number" && o.durationMs > o.medianMs) {
    return 4
  }
  return 5
}

/**
 * 是否到期（next_review_at <= now）。
 * @param {object} card
 * @param {string} nowIso
 * @returns {boolean}
 */
function isDue(card, nowIso) {
  const current = normalizeCard(card)
  const now = nowIso ? new Date(nowIso).getTime() : Date.now()
  return new Date(current.next_review_at).getTime() <= now
}

/**
 * 逾期毫秒数（越大越久没复习）。
 */
function overdueMs(card, nowIso) {
  const current = normalizeCard(card)
  const now = nowIso ? new Date(nowIso).getTime() : Date.now()
  return now - new Date(current.next_review_at).getTime()
}

/**
 * 按逾期时长倒序排到期卡片（逾期最久的排最前）。不改动原数组。
 * @param {object[]} cards
 * @param {string} nowIso
 * @returns {object[]}
 */
function sortByOverdue(cards, nowIso) {
  return (cards || []).slice().sort(function (a, b) {
    const diff = overdueMs(b, nowIso) - overdueMs(a, nowIso)
    if (diff !== 0) return diff
    return String(a.problem_id).localeCompare(String(b.problem_id))
  })
}

module.exports = {
  DEFAULT_EASE: DEFAULT_EASE,
  MIN_EASE: MIN_EASE,
  grade: grade,
  qualityFromOutcome: qualityFromOutcome,
  isDue: isDue,
  sortByOverdue: sortByOverdue,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `9 / 9 套件通过`，退出码 0（M1 的 8 个套件 + 本任务新增的 `sm2.test.js`）

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加 SM-2 间隔重复与判题结果映射

- core/review/sm2.js：公式逐字搬自 knowledge-hub/core/review.js（easiness 下限 1.3）
- grade(card, quality, nowIso)：卡片用 M1 的 review_cards snake_case 形状，可直接进 SQLite
- qualityFromOutcome：按设计文档 §4.2 把判题结果映射到 0~5 六档
- isDue 与 sortByOverdue：到期判断与逾期倒序（不改动原数组）
- 下次复习时间改用 UTC 日历日推进，避免时区与夏令时漂移
- 测试：公式重置分支、easiness 下限、六档映射、到期与排序共 16 条断言"
git push origin main
```

---

## Task 2: 轮次解析（按列名关键词匹配，容错优先）

**Files:**
- Create: `projects/apps/algo-plan/core/sync/rounds.js`
- Create: `projects/apps/algo-plan/tests/rounds-parse.test.js`

**Interfaces:**
- Consumes: 无（纯解析，不碰 SQLite；只用 `node:fs` / `node:path`）
- Produces:
  - `core/sync/rounds.js` 导出：
    - `parseRounds(progressRoot) -> {rounds, warnings}`
      - `round = {id, file, title, goal, status, items}`（契约 §3 的形状）
      - `item  = {raw, id, title, status, doneDate, commitSha}`
      - `round.status` 取 `"active"` / `"done"`；`item.status` 取 `"done"` / `"todo"`
    - `parseRoundText(file, text) -> {round, warnings}`（Task 3 的写回逻辑复用它定位目标行）
  - **额外字段**：每个 round 对象带一个 `startedAt`（`"YYYY-MM-DD"` 或 `""`）——
    接口契约的 round 形状里没有它，但「优先最近创建的 active 轮次」这条排序规则需要它。
    **接口响应不返回它**（`GET /api/rounds` 只回契约里的 6 个字段），只在进程内部用。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/rounds-parse.test.js`：

```javascript
"use strict"
/**
 * rounds-parse.test.js —— 轮次解析：7 种真实表头 + 缺列 + 坏行
 *
 * 夹具里的表头与数据行是从 learning/progress/ 的 9 个真实轮次文件里**原样摘出来的**，
 * 不许改成理想格式——真实文件就是乱的。勘察确认有 7 种表头变体：
 *   r25「ID | 卡片 | 主题 | 状态」
 *   r26「# | 卡片 ID | 主题 | 状态」
 *   r30「卡 ID | 名称 | 状态」
 *   r32「时间戳 | 卡 ID | commit SHA | scaffold 路径 | NOTES 路径 | 审核人」（**整张表没有「状态」列**）
 *   r33「序号 | ID | 名称 | 状态 | 完成时间」
 *   r35「序号 | ID | 名称 | 状态 | 完成时间 | commit SHA」
 *   r36/r37/r38「序号 | ID | 名称 | 语言 | 状态 | 完成时间 | commit SHA」
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const rounds = require("../core/sync/rounds.js")

/** 真实轮次文件的表头 + 首行数据（原样摘录） */
const REAL_TABLES = [
  {
    name: "r25（ID 是序号，卡片才是标识）",
    header: "| ID | 卡片 | 主题 | 状态 |",
    row: "| 1 | epoll | epoll 事件驱动 | done |",
    expect: { id: "epoll", title: "epoll 事件驱动", status: "done", doneDate: "", commitSha: "" },
  },
  {
    name: "r26（# 是序号，卡片 ID 是标识）",
    header: "| # | 卡片 ID | 主题 | 状态 |",
    row: "| 1 | namespace | 网络命名空间(Netns) | done |",
    expect: { id: "namespace", title: "网络命名空间(Netns)", status: "done", doneDate: "", commitSha: "" },
  },
  {
    name: "r30（三列）",
    header: "| 卡 ID | 名称 | 状态 |",
    row: "| basic_types | 基础类型 | done |",
    expect: { id: "basic_types", title: "基础类型", status: "done", doneDate: "", commitSha: "" },
  },
  {
    name: "r32（整张表没有「状态」列）",
    header: "| 时间戳 | 卡 ID | commit SHA | scaffold 路径 | NOTES 路径 | 审核人 |",
    row: "| TBD-deferred | virtual_env | TBD-deferred | learning/scaffold/python/virtual_env/ | learning/scaffold/python/virtual_env/NOTES.md | yinch |",
    expect: { id: "virtual_env", title: "", status: "todo", doneDate: "", commitSha: "TBD-deferred" },
  },
  {
    name: "r33（五列）",
    header: "| 序号 | ID | 名称 | 状态 | 完成时间 |",
    row: "| 1 | big_o | 大 O 分析 | done | 2026-07-12 |",
    expect: { id: "big_o", title: "大 O 分析", status: "done", doneDate: "2026-07-12", commitSha: "" },
  },
  {
    name: "r35（六列）",
    header: "| 序号 | ID | 名称 | 状态 | 完成时间 | commit SHA |",
    row: "| 1 | monkey_testing | 混沌测试/故障注入 | done | 2026-07-12 | TBD-deferred |",
    expect: { id: "monkey_testing", title: "混沌测试/故障注入", status: "done", doneDate: "2026-07-12", commitSha: "TBD-deferred" },
  },
  {
    name: "r36（七列，含语言）",
    header: "| 序号 | ID | 名称 | 语言 | 状态 | 完成时间 | commit SHA |",
    row: "| 1 | thread_basics | 线程基础（pthread 创建/同步/竞态条件） | C | done | 2026-07-12 | TBD-deferred |",
    expect: {
      id: "thread_basics",
      title: "线程基础（pthread 创建/同步/竞态条件）",
      status: "done",
      doneDate: "2026-07-12",
      commitSha: "TBD-deferred",
    },
  },
]

/** 造一个临时 progress 目录 */
function tempProgress(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-progress-"))
  Object.keys(files).forEach(function (name) {
    fs.writeFileSync(path.join(dir, name), files[name], "utf8")
  })
  return dir
}

/** 造一个只含清单表的轮次文件 */
function fileWithTable(header, rows) {
  return [
    "# R99 测试轮次 — 学习进度",
    "",
    "## 基本信息",
    "",
    "| 字段 | 值 |",
    "|------|-----|",
    "| 开始时间 | 2026-11-01 |",
    "| 目标 | 测试轮次 |",
    "",
    header,
    "|---|---|",
  ]
    .concat(rows)
    .join("\n")
}

test("7 种真实表头都能按列名关键词解析出 id / 标题 / 状态", function () {
  REAL_TABLES.forEach(function (spec) {
    const dir = tempProgress({ "r99-progress.md": fileWithTable(spec.header, [spec.row]) })
    const parsed = rounds.parseRounds(dir)
    assert.strictEqual(parsed.rounds.length, 1, spec.name + "：应解析出 1 个轮次")
    const items = parsed.rounds[0].items
    assert.strictEqual(items.length, 1, spec.name + "：应解析出 1 个条目")
    const item = items[0]
    assert.strictEqual(item.id, spec.expect.id, spec.name + "：id 解析错了")
    assert.strictEqual(item.title, spec.expect.title, spec.name + "：标题解析错了")
    assert.strictEqual(item.status, spec.expect.status, spec.name + "：状态解析错了")
    assert.strictEqual(item.doneDate, spec.expect.doneDate, spec.name + "：完成时间解析错了")
    assert.strictEqual(item.commitSha, spec.expect.commitSha, spec.name + "：commit SHA 解析错了")
  })
})

test("缺列的行照常解析，缺的字段填空值", function () {
  const dir = tempProgress({
    "r99-progress.md": fileWithTable("| 卡片 ID | 名称 |", ["| dp_basic | 动态规划基础 |"]),
  })
  const parsed = rounds.parseRounds(dir)
  const item = parsed.rounds[0].items[0]
  assert.strictEqual(item.id, "dp_basic")
  assert.strictEqual(item.title, "动态规划基础")
  assert.strictEqual(item.status, "todo", "没有状态列 → 视为未完成")
  assert.strictEqual(item.doneDate, "")
  assert.strictEqual(item.commitSha, "")
})

test("坏行被跳过并计入告警，其它行不受影响", function () {
  const dir = tempProgress({
    "r99-progress.md": fileWithTable("| 卡片 ID | 名称 | 状态 |", [
      "| dp_basic | 动态规划基础 | done |",
      "| 这行坏了 |",
      "| graph_shortest | 图上最短路 | todo |",
    ]),
  })
  const parsed = rounds.parseRounds(dir)
  assert.strictEqual(parsed.rounds[0].items.length, 2, "坏行应被跳过，其余两行保留")
  assert.ok(parsed.warnings.length > 0, "坏行应产生告警")
  assert.ok(parsed.warnings.some(function (w) { return w.indexOf("跳过") !== -1 }), parsed.warnings.join("|"))
})

test("没有 ID 的行被跳过并计入告警（条目靠 ID 定位）", function () {
  const dir = tempProgress({
    "r99-progress.md": fileWithTable("| 卡片 ID | 名称 | 状态 |", [
      "|  | 没有 ID 的行 | done |",
      "| ok_item | 正常行 | done |",
    ]),
  })
  const parsed = rounds.parseRounds(dir)
  assert.strictEqual(parsed.rounds[0].items.length, 1)
  assert.strictEqual(parsed.rounds[0].items[0].id, "ok_item")
  assert.ok(parsed.warnings.length > 0)
})

test("轮次 ID 从文件名取，标题从一级标题取", function () {
  const dir = tempProgress({
    "r33-progress.md": [
      "# R33 Grokking 算法篇 — 学习进度",
      "",
      "## 基本信息",
      "",
      "| 字段 | 值 |",
      "|------|-----|",
      "| 开始时间 | 2026-07-12 |",
      "| 目标 | Grokking 算法篇 16 张卡片 |",
      "| 状态 | TBD-deferred |",
      "",
      "| 序号 | ID | 名称 | 状态 | 完成时间 |",
      "|------|-----|------|------|----------|",
      "| 1 | big_o | 大 O 分析 | done | 2026-07-12 |",
      "| 2 | arrays | 数组技巧 | done | 2026-07-12 |",
    ].join("\n"),
  })
  const parsed = rounds.parseRounds(dir)
  const round = parsed.rounds[0]
  assert.strictEqual(round.id, "r33")
  assert.strictEqual(round.title, "R33 Grokking 算法篇 — 学习进度")
  assert.strictEqual(round.goal, "Grokking 算法篇 16 张卡片")
  assert.strictEqual(round.startedAt, "2026-07-12")
  assert.strictEqual(round.items.length, 2)
})

test("基本信息里的「状态」是 TBD-deferred 时轮次算 active", function () {
  const dir = tempProgress({
    "r33-progress.md": [
      "# R33 Grokking 算法篇 — 学习进度",
      "",
      "| 字段 | 值 |",
      "|------|-----|",
      "| 状态 | TBD-deferred |",
      "",
      "| 序号 | ID | 名称 | 状态 |",
      "|------|-----|------|------|",
      "| 1 | big_o | 大 O 分析 | done |",
    ].join("\n"),
  })
  const parsed = rounds.parseRounds(dir)
  assert.strictEqual(parsed.rounds[0].status, "active")
})

test("没有状态字段且条目全部 done 时轮次算 done", function () {
  const dir = tempProgress({
    "r25-progress.md": [
      "# R25 Linux 网络基础 — 学习进度",
      "",
      "## 基本信息",
      "",
      "- **开始日期**: 2026-07-12",
      "- **主题**: Linux 网络基础",
      "- **卡数**: 10 张",
      "",
      "| ID | 卡片 | 主题 | 状态 |",
      "|----|------|------|------|",
      "| 1 | epoll | epoll 事件驱动 | done |",
      "| 2 | zero_copy | 零拷贝技术 | done |",
    ].join("\n"),
  })
  const parsed = rounds.parseRounds(dir)
  const round = parsed.rounds[0]
  assert.strictEqual(round.status, "done")
  assert.strictEqual(round.goal, "Linux 网络基础", "无序列表形式的「主题」也要认")
  assert.strictEqual(round.startedAt, "2026-07-12")
})

test("没有清单表的轮次返回空条目并给告警，不整体报错", function () {
  const dir = tempProgress({
    "r99-progress.md": ["# R99 只有标题", "", "## 基本信息", "", "- **主题**: 空轮次"].join("\n"),
  })
  const parsed = rounds.parseRounds(dir)
  assert.strictEqual(parsed.rounds.length, 1)
  assert.deepStrictEqual(parsed.rounds[0].items, [])
  assert.ok(parsed.warnings.length > 0)
})

test("轮次目录不存在时返回空列表 + 告警，不抛错", function () {
  const parsed = rounds.parseRounds(path.join(os.tmpdir(), "algo-plan-不存在-" + Date.now()))
  assert.deepStrictEqual(parsed.rounds, [])
  assert.ok(parsed.warnings.length > 0)
})

test("多个轮次按文件名排序返回", function () {
  const dir = tempProgress({
    "r38-progress.md": fileWithTable("| 卡片 ID | 名称 | 状态 |", ["| a | 甲 | done |"]),
    "r33-progress.md": fileWithTable("| 卡片 ID | 名称 | 状态 |", ["| b | 乙 | done |"]),
  })
  const parsed = rounds.parseRounds(dir)
  assert.deepStrictEqual(parsed.rounds.map(function (r) { return r.id }), ["r33", "r38"])
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/sync/rounds.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/sync/rounds.js`：

```javascript
"use strict"
/**
 * rounds.js —— 轮次解析 / 勾选写回 / 错题订正 / 工作区查脏
 *
 * learning/progress 下的 9 个轮次文件格式极不统一（勘察结论）：
 *   - 一个 frontmatter 都没有，都以 "# R<NN> <主题> — 学习进度" 开头
 *     （r30 是「进度追踪」，r32 是「审计进度日志」）
 *   - 清单表的列名逐个文件不同，实测 7 种表头
 *   - 完成标记是字符串 done，未知值统一是 TBD-deferred
 * 所以解析一律按「列名关键词」匹配，不按列序、不按固定列数（G21）。
 * 解析不了的行跳过并计入告警，绝不整体报错。
 *
 * 本文件先落「解析」部分（Task 2）；写回、错题订正、查脏在 Task 3 追加。
 */

const fs = require("node:fs")
const path = require("node:path")

/**
 * 列角色关键词表。
 * 第一轮按这里的关键词强匹配（同一列只能被一个角色占用，先到先得）；
 * 强 id 优先于 title，「卡片id」这种强写法优先于裸「id」。
 */
const ROLE_KEYWORDS = [
  { role: "id", keywords: ["卡片id", "卡id", "题目id", "题id", "题号"] },
  { role: "title", keywords: ["名称", "标题", "主题", "题目"] },
  { role: "status", keywords: ["状态"] },
  { role: "doneDate", keywords: ["完成时间", "完成日期", "完成日"] },
  { role: "commitSha", keywords: ["commitsha", "commit", "sha"] },
  { role: "language", keywords: ["语言"] },
  { role: "order", keywords: ["序号", "编号"] },
]

/**
 * 表头归一化：转小写、去空白、去星号。
 * 「卡片 ID」→ 「卡片id」，「commit SHA」→ 「commitsha」。
 */
function normalizeHeader(text) {
  return String(text === null || text === undefined ? "" : text)
    .toLowerCase()
    .replace(/\s+/g, "")
    .replace(/[*`]/g, "")
    .trim()
}

/**
 * 拆一行 markdown 表格：去掉首尾的竖线，逐格 trim。
 * @param {string} line
 * @returns {string[]}
 */
function splitRow(line) {
  const trimmed = String(line || "").trim()
  let body = trimmed
  // 左边有 "|" 就切掉，右边有 "|" 也切掉；没有就原样（别把第一列切没了）
  if (body.charAt(0) === "|") body = body.slice(1)
  if (body.charAt(body.length - 1) === "|") body = body.slice(0, -1)
  return body.split("|").map(function (cell) {
    return cell.trim()
  })
}

/**
 * 是不是表格分隔行（|---|---|）。
 */
function isSeparatorRow(cells) {
  if (!cells || cells.length === 0) return false
  return cells.every(function (cell) {
    return cell === "" || /^:?-{2,}:?$/.test(cell)
  })
}

/**
 * 找出文件里所有连续的表格块。
 * @param {string[]} lines
 * @returns {Array<{start:number, rows:Array<{index:number,line:string,cells:string[]}>}>}
 */
function findTableBlocks(lines) {
  const blocks = []
  let current = null
  lines.forEach(function (line, index) {
    const trimmed = line.trim()
    if (trimmed.charAt(0) === "|") {
      if (!current) current = { start: index, rows: [] }
      current.rows.push({ index: index, line: line, cells: splitRow(line) })
      return
    }
    if (current) {
      blocks.push(current)
      current = null
    }
  })
  if (current) blocks.push(current)
  return blocks
}

/**
 * 取某一列的值；列不存在或越界一律返回空串。
 */
function cellAt(cells, index) {
  if (index === undefined || index === null) return ""
  if (!cells || index < 0 || index >= cells.length) return ""
  return String(cells[index]).trim()
}

/**
 * 某一列的所有数据值是不是纯数字。
 */
function allNumeric(rows, index) {
  if (!rows || rows.length === 0) return false
  let seen = 0
  for (const row of rows) {
    const value = cellAt(row.cells, index)
    if (value === "") continue
    seen += 1
    if (!/^\d+$/.test(value)) return false
  }
  return seen > 0
}

/**
 * 按列名关键词把表头映射到角色。
 * @param {string[]} headerCells 表头格
 * @param {Array<{cells:string[]}>} dataRows 数据行（用于判断「纯数字的 ID 列其实是序号」）
 * @returns {Object<string, number>} 角色 → 列下标
 */
function matchColumns(headerCells, dataRows) {
  const norms = headerCells.map(normalizeHeader)
  const assigned = {}
  const taken = {}

  function claim(role, index) {
    if (taken[index]) return false
    assigned[role] = index
    taken[index] = true
    return true
  }

  // 第一轮：关键词强匹配
  ROLE_KEYWORDS.forEach(function (spec) {
    for (let i = 0; i < norms.length; i += 1) {
      if (taken[i]) continue
      const matched = spec.keywords.some(function (kw) {
        return norms[i].indexOf(kw) !== -1
      })
      if (matched) {
        claim(spec.role, i)
        return
      }
    }
  })

  // 第二轮：弱 id 匹配（裸「id」列、「卡片」列）
  const idCandidates = []
  for (let i = 0; i < norms.length; i += 1) {
    if (taken[i]) continue
    const norm = norms[i]
    if (norm.indexOf("id") !== -1 || norm === "卡片" || norm === "卡") {
      idCandidates.push(i)
    }
  }
  let numericIdColumn = -1
  if (idCandidates.length > 0) {
    let picked = -1
    for (const i of idCandidates) {
      if (allNumeric(dataRows, i)) {
        if (numericIdColumn === -1) numericIdColumn = i
        continue
      }
      picked = i
      break
    }
    if (picked === -1) picked = idCandidates[0]
    claim("id", picked)
  }

  // 第三轮：序号列（「#」或含「序」）
  if (assigned.order === undefined) {
    for (let i = 0; i < norms.length; i += 1) {
      if (taken[i]) continue
      const norm = norms[i]
      if (norm === "#" || norm.indexOf("序") !== -1) {
        claim("order", i)
        break
      }
    }
  }

  // 第四轮：全数字的 id 候选列改判成序号（r25 的「ID | 卡片」就是这种情况）
  if (assigned.order === undefined && numericIdColumn !== -1) {
    claim("order", numericIdColumn)
  }

  return assigned
}

/**
 * 解析「基本信息」：两列表格 + 无序列表两种写法都认。
 * 只看清单表之前的行，避免把清单后面的小节误当成基本信息。
 * @param {string[]} lines
 * @param {number} limit 清单表起始行（不含）
 * @returns {{goal: string, status: string, startedAt: string}}
 */
function parseBasicInfo(lines, limit) {
  const info = { goal: "", status: "", startedAt: "" }
  const end = limit === undefined ? lines.length : Math.min(limit, lines.length)

  function apply(key, value) {
    const k = String(key || "").replace(/[*`]/g, "").trim()
    const v = String(value || "").trim()
    if (k === "" || v === "") return
    if (info.goal === "" && (k.indexOf("目标") !== -1 || k.indexOf("主题") !== -1)) {
      info.goal = v
      return
    }
    if (info.status === "" && k.indexOf("状态") !== -1) {
      info.status = v
      return
    }
    if (info.startedAt === "" && k.indexOf("开始") !== -1) {
      info.startedAt = /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : ""
    }
  }

  // 两列表格：| 字段 | 值 |
  findTableBlocks(lines.slice(0, end)).forEach(function (block) {
    if (block.rows[0].cells.length !== 2) return
    block.rows.slice(1).forEach(function (row) {
      if (isSeparatorRow(row.cells)) return
      if (row.cells.length < 2) return
      apply(row.cells[0], row.cells[1])
    })
  })

  // 无序列表：- **开始日期**: 2026-07-12
  for (let i = 0; i < end; i += 1) {
    const m = /^[-*]\s+(.+?)\s*[:：]\s*(.*)$/.exec(String(lines[i]).trim())
    if (!m) continue
    apply(m[1], m[2])
  }

  return info
}

/**
 * 轮次状态：基本信息里有「状态」就用它；否则看条目是否全部完成。
 */
function deriveRoundStatus(infoStatus, items) {
  if (infoStatus) {
    const value = String(infoStatus).trim().toLowerCase()
    if (value === "done" || value === "已完成" || value === "完成") return "done"
    return "active"
  }
  if (items.length > 0 && items.every(function (item) { return item.status === "done" })) {
    return "done"
  }
  return "active"
}

/**
 * 把一行数据组装成 item；解析不了返回 null。
 */
function buildItem(row, columns) {
  const cells = row.cells
  if (!cells || cells.length < 2) return null
  const id = cellAt(cells, columns.id)
  if (id === "") return null
  const statusRaw = cellAt(cells, columns.status).toLowerCase()
  return {
    raw: String(row.line).trim(),
    id: id,
    title: cellAt(cells, columns.title),
    status: statusRaw === "done" ? "done" : "todo",
    doneDate: cellAt(cells, columns.doneDate),
    commitSha: cellAt(cells, columns.commitSha),
  }
}

/**
 * 解析一篇轮次文件。
 * @param {string} file 绝对路径
 * @param {string} text 文件内容
 * @returns {{round: object|null, warnings: string[]}}
 */
function parseRoundText(file, text) {
  const warnings = []
  const lines = String(text || "").replace(/\r\n/g, "\n").split("\n")

  let title = ""
  for (const line of lines) {
    const trimmed = line.trim()
    if (trimmed.charAt(0) === "#") {
      title = trimmed.replace(/^#+\s*/, "").trim()
      break
    }
  }

  const matched = path.basename(file).match(/^(r\d+)/i)
  const id = matched ? matched[1].toLowerCase() : ""

  const blocks = findTableBlocks(lines)
  let itemBlock = null
  for (const block of blocks) {
    if (block.rows.length >= 2 && block.rows[0].cells.length >= 3) {
      itemBlock = block
      break
    }
  }

  const items = []
  if (!itemBlock) {
    warnings.push("没找到清单表（至少 3 列的表格）")
  } else {
    const header = itemBlock.rows[0].cells
    const dataRows = itemBlock.rows.slice(1).filter(function (row) {
      return !isSeparatorRow(row.cells)
    })
    const columns = matchColumns(header, dataRows)
    dataRows.forEach(function (row) {
      const item = buildItem(row, columns)
      if (item === null) {
        warnings.push("第 " + (row.index + 1) + " 行解析不了（列数不对或没有 ID），已跳过")
        return
      }
      items.push(item)
    })
  }

  const info = parseBasicInfo(lines, itemBlock ? itemBlock.start : lines.length)

  const round = {
    id: id,
    file: file,
    title: title,
    goal: info.goal,
    status: deriveRoundStatus(info.status, items),
    items: items,
    startedAt: info.startedAt,
  }
  return { round: round, warnings: warnings }
}

/**
 * 解析一个轮次目录下的全部轮次文件。
 * @param {string} progressRoot learning/progress 目录
 * @returns {{rounds: object[], warnings: string[]}}
 */
function parseRounds(progressRoot) {
  const rounds = []
  const warnings = []
  if (!progressRoot || !fs.existsSync(progressRoot)) {
    return { rounds: rounds, warnings: ["轮次目录不存在：" + String(progressRoot)] }
  }

  let names = []
  try {
    names = fs
      .readdirSync(progressRoot)
      .filter(function (name) {
        return /^r\d+.*\.md$/i.test(name)
      })
      .sort()
  } catch (e) {
    return { rounds: rounds, warnings: ["读取轮次目录失败：" + e.message] }
  }

  names.forEach(function (name) {
    const file = path.join(progressRoot, name)
    let text = ""
    try {
      text = fs.readFileSync(file, "utf8")
    } catch (e) {
      warnings.push(name + "：读取失败（" + e.message + "）")
      return
    }
    const parsed = parseRoundText(file, text)
    if (parsed.round) rounds.push(parsed.round)
    parsed.warnings.forEach(function (w) {
      warnings.push(name + "：" + w)
    })
  })

  return { rounds: rounds, warnings: warnings }
}

module.exports = {
  parseRounds: parseRounds,
  parseRoundText: parseRoundText,
  normalizeHeader: normalizeHeader,
  splitRow: splitRow,
  matchColumns: matchColumns,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `10 / 10 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加轮次解析（按列名关键词匹配）

- core/sync/rounds.js：解析 learning/progress 下的轮次文件
- 实测 7 种表头变体全部按列名关键词映射：ID | 卡片 | 主题 | 状态 /
  # | 卡片 ID | 主题 | 状态 / 卡 ID | 名称 | 状态 /
  时间戳 | 卡 ID | commit SHA | scaffold 路径 | NOTES 路径 | 审核人 /
  序号 | ID | 名称 | 状态 | 完成时间 |（可选 commit SHA）|（可选语言）
- 裸「id」列若全为纯数字则改判为序号，标识符改取「卡片」列（r25 的情况）
- 缺列按空值处理；坏行与无 ID 的行跳过并计入告警，绝不整体报错
- 轮次状态：基本信息有「状态」就用它，否则看条目是否全部 done
- 基本信息同时认「| 字段 | 值 |」两列表与「- **键**: 值」无序列表
- 测试：7 种真实表头 + 缺列 + 坏行 + 无 ID + 轮次状态 + 目录缺失共 12 条断言"
git push origin main
```

---

## Task 3: 写回 learning 仓（查脏、勾选写回、错题订正）与「错题订正」惯例登记

**Files:**
- Modify: `projects/apps/algo-plan/core/sync/rounds.js`（追加写回 / 订正 / 查脏三块）
- Create: `projects/apps/algo-plan/tests/sync-write.test.js`
- Modify: `learning/notes/_meta/schema.md`（登记「错题订正」这个新笔记惯例）

**Interfaces:**
- Consumes: Task 2 的 `core/sync/rounds.js`（`parseRoundText` 与内部列映射逻辑复用）
- Produces（契约 §3 已冻结的三个签名）：
  - `assertCleanWorktree(repoRoot) -> {ok: boolean, dirtyFiles: string[], reason: string}`
    - 契约 §3 冻结的是 `{ok, dirtyFiles}`；这里**多一个 `reason`**（读不到 git 状态时的中文原因），
      是个纯附加字段，不影响既有形状
    - `dirtyFiles` 是被动过的文件路径（相对仓库根）
    - 脏工作区时 `updateRoundItem` / `writeCorrection` 抛错，错误对象带 `status = 409` 与 `dirtyFiles`
  - `updateRoundItem(progressRoot, roundId, itemId, patch) -> {diff, warnings}`
    - `patch = {status?, doneDate?, commitSha?}`；只有给了值的字段才写
    - **只改目标行的目标单元格**，其它行逐字节不变；表里没有对应列时写告警、不新增列
  - `writeCorrection(learningRoot, problem, text) -> {file, diff}`
    - 写到 `<learningRoot>/notes/practice/<problem.id>-订正.md`
    - 文件不存在 → 建（含 frontmatter）；已存在 → 追加一段 `## 订正 <日期>`
  - 附加导出（Task 4/5 用）：`diffLines(before, after)`、`makeDiff(file, before, after)`、`stackForProblem(problem)`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/sync-write.test.js`：

```javascript
"use strict"
/**
 * sync-write.test.js —— 写回 learning 仓：查脏 / 勾选写回 / 错题订正
 *
 * 全部在 fs.mkdtemp 出来的**临时副本**上跑，绝不碰真实的 learning 仓。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const rounds = require("../core/sync/rounds.js")

/** 一篇仿 r33 的轮次文件（表头与真实文件一致） */
const ROUND_FILE = [
  "# R33 Grokking 算法篇 — 学习进度",
  "",
  "## 基本信息",
  "",
  "| 字段 | 值 |",
  "|------|-----|",
  "| 开始时间 | 2026-07-12 |",
  "| 目标 | Grokking 算法篇 16 张卡片 |",
  "| 状态 | TBD-deferred |",
  "",
  "## 16 张卡片清单",
  "",
  "| 序号 | ID | 名称 | 状态 | 完成时间 |",
  "|------|-----|------|------|----------|",
  "| 1 | big_o | 大 O 分析 | done | 2026-07-12 |",
  "| 2 | arrays | 数组技巧 | todo |  |",
  "| 3 | linked_lists | 链表技巧 | todo |  |",
  "",
].join("\n")

/** 造一个干净的临时 learning 仓（带 git 仓库与一个轮次文件） */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-learning-"))
  execFileSync("git", ["init", "-q"], { cwd: root })
  execFileSync("git", ["config", "user.email", "test@example.com"], { cwd: root })
  execFileSync("git", ["config", "user.name", "test"], { cwd: root })
  const progress = path.join(root, "progress")
  fs.mkdirSync(progress, { recursive: true })
  fs.writeFileSync(path.join(progress, "r33-progress.md"), ROUND_FILE, "utf8")
  fs.mkdirSync(path.join(root, "notes"), { recursive: true })
  execFileSync("git", ["add", "-A"], { cwd: root })
  execFileSync("git", ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "初始化"], { cwd: root })
  return root
}

/** 把仓库弄脏 */
function dirty(root, name) {
  fs.writeFileSync(path.join(root, name), "改一下\n", "utf8")
}

const PROBLEM = {
  id: "lc-00001",
  title: "两数之和",
  difficulty: "medium",
  topics: ["哈希表", "数组"],
  tracks: ["interview", "fundamentals"],
}

test("工作区干净时 assertCleanWorktree 返回 ok", function () {
  const root = tempLearning()
  const result = rounds.assertCleanWorktree(root)
  assert.strictEqual(result.ok, true)
  assert.deepStrictEqual(result.dirtyFiles, [])
})

test("工作区脏时 assertCleanWorktree 指出被动过的文件", function () {
  const root = tempLearning()
  dirty(root, path.join("progress", "r33-progress.md"))
  const result = rounds.assertCleanWorktree(root)
  assert.strictEqual(result.ok, false)
  assert.ok(result.dirtyFiles.length > 0)
  assert.ok(
    result.dirtyFiles.some(function (f) { return f.indexOf("r33-progress.md") !== -1 }),
    result.dirtyFiles.join("|")
  )
})

test("不是 git 仓库时返回 ok=false 而不是抛错", function () {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-nogit-"))
  const result = rounds.assertCleanWorktree(dir)
  assert.strictEqual(result.ok, false)
  assert.ok(result.reason.length > 0, "应给出中文原因")
})

test("勾选写回只改目标行，其它行逐字节不变", function () {
  const root = tempLearning()
  const file = path.join(root, "progress", "r33-progress.md")
  const before = fs.readFileSync(file, "utf8").split("\n")

  const result = rounds.updateRoundItem(path.join(root, "progress"), "r33", "arrays", {
    status: "done",
    doneDate: "2026-11-11",
  })

  const after = fs.readFileSync(file, "utf8").split("\n")
  assert.strictEqual(after.length, before.length, "行数不该变")
  let changed = 0
  for (let i = 0; i < before.length; i += 1) {
    if (before[i] !== after[i]) {
      changed += 1
      assert.ok(before[i].indexOf("arrays") !== -1, "只有目标行允许变：" + before[i])
      assert.ok(after[i].indexOf("arrays") !== -1)
      assert.ok(after[i].indexOf("done") !== -1, "目标行应写入 done：" + after[i])
    }
  }
  assert.strictEqual(changed, 1, "只应改一行")
  assert.ok(result.diff.indexOf("arrays") !== -1, "diff 里应能看到目标行")
  assert.ok(result.diff.indexOf("--- a/") === 0, "diff 应有统一的头部")
})

test("勾选写回在脏工作区时拒绝并指出被动过的文件", function () {
  const root = tempLearning()
  dirty(root, path.join("notes", "随手改的.md"))
  assert.throws(
    function () {
      rounds.updateRoundItem(path.join(root, "progress"), "r33", "arrays", { status: "done" })
    },
    function (err) {
      assert.strictEqual(err.status, 409)
      assert.ok(err.dirtyFiles.length > 0)
      assert.ok(err.message.indexOf("不干净") !== -1, err.message)
      return true
    }
  )
})

test("条目不存在时返回 404 语义的错误", function () {
  const root = tempLearning()
  assert.throws(
    function () {
      rounds.updateRoundItem(path.join(root, "progress"), "r33", "不存在的条目", { status: "done" })
    },
    function (err) {
      return err.status === 404
    }
  )
})

test("轮次不存在时返回 404 语义的错误", function () {
  const root = tempLearning()
  assert.throws(
    function () {
      rounds.updateRoundItem(path.join(root, "progress"), "r99", "arrays", { status: "done" })
    },
    function (err) {
      return err.status === 404
    }
  )
})

test("表里没有「完成时间」列时写告警而不是新增列", function () {
  const root = tempLearning()
  fs.writeFileSync(
    path.join(root, "progress", "r30-progress.md"),
    [
      "# R30 Python 基础 — 进度追踪",
      "",
      "| 卡 ID | 名称 | 状态 |",
      "|-------|------|------|",
      "| basic_types | 基础类型 | todo |",
      "",
    ].join("\n"),
    "utf8"
  )
  execFileSync("git", ["add", "-A"], { cwd: root })
  execFileSync("git", ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "补 r30"], { cwd: root })

  const result = rounds.updateRoundItem(path.join(root, "progress"), "r30", "basic_types", {
    status: "done",
    doneDate: "2026-11-11",
  })
  assert.ok(result.warnings.length > 0, "应有告警")
  assert.ok(result.warnings.some(function (w) { return w.indexOf("完成时间") !== -1 }), result.warnings.join("|"))
  const text = fs.readFileSync(path.join(root, "progress", "r30-progress.md"), "utf8")
  assert.ok(text.indexOf("| basic_types | 基础类型 | done |") !== -1, text)
  assert.ok(text.indexOf("完成时间") === -1, "不该新增列：" + text)
})

test("错题订正新建文件：路径、frontmatter 键序、正文结构", function () {
  const root = tempLearning()
  const result = rounds.writeCorrection(root, PROBLEM, "哈希表一次遍历就能出解，先查再插。")

  const expected = path.join(root, "notes", "practice", "lc-00001-订正.md")
  assert.strictEqual(result.file, expected)
  assert.ok(fs.existsSync(expected))
  assert.ok(result.diff.indexOf("--- a/") === 0, "新文件也要给 diff")

  const text = fs.readFileSync(expected, "utf8")
  const keys = text
    .split("---")[1]
    .trim()
    .split("\n")
    .map(function (line) { return line.split(":")[0] })
  assert.deepStrictEqual(keys, [
    "stack",
    "difficulty",
    "status",
    "links",
    "ref",
    "created",
    "updated",
    "tags",
    "unresolved",
    "problem",
  ])
  assert.ok(text.indexOf("stack: c") !== -1, "interview 轨道映射到 stack: c")
  assert.ok(text.indexOf("difficulty: medium") !== -1)
  assert.ok(text.indexOf("tags: [practice, correction]") !== -1)
  assert.ok(text.indexOf("unresolved: true") !== -1)
  assert.ok(text.indexOf("problem: lc-00001") !== -1)
  assert.ok(text.indexOf("## 订正 ") !== -1)
  assert.ok(text.indexOf("先查再插") !== -1)
  assert.ok(text.indexOf("bank/interview/lc-00001.md") !== -1)
})

test("错题订正对已存在的文件是追加，不覆盖原内容", function () {
  const root = tempLearning()
  rounds.writeCorrection(root, PROBLEM, "第一次订正")
  const file = path.join(root, "notes", "practice", "lc-00001-订正.md")
  rounds.writeCorrection(root, PROBLEM, "第二次订正")

  const text = fs.readFileSync(file, "utf8")
  assert.ok(text.indexOf("第一次订正") !== -1, "第一次的内容要保留")
  assert.ok(text.indexOf("第二次订正") !== -1, "第二次的内容要追加")
  assert.strictEqual(text.split("## 订正 ").length - 1, 2, "应有两段订正")
})

test("错题订正在脏工作区时拒绝写入", function () {
  const root = tempLearning()
  dirty(root, path.join("notes", "随手改的.md"))
  assert.throws(
    function () {
      rounds.writeCorrection(root, PROBLEM, "不该写进去")
    },
    function (err) {
      return err.status === 409
    }
  )
  assert.strictEqual(fs.existsSync(path.join(root, "notes", "practice", "lc-00001-订正.md")), false)
})

test("diffLines：单行改动给出一删一增", function () {
  const diff = rounds.diffLines("a\nb\nc\n", "a\nB\nc\n")
  assert.strictEqual(diff.removed, 1)
  assert.strictEqual(diff.added, 1)
  assert.ok(diff.lines.indexOf("-b") !== -1, diff.lines.join("|"))
  assert.ok(diff.lines.indexOf("+B") !== -1, diff.lines.join("|"))
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `assertCleanWorktree is not a function`（`core/sync/rounds.js` 还没有写回相关的导出）

- [ ] **Step 3: 追加写回 / 订正 / 查脏的实现**

Modify `projects/apps/algo-plan/core/sync/rounds.js`：

1. 在文件顶部的 `const fs = ...` / `const path = ...` 之后追加一行：

```javascript
const { execFileSync } = require("node:child_process")
```

2. 在文件末尾 `module.exports = {` **之前**插入下面整块代码：

```javascript
/* ==================== 写回 / 订正 / 查脏 ==================== */

/**
 * track → 笔记 frontmatter 的 stack 枚举。
 * 笔记 schema 的 stack 取值只有 linux/db/c/ds/cpp/python，
 * 题目的 track 只有 interview/fundamentals/advanced/engineering，所以要映射。
 */
const TRACK_STACK = {
  interview: "c",
  fundamentals: "ds",
  advanced: "ds",
  engineering: "db",
}

/**
 * 检查 git 工作区是否干净。
 *
 * 按 G20：用 `git -c core.quotepath=false status --porcelain -z`，**按 NUL 切分**；
 * 路径用「第一个空格之后的全部」切出来，不做 line.slice(3) 硬切
 * （中文路径、重命名记录、带空格的路径都会切错）。
 *
 * @param {string} repoRoot 仓库根目录
 * @returns {{ok: boolean, dirtyFiles: string[], reason: string}}
 */
function assertCleanWorktree(repoRoot) {
  let stdout = ""
  try {
    stdout = execFileSync(
      "git",
      ["-c", "core.quotepath=false", "status", "--porcelain", "-z"],
      { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    )
  } catch (e) {
    return {
      ok: false,
      dirtyFiles: [],
      reason: "读不到 git 状态：" + (e && e.message ? e.message : String(e)),
    }
  }

  const dirtyFiles = []
  String(stdout).split("\0").forEach(function (record) {
    if (record === "") return
    if (!/^[ MADRCU?!][ MADRCU?!] /.test(record)) {
      // 重命名记录里的旧路径（-z 模式下是独立的一段），同样算被动过
      dirtyFiles.push(record)
      return
    }
    const cut = record.indexOf(" ")
    if (cut === -1) {
      dirtyFiles.push(record)
      return
    }
    dirtyFiles.push(record.slice(cut + 1))
  })

  return { ok: dirtyFiles.length === 0, dirtyFiles: dirtyFiles, reason: "" }
}

/** 脏工作区错误（409） */
function dirtyError(dirtyFiles) {
  const err = new Error("learning 仓工作区不干净，拒绝写回。被动过的文件：" + dirtyFiles.join("、"))
  err.status = 409
  err.dirtyFiles = dirtyFiles
  return err
}

/** 找不到东西的错误（404） */
function notFoundError(message) {
  const err = new Error(message)
  err.status = 404
  return err
}

/**
 * 按轮次 ID 找到文件（r33 → r33-progress.md）。
 */
function findRoundFile(progressRoot, roundId) {
  const wanted = String(roundId || "").toLowerCase()
  let names = []
  try {
    names = fs.readdirSync(progressRoot)
  } catch (e) {
    return null
  }
  const hit = names
    .filter(function (name) { return /^r\d+.*\.md$/i.test(name) })
    .sort()
    .find(function (name) {
      const m = name.match(/^(r\d+)/i)
      return m && m[1].toLowerCase() === wanted
    })
  return hit ? path.join(progressRoot, hit) : null
}

/**
 * 在原始行数组里定位某个条目所在的那一行，并带回列映射。
 * @param {string[]} lines 原始行（保持原换行风格切出来的）
 * @param {string} itemId 条目 ID
 * @returns {{lineIndex:number, cells:string[], columns:object}|null}
 */
function locateItemRow(lines, itemId) {
  const blocks = findTableBlocks(lines)
  let itemBlock = null
  for (const block of blocks) {
    if (block.rows.length >= 2 && block.rows[0].cells.length >= 3) {
      itemBlock = block
      break
    }
  }
  if (!itemBlock) return null

  const header = itemBlock.rows[0].cells
  const dataRows = itemBlock.rows.slice(1).filter(function (row) {
    return !isSeparatorRow(row.cells)
  })
  const columns = matchColumns(header, dataRows)
  for (const row of dataRows) {
    if (cellAt(row.cells, columns.id) === itemId) {
      return { lineIndex: row.index, cells: row.cells, columns: columns }
    }
  }
  return null
}

/**
 * 替换单元格但保留原来的缩进空格。
 * 原来的格子是空的（只有空格）时，统一写成一个空格包着新值。
 */
function replaceCell(originalSegment, value) {
  if (originalSegment.trim() === "") return " " + value + " "
  const lead = /^\s*/.exec(originalSegment)[0]
  const trail = /\s*$/.exec(originalSegment)[0]
  return lead + value + trail
}

/**
 * 行级 diff（显示用）：先算最长公共前缀与后缀，中间就是改动部分。
 * @returns {{start:number, removed:number, added:number, lines:string[]}}
 */
function diffLines(before, after, context) {
  const ctx = context === undefined ? 2 : context
  const a = String(before === null || before === undefined ? "" : before).split("\n")
  const b = String(after === null || after === undefined ? "" : after).split("\n")

  let p = 0
  while (p < a.length && p < b.length && a[p] === b[p]) p += 1
  let s = 0
  while (s < a.length - p && s < b.length - p && a[a.length - 1 - s] === b[b.length - 1 - s]) s += 1

  const lines = []
  const ctxStart = Math.max(0, p - ctx)
  for (let i = ctxStart; i < p; i += 1) lines.push(" " + a[i])
  for (let i = p; i < a.length - s; i += 1) lines.push("-" + a[i])
  for (let i = p; i < b.length - s; i += 1) lines.push("+" + b[i])
  if (before !== "" && before !== null && before !== undefined) {
    const ctxEnd = Math.min(a.length, a.length - s + ctx)
    for (let i = a.length - s; i < ctxEnd; i += 1) lines.push(" " + a[i])
  }

  return { start: p + 1, removed: a.length - s - p, added: b.length - s - p, lines: lines }
}

/**
 * 组装 unified 风格的 diff 文本。
 */
function makeDiff(file, before, after) {
  const diff = diffLines(before, after)
  if (diff.lines.length === 0) return ""
  return [
    "--- a/" + file,
    "+++ b/" + file,
    "@@ -" + diff.start + "," + diff.removed + " +" + diff.start + "," + diff.added + " @@",
  ]
    .concat(diff.lines)
    .join("\n")
}

/**
 * 勾选写回：只改目标行的目标单元格。
 * @param {string} progressRoot learning/progress 目录
 * @param {string} roundId 轮次 ID（如 r33）
 * @param {string} itemId 条目 ID
 * @param {{status?:string, doneDate?:string, commitSha?:string}} patch
 * @returns {{diff: string, warnings: string[]}}
 */
function updateRoundItem(progressRoot, roundId, itemId, patch) {
  const options = patch || {}
  const warnings = []
  const repoRoot = path.dirname(path.resolve(progressRoot))

  const clean = assertCleanWorktree(repoRoot)
  if (!clean.ok) throw dirtyError(clean.dirtyFiles)

  const file = findRoundFile(progressRoot, roundId)
  if (!file) throw notFoundError("找不到轮次：" + roundId)

  const before = fs.readFileSync(file, "utf8")
  const eol = before.indexOf("\r\n") !== -1 ? "\r\n" : "\n"
  const lines = before.split(eol)

  const located = locateItemRow(lines, itemId)
  if (!located) throw notFoundError("轮次 " + roundId + " 里找不到条目：" + itemId)

  const cells = located.cells.slice()
  const columns = located.columns
  const targets = [
    { key: "status", column: "status", label: "状态" },
    { key: "doneDate", column: "doneDate", label: "完成时间" },
    { key: "commitSha", column: "commitSha", label: "commit SHA" },
  ]
  targets.forEach(function (target) {
    const value = options[target.key]
    if (value === undefined || value === null) return
    if (columns[target.column] === undefined) {
      warnings.push("该轮次的清单表没有「" + target.label + "」列，无法写入")
      return
    }
    cells[columns[target.column]] = String(value)
  })

  const originalLine = lines[located.lineIndex]
  const segments = originalLine.split("|")
  const offset = originalLine.trim().charAt(0) === "|" ? 1 : 0
  cells.forEach(function (value, index) {
    const at = offset + index
    if (at < 0 || at >= segments.length) return
    segments[at] = replaceCell(segments[at], value)
  })
  lines[located.lineIndex] = segments.join("|")
  const after = lines.join(eol)

  if (after === before) {
    return { diff: "", warnings: warnings }
  }
  fs.writeFileSync(file, after, "utf8")
  return { diff: makeDiff(path.relative(repoRoot, file), before, after), warnings: warnings }
}

/**
 * 题目 → 笔记 frontmatter 的 stack。
 */
function stackForProblem(problem) {
  const tracks = (problem && problem.tracks) || []
  for (const track of tracks) {
    if (TRACK_STACK[track]) return TRACK_STACK[track]
  }
  return "c"
}

/** 今天的日期（本地时区，YYYY-MM-DD） */
function todayStamp() {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const d = String(now.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + d
}

/**
 * 错题订正的 frontmatter。
 * 键序：notes/_meta/schema.md 的基线 8 键顺序不变，扩展键 unresolved / problem 追加在后面。
 */
function renderCorrectionFrontmatter(problem, today) {
  return [
    "---",
    "stack: " + stackForProblem(problem),
    "difficulty: " + (problem.difficulty || "medium"),
    "status: in-progress",
    "links: []",
    "ref: []",
    "created: " + today,
    "updated: " + today,
    "tags: [practice, correction]",
    "unresolved: true",
    "problem: " + problem.id,
    "---",
  ].join("\n")
}

/**
 * 一段订正正文。
 */
function renderCorrectionSection(problem, text, today) {
  const track = (problem.tracks && problem.tracks[0]) || "interview"
  const topics = (problem.topics || []).join("、")
  return [
    "## 订正 " + today,
    "",
    String(text || "").trim(),
    "",
    "## 关联",
    "",
    "- 题目：`bank/" + track + "/" + problem.id + ".md`（`" + problem.id + "`）",
    "- 知识点：" + (topics || "（无）"),
  ].join("\n")
}

/**
 * 写错题订正：新建或追加一篇 notes/practice/<id>-订正.md。
 * @param {string} learningRoot learning 仓根目录
 * @param {object} problem M1 的 Problem 形状
 * @param {string} text 订正正文
 * @returns {{file: string, diff: string}}
 */
function writeCorrection(learningRoot, problem, text) {
  const clean = assertCleanWorktree(learningRoot)
  if (!clean.ok) throw dirtyError(clean.dirtyFiles)

  const id = String(problem.id)
  const dir = path.join(learningRoot, "notes", "practice")
  const file = path.join(dir, id + "-订正.md")
  const rel = path.join("notes", "practice", id + "-订正.md")
  const today = todayStamp()

  let before = ""
  if (fs.existsSync(file)) before = fs.readFileSync(file, "utf8")

  let after
  if (before.trim() === "") {
    after = [
      renderCorrectionFrontmatter(problem, today),
      "",
      "# " + (problem.title || id) + " · 错题订正",
      "",
      renderCorrectionSection(problem, text, today),
      "",
    ].join("\n")
  } else {
    after = before.replace(/\s*$/, "") + "\n\n" + renderCorrectionSection(problem, text, today) + "\n"
  }

  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(file, after, "utf8")
  return { file: file, diff: makeDiff(rel, before, after) }
}
```

3. 把文件末尾的 `module.exports` 整段替换成：

```javascript
module.exports = {
  parseRounds: parseRounds,
  parseRoundText: parseRoundText,
  normalizeHeader: normalizeHeader,
  splitRow: splitRow,
  matchColumns: matchColumns,
  assertCleanWorktree: assertCleanWorktree,
  updateRoundItem: updateRoundItem,
  writeCorrection: writeCorrection,
  diffLines: diffLines,
  makeDiff: makeDiff,
  stackForProblem: stackForProblem,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `11 / 11 套件通过`，退出码 0

- [ ] **Step 5: 在 learning 仓登记「错题订正」惯例**

Modify `learning/notes/_meta/schema.md`：

1. 在「## 字段说明」的表格末尾（`tags` 那一行之后）追加两行：

```markdown
| `unresolved` | boolean | ⬜ | 扩展键（`question` / `correction` 专用）：`true` 表示还没解决，会出现在仪表盘的「待解决疑问」清单里 |
| `problem` | string | ⬜ | 扩展键（`correction` 专用）：关联的题目 ID（如 `lc-00001`），是笔记与题库之间的连接键 |
```

2. 在「## 笔记类型」的表格末尾追加一行：

```markdown
| `correction` | `_templates/correction.md` | `status` 默认 `in-progress`，`tags` 必填 `[practice, correction]`，追加 `unresolved` 与 `problem` 两个扩展键 |
```

3. 在文件末尾（`## 渐进式迁移策略` 之前）插入下面这一整节：

```markdown
## 错题订正（correction）惯例

M4 起，app 会把做错题的复盘写进 `notes/practice/<题目ID>-订正.md`。这是新建的惯例。

- **目录**：`notes/practice/`，一个题目一篇，文件名 `<题目ID>-订正.md`
- **frontmatter 键序**：基线 8 键（`stack` / `difficulty` / `status` / `links` / `ref` / `created` / `updated` / `tags`）顺序不变，
  扩展键 `unresolved` 与 `problem` 追加在后面
- **`stack` 取值**：按题目的 track 映射——`interview→c`、`fundamentals→ds`、`advanced→ds`、`engineering→db`
- **`difficulty`**：直接取题目的难度（`easy` / `medium` / `hard`）
- **`status`**：默认 `in-progress`；订正做完改成 `done`
- **`tags`**：固定 `[practice, correction]`
- **`unresolved`**：默认 `true`——还没弄透就保持 `true`，它会出现在「待解决疑问」清单里；弄透后改成 `false`
- **`problem`**：题目的稳定 ID（如 `lc-00001`）
- **正文结构**：`## 订正 <日期>` 小节（可追加多段），末尾 `## 关联` 列出题目路径与知识点

示例：

```markdown
---
stack: c
difficulty: medium
status: in-progress
links: []
ref: []
created: 2026-11-11
updated: 2026-11-11
tags: [practice, correction]
unresolved: true
problem: lc-00001
---

# 两数之和 · 错题订正

## 订正 2026-11-11

哈希表一次遍历就能出解：先查再插，别先插再查。

## 关联

- 题目：`bank/interview/lc-00001.md`（`lc-00001`）
- 知识点：哈希表、数组
```
```

> **说明**：`_templates/correction.md` 这个模板文件本计划不生成（M4 只在运行时按上面的格式落盘）。
> 要模板的话，复制 `_templates/question.md` 改键名即可。

- [ ] **Step 6: 提交并推送（projects 仓）**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加 learning 仓写回（查脏 / 勾选 / 错题订正）

- core/sync/rounds.js：assertCleanWorktree 用 git status --porcelain -z 按 NUL 切分，
  路径取第一个空格之后的全部，不做 slice(3) 硬切
- updateRoundItem：只替换目标行的目标单元格，其余行逐字节不变；缺列写告警不新增列
- writeCorrection：新建或追加 notes/practice/<id>-订正.md，frontmatter 键序对齐 schema
- 脏工作区一律拒绝写回并返回 409 + 被动过的文件列表
- 写后返回 unified 风格 diff，绝不自动 commit
- 测试：查脏、只改目标行、缺列、脏仓拒绝、订正新建与追加共 13 条断言"
git push origin main
```

- [ ] **Step 7: 提交并推送（learning 子仓的惯例登记）**

```bash
cd /c/code/StillEvolving/learning
git add notes/_meta/schema.md
git commit -m "docs(notes): 登记错题订正（correction）笔记惯例

- notes/_meta/schema.md：新增 correction 类型与 unresolved / problem 两个扩展键
- 说明 notes/practice/<题目ID>-订正.md 的目录、键序、stack 映射与正文结构
- 错题订正默认 unresolved: true，会出现在仪表盘的「待解决疑问」清单里"
git push origin main
```

> **这一步是本计划唯一一次改 learning 仓的源码。** app 运行时对 learning 仓的写入（勾选写回、
> 错题订正）由用户在界面上触发，**app 与本计划都不会自动 `git commit`**（G11）。

---

## Task 4: 推下一题（候选动作优先级 + 单日配额）

**Files:**
- Create: `projects/apps/algo-plan/core/scheduler/next-action.js`
- Modify: `projects/apps/algo-plan/server/db.js`（**只新增**两个方法，不动 M1 已有方法）
- Create: `projects/apps/algo-plan/tests/next-action.test.js`

**Interfaces:**
- Consumes:
  - M1 的 `store.listDueCards(nowIso)` / `store.getSetting(key, fallback)` / `store.setSetting(key, value)` / `store.allSettings()` / `store.insertAttempt(attempt)`
  - Task 1 的 `sortByOverdue(cards, nowIso) -> card[]`
  - Task 2 的 `parseRounds(progressRoot) -> {rounds, warnings}`（轮次对象形状 `{id, file, title, goal, status, items}`）
- Produces:
  - `nextAction(ctx) -> action | null`
    - `ctx = {store, provider, rounds, nowIso, settings}`（契约 §3 列的五个字段**全部照用**）
    - **契约之外新增两个可选字段**（不改既有字段、不改签名）：
      - `problems`（题库快照数组）——`nextAction` 是**同步**函数，而 M1 的 `provider.list()` 是异步的，
        所以由调用方（Task 5 的接口层）先 `await provider.list()` 再把快照塞进 ctx。
        不传就当成空数组：复习与轮次分支照常工作，探索分支没有题可推。
      - `currentRoundId`（字符串）——对应设计文档 §4.1「今日页顶部可手动切换当前轮次」；
        不传就自动选「最近创建的 active 轮次」。
    - `action = {kind: "review"|"round"|"explore", problemId, problem, estimatedMinutes, reason, reviewQueueLength}`
      - 契约冻结的六个字段一个不少；**额外**带一个 `title`（显示用标题）——
        轮次条目未必能在题库里找到对应题目，这时 `problem` 为 `null`，界面仍要有标题可显示。
  - `quotaState(store, nowIso, settings) -> {date, questions, minutes, limitQuestions, limitMinutes, exhausted, exhaustedBy}`
  - `consumeQuota(store, usage, nowIso) -> {questions, minutes}`
  - `estimateMinutes(problem, avgByDifficulty) -> number`
  - `masteryByTopic(problems, attemptsByProblem) -> {topic: number}`
  - `dayKey(nowIso) -> "YYYY-MM-DD"`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/next-action.test.js`：

```javascript
"use strict"
/**
 * next-action.test.js —— 推下一题：优先级 / 单日配额 / 轮次挑选
 */

const test = require("node:test")
const assert = require("node:assert")

const { openDb, createStore } = require("../server/db.js")
const scheduler = require("../core/scheduler/next-action.js")

const NOW = "2026-11-11T09:00:00.000Z"

/** 本地日期键（独立实现，不复用被测模块的函数） */
function localDayKey(iso) {
  const d = new Date(iso)
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return d.getFullYear() + "-" + m + "-" + day
}

function freshStore() {
  const db = openDb(":memory:")
  return { db: db, store: createStore(db) }
}

function addCard(store, problemId, nextReviewAt) {
  store.upsertReviewCard({
    problem_id: problemId,
    easiness: 2.5,
    interval_days: 1,
    repetitions: 1,
    last_quality: 4,
    last_at: "2026-11-01T00:00:00.000Z",
    next_review_at: nextReviewAt,
    lapses: 0,
  })
}

function addAttempt(store, problemId, verdict, ts) {
  store.insertAttempt({
    problem_id: problemId,
    ts: ts || "2026-11-01T00:00:00.000Z",
    language: "cpp",
    code: "int main(){}",
    verdict: verdict,
    passed_cases: verdict === "pass" ? 2 : 0,
    total_cases: 2,
    duration_ms: 600000,
    mode: "solve",
  })
}

function makeItem(id, title, status) {
  return {
    raw: "| " + id + " | " + title + " | " + (status || "todo") + " |",
    id: id,
    title: title,
    status: status || "todo",
    doneDate: "",
    commitSha: "",
  }
}

function makeRound(id, startedAt, items) {
  return {
    id: id,
    file: "/fake/" + id + "-progress.md",
    title: id + " 轮次",
    goal: "把 " + id + " 刷完",
    status: "active",
    startedAt: startedAt,
    items: items,
  }
}

function makeCtx(store, extra) {
  return Object.assign(
    {
      store: store,
      provider: null,
      rounds: [],
      nowIso: NOW,
      settings: store.allSettings(),
      problems: [],
    },
    extra || {}
  )
}

const PROBLEMS = [
  {
    id: "lc-00001",
    title: "两数之和",
    difficulty: "medium",
    topics: ["哈希表"],
    tracks: ["interview"],
  },
  {
    id: "lc-00002",
    title: "三数之和",
    difficulty: "medium",
    topics: ["双指针"],
    tracks: ["interview"],
  },
]

test("有到期卡片时先给复习动作", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-10T00:00:00.000Z")
  const action = scheduler.nextAction(makeCtx(store, { problems: PROBLEMS }))
  assert.ok(action)
  assert.strictEqual(action.kind, "review")
  assert.strictEqual(action.problemId, "lc-00001")
  assert.strictEqual(action.reviewQueueLength, 1)
  assert.ok(action.reason.indexOf("复习") !== -1, action.reason)
  db.close()
})

test("逾期越久的卡片排在前面", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-01T00:00:00.000Z")
  addCard(store, "lc-00002", "2026-11-11T00:00:00.000Z")
  const action = scheduler.nextAction(makeCtx(store, { problems: PROBLEMS }))
  assert.strictEqual(action.problemId, "lc-00001", "逾期十天的比刚到期的更该先做")
  db.close()
})

test("复习题数配额用满后让位给轮次推进", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-10T00:00:00.000Z")
  store.setSetting("review.used.questions." + localDayKey(NOW), "10")
  const rounds = [makeRound("r33", "2026-07-12", [makeItem("arrays", "数组技巧", "todo")])]
  const action = scheduler.nextAction(
    makeCtx(store, { rounds: rounds, problems: PROBLEMS })
  )
  assert.strictEqual(action.kind, "round")
  assert.strictEqual(action.reviewQueueLength, 1, "队列长度照实报")
  db.close()
})

test("复习分钟配额用满后同样让位", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-10T00:00:00.000Z")
  store.setSetting("review.used.minutes." + localDayKey(NOW), "20")
  const rounds = [makeRound("r33", "2026-07-12", [makeItem("arrays", "数组技巧", "todo")])]
  const action = scheduler.nextAction(
    makeCtx(store, { rounds: rounds, problems: PROBLEMS })
  )
  assert.strictEqual(action.kind, "round")
  db.close()
})

test("配额上限可以在 settings 里调小", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-10T00:00:00.000Z")
  store.setSetting("review.daily_quota_questions", "0")
  const rounds = [makeRound("r33", "2026-07-12", [makeItem("arrays", "数组技巧", "todo")])]
  const action = scheduler.nextAction(
    makeCtx(store, { rounds: rounds, problems: PROBLEMS })
  )
  assert.strictEqual(action.kind, "round")
  db.close()
})

test("多个 active 轮次优先最近创建的", function () {
  const { db, store } = freshStore()
  const rounds = [
    makeRound("r30", "2026-05-01", [makeItem("a", "旧轮次的题", "todo")]),
    makeRound("r38", "2026-10-01", [makeItem("b", "新轮次的题", "todo")]),
  ]
  const action = scheduler.nextAction(makeCtx(store, { rounds: rounds, problems: PROBLEMS }))
  assert.strictEqual(action.kind, "round")
  assert.strictEqual(action.problemId, null, "没匹配到题库题目时 problemId 为空")
  assert.ok(action.reason.indexOf("r38") !== -1, action.reason)
  db.close()
})

test("手动指定当前轮次时按指定的来", function () {
  const { db, store } = freshStore()
  const rounds = [
    makeRound("r30", "2026-05-01", [makeItem("a", "旧轮次的题", "todo")]),
    makeRound("r38", "2026-10-01", [makeItem("b", "新轮次的题", "todo")]),
  ]
  const action = scheduler.nextAction(
    makeCtx(store, { rounds: rounds, problems: PROBLEMS, currentRoundId: "r30" })
  )
  assert.ok(action.reason.indexOf("r30") !== -1, action.reason)
  db.close()
})

test("轮次里掌握度最低的 topic 优先", function () {
  const { db, store } = freshStore()
  // 哈希表：首次尝试失败 → 掌握度低；双指针：首次通过 → 掌握度高
  addAttempt(store, "lc-00001", "wrong_answer")
  addAttempt(store, "lc-00002", "pass")
  const rounds = [
    makeRound("r33", "2026-07-12", [
      makeItem("two_sum", "三数之和", "todo"),
      makeItem("hash", "两数之和", "todo"),
    ]),
  ]
  const action = scheduler.nextAction(
    makeCtx(store, { rounds: rounds, problems: PROBLEMS })
  )
  assert.strictEqual(action.kind, "round")
  assert.strictEqual(action.problemId, "lc-00001", "掌握度低的「哈希表」应排前面")
  db.close()
})

test("同一 topic 内按清单里的题号顺序", function () {
  const { db, store } = freshStore()
  const same = [
    { id: "lc-00001", title: "两数之和", difficulty: "medium", topics: ["哈希表"], tracks: ["interview"] },
    { id: "lc-00002", title: "三数之和", difficulty: "medium", topics: ["哈希表"], tracks: ["interview"] },
  ]
  const rounds = [
    makeRound("r33", "2026-07-12", [
      makeItem("first", "两数之和", "todo"),
      makeItem("second", "三数之和", "todo"),
    ]),
  ]
  const action = scheduler.nextAction(makeCtx(store, { rounds: rounds, problems: same }))
  assert.strictEqual(action.problemId, "lc-00001", "同 topic 取清单里靠前的那题")
  db.close()
})

test("没有 active 轮次时退回主动探索", function () {
  const { db, store } = freshStore()
  const action = scheduler.nextAction(makeCtx(store, { problems: PROBLEMS }))
  assert.strictEqual(action.kind, "explore")
  assert.strictEqual(action.problemId, "lc-00001")
  db.close()
})

test("每次只给一个动作并带耗时估算", function () {
  const { db, store } = freshStore()
  addCard(store, "lc-00001", "2026-11-10T00:00:00.000Z")
  const action = scheduler.nextAction(makeCtx(store, { problems: PROBLEMS }))
  assert.ok(action && !Array.isArray(action))
  assert.ok(action.estimatedMinutes > 0, "要有「这一步大约 N 分钟」")
  assert.strictEqual(action.title, "两数之和")
  assert.strictEqual(typeof action.reason, "string")
  db.close()
})

test("做过的题不会被当成探索目标", function () {
  const { db, store } = freshStore()
  addAttempt(store, "lc-00001", "pass")
  const action = scheduler.nextAction(makeCtx(store, { problems: PROBLEMS }))
  assert.strictEqual(action.problemId, "lc-00002")
  db.close()
})

test("没有任何可推的动作时返回 null", function () {
  const { db, store } = freshStore()
  const action = scheduler.nextAction(makeCtx(store, { problems: [] }))
  assert.strictEqual(action, null)
  db.close()
})

test("consumeQuota 把题数与分钟记到今天的键上", function () {
  const { db, store } = freshStore()
  const result = scheduler.consumeQuota(store, { questions: 1, minutes: 15 }, NOW)
  assert.strictEqual(result.questions, 1)
  assert.strictEqual(result.minutes, 15)
  assert.strictEqual(store.getSetting("review.used.questions." + localDayKey(NOW)), "1")
  assert.strictEqual(store.getSetting("review.used.minutes." + localDayKey(NOW)), "15")
  db.close()
})

test("quotaState 报出是哪一项配额用满了", function () {
  const { db, store } = freshStore()
  store.setSetting("review.used.questions." + localDayKey(NOW), "10")
  const state = scheduler.quotaState(store, NOW, store.allSettings())
  assert.strictEqual(state.exhausted, true)
  assert.strictEqual(state.exhaustedBy, "questions")
  assert.strictEqual(state.limitQuestions, 10)
  assert.strictEqual(state.limitMinutes, 20)
  db.close()
})

test("masteryByTopic 首次通过率低的主题分数更低", function () {
  const attempts = {
    "lc-00001": [{ problem_id: "lc-00001", verdict: "wrong_answer" }],
    "lc-00002": [{ problem_id: "lc-00002", verdict: "pass" }],
  }
  const mastery = scheduler.masteryByTopic(PROBLEMS, attempts)
  assert.ok(mastery["哈希表"] < mastery["双指针"], JSON.stringify(mastery))
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/scheduler/next-action.js'`

- [ ] **Step 3: 给 db.js 追加两个只读方法**

Modify `projects/apps/algo-plan/server/db.js`，在 `createStore` 返回对象里，
**紧接在 `countAttempts` 之后**插入：

```javascript
    /* ---------- attempts（M4 追加：只读，不动已有方法） ---------- */

    listAttempts: function () {
      return db.prepare("SELECT * FROM attempts ORDER BY ts ASC, id ASC").all()
    },

    countAttemptsSince: function (iso) {
      const row = db
        .prepare("SELECT COUNT(*) AS n FROM attempts WHERE ts >= ?")
        .get(String(iso))
      return Number(row.n)
    },
```

> **不要改** M1 已冻结的 `insertAttempt` / `listAttemptsByProblem` / `countAttempts`，
> 也**不要改** `SCHEMA`（表结构不动）。

- [ ] **Step 4: 写实现**

Create `projects/apps/algo-plan/core/scheduler/next-action.js`：

```javascript
"use strict"
/**
 * core/scheduler/next-action.js —— 推下一题
 *
 * 候选动作的优先级（设计文档 §4.1）：
 *   1. 到期复习：next_review_at <= now 的卡片，逾期越久越靠前
 *   2. 轮次推进：多个 active 轮次优先最近创建的；轮次内掌握度最低的 topic 优先，
 *                同一 topic 内按清单里的题号顺序
 *   3. 主动探索：没有 active 轮次时的兜底，挑没做过的题
 *
 * 单日配额「10 题 **或** 20 分钟，取先到者」：任一顶到就不再推复习。
 * 配额上限在 settings 表（review.daily_quota_questions / review.daily_quota_minutes），
 * 用量记在同表的日期作用域键上（review.used.questions.<日期> / review.used.minutes.<日期>）。
 */

const fs = require("node:fs")
const { sortByOverdue } = require("../review/sm2.js")

/** 各难度的基准耗时（分钟） */
const BASE_MINUTES = { easy: 10, medium: 15, hard: 25 }

/** 单日配额默认值 */
const DEFAULT_QUOTA_QUESTIONS = 10
const DEFAULT_QUOTA_MINUTES = 20

/**
 * 本地日期键 YYYY-MM-DD（配额按本地日计）。
 */
function dayKey(nowIso) {
  const d = new Date(nowIso)
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return d.getFullYear() + "-" + m + "-" + day
}

/**
 * 读今天的配额状态。
 * @param {object} store M1 的 store
 * @param {string} nowIso
 * @param {object} settings settings 表的全量键值
 */
function quotaState(store, nowIso, settings) {
  const conf = settings || {}
  const date = dayKey(nowIso)
  const limitQuestions = Number(conf["review.daily_quota_questions"] || DEFAULT_QUOTA_QUESTIONS)
  const limitMinutes = Number(conf["review.daily_quota_minutes"] || DEFAULT_QUOTA_MINUTES)
  const questions = Number(store.getSetting("review.used.questions." + date, "0"))
  const minutes = Number(store.getSetting("review.used.minutes." + date, "0"))
  const byQuestions = questions >= limitQuestions
  const byMinutes = minutes >= limitMinutes
  return {
    date: date,
    questions: questions,
    minutes: minutes,
    limitQuestions: limitQuestions,
    limitMinutes: limitMinutes,
    exhausted: byQuestions || byMinutes,
    exhaustedBy: byQuestions ? "questions" : byMinutes ? "minutes" : null,
  }
}

/**
 * 记一次配额消耗。
 */
function consumeQuota(store, usage, nowIso) {
  const date = dayKey(nowIso)
  const add = usage || {}
  const questions =
    Number(store.getSetting("review.used.questions." + date, "0")) + Number(add.questions || 0)
  const minutes =
    Number(store.getSetting("review.used.minutes." + date, "0")) + Number(add.minutes || 0)
  store.setSetting("review.used.questions." + date, String(questions))
  store.setSetting("review.used.minutes." + date, String(minutes))
  return { questions: questions, minutes: minutes }
}

/**
 * 估算这一步要花多少分钟：有该难度的历史平均用时就用它，和难度基准取较大者。
 */
function estimateMinutes(problem, avgByDifficulty) {
  const difficulty = (problem && problem.difficulty) || "medium"
  const base = BASE_MINUTES[difficulty] || BASE_MINUTES.medium
  const avg = avgByDifficulty ? avgByDifficulty[difficulty] : null
  if (avg === null || avg === undefined || Number.isNaN(Number(avg))) return base
  const historical = Math.max(1, Math.round(Number(avg) / 60000))
  return Math.max(base, historical)
}

/**
 * 按题目把尝试记录分组（rows 按时间升序，第一条就是首次尝试）。
 */
function groupAttemptsByProblem(attempts) {
  const out = {}
  ;(attempts || []).forEach(function (row) {
    const id = String(row.problem_id)
    if (!out[id]) out[id] = []
    out[id].push(row)
  })
  return out
}

/**
 * 各难度的历史平均用时（毫秒）。
 */
function averageMsByDifficulty(problems, attemptsByProblem) {
  const sums = {}
  const counts = {}
  ;(problems || []).forEach(function (p) {
    const rows = attemptsByProblem[String(p.id)] || []
    rows.forEach(function (row) {
      const ms = Number(row.duration_ms || 0)
      if (!ms) return
      const d = p.difficulty || "medium"
      sums[d] = (sums[d] || 0) + ms
      counts[d] = (counts[d] || 0) + 1
    })
  })
  const out = {}
  Object.keys(sums).forEach(function (d) {
    out[d] = sums[d] / counts[d]
  })
  return out
}

/**
 * 主题掌握度近似值。
 *
 *   首次通过率 = 首次尝试就过的比例
 *   掌握度     = 0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)
 *
 * M4 先不含遗忘因子（0.5 ^ (距上次练习天数/14)）——那需要每个 topic 的上次练习时间，
 * M5 落地后整体换成 core/mastery/mastery.js 的 masteryOf()，调用方接口不变。
 * 一个题都没练过的 topic 给 0.3（只剩 e^0 那一项），也就是最该补的短板。
 */
function masteryByTopic(problems, attemptsByProblem) {
  const topics = {}
  ;(problems || []).forEach(function (p) {
    ;(p.topics || []).forEach(function (t) {
      if (!topics[t]) topics[t] = { ids: [], firstPass: 0, firstTotal: 0, lapses: 0 }
      topics[t].ids.push(String(p.id))
    })
  })

  const out = {}
  Object.keys(topics).forEach(function (t) {
    const stat = topics[t]
    stat.ids.forEach(function (id) {
      const rows = attemptsByProblem[id] || []
      if (rows.length === 0) return
      const first = rows[0]
      stat.firstTotal += 1
      if (String(first.verdict) === "pass") stat.firstPass += 1
      else stat.lapses += 1
    })
    if (stat.firstTotal === 0) {
      out[t] = 0.3
    } else {
      const rate = stat.firstPass / stat.firstTotal
      out[t] = 0.7 * rate + 0.3 * Math.exp(-stat.lapses / 2)
    }
  })
  return out
}

/**
 * 题库索引：按 ID 与标题各建一张表。
 */
function buildProblemIndex(problems) {
  const byId = new Map()
  const byTitle = new Map()
  ;(problems || []).forEach(function (p) {
    if (!p) return
    if (p.id) byId.set(String(p.id), p)
    if (p.title) byTitle.set(String(p.title), p)
  })
  return { byId: byId, byTitle: byTitle }
}

/**
 * 轮次条目 → 题库题目：先按 ID 精确匹配，再按标题精确匹配；都匹配不上返回 null。
 */
function matchProblem(item, index) {
  if (index.byId.has(String(item.id))) return index.byId.get(String(item.id))
  if (item.title && index.byTitle.has(String(item.title))) return index.byTitle.get(String(item.title))
  return null
}

/**
 * 条目所属的 topic：优先取匹配到的题目的第一个 topic；匹配不上就用条目标题当临时 topic。
 */
function topicOf(item, index) {
  const problem = matchProblem(item, index)
  if (problem && problem.topics && problem.topics.length > 0) return problem.topics[0]
  return String(item.title || item.id)
}

/**
 * 轮次的「最近创建」排序键：开始时间优先，没有就用文件修改时间。
 */
function roundCreatedKey(round) {
  if (round && round.startedAt) return String(round.startedAt)
  try {
    return fs.statSync(round.file).mtime.toISOString()
  } catch (e) {
    return ""
  }
}

/**
 * 选当前轮次：手动指定 > 最近创建的 active 轮次。
 */
function pickRound(rounds, currentRoundId) {
  const list = rounds || []
  if (currentRoundId) {
    const wanted = String(currentRoundId).toLowerCase()
    const hit = list.find(function (r) {
      return String(r.id).toLowerCase() === wanted
    })
    if (hit) return hit
  }
  const active = list.filter(function (r) {
    return r.status === "active"
  })
  if (active.length === 0) return null
  active.sort(function (a, b) {
    const ka = roundCreatedKey(a)
    const kb = roundCreatedKey(b)
    if (ka !== kb) return ka < kb ? 1 : -1
    return String(a.id).toLowerCase() < String(b.id).toLowerCase() ? -1 : 1
  })
  return active[0]
}

/**
 * 轮次里挑一题：掌握度最低的 topic 优先，同 topic 内按清单原始顺序（题号顺序）。
 */
function pickRoundItem(round, index, mastery) {
  const pending = []
  round.items.forEach(function (item, order) {
    if (item.status === "done") return
    pending.push({ item: item, order: order })
  })
  if (pending.length === 0) return null

  pending.sort(function (a, b) {
    const ma = mastery[topicOf(a.item, index)]
    const mb = mastery[topicOf(b.item, index)]
    const va = ma === undefined ? 0.3 : ma
    const vb = mb === undefined ? 0.3 : mb
    if (va !== vb) return va - vb
    return a.order - b.order
  })

  const chosen = pending[0]
  return {
    item: chosen.item,
    problem: matchProblem(chosen.item, index),
    topic: topicOf(chosen.item, index),
  }
}

/**
 * 主动探索：挑一道没做过的题（一个尝试都没有的）。
 */
function pickExplore(problems, attemptsByProblem) {
  const untouched = []
  ;(problems || []).forEach(function (p) {
    const rows = attemptsByProblem[String(p.id)] || []
    if (rows.length === 0) untouched.push(p)
  })
  if (untouched.length === 0) return null
  untouched.sort(function (a, b) {
    return String(a.id) < String(b.id) ? -1 : 1
  })
  return untouched[0]
}

/**
 * 推下一个动作。
 *
 * @param {{store:object, provider:object, rounds:object[], nowIso:string,
 *          settings:object, problems?:object[], currentRoundId?:string}} ctx
 * @returns {{kind:string, problemId:string|null, problem:object|null,
 *            estimatedMinutes:number, reason:string, reviewQueueLength:number}|null}
 */
function nextAction(ctx) {
  const context = ctx || {}
  const store = context.store
  const nowIso = context.nowIso || new Date().toISOString()
  const settings = context.settings || {}
  const problems = context.problems || []

  const attempts = typeof store.listAttempts === "function" ? store.listAttempts() : []
  const attemptsByProblem = groupAttemptsByProblem(attempts)
  const index = buildProblemIndex(problems)
  const avgMs = averageMsByDifficulty(problems, attemptsByProblem)
  const mastery = masteryByTopic(problems, attemptsByProblem)

  /* ---- 1. 到期复习 ---- */
  const queue = sortByOverdue(store.listDueCards(nowIso), nowIso)
  const quota = quotaState(store, nowIso, settings)

  if (queue.length > 0 && !quota.exhausted) {
    const card = queue[0]
    const problem = index.byId.get(String(card.problem_id)) || null
    const overdueDays = Math.max(
      0,
      Math.floor((Date.parse(nowIso) - Date.parse(card.next_review_at)) / 86400000)
    )
    return {
      kind: "review",
      problemId: String(card.problem_id),
      problem: problem,
      title: problem ? problem.title : String(card.problem_id),
      estimatedMinutes: estimateMinutes(problem, avgMs),
      reason:
        "到期复习：还有 " +
        queue.length +
        " 张卡片到期了，先捡逾期最久的那张（已经逾期 " +
        overdueDays +
        " 天）",
      reviewQueueLength: queue.length,
    }
  }

  /* ---- 2. 轮次推进 ---- */
  const round = pickRound(context.rounds || [], context.currentRoundId)
  if (round) {
    const picked = pickRoundItem(round, index, mastery)
    if (picked) {
      const left = round.items.filter(function (it) {
        return it.status !== "done"
      }).length
      const quotaNote =
        quota.exhausted && queue.length > 0
          ? "今天的复习配额用完了（已复习 " +
            quota.questions +
            " 题 / " +
            quota.minutes +
            " 分钟），先推进轮次。"
          : ""
      return {
        kind: "round",
        problemId: picked.problem ? picked.problem.id : null,
        problem: picked.problem,
        title: picked.problem ? picked.problem.title : String(picked.item.title || picked.item.id),
        estimatedMinutes: estimateMinutes(picked.problem, avgMs),
        reason:
          quotaNote +
          "轮次 " +
          round.id +
          " 还剩 " +
          left +
          " 张卡片没做，先补「" +
          picked.topic +
          "」这个短板",
        reviewQueueLength: queue.length,
      }
    }
  }

  /* ---- 3. 主动探索 ---- */
  const explore = pickExplore(problems, attemptsByProblem)
  if (explore) {
    return {
      kind: "explore",
      problemId: explore.id,
      problem: explore,
      title: explore.title,
      estimatedMinutes: estimateMinutes(explore, avgMs),
      reason: "没有进行中的轮次了，从题库里挑一道没做过的题",
      reviewQueueLength: queue.length,
    }
  }

  return null
}

module.exports = {
  BASE_MINUTES: BASE_MINUTES,
  DEFAULT_QUOTA_QUESTIONS: DEFAULT_QUOTA_QUESTIONS,
  DEFAULT_QUOTA_MINUTES: DEFAULT_QUOTA_MINUTES,
  nextAction: nextAction,
  quotaState: quotaState,
  consumeQuota: consumeQuota,
  estimateMinutes: estimateMinutes,
  masteryByTopic: masteryByTopic,
  dayKey: dayKey,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `12 / 12 套件通过`，退出码 0

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加推下一题的排程器

- core/scheduler/next-action.js：复习 > 轮次推进 > 主动探索三级优先级
- 单日配额「10 题 或 20 分钟，取先到者」，上限在 settings 表、用量按日期作用域记账
- 多个 active 轮次优先最近创建的；轮次内掌握度最低的 topic 优先，同 topic 按题号顺序
- 掌握度用 0.7×首次通过率 + 0.3×e^(-失误/2) 的近似值，M5 落地后换成 mastery.js
- 每次只给一个动作，带「这一步大约 N 分钟」估算
- server/db.js 只新增 listAttempts 与 countAttemptsSince 两个只读方法
- 测试：优先级、逾期倒序、两种配额耗尽、轮次挑选、掌握度排序共 16 条断言"
git push origin main
```

---

## Task 5: 五个新接口接线

**Files:**
- Modify: `projects/apps/algo-plan/server/api.js`（M1 的三个接口**一个字不改**，只在 `buildRoutes` 里追加新路由）
- Create: `projects/apps/algo-plan/tests/api-m4.test.js`

**Interfaces:**
- Consumes:
  - Task 1 的 `grade(card, quality, nowIso) -> card`
  - Task 2 的 `parseRounds(progressRoot)` / `updateRoundItem(progressRoot, roundId, itemId, patch)` / `writeCorrection(learningRoot, problem, text)`
  - Task 4 的 `nextAction(ctx)` / `quotaState(store, nowIso, settings)` / `consumeQuota(store, usage, nowIso)` / `dayKey(nowIso)`
  - M1 的 `server/router.js` 导出的 `readJsonBody(req)`
  - M1 的 `ctx` 形状：`{store, provider, learning, sendJson}`（`learning` = `{ok, root, reason}`）
- Produces（响应形状**逐字**照契约 §3）：

  | 接口 | 入参 | 响应 |
  |---|---|---|
  | `GET /api/next` | 无 | `{action: {kind, problemId, title, estimatedMinutes, reason, reviewQueueLength} \| null, reviewQueueLength}` |
  | `POST /api/review/:id/grade` | `{quality}` | `{problemId, nextReviewAt, intervalDays, easiness, lapses}` |
  | `GET /api/rounds` | 无 | `{rounds: [{id, file, title, goal, status, items: [...]}], warnings: []}` |
  | `PATCH /api/rounds/:id/items/:itemId` | `{status, doneDate, commitSha}` | `{diff, warnings}` |
  | `POST /api/correction` | `{problemId, text}` | `{file, diff}` |
  | `GET /api/progress`（**契约之外的补充接口**） | 无 | `{date, solved, reviewed, reviewMinutes, quota}` |

  > `GET /api/progress` 是为了「今日」页的进度条，契约 §3 没有它。
  > 按契约 §7 的写作规范，**只新增、不改既有接口**，所以它不影响 M5/M6。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/api-m4.test.js`：

```javascript
"use strict"
/**
 * api-m4.test.js —— M4 的接口：下一题 / 评分 / 轮次 / 勾选写回 / 错题订正 / 今日进度
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const { createApp } = require("../server/app.js")

const PROBLEM_MD = [
  "---",
  "id: lc-00001",
  "source: leetcode",
  "title: 两数之和",
  "difficulty: easy",
  "topics: [哈希表, 数组]",
  "tracks: [interview, fundamentals]",
  "status: todo",
  "needs_fill: false",
  "created: 2026-11-11",
  "updated: 2026-11-11",
  "---",
  "## 题面",
  "",
  "给定整数数组与目标值。",
  "",
  "## 测试用例",
  "",
  "| input | expect |",
  "|---|---|",
  "| [2,7,11,15], 9 | [0,1] |",
  "",
  "## 参考解法",
  "",
  "```cpp",
  "int main() { return 0; }",
  "```",
  "",
].join("\n")

const ROUND_MD = [
  "# R33 Grokking 算法篇 — 学习进度",
  "",
  "## 基本信息",
  "",
  "| 字段 | 值 |",
  "|------|-----|",
  "| 开始时间 | 2026-07-12 |",
  "| 目标 | Grokking 算法篇 16 张卡片 |",
  "| 状态 | TBD-deferred |",
  "",
  "## 卡片清单",
  "",
  "| 序号 | ID | 名称 | 状态 | 完成时间 |",
  "|------|-----|------|------|----------|",
  "| 1 | two_sum | 两数之和 | todo |  |",
  "| 2 | arrays | 数组技巧 | todo |  |",
  "",
].join("\n")

/** 造一个干净的临时 learning 仓（git 仓库 + 题库 + 轮次） */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-m4-"))
  const bank = path.join(root, "bank", "interview")
  fs.mkdirSync(bank, { recursive: true })
  fs.writeFileSync(path.join(bank, "lc-00001.md"), PROBLEM_MD, "utf8")
  const progress = path.join(root, "progress")
  fs.mkdirSync(progress, { recursive: true })
  fs.writeFileSync(path.join(progress, "r33-progress.md"), ROUND_MD, "utf8")

  execFileSync("git", ["init", "-q"], { cwd: root })
  execFileSync("git", ["config", "user.email", "test@example.com"], { cwd: root })
  execFileSync("git", ["config", "user.name", "test"], { cwd: root })
  execFileSync("git", ["add", "-A"], { cwd: root })
  execFileSync("git", ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "初始化"], { cwd: root })
  return root
}

async function withApp(fn) {
  const root = tempLearning()
  const app = createApp({ dbPath: ":memory:", learningRoot: root })
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port, root)
  } finally {
    await app.close()
  }
}

test("GET /api/next 返回契约要求的字段", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/next")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok("action" in body)
    assert.ok("reviewQueueLength" in body)
    assert.ok(body.action, "应该给出一个动作")
    assert.deepStrictEqual(
      Object.keys(body.action).sort(),
      ["estimatedMinutes", "kind", "problemId", "reason", "reviewQueueLength", "title"].sort()
    )
    assert.strictEqual(body.action.kind, "round")
    assert.strictEqual(body.action.problemId, "lc-00001")
    assert.strictEqual(body.action.title, "两数之和")
    assert.ok(body.action.estimatedMinutes > 0)
  })
})

test("GET /api/next 在没有题也没有轮次时 action 为 null", async function () {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-empty-"))
  const app = createApp({ dbPath: ":memory:", learningRoot: root })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/next")
    const body = await res.json()
    assert.strictEqual(body.action, null)
    assert.strictEqual(body.reviewQueueLength, 0)
  } finally {
    await app.close()
  }
})

test("POST /api/review/:id/grade 返回下一次复习时间等五个字段", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/review/lc-00001/grade", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ quality: 5 }),
    })
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.deepStrictEqual(
      Object.keys(body).sort(),
      ["easiness", "intervalDays", "lapses", "nextReviewAt", "problemId"].sort()
    )
    assert.strictEqual(body.problemId, "lc-00001")
    assert.strictEqual(body.intervalDays, 1)
    assert.strictEqual(body.lapses, 0)
    assert.ok(Math.abs(body.easiness - 2.6) < 1e-9, String(body.easiness))
    assert.ok(!Number.isNaN(Date.parse(body.nextReviewAt)))
  })
})

test("POST /api/review/:id/grade 拒绝非法 quality", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/review/lc-00001/grade", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ quality: 9 }),
    })
    assert.strictEqual(res.status, 400)
    const body = await res.json()
    assert.ok(body.error, "要给出中文错误说明")
  })
})

test("GET /api/rounds 返回轮次与告警", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/rounds")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok(Array.isArray(body.warnings))
    assert.strictEqual(body.rounds.length, 1)
    const round = body.rounds[0]
    assert.strictEqual(round.id, "r33")
    assert.strictEqual(round.title, "Grokking 算法篇 — 学习进度")
    assert.strictEqual(round.status, "active")
    assert.ok(round.goal.indexOf("Grokking") !== -1, round.goal)
    assert.strictEqual(round.items.length, 2)
    assert.strictEqual(round.items[0].id, "two_sum")
    assert.strictEqual(round.items[0].status, "todo")
    assert.ok("file" in round)
  })
})

test("PATCH /api/rounds/:id/items/:itemId 只改目标行并返回 diff", async function () {
  await withApp(async function (base, root) {
    const file = path.join(root, "progress", "r33-progress.md")
    const before = fs.readFileSync(file, "utf8").split("\n")

    const res = await fetch(base + "/api/rounds/r33/items/arrays", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ status: "done", doneDate: "2026-11-11" }),
    })
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok("diff" in body)
    assert.ok(Array.isArray(body.warnings))
    assert.ok(body.diff.indexOf("arrays") !== -1, body.diff)

    const after = fs.readFileSync(file, "utf8").split("\n")
    let changed = 0
    for (let i = 0; i < before.length; i += 1) {
      if (before[i] !== after[i]) changed += 1
    }
    assert.strictEqual(changed, 1, "只应改一行")
  })
})

test("learning 仓不干净时写回被拒绝并指出被动过的文件", async function () {
  await withApp(async function (base, root) {
    fs.writeFileSync(path.join(root, "随手改的.md"), "脏一下\n", "utf8")
    const res = await fetch(base + "/api/rounds/r33/items/arrays", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ status: "done" }),
    })
    assert.strictEqual(res.status, 409)
    const body = await res.json()
    assert.ok(body.error.indexOf("不干净") !== -1, body.error)
    assert.ok(Array.isArray(body.dirtyFiles))
    assert.ok(body.dirtyFiles.length > 0)
  })
})

test("POST /api/correction 写入订正笔记并返回 diff", async function () {
  await withApp(async function (base, root) {
    const res = await fetch(base + "/api/correction", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", text: "先查再插，别先插再查。" }),
    })
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok("file" in body)
    assert.ok("diff" in body)
    const file = path.join(root, "notes", "practice", "lc-00001-订正.md")
    assert.strictEqual(body.file, file)
    assert.ok(fs.existsSync(file), "订正笔记要真的写出来")
    const text = fs.readFileSync(file, "utf8")
    assert.ok(text.indexOf("先查再插") !== -1)
    assert.ok(text.indexOf("problem: lc-00001") !== -1)
  })
})

test("GET /api/progress 给出今日进度与配额", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/progress")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.ok("date" in body)
    assert.strictEqual(typeof body.solved, "number")
    assert.strictEqual(typeof body.reviewed, "number")
    assert.strictEqual(typeof body.reviewMinutes, "number")
    assert.strictEqual(body.quota.limitQuestions, 10)
    assert.strictEqual(body.quota.limitMinutes, 20)
    assert.strictEqual(body.quota.exhausted, false)
  })
})

test("M3 的 POST /api/attempt 没有被 M4 改掉（跨里程碑回归闸门）", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/attempt", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "不存在的题", code: "", language: "cpp" }),
    })
    const body = await res.json()
    // 路由被删掉时，走的是「接口不存在」分支；路由还在时，走的是 M3 的业务分支
    // （题不存在 → 404 +「题目不存在」；代码为空 → 400 +「代码不能为空」）。
    assert.notStrictEqual(body.error, "接口不存在", "/api/attempt 被 M4 误删了——检查 buildRoutes 是否被整体替换")
  })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Expected values to be strictly equal` 加上 `404`（接口还不存在）

- [ ] **Step 3: 改 server/api.js 的头部**

Modify `projects/apps/algo-plan/server/api.js`，把文件开头的这段：

```javascript
const { toSummary } = require("../core/bank/problem.js")
```

替换成：

```javascript
const path = require("node:path")

const { toSummary } = require("../core/bank/problem.js")
const { grade } = require("../core/review/sm2.js")
const { nextAction, quotaState, consumeQuota, dayKey } = require("../core/scheduler/next-action.js")
const { parseRounds, updateRoundItem, writeCorrection } = require("../core/sync/rounds.js")
const { readJsonBody } = require("./router.js")
```

- [ ] **Step 4: 改 server/api.js 的 buildRoutes**

> **⚠️ 这一步是「插入」，不是「替换」。**
>
> M3 已经在 `server/api.js` 的 `buildRoutes` 里加过一条 `POST /api/attempt`。
> 如果这一步把整个 `buildRoutes` 换成下面这个版本，**M3 的判题接口会被静默删掉**——
> 现象是 M4 落地后前端提交代码一律 404，而单测全绿（因为 M4 自己的测试只打自己那几条路由）。
>
> 正确做法：
> 1. 把代码块开头的 `loadRounds` 辅助函数**插到现有 `buildRoutes` 函数之前**（模块级函数）。
> 2. 把代码块里 `/* ---------- M4：闭环 ---------- */` 与 `/* ---------- M4：闭环结束 ---------- */`
>    **之间那一整段**（含注释行）插到现有 `buildRoutes` 函数的 `return routes` **这一行之前**。
> 3. `buildRoutes` 里已有的内容——M1 的三个接口、M3 的 `POST /api/attempt`——**一个字都不动**。
>
> 下面代码块里凡是标了 `M4：闭环` 注释的，就是第 2 步要插入的那一段；其余部分仅供对照。

```javascript
/**
 * 读 learning/progress 下的轮次。没连上 learning 仓就返回空列表（纯本地模式降级）。
 */
function loadRounds(ctx) {
  if (!ctx.learning || !ctx.learning.ok || !ctx.learning.root) {
    return { rounds: [], warnings: [] }
  }
  return parseRounds(path.join(ctx.learning.root, "progress"))
}

/**
 * 组装路由表。
 * @param {{store: object, provider: object, learning: object, sendJson: Function}} ctx
 * @returns {Array<{method: string, pattern: string, handler: Function}>}
 */
function buildRoutes(ctx) {
  const routes = []

  routes.push({
    method: "GET",
    pattern: "/api/health",
    handler: async function (req, res) {
      const stats = ctx.provider.stats()
      ctx.sendJson(res, 200, {
        ok: true,
        node: process.version,
        learning: {
          ok: ctx.learning.ok,
          root: ctx.learning.root,
          reason: ctx.learning.reason,
        },
        bank: stats,
        attempts: ctx.store.countAttempts(),
      })
    },
  })

  routes.push({
    method: "GET",
    pattern: "/api/bank",
    handler: async function (req, res, params, query) {
      const problems = await ctx.provider.list({
        track: query.get("track") || undefined,
        topic: query.get("topic") || undefined,
        difficulty: query.get("difficulty") || undefined,
        status: query.get("status") || undefined,
        idPrefix: query.get("prefix") || undefined,
      })
      const limitRaw = Number(query.get("limit") || 0)
      const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? limitRaw : problems.length
      ctx.sendJson(res, 200, {
        total: problems.length,
        items: problems.slice(0, limit).map(toSummary),
      })
    },
  })

  routes.push({
    method: "GET",
    pattern: "/api/problem/:id",
    handler: async function (req, res, params) {
      const problem = await ctx.provider.get(params.id)
      if (!problem) {
        ctx.sendJson(res, 404, { error: "题目不存在", id: params.id })
        return
      }
      ctx.sendJson(res, 200, {
        id: problem.id,
        title: problem.title,
        source: problem.source,
        difficulty: problem.difficulty,
        topics: problem.topics,
        tracks: problem.tracks,
        status: problem.status,
        needsFill: problem.needsFill,
        statement: problem.statement,
        cases: {
          sample: problem.cases.slice(0, SAMPLE_CASE_COUNT),
          total: problem.cases.length,
        },
      })
    },
  })

  /* ---------- M4：闭环 ---------- */
  /* ↓↓↓ 以下整段插入到现有 buildRoutes 的 `return routes` 之前，其余部分一字不动 ↓↓↓ */

  routes.push({
    method: "GET",
    pattern: "/api/next",
    handler: async function (req, res) {
      const nowIso = new Date().toISOString()
      const problems = await ctx.provider.list()
      const parsed = loadRounds(ctx)
      const action = nextAction({
        store: ctx.store,
        provider: ctx.provider,
        rounds: parsed.rounds,
        nowIso: nowIso,
        settings: ctx.store.allSettings(),
        problems: problems,
      })

      if (!action) {
        ctx.sendJson(res, 200, { action: null, reviewQueueLength: 0 })
        return
      }

      // 复习动作先把这次的耗时估算记下来，等评分时计入单日配额
      if (action.kind === "review") {
        ctx.store.setSetting("review.estimate." + action.problemId, String(action.estimatedMinutes))
      }

      ctx.sendJson(res, 200, {
        action: {
          kind: action.kind,
          problemId: action.problemId,
          title: action.title,
          estimatedMinutes: action.estimatedMinutes,
          reason: action.reason,
          reviewQueueLength: action.reviewQueueLength,
        },
        reviewQueueLength: action.reviewQueueLength,
      })
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/review/:id/grade",
    handler: async function (req, res, params) {
      const body = await readJsonBody(req)
      const quality = Number(body.quality)
      if (!Number.isInteger(quality) || quality < 0 || quality > 5) {
        ctx.sendJson(res, 400, { error: "quality 必须是 0~5 的整数" })
        return
      }

      const problemId = String(params.id)
      const nowIso = new Date().toISOString()
      const existing = ctx.store.getReviewCard(problemId)
      const card = existing || {
        problem_id: problemId,
        easiness: 2.5,
        interval_days: 0,
        repetitions: 0,
        last_quality: null,
        last_at: null,
        next_review_at: nowIso,
        lapses: 0,
      }
      const graded = grade(card, quality, nowIso)
      ctx.store.upsertReviewCard(graded)

      // 复习一道算一题；分钟数用 /api/next 记下来的估算
      const estimate = Number(ctx.store.getSetting("review.estimate." + problemId, "0")) || 0
      ctx.store.setSetting("review.estimate." + problemId, "0")
      consumeQuota(ctx.store, { questions: 1, minutes: estimate }, nowIso)

      ctx.sendJson(res, 200, {
        problemId: problemId,
        nextReviewAt: graded.next_review_at,
        intervalDays: graded.interval_days,
        easiness: graded.easiness,
        lapses: graded.lapses,
      })
    },
  })

  routes.push({
    method: "GET",
    pattern: "/api/rounds",
    handler: async function (req, res) {
      const parsed = loadRounds(ctx)
      ctx.sendJson(res, 200, {
        rounds: parsed.rounds.map(function (round) {
          return {
            id: round.id,
            file: round.file,
            title: round.title,
            goal: round.goal,
            status: round.status,
            items: round.items.map(function (item) {
              return {
                raw: item.raw,
                id: item.id,
                title: item.title,
                status: item.status,
                doneDate: item.doneDate,
                commitSha: item.commitSha,
              }
            }),
          }
        }),
        warnings: parsed.warnings,
      })
    },
  })

  routes.push({
    method: "PATCH",
    pattern: "/api/rounds/:id/items/:itemId",
    handler: async function (req, res, params) {
      const body = await readJsonBody(req)
      const patch = {}
      if (body.status !== undefined && body.status !== null) patch.status = String(body.status)
      if (body.doneDate !== undefined && body.doneDate !== null) patch.doneDate = String(body.doneDate)
      if (body.commitSha !== undefined && body.commitSha !== null) patch.commitSha = String(body.commitSha)

      if (!ctx.learning || !ctx.learning.ok || !ctx.learning.root) {
        ctx.sendJson(res, 503, { error: "还没连上 learning 仓，写回不可用" })
        return
      }

      try {
        const result = updateRoundItem(
          path.join(ctx.learning.root, "progress"),
          params.id,
          params.itemId,
          patch
        )
        ctx.sendJson(res, 200, { diff: result.diff, warnings: result.warnings })
      } catch (err) {
        ctx.sendJson(res, err && err.status ? err.status : 500, {
          error: (err && err.message) || "写回失败",
          dirtyFiles: (err && err.dirtyFiles) || [],
        })
      }
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/correction",
    handler: async function (req, res) {
      const body = await readJsonBody(req)
      const problemId = String(body.problemId || "")
      const text = String(body.text || "")
      if (!problemId) {
        ctx.sendJson(res, 400, { error: "缺少 problemId" })
        return
      }
      if (!text.trim()) {
        ctx.sendJson(res, 400, { error: "订正内容不能为空" })
        return
      }
      if (!ctx.learning || !ctx.learning.ok || !ctx.learning.root) {
        ctx.sendJson(res, 503, { error: "还没连上 learning 仓，写回不可用" })
        return
      }

      const problem = await ctx.provider.get(problemId)
      if (!problem) {
        ctx.sendJson(res, 404, { error: "题目不存在：" + problemId })
        return
      }

      try {
        const result = writeCorrection(ctx.learning.root, problem, text)
        ctx.sendJson(res, 200, { file: result.file, diff: result.diff })
      } catch (err) {
        ctx.sendJson(res, err && err.status ? err.status : 500, {
          error: (err && err.message) || "写回失败",
          dirtyFiles: (err && err.dirtyFiles) || [],
        })
      }
    },
  })

  routes.push({
    method: "GET",
    pattern: "/api/progress",
    handler: async function (req, res) {
      const now = new Date()
      const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString()
      const nowIso = now.toISOString()
      const quota = quotaState(ctx.store, nowIso, ctx.store.allSettings())
      ctx.sendJson(res, 200, {
        date: dayKey(nowIso),
        solved: ctx.store.countAttemptsSince(startOfDay),
        reviewed: quota.questions,
        reviewMinutes: quota.minutes,
        quota: {
          questions: quota.questions,
          minutes: quota.minutes,
          limitQuestions: quota.limitQuestions,
          limitMinutes: quota.limitMinutes,
          exhausted: quota.exhausted,
          exhaustedBy: quota.exhaustedBy,
        },
      })
    },
  })

  /* ---------- M4：闭环结束 ---------- */
  /* ↑↑↑ 到此结束插入 ↑↑↑ */

  return routes
}
```

> `module.exports = { buildRoutes: buildRoutes, SAMPLE_CASE_COUNT: SAMPLE_CASE_COUNT }` **不用改**。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `13 / 13 套件通过`，退出码 0

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 接入 M4 的五个新接口

- GET /api/next：返回下一个动作（复习/轮次/探索）与到期复习数
- POST /api/review/:id/grade：按 quality 更新 SM-2 卡片，并计入单日配额
- GET /api/rounds：返回轮次清单与解析告警
- PATCH /api/rounds/:id/items/:itemId：勾选写回，只改目标行，返回 diff
- POST /api/correction：写错题订正笔记，返回文件路径与 diff
- GET /api/progress：今日进度与配额状态（契约之外的补充接口）
- learning 仓不干净时写回返回 409，并列出被动过的文件
- 测试：接口响应字段逐个对齐契约，共 9 条断言"
git push origin main
```

---

## Task 6: 前端四个页面（今日 / 作答 / 复习 / 轮次）

**Files:**
- Modify: `projects/apps/algo-plan/web/index.html`（加 4 个 script 标签）
- Modify: `projects/apps/algo-plan/web/app.js`（改成 tab 调度 + 公共工具，页面挪到 `web/pages/`）
- Modify: `projects/apps/algo-plan/web/style.css`（追加新控件的样式）
- Create: `projects/apps/algo-plan/web/pages/today.js`
- Create: `projects/apps/algo-plan/web/pages/answer.js`
- Create: `projects/apps/algo-plan/web/pages/review.js`
- Create: `projects/apps/algo-plan/web/pages/rounds.js`
- Create: `projects/apps/algo-plan/tests/pages.test.js`

**Interfaces:**
- Consumes: Task 5 的六个接口（`/api/next`、`/api/review/:id/grade`、`/api/rounds`、`/api/rounds/:id/items/:itemId`、`/api/correction`、`/api/progress`），以及 M1 的 `/api/health`、`/api/bank`、`/api/problem/:id`，以及 **M3 的 `POST /api/attempt`**（作答页的「提交判题」按钮直接用它，判题结果由 `verdictBox()` 渲染——M3 做的结果面板在这里被完整保留并搬到 `web/pages/answer.js`）
- Produces:
  - `window.AlgoPlan`：`{el, getJson, postJson, patchJson, state, pages, go}`
    - `el(tag, attrs, children)`——M1 的版本，**M4 扩展**：`on*` 开头的属性当事件监听器挂上（`onclick` 之类）
    - `state = {problemId, currentRoundId}`——页面之间共享的当前题目 / 当前轮次
    - `pages[key] = {title, render(view)}`——每个页面自己往 `#view` 里画
    - `go(key)`——切页
  - 页面与标签的对应：`today`=今日、`answer`=作答、`review`=复习、`rounds`=轮次

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/pages.test.js`：

```javascript
"use strict"
/**
 * pages.test.js —— 四个前端页面都注册进 window.AlgoPlan.pages
 *
 * 页面脚本本来在浏览器里跑，但「注册」这一步可以在 Node 里验：
 * 给一个最小的 window 替身，把页面脚本 require 进来。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const WEB = path.resolve(__dirname, "..", "web")
const PAGES = ["today", "answer", "review", "rounds"]

function stubWindow() {
  global.window = {
    AlgoPlan: {
      el: function () {
        return {}
      },
      getJson: function () {
        return Promise.resolve({})
      },
      postJson: function () {
        return Promise.resolve({})
      },
      patchJson: function () {
        return Promise.resolve({})
      },
      state: { problemId: null, currentRoundId: null },
      pages: {},
      go: function () {},
    },
  }
}

test("四个页面脚本都注册进 window.AlgoPlan.pages", function () {
  stubWindow()
  PAGES.forEach(function (name) {
    require(path.join(WEB, "pages", name + ".js"))
  })
  PAGES.forEach(function (name) {
    const page = global.window.AlgoPlan.pages[name]
    assert.ok(page, name + " 页没有注册")
    assert.strictEqual(typeof page.render, "function", name + " 页缺少 render")
  })
})

test("index.html 引用了四个页面脚本", function () {
  const html = fs.readFileSync(path.join(WEB, "index.html"), "utf8")
  PAGES.forEach(function (name) {
    assert.ok(html.indexOf("/pages/" + name + ".js") !== -1, "index.html 里没有 " + name + ".js")
  })
})

test("复习页的四个直觉文案映射到 SM-2 的 quality", function () {
  stubWindow()
  require(path.join(WEB, "pages", "review.js"))
  const buttons = global.window.AlgoPlan.pages.review.buttons
  assert.strictEqual(buttons.length, 4)
  assert.deepStrictEqual(
    buttons.map(function (b) {
      return b.quality
    }),
    [1, 2, 3, 5]
  )
  assert.deepStrictEqual(
    buttons.map(function (b) {
      return b.label
    }),
    ["完全忘了", "想很久", "有点印象", "秒答"]
  )
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '.../web/pages/today.js'`

- [ ] **Step 3: 改 web/index.html**

把 `projects/apps/algo-plan/web/index.html` 整个替换成：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>算法能力计划</title>
  <link rel="stylesheet" href="/style.css" />
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
  <script src="/pages/today.js"></script>
  <script src="/pages/answer.js"></script>
  <script src="/pages/review.js"></script>
  <script src="/pages/rounds.js"></script>
</body>
</html>
```

- [ ] **Step 4: 改 web/app.js**

把 `projects/apps/algo-plan/web/app.js` 整个替换成：

```javascript
"use strict"
/**
 * app.js —— 前端骨架：tab 调度 + 公共工具
 *
 * 原生 JS，无构建步骤。四个页面在 web/pages/ 下，各自注册到 window.AlgoPlan.pages。
 * index.html 里 app.js 先加载，所以页面脚本加载时公共工具已经就绪。
 */

/** 极简 DOM 构造器 */
function el(tag, attrs, children) {
  const node = document.createElement(tag)
  if (attrs) {
    Object.keys(attrs).forEach(function (key) {
      if (key === "class") node.className = attrs[key]
      else if (key === "text") node.textContent = attrs[key]
      else if (key.indexOf("on") === 0 && typeof attrs[key] === "function") {
        // 事件监听器：onclick → click
        node.addEventListener(key.slice(2).toLowerCase(), attrs[key])
      } else node.setAttribute(key, attrs[key])
    })
  }
  ;(children || []).forEach(function (child) {
    if (!child) return
    node.appendChild(child)
  })
  return node
}

/** 取 JSON，失败时抛出带中文说明的错误 */
async function getJson(url) {
  const res = await fetch(url)
  const body = await res.json()
  if (!res.ok) {
    throw new Error((body && body.error) || "请求失败：" + res.status)
  }
  return body
}

/** 发 JSON（POST / PATCH），失败时抛出带中文说明的错误 */
async function sendJson(url, method, body) {
  const res = await fetch(url, {
    method: method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body || {}),
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error((data && data.error) || "请求失败：" + res.status)
  }
  return data
}

function postJson(url, body) {
  return sendJson(url, "POST", body)
}

function patchJson(url, body) {
  return sendJson(url, "PATCH", body)
}

/** 切页 */
function go(key) {
  activeTab = key
  renderTabs(activeTab)
  render()
}

/** 页面注册表 + 公共工具 */
window.AlgoPlan = Object.assign(window.AlgoPlan || {}, {
  el: el,
  getJson: getJson,
  postJson: postJson,
  patchJson: patchJson,
  state: Object.assign((window.AlgoPlan && window.AlgoPlan.state) || {}, {
    problemId: null,
    currentRoundId: null,
  }),
  pages: (window.AlgoPlan && window.AlgoPlan.pages) || {},
  go: go,
})

/** 顶栏的四个标签 */
const TABS = [
  { key: "today", label: "今日" },
  { key: "answer", label: "作答" },
  { key: "review", label: "复习" },
  { key: "rounds", label: "轮次" },
]

let activeTab = "today"

/** 画标签栏 */
function renderTabs(active) {
  const nav = document.getElementById("tabs")
  if (!nav) return
  nav.textContent = ""
  TABS.forEach(function (tab) {
    nav.appendChild(
      el("button", {
        class: tab.key === active ? "active" : "",
        text: tab.label,
        onclick: function () {
          go(tab.key)
        },
      })
    )
  })
}

/** 渲染当前页 */
async function render() {
  const view = document.getElementById("view")
  if (!view) return
  const page = window.AlgoPlan.pages[activeTab]
  view.textContent = ""
  if (!page) {
    view.appendChild(el("div", { class: "panel", text: "页面没注册：" + activeTab }))
    return
  }
  try {
    await page.render(view)
  } catch (err) {
    view.textContent = ""
    view.appendChild(
      el("section", { class: "panel" }, [
        el("h2", { text: "出错了" }),
        el("p", { class: "error", text: String(err.message || err) }),
      ])
    )
  }
}

document.addEventListener("DOMContentLoaded", function () {
  renderTabs(activeTab)
  render()
})
```

- [ ] **Step 5: 写 web/pages/today.js**

Create `projects/apps/algo-plan/web/pages/today.js`：

```javascript
"use strict"
/**
 * today.js —— 今日页
 *
 * 三块内容：
 *   1. 下一题卡片（GET /api/next）：什么动作、为什么、这一步大约几分钟
 *   2. 到期复习数
 *   3. 今日进度（GET /api/progress）：今天做了多少题、复习了多少、配额还剩多少
 *
 * 另外把运行状态（learning 仓连没连上）摆出来——写回不可用时要一眼看得出。
 */

(function () {
  const A = window.AlgoPlan
  const el = A.el

  /** 动作类型 → 中文 */
  const KIND_TEXT = {
    review: "到期复习",
    round: "推进轮次",
    explore: "主动探索",
  }

  /** 下一题卡片 */
  function nextPanel(next) {
    const action = next && next.action
    if (!action) {
      return el("section", { class: "panel" }, [
        el("h2", { text: "下一步" }),
        el("p", { class: "muted", text: "现在没有该做的事：没有到期的复习卡片，也没有没做的轮次条目。" }),
      ])
    }
    const buttons = []
    if (action.problemId) {
      buttons.push(
        el("button", {
          class: "primary",
          text: action.kind === "review" ? "去复习这道" : "去作答",
          onclick: function () {
            A.state.problemId = action.problemId
            A.go(action.kind === "review" ? "review" : "answer")
          },
        })
      )
    }
    return el("section", { class: "panel" }, [
      el("h2", { text: "下一步" }),
      el("div", { class: "kv" }, [
        el("div", {}, [document.createTextNode("类型："), el("span", { text: KIND_TEXT[action.kind] || action.kind })]),
        el("div", {}, [document.createTextNode("题目："), el("span", { text: action.title })]),
        el("div", {}, [document.createTextNode("用时："), el("span", { text: "这一步大约 " + action.estimatedMinutes + " 分钟" })]),
        el("div", {}, [document.createTextNode("到期复习："), el("span", { text: action.reviewQueueLength + " 张" })]),
      ]),
      el("p", { class: "reason", text: action.reason }),
      el("div", { class: "row" }, buttons),
    ])
  }

  /** 今日进度 */
  function progressPanel(progress) {
    const quota = (progress && progress.quota) || {}
    const limit = Math.max(1, Number(quota.limitQuestions) || 1)
    const percent = Math.min(100, Math.round((Number(quota.questions) || 0) / limit * 100))
    const rows = [
      el("div", {}, [document.createTextNode("日期："), el("span", { text: (progress && progress.date) || "" })]),
      el("div", {}, [document.createTextNode("今天做题："), el("span", { text: (progress && progress.solved) + " 道" })]),
      el("div", {}, [document.createTextNode("今天复习："), el("span", { text: (progress && progress.reviewed) + " 张" })]),
      el("div", {}, [document.createTextNode("复习用时："), el("span", { text: (progress && progress.reviewMinutes) + " 分钟" })]),
      el("div", {}, [
        document.createTextNode("复习配额："),
        el("span", {
          text:
            (quota.questions || 0) + "/" + (quota.limitQuestions || 0) + " 题，" +
            (quota.minutes || 0) + "/" + (quota.limitMinutes || 0) + " 分钟",
        }),
      ]),
    ]
    if (quota.exhausted) {
      rows.push(el("p", { class: "warn-text", text: "今天的复习配额用完了，接下来推新题。" }))
    }
    return el("section", { class: "panel" }, [
      el("h2", { text: "今日进度" }),
      el("div", { class: "kv" }, rows),
      el("div", { class: "bar" }, [el("div", { class: "fill", style: "width:" + percent + "%" })]),
    ])
  }

  /** 运行状态 */
  function healthPanel(health) {
    const learning = (health && health.learning) || {}
    const bank = (health && health.bank) || {}
    return el("section", { class: "panel" }, [
      el("h2", { text: "运行状态" }),
      el("div", { class: "kv" }, [
        el("div", {}, [
          document.createTextNode("learning 仓："),
          el("span", { class: learning.ok ? "badge ok" : "badge warn", text: learning.ok ? "已连接" : "纯本地模式" }),
        ]),
        el("div", {}, [document.createTextNode("题库题目数："), el("span", { text: String(bank.problemCount || 0) })]),
        el("div", {}, [document.createTextNode("作答流水条数："), el("span", { text: String((health && health.attempts) || 0) })]),
      ]),
    ])
  }

  A.pages.today = {
    title: "今日",
    render: async function (view) {
      view.textContent = ""
      view.appendChild(el("div", { class: "panel", text: "正在算今天该做什么…" }))
      let next = null
      let progress = null
      let health = null
      try {
        next = await A.getJson("/api/next")
        progress = await A.getJson("/api/progress")
        health = await A.getJson("/api/health")
      } catch (err) {
        view.textContent = ""
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "加载失败" }),
            el("p", { class: "error", text: String(err.message || err) }),
          ])
        )
        return
      }
      view.textContent = ""
      view.appendChild(nextPanel(next))
      view.appendChild(progressPanel(progress))
      view.appendChild(healthPanel(health))
    },
  }
})()
```

- [ ] **Step 6: 写 web/pages/answer.js**

Create `projects/apps/algo-plan/web/pages/answer.js`：

```javascript
"use strict"
/**
 * answer.js —— 作答页：看题面 → 写代码 → 提交判题 → 写错题订正
 *
 * 判题接口 POST /api/attempt 由 M3 提供；M3 还没上线时这里给出中文提示，不白屏。
 * 订正写回 POST /api/correction 由 M4 提供；写回只改 learning 仓的工作区，
 * **app 不会自动提交**，diff 摆在这里给用户看，提交与否由用户决定。
 */

(function () {
  const A = window.AlgoPlan
  const el = A.el

  /** 页面内状态：代码与判题结果跨渲染保留 */
  const state = {
    problem: null,
    code: "",
    language: "cpp",
    verdict: null,
    correctionText: "",
    diff: "",
  }

  /** 题面 */
  function statementPanel(problem) {
    const cases = problem.cases || {}
    const sample = (cases.sample || []).map(function (c) {
      return "输入：" + c.input + "　期望：" + c.expect
    })
    return el("section", { class: "panel" }, [
      el("h2", { text: problem.title || problem.id }),
      el("div", { class: "kv" }, [
        el("div", {}, [document.createTextNode("ID："), el("span", { text: problem.id })]),
        el("div", {}, [document.createTextNode("难度："), el("span", { text: problem.difficulty || "" })]),
        el("div", {}, [document.createTextNode("知识点："), el("span", { text: (problem.topics || []).join("、") })]),
        el("div", {}, [document.createTextNode("用例数："), el("span", { text: String(cases.total || 0) })]),
      ]),
      el("p", { text: problem.statement || "" }),
      sample.length === 0
        ? el("p", { class: "muted", text: "（没有样例用例）" })
        : el("ul", {}, sample.map(function (line) { return el("li", { text: line }) })),
    ])
  }

  /** 代码框 + 语言选择 + 提交 */
  function codePanel() {
    const textarea = el("textarea", { class: "code", rows: "18", spellcheck: "false" })
    textarea.value = state.code
    textarea.addEventListener("input", function () {
      state.code = textarea.value
    })

    const select = el("select", {}, [
      el("option", { value: "cpp", text: "C++" }),
      el("option", { value: "python", text: "Python" }),
    ])
    select.value = state.language
    select.addEventListener("change", function () {
      state.language = select.value
    })

    const result = el("div", { class: "result" })

    const submit = el("button", {
      class: "primary",
      text: "提交判题",
      onclick: async function () {
        result.textContent = "判题中…"
        try {
          const body = await A.postJson("/api/attempt", {
            problemId: state.problem.id,
            code: textarea.value,
            language: select.value,
            mode: "solve",
          })
          state.verdict = body
          result.textContent = ""
          result.appendChild(verdictBox(body))
        } catch (err) {
          result.textContent = ""
          result.appendChild(el("p", { class: "error", text: String(err.message || err) }))
          if (String(err.message || "").indexOf("404") !== -1) {
            result.appendChild(el("p", { class: "muted", text: "判题接口还没上线（M3 未完成）。" }))
          }
        }
      },
    })

    return el("section", { class: "panel" }, [
      el("h2", { text: "我的代码" }),
      el("div", { class: "row" }, [select, submit]),
      textarea,
      result,
    ])
  }

  /** 判题结果 */
  function verdictBox(body) {
    const verdict = body.verdict || ""
    const cls = verdict === "pass" ? "badge ok" : "badge bad"
    const rows = [
      el("div", {}, [
        document.createTextNode("结果："),
        el("span", { class: cls, text: verdict }),
      ]),
      el("div", {}, [document.createTextNode("用例："), el("span", { text: body.passedCases + "/" + body.totalCases })]),
      el("div", {}, [document.createTextNode("用时："), el("span", { text: body.durationMs + " ms" })]),
    ]
    const failed = body.failedCase
    const detail = failed
      ? el("div", { class: "kv" }, [
          el("div", {}, [document.createTextNode("失败用例 #" + failed.index + " 输入："), el("span", { text: failed.input })]),
          el("div", {}, [document.createTextNode("期望："), el("span", { text: failed.expected })]),
          el("div", {}, [document.createTextNode("实际："), el("span", { text: failed.actual })]),
        ])
      : null
    const compiler = body.compilerOutput
      ? el("pre", { class: "diff", text: body.compilerOutput })
      : null
    return el("div", {}, [
      el("div", { class: "kv" }, rows),
      body.message ? el("p", { class: "muted", text: body.message }) : null,
      detail,
      compiler,
      verdict === "pass" ? null : correctionPanel(),
    ].filter(Boolean))
  }

  /** 错题订正 */
  function correctionPanel() {
    const textarea = el("textarea", { class: "code", rows: "5", spellcheck: "false" })
    textarea.value = state.correctionText
    textarea.addEventListener("input", function () {
      state.correctionText = textarea.value
    })
    const out = el("div", { class: "result" })

    const button = el("button", {
      text: "写错题订正",
      onclick: async function () {
        out.textContent = "写入中…"
        try {
          const body = await A.postJson("/api/correction", {
            problemId: state.problem.id,
            text: textarea.value,
          })
          out.textContent = ""
          out.appendChild(el("p", { class: "ok-text", text: "已写入：" + body.file }))
          out.appendChild(el("p", { class: "muted", text: "写回只改 learning 仓的工作区，app 不会自动提交；下面是 diff，提交与否由你决定。" }))
          out.appendChild(el("pre", { class: "diff", text: body.diff || "（没有变化）" }))
        } catch (err) {
          out.textContent = ""
          out.appendChild(el("p", { class: "error", text: String(err.message || err) }))
        }
      },
    })

    return el("div", { class: "correction" }, [
      el("h3", { text: "错题订正" }),
      el("p", { class: "muted", text: "写下的复盘会存成 learning 仓里的 notes/practice/" + state.problem.id + "-订正.md。" }),
      textarea,
      el("div", { class: "row" }, [button]),
      out,
    ])
  }

  /** 没选题目时：给个题库下拉 */
  function pickPanel() {
    const out = el("div", { class: "panel" })
    A.getJson("/api/bank")
      .then(function (bank) {
        const items = bank.items || []
        const select = el("select", {}, items.map(function (item) {
          return el("option", { value: item.id, text: item.id + " " + item.title })
        }))
        out.appendChild(el("h2", { text: "先选一道题" }))
        out.appendChild(el("div", { class: "row" }, [
          select,
          el("button", {
            text: "打开",
            onclick: function () {
              A.state.problemId = select.value
              A.go("answer")
            },
          }),
        ]))
        if (items.length === 0) {
          out.appendChild(el("p", { class: "muted", text: "题库还是空的。" }))
        }
      })
      .catch(function (err) {
        out.appendChild(el("p", { class: "error", text: String(err.message || err) }))
      })
    return out
  }

  A.pages.answer = {
    title: "作答",
    render: async function (view) {
      view.textContent = ""
      view.appendChild(el("div", { class: "panel", text: "加载中…" }))
      const id = A.state.problemId
      if (!id) {
        view.textContent = ""
        view.appendChild(pickPanel())
        return
      }
      try {
        state.problem = await A.getJson("/api/problem/" + encodeURIComponent(id))
      } catch (err) {
        view.textContent = ""
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "打不开这道题" }),
            el("p", { class: "error", text: String(err.message || err) }),
          ])
        )
        return
      }
      view.textContent = ""
      view.appendChild(statementPanel(state.problem))
      view.appendChild(codePanel())
    },
  }
})()
```

- [ ] **Step 7: 写 web/pages/review.js**

Create `projects/apps/algo-plan/web/pages/review.js`：

```javascript
"use strict"
/**
 * review.js —— 复习页：到期卡片 + 直觉评分
 *
 * 直觉文案 → SM-2 quality 的映射（设计文档 §4.2 的六档里，界面只暴露四档）：
 *   完全忘了 → 1（没记住，重置间隔）
 *   想很久   → 2（想很久才想起，重置间隔）
 *   有点印象 → 3（想起来了，间隔不变）
 *   秒答     → 5（一次过而且快，间隔按 easiness 拉长）
 * 剩下两档——0 = 直接抄参考答案、4 = 一次通过但偏慢——由判题流程自动判定，不做按钮。
 */

(function () {
  const A = window.AlgoPlan
  const el = A.el

  /** 四个直觉评分按钮 */
  const BUTTONS = [
    { label: "完全忘了", quality: 1 },
    { label: "想很久", quality: 2 },
    { label: "有点印象", quality: 3 },
    { label: "秒答", quality: 5 },
  ]

  /** 队列概况 */
  function queuePanel(next) {
    const count = (next && next.reviewQueueLength) || 0
    return el("section", { class: "panel" }, [
      el("h2", { text: "到期复习" }),
      el("div", { class: "kv" }, [
        el("div", {}, [document.createTextNode("队列长度："), el("span", { text: count + " 张" })]),
        el("div", {}, [
          document.createTextNode("单日配额："),
          el("span", { text: "10 题 或 20 分钟，取先到者" }),
        ]),
      ]),
    ])
  }

  /** 到期卡片 + 四个评分按钮 */
  function cardPanel(action) {
    const out = el("div", { class: "result" })
    const buttons = BUTTONS.map(function (item) {
      return el("button", {
        text: item.label,
        onclick: async function () {
          out.textContent = "记录中…"
          try {
            const body = await A.postJson("/api/review/" + encodeURIComponent(action.problemId) + "/grade", {
              quality: item.quality,
            })
            out.textContent = ""
            out.appendChild(
              el("p", {
                class: "ok-text",
                text:
                  "记下了（" + item.label + "）。下次复习：" +
                  String(body.nextReviewAt).slice(0, 10) +
                  "，间隔 " + body.intervalDays + " 天。",
              })
            )
            out.appendChild(el("p", { class: "muted", text: "点「换一张」继续。" }))
          } catch (err) {
            out.textContent = ""
            out.appendChild(el("p", { class: "error", text: String(err.message || err) }))
          }
        },
      })
    })

    return el("section", { class: "panel" }, [
      el("h2", { text: "该复习这道" }),
      el("div", { class: "kv" }, [
        el("div", {}, [document.createTextNode("题目："), el("span", { text: action.title })]),
        el("div", {}, [document.createTextNode("用时："), el("span", { text: "这一步大约 " + action.estimatedMinutes + " 分钟" })]),
      ]),
      el("p", { class: "reason", text: action.reason }),
      el("div", { class: "row" }, buttons),
      out,
    ])
  }

  A.pages.review = {
    title: "复习",
    buttons: BUTTONS,
    render: async function (view) {
      view.textContent = ""
      view.appendChild(el("div", { class: "panel", text: "加载中…" }))
      let next = null
      try {
        next = await A.getJson("/api/next")
      } catch (err) {
        view.textContent = ""
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "加载失败" }),
            el("p", { class: "error", text: String(err.message || err) }),
          ])
        )
        return
      }
      view.textContent = ""
      const action = next && next.action
      view.appendChild(queuePanel(next))
      if (action && action.kind === "review") {
        view.appendChild(cardPanel(action))
      } else {
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "暂时没有要复习的卡片" }),
            el("p", { class: "muted", text: "没有到期的卡片，或者今天的复习配额已经用完。回到「今日」页做别的吧。" }),
          ])
        )
      }
    },
  }
})()
```

- [ ] **Step 8: 写 web/pages/rounds.js**

Create `projects/apps/algo-plan/web/pages/rounds.js`：

```javascript
"use strict"
/**
 * rounds.js —— 轮次页：清单可视化 + 勾选写回 + 看 diff
 *
 * 勾选走 PATCH /api/rounds/:id/items/:itemId，写回只改 learning 仓里那一行，
 * **app 绝不自动 commit** —— diff 摆出来，提交与否由用户决定。
 */

(function () {
  const A = window.AlgoPlan
  const el = A.el

  /** 今天的日期（写完成时间用） */
  function today() {
    const now = new Date()
    const m = String(now.getMonth() + 1).padStart(2, "0")
    const d = String(now.getDate()).padStart(2, "0")
    return now.getFullYear() + "-" + m + "-" + d
  }

  /** 一行条目 */
  function itemRow(round, item, out) {
    const box = el("input", { type: "checkbox" })
    box.checked = item.status === "done"
    box.addEventListener("change", async function () {
      const done = box.checked
      box.disabled = true
      out.textContent = "写回中…"
      try {
        const body = await A.patchJson(
          "/api/rounds/" + encodeURIComponent(round.id) + "/items/" + encodeURIComponent(item.id),
          { status: done ? "done" : "todo", doneDate: done ? today() : "" }
        )
        out.textContent = ""
        out.appendChild(el("p", { class: "ok-text", text: "已写回 learning 仓（没有自动提交，提交与否由你决定）。" }))
        out.appendChild(el("pre", { class: "diff", text: body.diff || "（没有变化）" }))
        if (body.warnings && body.warnings.length > 0) {
          out.appendChild(el("ul", {}, body.warnings.map(function (w) { return el("li", { class: "warn-text", text: w }) })))
        }
      } catch (err) {
        out.textContent = ""
        out.appendChild(el("p", { class: "error", text: String(err.message || err) }))
        box.checked = !done
      } finally {
        box.disabled = false
      }
    })
    return el("tr", {}, [
      el("td", {}, [box]),
      el("td", { text: item.id }),
      el("td", { text: item.title }),
      el("td", {}, [el("span", { class: item.status === "done" ? "badge ok" : "badge", text: item.status === "done" ? "已完成" : "待完成" })]),
      el("td", { text: item.doneDate || "" }),
    ])
  }

  /** 一个轮次 */
  function roundPanel(round) {
    const out = el("div", { class: "result" })
    const rows = round.items.map(function (item) {
      return itemRow(round, item, out)
    })
    const doneCount = round.items.filter(function (item) {
      return item.status === "done"
    }).length

    return el("section", { class: "panel" }, [
      el("h2", { text: round.title || round.id }),
      el("div", { class: "kv" }, [
        el("div", {}, [document.createTextNode("轮次："), el("span", { text: round.id })]),
        el("div", {}, [document.createTextNode("状态："), el("span", { class: round.status === "done" ? "badge ok" : "badge", text: round.status === "done" ? "已完成" : "进行中" })]),
        el("div", {}, [document.createTextNode("进度："), el("span", { text: doneCount + "/" + round.items.length })]),
        el("div", {}, [document.createTextNode("目标："), el("span", { text: round.goal || "（没写目标）" })]),
      ]),
      round.items.length === 0
        ? el("p", { class: "muted", text: "这个轮次没解析出清单条目。" })
        : el("table", {}, [
            el("thead", {}, [
              el("tr", {}, [
                el("th", { text: "" }),
                el("th", { text: "ID" }),
                el("th", { text: "名称" }),
                el("th", { text: "状态" }),
                el("th", { text: "完成时间" }),
              ]),
            ]),
            el("tbody", {}, rows),
          ]),
      out,
    ])
  }

  A.pages.rounds = {
    title: "轮次",
    render: async function (view) {
      view.textContent = ""
      view.appendChild(el("div", { class: "panel", text: "加载中…" }))
      let data = null
      try {
        data = await A.getJson("/api/rounds")
      } catch (err) {
        view.textContent = ""
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "加载失败" }),
            el("p", { class: "error", text: String(err.message || err) }),
          ])
        )
        return
      }
      view.textContent = ""

      if (data.warnings && data.warnings.length > 0) {
        view.appendChild(
          el("section", { class: "panel warn-panel" }, [
            el("h2", { text: "解析告警（" + data.warnings.length + "）" }),
            el("ul", {}, data.warnings.map(function (w) { return el("li", { text: w }) })),
          ])
        )
      }

      const rounds = data.rounds || []
      if (rounds.length === 0) {
        view.appendChild(
          el("section", { class: "panel" }, [
            el("h2", { text: "轮次" }),
            el("p", { class: "muted", text: "learning/progress/ 下没解析到轮次文件。" }),
          ])
        )
        return
      }
      rounds.forEach(function (round) {
        view.appendChild(roundPanel(round))
      })
    },
  }
})()
```

- [ ] **Step 9: 给 web/style.css 追加样式**

在 `projects/apps/algo-plan/web/style.css` **末尾**追加：

```css
/* ---------- M4：四个页面用到的控件 ---------- */
.row { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin: 10px 0; }
button {
  background: #262b33;
  border: 1px solid var(--line);
  border-radius: 8px;
  color: var(--fg);
  font-size: 14px;
  padding: 6px 14px;
  cursor: pointer;
}
button:hover { border-color: var(--accent); }
button.primary { background: var(--accent); border-color: var(--accent); color: #0f1216; font-weight: 600; }
button:disabled { opacity: 0.5; cursor: default; }
textarea.code {
  width: 100%;
  background: #10131a;
  border: 1px solid var(--line);
  border-radius: 8px;
  color: var(--fg);
  font: 13px/1.6 Consolas, "Cascadia Mono", monospace;
  padding: 10px 12px;
  resize: vertical;
}
select {
  background: #262b33;
  border: 1px solid var(--line);
  border-radius: 8px;
  color: var(--fg);
  font-size: 14px;
  padding: 6px 10px;
}
.reason { color: var(--muted); margin: 10px 0; }
.muted { color: var(--muted); }
.error { color: var(--bad); }
.ok-text { color: var(--ok); }
.warn-text { color: var(--warn); }
.result { margin-top: 12px; }
.bar { height: 8px; background: #262b33; border-radius: 999px; overflow: hidden; margin-top: 10px; }
.fill { height: 100%; background: var(--accent); }
.diff {
  background: #10131a;
  border: 1px solid var(--line);
  border-radius: 8px;
  color: var(--fg);
  font: 12px/1.6 Consolas, "Cascadia Mono", monospace;
  padding: 10px 12px;
  overflow-x: auto;
  white-space: pre;
}
.warn-panel { border-color: var(--warn); }
.correction { border-top: 1px solid var(--line); margin-top: 14px; padding-top: 12px; }
.correction h3 { font-size: 14px; margin: 0 0 8px; }
table { width: 100%; border-collapse: collapse; margin-top: 8px; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); font-size: 14px; }
th { color: var(--muted); font-weight: 500; }
```

- [ ] **Step 10: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node --check web/app.js && node --check web/pages/today.js && node --check web/pages/answer.js && node --check web/pages/review.js && node --check web/pages/rounds.js && node tests/run-all.js
```

Expected: `node --check` 五处都无输出；`14 / 14 套件通过`，退出码 0

- [ ] **Step 11: 真起一次服务，人工看四页**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

另开一个终端：

```bash
curl -s http://127.0.0.1:5173/api/next
curl -s http://127.0.0.1:5173/api/rounds | head -c 400
curl -s http://127.0.0.1:5173/api/progress
```

浏览器打开 `http://127.0.0.1:5173/`，逐个点「今日 / 作答 / 复习 / 轮次」四个标签。

Expected:
- 今日页出现「下一步」卡片，写着类型、题目、「这一步大约 N 分钟」，下面有今日进度条
- 复习页出现四个按钮：完全忘了 / 想很久 / 有点印象 / 秒答
- 轮次页列出 learning/progress 下的 9 个轮次，勾选后弹出 diff，**learning 仓里只有那一行变了，`git status` 会看到改动，但 app 不会提交**

> **不要在 learning 仓里 `git checkout` 回滚**：写回是给人看的真实改动，要不要提交由人决定。

- [ ] **Step 12: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加今日 / 作答 / 复习 / 轮次四个页面

- web/app.js：改成 tab 调度 + 公共工具，el 支持 on* 事件监听
- web/pages/today.js：下一题卡片、到期复习数、今日进度条与配额
- web/pages/answer.js：题面、代码框、提交判题、错题订正（M3 未上线时给中文提示）
- web/pages/review.js：四个直觉评分按钮，映射到 SM-2 的 quality 1/2/3/5
- web/pages/rounds.js：轮次清单可视化、勾选写回、显示 diff
- 写回后只显示 diff，app 绝不自动提交 learning 仓
- 测试：四个页面注册、index.html 引用、评分映射共 3 条断言"
git push origin main
```

---

## Task 7: 端到端闭环验收与 README

**Files:**
- Create: `projects/apps/algo-plan/tests/fixtures-m4.js`（M4 各测试共用的临时 learning 仓）
- Create: `projects/apps/algo-plan/tests/e2e-m4.test.js`
- Modify: `projects/apps/algo-plan/tests/api-m4.test.js`（改成复用 `fixtures-m4.js`，不再各写一份夹具）
- Modify: `projects/apps/algo-plan/README.md`

**Interfaces:**
- Consumes: Task 1–6 的全部产出
- Produces:
  - `tests/fixtures-m4.js` 导出 `{PROBLEM_MD, ROUND_MD, tempLearning, withApp}`
  - 端到端验收：**写回落在 learning 仓工作区，app 不自动提交**（用 `git rev-list --count HEAD` 前后对比来证明）

- [ ] **Step 1: 写失败的端到端测试**

Create `projects/apps/algo-plan/tests/fixtures-m4.js`：

```javascript
"use strict"
/**
 * fixtures-m4.js —— M4 各测试共用的临时 learning 仓
 *
 * 全程在 fs.mkdtemp 出来的临时目录里跑，**绝不碰真实的 learning 仓**。
 * 临时仓是个 git 仓库并且初始提交过一次——写回前要查脏，工作区必须是干净的。
 */

const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const { createApp } = require("../server/app.js")

/** 一道题（题库文件） */
const PROBLEM_MD = [
  "---",
  "id: lc-00001",
  "source: leetcode",
  "title: 两数之和",
  "difficulty: easy",
  "topics: [哈希表, 数组]",
  "tracks: [interview, fundamentals]",
  "status: todo",
  "needs_fill: false",
  "created: 2026-11-11",
  "updated: 2026-11-11",
  "---",
  "## 题面",
  "",
  "给定整数数组与目标值。",
  "",
  "## 测试用例",
  "",
  "| input | expect |",
  "|---|---|",
  "| [2,7,11,15], 9 | [0,1] |",
  "",
  "## 参考解法",
  "",
  "```cpp",
  "int main() { return 0; }",
  "```",
  "",
].join("\n")

/** 一个轮次（清单表头照抄真实的 r33） */
const ROUND_MD = [
  "# R33 Grokking 算法篇 — 学习进度",
  "",
  "## 基本信息",
  "",
  "| 字段 | 值 |",
  "|------|-----|",
  "| 开始时间 | 2026-07-12 |",
  "| 目标 | Grokking 算法篇 16 张卡片 |",
  "| 状态 | TBD-deferred |",
  "",
  "## 卡片清单",
  "",
  "| 序号 | ID | 名称 | 状态 | 完成时间 |",
  "|------|-----|------|------|----------|",
  "| 1 | two_sum | 两数之和 | todo |  |",
  "| 2 | arrays | 数组技巧 | todo |  |",
  "",
].join("\n")

/** 造一个干净的临时 learning 仓（git 仓库 + 题库 + 轮次） */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-m4-"))
  const bank = path.join(root, "bank", "interview")
  fs.mkdirSync(bank, { recursive: true })
  fs.writeFileSync(path.join(bank, "lc-00001.md"), PROBLEM_MD, "utf8")
  const progress = path.join(root, "progress")
  fs.mkdirSync(progress, { recursive: true })
  fs.writeFileSync(path.join(progress, "r33-progress.md"), ROUND_MD, "utf8")

  execFileSync("git", ["init", "-q"], { cwd: root })
  execFileSync("git", ["config", "user.email", "test@example.com"], { cwd: root })
  execFileSync("git", ["config", "user.name", "test"], { cwd: root })
  execFileSync("git", ["add", "-A"], { cwd: root })
  execFileSync("git", ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "初始化"], { cwd: root })
  return root
}

/** 起一次服务，跑完就关 */
async function withApp(fn) {
  const root = tempLearning()
  const app = createApp({ dbPath: ":memory:", learningRoot: root })
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port, root)
  } finally {
    await app.close()
  }
}

module.exports = {
  PROBLEM_MD: PROBLEM_MD,
  ROUND_MD: ROUND_MD,
  tempLearning: tempLearning,
  withApp: withApp,
}
```

Create `projects/apps/algo-plan/tests/e2e-m4.test.js`：

```javascript
"use strict"
/**
 * e2e-m4.test.js —— M4 闭环端到端
 *
 * 下一题 → 勾选写回 → 错题订正 → 复习评分，
 * 并验证写回落在 learning 仓的**工作区**、**app 没有自动提交**。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const { withApp } = require("./fixtures-m4.js")

/** 工作区状态（相对仓库根的路径，中文不转义） */
function gitStatus(root) {
  return execFileSync("git", ["-c", "core.quotepath=false", "status", "--porcelain"], {
    cwd: root,
    encoding: "utf8",
  })
}

/** 提交条数 */
function commitCount(root) {
  const out = execFileSync("git", ["rev-list", "--count", "HEAD"], {
    cwd: root,
    encoding: "utf8",
  })
  return Number(String(out).trim())
}

test("闭环：下一题 → 勾选写回 → 错题订正 → 复习评分，且不自动提交", async function () {
  await withApp(async function (base, root) {
    const commitsBefore = commitCount(root)

    /* 1. 下一题 */
    const nextRes = await fetch(base + "/api/next")
    assert.strictEqual(nextRes.status, 200)
    const next = await nextRes.json()
    assert.ok(next.action, "应该给出下一个动作")
    assert.ok(next.action.reason.length > 0, "要给出中文理由")

    /* 2. 勾选写回：只改目标行 */
    const patchRes = await fetch(base + "/api/rounds/r33/items/two_sum", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ status: "done", doneDate: "2026-11-11" }),
    })
    assert.strictEqual(patchRes.status, 200)
    const patched = await patchRes.json()
    assert.ok(patched.diff.indexOf("two_sum") !== -1, patched.diff)

    const roundText = fs.readFileSync(path.join(root, "progress", "r33-progress.md"), "utf8")
    assert.ok(
      roundText.indexOf("| 1 | two_sum | 两数之和 | done | 2026-11-11 |") !== -1,
      roundText
    )
    assert.ok(roundText.indexOf("| 2 | arrays | 数组技巧 | todo |  |") !== -1, roundText)

    /* 3. 错题订正 */
    const corrRes = await fetch(base + "/api/correction", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", text: "先查再插，别先插再查。" }),
    })
    assert.strictEqual(corrRes.status, 200)
    const corr = await corrRes.json()
    assert.ok(fs.existsSync(corr.file), "订正笔记要真的写出来")
    assert.ok(fs.readFileSync(corr.file, "utf8").indexOf("先查再插") !== -1)

    /* 4. 复习评分 */
    const gradeRes = await fetch(base + "/api/review/lc-00001/grade", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ quality: 3 }),
    })
    assert.strictEqual(gradeRes.status, 200)
    const graded = await gradeRes.json()
    assert.strictEqual(graded.problemId, "lc-00001")
    assert.strictEqual(graded.intervalDays, 1)

    /* 5. 写回落在工作区，app 没有自动提交 */
    const status = gitStatus(root)
    assert.ok(status.indexOf("r33-progress.md") !== -1, status)
    assert.ok(status.indexOf("订正") !== -1, status)
    assert.strictEqual(commitCount(root), commitsBefore, "app 不应该自动提交")
  })
})

test("learning 仓脏的时候写回被拒绝，仓库内容一个字节都不动", async function () {
  await withApp(async function (base, root) {
    const file = path.join(root, "progress", "r33-progress.md")
    const before = fs.readFileSync(file, "utf8")
    fs.writeFileSync(path.join(root, "别的改动.md"), "手工改的\n", "utf8")

    const res = await fetch(base + "/api/rounds/r33/items/two_sum", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ status: "done" }),
    })
    assert.strictEqual(res.status, 409)
    const body = await res.json()
    assert.ok(body.dirtyFiles.length > 0)
    assert.strictEqual(fs.readFileSync(file, "utf8"), before, "被拒绝时不能改动文件")
  })
})
```

- [ ] **Step 2: 让 api-m4.test.js 复用同一份夹具**

Modify `projects/apps/algo-plan/tests/api-m4.test.js`：

**删掉**三样东西（它们已经搬到 `tests/fixtures-m4.js`）：

1. `const { execFileSync } = require("node:child_process")` 这一行
2. `const PROBLEM_MD = [...]` 整个常量
3. `const ROUND_MD = [...]` 整个常量
4. `function tempLearning() { ... }` 整个函数

**换成**一行 require：

```javascript
const { tempLearning, withApp } = require("./fixtures-m4.js")
```

文件开头的 require 段变成：

```javascript
"use strict"
/**
 * api-m4.test.js —— M4 的接口：下一题 / 评分 / 轮次 / 勾选写回 / 错题订正 / 今日进度
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { tempLearning, withApp } = require("./fixtures-m4.js")
```

- [ ] **Step 3: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `15 / 15 套件通过`，退出码 0

- [ ] **Step 4: 更新 README**

Modify `projects/apps/algo-plan/README.md`：

1. 把开头这两行：

```markdown
当前进度：**M1 骨架**（服务起得来 / SQLite schema / 题库 md 解析 / 页面壳）。
判题、复习、轮次、诊断、LLM 属于 M2–M6，尚未实现。
```

替换成：

```markdown
当前进度：**M4 闭环**（推下一题 / SM-2 复习 / 轮次清单 / 勾选写回 / 错题订正）。
判题（M3）、诊断（M5）、LLM（M6）尚未实现——没做判题时，「作答」页会提示接口还没上线。
```

2. 把「## 目录结构」里的 `core/` 那一行说明换成：

```
├── core/            纯函数层：Problem 模型、markdown 解析、provider、路径解析
│   ├── review/      SM-2 间隔重复与判题结果映射
│   ├── scheduler/   推下一题：候选动作优先级 + 单日配额
│   └── sync/        learning 仓同步：轮次解析、勾选写回、错题订正、查脏
```

3. 把 `web/` 那一行换成：

```
├── web/             原生 JS 单页（无构建）：today / answer / review / rounds 四页
```

4. 在「## 接口」表格末尾追加：

```markdown
| GET | `/api/next` | 下一个动作：复习 / 轮次推进 / 主动探索，带「这一步大约 N 分钟」 |
| POST | `/api/review/:id/grade` | 给复习卡片打分（`quality` 0~5），返回下一次复习时间、间隔、难度因子、遗忘次数 |
| GET | `/api/rounds` | learning/progress 下的轮次清单与解析告警 |
| PATCH | `/api/rounds/:id/items/:itemId` | 勾选写回（`status` / `doneDate` / `commitSha`），只改目标行，返回 diff |
| POST | `/api/correction` | 写错题订正到 `notes/practice/<id>-订正.md`，返回文件路径与 diff |
| GET | `/api/progress` | 今日进度与单日复习配额 |
```

5. 在「## 测试」的表格末尾追加：

```markdown
| `sm2.test.js` | SM-2 公式、easiness 下限、六档 quality 映射、到期与逾期排序 |
| `rounds-parse.test.js` | 7 种真实表头变体、缺列、坏行、告警 |
| `sync-write.test.js` | 查脏、只改目标行、缺列告警、脏仓拒绝、错题订正 |
| `next-action.test.js` | 三级优先级、两种配额耗尽、轮次挑选与掌握度排序 |
| `api-m4.test.js` | M4 五个接口的响应字段 |
| `pages.test.js` | 四个页面注册与评分映射 |
| `e2e-m4.test.js` | 下一题 → 写回 → 订正 → 评分，且不自动提交 |
```

6. 在「## 归属」之前插入新的一节：

```markdown
## 写回 learning 仓的规矩

- **写回前查脏**：`git -c core.quotepath=false status --porcelain -z`（按 NUL 切分），
  工作区不干净就拒绝写回，并告诉你哪个文件被动过。
- **只改目标行**：读-改-写，整份轮次文件只有那一行会变。
- **绝不自动 commit**：写回只落在 learning 仓的工作区，界面把 diff 摆出来，
  提交与否由你决定。app 不会替你 `git add`，也不会替你 `git commit`。
- **错题订正**写到 `notes/practice/<题目ID>-订正.md`，frontmatter 键序按
  `notes/_meta/schema.md` 登记的 `correction` 惯例。
```

- [ ] **Step 5: 端到端真跑一次（人工）**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

浏览器打开 `http://127.0.0.1:5173/`：

1. 「今日」页应给出下一个动作（learning 仓里有 9 个轮次文件，会走「轮次推进」）
2. 「轮次」页勾选一个条目 → 弹出 diff；**learning 仓的 git 里会多出一处改动，但没有任何新提交**
3. 「复习」页在有到期卡片时显示四个评分按钮
4. 「作答」页在 M3 没做之前提示「判题接口还没上线（M3 未完成）」

Expected: 四页都能打开；勾选写回只改一行；`git log` 条数不变。

> 真实 learning 仓里留下的改动由你自己决定提交还是回滚——**app 不会替你提交**。

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 补上 M4 端到端闭环验收与 README

- tests/fixtures-m4.js：M4 各测试共用的临时 learning 仓（git 仓库，初始已提交）
- tests/e2e-m4.test.js：下一题 → 勾选写回 → 错题订正 → 复习评分，
  并用 git rev-list --count HEAD 前后对比证明 app 没有自动提交
- 脏工作区时写回被拒绝，仓库内容一个字节都不动
- README：补 M4 的六个接口、四个页面、SM-2/排程/同步目录说明与写回规矩
- 测试：15 / 15 套件通过"
git push origin main
```

---

## M4 验收清单

做完上面 7 个 Task，逐条对照：

- [ ] `node tests/run-all.js` → `15 / 15 套件通过`，退出码 0
- [ ] `node --check` 五个前端脚本都无语法错误
- [ ] `GET /api/next` 每次只给**一个**动作，带「这一步大约 N 分钟」
- [ ] 有到期卡片时给复习；配额（10 题 / 20 分钟）任一顶到就改推新题
- [ ] 多个 active 轮次时优先最近创建的；轮次内掌握度最低的 topic 优先，同 topic 按题号顺序
- [ ] `GET /api/rounds` 能解析 learning/progress 下 **9 个**轮次文件的 **7 种表头变体**
- [ ] 坏行跳过并计告警，告警在界面上看得见
- [ ] 勾选写回**只改目标行**，写后返回 diff
- [ ] learning 仓工作区不干净时**拒绝写回**并指出被动过的文件
- [ ] 写回 learning 仓后**没有任何自动提交**（提交条数不变）
- [ ] 错题订正写到 `notes/practice/<id>-订正.md`，frontmatter 键序与
      `learning/notes/_meta/schema.md` 登记的 `correction` 惯例一致
- [ ] 复习评分用四个直觉文案，映射到 SM-2 的 quality 1 / 2 / 3 / 5
- [ ] 四个页面（今日 / 作答 / 复习 / 轮次）都能打开
- [ ] M3 没上线时作答页给中文提示，不白屏

## 后续里程碑备忘（M5–M6，写计划时直接用）

- **M5 诊断**：`core/mastery/mastery.js` 落地后，把 `core/scheduler/next-action.js` 里的
  `masteryByTopic` 换成 `masteryOf(topicId)`——**接口不变**，只换实现。
  届时补上设计文档 §4.3 的遗忘因子 `0.5 ^ (距上次练习天数 / 14)`
  （M4 的近似值不含这一项），并补「覆盖度」维度，凑齐四种诊断状态。
- **M6 LLM**：出题、生成测试用例、解释错误。`core/bank/problem.js` 的 `makeLlmId(seed)`
  已经预留；LLM 出的题同样进 `learning/bank/<track>/`，一样受「不自动 commit」约束。
- **M3 判题**没上线前，「作答」页只能看题面不能判题；M3 上线后把
  `POST /api/attempt` 的 verdict 接进 `qualityFromOutcome(outcome)`，
  自动算出 0~5 的 quality，就不用手点四个按钮了。


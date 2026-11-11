# 算法能力提升计划 App —— M2–M6 跨计划接口契约

> 日期：2026-11-11
> 作用：M2 / M3 / M4 / M5 / M6 五份实施计划**共用**这一份契约。
> 任何一份计划里的新模块、函数签名、API 响应形状，都必须与本文件一致；
> 本文件没写的东西，各计划可以自由新增，但不能与本文件冲突。
>
> 上游依据：
> - 设计文档：`docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`
> - M1 计划（已写全，**尚未执行**）：`docs/superpowers/plans/2026-11-11-algo-plan-app-M1.md`
> - M1 勘察备忘（M2–M4 写计划时直接用）：M1 计划末尾的「后续里程碑备忘（M2–M4，写计划时直接用）」

---

## 0. 起点状态：M1 执行完后仓库里有什么

M1 计划的 7 个 Task 全部执行完之后，`projects/apps/algo-plan/` 里有：

```
package.json                 无 dependencies
core/paths.js                resolveLearningRoot / bankDir
core/bank/problem.js         Problem 模型与常量
core/bank/parse.js           markdown ↔ Problem 双向转换
core/bank/provider.js        FileProvider / NullProvider
server/router.js             路由内核
server/app.js                组合根 createApp
server/db.js                 SQLite schema 与 store
server/api.js                buildRoutes(ctx)，M1 的三个接口
web/index.html web/app.js web/style.css
tools/seed-bank.js           样板题导入
fixtures/seed-bank/          2 道样板题
tests/run-all.js + 8 个套件
```

**M1 已冻结的导出签名（M2–M6 直接用，不要改）**：

```js
// core/paths.js
resolveLearningRoot(env, override?) -> {root: string|null, ok: boolean, reason: string}
bankDir(learningRoot) -> string|null

// core/bank/problem.js
TRACKS, SOURCES, SOURCE_PREFIX, DIFFICULTIES, STATUSES
normalizeTopic(text) -> string
normalizeTopics(list) -> string[]
normalizeTracks(list) -> string[]
today() -> "YYYY-MM-DD"
makeId(source, number) -> string
makeLlmId(seed) -> string
isValidId(id) -> boolean
validateProblem(problem) -> {ok: boolean, errors: string[]}
createProblem(input) -> Problem      // 字段非法直接抛错
toSummary(problem) -> {id,title,source,difficulty,topics,tracks,status,needsFill}

// core/bank/parse.js
parseFrontmatter(text) -> object
serializeFrontmatter(obj) -> string
splitSections(body) -> {标题: 内容}
parseCases(text) -> [{input, expect, tol}]
parseSolution(text) -> {code, lang}
parseProblemMarkdown(text) -> {problem, warnings}
serializeProblemMarkdown(problem) -> string

// core/bank/provider.js
new FileProvider(bankDir | null)
  .list(filter?) -> Promise<Problem[]>   // filter: {track, topic, difficulty, status, idPrefix}
  .get(id) -> Promise<Problem|undefined>
  .put(problem) -> Promise<string>       // 返回写入的绝对路径
  .stats() -> {fileCount, problemCount, warnings[]}
new NullProvider()

// server/db.js
openDb(filePath) -> DatabaseSync
createStore(db) -> store
  store.getSetting(key, fallback?) -> string|null
  store.setSetting(key, value)
  store.allSettings() -> {key: value}
  store.insertAttempt(attempt) -> number
  store.listAttemptsByProblem(problemId) -> row[]
  store.countAttempts() -> number
  store.upsertReviewCard(card) / store.getReviewCard(problemId) / store.listDueCards(nowIso) / store.countReviewCards()
  store.upsertTopic(topic) / store.listTopics() / store.countTopics()
  store.close()

// server/app.js
createApp({dbPath?, learningRoot?, env?}) -> {server, listen(port), close(), db, store, provider, learning}
createServer({routes}) -> {server, listen(port), close()}
sendJson(res, status, body)
ROOT, WEB_DIR

// server/api.js
buildRoutes(ctx) -> Array<{method, pattern, handler}>   // ctx = {store, provider, learning, sendJson}
SAMPLE_CASE_COUNT = 2

// Problem 的字段形状（M2–M6 全部按这个来）
{
  id, source, title, difficulty, topics[], tracks[], status, needsFill,
  created, updated, statement, cases: [{input, expect, tol}], solution, solutionLang, extraSections[]
}
```

**M1 已冻结的三个接口**（M4/M5/M6 在此基础上**加字段**，不另起炉灶）：

| 接口 | 响应形状 |
|---|---|
| `GET /api/health` | `{ok, node, learning:{ok,root,reason}, bank:{fileCount,problemCount,warnings}, attempts}` |
| `GET /api/bank?track=&topic=&difficulty=&status=&prefix=&limit=` | `{total, items:[摘要]}` |
| `GET /api/problem/:id` | `{id,title,source,difficulty,topics,tracks,status,needsFill,statement,cases:{sample,total}}` |

---

## 1. M2 新增（题库）

```
core/bank/legacy.js        纯函数：解析死脚本里的内联题目清单、分类 slug → track 映射
core/bank/solutions-scan.js 纯函数：解析存量题解文件 → 题目条目
tools/import-catalog.js    死脚本清单 → learning/bank
tools/import-solutions.js  存量题解 → learning/bank
```

```js
// core/bank/legacy.js
CATEGORY_TRACK_MAP                     // {categorySlug: track}，25 个 slug 全覆盖
parseLegacyPracticeData(text) -> {items: [{platform, problemId, title, difficulty, tags[], repeat}], warnings[]}
mapCategoryToTrack(slug) -> track      // 未知 slug 落到 "interview" 并计告警
legacyIdOf(item) -> string             // 用 M1 的 makeId；platform: leetcode→lc / nowcoder→nc

// core/bank/solutions-scan.js
parseSolutionFiles(files) -> {items: [{source, sourceId, title, lang, code, file}], warnings[]}
```

```js
// tools/import-catalog.js 与 tools/import-solutions.js 同形
run(opts) -> {written: string[], skipped: string[], errors: string[], warnings: string[]}
opts = {env, dryRun?, force?, scriptsDir?, learningRoot?}
```

**M2 的硬约定**：

- 导入的题一律 `needsFill: true`（死脚本与存量题解都没有题面和用例）
- `difficulty` 只有 `easy` / `medium`，**没有 hard**（实测事实，别造 hard）
- id 冲突时跳过并计入 `skipped`；`force: true` 才覆盖
- 写进 `learning/bank/<track>/<id>.md`，**不要**建 `learning/bank/data/`

---

## 2. M3 新增（判题）

```
core/judge-spec/cases.js    用例归一化
core/judge-spec/compare.js  输出比对
judge/sandbox.js             临时目录、跑进程、超时杀进程树、解释器探测
judge/runner.js             编排：写文件 → 编译 → 跑用例 → 比对 → verdict
judge/manifest.js           fixture 题库清单（判题测试用的题面 + 用例 + 参考解法）
```

```js
// core/judge-spec/cases.js
normalizeCases(cases) -> [{index, expect, input, tol}]   // index 从 1 开始

// core/judge-spec/compare.js
compareOutput(actual, expected, tol) -> {equal: boolean, reason: string}
//   默认：去首尾空白 + 忽略末尾空行后精确匹配
//   tol != null：数值容差比较

// judge/sandbox.js
detectCompiler() -> {cmd: "g++", version: string} | null
detectPython(override?: string|null) -> {cmd: string, args: string[], version: string} | null
  // 依次试 python3 → python → py -3，第一个能跑 --version 的胜出
  // 给了 override 就先试它；override 与缓存一致时直接复用缓存，不再 spawn
createSandbox() -> {dir: string, cleanup(): void}
runCommand(cmd, args, {cwd, input, timeoutMs}) -> Promise<{
  code: number|null, stdout: string, stderr: string,
  durationMs: number, timedOut: boolean, signal: string|null,
  truncated: boolean          // 输出是否被 2MB 上限截断过
}>
  // 超时后杀整棵进程树；杀完还没结束就等 2 秒宽限期，到点强行按超时收摊
  // （否则请求会永远挂着，临时目录也永远删不掉）

// judge/runner.js
judge({problem, code, language, timeoutMs}) -> Promise<{
  verdict: "pass"|"wrong_answer"|"timeout"|"compile_error"|"runtime_error",
  passedCases: number, totalCases: number, durationMs: number,
  failedCase: {index, input, expected, actual} | null,
  message: string,        // 中文说明
  compilerOutput: string, // 编译错误原文 / stderr
}>
```

**M3 的硬约定**：

- **判题契约是「stdin 进、stdout 出」的裸程序**：用户必须自己写 `main()`。
  存量 LeetCode 风格题解是 `class Solution{...}` 没有 `main()`——**不注入、不包装、不自动生成 main**。
- **不得写死 `python3`**：本机 `python3` 是 Microsoft Store 的空占位符，真身是 `python`（3.11.15）/ `py -3`（3.12.3）。
  按 `python3` → `python` → `py -3` 依次探测。
- C/C++：`g++ -std=c++17 -O2`，**不加** `-Werror`、**不加** `-Wall`。
- 单用例超时默认 2000ms。超时必须杀**整棵进程树**：Windows `taskkill /T /F`，POSIX 进程组 kill。
- 编译产物与临时目录判完即删。
- 这**不是安全沙箱**：用户代码以自己的权限在临时目录里跑。

**M3 新增接口**：

| 接口 | 响应 |
|---|---|
| `POST /api/attempt` | 入参 `{problemId, code, language, mode}`；响应 `{attemptId, verdict, passedCases, totalCases, durationMs, failedCase, message, compilerOutput}` |

`mode` 取 `solve` / `review` / `probe`。

---

## 3. M4 新增（闭环）

```
core/review/sm2.js           SM-2（公式逐字搬自 projects/apps/knowledge-hub/core/review.js）
core/scheduler/next-action.js 候选动作优先级 + 每日配额 → 下一个动作
core/sync/rounds.js          轮次解析 / 勾选写回 / 错题订正 / 工作区查脏
```

```js
// core/review/sm2.js
DEFAULT_EASE = 2.5
grade(card, quality, nowIso) -> card     // card 用 M1 的 review_cards 形状（snake_case）
qualityFromOutcome(outcome) -> number    // 0~5
isDue(card, nowIso) -> boolean
sortByOverdue(cards, nowIso) -> card[]

// core/scheduler/next-action.js
nextAction(ctx) -> action | null
ctx = {store, provider, rounds, nowIso, settings}
// action = {kind: "review"|"round"|"explore", problemId, problem, estimatedMinutes, reason, reviewQueueLength}

// core/sync/rounds.js
parseRounds(progressRoot) -> {rounds, warnings}
  // round = {id, file, title, goal, status, items}
  // item  = {raw, id, title, status, doneDate, commitSha}
updateRoundItem(progressRoot, roundId, itemId, patch) -> {diff, warnings}
writeCorrection(learningRoot, problem, text) -> {file, diff}
assertCleanWorktree(repoRoot) -> {ok, dirtyFiles}
```

**M4 的硬约定**：

- 复习优先于新题，但**单日配额取先到者**：「10 题 **或** 20 分钟」。
  配额键：`review.daily_quota_questions` / `review.daily_quota_minutes`（存 `settings` 表）。
- 多个 active 轮次允许并行，**优先最近创建的 active 轮次**。
- 轮次内挑题：**掌握度最低的 topic 优先**，同 topic 内按题号顺序。
- 每次只给**一个**动作，附「这一步大约 N 分钟」。
- 轮次解析**按列名关键词匹配**，不按列序、不按固定列数。已实测 learning 仓有 6 种列名变体：
  `序号|ID|名称|语言|状态|完成时间|commit SHA` / `序号|ID|名称|状态|完成时间|commit SHA` /
  `序号|ID|名称|状态|完成时间` / `# | 卡片 ID | 主题 | 状态` / `ID | 卡片 | 主题 | 状态` / `卡 ID | 名称 | 状态`。
- 解析不了的行**跳过并计入告警**，绝不整体报错。告警数要在 UI 上可见。
- 写回前查脏：`git -c core.quotepath=false status --porcelain -z`，**按 NUL 切分**，
  不要用 `line.slice(3)` 硬切（中文路径与带空格路径会切错）。
- 写回**只改目标行**；写后返回 diff；**绝不自动 commit**。
- `learning/notes/` 没有现成的「错题订正」惯例，是新建惯例——M4 必须同时在
  `learning/notes/_meta/schema.md` 登记。

**M4 新增接口**：

| 接口 | 响应 |
|---|---|
| `GET /api/next` | `{action: {kind, problemId, title, estimatedMinutes, reason, reviewQueueLength} \| null, reviewQueueLength}` |
| `POST /api/review/:id/grade` | 入参 `{quality}`；响应 `{problemId, nextReviewAt, intervalDays, easiness, lapses}` |
| `GET /api/rounds` | `{rounds: [{id, file, title, goal, status, items:[...]}], warnings: []}` |
| `PATCH /api/rounds/:id/items/:itemId` | 入参 `{status, doneDate, commitSha}`；响应 `{diff, warnings}` |
| `POST /api/correction` | 入参 `{problemId, text}`；响应 `{file, diff}` |
| `GET /api/progress`（M4 补充） | 无入参；响应 `{date, solved, reviewed, reviewMinutes, quota: {limitQuestions, limitMinutes, usedQuestions, usedMinutes}}` |

---

## 4. M5 新增（诊断）

```
core/mastery/mastery.js   掌握度模型与四档诊断
web/diagnose.js 或 web/app.js 内新增诊断页视图
```

```js
// core/mastery/mastery.js
masteryOf(stat, nowIso) -> number          // 0~1
  // 首次通过率 = firstPass / attempts
  // 遗忘因子   = 0.5 ^ (距上次练习天数 / 14)
  // 掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
coverageOf(stat, expectedCount) -> number  // 0~1
diagnose(mastery, coverage) -> "weak-sparse"|"weak-dense"|"strong-sparse"|"strong-dense"
diagnoseLabel(bucket) -> string            // 薄弱且练得少 / 练过但总错 / 偶然会，没练透 / 掌握
rankTopics(stats, nowIso, expectedCounts) -> [{topic, mastery, coverage, bucket, label}]
```

**M5 新增接口**：

| 接口 | 响应 |
|---|---|
| `GET /api/insights` | `{topics:[{topic, mastery, coverage, bucket, label, attempts, firstPass, lapses, lastAt}], summary:{...}, series:[{date, count}]}` |

**M5 的硬约定**：

- 掌握度用 M1 的 `topics` 表统计（`first_pass` / `attempts` / `lapses` / `last_at`）。
- 诊断页要出：掌握度雷达、弱项榜、每日题量曲线、知识点覆盖。
- **不用第三方图表库**（零 npm 依赖）——SVG 手绘。

---

## 5. M6 新增（LLM）

```
core/llm/prompts.js    提示词构造与响应解析（纯函数）
core/llm/client.js     ArkClient / AnthropicClient / NullClient
core/llm/guard.js      成本护栏（单次会话上限 + 每日上限）
core/llm/service.js    服务层：串起 client + guard + prompts，供 HTTP 层调用
server/api-llm.js      M6 的五个场景接口 + LLM 设置的读写
```

```js
// core/llm/prompts.js
buildPrompt(kind, context) -> {system: string, user: string}
  // kind ∈ "explain" | "hint" | "grade-idea" | "generate" | "fill"
parseResponse(text, kind) -> object      // 结构化解析；解析不出给 {ok: false, reason}

// core/llm/client.js
createLlmClient({provider, apiKey, baseUrl, model}) -> client
  client.complete({system, user, temperature}) -> Promise<string>
  client.name -> "ark" | "anthropic" | "null"

// core/llm/guard.js
checkQuota(store, key) -> {ok, used, limit}
consumeQuota(store, key, n) -> {used, limit}
```

**M6 的硬约定**：

- **把 LLM 关掉，app 仍然完整可用**（`NullClient` 返回明确的中文提示，不抛错）。
- **不主动泄题**：讲解只到思路层；只有显式选「直接给代码」才给代码。
- **产出全部可追溯**：生成的题落盘进 `learning/bank/`（`source: llm`，id 用 `makeLlmId`）；
  讲解记录 model + prompt 摘要。
- 提示词是纯函数，`buildPrompt` / `parseResponse` 用 `node:test` 钉住，**不联网测**。
- 成本护栏：单次会话请求上限 + 每日请求上限，超了直接停并提示「今天用完了」。

**M6 新增接口**：

| 接口 | 响应 |
|---|---|
| `POST /api/llm/explain` | 入参 `{problemId, level}`；响应 `{text, model}` |
| `POST /api/llm/hint` | 入参 `{problemId, level}`；level ∈ 方向/思路/伪码/代码；响应 `{text, model}` |
| `POST /api/llm/grade-idea` | 入参 `{problemId, idea}`；响应 `{verdict, comment, model}` |
| `POST /api/bank/llm-generate` | 入参 `{track, topics[], difficulty}`；响应 `{problem, model}`（落盘进 bank） |
| `POST /api/llm/fill` | 入参 `{problemId}`；响应 `{problem, model}`（补全题面与用例，落盘进 bank） |
| `GET/PUT /api/llm/settings`（M6 补充） | 响应 `{provider, model, baseUrl, keySource, enabled}`；PUT 只接受这五个字段 |

---

## 6. M2–M6 共同继承的全局约束

M1 的 **G1–G16 全部继续生效**（零 npm 依赖、零构建、Node ≥ 24、中文注释与提交、提交即推送、
产物只在 `projects/apps/algo-plan/`、learning 仓路径不硬编码、稳定题目 ID、测试入口
`node tests/run-all.js`、中文输出、不自动 commit、SQLite 类型约束等）。各计划在 G1–G16 之后
追加自己的 G17+ 条目，但**以下 6 条是五份计划共用的**，编号统一：

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测，第一个能 `--version` 的胜出；探测结果可缓存进 `settings` |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序，用户自己写 `main()`；不注入 Solution 包装、不自动生成 main |
| G19 | **导入 id 冲突** | 同 id 已存在则跳过并计入 `skipped`；只有 `force` 才覆盖 |
| G20 | **写回前查脏** | `git -c core.quotepath=false status --porcelain -z`，按 NUL 切分；不许 `line.slice(3)` |
| G21 | **轮次解析容错** | 按列名关键词匹配，缺列填空，坏行跳过并计告警；不因一行看不懂而整体报错 |
| G22 | **零第三方图表** | 雷达图、曲线一律手绘 SVG，不引图表库 |

---

## 7. 每份计划必须遵守的写作规范

1. **文件名**：`docs/superpowers/plans/2026-11-11-algo-plan-app-M{N}.md`（M2–M6 各一份）。
2. **开头照抄 M1 计划的头部结构**：标题、`> **For agentic workers:** ...`、Goal、Architecture、Tech Stack、Spec 引用、Global Constraints 表、里程碑边界表、文件结构总览。
3. **每个 Task 是一个可独立验收的交付物**，Task 内用 `- [ ] **Step N: ...**` 复选框。
4. **Step 里给完整可粘贴的代码**（测试代码 + 实现代码），禁止「类似 Task N」「自行补充」「TODO」。
5. **每个 Task 以「跑测试 → 提交并推送」结束**，提交信息中文，落在 `projects` 子模块里。
6. **不许造接口**：跨计划调用只准用本文件里出现的名字。
7. **不许编事实**：涉及 learning 仓与 projects 仓的真实数据（死脚本结构、轮次文件列名、题解目录、
   `g++` / `python` 版本、`.gitignore` 规则），动手前必须读实际文件确认；读不出来就在计划里写明
   「按 X 处理」的处理规则，而不是编一个数。

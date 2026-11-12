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

> **`GET /api/next` 的补充字段**（M4 收尾时实测真实 learning 仓后追加）：
> 轮次分支的动作额外带 `roundId` 与 `itemId`（字符串，别的分支为空串）。
> 原因：真实轮次里混着**不在算法题库里**的卡片（Python 工具链、设计模式……），
> 这类卡片的 `problemId` 为 `null`——推一个打不开题面的题目不算「下一个动作」。
> 前端拿到 `problemId` 为空但有 `roundId` 时，应该把用户带到**轮次页**去勾掉那张卡片，
> 而不是跳去空的作答页。
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

---

## 8. 补全轮追加：两套题库根与 Codeforces 题源

> 日期：2026-11-12
> 背景：M1–M3 完成后补了题库（用户反馈「没有跳原题的链接」「还缺俄罗斯竞赛的题」）。
> 本节记录这轮改动对**既有签名**的增量，M5/M6 直接继承，不再另起炉灶。

### 8.1 两套题库根

```js
// core/paths.js（新增，不改 resolveLearningRoot / bankDir 的语义）
localBankDir(env, override?) -> string
//   env.ALGO_PLAN_LOCAL_BANK 有值就用它（相对路径按 cwd 解析）；
//   没有值就用工程仓内置的 <app>/bank。
```

```js
// core/bank/provider.js（构造函数放宽，list/get/put 语义不变）
new FileProvider(bankDir | string[] | null)
//   给数组时按数组顺序建索引：同一个 id 出现在多个根里，**先出现的赢**，
//   并往 index.warnings 里记一笔重复 id。
//   读取（get/list）看到的是合并后的去重结果；
//   写入（put）永远落在**第一个根**（人审库优先）。
```

`server/app.js` 的装配顺序固定为：

```js
const bankRoots = []
if (learning.ok) bankRoots.push(path.join(learning.root, "bank"))   // 1. 人审题库
if (options.localBank !== null) bankRoots.push(localBankDir(env, options.localBank))  // 2. 工程仓内置
const provider = new FileProvider(bankRoots)
```

- `options.localBank === null` 表示**显式关掉内置题库**（测试隔离用）。
- 工程仓内置题库住在 `apps/algo-plan/bank/`，**不能放 `data/`**——
  `projects/.gitignore` 有 `data/` 规则，放那儿进不了 git。

### 8.2 Codeforces 题源

- 题目来源：Codeforces（`source: codeforces`），题号带字母（如 `cf-33-b`）。
- **测试数据不公开**，所以用例**只提取题面里的样例**（官方给的输入输出）。
- 题面结构：中文题意（人工整理）→ 英文原题面 → 输入输出 → 限制 → 样例 → 「题目信息」。
- 每题带 `url`（去原题）与 `search_url`（源站搜索）两个字段。

### 8.3 新增工具

| 工具 | 作用 |
|---|---|
| `tools/import-codeforces.js` | 抓 CF 题面 → 写到**工程仓** `bank/<track>/`。CLI：`--dry-run` / `--rewrite` / `--bank <dir>` |
| `tools/sync-links.js` | 给存量题回填 `url` / `search_url` |
| `tools/fetch-cf-pages.js` | Chrome DevTools Protocol 抓 CF 题面页（网页版挂在 Cloudflare 后面，`/api/*` 放行） |

导入器**绝不**碰 learning 仓的 git（同 G19/G20 精神）：只写文件，不 commit、不 push。

### 8.4 接口字段增量

在 §0 的既有接口上**加字段**，不改旧字段：

| 接口 | 新增字段 |
|---|---|
| `GET /api/health` | `bank.roots: string[]`（当前生效的题库根，按优先级） |
| `GET /api/problem/:id` | `sourceId: string`、`url: string`、`searchUrl: string` |

`GET /api/bank` 的摘要项（`toSummary`）也带上 `url` / `searchUrl`，
前端据此给出「去原题」/「去源站搜索」——两个都没有就明说没有，不装死链。

---

## 9. M5 落地后的契约增量

M5 实现完成后，把 §4 的接口补成实际落地的形状（**加字段，不改旧字段**）。

### 9.1 `GET /api/insights`

查询参数：`?days=N`（默认 `30`，`0`＝全部不补 0，上限 `365`；非法值回退默认）。

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
    lastAt: "2026-11-10T09:00:00.000Z",
    expected: 5,
    expectedSource: "floor",     // "override" | "bank" | "floor"
    problems: 2,
  }],
  summary: {
    topicCount: 2,
    untouchedTopics: 1,
    weakCount: 1,
    strongCount: 1,
    avgMastery: 0.4061,
    avgCoverage: 0.3,
    totalAttempts: 4,
    totalProblems: 2,
    lastPracticeAt: "2026-11-10T09:00:00.000Z",
    minExpectedQuestions: 5,
    windowDays: 30,
    windowAttempts: 4,
  },
  series: [{ date: "2026-11-01", count: 0 }],
}
```

**排序契约**：`topics` 按处置优先级排——
「练过但总错（weak-dense）→ 薄弱且练得少（weak-sparse）→ 偶然会，没练透（strong-sparse）→ 掌握（strong-dense）」，
同一档内按掌握度**升序**（最该治的在前）。

**总数口径**：`summary.totalAttempts` / `totalProblems` **从原始流水算**，
不按知识点加总——一道题挂多个知识点时，按知识点加总会把同一次提交数两遍。

### 9.2 期望题量的 settings 键

| 键 | 作用 | 默认 |
|---|---|---|
| `insights.expected_min_questions` | 所有知识点的期望题量下限 | `5` |
| `insights.expected_override.<topic>` | 单个知识点的期望题量 | 无 |

合成规则：`期望题量 = max(题库题数, 下限常量)`；手工覆盖值优先级最高。

### 9.3 `topics` 表是物化视图

M5 每次调 `/api/insights` 都从 `attempts` 表**重新派生**，
再用 `store.replaceTopics(rows)` **整体覆盖** `topics` 表——幂等，
反复调接口不会把数字累加上去。M1 的 `upsertTopic`（累加写法）保留不动，
M3/M4 若还在用它写增量也不受影响：M5 每次都会用派生结果覆盖回去。

### 9.4 新增的 store 方法（只做加法）

| 方法 | 返回 |
|---|---|
| `store.listAttemptSummaries()` | `[{id, problem_id, ts, verdict}]`——**不带 `code` 列** |
| `store.countAttemptsByDay()` | `[{date, count}]`（`substr(ts,1,10)` 分组） |
| `store.replaceTopics(rows)` | `void`（先 `DELETE FROM topics` 再批量插入） |

### 9.5 路由文件约定

M5 的路由放在 `server/api-insights.js`（导出 `buildInsightRoutes(ctx)`），
在 `server/app.js` 里**合并**进 `server/api.js` 的同一张路由表。
**M5 完全不改 `server/api.js`**——M3 整体替换过它、M4 替换过整个 `buildRoutes`，
再来一次整体覆盖就会把 `POST /api/attempt` 和 M4 的五条接口一起删掉。

---

## 10. M6 落地后的契约增量

> 日期：2026-11-12
> M6 实现完成后，把 §5 补成实际落地的形状（**加字段，不改旧字段**）。

### 10.1 文件与导出

```
core/llm/prompts.js    提示词构造与响应解析（纯函数）
core/llm/client.js     ArkClient / AnthropicClient / NullClient
core/llm/guard.js      成本护栏（单次会话上限 + 每日上限）
core/llm/service.js    服务层：串起 client + guard + prompts
server/api-llm.js      M6 的七个路由
tools/llm-check.js     离线自检（只读、不联网）
web/llm.js             LLM 工作台（前端，**app.js 一个字没改**）
```

```js
// core/llm/prompts.js
buildPrompt(kind, context) -> {system, user}
  // kind ∈ KINDS = ["explain", "hint", "grade-idea", "generate", "fill"]
  // 纯函数：不联网、不读环境变量、不读文件、不取时间。
  // 同样的输入必须构造出同样的提示词（tools/llm-check.js 对五个 kind 做指纹自检）。
parseResponse(text, kind) -> {ok: true, ...} | {ok: false, reason: string}
EXPLAIN_LEVELS = ["思路", "代码"]
HINT_LEVELS    = ["方向", "思路", "伪码", "代码"]

// core/llm/client.js
createLlmClient({provider?, apiKey?, baseUrl?, model?, env?, fetchImpl?, enabled?}) -> client
  client.complete({system, user, temperature?}) -> Promise<string>
  client.name  -> "ark" | "anthropic" | "null"
  client.model -> string
  client.reason -> string   // 只在 null 客户端上有
keySourceOf(provider, env) -> string   // 只报变量名，**绝不回显密钥**

// core/llm/guard.js
checkAll(store, sessionId, date)   -> {ok, message, ...}   // 会话与每日两档一起查
consumeAll(store, sessionId, date) -> void                // 两档一起计数
limits(store) -> {sessionLimit, dailyLimit}
sessionKey(sessionId) -> "llm.quota.session.<id>"
dailyKey(date)         -> "llm.quota.daily.<YYYY-MM-DD>"
seedLimits(store, env) -> void   // 只在键不存在时写，不覆盖已有值
// checkQuota / consumeQuota 也导出，签名同 §5（单键版本）

// core/llm/service.js
createLlmService({client?, getClient?, store, provider, env?, now?}) -> service
  service.explain({problem, level?, sessionId?})    -> {text, model}
  service.hint({problem, level, sessionId?})        -> {text, model}
  service.gradeIdea({problem, idea, sessionId?})    -> {verdict, comment, model}
  service.generate({track, topics?, difficulty?, sessionId?}) -> {problem, model, file}
  service.fill({problem, sessionId?})               -> {problem, model, file}
  service.describe(sessionId?)                      -> 见 §10.3
readLlmSettings(store) -> {enabled, provider, model, baseUrl}
writeLlmSettings(store, patch) -> 同上   // **只认这四个字段，密钥永远不写**
```

### 10.2 五个场景接口的实际形状

`sessionId` 是**可选**的：成本护栏按「单次会话」计数要用；不传就落到 `default` 桶。

| 接口 | 入参 | 响应 |
|---|---|---|
| `POST /api/llm/explain` | `{problemId, level?, sessionId?}` | `{text, model}` |
| `POST /api/llm/hint` | `{problemId, level, sessionId?}` | `{text, model}` |
| `POST /api/llm/grade-idea` | `{problemId, idea, sessionId?}` | `{verdict, comment, model}` |
| `POST /api/bank/llm-generate` | `{track, topics[], difficulty?, sessionId?}` | `{problem, model}` |
| `POST /api/llm/fill` | `{problemId, sessionId?}` | `{problem, model}` |

- `explain` 的 `level` 缺省是 `思路`；`hint` 的 `level` 非法（不在四档里）回 **400**。
- `verdict` 归一成 `correct` / `partial` / `wrong` / `unknown` 四个值。
- `generate` 与 `fill` **真的落盘**：`generate` 新建 `learning/bank/<track>/<llm-题号>.md`（`source: llm`）；
  `fill` **只补缺的部分**——原来有的题面与用例一律保留，写回后 `needs_fill` 变成 `false`。
- **不主动泄题**：`explain` 与 `hint` 的提示词**根本不读** `problem.solution`，
  只有显式选「代码」档才允许给出完整代码。

### 10.3 LLM 设置接口

| 接口 | 响应 |
|---|---|
| `GET /api/llm/settings` | 见下方 |
| `PUT /api/llm/settings` | `{ok: true, settings: {enabled, provider, model, baseUrl}}` |

`GET /api/llm/settings` 的完整响应：

```js
{
  enabled: true,              // settings 表里的开关
  provider: "",               // settings 表里的 provider（空＝按密钥推断）
  model: "",                  // settings 表里的模型名（空＝用默认）
  baseUrl: "",                // settings 表里的地址（空＝用默认）
  effectiveProvider: "null",  // 实际生效的 provider："ark" | "anthropic" | "null"
  effectiveModel: "null",
  keySource: "环境变量 ARK_API_KEY",   // **只报变量名，绝不回显密钥**
  reason: "没有配置 provider，也没有找到 ARK_API_KEY 或 ANTHROPIC_API_KEY",
  tracks: ["interview", "fundamentals", "advanced", "engineering"],
  difficulties: ["easy", "medium", "hard"],
  quota: {sessionLimit: 20, dailyLimit: 100, usedSession: 0, usedDaily: 0},
}
```

- `tracks` 与 `difficulties` 直接透出 M1 冻结的 `TRACKS` / `DIFFICULTIES`，
  **前端不自己硬编码一份**（否则两边会漂）。
- `GET` 可带 `?sessionId=`，用于报当前会话已用次数。
- `PUT` **只接受这四个字段**：`enabled` / `provider` / `model` / `baseUrl`。
  传 `apiKey` / `key` / `token` 一律**忽略**——服务端根本没有写密钥的代码路径（G27）。

### 10.4 错误状态码

M6 的路由**不改 M1 的错误处理**，只在自己的文件里把业务错误转成 `HttpError`：

| 状态码 | 什么时候 | 例子 |
|---|---|---|
| 400 | 参数不对 | 「求助档位非法：神级」「这道题已经生成过了」 |
| 404 | 题号不存在 | `{error: "题目不存在", id}` |
| 429 | 成本护栏拦住了 | 「本次会话的 LLM 请求次数已用完…」「今天用完了：…」 |
| 503 | LLM 没开或没装配 | 「【LLM 未启用】…不受影响。」 |

> **关闭态的行为约定**（G23）：LLM 关着时，`explain` / `hint` **仍然回 200**，
> 正文是一句明确的中文提示；`gradeIdea` 回 200 且 `verdict: "unknown"`；
> `generate` / `fill` 回 **503**（不是 500），且**绝不改动题库文件**。
> 其余接口（题库、判题、复习、进度）完全不受影响。

### 10.5 settings 表里的键（M6 的全部落点）

**不新增数据表**（G30），M6 的东西全落在 M1 已有的 `settings` 表里：

| 键 | 作用 |
|---|---|
| `llm.enabled` / `llm.provider` / `llm.model` / `llm.base_url` | LLM 设置（**没有密钥键**） |
| `llm.quota.session_limit` / `llm.quota.daily_limit` | 两个上限，默认 20 / 100 |
| `llm.quota.session.<sessionId>` | 该会话已用次数 |
| `llm.quota.daily.<YYYY-MM-DD>` | 当天已用次数 |
| `llm.trace.<problemId>` | 该题的调用留痕（JSON 数组，每题最多 20 条） |

留痕的每一条：`{ts, kind, level, model, prompt: {digest, length, head}}`——
只存提示词的 **sha1 指纹 + 长度 + 开头 120 字**，不整段存（G25）。

### 10.6 密钥的来源约定（G27）

- 密钥**只从环境变量读**：`ARK_API_KEY`（火山方舟）或 `ANTHROPIC_API_KEY`。
- **绝不**写进 `settings` 表、**绝不**写进代码、**绝不**进 git、**绝不**出现在接口响应里。
- `server/main.js` 的 `loadDotEnv(file?)` 读 `apps/algo-plan/.env`；
  **已存在的环境变量优先，`.env` 不覆盖**。
- 上限也能从环境变量调：`ALGO_PLAN_LLM_SESSION_LIMIT` / `ALGO_PLAN_LLM_DAILY_LIMIT`。
- 总开关：`ALGO_PLAN_LLM_ENABLED`（`0` / `false` / `off` = 关）；
  provider：`ALGO_PLAN_LLM_PROVIDER`（`ark` / `anthropic` / `null`）；
  模型：`ALGO_PLAN_LLM_MODEL`；地址：`ALGO_PLAN_LLM_BASE_URL` / `ARK_BASE_URL`。

### 10.7 前端接线约定

- M6 的前端代码**全部在 `web/llm.js`**——`web/app.js` **一个字都没改**。
- 面板在 `DOMContentLoaded` 之后挂到 `main#view` 顶部，
  用 `MutationObserver` 盯着 `app.js` 的重渲染，掉了就重新挂。
- 页面上出现带 `data-problem-id` 的元素就自动认作「当前题」；认不出就用面板自带的题目下拉框。
- 求助四档**逐级解锁**，进度存 `sessionStorage`（键前缀 `algo-plan-llm-unlock-`），关掉浏览器就没了。
- 设置请求体由 `settingsRequestBody(patch)` 生成，**只保留四个白名单字段**。

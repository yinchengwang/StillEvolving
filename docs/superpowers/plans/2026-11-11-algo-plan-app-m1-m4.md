# 算法能力提升计划 App（M1–M4）实施计划【草稿】

> ⚠️ **这份文档是早期草稿，不要照着执行。**
>
> - **M1 已单独成文**：`2026-11-11-algo-plan-app-M1.md`。本文件的 **Task 1–4**（工程骨架 / Problem 解析 /
>   provider / SQLite）已被那份取代——M1 计划的代码是**实际跑过 `node tests/run-all.js`（8/8 套件通过）
>   验证过**的，本文件里的版本没有验证过。
> - **Task 5–9**（SM-2 / 掌握度 / 排程器 / 用例比对 / 判题执行器）对应 M2–M4 的内容，
>   仍然只是草稿，**尚未验证**。写 M2/M3/M4 的正式计划时，请以
>   `2026-11-11-algo-plan-app-M1.md` 末尾的「后续里程碑备忘」里的勘察结论为准
>   （尤其是 `python3` 在本机是 Store 别名、learning 的轮次文件没有 frontmatter 且列名逐个不同
>   这两条，它们直接推翻本文件 Task 5/9 的部分假设）。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个本机 Web 应用，把「练什么 → 判对错 → 该复习 → 进度写回 git」这条闭环跑通（M1–M4 主线），产出你愿意每天打开的版本。

**Architecture:** 单个 Node 进程（`node:http` + `node:sqlite` + `node:child_process`），零 npm 依赖、零构建。`core/` 是纯函数层（排程 / SM-2 / 掌握度 / 用例解析 / 同步），可脱离 IO 单测；`server/` 提供 REST API 与静态页；`judge/` 真实编译执行用户代码；`web/` 原生 JS 单页。数据双层：低频人读内容进 `learning` 仓（git），高频调度态进 SQLite，靠稳定题目 ID 互链。

**Tech Stack:** Node.js ≥ 24（内置 `node:sqlite` / `node:test` / `node:http`）、`g++ -std=c++17 -O2`（mingw64）、`python3`、原生 JS + WXSS 风格 CSS。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`

---

## Global Constraints

以下约束对**每一个** task 生效，写代码时不要违反：

| # | 约束 | 精确值 |
|---|---|---|
| G1 | **零 npm 依赖** | 只用 Node 内置模块（`node:http`/`node:sqlite`/`node:child_process`/`node:test`/`node:fs`/`node:path`/`node:os`）。不许 `npm install` 任何包 |
| G2 | **零构建** | 前端是原生 JS + HTML + CSS，浏览器直接跑。不用 webpack/vite/esbuild，不用 TypeScript 编译 |
| G3 | **Node 版本下限** | ≥ 24（`node:sqlite` 在 24 上是稳定 API）。低于 24 直接启动失败并打印明确错误 |
| G4 | **注释与提交信息用中文** | 沿用 `projects/CLAUDE.md`。代码注释中文，commit message 中文 |
| G5 | **提交即推送** | 每个 commit 完成后立刻 `git push origin main`（`projects/CLAUDE.md` 的「即时推送」纪律） |
| G6 | **产物路径** | 全部代码在 `projects/apps/algo-plan/`，**不要**在 `projects/` 根目录放新文件（违反根目录准入规则） |
| G7 | **learning 仓路径不硬编码** | 通过环境变量 `ALGO_PLAN_LEARNING_ROOT` 取得；未设置时降级为「纯本地模式」（只有 SQLite，无笔记同步）。不得出现 `../../learning` 这类相对路径假设 |
| G8 | **判题参数** | C++：`g++ -std=c++17 -O2`（**不加** `-Werror`，**不加** `-Wall`）；Python：`python3`；单用例超时默认 2000ms |
| G9 | **进程清理** | 超时后必须杀掉**整棵进程树**（Windows 用 `taskkill /T /F`，POSIX 用进程组 kill），不能留孤儿进程 |
| G10 | **不自动 commit** | app 写回 learning 仓后只返回 diff，**绝不**执行 `git commit`/`git push` |
| G11 | **写回前查脏** | 写回 learning 仓前必须 `git status --porcelain`，非空则拒绝写回并指出是哪个文件 |
| G12 | **稳定题目 ID** | 格式 `<前缀>-<5 位数字>`：`lc-`/`nc-`/`jz-`/`sl-`/`llm-`。它是 git 侧与 SQLite 侧的唯一连接键，任何地方都不得用标题或行号代替 |
| G13 | **测试入口** | `node tests/run-all.js` 跑全部套件。沿用 `apps/knowledge-hub/tests/run-all.js` 的「自动发现 `*.test.js`」模式 |
| G14 | **中文输出** | 面向用户的文案（verdict 说明、诊断结论、错误提示）全部中文 |

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── package.json                 仅 {name, private, type:"commonjs"}，无 dependencies
├── README.md                    怎么跑、目录说明、怎么接 learning 仓
├── core/                        纯函数层：可脱离 IO 单测
│   ├── bank/problem.js          Problem 模型、ID 生成、topic 归一化、字段校验
│   ├── bank/parse.js            markdown ↔ Problem 双向转换（含 frontmatter mini-YAML）
│   ├── bank/provider.js         Provider 接口 + FileProvider（读写 learning/bank）
│   ├── scheduler/next-action.js 候选动作优先级 + 每日配额 → 下一个动作
│   ├── review/sm2.js            SM-2（搬运 knowledge-hub/core/review.js）+ quality 映射
│   ├── mastery/mastery.js       掌握度模型 + 四档诊断
│   ├── judge-spec/cases.js      测试用例表格 → 结构化用例
│   ├── judge-spec/compare.js    输出比对（trim / 容差）
│   └── sync/sync.js             learning 仓 round 解析 / 勾选写回 / 错题订正写入
├── server/
│   ├── main.js                  启动入口 + 静态托管 + 路由挂载
│   ├── api.js                   全部 API handler
│   └── db.js                    node:sqlite schema + 仓储函数
├── judge/
│   ├── sandbox.js               临时目录、跑进程、超时杀进程树
│   └── runner.js                编排：写文件 → 编译 → 跑用例 → 比对 → verdict
├── web/
│   ├── index.html               单页外壳
│   ├── app.js                   前端逻辑（今日/作答/复习/轮次）
│   └── style.css
├── tools/
│   ├── legacy/                  从 projects/scripts/ 搬来的死代码，改造为数据源
│   │   ├── gen-practice-data.js
│   │   └── expand-practice.js
│   ├── import-catalog.js        死代码清单 → learning/bank 的 catalog 题
│   ├── import-solutions.js      learning 存量题解 → learning/bank 的 catalog 题
│   └── seed-bank.js             样板题 → learning/bank 的完整题
├── fixtures/
│   └── seed-bank/               5 道完整样板题（题面 + 用例 + 参考解法）
└── tests/
    ├── run-all.js
    └── *.test.js
```

**归属**：本计划只覆盖 spec §10 的 **M1–M4**（主线，产出可天天用的版本）。**M5（诊断页）与 M6（LLM 接入）另出计划**，不在本计划范围内——`core/mastery/mastery.js` 在本计划里只做到「能算、能测」，不做可视化。

---

## Task 1: 工程骨架与零依赖自检

**Files:**
- Create: `projects/apps/algo-plan/package.json`
- Create: `projects/apps/algo-plan/server/main.js`
- Create: `projects/apps/algo-plan/web/index.html`
- Create: `projects/apps/algo-plan/web/style.css`
- Create: `projects/apps/algo-plan/tests/run-all.js`
- Create: `projects/apps/algo-plan/tests/smoke.test.js`

**Interfaces:**
- Consumes: 无
- Produces:
  - `server/main.js` 导出 `createServer(opts) -> { server, listen(port): Promise<number>, close(): Promise<void> }`
  - `server/main.js` 导出 `ROOT`（本仓根目录绝对路径）
  - `tests/run-all.js` 命令行入口：自动发现 `tests/*.test.js`，逐个 `execFileSync(process.execPath, ...)`，全部通过 exit 0，任意失败 exit 1

- [ ] **Step 1: 写失败的冒烟测试**

Create `projects/apps/algo-plan/tests/smoke.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")
const { createServer, ROOT } = require("../server/main.js")

test("静态首页可访问且返回 200", async function () {
  const app = createServer()
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/")
    assert.strictEqual(res.status, 200)
    const body = await res.text()
    assert.ok(body.indexOf("算法能力计划") !== -1, "首页应包含标题")
  } finally {
    await app.close()
  }
})

test("未知路径返回 404", async function () {
  const app = createServer()
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/nope")
    assert.strictEqual(res.status, 404)
  } finally {
    await app.close()
  }
})

test("ROOT 指向本仓根目录", function () {
  assert.ok(path.basename(ROOT) === "algo-plan")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/smoke.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../server/main.js'`

- [ ] **Step 3: 创建 package.json**

Create `projects/apps/algo-plan/package.json`：

```json
{
  "name": "algo-plan",
  "version": "0.1.0",
  "private": true,
  "description": "算法能力提升计划 App（本地 Web，零依赖零构建）",
  "type": "commonjs",
  "scripts": {
    "start": "node server/main.js",
    "test": "node tests/run-all.js"
  }
}
```

- [ ] **Step 4: 创建 server/main.js**

Create `projects/apps/algo-plan/server/main.js`：

```javascript
"use strict"
/**
 * main.js —— 服务启动入口 + 静态文件托管
 *
 * 零依赖：只用 node 内置模块。
 */

const http = require("node:http")
const fs = require("node:fs")
const path = require("node:path")

const ROOT = path.resolve(__dirname, "..")
const WEB_DIR = path.join(ROOT, "web")

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body)
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(text),
  })
  res.end(text)
}

/** 把 URL 路径安全地映射到 web/ 内的文件；越界一律拒绝 */
function resolveStatic(urlPath) {
  const clean = decodeURIComponent(urlPath.split("?")[0])
  const rel = clean === "/" ? "index.html" : clean.replace(/^\/+/, "")
  const abs = path.resolve(WEB_DIR, rel)
  if (abs !== WEB_DIR && !abs.startsWith(WEB_DIR + path.sep)) return null
  return abs
}

function createServer(opts) {
  const options = opts || {}
  const routes = options.routes || []

  const server = http.createServer(function (req, res) {
    const urlPath = (req.url || "/").split("?")[0]

    for (const route of routes) {
      if (route.method === req.method && route.pattern === urlPath) {
        route.handler(req, res)
        return
      }
    }

    if (urlPath.startsWith("/api/")) {
      sendJson(res, 404, { error: "接口不存在", path: urlPath })
      return
    }

    const file = resolveStatic(urlPath)
    if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" })
      res.end("404 找不到")
      return
    }
    const body = fs.readFileSync(file)
    res.writeHead(200, {
      "content-type": MIME[path.extname(file)] || "application/octet-stream",
      "content-length": body.length,
    })
    res.end(body)
  })

  return {
    server: server,
    listen: function (port) {
      return new Promise(function (resolve, reject) {
        server.once("error", reject)
        server.listen(port, "127.0.0.1", function () {
          resolve(server.address().port)
        })
      })
    },
    close: function () {
      return new Promise(function (resolve) {
        server.close(function () { resolve() })
      })
    },
  }
}

module.exports = { createServer, ROOT, sendJson, resolveStatic }

if (require.main === module) {
  if (Number(process.versions.node.split(".")[0]) < 24) {
    console.error("需要 Node >= 24（用到 node:sqlite），当前是 " + process.version)
    process.exit(1)
  }
  const app = createServer()
  const port = Number(process.env.PORT || 5173)
  app.listen(port).then(function (p) {
    console.log("算法能力计划 App 已启动：http://127.0.0.1:" + p)
  })
}
```

- [ ] **Step 5: 创建 web/index.html 与 web/style.css**

Create `projects/apps/algo-plan/web/index.html`：

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
  <main id="view">正在加载…</main>
  <script src="/app.js"></script>
</body>
</html>
```

Create `projects/apps/algo-plan/web/style.css`：

```css
:root {
  --bg: #14161a;
  --panel: #1d2026;
  --line: #2c3038;
  --fg: #e6e8ec;
  --muted: #9aa1ad;
  --accent: #5aa9ff;
  --ok: #4ec9a0;
  --bad: #e5675f;
  --warn: #e0b martial;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 15px/1.6 "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
}
.topbar {
  display: flex; align-items: center; gap: 24px;
  padding: 14px 24px; border-bottom: 1px solid var(--line); background: var(--panel);
}
.topbar h1 { font-size: 17px; margin: 0; font-weight: 600; }
nav button {
  background: none; border: none; color: var(--muted);
  font-size: 14px; padding: 4px 2px; margin-right: 16px; cursor: pointer;
}
nav button.active { color: var(--accent); border-bottom: 2px solid var(--accent); }
main { max-width: 1080px; margin: 0 auto; padding: 24px; }
.panel {
  background: var(--panel); border: 1px solid var(--line);
  border-radius: 10px; padding: 18px 20px; margin-bottom: 18px;
}
button.primary {
  background: var(--accent); color: #0b0d10; border: none;
  border-radius: 6px; padding: 8px 16px; font-size: 14px; cursor: pointer;
}
button.ghost {
  background: none; color: var(--muted); border: 1px solid var(--line);
  border-radius: 6px; padding: 8px 14px; font-size: 14px; cursor: pointer;
}
textarea, input, select {
  width: 100%; background: #111317; color: var(--fg);
  border: 1px solid var(--line); border-radius: 6px; padding: 10px;
  font-family: Consolas, "Cascadia Mono", monospace; font-size: 13px;
}
.verdict-pass { color: var(--ok); }
.verdict-bad { color: var(--bad); }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); }
```

- [ ] **Step 6: 创建 tests/run-all.js**

Create `projects/apps/algo-plan/tests/run-all.js`：

```javascript
"use strict"
/**
 * run-all.js —— 一键跑全部测试
 *
 * 用法：node tests/run-all.js
 * 自动发现 tests/*.test.js，无需手动登记。
 */

const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const ROOT = path.resolve(__dirname, "..")

const suites = []
fs.readdirSync(path.join(ROOT, "tests")).forEach(function (f) {
  if (/^.+\.test\.js$/.test(f)) suites.push(f)
})

let failed = 0
suites.forEach(function (file) {
  process.stdout.write("\n▶ " + file + "\n")
  try {
    const out = execFileSync(process.execPath, [path.join(ROOT, "tests", file)], {
      cwd: ROOT,
      encoding: "utf8",
    })
    const lines = out.trim().split("\n")
    console.log(lines.slice(-2).join("\n"))
  } catch (e) {
    failed += 1
    const out = ((e.stdout || "") + (e.stderr || "")).trim()
    console.log(out.split("\n").slice(-16).join("\n"))
  }
})

console.log("\n" + (suites.length - failed) + " / " + suites.length + " 套件通过")
process.exit(failed === 0 ? 0 : 1)
```

- [ ] **Step 7: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `1 / 1 套件通过`，退出码 0

- [ ] **Step 8: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 建立零依赖应用骨架与测试入口

- package.json 仅声明 name/private/type，无任何 dependencies
- server/main.js：node:http 静态托管 + 路由挂载点 + 路径越界防护
- web/：单页外壳与样式
- tests/run-all.js：自动发现 *.test.js 的测试入口
- 测试：首页 200 / 未知路径 404 / ROOT 指向本仓根"
git push origin main
```

---

## Task 2: Problem 模型与 markdown 解析

**Files:**
- Create: `projects/apps/algo-plan/core/bank/problem.js`
- Create: `projects/apps/algo-plan/core/bank/parse.js`
- Test: `projects/apps/algo-plan/tests/bank.test.js`

**Interfaces:**
- Consumes: 无
- Produces:
  - `core/bank/problem.js`：
    - `TRACKS: string[]` = `["interview","fundamentals","advanced","engineering"]`
    - `SOURCES: string[]` = `["leetcode","nowcoder","jz","self","llm"]`
    - `SOURCE_PREFIX: {leetcode:"lc", nowcoder:"nc", jz:"jz", self:"sl", llm:"llm"}`
    - `makeId(source, problemId) -> string` — `llm` 用 `llm-` + 内容哈希前 8 位，其余用 5 位零填充数字
    - `normalizeTopic(raw) -> string` — 去首尾空白、内部连续空白压成一个空格
    - `validateProblem(p) -> string[]` — 返回错误信息数组，空数组表示合法
  - `core/bank/parse.js`：
    - `parseProblem(markdown) -> {problem, warnings}` — 解析失败抛 `Error`
    - `serializeProblem(problem) -> string` — 生成规范 markdown（frontmatter + 题面/用例/参考解法三节）
    - `parseFrontmatter(text) -> object` — 导出以便单测
    - `serializeFrontmatter(obj) -> string`

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/bank.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const problem = require("../core/bank/problem.js")
const parse = require("../core/bank/parse.js")

test("makeId 给 leetcode 补零到 5 位", function () {
  assert.strictEqual(problem.makeId("leetcode", "1"), "lc-00001")
  assert.strictEqual(problem.makeId("leetcode", "1455"), "lc-01455")
  assert.strictEqual(problem.makeId("nowcoder", "12"), "nc-00012")
  assert.strictEqual(problem.makeId("jz", "26"), "jz-00026")
  assert.strictEqual(problem.makeId("self", "7"), "sl-00007")
})

test("makeId 对 llm 用内容哈希", function () {
  const a = problem.makeId("llm", "两数之和|1,2")
  const b = problem.makeId("llm", "两数之和|1,2")
  assert.strictEqual(a, b)
  assert.ok(/^llm-[0-9a-f]{8}$/.test(a), "llm id 应是 llm- 加 8 位十六进制：" + a)
})

test("normalizeTopic 压掉内部多余空白", function () {
  assert.strictEqual(problem.normalizeTopic("  动态  规划 "), "动态 规划")
})

test("validateProblem 报缺字段与非法枚举", function () {
  const errors = problem.validateProblem({
    id: "lc-00001",
    source: "leetcode",
    title: "两数之和",
    difficulty: "easy",
    topics: ["数组"],
    tracks: ["interview"],
    status: "todo",
  })
  assert.deepStrictEqual(errors, [])

  const bad = problem.validateProblem({
    id: "",
    source: "unknown",
    title: "",
    difficulty: "insane",
    topics: [],
    tracks: ["nope"],
    status: "todo",
  })
  assert.ok(bad.length >= 5, "应报出 5 处问题，实际：" + JSON.stringify(bad))
})

test("parseFrontmatter 解析标量 / 行内列表 / 块列表", function () {
  const fm = parse.parseFrontmatter(
    ["id: lc-00001", "title: 两数之和", "topics: [数组, 哈希表]", "links:", "  - a", "  - b"].join("\n")
  )
  assert.strictEqual(fm.id, "lc-00001")
  assert.strictEqual(fm.title, "两数之和")
  assert.deepStrictEqual(fm.topics, ["数组", "哈希表"])
  assert.deepStrictEqual(fm.links, ["a", "b"])
})

test("parseProblem 解析完整题目", function () {
  const md = [
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
    "给定两个整数数组，找出和为目标值的两个数。",
    "",
    "## 测试用例",
    "| input | expect |",
    "|---|---|",
    "| `[2,7,11,15]`, 9 | `[0,1]` |",
    "",
    "## 参考解法",
    "```cpp",
    "int main(){return 0;}",
    "```",
  ].join("\n")
  const r = parse.parseProblem(md)
  assert.strictEqual(r.problem.id, "lc-00001")
  assert.strictEqual(r.problem.title, "两数之和")
  assert.deepStrictEqual(r.problem.topics, ["数组", "哈希表"])
  assert.strictEqual(r.problem.statement.indexOf("给定两个整数数组") !== -1, true)
  assert.strictEqual(r.problem.cases.length, 1)
  assert.strictEqual(r.problem.cases[0].input, "[2,7,11,15]`, 9")
  assert.strictEqual(r.problem.reference.language, "cpp")
  assert.strictEqual(r.problem.reference.code, "int main(){return 0;}")
})

test("serializeProblem 后再 parse，字段等价（往返）", function () {
  const p = {
    id: "lc-00001",
    source: "leetcode",
    title: "两数之和",
    difficulty: "easy",
    topics: ["数组", "哈希表"],
    tracks: ["interview"],
    status: "todo",
    needs_fill: false,
    statement: "题面正文",
    cases: [{ input: "1 2", expect: "3", tol: null }],
    reference: { language: "cpp", code: "int main(){}" },
    created: "2026-11-11",
    updated: "2026-11-11",
  }
  const back = parse.parseProblem(parse.serializeProblem(p)).problem
  assert.strictEqual(back.id, p.id)
  assert.deepStrictEqual(back.topics, p.topics)
  assert.strictEqual(back.cases[0].input, "1 2")
  assert.strictEqual(back.cases[0].expect, "3")
  assert.strictEqual(back.reference.code, p.reference.code)
})

test("parseProblem 对缺 frontmatter 抛错", function () {
  assert.throws(function () { parse.parseProblem("## 题面\n没有 frontmatter") })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/bank.test.js
```

Expected: FAIL，`Cannot find module '../core/bank/problem.js'`

- [ ] **Step 3: 实现 core/bank/problem.js**

Create `projects/apps/algo-plan/core/bank/problem.js`：

```javascript
"use strict"
/**
 * problem.js —— 题目模型：ID 生成、topic 归一化、字段校验
 *
 * 纯函数模块，不依赖任何 IO。
 */

const crypto = require("node:crypto")

const TRACKS = ["interview", "fundamentals", "advanced", "engineering"]
const SOURCES = ["leetcode", "nowcoder", "jz", "self", "llm"]
const SOURCE_PREFIX = {
  leetcode: "lc",
  nowcoder: "nc",
  jz: "jz",
  self: "sl",
  llm: "llm",
}
const DIFFICULTIES = ["easy", "medium", "hard"]
const STATUSES = ["todo", "in-progress", "done"]

/**
 * 生成稳定题目 ID。
 * @param {string} source leetcode|nowcoder|jz|self|llm
 * @param {string} problemId 平台侧题号；llm 时传内容摘要
 * @returns {string}
 */
function makeId(source, problemId) {
  const prefix = SOURCE_PREFIX[source]
  if (!prefix) throw new Error("未知来源：" + source)
  const raw = String(problemId == null ? "" : problemId).trim()
  if (source === "llm") {
    const hash = crypto.createHash("sha256").update(raw).digest("hex").slice(0, 8)
    return "llm-" + hash
  }
  const num = raw.replace(/\D/g, "")
  if (!num) throw new Error("题号里没有数字：" + raw)
  return prefix + "-" + num.padStart(5, "0")
}

/**
 * 知识点标签归一化：去首尾空白、内部连续空白压成一个空格。
 * @param {string} raw
 * @returns {string}
 */
function normalizeTopic(raw) {
  return String(raw == null ? "" : raw).trim().replace(/\s+/g, " ")
}

/**
 * 校验题目字段。
 * @param {object} p
 * @returns {string[]} 错误信息数组，空数组表示合法
 */
function validateProblem(p) {
  const errors = []
  if (!p || typeof p !== "object") return ["题目不是对象"]
  if (!p.id) errors.push("缺少 id")
  if (SOURCES.indexOf(p.source) === -1) errors.push("source 非法：" + p.source)
  if (!p.title) errors.push("缺少 title")
  if (DIFFICULTIES.indexOf(p.difficulty) === -1) errors.push("difficulty 非法：" + p.difficulty)
  if (STATUSES.indexOf(p.status) === -1) errors.push("status 非法：" + p.status)
  if (!Array.isArray(p.topics) || p.topics.length === 0) errors.push("topics 为空")
  if (!Array.isArray(p.tracks) || p.tracks.length === 0) errors.push("tracks 为空")
  else {
    for (const t of p.tracks) {
      if (TRACKS.indexOf(t) === -1) errors.push("track 非法：" + t)
    }
  }
  return errors
}

module.exports = {
  TRACKS: TRACKS,
  SOURCES: SOURCES,
  SOURCE_PREFIX: SOURCE_PREFIX,
  DIFFICULTIES: DIFFICULTIES,
  STATUSES: STATUSES,
  makeId: makeId,
  normalizeTopic: normalizeTopic,
  validateProblem: validateProblem,
}
```

- [ ] **Step 4: 实现 core/bank/parse.js**

Create `projects/apps/algo-plan/core/bank/parse.js`：

```javascript
"use strict"
/**
 * parse.js —— 题目 markdown ↔ 结构化对象 双向转换
 *
 * frontmatter 只支持三种写法（本项目用不到更复杂的 YAML）：
 *   key: value            标量
 *   key: [a, b]           行内列表
 *   key:                  块列表（下面若干行 "  - item"）
 */

const { validateProblem, normalizeTopic } = require("./problem.js")

/**
 * 解析 frontmatter 片段。
 * @param {string} text frontmatter 内的行（不含 --- 分隔线）
 * @returns {object}
 */
function parseFrontmatter(text) {
  const lines = String(text || "").split(/\r?\n/)
  const out = {}
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if (!line.trim() || line.trim().startsWith("#")) { i += 1; continue }
    const m = /^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/.exec(line)
    if (!m) { i += 1; continue }
    const key = m[1]
    const value = m[2].trim()
    if (value === "") {
      // 块列表
      const items = []
      i += 1
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*-\s+/, "").trim())
        i += 1
      }
      out[key] = items
      continue
    }
    if (value.startsWith("[") && value.endsWith("]")) {
      const inner = value.slice(1, -1).trim()
      out[key] = inner === "" ? [] : inner.split(",").map(function (s) { return s.trim() })
    } else {
      out[key] = value
    }
    i += 1
  }
  return out
}

/**
 * 序列化 frontmatter。
 * @param {object} obj
 * @returns {string} 不含首尾 --- 的内容
 */
function serializeFrontmatter(obj) {
  const lines = []
  Object.keys(obj).forEach(function (key) {
    const value = obj[key]
    if (Array.isArray(value)) {
      lines.push(key + ": [" + value.join(", ") + "]")
    } else if (typeof value === "boolean") {
      lines.push(key + ": " + (value ? "true" : "false"))
    } else {
      lines.push(key + ": " + value)
    }
  })
  return lines.join("\n")
}

function splitSections(body) {
  const sections = {}
  const lines = body.split(/\r?\n/)
  let current = "_preamble"
  let buf = []
  for (const line of lines) {
    const m = /^##\s+(.+?)\s*$/.exec(line)
    if (m) {
      sections[current] = buf.join("\n").trim()
      current = m[1]
      buf = []
    } else {
      buf.push(line)
    }
  }
  sections[current] = buf.join("\n").trim()
  return sections
}

/** 解析测试用例 markdown 表格 → [{input, expect, tol}] */
function parseCases(tableText) {
  const rows = []
  const lines = String(tableText || "").split(/\r?\n/)
  for (const line of lines) {
    const t = line.trim()
    if (!t.startsWith("|")) continue
    const cells = t.slice(1, t.endsWith("|") ? -1 : undefined).split("|").map(function (s) { return s.trim() })
    if (cells.length < 2) continue
    if (/^-+$/.test(cells[0]) || /^:?-{2,}:?$/.test(cells[0])) continue
    if (cells[0] === "input" && cells[1] === "expect") continue
    const tolRaw = cells[2] || ""
    const tolMatch = /^tol\s*=\s*([0-9.eE+-]+)$/.exec(tolRaw)
    rows.push({
      input: cells[0],
      expect: cells[1],
      tol: tolMatch ? Number(tolMatch[1]) : null,
    })
  }
  return rows
}

/**
 * 解析题目 markdown。
 * @param {string} markdown
 * @returns {{problem: object, warnings: string[]}}
 */
function parseProblem(markdown) {
  const text = String(markdown || "").replace(/\r\n/g, "\n")
  const m = /^---\n([\s\S]*?)\n---\n?/.exec(text)
  if (!m) throw new Error("缺少 frontmatter")
  const fm = parseFrontmatter(m[1])
  const sections = splitSections(text.slice(m[0].length))

  const referenceText = sections["参考解法"] || ""
  const refMatch = /```(\w+)?\n([\s\S]*?)```/.exec(referenceText)

  const p = {
    id: fm.id || "",
    source: fm.source || "",
    title: fm.title || "",
    difficulty: fm.difficulty || "",
    topics: Array.isArray(fm.topics) ? fm.topics.map(normalizeTopic) : [],
    tracks: Array.isArray(fm.tracks) ? fm.tracks : [],
    status: fm.status || "todo",
    needs_fill: fm.needs_fill === true || fm.needs_fill === "true",
    statement: sections["题面"] || "",
    cases: parseCases(sections["测试用例"] || ""),
    reference: refMatch
      ? { language: refMatch[1] || "cpp", code: refMatch[2].trim() }
      : { language: "", code: "" },
    created: fm.created || "",
    updated: fm.updated || "",
  }
  return { problem: p, warnings: validateProblem(p) }
}

/**
 * 序列化为规范 markdown。
 * @param {object} p
 * @returns {string}
 */
function serializeProblem(p) {
  const fm = serializeFrontmatter({
    id: p.id,
    source: p.source,
    title: p.title,
    difficulty: p.difficulty,
    topics: p.topics,
    tracks: p.tracks,
    status: p.status,
    needs_fill: p.needs_fill === true,
    created: p.created,
    updated: p.updated,
  })
  const caseRows = (p.cases || []).map(function (c) {
    const tol = c.tol == null ? "" : " tol=" + c.tol
    return "| " + c.input + " | " + c.expect + " |" + tol + " |"
  })
  const parts = [
    "---",
    fm,
    "---",
    "",
    "## 题面",
    p.statement || "",
    "",
    "## 测试用例",
    "| input | expect |",
    "|---|---|",
  ].concat(caseRows)
  if (p.reference && p.reference.code) {
    parts.push("", "## 参考解法", "```" + (p.reference.language || "cpp"), p.reference.code, "```")
  }
  return parts.join("\n") + "\n"
}

module.exports = {
  parseFrontmatter: parseFrontmatter,
  serializeFrontmatter: serializeFrontmatter,
  parseCases: parseCases,
  parseProblem: parseProblem,
  serializeProblem: serializeProblem,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/bank.test.js
```

Expected: 全部 `# pass`（约 8 条）

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 题目模型与 markdown 双向解析

- core/bank/problem.js：稳定 ID 生成（llm 用内容哈希）、topic 归一化、字段校验
- core/bank/parse.js：frontmatter mini-YAML（标量/行内列表/块列表）、
  题面与测试用例分节解析、序列化后往返等价
- 测试 8 条：ID 规则、校验、frontmatter 三种写法、整题解析、往返、缺 frontmatter 报错"
git push origin main
```

---

## Task 3: 题库 provider 与 learning 仓同步

**Files:**
- Create: `projects/apps/algo-plan/core/bank/provider.js`
- Create: `projects/apps/algo-plan/core/sync/sync.js`
- Test: `projects/apps/algo-plan/tests/provider.test.js`
- Test: `projects/apps/algo-plan/tests/sync.test.js`

**Interfaces:**
- Consumes: `core/bank/parse.js` 的 `parseProblem` / `serializeProblem`
- Produces:
  - `core/bank/provider.js`：
    - `createFileProvider(bankRoot) -> Provider`
    - `Provider.list(filter) -> Promise<Problem[]>`，filter 支持 `{track, topic, status, source, needsFill}`
    - `Provider.get(id) -> Promise<Problem|undefined>`
    - `Provider.put(problem) -> Promise<void>`（自动建目录，写 `bankRoot/<track>/<id>.md`）
  - `core/sync/sync.js`：
    - `parseRounds(progressRoot) -> {rounds: Round[], warnings: string[]}`
    - `Round = {id, file, title, goal, status, items: RoundItem[]}`
    - `RoundItem = {raw, id, title, status, doneDate, commitSha}`
    - `updateRoundItem(progressRoot, roundId, itemId, {status, doneDate, commitSha}) -> {diff, warnings}` — 只改目标行，返回统一 diff 文本
    - `writeCorrection(learningRoot, problem, text) -> {file, diff}` — 写 `notes/practice/<id>-订正.md`
    - `assertCleanWorktree(repoRoot) -> {ok: boolean, dirtyFiles: string[]}` — 跑 `git status --porcelain`

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/provider.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { createFileProvider } = require("../core/bank/provider.js")

function tmpRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "algo-bank-"))
}

const SAMPLE = {
  id: "lc-00001",
  source: "leetcode",
  title: "两数之和",
  difficulty: "easy",
  topics: ["数组"],
  tracks: ["interview"],
  status: "todo",
  needs_fill: false,
  statement: "题面",
  cases: [{ input: "1", expect: "2", tol: null }],
  reference: { language: "cpp", code: "int main(){}" },
  created: "2026-11-11",
  updated: "2026-11-11",
}

test("put 后 get 能取回同一题", async function () {
  const root = tmpRoot()
  const p = createFileProvider(root)
  await p.put(SAMPLE)
  const got = await p.get("lc-00001")
  assert.ok(got)
  assert.strictEqual(got.title, "两数之和")
  assert.ok(fs.existsSync(path.join(root, "interview", "lc-00001.md")))
})

test("list 能按 track 与 topic 过滤", async function () {
  const root = tmpRoot()
  const p = createFileProvider(root)
  await p.put(SAMPLE)
  await p.put(Object.assign({}, SAMPLE, {
    id: "lc-00002", title: "三数之和", topics: ["双指针"], tracks: ["advanced"],
  }))
  assert.strictEqual((await p.list({})).length, 2)
  assert.strictEqual((await p.list({ track: "advanced" })).length, 1)
  assert.strictEqual((await p.list({ topic: "数组" })).length, 1)
})

test("list 对 needsFill 只返回 needs_fill 为真的题", async function () {
  const root = tmpRoot()
  const p = createFileProvider(root)
  await p.put(SAMPLE)
  await p.put(Object.assign({}, SAMPLE, { id: "lc-00003", needs_fill: true }))
  assert.strictEqual((await p.list({ needsFill: true })).length, 1)
})

test("put 覆盖写不产生重复文件", async function () {
  const root = tmpRoot()
  const p = createFileProvider(root)
  await p.put(SAMPLE)
  await p.put(Object.assign({}, SAMPLE, { status: "done" }))
  assert.strictEqual((await p.list({})).length, 1)
  const got = await p.get("lc-00001")
  assert.strictEqual(got.status, "done")
})
```

Create `projects/apps/algo-plan/tests/sync.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const sync = require("../core/sync/sync.js")

const ROUND_MD = [
  "# R38 Grokking 机器学习 — 学习进度",
  "",
  "## 基本信息",
  "",
  "| 字段 | 值 |",
  "|------|-----|",
  "| 开始时间 | 2026-07-12 |",
  "| 目标 | Grokking 机器学习系统 14 张卡片 |",
  "| 状态 | 进行中 |",
  "",
  "## 14 张卡片清单",
  "",
  "| 序号 | ID | 名称 | 语言 | 状态 | 完成时间 | commit SHA |",
  "|------|-----|------|------|------|----------|------------|",
  "| 1 | ml_fundamentals | 机器学习基础 | Python | done | 2026-07-12 | abc123 |",
  "| 2 | linear_regression | 线性回归 | Python | todo |  |  |",
  "",
].join("\n")

function tmpProgress() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-prog-"))
  fs.writeFileSync(path.join(root, "r38-progress.md"), ROUND_MD, "utf8")
  return root
}

test("parseRounds 解析出轮次与条目", function () {
  const r = sync.parseRounds(tmpProgress())
  assert.strictEqual(r.rounds.length, 1)
  const round = r.rounds[0]
  assert.strictEqual(round.id, "r38")
  assert.strictEqual(round.items.length, 2)
  assert.strictEqual(round.items[0].id, "ml_fundamentals")
  assert.strictEqual(round.items[0].status, "done")
  assert.strictEqual(round.items[1].status, "todo")
  assert.strictEqual(round.title, "Grokking 机器学习 — 学习进度")
})

test("parseRounds 对缺列容错，不抛错", function () {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-prog-"))
  fs.writeFileSync(path.join(root, "r99-progress.md"), [
    "# R99 残缺轮次", "", "| 序号 | ID | 名称 | 状态 |", "|---|---|---|---|", "| 1 | x1 | 某项 | todo |", "",
  ].join("\n"), "utf8")
  const r = sync.parseRounds(root)
  assert.strictEqual(r.rounds.length, 1)
  assert.strictEqual(r.rounds[0].items[0].id, "x1")
  assert.strictEqual(r.rounds[0].items[0].doneDate, "")
})

test("updateRoundItem 只改目标行，其余字节不变", function () {
  const root = tmpProgress()
  const before = fs.readFileSync(path.join(root, "r38-progress.md"), "utf8")
  const res = sync.updateRoundItem(root, "r38", "linear_regression", {
    status: "done", doneDate: "2026-11-11", commitSha: "deadbee",
  })
  const after = fs.readFileSync(path.join(root, "r38-progress.md"), "utf8")
  assert.ok(res.diff.indexOf("linear_regression") !== -1, "diff 应含目标行")
  assert.ok(after.indexOf("abc123") !== -1, "其它行应原样保留")
  assert.ok(after.indexOf("2026-11-11") !== -1, "应写入完成时间")
  assert.strictEqual(before.split("\n").length, after.split("\n").length, "行数不应变化")
})

test("updateRoundItem 对不存在的条目返回告警且不改文件", function () {
  const root = tmpProgress()
  const before = fs.readFileSync(path.join(root, "r38-progress.md"), "utf8")
  const res = sync.updateRoundItem(root, "r38", "not_exist", { status: "done" })
  assert.ok(res.warnings.length > 0)
  assert.strictEqual(fs.readFileSync(path.join(root, "r38-progress.md"), "utf8"), before)
})

test("writeCorrection 写入错题订正文件", function () {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-learn-"))
  const res = sync.writeCorrection(root, { id: "lc-00001", title: "两数之和" }, "我的错误：用了两层循环。")
  assert.ok(fs.existsSync(res.file))
  const text = fs.readFileSync(res.file, "utf8")
  assert.ok(text.indexOf("我的错误：用了两层循环。") !== -1)
  assert.ok(text.indexOf("lc-00001") !== -1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/provider.test.js
```

Expected: FAIL，`Cannot find module '../core/bank/provider.js'`

- [ ] **Step 3: 实现 core/bank/provider.js**

Create `projects/apps/algo-plan/core/bank/provider.js`：

```javascript
"use strict"
/**
 * provider.js —— 题库读写
 *
 * FileProvider：读写 <bankRoot>/<track>/<id>.md
 * 接口保留是为了将来换 engine/db 做检索层时不必改上层（本期不实现别的 provider）。
 */

const fs = require("node:fs")
const path = require("node:path")
const { parseProblem, serializeProblem } = require("./parse.js")

function walk(dir) {
  const out = []
  if (!fs.existsSync(dir)) return out
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push.apply(out, walk(abs))
    else if (entry.isFile() && entry.name.endsWith(".md")) out.push(abs)
  }
  return out
}

function matches(p, filter) {
  const f = filter || {}
  if (f.track && p.tracks.indexOf(f.track) === -1) return false
  if (f.topic && p.topics.indexOf(f.topic) === -1) return false
  if (f.status && p.status !== f.status) return false
  if (f.source && p.source !== f.source) return false
  if (f.needsFill === true && p.needs_fill !== true) return false
  if (f.needsFill === false && p.needs_fill === true) return false
  return true
}

/**
 * @param {string} bankRoot 题库根目录（通常是 <learning>/bank）
 */
function createFileProvider(bankRoot) {
  return {
    async list(filter) {
      const files = walk(bankRoot)
      const out = []
      for (const file of files) {
        let parsed
        try {
          parsed = parseProblem(fs.readFileSync(file, "utf8"))
        } catch (e) {
          continue // 坏文件跳过，不让整个题库挂掉
        }
        if (matches(parsed.problem, filter)) out.push(parsed.problem)
      }
      out.sort(function (a, b) { return a.id < b.id ? -1 : 1 })
      return out
    },

    async get(id) {
      const files = walk(bankRoot)
      for (const file of files) {
        if (path.basename(file) !== id + ".md") continue
        try {
          return parseProblem(fs.readFileSync(file, "utf8")).problem
        } catch (e) {
          return undefined
        }
      }
      return undefined
    },

    async put(problem) {
      const track = problem.tracks[0] || "interview"
      const dir = path.join(bankRoot, track)
      fs.mkdirSync(dir, { recursive: true })
      fs.writeFileSync(
        path.join(dir, problem.id + ".md"),
        serializeProblem(problem),
        "utf8"
      )
    },
  }
}

module.exports = { createFileProvider: createFileProvider }
```

- [ ] **Step 4: 实现 core/sync/sync.js**

Create `projects/apps/algo-plan/core/sync/sync.js`：

```javascript
"use strict"
/**
 * sync.js —— 与 learning 仓的同步：轮次解析 / 勾选写回 / 错题订正
 *
 * 规则：
 *  - 写回只改目标行，不重排整文件
 *  - 写回前必须查工作区是否干净（assertCleanWorktree）
 *  - 只返回 diff，绝不自动 commit
 */

const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

/** 从 markdown 表格行切出各单元格 */
function splitRow(line) {
  const t = line.trim()
  if (!t.startsWith("|")) return null
  const inner = t.slice(1, t.endsWith("|") ? -1 : undefined)
  return inner.split("|").map(function (s) { return s.trim() })
}

function isSeparator(cells) {
  return cells.length > 0 && cells.every(function (c) { return /^:?-{2,}:?$/.test(c) })
}

/**
 * 解析 progress 目录下的所有 rXX-progress.md。
 * @param {string} progressRoot
 * @returns {{rounds: object[], warnings: string[]}}
 */
function parseRounds(progressRoot) {
  const rounds = []
  const warnings = []
  if (!fs.existsSync(progressRoot)) return { rounds: rounds, warnings: warnings }

  const files = fs.readdirSync(progressRoot).filter(function (f) {
    return /-progress\.md$/.test(f)
  })

  for (const file of files) {
    const abs = path.join(progressRoot, file)
    const text = fs.readFileSync(abs, "utf8").replace(/\r\n/g, "\n")
    const lines = text.split("\n")
    const idMatch = /^(r\d+)/.exec(file)
    const id = idMatch ? idMatch[1] : file.replace(/-progress\.md$/, "")

    let title = ""
    const titleMatch = /^#\s+(.+)$/m.exec(text)
    if (titleMatch) title = titleMatch[1].trim()

    let goal = ""
    let status = ""
    for (const line of lines) {
      const cells = splitRow(line)
      if (!cells || cells.length < 2) continue
      if (cells[0] === "目标") goal = cells[1]
      if (cells[0] === "状态") status = cells[1]
    }

    // 找「卡片清单」表：表头含 ID 与 名称
    let headerIndex = -1
    for (let i = 0; i < lines.length; i += 1) {
      const cells = splitRow(lines[i])
      if (!cells) continue
      const hasId = cells.indexOf("ID") !== -1
      const hasName = cells.some(function (c) { return c === "名称" || c === "题目" })
      if (hasId && hasName) { headerIndex = i; break }
    }

    const items = []
    if (headerIndex === -1) {
      warnings.push(file + "：找不到含 ID 与名称的表格")
    } else {
      const header = splitRow(lines[headerIndex])
      const idx = {
        id: header.indexOf("ID"),
        title: header.indexOf("名称") !== -1 ? header.indexOf("名称") : header.indexOf("题目"),
        status: header.indexOf("状态"),
        doneDate: header.indexOf("完成时间"),
        commitSha: header.indexOf("commit SHA"),
      }
      for (let i = headerIndex + 1; i < lines.length; i += 1) {
        const cells = splitRow(lines[i])
        if (!cells || isSeparator(cells)) continue
        if (cells.length === 1 && cells[0] === "") continue
        const itemId = idx.id >= 0 ? (cells[idx.id] || "") : ""
        if (!itemId) continue
        items.push({
          raw: lines[i],
          id: itemId,
          title: idx.title >= 0 ? (cells[idx.title] || "") : "",
          status: idx.status >= 0 ? (cells[idx.status] || "todo") : "todo",
          doneDate: idx.doneDate >= 0 ? (cells[idx.doneDate] || "") : "",
          commitSha: idx.commitSha >= 0 ? (cells[idx.commitSha] || "") : "",
        })
      }
    }

    rounds.push({ id: id, file: file, title: title, goal: goal, status: status, items: items })
  }

  rounds.sort(function (a, b) { return a.id < b.id ? -1 : 1 })
  return { rounds: rounds, warnings: warnings }
}

/**
 * 写回某个条目的状态。返回 diff 与告警；文件不变时 diff 为空串。
 * @param {string} progressRoot
 * @param {string} roundId
 * @param {string} itemId
 * @param {{status?:string, doneDate?:string, commitSha?:string}} patch
 */
function updateRoundItem(progressRoot, roundId, itemId, patch) {
  const warnings = []
  const abs = path.join(progressRoot, roundId + "-progress.md")
  if (!fs.existsSync(abs)) {
    return { diff: "", warnings: ["找不到轮次文件：" + roundId] }
  }
  const before = fs.readFileSync(abs, "utf8").replace(/\r\n/g, "\n")
  const lines = before.split("\n")
  const parsed = parseRounds(progressRoot)
  const round = parsed.rounds.filter(function (r) { return r.id === roundId })[0]
  if (!round) return { diff: "", warnings: ["找不到轮次：" + roundId] }

  const headerLine = lines.filter(function (l) {
    const cells = splitRow(l)
    return cells && cells.indexOf("ID") !== -1 && cells.some(function (c) { return c === "名称" || c === "题目" })
  })[0]
  if (!headerLine) return { diff: "", warnings: ["轮次文件里找不到清单表头"] }
  const header = splitRow(headerLine)
  const idx = {
    id: header.indexOf("ID"),
    title: header.indexOf("名称") !== -1 ? header.indexOf("名称") : header.indexOf("题目"),
    status: header.indexOf("状态"),
    doneDate: header.indexOf("完成时间"),
    commitSha: header.indexOf("commit SHA"),
  }

  let changed = false
  for (let i = 0; i < lines.length; i += 1) {
    const cells = splitRow(lines[i])
    if (!cells || isSeparator(cells)) continue
    const cellId = idx.id >= 0 ? (cells[idx.id] || "") : ""
    if (cellId !== itemId) continue
    const next = cells.slice()
    if (patch.status != null && idx.status >= 0) next[idx.status] = patch.status
    if (patch.doneDate != null && idx.doneDate >= 0) next[idx.doneDate] = patch.doneDate
    if (patch.commitSha != null && idx.commitSha >= 0) next[idx.commitSha] = patch.commitSha
    const rebuilt = "| " + next.join(" | ") + " |"
    if (rebuilt !== lines[i]) { lines[i] = rebuilt; changed = true }
    break
  }

  if (!changed) {
    return { diff: "", warnings: ["条目 " + itemId + " 未找到或内容无变化"] }
  }
  const after = lines.join("\n")
  fs.writeFileSync(abs, after, "utf8")
  return { diff: diffText(before, after), warnings: warnings }
}

/** 生成最小 diff（逐行对比） */
function diffText(before, after) {
  const a = before.split("\n")
  const b = after.split("\n")
  const out = []
  const max = Math.max(a.length, b.length)
  for (let i = 0; i < max; i += 1) {
    if (a[i] === b[i]) continue
    if (a[i] !== undefined) out.push("- " + a[i])
    if (b[i] !== undefined) out.push("+ " + b[i])
  }
  return out.join("\n")
}

/**
 * 写错题订正。
 * @param {string} learningRoot learning 仓根目录
 * @param {{id:string,title:string}} problem
 * @param {string} text 订正正文
 */
function writeCorrection(learningRoot, problem, text) {
  const dir = path.join(learningRoot, "notes", "practice")
  fs.mkdirSync(dir, { recursive: true })
  const file = path.join(dir, problem.id + "-订正.md")
  const existed = fs.existsSync(file)
  const before = existed ? fs.readFileSync(file, "utf8") : ""
  const body = existed
    ? before.replace(/\n?$/, "\n") + "\n" + text + "\n"
    : [
        "---",
        "id: " + problem.id,
        "title: " + problem.title,
        "type: practice",
        "status: in-progress",
        "created: " + today(),
        "updated: " + today(),
        "---",
        "",
        "## 订正",
        "",
        text,
        "",
      ].join("\n")
  fs.writeFileSync(file, body, "utf8")
  return { file: file, diff: diffText(before, body) }
}

function today() {
  return new Date().toISOString().slice(0, 10)
}

/**
 * 检查 learning 仓工作区是否干净。
 * @param {string} repoRoot
 * @returns {{ok:boolean, dirtyFiles:string[]}}
 */
function assertCleanWorktree(repoRoot) {
  let out = ""
  try {
    out = execFileSync("git", ["-C", repoRoot, "status", "--porcelain"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    })
  } catch (e) {
    return { ok: false, dirtyFiles: ["<git status 执行失败>"] }
  }
  const dirtyFiles = out.split("\n").filter(function (l) { return l.trim() !== "" }).map(function (l) {
    return l.slice(3).trim()
  })
  return { ok: dirtyFiles.length === 0, dirtyFiles: dirtyFiles }
}

module.exports = {
  parseRounds: parseRounds,
  updateRoundItem: updateRoundItem,
  writeCorrection: writeCorrection,
  assertCleanWorktree: assertCleanWorktree,
  diffText: diffText,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `3 / 3 套件通过`（smoke / bank / provider / sync 中新增的 provider 与 sync）

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 题库 provider 与 learning 仓同步

- core/bank/provider.js：FileProvider 读写 <bank>/<track>/<id>.md，
  支持 track/topic/status/source/needsFill 过滤；坏文件跳过不拖垮整个题库
- core/sync/sync.js：轮次解析（按列名关键词匹配、缺列容错、坏行跳过并计告警）、
  勾选写回只改目标行、错题订正写入 notes/practice/、写回前查工作区是否干净
- 全程只返回 diff，绝不自动 commit"
git push origin main
```

---

## Task 4: SQLite 存储层

**Files:**
- Create: `projects/apps/algo-plan/server/db.js`
- Test: `projects/apps/algo-plan/tests/db.test.js`

**Interfaces:**
- Consumes: 无
- Produces: `server/db.js` 导出
  - `openDb(filePath) -> Database`（`:memory:` 可用于测试）
  - `insertAttempt(db, attempt) -> number`（返回新行 id）
  - `listAttempts(db, {problemId, since, until}) -> Attempt[]`
  - `upsertReviewCard(db, card) -> void`
  - `getReviewCard(db, problemId) -> Card|undefined`
  - `dueCards(db, nowIso) -> Card[]`
  - `countReviewsToday(db, nowIso) -> number`
  - `recordTopicResult(db, topic, {passedFirstTry, lapsed}) -> void`
  - `getTopicStats(db, topic) -> {topic, attempts, firstPass, lapses, lastAt}`
  - `listTopicStats(db) -> {topic, attempts, firstPass, lapses, lastAt}[]`
  - `setSetting(db, key, value) / getSetting(db, key, fallback) / listSettings(db)`

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/db.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const db = require("../server/db.js")

test("建表后插入并读回 attempt", function () {
  const d = db.openDb(":memory:")
  const id = db.insertAttempt(d, {
    problemId: "lc-00001", ts: "2026-11-11T10:00:00.000Z", language: "cpp",
    code: "int main(){}", verdict: "pass", passedCases: 2, totalCases: 2,
    durationMs: 120, mode: "solve",
  })
  assert.ok(id > 0)
  const rows = db.listAttempts(d, { problemId: "lc-00001" })
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].verdict, "pass")
  assert.strictEqual(rows[0].durationMs, 120)
})

test("按时间窗过滤 attempt", function () {
  const d = db.openDb(":memory:")
  db.insertAttempt(d, { problemId: "a", ts: "2026-11-10T01:00:00.000Z", language: "cpp", code: "", verdict: "pass", passedCases: 1, totalCases: 1, durationMs: 1, mode: "solve" })
  db.insertAttempt(d, { problemId: "a", ts: "2026-11-11T01:00:00.000Z", language: "cpp", code: "", verdict: "pass", passedCases: 1, totalCases: 1, durationMs: 1, mode: "solve" })
  assert.strictEqual(db.listAttempts(d, { since: "2026-11-11T00:00:00.000Z" }).length, 1)
})

test("复习卡 upsert 与到期查询", function () {
  const d = db.openDb(":memory:")
  db.upsertReviewCard(d, {
    problemId: "lc-00002", easiness: 2.5, intervalDays: 1, repetitions: 0,
    lastQuality: 4, lastAt: "2026-11-10T00:00:00.000Z",
    nextReviewAt: "2026-11-11T00:00:00.000Z", lapses: 0,
  })
  db.upsertReviewCard(d, {
    problemId: "lc-00002", easiness: 2.6, intervalDays: 6, repetitions: 1,
    lastQuality: 5, lastAt: "2026-11-11T00:00:00.000Z",
    nextReviewAt: "2026-11-17T00:00:00.000Z", lapses: 0,
  })
  assert.strictEqual(db.listAttempts(d, {}).length, 0)
  assert.strictEqual(db.dueCards(d, "2026-11-12T00:00:00.000Z").length, 0)
  assert.strictEqual(db.dueCards(d, "2026-11-11T00:00:00.000Z").length, 1)
  const card = db.getReviewCard(d, "lc-00002")
  assert.strictEqual(card.intervalDays, 6)
})

test("topic 统计累加", function () {
  const d = db.openDb(":memory:")
  db.recordTopicResult(d, "数组", { passedFirstTry: true, lapsed: false, at: "2026-11-11T00:00:00.000Z" })
  db.recordTopicResult(d, "数组", { passedFirstTry: false, lapsed: true, at: "2026-11-11T01:00:00.000Z" })
  const s = db.getTopicStats(d, "数组")
  assert.strictEqual(s.attempts, 2)
  assert.strictEqual(s.firstPass, 1)
  assert.strictEqual(s.lapses, 1)
})

test("设置项读写", function () {
  const d = db.openDb(":memory:")
  assert.strictEqual(db.getSetting(d, "x", "fallback"), "fallback")
  db.setSetting(d, "x", "1")
  assert.strictEqual(db.getSetting(d, "x", "fallback"), "1")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/db.test.js
```

Expected: FAIL，`Cannot find module '../server/db.js'`

- [ ] **Step 3: 实现 server/db.js**

Create `projects/apps/algo-plan/server/db.js`：

```javascript
"use strict"
/**
 * db.js —— SQLite 存储层（node:sqlite）
 *
 * 存的是「高频、机器调度」的数据：作答流水、SM-2 调度态、topic 统计、设置。
 * 「低频、人要看」的内容在 learning 仓（git），见 core/sync/sync.js。
 */

const { DatabaseSync } = require("node:sqlite")

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS attempts (
     id            INTEGER PRIMARY KEY,
     problem_id    TEXT NOT NULL,
     ts            TEXT NOT NULL,
     language      TEXT NOT NULL,
     code          TEXT NOT NULL,
     verdict       TEXT NOT NULL,
     passed_cases  INTEGER NOT NULL DEFAULT 0,
     total_cases   INTEGER NOT NULL DEFAULT 0,
     duration_ms   INTEGER NOT NULL DEFAULT 0,
     mode          TEXT NOT NULL DEFAULT 'solve'
   )`,
  `CREATE INDEX IF NOT EXISTS attempts_problem ON attempts(problem_id)`,
  `CREATE INDEX IF NOT EXISTS attempts_ts ON attempts(ts)`,
  `CREATE TABLE IF NOT EXISTS review_cards (
     problem_id     TEXT PRIMARY KEY,
     easiness       REAL NOT NULL DEFAULT 2.5,
     interval_days  INTEGER NOT NULL DEFAULT 1,
     repetitions    INTEGER NOT NULL DEFAULT 0,
     last_quality   INTEGER,
     last_at        TEXT,
     next_review_at TEXT NOT NULL,
     lapses         INTEGER NOT NULL DEFAULT 0
   )`,
  `CREATE INDEX IF NOT EXISTS review_cards_due ON review_cards(next_review_at)`,
  `CREATE TABLE IF NOT EXISTS topics (
     id         TEXT PRIMARY KEY,
     attempts   INTEGER NOT NULL DEFAULT 0,
     first_pass INTEGER NOT NULL DEFAULT 0,
     lapses     INTEGER NOT NULL DEFAULT 0,
     last_at    TEXT
   )`,
  `CREATE TABLE IF NOT EXISTS settings (
     key   TEXT PRIMARY KEY,
     value TEXT NOT NULL
   )`,
]

/**
 * 打开数据库并建表。
 * @param {string} filePath 路径或 ':memory:'
 */
function openDb(filePath) {
  const db = new DatabaseSync(filePath)
  for (const stmt of SCHEMA) db.exec(stmt)
  return db
}

function rowToAttempt(r) {
  return {
    id: r.id,
    problemId: r.problem_id,
    ts: r.ts,
    language: r.language,
    code: r.code,
    verdict: r.verdict,
    passedCases: r.passed_cases,
    totalCases: r.total_cases,
    durationMs: r.duration_ms,
    mode: r.mode,
  }
}

function insertAttempt(db, a) {
  const stmt = db.prepare(
    `INSERT INTO attempts (problem_id, ts, language, code, verdict, passed_cases, total_cases, duration_ms, mode)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  )
  const res = stmt.run(
    a.problemId, a.ts, a.language, a.code || "", a.verdict,
    a.passedCases || 0, a.totalCases || 0, a.durationMs || 0, a.mode || "solve"
  )
  return Number(res.lastInsertRowid)
}

function listAttempts(db, filter) {
  const f = filter || {}
  const where = []
  const params = []
  if (f.problemId) { where.push("problem_id = ?"); params.push(f.problemId) }
  if (f.since) { where.push("ts >= ?"); params.push(f.since) }
  if (f.until) { where.push("ts <= ?"); params.push(f.until) }
  const sql = "SELECT * FROM attempts" + (where.length ? " WHERE " + where.join(" AND ") : "") + " ORDER BY ts ASC"
  return db.prepare(sql).all.apply(null, params).map(rowToAttempt)
}

function upsertReviewCard(db, c) {
  db.prepare(
    `INSERT INTO review_cards (problem_id, easiness, interval_days, repetitions, last_quality, last_at, next_review_at, lapses)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(problem_id) DO UPDATE SET
       easiness = excluded.easiness,
       interval_days = excluded.interval_days,
       repetitions = excluded.repetitions,
       last_quality = excluded.last_quality,
       last_at = excluded.last_at,
       next_review_at = excluded.next_review_at,
       lapses = excluded.lapses`
  ).run(
    c.problemId, c.easiness, c.intervalDays, c.repetitions,
    c.lastQuality == null ? null : c.lastQuality,
    c.lastAt || null, c.nextReviewAt, c.lapses || 0
  )
}

function getReviewCard(db, problemId) {
  const row = db.prepare("SELECT * FROM review_cards WHERE problem_id = ?").get(problemId)
  if (!row) return undefined
  return {
    problemId: row.problem_id,
    easiness: row.easiness,
    intervalDays: row.interval_days,
    repetitions: row.repetitions,
    lastQuality: row.last_quality,
    lastAt: row.last_at,
    nextReviewAt: row.next_review_at,
    lapses: row.lapses,
  }
}

function dueCards(db, nowIso) {
  return db.prepare("SELECT * FROM review_cards WHERE next_review_at <= ? ORDER BY next_review_at ASC")
    .all(nowIso)
    .map(function (r) {
      return {
        problemId: r.problem_id,
        easiness: r.easiness,
        intervalDays: r.interval_days,
        repetitions: r.repetitions,
        lastQuality: r.last_quality,
        lastAt: r.last_at,
        nextReviewAt: r.next_review_at,
        lapses: r.lapses,
      }
    })
}

function countReviewsToday(db, nowIso) {
  const day = nowIso.slice(0, 10)
  const row = db.prepare("SELECT COUNT(*) AS n FROM attempts WHERE mode = 'review' AND substr(ts, 1, 10) = ?").get(day)
  return row ? Number(row.n) : 0
}

function recordTopicResult(db, topic, r) {
  const at = r.at || new Date().toISOString()
  db.prepare(
    `INSERT INTO topics (id, attempts, first_pass, lapses, last_at) VALUES (?, 1, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       attempts = topics.attempts + 1,
       first_pass = topics.first_pass + excluded.first_pass,
       lapses = topics.lapses + excluded.lapses,
       last_at = excluded.last_at`
  ).run(topic, r.passedFirstTry ? 1 : 0, r.lapsed ? 1 : 0, at)
}

function topicRowToStats(r) {
  return {
    topic: r.id,
    attempts: r.attempts,
    firstPass: r.first_pass,
    lapses: r.lapses,
    lastAt: r.last_at,
  }
}

function getTopicStats(db, topic) {
  const row = db.prepare("SELECT * FROM topics WHERE id = ?").get(topic)
  if (!row) return { topic: topic, attempts: 0, firstPass: 0, lapses: 0, lastAt: null }
  return topicRowToStats(row)
}

function listTopicStats(db) {
  return db.prepare("SELECT * FROM topics ORDER BY id ASC").all().map(topicRowToStats)
}

function setSetting(db, key, value) {
  db.prepare("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .run(key, String(value))
}

function getSetting(db, key, fallback) {
  const row = db.prepare("SELECT value FROM settings WHERE key = ?").get(key)
  return row ? row.value : fallback
}

function listSettings(db) {
  const out = {}
  db.prepare("SELECT key, value FROM settings").all().forEach(function (r) { out[r.key] = r.value })
  return out
}

module.exports = {
  openDb: openDb,
  insertAttempt: insertAttempt,
  listAttempts: listAttempts,
  upsertReviewCard: upsertReviewCard,
  getReviewCard: getReviewCard,
  dueCards: dueCards,
  countReviewsToday: countReviewsToday,
  recordTopicResult: recordTopicResult,
  getTopicStats: getTopicStats,
  listTopicStats: listTopicStats,
  setSetting: setSetting,
  getSetting: getSetting,
  listSettings: listSettings,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `4 / 4 套件通过`

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): SQLite 存储层

node:sqlite 建 attempts / review_cards / topics / settings 四张表，
提供作答流水读写、复习卡 upsert 与到期查询、topic 统计累加、设置项读写。
高频调度态只落库不进 git。"
git push origin main
```

---

## Task 5: SM-2 复习与 quality 映射

**Files:**
- Create: `projects/apps/algo-plan/core/review/sm2.js`
- Test: `projects/apps/algo-plan/tests/review.test.js`

**Interfaces:**
- Consumes: `server/db.js` 的 ReviewCard 形状 `{problemId, easiness, intervalDays, repetitions, lastQuality, lastAt, nextReviewAt, lapses}`
- Produces: `core/review/sm2.js` 导出
  - `DEFAULT_EASE = 2.5`
  - `grade(card, quality, nowIso) -> {easiness, intervalDays, repetitions, lastQuality, lastAt, nextReviewAt, lapses}` — `quality < 3` 时间隔重置为 1、repetitions 归零、lapses +1
  - `qualityFromOutcome({verdict, durationMs, medianMs, usedHint, usedReference}) -> number` — 0~5
  - `isDue(card, nowIso) -> boolean`
  - `sortByOverdue(cards, nowIso) -> Card[]` — 逾期久的在前

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/review.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const sm2 = require("../core/review/sm2.js")

function card(over) {
  return Object.assign({
    problemId: "lc-00001",
    easiness: 2.5,
    intervalDays: 1,
    repetitions: 0,
    lastQuality: null,
    lastAt: null,
    nextReviewAt: "2026-11-11T00:00:00.000Z",
    lapses: 0,
  }, over || {})
}

test("quality 5 时间隔按 easiness 增长", function () {
  const c = sm2.grade(card({ repetitions: 1, intervalDays: 6 }), 5, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(c.repetitions, 2)
  assert.ok(c.intervalDays > 6, "间隔应增长，实际 " + c.intervalDays)
  assert.strictEqual(c.lapses, 0)
})

test("quality 低于 3 时重置间隔并记一次失误", function () {
  const c = sm2.grade(card({ repetitions: 4, intervalDays: 20, lapses: 1 }), 2, "2026-11-11T00:00:00.000Z")
  assert.strictEqual(c.intervalDays, 1)
  assert.strictEqual(c.repetitions, 0)
  assert.strictEqual(c.lapses, 2)
})

test("easiness 有 1.3 下限", function () {
  let c = card({ easiness: 1.35 })
  for (let i = 0; i < 5; i += 1) c = sm2.grade(c, 0, "2026-11-11T00:00:00.000Z")
  assert.ok(c.easiness >= 1.3, "easiness 不应低于 1.3，实际 " + c.easiness)
})

test("qualityFromOutcome 覆盖六种表现", function () {
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "pass", durationMs: 100, medianMs: 500 }), 5)
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "pass", durationMs: 4000, medianMs: 500 }), 4)
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "pass", durationMs: 100, medianMs: 500, usedHint: true }), 3)
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "wrong_answer", durationMs: 100, medianMs: 500, retried: true }), 2)
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "wrong_answer", durationMs: 100, medianMs: 500 }), 1)
  assert.strictEqual(sm2.qualityFromOutcome({ verdict: "wrong_answer", durationMs: 100, medianMs: 500, usedReference: true }), 0)
})

test("isDue 与 sortByOverdue", function () {
  assert.strictEqual(sm2.isDue(card({ nextReviewAt: "2026-11-10T00:00:00.000Z" }), "2026-11-11T00:00:00.000Z"), true)
  assert.strictEqual(sm2.isDue(card({ nextReviewAt: "2026-11-12T00:00:00.000Z" }), "2026-11-11T00:00:00.000Z"), false)
  const sorted = sm2.sortByOverdue([
    card({ problemId: "b", nextReviewAt: "2026-11-10T00:00:00.000Z" }),
    card({ problemId: "a", nextReviewAt: "2026-11-01T00:00:00.000Z" }),
  ], "2026-11-11T00:00:00.000Z")
  assert.strictEqual(sorted[0].problemId, "a")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/review.test.js
```

Expected: FAIL，`Cannot find module '../core/review/sm2.js'`

- [ ] **Step 3: 实现 core/review/sm2.js**

Create `projects/apps/algo-plan/core/review/sm2.js`：

```javascript
"use strict"
/**
 * sm2.js —— SM-2 间隔重复（搬运自 apps/knowledge-hub/core/review.js，公式逐字保留）
 *
 * 与原版的差别：
 *  - 记录形状从 review record 换成 review_cards 表的形状（intervalDays / nextReviewAt）
 *  - quality < 3 时额外记 lapses（失误次数），供掌握度模型使用
 *  - 去掉 createReview（造卡由 server 层负责）
 *
 * 质量映射规则见 spec §4.2。
 */

const DEFAULT_EASE = 2.5

/**
 * 按本次回忆质量更新卡片。
 * @param {object} card
 * @param {number} quality 0-5
 * @param {string} nowIso
 */
function grade(card, quality, nowIso) {
  let easiness = card.easiness
  let intervalDays = card.intervalDays
  let repetitions = card.repetitions
  let lapses = card.lapses || 0

  easiness = Math.max(
    1.3,
    easiness + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
  )

  if (quality < 3) {
    repetitions = 0
    intervalDays = 1
    lapses += 1
  } else if (repetitions === 0) {
    intervalDays = 1
    repetitions += 1
  } else if (repetitions === 1) {
    intervalDays = 6
    repetitions += 1
  } else {
    intervalDays = Math.max(1, Math.round(intervalDays * easiness))
    repetitions += 1
  }

  const next = new Date(nowIso)
  next.setDate(next.getDate() + intervalDays)

  return {
    problemId: card.problemId,
    easiness: easiness,
    intervalDays: intervalDays,
    repetitions: repetitions,
    lastQuality: quality,
    lastAt: nowIso,
    nextReviewAt: next.toISOString(),
    lapses: lapses,
  }
}

/**
 * 由本次作答表现推导 SM-2 的 quality。
 * @param {{verdict:string, durationMs:number, medianMs:number,
 *          usedHint?:boolean, usedReference?:boolean, retried?:boolean}} outcome
 * @returns {number} 0-5
 */
function qualityFromOutcome(outcome) {
  const o = outcome || {}
  if (o.usedReference) return 0
  if (o.verdict === "pass") {
    if (o.usedHint) return 3
    if (o.medianMs && o.durationMs <= o.medianMs) return 5
    return 4
  }
  if (o.retried) return 2
  return 1
}

function isDue(card, nowIso) {
  return new Date(card.nextReviewAt).getTime() <= new Date(nowIso).getTime()
}

/** 按逾期时长倒序（逾期越久越靠前） */
function sortByOverdue(cards, nowIso) {
  const now = new Date(nowIso).getTime()
  return (cards || []).slice().sort(function (a, b) {
    return new Date(a.nextReviewAt).getTime() - new Date(b.nextReviewAt).getTime()
  })
}

module.exports = {
  DEFAULT_EASE: DEFAULT_EASE,
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

Expected: `5 / 5 套件通过`

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): SM-2 复习与 quality 映射

- core/review/sm2.js：公式逐字搬运自 knowledge-hub/core/review.js，
  换成 review_cards 表的记录形状，quality<3 时额外记 lapses
- qualityFromOutcome 把判题结果与用时映射到 0-5：
  抄答案 0 / 没改对 1 / 改对了 2 / 用了提示 3 / 慢但对 4 / 快且对 5"
git push origin main
```

---

## Task 6: 掌握度模型与诊断

**Files:**
- Create: `projects/apps/algo-plan/core/mastery/mastery.js`
- Test: `projects/apps/algo-plan/tests/mastery.test.js`

**Interfaces:**
- Consumes: `server/db.js` 的 `listTopicStats` 返回形状 `{topic, attempts, firstPass, lapses, lastAt}`
- Produces: `core/mastery/mastery.js` 导出
  - `masteryOf(stat, nowIso) -> number` — 0~1
  - `coverageOf(stat, expectedCount) -> number` — 0~1
  - `diagnose(mastery, coverage) -> "weak-sparse" | "weak-dense" | "strong-sparse" | "strong-dense"`
  - `diagnoseLabel(bucket) -> string` — 中文标签
  - `rankTopics(stats, nowIso, expectedCounts) -> {topic, mastery, coverage, bucket, label}[]` — 按 mastery 升序

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/mastery.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const m = require("../core/mastery/mastery.js")

test("从未练过的 topic 掌握度为 0", function () {
  assert.strictEqual(m.masteryOf({ attempts: 0, firstPass: 0, lapses: 0, lastAt: null }, "2026-11-11T00:00:00.000Z"), 0)
})

test("全一次通过的 topic 掌握度接近 1", function () {
  const s = m.masteryOf({ attempts: 4, firstPass: 4, lapses: 0, lastAt: "2026-11-11T00:00:00.000Z" }, "2026-11-11T00:00:00.000Z")
  assert.ok(s > 0.9, "实际 " + s)
})

test("遗忘因子随时间衰减（半衰期 14 天）", function () {
  const stat = { attempts: 4, firstPass: 4, lapses: 0, lastAt: "2026-10-11T00:00:00.000Z" }
  const fresh = m.masteryOf({ attempts: 4, firstPass: 4, lapses: 0, lastAt: "2026-11-11T00:00:00.000Z" }, "2026-11-11T00:00:00.000Z")
  const old = m.masteryOf(stat, "2026-11-11T00:00:00.000Z")
  assert.ok(old < fresh, "旧练习的掌握度应更低")
  assert.ok(old / fresh < 0.55, "30 天后应衰减到约一半，实际 " + (old / fresh))
})

test("失误会拉低掌握度", function () {
  const a = m.masteryOf({ attempts: 4, firstPass: 4, lapses: 0, lastAt: "2026-11-11T00:00:00.000Z" }, "2026-11-11T00:00:00.000Z")
  const b = m.masteryOf({ attempts: 4, firstPass: 4, lapses: 3, lastAt: "2026-11-11T00:00:00.000Z" }, "2026-11-11T00:00:00.000Z")
  assert.ok(b < a)
})

test("四档诊断判定", function () {
  assert.strictEqual(m.diagnose(0.2, 0.2), "weak-sparse")
  assert.strictEqual(m.diagnose(0.2, 0.8), "weak-dense")
  assert.strictEqual(m.diagnose(0.9, 0.2), "strong-sparse")
  assert.strictEqual(m.diagnose(0.9, 0.8), "strong-dense")
})

test("rankTopics 按掌握度升序", function () {
  const stats = [
    { topic: "强", attempts: 5, firstPass: 5, lapses: 0, lastAt: "2026-11-11T00:00:00.000Z" },
    { topic: "弱", attempts: 5, firstPass: 1, lapses: 3, lastAt: "2026-11-11T00:00:00.000Z" },
  ]
  const ranked = m.rankTopics(stats, "2026-11-11T00:00:00.000Z", { 强: 5, 弱: 5 })
  assert.strictEqual(ranked[0].topic, "弱")
  assert.strictEqual(ranked[0].label, "薄弱且练得少")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/mastery.test.js
```

Expected: FAIL，`Cannot find module '../core/mastery/mastery.js'`

- [ ] **Step 3: 实现 core/mastery/mastery.js**

Create `projects/apps/algo-plan/core/mastery/mastery.js`：

```javascript
"use strict"
/**
 * mastery.js —— 掌握度模型与四档诊断
 *
 * 公式见 spec §4.3：
 *   首次通过率 = firstPass / attempts        （反复重试通过不算掌握）
 *   遗忘因子   = 0.5 ^ (距上次练习天数 / 14)
 *   掌握度     = (0.7 × 首次通过率 + 0.3 × e^(-失误次数/2)) × 遗忘因子
 */

const HALF_LIFE_DAYS = 14
const MASTERY_THRESHOLD = 0.5
const COVERAGE_THRESHOLD = 0.5

/**
 * @param {{attempts:number, firstPass:number, lapses:number, lastAt:string|null}} stat
 * @param {string} nowIso
 * @returns {number} 0~1
 */
function masteryOf(stat, nowIso) {
  const s = stat || {}
  if (!s.attempts) return 0
  const firstPassRate = Math.min(1, s.firstPass / s.attempts)
  const lapseFactor = Math.exp(-(s.lapses || 0) / 2)
  const base = 0.7 * firstPassRate + 0.3 * lapseFactor

  let days = 0
  if (s.lastAt) {
    days = Math.max(0, (new Date(nowIso).getTime() - new Date(s.lastAt).getTime()) / 86400000)
  }
  const decay = Math.pow(0.5, days / HALF_LIFE_DAYS)
  return Math.max(0, Math.min(1, base * decay))
}

/**
 * 覆盖度：练过的题数 / 期望题数。
 * @param {{attempts:number}} stat
 * @param {number} expectedCount
 */
function coverageOf(stat, expectedCount) {
  const s = stat || {}
  const expected = expectedCount && expectedCount > 0 ? expectedCount : 1
  return Math.max(0, Math.min(1, s.attempts / expected))
}

/**
 * 四档诊断。
 * @param {number} mastery
 * @param {number} coverage
 */
function diagnose(mastery, coverage) {
  const strong = mastery >= MASTERY_THRESHOLD
  const dense = coverage >= COVERAGE_THRESHOLD
  if (!strong && !dense) return "weak-sparse"
  if (!strong && dense) return "weak-dense"
  if (strong && !dense) return "strong-sparse"
  return "strong-dense"
}

const LABELS = {
  "weak-sparse": "薄弱且练得少",
  "weak-dense": "练过但总错",
  "strong-sparse": "偶然会，没练透",
  "strong-dense": "掌握",
}

function diagnoseLabel(bucket) {
  return LABELS[bucket] || bucket
}

/**
 * 给 topic 排序（掌握度低的在前），供排程器挑题用。
 * @param {object[]} stats
 * @param {string} nowIso
 * @param {Object<string, number>} expectedCounts topic → 期望题数
 */
function rankTopics(stats, nowIso, expectedCounts) {
  const expected = expectedCounts || {}
  return (stats || []).map(function (s) {
    const mastery = masteryOf(s, nowIso)
    const coverage = coverageOf(s, expected[s.topic] || 0)
    const bucket = diagnose(mastery, coverage)
    return {
      topic: s.topic,
      mastery: mastery,
      coverage: coverage,
      bucket: bucket,
      label: diagnoseLabel(bucket),
      attempts: s.attempts,
      lastAt: s.lastAt,
    }
  }).sort(function (a, b) {
    if (a.mastery !== b.mastery) return a.mastery - b.mastery
    return a.topic < b.topic ? -1 : 1
  })
}

module.exports = {
  HALF_LIFE_DAYS: HALF_LIFE_DAYS,
  MASTERY_THRESHOLD: MASTERY_THRESHOLD,
  masteryOf: masteryOf,
  coverageOf: coverageOf,
  diagnose: diagnose,
  diagnoseLabel: diagnoseLabel,
  rankTopics: rankTopics,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `6 / 6 套件通过`

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 掌握度模型与四档诊断

- core/mastery/mastery.js：首次通过率 + 半衰期 14 天的遗忘因子 + 失误惩罚
- 四档诊断：薄弱且练得少 / 练过但总错 / 偶然会没练透 / 掌握，
  用于区分「题做得少」与「概念没懂」两种不同处方
- rankTopics 按掌握度升序，供排程器补短板"
git push origin main
```

---

## Task 7: 排程器「推下一题」

**Files:**
- Create: `projects/apps/algo-plan/core/scheduler/next-action.js`
- Test: `projects/apps/algo-plan/tests/scheduler.test.js`

**Interfaces:**
- Consumes: `core/review/sm2.js` 的 `sortByOverdue`、`core/mastery/mastery.js` 的 `rankTopics`
- Produces: `core/scheduler/next-action.js` 导出
  - `nextAction({now, dueCards, rounds, currentRoundId, topicRank, attemptsToday, quota, expectedMinutes}) -> Action | null`
  - `Action = {type:"review"|"round"|"explore", problemId, roundId, topic, reason, estimatedMinutes}`
  - `DEFAULT_QUOTA = {questions: 10, minutes: 20}`
  - `estimateMinutes(difficulty, attemptsForDifficulty) -> number` — 按该难度历史平均用时估，缺样本时用默认 15

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/scheduler.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const sched = require("../core/scheduler/next-action.js")

const NOW = "2026-11-11T10:00:00.000Z"

function roundWithItems(items) {
  return {
    id: "r38",
    file: "r38-progress.md",
    title: "R38",
    goal: "",
    status: "进行中",
    items: items.map(function (it, i) {
      return {
        raw: "| " + (i + 1) + " | " + it.id + " | 题 | todo |  |  |",
        id: it.id,
        title: "题",
        status: it.status || "todo",
        doneDate: "",
        commitSha: "",
      }
    }),
  }
}

test("有到期复习时优先给复习", function () {
  const a = sched.nextAction({
    now: NOW,
    dueCards: [{ problemId: "lc-00009", nextReviewAt: "2026-11-01T00:00:00.000Z" }],
    rounds: [roundWithItems([{ id: "lc-00001" }])],
    topicRank: [],
    attemptsToday: [],
    quota: { questions: 10, minutes: 20 },
  })
  assert.strictEqual(a.type, "review")
  assert.strictEqual(a.problemId, "lc-00009")
})

test("复习配额用尽后切到轮次推进", function () {
  const a = sched.nextAction({
    now: NOW,
    dueCards: [{ problemId: "lc-00009", nextReviewAt: "2026-11-01T00:00:00.000Z" }],
    rounds: [roundWithItems([{ id: "lc-00001" }])],
    topicRank: [],
    attemptsToday: Array.from({ length: 10 }, function (_, i) {
      return { problemId: "lc-" + i, ts: NOW, durationMs: 60000, mode: "review" }
    }),
    quota: { questions: 10, minutes: 20 },
  })
  assert.strictEqual(a.type, "round")
  assert.strictEqual(a.problemId, "lc-00001")
})

test("复习时间配额用尽也切走", function () {
  const a = sched.nextAction({
    now: NOW,
    dueCards: [{ problemId: "lc-00009", nextReviewAt: "2026-11-01T00:00:00.000Z" }],
    rounds: [roundWithItems([{ id: "lc-00001" }])],
    topicRank: [],
    attemptsToday: Array.from({ length: 3 }, function (_, i) {
      return { problemId: "lc-" + i, ts: NOW, durationMs: 8 * 60000, mode: "review" }
    }),
    quota: { questions: 10, minutes: 20 },
  })
  assert.strictEqual(a.type, "round")
})

test("轮次内优先挑掌握度最低的 topic", function () {
  const a = sched.nextAction({
    now: NOW,
    dueCards: [],
    rounds: [roundWithItems([{ id: "lc-00001" }, { id: "lc-00002" }])],
    topicRank: [
      { topic: "数组", mastery: 0.2 },
      { topic: "哈希表", mastery: 0.9 },
    ],
    topicOfProblem: { "lc-00001": "哈希表", "lc-00002": "数组" },
    attemptsToday: [],
    quota: { questions: 10, minutes: 20 },
  })
  assert.strictEqual(a.problemId, "lc-00002")
  assert.strictEqual(a.topic, "数组")
})

test("没有可做的轮次时返回 null", function () {
  const a = sched.nextAction({
    now: NOW,
    dueCards: [],
    rounds: [roundWithItems([{ id: "lc-00001", status: "done" }])],
    topicRank: [],
    attemptsToday: [],
    quota: { questions: 10, minutes: 20 },
  })
  assert.strictEqual(a, null)
})

test("estimateMinutes 用历史平均，无历史时给默认 15", function () {
  assert.strictEqual(sched.estimateMinutes("easy", []), 15)
  assert.strictEqual(sched.estimateMinutes("easy", [{ durationMs: 300000 }]), 5)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/scheduler.test.js
```

Expected: FAIL，`Cannot find module '../core/scheduler/next-action.js'`

- [ ] **Step 3: 实现 core/scheduler/next-action.js**

Create `projects/apps/algo-plan/core/scheduler/next-action.js`：

```javascript
"use strict"
/**
 * next-action.js —— 决定「下一个动作」
 *
 * 候选动作与优先级（见 spec §4.1）：
 *   1. 到期复习（受每日配额限制）
 *   2. 轮次推进（当前 active 轮次里未完成的题）
 *   3. 主动探索（本期不做，返回 null 交由上层引导）
 */

const { sortByOverdue } = require("../review/sm2.js")

const DEFAULT_QUOTA = { questions: 10, minutes: 20 }
const DEFAULT_ESTIMATE_MINUTES = 15

/**
 * 估算某题预计耗时（分钟）。
 * @param {string} difficulty
 * @param {Array<{durationMs:number}>} attempts 同难度的历史作答
 */
function estimateMinutes(difficulty, attempts) {
  const list = (attempts || []).filter(function (a) { return a && a.durationMs > 0 })
  if (!list.length) return DEFAULT_ESTIMATE_MINUTES
  const sum = list.reduce(function (s, a) { return s + a.durationMs }, 0)
  const avgMinutes = sum / list.length / 60000
  return Math.max(1, Math.round(avgMinutes))
}

/**
 * 今日已用的复习量。
 * @param {Array<{ts:string,durationMs:number,mode:string}>} attemptsToday
 */
function reviewUsageToday(attemptsToday, now) {
  const day = now.slice(0, 10)
  const rows = (attemptsToday || []).filter(function (a) {
    return a.mode === "review" && String(a.ts).slice(0, 10) === day
  })
  const minutes = rows.reduce(function (s, a) { return s + (a.durationMs || 0) }, 0) / 60000
  return { questions: rows.length, minutes: Math.round(minutes) }
}

/**
 * 选下一个动作。
 * @param {{now:string, dueCards:object[], rounds:object[], currentRoundId?:string,
 *          topicRank:object[], topicOfProblem?:Object<string,string>,
 *          attemptsToday:object[], quota?:object}} input
 * @returns {object|null}
 */
function nextAction(input) {
  const now = input.now
  const quota = input.quota || DEFAULT_QUOTA
  const used = reviewUsageToday(input.attemptsToday, now)

  const quotaLeft = used.questions < quota.questions && used.minutes < quota.minutes

  if (quotaLeft && input.dueCards && input.dueCards.length) {
    const card = sortByOverdue(input.dueCards, now)[0]
    return {
      type: "review",
      problemId: card.problemId,
      roundId: null,
      topic: null,
      reason: "到期复习（已逾期 " + Math.floor((new Date(now).getTime() - new Date(card.nextReviewAt).getTime()) / 86400000) + " 天）",
      estimatedMinutes: DEFAULT_ESTIMATE_MINUTES,
    }
  }

  const rounds = input.rounds || []
  const active = input.currentRoundId
    ? rounds.filter(function (r) { return r.id === input.currentRoundId })
    : rounds.slice().sort(function (a, b) { return a.id < b.id ? 1 : -1 }).slice(0, 1)
  const round = active[0]
  if (!round) return null

  const pending = round.items.filter(function (it) { return it.status !== "done" })
  if (!pending.length) return null

  const topicOf = input.topicOfProblem || {}
  const rank = input.topicRank || []
  const rankOf = {}
  rank.forEach(function (r, i) { rankOf[r.topic] = i })

  const sorted = pending.slice().sort(function (a, b) {
    const ra = rankOf[topicOf[a.id]] == null ? 999 : rankOf[topicOf[a.id]]
    const rb = rankOf[topicOf[b.id]] == null ? 999 : rankOf[topicOf[b.id]]
    if (ra !== rb) return ra - rb
    return a.id < b.id ? -1 : 1
  })

  const picked = sorted[0]
  const topic = topicOf[picked.id] || null
  return {
    type: "round",
    problemId: picked.id,
    roundId: round.id,
    topic: topic,
    reason: topic ? "当前轮次里「" + topic + "」最薄弱" : "当前轮次的下一题",
    estimatedMinutes: DEFAULT_ESTIMATE_MINUTES,
  }
}

module.exports = {
  DEFAULT_QUOTA: DEFAULT_QUOTA,
  DEFAULT_ESTIMATE_MINUTES: DEFAULT_ESTIMATE_MINUTES,
  nextAction: nextAction,
  estimateMinutes: estimateMinutes,
  reviewUsageToday: reviewUsageToday,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `7 / 7 套件通过`

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 排程器「推下一题」

- core/scheduler/next-action.js：复习优先（受每日题数/时长双配额约束），
  配额用尽切轮次推进；轮次内按掌握度升序补短板，同 topic 按题号保连续性
- 每次只给一个动作，并给出预计耗时
- 没有可做的轮次时返回 null，由上层引导"
git push origin main
```

---

## Task 8: 用例解析与输出比对

**Files:**
- Create: `projects/apps/algo-plan/core/judge-spec/cases.js`
- Create: `projects/apps/algo-plan/core/judge-spec/compare.js`
- Test: `projects/apps/algo-plan/tests/judge-spec.test.js`

**Interfaces:**
- Consumes: `core/bank/parse.js` 的 `parseCases`
- Produces:
  - `core/judge-spec/cases.js`：`parseCaseRows(rows) -> Case[]`、`Case = {input, expect, tol}`、`splitInput(input) -> string[]`（按换行切多行输入）
  - `core/judge-spec/compare.js`：`normalizeOutput(text) -> string`（去首尾空白、忽略末尾空行）、`compareOutput(actual, expected, tol) -> {ok, reason}`

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/judge-spec.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const cases = require("../core/judge-spec/cases.js")
const compare = require("../core/judge-spec/compare.js")

test("用例行解析出 input/expect/tol", function () {
  const list = cases.parseCaseRows([
    { input: "1 2", expect: "3", tol: null },
    { input: "2.0 4.0", expect: "6.0", tol: 1e-6 },
  ])
  assert.strictEqual(list.length, 2)
  assert.strictEqual(list[1].tol, 1e-6)
})

test("多行输入按换行切分", function () {
  const lines = cases.splitInput("3\n1 2 3")
  assert.deepStrictEqual(lines, ["3", "1 2 3"])
})

test("输出比对忽略首尾空白与末尾空行", function () {
  assert.strictEqual(compare.compareOutput("  3  \n\n", "3").ok, true)
  assert.strictEqual(compare.compareOutput("3\n", "3").ok, true)
  assert.strictEqual(compare.compareOutput("4", "3").ok, false)
})

test("容差比对接受误差内的数值", function () {
  const r = compare.compareOutput("3.0000001", "3.0", 1e-6)
  assert.strictEqual(r.ok, true)
  const r2 = compare.compareOutput("3.1", "3.0", 1e-6)
  assert.strictEqual(r2.ok, false)
})

test("多行输出逐行比对", function () {
  assert.strictEqual(compare.compareOutput("1\n2", "1\n2").ok, true)
  assert.strictEqual(compare.compareOutput("1\n3", "1\n2").ok, false)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/judge-spec.test.js
```

Expected: FAIL，`Cannot find module '../core/judge-spec/cases.js'`

- [ ] **Step 3: 实现 core/judge-spec/cases.js**

Create `projects/apps/algo-plan/core/judge-spec/cases.js`：

```javascript
"use strict"
/**
 * cases.js —— 测试用例的解析与输入切分
 */

/**
 * 规范化用例行。
 * @param {Array<{input:string, expect:string, tol:?number}>} rows
 */
function parseCaseRows(rows) {
  return (rows || []).map(function (r) {
    return {
      input: String(r.input == null ? "" : r.input),
      expect: String(r.expect == null ? "" : r.expect),
      tol: r.tol == null ? null : Number(r.tol),
    }
  })
}

/**
 * 按换行切分输入；单行输入返回单元素数组。
 * @param {string} input
 * @returns {string[]}
 */
function splitInput(input) {
  const text = String(input == null ? "" : input)
  if (text.indexOf("\n") === -1) return [text]
  return text.split("\n").map(function (l) { return l.replace(/\r$/, "") })
}

module.exports = { parseCaseRows: parseCaseRows, splitInput: splitInput }
```

- [ ] **Step 4: 实现 core/judge-spec/compare.js**

Create `projects/apps/algo-plan/core/judge-spec/compare.js`：

```javascript
"use strict"
/**
 * compare.js —— 输出比对
 *
 * 默认规则：去首尾空白后精确匹配，忽略末尾空行。
 * 给了容差时按「整段都是数字」才走数值比较，否则回退到精确匹配。
 */

/**
 * 归一化输出：去掉每行行尾空白、去掉末尾空行。
 * @param {string} text
 */
function normalizeOutput(text) {
  const lines = String(text == null ? "" : text).split("\n").map(function (l) {
    return l.replace(/\r$/, "").replace(/[ \t]+$/, "")
  })
  while (lines.length && lines[lines.length - 1] === "") lines.pop()
  return lines.join("\n").trim()
}

function looksNumeric(text) {
  return /^\s*[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?\s*$/.test(text)
}

/**
 * 比对实际输出与期望输出。
 * @param {string} actual
 * @param {string} expected
 * @param {?number} tol 数值容差；null 表示精确匹配
 * @returns {{ok:boolean, reason:string}}
 */
function compareOutput(actual, expected, tol) {
  const a = normalizeOutput(actual)
  const e = normalizeOutput(expected)
  if (a === e) return { ok: true, reason: "" }

  if (tol != null && looksNumeric(a) && looksNumeric(e)) {
    const diff = Math.abs(Number(a) - Number(e))
    if (diff <= tol) return { ok: true, reason: "" }
    return { ok: false, reason: "数值偏差 " + diff + " 超过容差 " + tol }
  }

  return { ok: false, reason: "输出不一致" }
}

module.exports = {
  normalizeOutput: normalizeOutput,
  compareOutput: compareOutput,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `8 / 8 套件通过`

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 用例解析与输出比对

- core/judge-spec/cases.js：用例行规范化、多行输入按换行切分
- core/judge-spec/compare.js：默认去首尾空白精确匹配、忽略末尾空行；
  给容差时走数值比较；多行输出逐行比对"
git push origin main
```

---

## Task 9: 判题执行器

**Files:**
- Create: `projects/apps/algo-plan/judge/sandbox.js`
- Create: `projects/apps/algo-plan/judge/runner.js`
- Test: `projects/apps/algo-plan/tests/judge.test.js`

**Interfaces:**
- Consumes: `core/judge-spec/compare.js` 的 `compareOutput`、`core/judge-spec/cases.js` 的 `splitInput`
- Produces:
  - `judge/sandbox.js`：`makeTempDir(prefix) -> string`、`runProcess(cmd, args, {cwd, input, timeoutMs}) -> {code, stdout, stderr, timedOut, durationMs}`（超时杀整棵进程树）、`removeTempDir(dir)`
  - `judge/runner.js`：`judge({problem, code, language, timeoutMs, workDir}) -> {verdict, passedCases, totalCases, details[], compileOutput, durationMs}`
    - verdict ∈ `pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error`
    - `details[]` 每项 `{index, ok, expected, actual, reason}`

- [ ] **Step 1: 写失败测试**

Create `projects/apps/algo-plan/tests/judge.test.js`：

```javascript
"use strict"
const test = require("node:test")
const assert = require("node:assert")
const { judge } = require("../judge/runner.js")

const PROBLEM = {
  id: "self-00001",
  title: "读入两个数输出它们的和",
  cases: [
    { input: "1 2", expect: "3", tol: null },
    { input: "10 20", expect: "30", tol: null },
  ],
}

test("C++ 正确解法判为 pass", function () {
  const code = [
    "#include <iostream>",
    "int main(){ long a,b; std::cin>>a>>b; std::cout<<a+b<<std::endl; return 0; }",
  ].join("\n")
  const r = judge({ problem: PROBLEM, code: code, language: "cpp", timeoutMs: 10000 })
  assert.strictEqual(r.verdict, "pass")
  assert.strictEqual(r.passedCases, 2)
  assert.strictEqual(r.totalCases, 2)
})

test("C++ 输出错误判为 wrong_answer 并指出第几个用例", function () {
  const code = [
    "#include <iostream>",
    "int main(){ long a,b; std::cin>>a>>b; std::cout<<a*b<<std::endl; return 0; }",
  ].join("\n")
  const r = judge({ problem: PROBLEM, code: code, language: "cpp", timeoutMs: 10000 })
  assert.strictEqual(r.verdict, "wrong_answer")
  assert.strictEqual(r.passedCases, 1)
  const bad = r.details.filter(function (d) { return !d.ok })[0]
  assert.strictEqual(bad.index, 2)
  assert.strictEqual(bad.expected, "3")
  assert.ok(String(bad.actual).indexOf("2") !== -1)
})

test("C++ 编译错误判为 compile_error 并带回编译器输出", function () {
  const r = judge({ problem: PROBLEM, code: "int main(){ syntax error }", language: "cpp", timeoutMs: 10000 })
  assert.strictEqual(r.verdict, "compile_error")
  assert.ok(String(r.compileOutput).length > 0, "应带回编译器原文")
})

test("Python 正确解法判为 pass", function () {
  const code = "a, b = map(int, input().split())\nprint(a + b)\n"
  const r = judge({ problem: PROBLEM, code: code, language: "python", timeoutMs: 10000 })
  assert.strictEqual(r.verdict, "pass")
})

test("Python 语法错误判为 runtime_error", function () {
  const r = judge({ problem: PROBLEM, code: "def broken(:\n", language: "python", timeoutMs: 10000 })
  assert.strict
# 算法能力提升计划 App —— M1 骨架实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M1 里程碑——一个能跑起来的本地 Web 应用骨架：服务起得来、SQLite schema 就位、题库 markdown 能解析、页面壳能看到真实数据。

**Architecture:** 单个 Node 进程（`node:http` + `node:sqlite`），零 npm 依赖、零构建。`core/` 是纯函数层（Problem 模型、markdown 解析、provider），可脱离 IO 单测；`server/` 是组合根 + 路由 + 存储；`web/` 是原生 JS 单页。数据双层照设计文档 §1.7：低频人读内容进 `learning` 仓（git），高频调度态进 SQLite，靠稳定题目 ID 互链。

**Tech Stack:** Node.js ≥ 24（内置 `node:sqlite` / `node:test` / `node:http`）、原生 JS + CSS、零 npm 依赖。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划只覆盖其中 §10 的 **M1**）

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）

---

## Global Constraints

以下约束对**每一个** task 生效，写代码时不要违反：

| # | 约束 | 精确值 |
|---|---|---|
| G1 | **零 npm 依赖** | 只用 Node 内置模块（`node:http`/`node:sqlite`/`node:fs`/`node:path`/`node:os`/`node:crypto`/`node:child_process`/`node:test`/`node:stream`）。不许 `npm install` 任何包 |
| G2 | **零构建** | 前端是原生 JS + HTML + CSS，浏览器直接跑。不用 webpack/vite/esbuild，不用 TypeScript |
| G3 | **Node 版本下限** | ≥ 24（`node:sqlite` 在 24 上可用）。低于 24 启动时打印明确错误并退出 1。本机实测 `v24.17.0` |
| G4 | **注释与提交信息用中文** | 沿用 `projects/CLAUDE.md` |
| G5 | **提交即推送** | 每个 commit 完成后立刻 `git push origin main`（`projects/CLAUDE.md` 的「即时推送」纪律） |
| G6 | **产物路径** | 全部代码在 `projects/apps/algo-plan/`。**不要**在 `projects/` 根目录放新文件（违反根目录准入白名单） |
| G7 | **learning 仓路径不硬编码** | 只认环境变量 `ALGO_PLAN_LEARNING_ROOT`。取不到就降级为「纯本地模式」（只有 SQLite，不与 learning 仓同步）。不得出现 `../../learning` 这类相对路径假设 |
| G8 | **稳定题目 ID** | 格式 `<前缀>-<5 位数字>`，前缀：`leetcode→lc` / `nowcoder→nc` / `jz→jz` / `self→self` / `llm→llm`。LLM 造题用 `llm-<10 位内容哈希>`。它是 git 侧与 SQLite 侧的唯一连接键，任何地方都不得用标题或行号代替 |
| G9 | **测试入口** | `node tests/run-all.js` 跑全部套件，自动发现 `tests/*.test.js`。沿用 `apps/knowledge-hub/tests/run-all.js` 的模式，但用 `node:test` 断言 |
| G10 | **中文输出** | 面向用户的文案（错误提示、界面文字）全部中文 |
| G11 | **不自动 commit** | app 写回 learning 仓后只返回 diff，**绝不**执行 `git commit`/`git push`（M4 才用到，M1 先立规矩） |
| G12 | **运行产物不入库** | SQLite 落在 `projects/apps/algo-plan/data/app.db`。`projects/.gitignore` 已忽略 `data/` 与 `*.db`，天然不入库 |
| G13 | **题库目录容错** | `learning/bank/` 目前**不存在**（新建目录）。provider 必须容忍目录缺失：list 返回空数组、get 返回 undefined，不许抛错 |
| G14 | **防作弊** | 单题接口默认只返回前 **2** 个样例用例 + 用例总数，不返回全部用例、不返回参考解法（设计文档 §7.2） |
| G15 | **SQL 类型** | `node:sqlite` 只接受 `null`/`number`/`bigint`/`string`/`Uint8Array`。布尔一律转 `0`/`1`，缺省值一律转 `null` |
| G16 | **node:sqlite 导入** | `const { DatabaseSync } = require("node:sqlite")`。本机 Node 24.17.0 无需任何 flag 即可用 |

---

## M1 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| **M1 骨架** | 服务起得来、SQLite schema、题库 md 解析、页面壳 | ✅ **本计划** |
| M2 题库 | 复活三个死脚本 + 存量题解导入 | ❌ 另出计划 |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | ❌ 另出计划 |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | ❌ 另出计划 |
| M5 诊断 | 掌握度模型 + 诊断页 | ❌ 另出计划 |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | ❌ 另出计划 |

**M1 做完的验收线：** `node server/main.js` 起得来，浏览器打开首页能看到题库里有几道题，
`node tests/run-all.js` 全绿。判题、复习、轮次、LLM 一概不碰。

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── package.json                 仅 {name,private,type,scripts}，无 dependencies
├── README.md                    怎么跑、目录说明、怎么接 learning 仓
├── core/                        纯函数层：可脱离 IO 单测
│   ├── paths.js                 learning 仓根路径解析（含纯本地降级）
│   └── bank/
│       ├── problem.js           Problem 模型、ID 生成、topic 归一化、字段校验
│       ├── parse.js             markdown ↔ Problem 双向转换（含 mini-YAML frontmatter）
│       └── provider.js          Provider 接口 + FileProvider（读写 learning/bank）
├── server/
│   ├── main.js                  命令行入口（Node 版本闸门 + 启动）
│   ├── app.js                   组合根：HTTP 服务 + 静态托管 + 装配 db/provider/api
│   ├── router.js                路径参数路由 + JSON body 解析
│   ├── api.js                   M1 的三个接口
│   └── db.js                    node:sqlite schema + 仓储函数
├── web/
│   ├── index.html               单页外壳
│   ├── app.js                   前端逻辑（M1 只渲染今日页骨架 + 题库概览）
│   └── style.css
├── tools/
│   └── seed-bank.js             把 fixtures/seed-bank/ 导入 learning 仓的 bank/
├── fixtures/
│   └── seed-bank/               2 道样板题（题面 + 用例 + 参考解法）
└── tests/
    ├── run-all.js               一键跑全部
    └── *.test.js                8 个套件
```

**归属**：本计划只改 `projects/` 子模块。`learning/` 子模块在本计划里**只被读取**
（Task 7 的种子导入会往 `learning/bank/` 写样板题，但那是一次性的人工动作，
由用户自己决定是否提交，app 与本计划都不碰 learning 的 git 历史）。

---

## Task 1: 工程骨架、静态托管与路由内核

**Files:**
- Create: `projects/apps/algo-plan/package.json`
- Create: `projects/apps/algo-plan/server/router.js`
- Create: `projects/apps/algo-plan/server/app.js`
- Create: `projects/apps/algo-plan/server/main.js`
- Create: `projects/apps/algo-plan/web/index.html`
- Create: `projects/apps/algo-plan/web/style.css`
- Create: `projects/apps/algo-plan/tests/run-all.js`
- Create: `projects/apps/algo-plan/tests/smoke.test.js`
- Create: `projects/apps/algo-plan/tests/router.test.js`
- Create: `projects/apps/algo-plan/tests/errors.test.js`
- Create: `projects/apps/algo-plan/tests/harness.test.js`

**Interfaces:**
- Consumes: 无
- Produces:
  - `server/router.js` 导出 `compile(pattern) -> (urlPath) => params|null`、`createRouter() -> {add, find}`、`readJsonBody(req) -> Promise<object>`、`HttpError`（带 `status` 字段）
  - `server/app.js` 导出 `createServer(opts) -> {server, listen(port), close()}`、`createApp(opts)`（Task 4/6 补齐）、`sendJson(res, status, body)`、`ROOT`、`WEB_DIR`
  - `server/app.js` 的 `createServer(opts)`：`opts.routes` 是 `[{method, pattern, handler}]`；handler 签名 `handler(req, res, params, query)`，`query` 是 `URLSearchParams`
  - `server/main.js` 导出 `main()`、`checkNodeVersion()`

> **Task 1 评审修复（2026-11-11）**：本 Task 的代码块已按 M1 Task 1 代码评审的意见修订，
> 重跑本计划请直接用下面的代码块（代码块与 `apps/algo-plan/` 下的实现逐字一致）。修订点：
>
> - `server/router.js`：`readJsonBody` 超限时**不再** `req.destroy()`——销毁 socket 会让 413 响应写不出去，
>   客户端只看到连接重置；改成暂停读取、把剩余 body 读干净丢弃，走正常的 413 响应路径；
>   解析结果不是 JSON 对象（数字/字符串/null/数组）时报 400。
> - `server/app.js`：只有 `HttpError` 自己的中文文案才透传给浏览器，其余异常统一回「服务端出错」
>   并在服务端 `console.error` 打完整堆栈；静态分支加 try/catch（读失败按错误类型分流 404/500）；
>   listen 成功后撤掉一次性的 error 监听器并装常驻的中文日志处理器；`/api` 前缀判定统一成 `isApiPath` helper。
> - `server/main.js`：`app.listen()` 补 `.catch`，启动失败打中文错误并 `process.exit(1)`。
> - `tests/run-all.js`：输出里保留 node:test 的断言计数；没有测试套件时报错退出，不再空跑静默通过。
> - 新增 `tests/errors.test.js` 与 `tests/harness.test.js`，覆盖上面这些错误路径。
>
> **Task 1 第二轮复审修复（2026-11-11）**：第一轮修复之后又冒出 4 个错误路径问题，本 Task 的代码块已再次修订：
>
> - `server/router.js`：删掉 `DRAIN_LIMIT_BYTES`（8MB）这个「读到就 `req.destroy()`」的兜底。
>   它和第一轮修掉的那个 `req.destroy()` 是同一个坑：客户端还在上传时销毁 socket，内核回 RST，
>   把已经写好的 413 响应冲掉，客户端只拿到 ECONNRESET（实测 10MB / 20MB 都复现）。
>   现在一路排空到 body 结束，正常走 413 响应路径；这个 destroy 对内存也毫无保护作用
>   （`chunks` 已经清空），只省带宽，而服务只监听 127.0.0.1。
> - `server/app.js`：`catch` 里的 `headersSent` 分支补上 `console.error`。
>   原来这个分支提前 `return`，把 500 兜底那条日志也跳过了，handler「先 `res.end()` 再 `throw`」
>   会彻底静默、零日志。
> - `server/main.js`：`catch` 按错误来源分支——`listen` 失败时端口被占用（`EADDRINUSE`）明确说「端口已被占用」，
>   权限不足（`EACCES`）单独提示；异常来自 `.then` 回调内部（比如读 `app.learning` 炸了）时不再误报
>   「无法监听端口」，而且不 `process.exit(1)`——那时服务已经监听成功，退出会把它杀掉。
> - `tests/run-all.js`：`process.exit()` 改成 `process.exitCode`，
>   免得 stderr 是异步管道时中文提示被截断；退出码照样非 0。
> - `tests/errors.test.js` 补 4 条断言：10MB 大 body 收到 413 + 中文 JSON、响应发出后的异常必须留日志、
>   端口被占用时文案点名「占用」、listen 成功后回调出错不再误报端口且不杀服务；
>   `tests/harness.test.js` 补 1 条：中文提示的尾部不能被截断。
- [ ] **Step 1: 写失败的冒烟测试**

Create `projects/apps/algo-plan/tests/smoke.test.js`：

```javascript
"use strict"
/**
 * smoke.test.js —— 服务起得来、静态页能开、越界被拒
 */

const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")

const { createServer } = require("../server/app.js")

test("静态首页可访问且返回 200", async function () {
  const app = createServer({ routes: [] })
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

test("未知静态路径返回 404", async function () {
  const app = createServer({ routes: [] })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/nope.html")
    assert.strictEqual(res.status, 404)
  } finally {
    await app.close()
  }
})

test("路径越界被拒绝（400）", async function () {
  const app = createServer({ routes: [] })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/%2e%2e%2fpackage.json")
    assert.strictEqual(res.status, 400)
  } finally {
    await app.close()
  }
})

test("未知 API 返回 404 JSON", async function () {
  const app = createServer({ routes: [] })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/nope")
    assert.strictEqual(res.status, 404)
    const body = await res.json()
    assert.strictEqual(body.error, "接口不存在")
  } finally {
    await app.close()
  }
})

test("路径对但方法不对返回 405", async function () {
  const app = createServer({
    routes: [{ method: "GET", pattern: "/api/ping", handler: function (req, res) { res.end("ok") } }],
  })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/ping", { method: "POST" })
    assert.strictEqual(res.status, 405)
  } finally {
    await app.close()
  }
})

test("静态资源根目录指向 web/", function () {
  const { WEB_DIR } = require("../server/app.js")
  assert.strictEqual(path.basename(WEB_DIR), "web")
})

test("静态资源带查询串仍能正常返回", async function () {
  const app = createServer({ routes: [] })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/style.css?v=1")
    assert.strictEqual(res.status, 200)
    assert.strictEqual(res.headers.get("content-type"), "text/css; charset=utf-8")
  } finally {
    await app.close()
  }
})
```

Create `projects/apps/algo-plan/tests/router.test.js`：

```javascript
"use strict"
/**
 * router.test.js —— 路径参数匹配、方法匹配、JSON body 解析
 */

const test = require("node:test")
const assert = require("node:assert")
const { Readable } = require("node:stream")

const { compile, createRouter, readJsonBody, MAX_BODY_BYTES } = require("../server/router.js")

/** 造一个假的 IncomingMessage */
function fakeReq(text) {
  return Readable.from(text === undefined ? [] : [Buffer.from(text, "utf8")])
}

test("compile 匹配静态路径", function () {
  const match = compile("/api/bank")
  assert.deepStrictEqual(match("/api/bank"), {})
  assert.strictEqual(match("/api/bank/1"), null)
  assert.strictEqual(match("/api/banks"), null)
})

test("compile 提取路径参数", function () {
  const match = compile("/api/problem/:id")
  assert.deepStrictEqual(match("/api/problem/lc-00001"), { id: "lc-00001" })
  assert.strictEqual(match("/api/problem"), null)
  assert.strictEqual(match("/api/problem/"), null)
})

test("compile 支持多段路径参数", function () {
  const match = compile("/api/rounds/:id/items/:itemId")
  assert.deepStrictEqual(match("/api/rounds/r36/items/3"), { id: "r36", itemId: "3" })
})

test("compile 对非法百分号编码返回 null 而不是抛错", function () {
  const match = compile("/api/problem/:id")
  assert.strictEqual(match("/api/problem/%E4%"), null)
})

test("路由表：路径对方法不对返回 methodNotAllowed", function () {
  const router = createRouter()
  router.add("GET", "/api/bank", function () {})
  assert.strictEqual(router.find("GET", "/api/bank").route.pattern, "/api/bank")
  assert.strictEqual(router.find("POST", "/api/bank").methodNotAllowed, true)
  assert.strictEqual(router.find("GET", "/api/other"), null)
})

test("readJsonBody 解析 JSON", async function () {
  const body = await readJsonBody(fakeReq('{"a":1,"b":"x"}'))
  assert.deepStrictEqual(body, { a: 1, b: "x" })
})

test("readJsonBody 空 body 返回空对象", async function () {
  const body = await readJsonBody(fakeReq(""))
  assert.deepStrictEqual(body, {})
})

test("readJsonBody 非法 JSON 报 400", async function () {
  await assert.rejects(
    function () {
      return readJsonBody(fakeReq("not json"))
    },
    function (err) {
      return err.status === 400
    }
  )
})

test("readJsonBody 请求体超限报 413", async function () {
  const big = "x".repeat(MAX_BODY_BYTES + 1)
  await assert.rejects(
    function () {
      return readJsonBody(fakeReq(big))
    },
    function (err) {
      return err.status === 413
    }
  )
})

test("readJsonBody 解析结果不是对象时报 400", async function () {
  // 数字、字符串、null、数组都不是 JSON 对象；当成空对象会把
  // 「客户端 body 传错了」变成「服务端字段缺失」，所以直接报 400
  const notObjects = ["123", '"abc"', "null", "[1,2]"]
  for (const raw of notObjects) {
    await assert.rejects(
      function () {
        return readJsonBody(fakeReq(raw))
      },
      function (err) {
        return err.status === 400
      },
      "body 为 " + raw + " 时应报 400"
    )
  }
})
```

Create `projects/apps/algo-plan/tests/errors.test.js`：

```javascript
"use strict"
/**
 * errors.test.js —— 错误路径：请求体超限、异常兜底、状态码透传
 *
 * 这些都是「只有出错时才走」的分支，最容易因为没测而悄悄坏掉。
 */

const test = require("node:test")
const assert = require("node:assert")
const path = require("node:path")
const { spawn, spawnSync } = require("node:child_process")

const { createServer } = require("../server/app.js")
const { HttpError, MAX_BODY_BYTES, readJsonBody } = require("../server/router.js")

/**
 * 病态大 body 的字节数：10MB，远超旧实现里 8MB 的「中途断连」阈值。
 * 用它来钉住「大 body 也必须收到 413，而不是连接重置」这条契约。
 */
const HUGE_BODY_BYTES = 10 * 1024 * 1024

/** 起一个服务，跑一段逻辑，最后一定关掉 */
async function withServer(routes, fn) {
  const app = createServer({ routes: routes })
  const port = await app.listen(0)
  try {
    return await fn(port)
  } finally {
    await app.close()
  }
}

/** 临时接管 console.error，把服务端日志抓下来 */
function captureConsoleError() {
  const original = console.error
  const lines = []
  console.error = function () {
    const args = Array.prototype.slice.call(arguments)
    lines.push(
      args
        .map(function (arg) {
          return arg instanceof Error ? arg.stack : String(arg)
        })
        .join("\n")
    )
  }
  return {
    lines: lines,
    restore: function () {
      console.error = original
    },
  }
}

/** 等一会儿 */
function sleep(ms) {
  return new Promise(function (resolve) {
    setTimeout(resolve, ms)
  })
}

/** 轮询等待条件成立，最多等 5 秒；超时返回 null */
async function waitFor(fn) {
  const deadline = Date.now() + 5000
  while (Date.now() < deadline) {
    const value = fn()
    if (value) return value
    await sleep(50)
  }
  return null
}

test("请求体超过 1MB 时客户端收到 413 与中文 JSON", async function () {
  await withServer(
    [
      {
        method: "POST",
        pattern: "/api/echo",
        handler: async function (req, res) {
          await readJsonBody(req)
          res.end("ok")
        },
      },
    ],
    async function (port) {
      const big = "x".repeat(MAX_BODY_BYTES + 1024)
      const res = await fetch("http://127.0.0.1:" + port + "/api/echo", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: big,
        signal: AbortSignal.timeout(15000),
      })
      assert.strictEqual(res.status, 413)
      const body = await res.json()
      assert.strictEqual(body.error, "请求体过大（上限 1MB）")
    }
  )
})

test("超过 8MB 的大 body 也收到 413 与中文 JSON（不是连接重置）", async function () {
  await withServer(
    [
      {
        method: "POST",
        pattern: "/api/echo",
        handler: async function (req, res) {
          await readJsonBody(req)
          res.end("ok")
        },
      },
    ],
    async function (port) {
      const big = "x".repeat(HUGE_BODY_BYTES)
      const res = await fetch("http://127.0.0.1:" + port + "/api/echo", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: big,
        signal: AbortSignal.timeout(30000),
      })
      // 旧实现：读到 8MB 兜底阈值就 req.destroy()，内核回 RST 把 413 响应冲掉，
      // 客户端拿到的是 fetch failed / ECONNRESET，而不是 413
      assert.strictEqual(res.status, 413, "大 body 也必须回 413，不能是连接重置")
      const body = await res.json()
      assert.strictEqual(body.error, "请求体过大（上限 1MB）")
    }
  )
})

test("响应已经发出之后再抛的异常，服务端必须留下日志", async function () {
  const capture = captureConsoleError()
  try {
    await withServer(
      [
        {
          method: "GET",
          pattern: "/api/late",
          handler: function (req, res) {
            res.writeHead(200, { "content-type": "text/plain; charset=utf-8" })
            res.end("ok")
            // 响应已经落地才炸：状态码改不了了，但异常不能凭空消失
            throw new TypeError("响应发出之后才炸的异常")
          },
        },
      ],
      async function (port) {
        const res = await fetch("http://127.0.0.1:" + port + "/api/late")
        assert.strictEqual(res.status, 200)
        assert.strictEqual(await res.text(), "ok")
      }
    )
    assert.ok(capture.lines.length > 0, "响应发出之后的异常也必须留下日志，不能被静默吞掉")
    const text = capture.lines.join("\n")
    assert.ok(text.indexOf("TypeError") !== -1, "日志里应有异常类型，实际：\n" + text)
    assert.ok(text.indexOf("响应发出之后才炸的异常") !== -1, "日志里应有异常信息，实际：\n" + text)
    assert.ok(text.indexOf("at ") !== -1, "日志里应有调用堆栈，实际：\n" + text)
  } finally {
    capture.restore()
  }
})

test("handler 抛非 HttpError 时返回 500 中文文案", async function () {
  // 这里顺手把服务端日志接住，免得测试输出里混进一坨堆栈
  const capture = captureConsoleError()
  try {
    await withServer(
      [
        {
          method: "GET",
          pattern: "/api/boom",
          handler: function () {
            throw new TypeError("Cannot read properties of undefined (reading 'id')")
          },
        },
      ],
      async function (port) {
        const res = await fetch("http://127.0.0.1:" + port + "/api/boom")
        assert.strictEqual(res.status, 500)
        const body = await res.json()
        assert.strictEqual(body.error, "服务端出错")
        assert.strictEqual(body.error.indexOf("Cannot read"), -1, "不应把英文原始报错透给浏览器")
      }
    )
  } finally {
    capture.restore()
  }
})

test("handler 抛非 HttpError 时服务端留下完整堆栈日志", async function () {
  const capture = captureConsoleError()
  try {
    await withServer(
      [
        {
          method: "GET",
          pattern: "/api/boom",
          handler: function () {
            throw new TypeError("Cannot read properties of undefined (reading 'id')")
          },
        },
      ],
      async function (port) {
        const res = await fetch("http://127.0.0.1:" + port + "/api/boom")
        assert.strictEqual(res.status, 500)
      }
    )
    assert.ok(capture.lines.length > 0, "服务端应该打日志，不能把异常静默吞掉")
    const text = capture.lines.join("\n")
    assert.ok(text.indexOf("TypeError") !== -1, "日志里应有异常类型")
    assert.ok(text.indexOf("Cannot read properties") !== -1, "日志里应有异常信息")
    assert.ok(text.indexOf("at ") !== -1, "日志里应有调用堆栈")
  } finally {
    capture.restore()
  }
})

test("HttpError 的 status 透传到 HTTP 响应状态码", async function () {
  await withServer(
    [
      {
        method: "GET",
        pattern: "/api/missing",
        handler: function () {
          throw new HttpError(404, "题目不存在")
        },
      },
      {
        method: "GET",
        pattern: "/api/teapot",
        handler: function () {
          throw new HttpError(418, "我是茶壶")
        },
      },
    ],
    async function (port) {
      const res404 = await fetch("http://127.0.0.1:" + port + "/api/missing")
      assert.strictEqual(res404.status, 404)
      const body404 = await res404.json()
      assert.strictEqual(body404.error, "题目不存在")

      const res418 = await fetch("http://127.0.0.1:" + port + "/api/teapot")
      assert.strictEqual(res418.status, 418)
      const body418 = await res418.json()
      assert.strictEqual(body418.error, "我是茶壶")
    }
  )
})

test("handler 收到的 query 是 URLSearchParams 实例", async function () {
  let received = null
  await withServer(
    [
      {
        method: "GET",
        pattern: "/api/query",
        handler: function (req, res, params, query) {
          received = query
          res.end("ok")
        },
      },
    ],
    async function (port) {
      const res = await fetch("http://127.0.0.1:" + port + "/api/query?a=1&b=%E4%B8%AD")
      assert.strictEqual(res.status, 200)
      assert.ok(received instanceof URLSearchParams, "query 应该是 URLSearchParams 实例")
      assert.strictEqual(received.get("a"), "1")
      assert.strictEqual(received.get("b"), "中")
    }
  )
})

test("/api（不带尾斜杠）返回与 /api/nope 一致的 JSON 404", async function () {
  await withServer([], async function (port) {
    const res = await fetch("http://127.0.0.1:" + port + "/api")
    assert.strictEqual(res.status, 404)
    assert.strictEqual(res.headers.get("content-type"), "application/json; charset=utf-8")
    const body = await res.json()
    assert.strictEqual(body.error, "接口不存在")
  })
})

test("静态文件读失败时按错误类型分流（EPERM 走 500，服务不挂）", async function () {
  const fs = require("node:fs")
  const original = fs.readFileSync
  const capture = captureConsoleError()
  try {
    // 模拟 Windows 上文件被独占锁定：readFileSync 抛 EPERM
    fs.readFileSync = function (file) {
      if (String(file).indexOf("style.css") !== -1) {
        const err = new Error("EPERM: operation not permitted, open '" + file + "'")
        err.code = "EPERM"
        throw err
      }
      return original.apply(fs, arguments)
    }
    await withServer([], async function (port) {
      const res = await fetch("http://127.0.0.1:" + port + "/style.css")
      assert.strictEqual(res.status, 500)
      assert.ok((await res.text()).indexOf("500") !== -1)
      // 服务还活着：再请求一次首页
      const ok = await fetch("http://127.0.0.1:" + port + "/")
      assert.strictEqual(ok.status, 200)
    })
  } finally {
    fs.readFileSync = original
    capture.restore()
  }
})

test("listen 成功后运行期错误只记日志，不会变成未捕获异常", async function () {
  const capture = captureConsoleError()
  try {
    const app = createServer({ routes: [] })
    const port = await app.listen(0)
    try {
      // 旧实现：第一次 error 被已 settle 的 reject 吞掉（无日志），
      // 第二次 error 就没监听器了 → 未捕获异常，整个进程挂掉
      app.server.emit("error", new Error("模拟第一次错误"))
      app.server.emit("error", new Error("模拟第二次错误"))
      assert.strictEqual(capture.lines.length, 2, "两次运行期错误都应该留下中文日志")
      assert.ok(capture.lines.join("\n").indexOf("服务运行期错误") !== -1)
    } finally {
      await app.close()
    }
  } finally {
    capture.restore()
  }
})

test("main.js 启动失败时打印中文错误并以退出码 1 退出", function () {
  // createApp 要到 Task 6 才落地，这里把 app.js 的导出换成假的 listen，
  // 用子进程跑 main()，验证端口被占用这类失败不会变成未捕获 rejection
  const appPath = path.join(__dirname, "..", "server", "app.js")
  const mainPath = path.join(__dirname, "..", "server", "main.js")
  const script = [
    "const appModule = require(" + JSON.stringify(appPath) + ")",
    "appModule.createApp = function () {",
    "  return {",
    "    learning: { ok: false, reason: '测试' },",
    "    listen: function () {",
    "      const err = new Error('listen EADDRINUSE 127.0.0.1:5173')",
    "      err.code = 'EADDRINUSE'",
    "      return Promise.reject(err)",
    "    },",
    "  }",
    "}",
    "require(" + JSON.stringify(mainPath) + ").main()",
  ].join("\n")
  const res = spawnSync(process.execPath, ["-e", script], { encoding: "utf8" })
  assert.strictEqual(res.status, 1, "启动失败时应以退出码 1 退出，实际输出：\n" + res.stderr)
  assert.ok(
    (res.stderr || "").indexOf("启动失败") !== -1,
    "应该打印中文提示，实际输出：\n" + res.stderr
  )
  assert.ok(
    (res.stderr || "").indexOf("EADDRINUSE") !== -1,
    "应该带上错误码，实际输出：\n" + res.stderr
  )
})

test("端口被占用时明确告诉用户是端口占用", function () {
  const appPath = path.join(__dirname, "..", "server", "app.js")
  const mainPath = path.join(__dirname, "..", "server", "main.js")
  const script = [
    "const appModule = require(" + JSON.stringify(appPath) + ")",
    "appModule.createApp = function () {",
    "  return {",
    "    learning: { ok: false, reason: '测试' },",
    "    listen: function () {",
    "      const err = new Error('listen EADDRINUSE 127.0.0.1:5173')",
    "      err.code = 'EADDRINUSE'",
    "      return Promise.reject(err)",
    "    },",
    "  }",
    "}",
    "require(" + JSON.stringify(mainPath) + ").main()",
  ].join("\n")
  const res = spawnSync(process.execPath, ["-e", script], { encoding: "utf8" })
  const stderr = res.stderr || ""
  assert.strictEqual(res.status, 1, "端口被占用时应以退出码 1 退出，实际输出：\n" + stderr)
  assert.ok(
    stderr.indexOf("端口") !== -1 && stderr.indexOf("占用") !== -1,
    "端口被占用时必须明确说出来，实际输出：\n" + stderr
  )
})

test("listen 成功但启动回调出错时，不再误报「无法监听端口」且不杀掉服务", async function () {
  const appPath = path.join(__dirname, "..", "server", "app.js")
  const mainPath = path.join(__dirname, "..", "server", "main.js")
  const script = [
    "const http = require('node:http')",
    "const appModule = require(" + JSON.stringify(appPath) + ")",
    "appModule.createApp = function () {",
    "  return {",
    "    learning: undefined,", // 读 app.learning.ok 会抛 TypeError
    "    listen: function () {",
    "      return new Promise(function (resolve) {",
    "        const s = http.createServer(function (req, res) { res.end('still alive') })",
    "        s.listen(0, '127.0.0.1', function () {",
    "          console.log('PORT=' + s.address().port)",
    "          resolve(s.address().port)",
    "        })",
    "      })",
    "    },",
    "  }",
    "}",
    "require(" + JSON.stringify(mainPath) + ").main()",
  ].join("\n")
  const child = spawn(process.execPath, ["-e", script], { stdio: ["ignore", "pipe", "pipe"] })
  let stdout = ""
  let stderr = ""
  child.stdout.on("data", function (chunk) {
    stdout += chunk.toString()
  })
  child.stderr.on("data", function (chunk) {
    stderr += chunk.toString()
  })
  try {
    // 等假服务把端口号打出来
    const port = await waitFor(function () {
      const m = /PORT=(\d+)/.exec(stdout)
      return m ? m[1] : null
    })
    assert.ok(port, "假服务没能启动起来，实际输出：\n" + stdout + stderr)
    // 再等一会儿，让 .then 回调里的异常冒出来
    await sleep(500)
    assert.strictEqual(
      child.exitCode,
      null,
      "listen 已经成功，服务不该被 process.exit(1) 杀掉，实际退出码：" + child.exitCode
    )
    assert.ok(
      stderr.indexOf("无法监听端口") === -1,
      "异常不是端口问题，不该说「无法监听端口」，实际输出：\n" + stderr
    )
    assert.ok(
      stderr.indexOf("占用") === -1,
      "异常不是端口问题，不该提端口占用，实际输出：\n" + stderr
    )
    assert.ok(stderr.indexOf("启动") !== -1, "应该打印中文提示，实际输出：\n" + stderr)
    assert.ok(stderr.indexOf("TypeError") !== -1, "应该带上异常类型，实际输出：\n" + stderr)
    // 服务还活着：说明异常没有把已经监听的服务器杀掉
    const res = await fetch("http://127.0.0.1:" + port + "/")
    assert.strictEqual(await res.text(), "still alive")
  } finally {
    child.kill()
  }
})
```

Create `projects/apps/algo-plan/tests/harness.test.js`：

```javascript
"use strict"
/**
 * harness.test.js —— 测试入口自检：run-all.js 自己别出岔子
 *
 * run-all.js 是「跑测试的测试」，它要是空跑还退出 0，
 * 整套回归就等于没有。这里把它复制到临时目录里单独跑。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync, spawnSync } = require("node:child_process")

const RUN_ALL = path.join(__dirname, "run-all.js")

/** 建一个临时目录，把 run-all.js 复制进去，模拟「另一个工程」 */
function makeSandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-harness-"))
  const testsDir = path.join(dir, "tests")
  fs.mkdirSync(testsDir)
  fs.copyFileSync(RUN_ALL, path.join(testsDir, "run-all.js"))
  return {
    dir: dir,
    testsDir: testsDir,
    cleanup: function () {
      fs.rmSync(dir, { recursive: true, force: true })
    },
  }
}

test("run-all.js 在没有测试套件时报错退出（退出码非 0）", function () {
  const sandbox = makeSandbox()
  try {
    const res = spawnSync(process.execPath, [path.join(sandbox.testsDir, "run-all.js")], {
      encoding: "utf8",
    })
    assert.notStrictEqual(res.status, 0, "空套件时退出码必须非 0，不能静默通过")
    assert.ok(
      (res.stderr || "").indexOf("没有找到任何测试套件") !== -1,
      "应该打印中文提示，实际输出：" + JSON.stringify(res.stderr)
    )
    // 提示必须完整送到：stderr 是异步管道时，process.exit() 会在管道把数据
    // 刷出去之前就把进程干掉，尾部会被截断。run-all.js 现在改用
    // process.exitCode 让进程自然退出，所以尾部也必须在。
    assert.ok(
      (res.stderr || "").indexOf("请先创建测试文件") !== -1,
      "中文提示的尾部不能被截断，实际输出：" + JSON.stringify(res.stderr)
    )
  } finally {
    sandbox.cleanup()
  }
})

test("run-all.js 的输出里能看到断言通过数", function () {
  const sandbox = makeSandbox()
  try {
    fs.writeFileSync(
      path.join(sandbox.testsDir, "fake.test.js"),
      'const test = require("node:test")\ntest("占位断言", function () {})\n',
      "utf8"
    )
    const out = execFileSync(process.execPath, [path.join(sandbox.testsDir, "run-all.js")], {
      encoding: "utf8",
    })
    assert.ok(out.indexOf("pass 1") !== -1, "输出里应能看到 pass 计数，实际输出：\n" + out)
    assert.ok(out.indexOf("1 / 1 套件通过") !== -1, "输出里应能看到套件通过数，实际输出：\n" + out)
  } finally {
    sandbox.cleanup()
  }
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/smoke.test.js
```

Expected: FAIL，错误信息含 `Cannot find module '../server/app.js'`

> `tests/run-all.js` 要到 Step 8 才创建，这一步直接跑测试文件即可；Step 9 再用 `run-all.js` 跑全量。

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

注意：**没有 `dependencies` 字段**，这就是零依赖契约。

- [ ] **Step 4: 创建 server/router.js**

Create `projects/apps/algo-plan/server/router.js`：

```javascript
"use strict"
/**
 * router.js —— 极简路由：方法匹配 + 路径参数 + JSON body 解析
 *
 * 零依赖。路径参数用 :name 段式，例如 "/api/problem/:id"。
 * 路由匹配只认路径段，不认正则通配——本机工具用不上那套。
 */

/** 请求体上限 1MB，防止本地误传超大 body 把内存吃满 */
const MAX_BODY_BYTES = 1024 * 1024

/** 带 HTTP 状态码的错误，供 handler 抛出 */
class HttpError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

/**
 * 把 "/api/problem/:id" 编成匹配函数。
 * @param {string} pattern
 * @returns {(urlPath: string) => (object|null)} 命中返回参数对象，不命中返回 null
 */
function compile(pattern) {
  const segs = pattern.split("/").filter(function (s) {
    return s !== ""
  })
  return function (urlPath) {
    const parts = urlPath.split("/").filter(function (s) {
      return s !== ""
    })
    if (parts.length !== segs.length) return null
    const params = {}
    for (let i = 0; i < segs.length; i += 1) {
      const seg = segs[i]
      const raw = parts[i]
      if (seg.charAt(0) === ":") {
        let value
        try {
          value = decodeURIComponent(raw)
        } catch (e) {
          return null
        }
        if (value === "") return null
        params[seg.slice(1)] = value
      } else if (seg !== raw) {
        return null
      }
    }
    return params
  }
}

/**
 * 创建路由表。
 * add(method, pattern, handler) 注册；find(method, urlPath) 查。
 */
function createRouter() {
  const routes = []

  function add(method, pattern, handler) {
    routes.push({
      method: method,
      pattern: pattern,
      match: compile(pattern),
      handler: handler,
    })
  }

  /**
   * @returns {{route: object, params: object}|{methodNotAllowed: true}|null}
   *   route 命中；methodNotAllowed 表示路径对但方法不对；null 表示没这个路径
   */
  function find(method, urlPath) {
    let pathMatched = false
    for (const route of routes) {
      const params = route.match(urlPath)
      if (params === null) continue
      pathMatched = true
      if (route.method === method) {
        return { route: route, params: params }
      }
    }
    if (pathMatched) return { methodNotAllowed: true }
    return null
  }

  return { add: add, find: find, routes: routes }
}

/**
 * 读请求体并解析成 JSON。
 * - 空 body 返回 {}
 * - 非法 JSON 抛 HttpError(400)
 * - body 超过 1MB 抛 HttpError(413)
 * - body 解析出来不是 JSON 对象（数字/字符串/null/数组）抛 HttpError(400)
 * @param {import("node:http").IncomingMessage} req
 * @returns {Promise<object>} 恒定 resolve 一个 JSON 对象
 */
function readJsonBody(req) {
  return new Promise(function (resolve, reject) {
    let size = 0
    let chunks = []
    let settled = false

    /** 超限后用来丢弃剩余数据的回调：只丢不存，也绝不中途断连 */
    function onDrain() {
      // 故意空实现：这段数据直接丢掉，只为把 socket 里剩下的 body 读干净。
      // 必须留一个 'data' 监听器：把 onData 摘掉之后光靠 resume() 不保证真的排空，
      // 留着监听器才能保证数据被消费掉——socket 收空，连接收尾时才不会回 RST。
      //
      // 之前这里有个「读到 8MB 就 req.destroy()」的兜底，害得 10MB 的请求
      // 客户端只拿到 ECONNRESET——销毁 socket 会让内核回 RST，
      // 把 app.js 已经写好的 413 响应冲掉。
      // 中途断连接对内存也毫无保护作用（chunks 已经清空，不再缓存任何东西），
      // 只省带宽而已；而本服务只监听 127.0.0.1，没有远程对手方。
      // 所以这里一路排空到 body 结束，让 413 响应能安稳送到客户端。
    }

    function onData(chunk) {
      size += chunk.length
      if (size > MAX_BODY_BYTES) {
        // 超限：只 reject，**不要** req.destroy()。
        // 销毁 socket 之后 app.js 的 413 响应就写不出去了，
        // 客户端只会收到连接重置（UND_ERR_SOCKET），看不到这句中文提示。
        settled = true
        chunks = []
        req.removeListener("data", onData)
        // 把剩下的 body 读干净并丢弃：socket 收空，连接收尾时才不会回 RST 把 413 响应打掉
        req.on("data", onDrain)
        req.resume()
        reject(new HttpError(413, "请求体过大（上限 1MB）"))
        return
      }
      chunks.push(chunk)
    }

    req.on("data", onData)
    req.on("end", function () {
      if (settled) return
      settled = true
      const raw = Buffer.concat(chunks).toString("utf8").trim()
      if (raw === "") {
        resolve({})
        return
      }
      let value
      try {
        value = JSON.parse(raw)
      } catch (e) {
        reject(new HttpError(400, "请求体不是合法 JSON"))
        return
      }
      // 只接受 JSON 对象：数字、字符串、null、数组都不是对象。
      // 悄悄当成空对象会把「客户端 body 传错了」变成「服务端字段缺失」，更难排查，
      // 所以直接报 400，让调用方明确知道 body 的形状不对。
      if (value === null || typeof value !== "object" || Array.isArray(value)) {
        reject(new HttpError(400, "请求体必须是 JSON 对象"))
        return
      }
      resolve(value)
    })
    req.on("error", function (err) {
      if (settled) return
      settled = true
      reject(err)
    })
  })
}

module.exports = {
  MAX_BODY_BYTES: MAX_BODY_BYTES,
  HttpError: HttpError,
  compile: compile,
  createRouter: createRouter,
  readJsonBody: readJsonBody,
}
```

- [ ] **Step 5: 创建 server/app.js**

Create `projects/apps/algo-plan/server/app.js`：

```javascript
"use strict"
/**
 * app.js —— 组合根：把 SQLite、题库 provider、API 装配到 HTTP 服务上
 *
 * 装配逻辑集中在这一个文件；server/main.js 只做命令行入口。
 */

const http = require("node:http")
const fs = require("node:fs")
const path = require("node:path")

const { createRouter, HttpError } = require("./router.js")

const ROOT = path.resolve(__dirname, "..")
const WEB_DIR = path.join(ROOT, "web")

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
}

/**
 * 回 JSON 响应。
 */
function sendJson(res, status, body) {
  const text = JSON.stringify(body)
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(text),
    "cache-control": "no-store",
  })
  res.end(text)
}

/**
 * API 请求前缀判定：/api 与 /api/... 都算 API 请求。
 * 统一成一个 helper，免得 /api 漏到静态分支去回 text/plain 的 404，
 * 跟 /api/nope 的 JSON 404 对不上。
 */
function isApiPath(urlPath) {
  return urlPath === "/api" || urlPath.indexOf("/api/") === 0
}

/**
 * 把 URL 路径映射到 web/ 内的文件；越界或编码非法一律拒绝（返回 null）。
 * 入参是已经切掉查询串的路径。
 */
function resolveStatic(urlPath) {
  let clean
  try {
    clean = decodeURIComponent(urlPath)
  } catch (e) {
    return null
  }
  const rel = clean === "/" ? "index.html" : clean.replace(/^\/+/, "")
  const abs = path.resolve(WEB_DIR, rel)
  if (abs !== WEB_DIR && abs.indexOf(WEB_DIR + path.sep) !== 0) return null
  return abs
}

/**
 * 创建 HTTP 服务。
 * @param {{routes?: Array}} opts
 */
function createServer(opts) {
  const options = opts || {}
  const router = createRouter()
  const routes = options.routes || []
  /** 常驻的 server 错误监听器只装一次，避免 listen 被调多次时重复挂 */
  let runtimeErrorHandled = false
  routes.forEach(function (route) {
    router.add(route.method, route.pattern, route.handler)
  })

  const server = http.createServer(function (req, res) {
    const rawUrl = req.url || "/"
    const rawPath = rawUrl.split("?")[0]
    const query = new URLSearchParams(rawUrl.indexOf("?") === -1 ? "" : rawUrl.slice(rawUrl.indexOf("?") + 1))
    const found = router.find(req.method, rawPath)

    if (found && found.route) {
      Promise.resolve()
        .then(function () {
          return found.route.handler(req, res, found.params, query)
        })
        .catch(function (err) {
          // 响应已经开始发出、或连接已经断了：不能再改状态码，只能收尾。
          // 但异常不能就这么没了——下面那条 console.error 在这个分支里会被跳过，
          // handler「先 res.end() 再 throw」就会彻底静默。所以这里也要留一份日志。
          if (res.headersSent || res.writableEnded || res.destroyed) {
            console.error(
              "[algo-plan] 接口 " + req.method + " " + rawPath + " 处理异常（响应已发出，无法再改状态码）：",
              err
            )
            if (!res.writableEnded && !res.destroyed) res.end()
            return
          }
          // 只有 HttpError 的文案是「我们自己写的中文」，可以直接透给浏览器；
          // 其它异常（TypeError 之类）是原生英文报错，透出去既看不懂也暴露实现细节
          const isHttpError = err instanceof HttpError
          // 只认 4xx/5xx：非法状态码会让 res.writeHead 抛错，反而把服务带崩
          const status = isHttpError && err.status >= 400 && err.status <= 599 ? err.status : 500
          if (!isHttpError) {
            // 服务端留一份完整堆栈，不然异常在终端里毫无痕迹
            console.error("[algo-plan] 接口 " + req.method + " " + rawPath + " 处理异常：", err)
          }
          sendJson(res, status, {
            error: isHttpError ? err.message : "服务端出错",
          })
        })
      return
    }

    if (found && found.methodNotAllowed) {
      sendJson(res, 405, {
        error: "方法不允许",
        method: req.method,
        path: rawPath,
      })
      return
    }

    if (isApiPath(rawPath)) {
      sendJson(res, 404, { error: "接口不存在", path: rawPath })
      return
    }

    const file = resolveStatic(rawPath)
    if (!file) {
      res.writeHead(400, { "content-type": "text/plain; charset=utf-8" })
      res.end("400 非法路径")
      return
    }
    let body
    try {
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
        res.writeHead(404, { "content-type": "text/plain; charset=utf-8" })
        res.end("404 找不到")
        return
      }
      body = fs.readFileSync(file)
    } catch (err) {
      // Windows 上文件被独占锁定（EPERM/EBUSY）时 statSync/readFileSync 会抛错。
      // 不兜住的话异常会从请求回调逃出去，Node 没有 uncaughtException 处理，整个服务挂掉。
      const code = err && err.code ? err.code : "未知错误"
      console.error("[algo-plan] 读取静态文件失败：" + file + "（" + code + "）")
      if (code === "ENOENT" || code === "ENOTDIR") {
        res.writeHead(404, { "content-type": "text/plain; charset=utf-8" })
        res.end("404 找不到")
        return
      }
      res.writeHead(500, { "content-type": "text/plain; charset=utf-8" })
      res.end("500 服务器内部错误")
      return
    }
    res.writeHead(200, {
      "content-type": MIME[path.extname(file)] || "application/octet-stream",
      "content-length": body.length,
      "cache-control": "no-store",
    })
    res.end(body)
  })

  return {
    server: server,
    listen: function (port) {
      return new Promise(function (resolve, reject) {
        function onListenError(err) {
          reject(err)
        }
        server.once("error", onListenError)
        server.listen(port, "127.0.0.1", function () {
          // listen 成功后撤掉这个一次性监听器：它留在 server 上就是空转，
          // 第一次 error 被已经 settle 的 reject 吞掉，第二次 error 就没人接（未捕获异常）。
          server.removeListener("error", onListenError)
          if (!runtimeErrorHandled) {
            runtimeErrorHandled = true
            // 常驻错误处理器：服务运行期的 socket 错误只记中文日志，不让进程崩掉
            server.on("error", function (err) {
              console.error(
                "[algo-plan] 服务运行期错误：" + (err && err.code ? err.code : "未知错误"),
                err
              )
            })
          }
          resolve(server.address().port)
        })
      })
    },
    close: function () {
      return new Promise(function (resolve) {
        server.close(function () {
          resolve()
        })
      })
    },
  }
}

/**
 * 装配整个应用。
 * @param {{dbPath?: string, learningRoot?: string, env?: object}} opts
 *   dbPath：SQLite 文件路径，默认 data/app.db；传 ":memory:" 用内存库
 *   learningRoot：learning 仓根目录；不传则读环境变量
 */
function createApp(opts) {
  const options = opts || {}

  // 延迟 require：core/ 与 db/api 在后续 Task 才落地，createServer 不依赖它们
  const { resolveLearningRoot } = require("../core/paths.js")
  const { FileProvider } = require("../core/bank/provider.js")
  const { openDb, createStore } = require("./db.js")

  const db = openDb(options.dbPath || path.join(ROOT, "data", "app.db"))
  const store = createStore(db)

  const learning = resolveLearningRoot(options.env || process.env, options.learningRoot)
  const provider = new FileProvider(learning.ok ? path.join(learning.root, "bank") : null)

  const routes = require("./api.js").buildRoutes({
    store: store,
    provider: provider,
    learning: learning,
    sendJson: sendJson,
  })

  const server = createServer({ routes: routes })

  return {
    server: server.server,
    listen: server.listen,
    close: function () {
      return server.close().then(function () {
        db.close()
      })
    },
    db: db,
    store: store,
    provider: provider,
    learning: learning,
  }
}

module.exports = { ROOT: ROOT, WEB_DIR: WEB_DIR, createServer: createServer, createApp: createApp, sendJson: sendJson }
```

> **注意**：`createApp` 依赖 Task 4 的 `server/db.js`、Task 5 的 `core/paths.js` 与 `core/bank/provider.js`、
> Task 6 的 `server/api.js`。这四个 `require` 写在 `createApp` **函数体内**（延迟加载），
> 所以本 Task 里 `createServer` 单独可用，测试不受影响；等 Task 6 做完 `createApp` 才真正跑得通。
> 这正是「一个 Task 一个可验收交付物」的边界。

- [ ] **Step 6: 创建 server/main.js**

Create `projects/apps/algo-plan/server/main.js`：

```javascript
"use strict"
/**
 * main.js —— 命令行入口
 *
 * 用法：node server/main.js
 * 环境变量：PORT（默认 5173）、ALGO_PLAN_LEARNING_ROOT（可选）
 */

const { createApp } = require("./app.js")

function checkNodeVersion() {
  const major = Number(process.versions.node.split(".")[0])
  if (major < 24) {
    console.error("需要 Node >= 24（用到 node:sqlite），当前是 " + process.version)
    process.exit(1)
  }
}

function main() {
  checkNodeVersion()
  const app = createApp()
  const port = Number(process.env.PORT || 5173)
  // listen 是否已经成功：用来区分「端口没起来」和「起来了但后面的启动输出炸了」
  let listenOk = false
  app
    .listen(port)
    .then(function (p) {
      listenOk = true
      console.log("算法能力计划 App 已启动：http://127.0.0.1:" + p)
      if (app.learning.ok) {
        console.log("learning 仓：" + app.learning.root)
      } else {
        console.log("未连接 learning 仓（纯本地模式）：" + app.learning.reason)
      }
    })
    .catch(function (err) {
      const code = err && err.code ? err.code : "未知错误"
      if (listenOk) {
        // listen 已经成功了：异常来自上面的 .then 回调（比如读 app.learning 时炸了），
        // 跟端口一点关系都没有。这时候再 process.exit(1) 会把已经跑起来的服务杀掉，
        // 所以只记日志，让服务继续跑。
        console.error(
          "[algo-plan] 启动信息输出失败（服务已在端口 " + port + " 上运行）：",
          err
        )
        return
      }
      // listen 失败：最常见的是端口被占用，按错误码给不同的中文提示
      if (code === "EADDRINUSE") {
        console.error(
          "启动失败：端口 " + port + " 已被占用（EADDRINUSE），请换一个端口，或先关掉占用该端口的程序"
        )
      } else if (code === "EACCES") {
        console.error(
          "启动失败：没有权限监听端口 " + port + "（EACCES），请换一个 1024 以上的端口"
        )
      } else {
        console.error("启动失败：无法监听端口 " + port + "（" + code + "）")
      }
      if (!err || !err.code) {
        // 没有错误码的意外异常才补一份堆栈，方便定位
        console.error(err)
      }
      // 这里必须用 process.exit(1)：createApp() 已经打开了 SQLite 连接，
      // 改成 process.exitCode = 1 的话进程会因为连接还挂着而不退出。
      // stderr 是终端而不是管道时不会截断；真要管道场景再单独处理。
      process.exit(1)
    })
}

if (require.main === module) {
  main()
}

module.exports = { main: main, checkNodeVersion: checkNodeVersion }
```

- [ ] **Step 7: 创建 web/index.html 与 web/style.css**

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
  <main id="view">
    <div class="panel">正在加载…</div>
  </main>
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
  --warn: #e0b341;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 15px/1.6 "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
}
.topbar {
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 14px 24px;
  border-bottom: 1px solid var(--line);
  background: var(--panel);
}
.topbar h1 { font-size: 17px; margin: 0; font-weight: 600; }
nav button {
  background: none;
  border: none;
  color: var(--muted);
  font-size: 14px;
  padding: 4px 2px;
  margin-right: 16px;
  cursor: pointer;
}
nav button.active { color: var(--accent); border-bottom: 2px solid var(--accent); }
main { max-width: 1080px; margin: 0 auto; padding: 24px; }
.panel {
  background: var(--panel);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 18px 20px;
  margin-bottom: 18px;
}
.panel h2 { font-size: 15px; margin: 0 0 12px; font-weight: 600; }
.kv { display: flex; flex-wrap: wrap; gap: 10px 28px; font-size: 14px; }
.kv div { color: var(--muted); }
.kv span { color: var(--fg); }
.badge {
  display: inline-block;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 1px 10px;
  font-size: 12px;
  color: var(--muted);
  margin-right: 6px;
}
.badge.ok { color: var(--ok); border-color: var(--ok); }
.badge.bad { color: var(--bad); border-color: var(--bad); }
.badge.warn { color: var(--warn); border-color: var(--warn); }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); }
th { color: var(--muted); font-weight: 500; }
.error { color: var(--bad); }
.muted { color: var(--muted); font-size: 13px; }
```

- [ ] **Step 8: 创建 tests/run-all.js**

Create `projects/apps/algo-plan/tests/run-all.js`：

```javascript
"use strict"
/**
 * run-all.js —— 一键跑全部测试
 *
 * 用法：node tests/run-all.js
 * 自动发现 tests/*.test.js，新增测试套件无需手动登记。
 */

const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const ROOT = path.resolve(__dirname, "..")

const suites = []
fs.readdirSync(path.join(ROOT, "tests")).forEach(function (file) {
  if (/^.+\.test\.js$/.test(file)) suites.push(file)
})

function main() {
  if (suites.length === 0) {
    // 空跑静默「通过」是最阴的一种假绿：一条断言都没跑，退出码却是 0
    // 这里用 process.exitCode 而不是 process.exit()：stderr 可能是异步管道，
    // process.exit() 会在管道把数据刷出去之前就把进程干掉，中文提示可能被截断。
    console.error("没有找到任何测试套件（tests/*.test.js），请先创建测试文件")
    process.exitCode = 1
    return
  }

  let failed = 0
  suites.forEach(function (file) {
    process.stdout.write("\n▶ " + file + "\n")
    try {
      const out = execFileSync(process.execPath, [path.join(ROOT, "tests", file)], {
        cwd: ROOT,
        encoding: "utf8",
      })
      const lines = out.trim().split("\n")
      // 保留 node:test 的收尾统计。只留 3 行会把 "ℹ pass N / ℹ fail 0" 正好切掉，
      // 看不出这套件到底跑了多少条断言
      console.log(lines.slice(-5).join("\n"))
      const counts = []
      lines.forEach(function (line) {
        const m = /^ℹ (tests|pass|fail)\s+(\d+)/.exec(line)
        if (m) counts.push(m[1] + " " + m[2])
      })
      if (counts.length > 0) console.log("断言统计：" + counts.join(" / "))
    } catch (e) {
      failed += 1
      const out = ((e.stdout || "") + (e.stderr || "")).trim()
      console.log(out.split("\n").slice(-20).join("\n"))
    }
  })

  console.log("\n" + (suites.length - failed) + " / " + suites.length + " 套件通过")
  // 用 process.exitCode 而不是 process.exit()：stderr 是异步管道时，
  // process.exit() 可能在管道把数据刷出去之前就把进程干掉，中文提示会被截断。
  // 置了 exitCode 之后进程自然退出，stderr 能被 flush 干净；退出码照样非 0。
  process.exitCode = failed === 0 ? 0 : 1
}

main()
```

- [ ] **Step 9: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `4 / 4 套件通过`，退出码 0（断言统计：errors 13 / harness 2 / router 10 / smoke 7，合计 32 条）

- [ ] **Step 10: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 建立零依赖应用骨架与路由内核

- package.json 仅声明 name/private/type/scripts，无任何 dependencies
- server/router.js：路径参数路由 + JSON body 解析 + HttpError
- server/app.js：静态托管（含路径越界防护）、404/405 分流、组合根
- server/main.js：命令行入口与 Node>=24 版本闸门
- web/：单页外壳与样式
- tests/run-all.js：自动发现 *.test.js 的测试入口
- 测试：静态首页 200 / 未知路径 404 / 越界 400 / 方法不对 405 / 路由与 body 解析"
git push origin main
```

---

## Task 2: Problem 模型、稳定 ID 与 topic 归一化

**Files:**
- Create: `projects/apps/algo-plan/core/bank/problem.js`
- Create: `projects/apps/algo-plan/tests/problem.test.js`

**Interfaces:**
- Consumes: 无
- Produces（后续 Task 直接引用这些名字与签名）：
  - `TRACKS` / `SOURCES` / `SOURCE_PREFIX` / `DIFFICULTIES` / `STATUSES`：常量数组与映射
  - `normalizeTopic(text) -> string`
  - `normalizeTopics(list) -> string[]`（接受数组或单个字符串）
  - `normalizeTracks(list) -> string[]`（丢弃非法轨道）
  - `today() -> "YYYY-MM-DD"`
  - `makeId(source, number) -> string`（抛错于未知来源/非数字题号）
  - `makeLlmId(seed) -> string`（`llm-` + sha1 前 10 位）
  - `isValidId(id) -> boolean`
  - `validateProblem(problem) -> {ok: boolean, errors: string[]}`
  - `createProblem(input) -> Problem`（填默认值 + 归一化 + 校验，非法抛错）
  - `toSummary(problem) -> {id, title, source, difficulty, topics, tracks, status, needsFill}`

  **Problem 的字段形状（后面 parse/provider 都按这个来）：**

  ```js
  {
    id: "lc-00001",
    source: "leetcode",
    title: "两数之和",
    difficulty: "easy",
    topics: ["哈希表", "数组"],
    tracks: ["interview", "fundamentals"],
    status: "todo",
    needsFill: false,
    created: "2026-11-11",
    updated: "2026-11-11",
    statement: "题面正文",
    cases: [{ input: "[2,7,11,15], 9", expect: "[0,1]", tol: null }],
    solution: "int main(){}",
    solutionLang: "cpp",
    extraSections: [{ title: "备注", content: "..." }],
  }
  ```

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/problem.test.js`：

```javascript
"use strict"
/**
 * problem.test.js —— Problem 模型：ID、topic 归一化、字段校验
 */

const test = require("node:test")
const assert = require("node:assert")

const problem = require("../core/bank/problem.js")

test("makeId 生成 5 位补零 ID", function () {
  assert.strictEqual(problem.makeId("leetcode", 1), "lc-00001")
  assert.strictEqual(problem.makeId("leetcode", 99999), "lc-99999")
  assert.strictEqual(problem.makeId("nowcoder", 12), "nc-00012")
  assert.strictEqual(problem.makeId("self", 7), "self-00007")
})

test("makeId 拒绝未知来源与非数字题号", function () {
  assert.throws(function () {
    problem.makeId("unknown", 1)
  })
  assert.throws(function () {
    problem.makeId("leetcode", "abc")
  })
})

test("makeLlmId 稳定且可复现", function () {
  const a = problem.makeLlmId("两数之和")
  const b = problem.makeLlmId("两数之和")
  assert.strictEqual(a, b)
  assert.ok(problem.isValidId(a), a + " 应是合法 ID")
  assert.notStrictEqual(a, problem.makeLlmId("三数之和"))
})

test("isValidId 只认已知前缀", function () {
  assert.ok(problem.isValidId("lc-00001"))
  assert.ok(problem.isValidId("llm-1a2b3c4d5e"))
  assert.ok(problem.isValidId("self-00007"))
  assert.ok(!problem.isValidId("xx-00001"))
  assert.ok(!problem.isValidId("lc-1"))
  assert.ok(!problem.isValidId(""))
})

test("normalizeTopics 去空白、去重、保序", function () {
  const out = problem.normalizeTopics([" 哈希表 ", "数组", "哈希表", "", "  "])
  assert.deepStrictEqual(out, ["哈希表", "数组"])
})

test("normalizeTopics 接受单个字符串", function () {
  assert.deepStrictEqual(problem.normalizeTopics("数组"), ["数组"])
})

test("normalizeTracks 丢掉非法轨道", function () {
  const out = problem.normalizeTracks(["interview", "不存在的轨道", "advanced"])
  assert.deepStrictEqual(out, ["interview", "advanced"])
})

test("validateProblem 报出具体错误", function () {
  const result = problem.validateProblem({
    id: "bad",
    source: "leetcode",
    title: "",
    difficulty: "hard",
    topics: [],
    tracks: ["interview"],
    status: "todo",
  })
  assert.strictEqual(result.ok, false)
  assert.ok(result.errors.some(function (e) { return e.indexOf("id 非法") === 0 }))
  assert.ok(result.errors.some(function (e) { return e.indexOf("title 为空") === 0 }))
  assert.ok(result.errors.some(function (e) { return e.indexOf("topics") === 0 }))
})

test("validateProblem 接受合法题目", function () {
  const result = problem.validateProblem({
    id: "lc-00001",
    source: "leetcode",
    title: "两数之和",
    difficulty: "easy",
    topics: ["数组"],
    tracks: ["interview"],
    status: "todo",
  })
  assert.deepStrictEqual(result.errors, [])
  assert.strictEqual(result.ok, true)
})

test("createProblem 填默认值并归一化", function () {
  const created = problem.createProblem({
    id: "lc-00002",
    source: "leetcode",
    title: "  三数之和  ",
    topics: [" 数组 ", "数组"],
    tracks: ["interview"],
  })
  assert.strictEqual(created.title, "三数之和")
  assert.deepStrictEqual(created.topics, ["数组"])
  assert.strictEqual(created.difficulty, "medium")
  assert.strictEqual(created.status, "todo")
  assert.strictEqual(created.needsFill, false)
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(created.created), created.created)
})

test("createProblem 字段非法时抛错", function () {
  assert.throws(function () {
    problem.createProblem({ id: "x", source: "leetcode", title: "t", topics: ["a"], tracks: ["interview"] })
  })
})

test("toSummary 不带题面与解法", function () {
  const created = problem.createProblem({
    id: "lc-00003",
    source: "leetcode",
    title: "题目",
    topics: ["数组"],
    tracks: ["interview"],
    statement: "题面正文",
    solution: "int main(){}",
  })
  const summary = problem.toSummary(created)
  assert.strictEqual(summary.id, "lc-00003")
  assert.strictEqual(summary.statement, undefined)
  assert.strictEqual(summary.solution, undefined)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/bank/problem.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/bank/problem.js`：

```javascript
"use strict"
/**
 * problem.js —— Problem 模型、稳定 ID、topic 归一化、字段校验
 *
 * 纯函数，无 IO。Problem 是 git 侧（learning/bank/*.md）与 SQLite 侧的唯一连接载体，
 * 一切靠稳定 id 互链（设计文档 §3.4）。
 */

const crypto = require("node:crypto")

/** 四条学习轨道 */
const TRACKS = ["interview", "fundamentals", "advanced", "engineering"]

/** 题目来源 */
const SOURCES = ["leetcode", "nowcoder", "jz", "self", "llm"]

/** 来源 → ID 前缀 */
const SOURCE_PREFIX = {
  leetcode: "lc",
  nowcoder: "nc",
  jz: "jz",
  self: "self",
  llm: "llm",
}

/** 难度 */
const DIFFICULTIES = ["easy", "medium", "hard"]

/** 题目状态 */
const STATUSES = ["todo", "in-progress", "done"]

/**
 * 归一化单个 topic：去首尾空白、内部连续空白压成一个空格。
 * topic 的 key 就是标签文本本身（设计文档 §3.4），所以拼写必须统一。
 */
function normalizeTopic(text) {
  if (text === null || text === undefined) return ""
  return String(text).trim().replace(/\s+/g, " ")
}

/**
 * 归一化 topic 列表：去空、去重、保序。
 * @param {string[]|string} list
 * @returns {string[]}
 */
function normalizeTopics(list) {
  const input = Array.isArray(list) ? list : list ? [list] : []
  const seen = Object.create(null)
  const out = []
  input.forEach(function (item) {
    const topic = normalizeTopic(item)
    if (topic === "" || seen[topic]) return
    seen[topic] = true
    out.push(topic)
  })
  return out
}

/**
 * 归一化 track 列表：只保留合法 track，去重保序。
 * @param {string[]|string} list
 * @returns {string[]}
 */
function normalizeTracks(list) {
  const input = Array.isArray(list) ? list : list ? [list] : []
  const seen = Object.create(null)
  const out = []
  input.forEach(function (item) {
    const track = normalizeTopic(item)
    if (track === "" || TRACKS.indexOf(track) === -1 || seen[track]) return
    seen[track] = true
    out.push(track)
  })
  return out
}

/** 今天的日期（YYYY-MM-DD，本地时区） */
function today() {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const d = String(now.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + d
}

/**
 * 生成稳定 ID：`<前缀>-<5 位数字>`，例如 lc-00001。
 * @param {string} source 来源，见 SOURCES
 * @param {number|string} number 题号
 * @returns {string}
 */
function makeId(source, number) {
  const prefix = SOURCE_PREFIX[source]
  if (!prefix) throw new Error("未知题目来源：" + source)
  const digits = String(Math.trunc(Number(number)))
  if (!/^\d+$/.test(digits)) throw new Error("题号必须是数字：" + number)
  return prefix + "-" + (digits.length >= 5 ? digits : "00000".slice(digits.length) + digits)
}

/**
 * LLM 现造题的 ID：内容哈希，稳定且可复现。
 * @param {string} seed 题面或参考解法
 * @returns {string}
 */
function makeLlmId(seed) {
  const hash = crypto.createHash("sha1").update(String(seed)).digest("hex")
  return "llm-" + hash.slice(0, 10)
}

/**
 * ID 是否合法。
 * @param {string} id
 * @returns {boolean}
 */
function isValidId(id) {
  return /^(lc|nc|jz|self|llm)-[0-9a-z]{5,12}$/.test(String(id || ""))
}

/**
 * 校验题目字段。
 * @param {object} problem
 * @returns {{ok: boolean, errors: string[]}}
 */
function validateProblem(problem) {
  const errors = []
  if (!problem || typeof problem !== "object") {
    return { ok: false, errors: ["题目不是对象"] }
  }
  if (!isValidId(problem.id)) errors.push("id 非法：" + problem.id)
  if (SOURCES.indexOf(problem.source) === -1) errors.push("source 非法：" + problem.source)
  if (!problem.title) errors.push("title 为空")
  if (DIFFICULTIES.indexOf(problem.difficulty) === -1) {
    errors.push("difficulty 非法：" + problem.difficulty)
  }
  if (!Array.isArray(problem.topics) || problem.topics.length === 0) {
    errors.push("topics 不能为空")
  }
  if (!Array.isArray(problem.tracks) || problem.tracks.length === 0) {
    errors.push("tracks 不能为空")
  } else {
    problem.tracks.forEach(function (track) {
      if (TRACKS.indexOf(track) === -1) errors.push("track 非法：" + track)
    })
  }
  if (STATUSES.indexOf(problem.status) === -1) errors.push("status 非法：" + problem.status)
  return { ok: errors.length === 0, errors: errors }
}

/**
 * 按字段建一道题：填默认值 + 归一化 + 校验（不合法直接抛错）。
 * @param {object} input
 * @returns {object} Problem
 */
function createProblem(input) {
  const src = input || {}
  const problem = {
    id: src.id,
    source: src.source,
    title: src.title ? String(src.title).trim() : "",
    difficulty: src.difficulty || "medium",
    topics: normalizeTopics(src.topics),
    tracks: normalizeTracks(src.tracks),
    status: src.status || "todo",
    needsFill: src.needsFill === true,
    created: src.created || today(),
    updated: src.updated || today(),
    statement: src.statement ? String(src.statement).trim() : "",
    cases: Array.isArray(src.cases) ? src.cases : [],
    solution: src.solution ? String(src.solution).replace(/\n$/, "") : "",
    solutionLang: src.solutionLang || "",
    extraSections: Array.isArray(src.extraSections) ? src.extraSections : [],
  }

  const result = validateProblem(problem)
  if (!result.ok) {
    throw new Error("题目字段非法：" + result.errors.join("；"))
  }
  return problem
}

/**
 * 题目摘要（列表页用，不含题面、用例、解法）。
 * @param {object} problem
 * @returns {object}
 */
function toSummary(problem) {
  return {
    id: problem.id,
    title: problem.title,
    source: problem.source,
    difficulty: problem.difficulty,
    topics: problem.topics,
    tracks: problem.tracks,
    status: problem.status,
    needsFill: problem.needsFill,
  }
}

module.exports = {
  TRACKS: TRACKS,
  SOURCES: SOURCES,
  SOURCE_PREFIX: SOURCE_PREFIX,
  DIFFICULTIES: DIFFICULTIES,
  STATUSES: STATUSES,
  normalizeTopic: normalizeTopic,
  normalizeTopics: normalizeTopics,
  normalizeTracks: normalizeTracks,
  today: today,
  makeId: makeId,
  makeLlmId: makeLlmId,
  isValidId: isValidId,
  validateProblem: validateProblem,
  createProblem: createProblem,
  toSummary: toSummary,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `3 / 3 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加 Problem 模型与稳定 ID

- core/bank/problem.js：Problem 字段定义、四条轨道与五种来源常量
- makeId 生成 lc-/nc-/jz-/self- 前缀的 5 位补零 ID；makeLlmId 用内容哈希
- topic 归一化：去空白、去重、保序；track 归一化丢弃非法值
- validateProblem 报出具体字段错误；createProblem 填默认值后校验
- toSummary 只带列表页需要的字段，不泄露题面与解法
- 测试：ID 生成、归一化、校验、默认值共 10 条断言"
git push origin main
```

---

## Task 3: 题库 markdown ↔ Problem 双向转换

**Files:**
- Create: `projects/apps/algo-plan/core/bank/parse.js`
- Create: `projects/apps/algo-plan/tests/parse.test.js`

**Interfaces:**
- Consumes: Task 2 的 `core/bank/problem.js`（`normalizeTopics`、`normalizeTracks`、`today`）
- Produces:
  - `parseFrontmatter(text) -> object`：mini-YAML frontmatter 解析（标量、内联数组、块列表、引号）
  - `serializeFrontmatter(obj) -> string`：反序列化，**不含**首尾 `---`
  - `splitSections(body) -> {标题: 内容}`：按 `## 标题` 切分
  - `parseCases(text) -> [{input, expect, tol}]`：解析用例表格，第三格可带 `tol=1e-6`
  - `parseSolution(text) -> {code, lang}`：解析代码块
  - `parseProblemMarkdown(text) -> {problem, warnings}`：整篇解析，缺 frontmatter 只告警不抛错
  - `serializeProblemMarkdown(problem) -> string`：整篇序列化
  - 常量 `SECTION_STATEMENT` / `SECTION_CASES` / `SECTION_SOLUTION`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/parse.test.js`：

```javascript
"use strict"
/**
 * parse.test.js —— markdown ↔ Problem 双向转换
 */

const test = require("node:test")
const assert = require("node:assert")

const parse = require("../core/bank/parse.js")

const SAMPLE = [
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
  "| 3,2,4, 6 | 1,2 | tol=1e-6 |",
  "",
  "## 参考解法",
  "",
  "```cpp",
  "int main() { return 0; }",
  "```",
  "",
].join("\n")

test("parseFrontmatter 解析标量、数组与空数组", function () {
  const fm = parse.parseFrontmatter(
    ["id: lc-00001", "title: 两数之和", "topics: [数组, 哈希表]", "links: []", "flag: true"].join("\n")
  )
  assert.strictEqual(fm.id, "lc-00001")
  assert.strictEqual(fm.title, "两数之和")
  assert.deepStrictEqual(fm.topics, ["数组", "哈希表"])
  assert.deepStrictEqual(fm.links, [])
  assert.strictEqual(fm.flag, "true")
})

test("parseFrontmatter 去掉引号", function () {
  const fm = parse.parseFrontmatter('title: "两数之和"')
  assert.strictEqual(fm.title, "两数之和")
})

test("parseFrontmatter 解析块列表", function () {
  const fm = parse.parseFrontmatter(["topics:", "  - 数组", "  - 哈希表"].join("\n"))
  assert.deepStrictEqual(fm.topics, ["数组", "哈希表"])
})

test("serializeFrontmatter 数组与布尔", function () {
  const text = parse.serializeFrontmatter({ id: "lc-00001", topics: ["数组"], needs_fill: true })
  assert.ok(text.indexOf("topics: [数组]") !== -1, text)
  assert.ok(text.indexOf("needs_fill: true") !== -1, text)
})

test("parseCases 解析用例表与容差", function () {
  const cases = parse.parseCases(
    ["| input | expect |", "|---|---|", "| a | b |", "| c | d | tol=1e-6 |"].join("\n")
  )
  assert.strictEqual(cases.length, 2)
  assert.deepStrictEqual(cases[0], { input: "a", expect: "b", tol: null })
  assert.strictEqual(cases[1].tol, 1e-6)
})

test("parseCases 认不出列就跳过，不报错", function () {
  const cases = parse.parseCases(["| a |", "|---|---|", "| 只有一列 |"].join("\n"))
  assert.strictEqual(cases.length, 0)
})

test("parseSolution 取代码块与语言", function () {
  const out = parse.parseSolution("```cpp\nint main() { return 0; }\n```")
  assert.strictEqual(out.lang, "cpp")
  assert.strictEqual(out.code, "int main() { return 0; }")
})

test("parseProblemMarkdown 解析整篇", function () {
  const result = parse.parseProblemMarkdown(SAMPLE)
  const p = result.problem
  assert.strictEqual(p.id, "lc-00001")
  assert.strictEqual(p.source, "leetcode")
  assert.strictEqual(p.title, "两数之和")
  assert.strictEqual(p.difficulty, "easy")
  assert.deepStrictEqual(p.topics, ["哈希表", "数组"])
  assert.deepStrictEqual(p.tracks, ["interview", "fundamentals"])
  assert.strictEqual(p.status, "todo")
  assert.strictEqual(p.needsFill, false)
  assert.strictEqual(p.statement, "给定整数数组与目标值。")
  assert.strictEqual(p.cases.length, 2)
  assert.strictEqual(p.cases[1].tol, 1e-6)
  assert.strictEqual(p.solution, "int main() { return 0; }")
  assert.strictEqual(p.solutionLang, "cpp")
  assert.deepStrictEqual(result.warnings, [])
})

test("parseProblemMarkdown 缺 frontmatter 时给告警而不是抛错", function () {
  const result = parse.parseProblemMarkdown("## 题面\n\n只有正文")
  assert.strictEqual(result.problem.id, "")
  assert.ok(result.warnings.length > 0)
})

test("parseProblemMarkdown 保留未识别的小节", function () {
  const text = SAMPLE + "\n## 备注\n\n一些补充说明\n"
  const result = parse.parseProblemMarkdown(text)
  assert.strictEqual(result.problem.extraSections.length, 1)
  assert.strictEqual(result.problem.extraSections[0].title, "备注")
})

test("Problem → markdown → Problem 往返等价", function () {
  const first = parse.parseProblemMarkdown(SAMPLE).problem
  const text = parse.serializeProblemMarkdown(first)
  const second = parse.parseProblemMarkdown(text).problem
  assert.deepStrictEqual(second, first)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/bank/parse.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/bank/parse.js`：

```javascript
"use strict"
/**
 * parse.js —— markdown ↔ Problem 双向转换
 *
 * 纯函数，无 IO。题库文件格式见设计文档 §3.2：
 *   frontmatter（id/source/title/difficulty/topics/tracks/status/needs_fill/created/updated）
 *   + 「## 题面」「## 测试用例」「## 参考解法」三个正文小节。
 *
 * frontmatter 用手写的 mini-YAML 解析器——零依赖是硬约束（设计文档 §1.9）。
 */

const { normalizeTopics, normalizeTracks, today } = require("./problem.js")

/** 已知的正文小节标题 */
const SECTION_STATEMENT = "题面"
const SECTION_CASES = "测试用例"
const SECTION_SOLUTION = "参考解法"
const KNOWN_SECTIONS = [SECTION_STATEMENT, SECTION_CASES, SECTION_SOLUTION]

/**
 * 去掉一层引号。
 */
function unquote(value) {
  const text = String(value).trim()
  if (text.length >= 2) {
    const first = text.charAt(0)
    const last = text.charAt(text.length - 1)
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return text.slice(1, -1)
    }
  }
  return text
}

/**
 * 解析 frontmatter 片段（不含首尾 --- 分隔线）。
 *
 * 支持：key: value、key: [a, b]、key: []、块列表（- item 形式）、引号包裹的值。
 * 不支持：嵌套 map、多行标量（| 与 >）——题库格式用不上。
 *
 * @param {string} text
 * @returns {object}
 */
function parseFrontmatter(text) {
  const lines = String(text || "").split(/\r?\n/)
  const out = {}
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    const trimmed = line.trim()
    if (trimmed === "" || trimmed.charAt(0) === "#") {
      i += 1
      continue
    }
    const m = /^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$/.exec(line)
    if (!m) {
      i += 1
      continue
    }
    const key = m[1]
    const raw = m[2].trim()
    if (raw === "") {
      // 块列表：下面连续的 "- xxx"
      const items = []
      i += 1
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
        items.push(unquote(lines[i].replace(/^\s*-\s+/, "")))
        i += 1
      }
      out[key] = items
      continue
    }
    if (raw.charAt(0) === "[" && raw.charAt(raw.length - 1) === "]") {
      const inner = raw.slice(1, -1).trim()
      if (inner === "") {
        out[key] = []
      } else {
        out[key] = inner.split(",").map(function (item) {
          return unquote(item)
        })
      }
      i += 1
      continue
    }
    out[key] = unquote(raw)
    i += 1
  }
  return out
}

/**
 * 序列化 frontmatter（不含首尾 --- 分隔线）。
 * @param {object} obj
 * @returns {string}
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

/**
 * 按「## 标题」切分正文。
 * @param {string} body
 * @returns {Object<string,string>} 标题 → 内容
 */
function splitSections(body) {
  const sections = {}
  let current = ""
  let buf = []
  String(body || "")
    .split(/\r?\n/)
    .forEach(function (line) {
      const m = /^##\s+(.*)$/.exec(line)
      if (m) {
        if (current !== "") sections[current] = buf.join("\n")
        current = m[1].trim()
        buf = []
      } else {
        buf.push(line)
      }
    })
  if (current !== "") sections[current] = buf.join("\n")
  return sections
}

/**
 * 解析「## 测试用例」里的 markdown 表格。
 *
 * 表头形如 `| input | expect |`，数据行第三格可带 `tol=1e-6` 容差标记。
 * 认不出列的行直接跳过，不报错。
 *
 * @param {string} text
 * @returns {Array<{input: string, expect: string, tol: number|null}>}
 */
function parseCases(text) {
  const cases = []
  let headerSeen = false
  String(text || "")
    .split(/\r?\n/)
    .forEach(function (line) {
      const trimmed = line.trim()
      if (trimmed.charAt(0) !== "|") return
      const body = trimmed.charAt(trimmed.length - 1) === "|" ? trimmed.slice(1, -1) : trimmed.slice(1)
      const cells = body.split("|").map(function (cell) {
        return cell.trim()
      })
      if (!headerSeen) {
        headerSeen = true
        return
      }
      // 分隔行 |---|---| 跳过
      if (cells.every(function (cell) {
        return cell === "" || /^-+:?$/.test(cell)
      })) {
        return
      }
      if (cells.length < 2) return
      let tol = null
      if (cells.length >= 3) {
        const m = /tol\s*=\s*([0-9.eE+-]+)/.exec(cells[2])
        if (m) {
          const value = Number(m[1])
          if (!Number.isNaN(value)) tol = value
        }
      }
      cases.push({ input: cells[0], expect: cells[1], tol: tol })
    })
  return cases
}

/**
 * 解析「## 参考解法」里的代码块。
 * @param {string} text
 * @returns {{code: string, lang: string}}
 */
function parseSolution(text) {
  const fence = /```([A-Za-z0-9+#_-]*)\n([\s\S]*?)```/.exec(String(text || ""))
  if (!fence) return { code: "", lang: "" }
  return {
    code: fence[2].replace(/\n+$/, ""),
    lang: fence[1] || "",
  }
}

/**
 * markdown → Problem。
 * @param {string} text
 * @returns {{problem: object|null, warnings: string[]}}
 */
function parseProblemMarkdown(text) {
  const warnings = []
  const src = String(text || "").replace(/\r\n/g, "\n")

  let body = src
  let fm = {}
  const match = /^---\n([\s\S]*?)\n---\n?/.exec(src)
  if (match) {
    fm = parseFrontmatter(match[1])
    body = src.slice(match[0].length)
  } else {
    warnings.push("缺少 frontmatter")
  }

  const sections = splitSections(body)
  const extraSections = []
  Object.keys(sections).forEach(function (title) {
    if (KNOWN_SECTIONS.indexOf(title) === -1) {
      extraSections.push({ title: title, content: sections[title].trim() })
    }
  })

  const needsFillRaw = fm.needs_fill
  const solution = parseSolution(sections[SECTION_SOLUTION] || "")
  const problem = {
    id: fm.id === undefined ? "" : String(fm.id),
    source: fm.source === undefined ? "" : String(fm.source),
    title: fm.title === undefined ? "" : String(fm.title),
    difficulty: fm.difficulty === undefined ? "medium" : String(fm.difficulty),
    topics: normalizeTopics(fm.topics),
    tracks: normalizeTracks(fm.tracks),
    status: fm.status === undefined ? "todo" : String(fm.status),
    needsFill: needsFillRaw === true || needsFillRaw === "true",
    created: fm.created === undefined ? today() : String(fm.created),
    updated: fm.updated === undefined ? today() : String(fm.updated),
    statement: (sections[SECTION_STATEMENT] || "").trim(),
    cases: parseCases(sections[SECTION_CASES] || ""),
    solution: solution.code,
    solutionLang: solution.lang,
    extraSections: extraSections,
  }

  if (!fm.id) warnings.push("frontmatter 缺 id")
  if (!fm.title) warnings.push("frontmatter 缺 title")

  return { problem: problem, warnings: warnings }
}

/**
 * Problem → markdown。
 * @param {object} problem
 * @returns {string}
 */
function serializeProblemMarkdown(problem) {
  const frontmatter = serializeFrontmatter({
    id: problem.id,
    source: problem.source,
    title: problem.title,
    difficulty: problem.difficulty,
    topics: problem.topics,
    tracks: problem.tracks,
    status: problem.status,
    needs_fill: problem.needsFill ? "true" : "false",
    created: problem.created,
    updated: problem.updated,
  })

  const lines = []
  lines.push("---")
  lines.push(frontmatter)
  lines.push("---")
  lines.push("")
  lines.push("## " + SECTION_STATEMENT)
  lines.push("")
  lines.push(problem.statement || "")
  lines.push("")
  lines.push("## " + SECTION_CASES)
  lines.push("")
  lines.push("| input | expect |")
  lines.push("|---|---|")
  ;(problem.cases || []).forEach(function (item) {
    const tol = item.tol === null || item.tol === undefined ? "" : " tol=" + item.tol
    lines.push("| " + item.input + " | " + item.expect + " |" + tol)
  })
  lines.push("")
  lines.push("## " + SECTION_SOLUTION)
  lines.push("")
  if (problem.solution) {
    lines.push("```" + (problem.solutionLang || "cpp"))
    lines.push(problem.solution)
    lines.push("```")
  }
  lines.push("")

  ;(problem.extraSections || []).forEach(function (section) {
    lines.push("## " + section.title)
    lines.push("")
    lines.push(section.content || "")
    lines.push("")
  })

  return lines.join("\n")
}

module.exports = {
  SECTION_STATEMENT: SECTION_STATEMENT,
  SECTION_CASES: SECTION_CASES,
  SECTION_SOLUTION: SECTION_SOLUTION,
  parseFrontmatter: parseFrontmatter,
  serializeFrontmatter: serializeFrontmatter,
  splitSections: splitSections,
  parseCases: parseCases,
  parseSolution: parseSolution,
  parseProblemMarkdown: parseProblemMarkdown,
  serializeProblemMarkdown: serializeProblemMarkdown,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `4 / 4 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加题库 markdown 与 Problem 的双向转换

- core/bank/parse.js：手写 mini-YAML frontmatter 解析（标量/内联数组/块列表/引号）
- 用例表格解析：第三格支持 tol= 容差标记，列数不对的行跳过不报错
- 参考解法按代码块解析，带出语言标记
- 缺 frontmatter 只产告警不抛错；未识别小节原样保留
- Problem → markdown → Problem 往返等价，有测试钉住
- 测试：frontmatter、用例表、代码块、往返等价共 11 条断言"
git push origin main
```

---

## Task 4: SQLite 存储层

**Files:**
- Create: `projects/apps/algo-plan/server/db.js`
- Create: `projects/apps/algo-plan/tests/db.test.js`

**Interfaces:**
- Consumes: 无
- Produces:
  - `server/db.js` 导出 `openDb(filePath) -> DatabaseSync`（建目录 + 建表）、`createStore(db) -> store`、`SCHEMA`
  - `store` 的方法（后面每个 Task 都用这些，签名照抄）：
    - `getSetting(key, fallback?) -> string|null`
    - `setSetting(key, value)`
    - `allSettings() -> {key: value}`
    - `insertAttempt(attempt) -> number`（返回自增 id）
    - `listAttemptsByProblem(problemId) -> row[]`
    - `countAttempts() -> number`
    - `upsertReviewCard(card)` / `getReviewCard(problemId)` / `listDueCards(nowIso)` / `countReviewCards()`
    - `upsertTopic(topic)` / `listTopics()` / `countTopics()`
    - `close()`

  **attempt 对象字段名**（照设计文档 §3.3 的列名）：`problem_id, ts, language, code, verdict, passed_cases, total_cases, duration_ms, mode`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/db.test.js`：

```javascript
"use strict"
/**
 * db.test.js —— SQLite schema 与仓储函数
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { openDb, createStore } = require("../server/db.js")

function freshStore() {
  const db = openDb(":memory:")
  return { db: db, store: createStore(db) }
}

test("openDb 建出四张表", function () {
  const db = openDb(":memory:")
  const rows = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all()
  const names = rows.map(function (r) { return r.name })
  assert.ok(names.indexOf("attempts") !== -1, names.join(","))
  assert.ok(names.indexOf("review_cards") !== -1)
  assert.ok(names.indexOf("topics") !== -1)
  assert.ok(names.indexOf("settings") !== -1)
  db.close()
})

test("openDb 在文件路径下自动建目录", function () {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-db-"))
  const file = path.join(dir, "nested", "app.db")
  const db = openDb(file)
  assert.ok(fs.existsSync(file), "应创建数据库文件")
  db.close()
})

test("settings 读写与覆盖", function () {
  const { store } = freshStore()
  assert.strictEqual(store.getSetting("review.daily_quota_questions", "10"), "10")
  store.setSetting("review.daily_quota_questions", "20")
  assert.strictEqual(store.getSetting("review.daily_quota_questions"), "20")
  store.setSetting("review.daily_quota_questions", "15")
  assert.strictEqual(store.getSetting("review.daily_quota_questions"), "15")
  assert.deepStrictEqual(Object.keys(store.allSettings()), ["review.daily_quota_questions"])
})

test("attempts 写入后能按题号查回", function () {
  const { store } = freshStore()
  const id = store.insertAttempt({
    problem_id: "lc-00001",
    ts: "2026-11-11T10:00:00.000Z",
    language: "cpp",
    code: "int main(){}",
    verdict: "pass",
    passed_cases: 2,
    total_cases: 2,
    duration_ms: 120,
    mode: "solve",
  })
  assert.ok(id > 0, "应返回自增 id")
  assert.strictEqual(store.countAttempts(), 1)
  const rows = store.listAttemptsByProblem("lc-00001")
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].verdict, "pass")
  assert.strictEqual(rows[0].passed_cases, 2)
})

test("review_cards upsert 后覆盖旧值", function () {
  const { store } = freshStore()
  store.upsertReviewCard({
    problem_id: "lc-00001",
    easiness: 2.5,
    interval_days: 1,
    repetitions: 1,
    last_quality: 5,
    last_at: "2026-11-11T10:00:00.000Z",
    next_review_at: "2026-11-12T10:00:00.000Z",
    lapses: 0,
  })
  store.upsertReviewCard({
    problem_id: "lc-00001",
    easiness: 2.6,
    interval_days: 6,
    repetitions: 2,
    last_quality: 4,
    last_at: "2026-11-12T10:00:00.000Z",
    next_review_at: "2026-11-18T10:00:00.000Z",
    lapses: 0,
  })
  assert.strictEqual(store.countReviewCards(), 1)
  const card = store.getReviewCard("lc-00001")
  assert.strictEqual(card.interval_days, 6)
  assert.strictEqual(card.easiness, 2.6)
})

test("listDueCards 只返回已到期的卡片", function () {
  const { store } = freshStore()
  store.upsertReviewCard({
    problem_id: "due", easiness: 2.5, interval_days: 1, repetitions: 0,
    last_quality: null, last_at: null, next_review_at: "2026-11-01T00:00:00.000Z", lapses: 0,
  })
  store.upsertReviewCard({
    problem_id: "later", easiness: 2.5, interval_days: 6, repetitions: 1,
    last_quality: 4, last_at: null, next_review_at: "2027-01-01T00:00:00.000Z", lapses: 0,
  })
  const due = store.listDueCards("2026-12-01T00:00:00.000Z")
  assert.strictEqual(due.length, 1)
  assert.strictEqual(due[0].problem_id, "due")
})

test("topics 累加而不是覆盖", function () {
  const { store } = freshStore()
  store.upsertTopic({ id: "数组", first_pass: 1, attempts: 1, last_at: "2026-11-11T00:00:00.000Z", lapses: 0 })
  store.upsertTopic({ id: "数组", first_pass: 0, attempts: 1, last_at: "2026-11-12T00:00:00.000Z", lapses: 1 })
  const topics = store.listTopics()
  assert.strictEqual(topics.length, 1)
  assert.strictEqual(topics[0].first_pass, 1)
  assert.strictEqual(topics[0].attempts, 2)
  assert.strictEqual(topics[0].lapses, 1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../server/db.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/server/db.js`：

```javascript
"use strict"
/**
 * db.js —— node:sqlite schema 与仓储函数
 *
 * 四张表照设计文档 §3.3 原样落：
 *   attempts（作答流水）/ review_cards（复习调度）/ topics（知识点）/ settings（配置）
 *
 * node:sqlite 只接受 null / number / bigint / string / Uint8Array，
 * 所以布尔一律转 0/1，undefined 一律转 null。
 */

const fs = require("node:fs")
const path = require("node:path")

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
     first_pass INTEGER NOT NULL DEFAULT 0,
     attempts   INTEGER NOT NULL DEFAULT 0,
     last_at    TEXT,
     lapses     INTEGER NOT NULL DEFAULT 0
   )`,
  `CREATE TABLE IF NOT EXISTS settings (
     key   TEXT PRIMARY KEY,
     value TEXT NOT NULL
   )`,
]

/**
 * 打开数据库（不存在则建目录建库）并建表。
 * @param {string} filePath 文件路径；":memory:" 表示内存库（测试用）
 * @returns {import("node:sqlite").DatabaseSync}
 */
function openDb(filePath) {
  const target = filePath || ":memory:"
  if (target !== ":memory:") {
    fs.mkdirSync(path.dirname(target), { recursive: true })
  }
  const db = new DatabaseSync(target)
  SCHEMA.forEach(function (stmt) {
    db.exec(stmt)
  })
  return db
}

/**
 * 仓储层：把 SQL 收在一处，上层不写 SQL 字符串。
 * @param {import("node:sqlite").DatabaseSync} db
 */
function createStore(db) {
  return {
    close: function () {
      db.close()
    },

    /* ---------- settings ---------- */

    getSetting: function (key, fallback) {
      const row = db.prepare("SELECT value FROM settings WHERE key = ?").get(key)
      if (!row) return fallback === undefined ? null : fallback
      return row.value
    },

    setSetting: function (key, value) {
      db.prepare(
        "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
      ).run(key, String(value))
    },

    allSettings: function () {
      const rows = db.prepare("SELECT key, value FROM settings ORDER BY key").all()
      const out = {}
      rows.forEach(function (row) {
        out[row.key] = row.value
      })
      return out
    },

    /* ---------- attempts ---------- */

    insertAttempt: function (attempt) {
      const result = db
        .prepare(
          `INSERT INTO attempts(problem_id, ts, language, code, verdict, passed_cases, total_cases, duration_ms, mode)
           VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`
        )
        .run(
          String(attempt.problem_id),
          String(attempt.ts),
          String(attempt.language),
          String(attempt.code || ""),
          String(attempt.verdict),
          Number(attempt.passed_cases || 0),
          Number(attempt.total_cases || 0),
          Number(attempt.duration_ms || 0),
          String(attempt.mode || "solve")
        )
      return Number(result.lastInsertRowid)
    },

    listAttemptsByProblem: function (problemId) {
      return db
        .prepare("SELECT * FROM attempts WHERE problem_id = ? ORDER BY ts DESC, id DESC")
        .all(String(problemId))
    },

    countAttempts: function () {
      const row = db.prepare("SELECT COUNT(*) AS n FROM attempts").get()
      return Number(row.n)
    },

    /* ---------- review_cards ---------- */

    upsertReviewCard: function (card) {
      db.prepare(
        `INSERT INTO review_cards(problem_id, easiness, interval_days, repetitions, last_quality, last_at, next_review_at, lapses)
         VALUES(?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(problem_id) DO UPDATE SET
           easiness = excluded.easiness,
           interval_days = excluded.interval_days,
           repetitions = excluded.repetitions,
           last_quality = excluded.last_quality,
           last_at = excluded.last_at,
           next_review_at = excluded.next_review_at,
           lapses = excluded.lapses`
      ).run(
        String(card.problem_id),
        Number(card.easiness),
        Number(card.interval_days),
        Number(card.repetitions),
        card.last_quality === null || card.last_quality === undefined ? null : Number(card.last_quality),
        card.last_at === null || card.last_at === undefined ? null : String(card.last_at),
        String(card.next_review_at),
        Number(card.lapses || 0)
      )
    },

    getReviewCard: function (problemId) {
      return db.prepare("SELECT * FROM review_cards WHERE problem_id = ?").get(String(problemId))
    },

    listDueCards: function (nowIso) {
      return db
        .prepare("SELECT * FROM review_cards WHERE next_review_at <= ? ORDER BY next_review_at ASC")
        .all(String(nowIso))
    },

    countReviewCards: function () {
      const row = db.prepare("SELECT COUNT(*) AS n FROM review_cards").get()
      return Number(row.n)
    },

    /* ---------- topics ---------- */

    upsertTopic: function (topic) {
      db.prepare(
        `INSERT INTO topics(id, first_pass, attempts, last_at, lapses)
         VALUES(?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           first_pass = topics.first_pass + excluded.first_pass,
           attempts = topics.attempts + excluded.attempts,
           last_at = excluded.last_at,
           lapses = topics.lapses + excluded.lapses`
      ).run(
        String(topic.id),
        Number(topic.first_pass || 0),
        Number(topic.attempts || 0),
        topic.last_at === null || topic.last_at === undefined ? null : String(topic.last_at),
        Number(topic.lapses || 0)
      )
    },

    listTopics: function () {
      return db.prepare("SELECT * FROM topics ORDER BY id ASC").all()
    },

    countTopics: function () {
      const row = db.prepare("SELECT COUNT(*) AS n FROM topics").get()
      return Number(row.n)
    },
  }
}

module.exports = { SCHEMA: SCHEMA, openDb: openDb, createStore: createStore }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `5 / 5 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加 SQLite 存储层

- server/db.js：四张表照设计文档 §3.3 原样落 schema，附索引
- openDb 自动建目录建表；':memory:' 用于测试
- 仓储层把 SQL 收在一处：settings / attempts / review_cards / topics
- node:sqlite 只接受 null 与数值，布尔一律转 0/1
- 测试：建表、落盘、配置覆盖、流水写读、卡片 upsert、到期筛选、知识点累加"
git push origin main
```

---

## Task 5: learning 仓路径解析与 FileProvider

**Files:**
- Create: `projects/apps/algo-plan/core/paths.js`
- Create: `projects/apps/algo-plan/core/bank/provider.js`
- Create: `projects/apps/algo-plan/tests/provider.test.js`

**Interfaces:**
- Consumes: Task 2 的 `core/bank/problem.js`、Task 3 的 `core/bank/parse.js`
- Produces:
  - `core/paths.js` 导出 `resolveLearningRoot(env, override?) -> {root: string|null, ok: boolean, reason: string}`、`bankDir(learningRoot) -> string|null`
    - `ok === false` 时 `root === null`，`reason` 是中文说明（纯本地模式）
  - `core/bank/provider.js` 导出 `FileProvider`、`NullProvider`、`listMarkdownFiles(dir)`
    - `new FileProvider(bankDir | null)`
    - `await provider.list(filter?) -> Problem[]`，filter 支持 `{track, topic, difficulty, status, idPrefix}`
    - `await provider.get(id) -> Problem|undefined`
    - `await provider.put(problem) -> string`（返回写入的绝对路径；非法字段抛错）
    - `provider.stats() -> {fileCount, problemCount, warnings[]}`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/provider.test.js`：

```javascript
"use strict"
/**
 * provider.test.js —— FileProvider 读写 learning/bank
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { FileProvider } = require("../core/bank/provider.js")
const { createProblem } = require("../core/bank/problem.js")
const { serializeProblemMarkdown } = require("../core/bank/parse.js")

function tempBank() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-bank-"))
  return dir
}

function sampleProblem(id, overrides) {
  return createProblem(
    Object.assign(
      {
        id: id,
        source: "leetcode",
        title: "题目 " + id,
        difficulty: "easy",
        topics: ["数组"],
        tracks: ["interview"],
        statement: "题面 " + id,
        cases: [{ input: "1", expect: "1", tol: null }],
        solution: "int main(){}",
        solutionLang: "cpp",
      },
      overrides || {}
    )
  )
}

test("bank 目录不存在时 list 返回空数组而不是报错", async function () {
  const provider = new FileProvider(path.join(tempBank(), "not-exist"))
  assert.deepStrictEqual(await provider.list(), [])
  assert.strictEqual(await provider.get("lc-00001"), undefined)
})

test("bank 目录为 null（纯本地模式）时 list 返回空数组", async function () {
  const provider = new FileProvider(null)
  assert.deepStrictEqual(await provider.list(), [])
})

test("put 写入 learning/bank/<track>/<id>.md 并能读回", async function () {
  const bank = tempBank()
  const provider = new FileProvider(bank)
  const file = await provider.put(sampleProblem("lc-00001"))
  assert.strictEqual(file, path.join(bank, "interview", "lc-00001.md"))
  assert.ok(fs.existsSync(file))

  const got = await provider.get("lc-00001")
  assert.strictEqual(got.title, "题目 lc-00001")
  assert.strictEqual(got.cases.length, 1)
})

test("put 拒绝字段非法的题目", async function () {
  const provider = new FileProvider(tempBank())
  await assert.rejects(function () {
    return provider.put({ id: "bad" })
  })
})

test("list 支持按 track / topic / difficulty 过滤", async function () {
  const bank = tempBank()
  const provider = new FileProvider(bank)
  await provider.put(sampleProblem("lc-00001", { tracks: ["interview"], topics: ["数组"] }))
  await provider.put(sampleProblem("lc-00002", { tracks: ["advanced"], topics: ["图论"], difficulty: "hard" }))

  assert.strictEqual((await provider.list({})).length, 2)
  assert.strictEqual((await provider.list({ track: "advanced" })).length, 1)
  assert.strictEqual((await provider.list({ topic: "数组" })).length, 1)
  assert.strictEqual((await provider.list({ difficulty: "hard" })).length, 1)
  assert.strictEqual((await provider.list({ track: "advanced" }))[0].id, "lc-00002")
})

test("list 结果按 id 排序", async function () {
  const bank = tempBank()
  const provider = new FileProvider(bank)
  await provider.put(sampleProblem("lc-00003"))
  await provider.put(sampleProblem("lc-00001"))
  await provider.put(sampleProblem("lc-00002"))
  const ids = (await provider.list({})).map(function (p) { return p.id })
  assert.deepStrictEqual(ids, ["lc-00001", "lc-00002", "lc-00003"])
})

test("缺 id 的文件被跳过并计入告警，不影响其它题", async function () {
  const bank = tempBank()
  fs.mkdirSync(path.join(bank, "interview"), { recursive: true })
  fs.writeFileSync(path.join(bank, "interview", "broken.md"), "## 题面\n\n没有 frontmatter", "utf8")
  const provider = new FileProvider(bank)
  await provider.put(sampleProblem("lc-00001"))
  const list = await provider.list({})
  assert.strictEqual(list.length, 1)
  const stats = provider.stats()
  assert.strictEqual(stats.problemCount, 1)
  assert.ok(stats.warnings.some(function (w) { return w.indexOf("broken.md") !== -1 }), stats.warnings.join("|"))
})

test("写出的文件能再次解析回来（往返一致）", async function () {
  const bank = tempBank()
  const provider = new FileProvider(bank)
  const original = sampleProblem("lc-00001")
  await provider.put(original)
  const text = fs.readFileSync(path.join(bank, "interview", "lc-00001.md"), "utf8")
  const { parseProblemMarkdown } = require("../core/bank/parse.js")
  const parsed = parseProblemMarkdown(text).problem
  assert.strictEqual(parsed.id, original.id)
  assert.strictEqual(parsed.title, original.title)
  assert.deepStrictEqual(parsed.topics, original.topics)
  assert.strictEqual(parsed.solution, original.solution)
})

test("serializeProblemMarkdown 产出 frontmatter", function () {
  const text = serializeProblemMarkdown(sampleProblem("lc-00001"))
  assert.ok(text.indexOf("---\nid: lc-00001") === 0, text.slice(0, 40))
  assert.ok(text.indexOf("needs_fill: false") !== -1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/bank/provider.js'`

- [ ] **Step 3: 写 core/paths.js**

Create `projects/apps/algo-plan/core/paths.js`：

```javascript
"use strict"
/**
 * paths.js —— learning 仓根路径解析
 *
 * 不硬编码 learning 仓位置。只认环境变量 ALGO_PLAN_LEARNING_ROOT，
 * 取不到就降级为「纯本地模式」：只有 SQLite，不与 learning 仓同步。
 */

const fs = require("node:fs")
const path = require("node:path")

/**
 * 解析 learning 仓根目录。
 * @param {object} env 进程环境变量对象
 * @param {string} [override] 显式指定路径（优先于环境变量，测试用）
 * @returns {{root: string|null, ok: boolean, reason: string}}
 */
function resolveLearningRoot(env, override) {
  const raw = override !== undefined && override !== null
    ? override
    : (env || process.env).ALGO_PLAN_LEARNING_ROOT

  if (raw === undefined || raw === null || String(raw).trim() === "") {
    return {
      root: null,
      ok: false,
      reason: "未设置 ALGO_PLAN_LEARNING_ROOT，进入纯本地模式（不与 learning 仓同步）",
    }
  }

  const abs = path.resolve(String(raw).trim())
  if (!fs.existsSync(abs)) {
    return { root: null, ok: false, reason: "ALGO_PLAN_LEARNING_ROOT 指向的目录不存在：" + abs }
  }
  if (!fs.statSync(abs).isDirectory()) {
    return { root: null, ok: false, reason: "ALGO_PLAN_LEARNING_ROOT 不是目录：" + abs }
  }
  return { root: abs, ok: true, reason: "" }
}

/**
 * 题库目录：learning 仓下的 bank/。
 * @param {string|null} learningRoot
 * @returns {string|null}
 */
function bankDir(learningRoot) {
  if (!learningRoot) return null
  return path.join(learningRoot, "bank")
}

module.exports = { resolveLearningRoot: resolveLearningRoot, bankDir: bankDir }
```

- [ ] **Step 4: 写 core/bank/provider.js**

Create `projects/apps/algo-plan/core/bank/provider.js`：

```javascript
"use strict"
/**
 * provider.js —— 题库 provider 接口 + FileProvider
 *
 * 接口（设计文档 §3.6）：
 *   list(filter)  -> Promise<Problem[]>
 *   get(id)       -> Promise<Problem|undefined>
 *   put(problem)  -> Promise<void>
 *
 * 现在只有 FileProvider（读写 learning/bank/*.md）。
 * 将来换 DbProvider（查 engine/db）只需再加一个实现，上层一行不用改。
 */

const fs = require("node:fs")
const path = require("node:path")

const { parseProblemMarkdown, serializeProblemMarkdown } = require("./parse.js")
const { validateProblem, toSummary } = require("./problem.js")

/**
 * 递归列出目录下所有 .md 文件。
 * @param {string} dir
 * @returns {string[]} 绝对路径
 */
function listMarkdownFiles(dir) {
  const out = []
  let entries
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
  } catch (e) {
    return out
  }
  entries.forEach(function (entry) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      out.push.apply(out, listMarkdownFiles(abs))
    } else if (entry.isFile() && /\.md$/i.test(entry.name)) {
      out.push(abs)
    }
  })
  return out
}

/**
 * 题库 provider。
 */
class FileProvider {
  /**
   * @param {string|null} bankDir 题库根目录；null 表示纯本地模式（无题库）
   */
  constructor(bankDir) {
    this.bankDir = bankDir || null
    this.index = null
    this.warnings = []
  }

  /**
   * 扫描题库目录，建 id → 文件路径的索引。
   * @returns {{byId: Object<string,string>, files: string[], warnings: string[]}}
   */
  buildIndex() {
    const byId = {}
    const files = []
    const warnings = []
    if (!this.bankDir || !fs.existsSync(this.bankDir)) {
      this.index = { byId: byId, files: files, warnings: warnings }
      return this.index
    }
    listMarkdownFiles(this.bankDir).forEach(function (file) {
      files.push(file)
      let text
      try {
        text = fs.readFileSync(file, "utf8")
      } catch (e) {
        warnings.push("读取失败：" + file + "（" + e.message + "）")
        return
      }
      const parsed = parseProblemMarkdown(text)
      if (!parsed.problem || !parsed.problem.id) {
        warnings.push("缺少 id，已跳过：" + file)
        return
      }
      if (byId[parsed.problem.id]) {
        warnings.push("id 重复：" + parsed.problem.id + "（保留先出现的）")
        return
      }
      byId[parsed.problem.id] = file
    })
    this.index = { byId: byId, files: files, warnings: warnings }
    return this.index
  }

  /** 取索引（懒建一次） */
  getIndex() {
    if (!this.index) this.buildIndex()
    return this.index
  }

  /**
   * 列出题目。
   * @param {{track?: string, topic?: string, difficulty?: string, status?: string, idPrefix?: string}} filter
   * @returns {Promise<object[]>}
   */
  async list(filter) {
    const f = filter || {}
    if (!this.bankDir || !fs.existsSync(this.bankDir)) return []
    const index = this.getIndex()
    const out = []
    const files = index.files
    for (const file of files) {
      let problem
      try {
        problem = parseProblemMarkdown(fs.readFileSync(file, "utf8")).problem
      } catch (e) {
        continue
      }
      if (!problem || !problem.id) continue
      if (f.track && problem.tracks.indexOf(f.track) === -1) continue
      if (f.topic && problem.topics.indexOf(f.topic) === -1) continue
      if (f.difficulty && problem.difficulty !== f.difficulty) continue
      if (f.status && problem.status !== f.status) continue
      if (f.idPrefix && problem.id.indexOf(f.idPrefix + "-") !== 0) continue
      out.push(problem)
    }
    out.sort(function (a, b) {
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
    })
    return out
  }

  /**
   * 取一道题。
   * @param {string} id
   * @returns {Promise<object|undefined>}
   */
  async get(id) {
    if (!this.bankDir || !fs.existsSync(this.bankDir)) return undefined
    const index = this.getIndex()
    const file = index.byId[id]
    if (!file) return undefined
    const parsed = parseProblemMarkdown(fs.readFileSync(file, "utf8"))
    return parsed.problem
  }

  /**
   * 写入一道题：learning/bank/<track>/<id>.md
   * @param {object} problem
   * @returns {Promise<string>} 写入的绝对路径
   */
  async put(problem) {
    if (!this.bankDir) {
      throw new Error("未连接 learning 仓，无法写入题库（纯本地模式只读 SQLite）")
    }
    const check = validateProblem(problem)
    if (!check.ok) {
      throw new Error("题目字段非法：" + check.errors.join("；"))
    }
    const track = problem.tracks[0] || "misc"
    const dir = path.join(this.bankDir, track)
    fs.mkdirSync(dir, { recursive: true })
    const file = path.join(dir, problem.id + ".md")
    fs.writeFileSync(file, serializeProblemMarkdown(problem), "utf8")
    this.index = null
    return file
  }

  /**
   * 题库概况：文件数、解析告警。
   * @returns {{fileCount: number, problemCount: number, warnings: string[]}}
   */
  stats() {
    const index = this.getIndex()
    return {
      fileCount: index.files.length,
      problemCount: Object.keys(index.byId).length,
      warnings: index.warnings,
    }
  }
}

/**
 * 一个只返回空集的 provider，用于纯本地模式。
 */
class NullProvider {
  async list() {
    return []
  }
  async get() {
    return undefined
  }
  async put() {
    throw new Error("纯本地模式：没有题库可写")
  }
  stats() {
    return { fileCount: 0, problemCount: 0, warnings: [] }
  }
}

module.exports = {
  FileProvider: FileProvider,
  NullProvider: NullProvider,
  listMarkdownFiles: listMarkdownFiles,
  toSummary: toSummary,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `6 / 6 套件通过`，退出码 0

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加题库 provider 与 learning 仓路径解析

- core/paths.js：只认 ALGO_PLAN_LEARNING_ROOT，取不到就降级为纯本地模式并给出中文原因
- core/bank/provider.js：Provider 接口 + FileProvider，读写 learning/bank/<track>/<id>.md
- 题库目录缺失时 list 返回空数组、get 返回 undefined，不抛错
- 缺 id 的文件跳过并计入告警，不影响其它题；结果按 id 排序
- 测试：目录缺失、写入读回、过滤、排序、坏文件容错、往返一致共 9 条断言"
git push origin main
```

---

## Task 6: M1 的三个接口与页面接线

**Files:**
- Create: `projects/apps/algo-plan/server/api.js`
- Create: `projects/apps/algo-plan/web/app.js`
- Create: `projects/apps/algo-plan/tests/api.test.js`
- 不需要修改 `server/app.js`——Task 1 已经把 API 挂载点写好了（`createApp` 里 `require("./api.js").buildRoutes(...)`）

**Interfaces:**
- Consumes: Task 2 的 `toSummary`、Task 4 的 `store`、Task 5 的 `provider` 与 `learning`
- Produces:
  - `server/api.js` 导出 `buildRoutes(ctx) -> Array<{method, pattern, handler}>`、`SAMPLE_CASE_COUNT = 2`
  - `ctx` 的形状：`{store, provider, learning, sendJson}`——`sendJson` 由 `server/app.js` 注入
  - 三个接口的响应形状（**M4 还要往这套形状上加字段，不要另起炉灶**）：

    | 接口 | 响应 |
    |---|---|
    | `GET /api/health` | `{ok, node, learning: {ok, root, reason}, bank: {fileCount, problemCount, warnings}, attempts}` |
    | `GET /api/bank?track=&topic=&difficulty=&status=&prefix=&limit=` | `{total, items: [摘要]}` |
    | `GET /api/problem/:id` | `{id, title, source, difficulty, topics, tracks, status, needsFill, statement, cases: {sample, total}}` |

    **单题接口不返回 `solution` / `solutionLang`**（G14 防作弊）。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/api.test.js`：

```javascript
"use strict"
/**
 * api.test.js —— M1 的三个接口：健康检查、题库列表、单题详情
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")

/** 造一个带一道题的 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-learning-"))
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
      "| 3,2,4, 6 | 1,2 |",
      "| 3,3,0,0,0, 6 | 0,1 |",
      "",
      "## 参考解法",
      "",
      "```cpp",
      "int main() { return 0; }",
      "```",
      "",
    ].join("\n"),
    "utf8"
  )
  return root
}

async function withApp(fn, opts) {
  const app = createApp(
    Object.assign({ dbPath: ":memory:", learningRoot: tempLearning() }, opts || {})
  )
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port)
  } finally {
    await app.close()
  }
}

test("GET /api/health 返回运行状态", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/health")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.strictEqual(body.ok, true)
    assert.strictEqual(body.learning.ok, true)
    assert.strictEqual(body.bank.problemCount, 1)
    assert.strictEqual(body.attempts, 0)
  })
})

test("未设置 learning 仓时降级为纯本地模式", async function () {
  const app = createApp({ dbPath: ":memory:", learningRoot: "", env: {} })
  const port = await app.listen(0)
  try {
    const res = await fetch("http://127.0.0.1:" + port + "/api/health")
    const body = await res.json()
    assert.strictEqual(body.learning.ok, false)
    assert.strictEqual(body.learning.root, null)
    assert.strictEqual(body.bank.problemCount, 0)
  } finally {
    await app.close()
  }
})

test("GET /api/bank 返回题目摘要", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/bank")
    const body = await res.json()
    assert.strictEqual(body.total, 1)
    assert.strictEqual(body.items[0].id, "lc-00001")
    assert.strictEqual(body.items[0].title, "两数之和")
    assert.strictEqual(body.items[0].statement, undefined, "列表不应带题面")
  })
})

test("GET /api/bank 支持 track 过滤", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/bank?track=advanced")
    const body = await res.json()
    assert.strictEqual(body.total, 0)
  })
})

test("GET /api/problem/:id 返回题面与样例用例", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/problem/lc-00001")
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.strictEqual(body.id, "lc-00001")
    assert.strictEqual(body.statement, "给定整数数组与目标值。")
    assert.strictEqual(body.cases.total, 3)
    assert.strictEqual(body.cases.sample.length, 2)
  })
})

test("单题接口不泄露参考解法", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/problem/lc-00001")
    const raw = await res.text()
    assert.strictEqual(raw.indexOf("int main"), -1, "响应里不应出现参考解法")
    const body = JSON.parse(raw)
    assert.strictEqual(body.solution, undefined)
  })
})

test("单题接口最多暴露 2 个样例用例，其余用例不外泄", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/problem/lc-00001")
    const body = await res.json()
    assert.strictEqual(body.cases.total, 3)
    assert.strictEqual(body.cases.sample.length, 2)
    const raw = await fetch(base + "/api/problem/lc-00001").then(function (r) { return r.text() })
    assert.strictEqual(raw.indexOf("3,3,0,0,0"), -1, "第 3 个用例不应出现在响应里")
  })
})

test("GET /api/problem/:id 题目不存在返回 404", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/problem/lc-99999")
    assert.strictEqual(res.status, 404)
    const body = await res.json()
    assert.strictEqual(body.error, "题目不存在")
  })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../server/api.js'`

- [ ] **Step 3: 写 server/api.js**

Create `projects/apps/algo-plan/server/api.js`：

```javascript
"use strict"
/**
 * api.js —— HTTP 接口层
 *
 * M1 只实现三个接口：健康检查、题库列表、单题详情。
 * 剩下的（推下一题、提交判题、复习评分、轮次写回）分别属于 M2–M4。
 *
 * 防作弊规则（设计文档 §7.2）：单题接口只返回前 2 个样例用例 + 用例总数，
 * 不返回全部用例、不返回参考解法。
 */

const { toSummary } = require("../core/bank/problem.js")

/** 题面接口最多暴露几个样例用例 */
const SAMPLE_CASE_COUNT = 2

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

  return routes
}

module.exports = { buildRoutes: buildRoutes, SAMPLE_CASE_COUNT: SAMPLE_CASE_COUNT }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `7 / 7 套件通过`，退出码 0

- [ ] **Step 5: 写 web/app.js**

Create `projects/apps/algo-plan/web/app.js`：

```javascript
"use strict"
/**
 * app.js —— 前端逻辑（M1：只渲染「今日」页的骨架与题库概览）
 *
 * 原生 JS，无构建步骤。后续里程碑在这里接作答 / 复习 / 轮次 / 诊断页。
 */

/** 极简 DOM 构造器 */
function el(tag, attrs, children) {
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

/** 取 JSON，失败时抛出带中文说明的错误 */
async function getJson(url) {
  const res = await fetch(url)
  const body = await res.json()
  if (!res.ok) {
    throw new Error((body && body.error) || "请求失败：" + res.status)
  }
  return body
}

/** 渲染健康状态面板 */
function renderHealth(health) {
  const learning = health.learning || {}
  const bank = health.bank || {}
  const badge = learning.ok
    ? el("span", { class: "badge ok", text: "已连接 learning 仓" })
    : el("span", { class: "badge warn", text: "纯本地模式" })
  const rows = [
    el("div", {}, [document.createTextNode("Node："), el("span", { text: health.node || "?" })]),
    el("div", {}, [document.createTextNode("题库题目数："), el("span", { text: String(bank.problemCount || 0) })]),
    el("div", {}, [document.createTextNode("作答流水条数："), el("span", { text: String(health.attempts || 0) })]),
    el("div", {}, [document.createTextNode("learning 仓："), el("span", { text: learning.root || "（未连接）" })]),
  ]
  return el("section", { class: "panel" }, [
    el("h2", { text: "运行状态" }),
    el("div", { class: "kv" }, rows),
    el("p", { class: "muted", text: learning.reason || "" }),
  ])
}

/** 渲染题库列表 */
function renderBank(bank) {
  const items = (bank && bank.items) || []
  const rows = items.map(function (item) {
    const topics = (item.topics || []).map(function (t) {
      return el("span", { class: "badge", text: t })
    })
    return el("tr", {}, [
      el("td", { text: item.id }),
      el("td", { text: item.title }),
      el("td", { text: item.difficulty }),
      el("td", {}, topics),
      el("td", {}, [el("span", { class: item.needsFill ? "badge warn" : "badge", text: item.needsFill ? "待补全" : item.status })]),
    ])
  })
  return el("section", { class: "panel" }, [
    el("h2", { text: "题库（" + (bank ? bank.total : 0) + "）" }),
    items.length === 0
      ? el("p", { class: "muted", text: "题库还是空的。设置 ALGO_PLAN_LEARNING_ROOT 后运行 node tools/seed-bank.js 导入样板题。" })
      : el("table", {}, [
          el("thead", {}, [
            el("tr", {}, [
              el("th", { text: "ID" }),
              el("th", { text: "标题" }),
              el("th", { text: "难度" }),
              el("th", { text: "知识点" }),
              el("th", { text: "状态" }),
            ]),
          ]),
          el("tbody", {}, rows),
        ]),
  ])
}

/** 主渲染 */
async function render() {
  const view = document.getElementById("view")
  view.textContent = ""
  try {
    const health = await getJson("/api/health")
    const bank = await getJson("/api/bank")
    view.appendChild(renderHealth(health))
    view.appendChild(renderBank(bank))
  } catch (err) {
    view.appendChild(
      el("section", { class: "panel" }, [
        el("h2", { text: "加载失败" }),
        el("p", { class: "error", text: String(err.message || err) }),
      ])
    )
  }
}

document.addEventListener("DOMContentLoaded", function () {
  render()
})
```

- [ ] **Step 6: 跑测试确认通过（前端语法自检 + 后端全绿）**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node --check web/app.js && node tests/run-all.js
```

Expected: `node --check` 无输出；`7 / 7 套件通过`

- [ ] **Step 7: 真起一次服务，人工看一眼页面**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

另开一个终端：

```bash
curl -s http://127.0.0.1:5173/api/health
curl -s http://127.0.0.1:5173/api/bank | head -c 400
```

浏览器打开 `http://127.0.0.1:5173/`，应看到「运行状态」与「题库」两个面板。

Expected: `/api/health` 返回 JSON；页面显示题库题目数（`learning/bank/` 还没建时显示 0，属正常）

- [ ] **Step 8: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 接线 M1 的三个接口与今日页

- server/api.js：/api/health、/api/bank、/api/problem/:id
- 单题接口只回前 2 个样例用例 + 用例总数，不回参考解法（防作弊）
- 题目不存在返回 404 JSON
- web/app.js：原生 JS 渲染运行状态与题库列表，无构建步骤
- 测试：三个接口 8 条断言（含纯本地模式降级与用例不外泄）"
git push origin main
```

---

## Task 7: 样板题、导入工具、端到端验收与 README

**Files:**
- Create: `projects/apps/algo-plan/fixtures/seed-bank/interview/lc-00001.md`
- Create: `projects/apps/algo-plan/fixtures/seed-bank/fundamentals/self-00001.md`
- Create: `projects/apps/algo-plan/tools/seed-bank.js`
- Create: `projects/apps/algo-plan/tests/e2e.test.js`
- Create: `projects/apps/algo-plan/README.md`

**Interfaces:**
- Consumes: Task 3 的 `parseProblemMarkdown`、Task 2 的 `validateProblem`、Task 5 的 `resolveLearningRoot`
- Produces:
  - `tools/seed-bank.js` 导出 `run(opts) -> {written: string[], skipped: string[], errors: string[]}`、`listFixtures(dir)`
    - `opts`：`{env, dryRun, force, fixturesDir}`
  - `learning/bank/<track>/<id>.md` 的**第一批真实题目文件**（Task 7 手工导入一次）

- [ ] **Step 1: 写失败的端到端测试**

Create `projects/apps/algo-plan/tests/e2e.test.js`：

```javascript
"use strict"
/**
 * e2e.test.js —— 端到端：导入样板题 → 起服务 → 打接口 → 校验落盘
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")
const seed = require("../tools/seed-bank.js")

function tempLearning() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-e2e-"))
}

test("样板题能导入 learning 仓的 bank/", function () {
  const root = tempLearning()
  const result = seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root } })
  assert.deepStrictEqual(result.errors, [])
  assert.strictEqual(result.written.length, 2)
  assert.ok(fs.existsSync(path.join(root, "bank", "interview", "lc-00001.md")))
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "self-00001.md")))
})

test("重复导入默认跳过，--force 才覆盖", function () {
  const root = tempLearning()
  seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root } })
  const again = seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root } })
  assert.strictEqual(again.written.length, 0)
  assert.strictEqual(again.skipped.length, 2)

  const forced = seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root }, force: true })
  assert.strictEqual(forced.written.length, 2)
})

test("未设置 learning 仓时导入报错而不是静默成功", function () {
  const result = seed.run({ env: {} })
  assert.strictEqual(result.written.length, 0)
  assert.strictEqual(result.errors.length, 1)
})

test("端到端：导入 → 起服务 → 打接口", async function () {
  const root = tempLearning()
  seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root } })

  const app = createApp({
    dbPath: path.join(root, "app.db"),
    learningRoot: root,
    env: { ALGO_PLAN_LEARNING_ROOT: root },
  })
  const port = await app.listen(0)
  const base = "http://127.0.0.1:" + port
  try {
    const health = await (await fetch(base + "/api/health")).json()
    assert.strictEqual(health.ok, true)
    assert.strictEqual(health.learning.ok, true)
    assert.strictEqual(health.learning.root, root)
    assert.strictEqual(health.bank.problemCount, 2)

    const bank = await (await fetch(base + "/api/bank")).json()
    assert.strictEqual(bank.total, 2)
    assert.deepStrictEqual(
      bank.items.map(function (item) { return item.id }),
      ["lc-00001", "self-00001"]
    )

    const problem = await (await fetch(base + "/api/problem/self-00001")).json()
    assert.strictEqual(problem.title, "字符串反转")
    assert.strictEqual(problem.cases.total, 2)
    assert.strictEqual(problem.solution, undefined)
  } finally {
    await app.close()
  }
})

test("端到端：SQLite 文件真的落盘了", function () {
  const root = tempLearning()
  seed.run({ env: { ALGO_PLAN_LEARNING_ROOT: root } })
  const dbPath = path.join(root, "app.db")
  const app = createApp({ dbPath: dbPath, learningRoot: root, env: {} })
  return app.close().then(function () {
    assert.ok(fs.existsSync(dbPath), "应生成 SQLite 文件")
  })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../tools/seed-bank.js'`

- [ ] **Step 3: 写样板题**

Create `projects/apps/algo-plan/fixtures/seed-bank/interview/lc-00001.md`：

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

给定一个整数数组 `nums` 和一个整数 `target`，请在数组中找出**和为目标值**的两个整数，
并返回它们的下标。

可以假设每种输入只会对应一个答案，且同一个元素不能重复使用。

## 测试用例

| input | expect |
|---|---|
| [2,7,11,15], 9 | [0,1] |
| [3,2,4], 6 | [1,2] |

## 参考解法

```cpp
#include <iostream>
#include <vector>
#include <unordered_map>
using namespace std;

int main() {
    vector<int> nums = {2, 7, 11, 15};
    int target = 9;
    unordered_map<int, int> seen;
    for (int i = 0; i < (int)nums.size(); ++i) {
        auto it = seen.find(target - nums[i]);
        if (it != seen.end()) {
            cout << it->second << "," << i << endl;
            return 0;
        }
        seen[nums[i]] = i;
    }
    return 0;
}
```
````

Create `projects/apps/algo-plan/fixtures/seed-bank/fundamentals/self-00001.md`：

````markdown
---
id: self-00001
source: self
title: 字符串反转
difficulty: easy
topics: [字符串]
tracks: [fundamentals]
status: todo
needs_fill: false
created: 2026-11-11
updated: 2026-11-11
---
## 题面

给定一个字符串 `s`，返回它的反转结果。

空串按原样返回。

## 测试用例

| input | expect |
|---|---|
| hello | olleh |
| 练字 | 字练 |

## 参考解法

```python
s = input().strip()
print(s[::-1])
```
````

- [ ] **Step 4: 写 tools/seed-bank.js**

Create `projects/apps/algo-plan/tools/seed-bank.js`：

```javascript
"use strict"
/**
 * seed-bank.js —— 把 fixtures/seed-bank/ 里的样板题导入 learning 仓的 bank/
 *
 * 用法：
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/seed-bank.js
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/seed-bank.js --dry-run
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/seed-bank.js --force
 *
 * 规则：
 *   - 已存在的文件默认不覆盖（--force 才覆盖）
 *   - 导入前先解析并校验题目，格式不合法的直接报错退出
 *   - 绝不自动 git commit
 */

const fs = require("node:fs")
const path = require("node:path")

const { resolveLearningRoot } = require("../core/paths.js")
const { parseProblemMarkdown } = require("../core/bank/parse.js")
const { validateProblem } = require("../core/bank/problem.js")

const FIXTURES_DIR = path.resolve(__dirname, "..", "fixtures", "seed-bank")

/**
 * 递归列出 fixtures 下所有 .md。
 */
function listFixtures(dir) {
  const out = []
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (entry) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push.apply(out, listFixtures(abs))
    else if (entry.isFile() && /\.md$/i.test(entry.name)) out.push(abs)
  })
  return out
}

/**
 * 主流程。
 * @param {{env?: object, dryRun?: boolean, force?: boolean, fixturesDir?: string}} opts
 * @returns {{written: string[], skipped: string[], errors: string[]}}
 */
function run(opts) {
  const options = opts || {}
  const learning = resolveLearningRoot(options.env || process.env)
  if (!learning.ok) {
    return { written: [], skipped: [], errors: [learning.reason] }
  }

  const bankDir = path.join(learning.root, "bank")
  const fixturesDir = options.fixturesDir || FIXTURES_DIR
  const written = []
  const skipped = []
  const errors = []

  listFixtures(fixturesDir).forEach(function (file) {
    const parsed = parseProblemMarkdown(fs.readFileSync(file, "utf8"))
    const problem = parsed.problem
    const check = validateProblem(problem)
    if (!check.ok) {
      errors.push(path.basename(file) + "：字段非法（" + check.errors.join("；") + "）")
      return
    }
    const track = problem.tracks[0] || "misc"
    const target = path.join(bankDir, track, problem.id + ".md")
    if (fs.existsSync(target) && !options.force) {
      skipped.push(target)
      return
    }
    if (!options.dryRun) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.copyFileSync(file, target)
    }
    written.push(target)
  })

  return { written: written, skipped: skipped, errors: errors }
}

function main() {
  const argv = process.argv.slice(2)
  const dryRun = argv.indexOf("--dry-run") !== -1
  const force = argv.indexOf("--force") !== -1
  const result = run({ dryRun: dryRun, force: force })

  if (result.errors.length > 0) {
    console.error("导入失败：")
    result.errors.forEach(function (line) {
      console.error("  · " + line)
    })
    process.exit(1)
  }
  console.log((dryRun ? "（试运行）将要写入：" : "已写入：") + result.written.length + " 道题")
  result.written.forEach(function (line) {
    console.log("  + " + line)
  })
  if (result.skipped.length > 0) {
    console.log("已存在跳过：" + result.skipped.length + " 道（要覆盖加 --force）")
  }
}

if (require.main === module) {
  main()
}

module.exports = { run: run, listFixtures: listFixtures, FIXTURES_DIR: FIXTURES_DIR }
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `8 / 8 套件通过`，退出码 0

- [ ] **Step 6: 写 README.md**

Create `projects/apps/algo-plan/README.md`：

`````markdown
# algo-plan · 算法能力提升计划 App

本机运行的算法学习助手：本地静态题库打底，LLM 做增强，判题走真实编译执行，
进度与错题写回 learning 仓进 git。

当前进度：**M1 骨架**（服务起得来 / SQLite schema / 题库 md 解析 / 页面壳）。
判题、复习、轮次、诊断、LLM 属于 M2–M6，尚未实现。

## 快速开始

需要 Node ≥ 24（用到内置 `node:sqlite`）。零 npm 依赖、零构建。

```bash
# 跑测试
node tests/run-all.js

# 接上 learning 仓并启动
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node server/main.js
# 打开 http://127.0.0.1:5173
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
├── core/            纯函数层：Problem 模型、markdown 解析、provider、路径解析
├── server/          组合根、路由、API、SQLite 存储
├── judge/           判题执行器（M3 才建）
├── web/             原生 JS 单页（无构建）
├── tools/           seed-bank.js：把样板题导入 learning 仓
├── fixtures/        样板题
└── tests/           node:test 套件，一个命令跑全部
```

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

## 归属

- 服务端、判题器、前端、测试 → `projects/apps/algo-plan/`（本仓）
- 题目本体、轮次清单、错题订正 → `learning/bank/`、`learning/progress/`、`learning/notes/`（学习仓）
`````

- [ ] **Step 7: 跑全量测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `8 / 8 套件通过`，退出码 0

- [ ] **Step 8: 导入样板题到真实 learning 仓（一次性动作）**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning node tools/seed-bank.js --dry-run
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning node tools/seed-bank.js
```

Expected: 先打印「（试运行）将要写入：2 道题」，再打印「已写入：2 道题」，
并在 `learning/bank/` 下生成 `interview/lc-00001.md` 与 `fundamentals/self-00001.md`。

> **这一步会往 learning 仓写入新文件。** 写不写、什么时候提交，由你决定——
> **app 和本计划都不会自动 `git commit`**（G11）。

- [ ] **Step 9: 端到端真跑一次**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

浏览器打开 `http://127.0.0.1:5173/`，应看到「题库（2）」。

- [ ] **Step 10: 提交并推送（app 仓）**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加样板题导入工具、端到端测试与 README

- tools/seed-bank.js：把 fixtures/seed-bank/ 导入 learning/bank/<track>/<id>.md
- 导入前解析并校验题目，格式不合法直接报错退出；默认不覆盖已存在的题
- fixtures/seed-bank/：2 道样板题（C++ 与 Python 各一）
- tests/e2e.test.js：导入 → 起服务 → 打接口 → 校验 SQLite 落盘
- README.md：快速开始、环境变量、题库格式、接口、测试说明"
git push origin main
```

- [ ] **Step 11: 更新父仓的 submodule 指针**

M1 的代码在 `projects` 子模块里，父仓 `StillEvolving` 记的是子模块指针，要跟着更新：

```bash
cd /c/code/StillEvolving
git add projects
git commit -m "chore(submodule): 更新 projects 子模块指针（algo-plan M1 骨架）"
git push origin main
```

---

## M1 验收清单

全部满足才算 M1 完成：

| # | 验收项 | 怎么验 |
|---|---|---|
| 1 | 服务起得来 | `node server/main.js` 打印启动地址 |
| 2 | 测试全绿 | `node tests/run-all.js` → `8 / 8 套件通过` |
| 3 | 零 npm 依赖 | `package.json` 无 `dependencies`；`node_modules/` 不存在 |
| 4 | SQLite schema 就位 | 四张表 `attempts` / `review_cards` / `topics` / `settings` 存在 |
| 5 | 题库 md 能解析 | `GET /api/problem/lc-00001` 返回题面与样例用例 |
| 6 | 页面壳有数据 | 首页显示「运行状态」与「题库（2）」 |
| 7 | 纯本地模式可降级 | 不设 `ALGO_PLAN_LEARNING_ROOT` 启动，`/api/health` 返回 `learning.ok === false` |
| 8 | 不泄露答案 | 单题接口响应里搜不到 `int main` |
| 9 | 没碰 learning 的 git | `git -C learning status` 只多出 `bank/`，无自动 commit |

---

## 后续里程碑备忘（M2–M4，写计划时直接用）

这些是勘察 learning 仓与 projects 仓时确认的事实，**写 M2–M4 计划时先看这里**，
省得重新摸一遍。

### M2 题库

- **死脚本在 `projects/scripts/`**：`gen-practice-data.js`（内联 255 题）、`expand-practice.js`（内联 ~992 题，
  25 个分类）、`split-practice-data.js`。它们都指向已删除的 `project/reading-radar/data/app/practice-data.js`，
  直接跑会 ENOENT——题目清单**内联在脚本源码里**，可以改写成导入器。
- 数据结构：`{title, platform: "leetcode"|"nowcoder", problemId, difficulty: "easy"|"medium", tags: [中文标签]}`，
  重复标记是 `repeat: true`。**难度只有 easy/medium，没有 hard**，也**没有任何题面与测试用例**——
  这 1249 条全是「纯元数据」，导入后 `needs_fill` 占比接近 100%。
- 分类 slug 共 25 个（`array`/`hash-table`/`dp-basic`/`graph`/`sliding-window`…），
  到设计文档四条 track 的映射**脚本里没有**，得自己定。
- **存量题解**：`learning/code-solutions/c/src/{c,cpp}/leetcode_<起>_<止>.c`（按题号范围分文件，
  靠 `// leetcode 56` 注释定位题目）与 `learning/algo-c/problems/leetcode_<id>/`（8 个目录，一题一文件）。
  **全是纯代码，没有题面、没有用例、没有难度、没有标签。**
- `learning/algo-c/{sliding_window,prefix_sum}/README.md` 里有两张「题号 / 题目 / 难度」表，
  但难度是中文（简单/中等），相对链接也是错的（少了 `problems/` 一层）——M2 可以顺手修。
- **`learning/bank/` 是新目录**（M1 建的）。注意 `learning/.gitignore` 忽略 `data/`，
  所以题目直接放 `learning/bank/<track>/<id>.md`，**不要**建 `learning/bank/data/`。

### M3 判题

- **本机 `python3` 是 Microsoft Store 的别名占位符**，`python3 --version` 没有输出，
  真正能用的是 `python`（3.11.15）与 `py -3`（3.12.3）。
  判题器解析解释器时必须按 `python3` → `python` → `py -3` 依次试，
  或者让用户在设置里指定——**别写死 `python3`**。
- `g++` 是 mingw64 14.2.0，`-std=c++17` 可用。
- **LeetCode 风格的存量题解没有 `main()`**（是 `class Solution { ... }`）。
  判题契约要么要求用户自己写 `main()`，要么注入 `main` 去调 `Solution::method`——
  后者需要知道方法名，做不到自动生成。设计文档 §5.1 假设的是「stdin 进、stdout 出」的裸程序，
  **M3 计划里必须把这个契约写死**。
- 超时杀进程树：Windows 用 `taskkill /T /F`，POSIX 用进程组 kill（G9）。

### M4 闭环

- **SM-2 直接搬** `projects/apps/knowledge-hub/core/review.js`（95 行纯函数，已有单测）：
  `calculateNextReview(record, quality)`、`isDue`、`filterDue`。
  它的 quality 语义是：`quality < 3` → 间隔重置为 1、repetitions 归 0；
  `repetitions === 0` → 间隔 1；`=== 1` → 间隔 6；否则 `间隔 × easiness`。
  easiness 下限 1.3。设计文档 §4.2 的表格要映射到这 5 档 quality 上。
- **learning 的轮次文件格式比设计文档假设的更乱**（勘察结论）：
  - `learning/progress/` 有 9 个文件（r25/r26/r30/r32/r33/r35/r36/r37/r38），**一个 frontmatter 都没有**，
    都以 `# R<NN> <主题> — 学习进度` 开头。
  - 清单表的列名**逐个文件不同**：7 列（序号|ID|名称|语言|状态|完成时间|commit SHA）、
    6 列、5 列、`# | 卡片 ID | 主题 | 状态`、`ID | 卡片 | 主题 | 状态`、`卡 ID | 名称 | 状态`。
    → 必须按**列名关键词**匹配，不能按列序，更不能按固定列数。
  - 完成标记是字符串 `done`（不是 ✅/x）；未知值统一是 `TBD-deferred`。
  - 「基本信息」小节是 `| 字段 | 值 |` 两列表，但 r25/r30 用的是无序列表。
  - 解析不了的行**跳过并计入告警**，绝不整体报错（设计文档 §8 已经这么要求，实际情况更需要）。
- **learning 仓没有「错题订正」笔记惯例**。最接近的是 `notes/_templates/question.md`
  （`unresolved: true` + `tags: [question]`）与 `_dashboard/progress.md` 的「待解决疑问」Dataview。
  M4 要写错题订正的话，是**新建惯例**，得同时在 `learning/notes/_meta/schema.md` 里登记。
- `notes/` 的 frontmatter 契约是 `stack/difficulty/status/links/ref/created/updated/tags`，
  键序固定；**164 个笔记里只有 24 个有 frontmatter**，解析器不许假设字段存在。
- 写回前查脏：`git status --porcelain`。注意仓库路径是中文重名的，
  建议用 `git -c core.quotepath=false status --porcelain -z` 按 NUL 切分，
  别用 `line.slice(3)` 硬切（重命名与带空格的路径会切错）。
- **写回 learning 仓后绝不自动 commit**（G11），只返回 diff，由用户决定。








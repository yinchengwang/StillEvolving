# 算法能力提升计划 App —— M6 LLM 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M6 里程碑——把 LLM 接进 app：提示词是纯函数、客户端可换可关、成本有护栏、五个场景（讲解 / 分级求助 / 批改思路 / 现造新题 / 补全缺口）都能用，并且**把 LLM 关掉后 app 依然完整可用**。

**Architecture:** 在 M1 的三层骨架上加一层 `core/llm/`：`prompts.js`（纯函数，构造提示词与解析响应）、`client.js`（`ArkClient` / `AnthropicClient` / `NullClient` 三个实现，统一 `complete({system, user, temperature}) -> Promise<string>`）、`guard.js`（成本护栏，计数落 M1 已有的 `settings` 表）、`service.js`（把提示词、客户端、护栏、题库串成五个场景，生成的题落盘进 `learning/bank/`）。`server/api-llm.js` 挂五个场景接口（**不碰 M1 的 `server/api.js`**，免得和 M2–M5 抢同一个文件），`web/llm.js` 提供「LLM 工作台」。**LLM 全部是可选增强**：没有密钥就自动降级成 `NullClient`，排程、判题、复习、进度一项不少。

**Tech Stack:** Node.js ≥ 24（内置 `node:http` / `node:sqlite` / `node:test` / 全局 `fetch`）、原生 JS + CSS、零 npm 依赖、零构建。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划只覆盖其中 §10 的 **M6**，以及 §6 LLM 接入、§3.2 Problem 文件格式、§7.1 页面、§7.2 API 契约）

**跨计划契约:** `docs/superpowers/plans/2026-11-11-algo-plan-app-接口契约.md`（本计划严格遵守其 §0 已冻结的导出签名与三个接口、§5 M6 新增、§6 G17–G22、§7 写作规范）

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）

**前置条件:** 本计划在 M1–M5 全部执行完之后执行。M1–M5 已冻结的东西**不许改**：
M1 的 `core/paths.js`、`core/bank/problem.js`、`core/bank/parse.js`、`core/bank/provider.js`、
`server/router.js`、`server/app.js`、`server/db.js`、`server/api.js` 的**导出签名**，
以及 `GET /api/health`、`GET /api/bank`、`GET /api/problem/:id` 三个接口的**响应形状**。
M6 只做**加法**：加接口、加模块、加前端区块。

---

## Global Constraints

以下约束对**每一个** task 生效，写代码时不要违反。

### 从 M1 继承（G1–G16，逐条继续生效）

| # | 约束 | 精确值 |
|---|---|---|
| G1 | **零 npm 依赖** | 只用 Node 内置模块（`node:http`/`node:sqlite`/`node:fs`/`node:path`/`node:os`/`node:crypto`/`node:child_process`/`node:test`/`node:stream`）与全局 `fetch`。不许 `npm install` 任何包 |
| G2 | **零构建** | 前端是原生 JS + HTML + CSS，浏览器直接跑。不用 webpack/vite/esbuild，不用 TypeScript |
| G3 | **Node 版本下限** | ≥ 24（`node:sqlite` 在 24 上可用）。低于 24 启动时打印明确错误并退出 1。本机实测 `v24.17.0` |
| G4 | **注释与提交信息用中文** | 沿用 `projects/CLAUDE.md` |
| G5 | **提交即推送** | 每个 commit 完成后立刻 `git push origin main`（`projects/CLAUDE.md` 的「即时推送」纪律） |
| G6 | **产物路径** | 全部代码在 `projects/apps/algo-plan/`。**不要**在 `projects/` 根目录放新文件 |
| G7 | **learning 仓路径不硬编码** | 只认环境变量 `ALGO_PLAN_LEARNING_ROOT`。取不到就降级为「纯本地模式」。不得出现 `../../learning` 这类相对路径假设 |
| G8 | **稳定题目 ID** | 格式 `<前缀>-<5 位数字>`，前缀 `leetcode→lc` / `nowcoder→nc` / `jz→jz` / `self→self` / `llm→llm`。**LLM 造题用 `llm-<10 位内容哈希>`**（M1 的 `makeLlmId`）。它是 git 侧与 SQLite 侧的唯一连接键 |
| G9 | **测试入口** | `node tests/run-all.js` 跑全部套件，自动发现 `tests/*.test.js` |
| G10 | **中文输出** | 面向用户的文案（错误提示、界面文字）全部中文 |
| G11 | **不自动 commit** | app 写回 learning 仓后只返回 diff，**绝不**执行 `git commit`/`git push` |
| G12 | **运行产物不入库** | SQLite 落在 `projects/apps/algo-plan/data/app.db`。`projects/.gitignore` 已忽略 `data/` 与 `*.db` |
| G13 | **题库目录容错** | `learning/bank/` 可能不存在。provider 必须容忍目录缺失：list 返回空数组、get 返回 undefined，不许抛错 |
| G14 | **防作弊** | 单题接口 `GET /api/problem/:id` 默认只返回前 **2** 个样例用例 + 用例总数，**不返回全部用例、不返回参考解法**。M6 造出来的新题也必须遵守这条 |
| G15 | **SQL 类型** | `node:sqlite` 只接受 `null`/`number`/`bigint`/`string`/`Uint8Array`。布尔一律转 `0`/`1`，缺省值一律转 `null` |
| G16 | **node:sqlite 导入** | `const { DatabaseSync } = require("node:sqlite")` |

### 从跨计划契约继承（G17–G22，逐条继续生效）

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测（M3 用，M6 不碰） |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序，用户自己写 `main()`（M3 用，M6 造题时提示词里要遵守） |
| G19 | **导入 id 冲突** | 同 id 已存在则跳过并计入 `skipped`；只有 `force` 才覆盖（M2 用，M6 造题遇到同 id 要明确报错，不覆盖） |
| G20 | **写回前查脏** | `git -c core.quotepath=false status --porcelain -z`，按 NUL 切分（M4 用，M6 写 bank 文件前要遵守） |
| G21 | **轮次解析容错** | 按列名关键词匹配，缺列填空，坏行跳过并计告警（M4 用，M6 不碰） |
| G22 | **零第三方图表** | 雷达图、曲线一律手绘 SVG（M5 用，M6 不碰） |

### M6 新增（G23–G31）

| # | 约束 | 精确值 |
|---|---|---|
| G23 | **LLM 可关** | **把 LLM 关掉，app 仍然完整可用**：排程、判题、复习、进度一项不少。`NullClient.complete()` 返回明确的中文提示且**不抛错**，app 不崩 |
| G24 | **不主动泄题** | 讲解只到思路层；**只有显式选「代码」档才给代码**。两道闸：① `buildPrompt` 在非「代码」档的 system 提示里明确禁止给代码；② service 层构造 context 时**绝不**把 `problem.solution` 放进提示词 |
| G25 | **产出全部可追溯** | LLM 现造的新题**落盘进 `learning/bank/<track>/<id>.md`**（`source: llm`，id 用 M1 的 `makeLlmId`），不是一次性玩具；讲解**记 model + prompt 摘要** |
| G26 | **提示词是纯函数** | `buildPrompt` / `parseResponse` 不联网、不读环境变量、不读文件、不取时间。改动用 `node:test` 钉住 |
| G27 | **密钥不入库** | API Key **只**从环境变量读。**绝不**写进 `settings` 表、**绝不**写进代码、**绝不**进 git、**绝不**出现在接口响应里 |
| G28 | **测试一律不联网** | LLM 客户端测试注入**假 fetch**；service 测试注入**假 client**。任何测试都不发起真实 HTTP 请求 |
| G29 | **环境变量沿用既有约定** | 密钥用官方/工具链既有名字：`ARK_API_KEY`、`ARK_BASE_URL`（arkcli 官方）、`ANTHROPIC_API_KEY`（Anthropic 官方）。app 自己的开关/模型用 `ALGO_PLAN_LLM_*` 前缀。**不另发明一套密钥变量名** |
| G30 | **不新增数据表** | 配额计数与讲解记录都落 M1 已有的 `settings` 表，**不改** M1 冻结的 schema |
| G31 | **成本护栏** | 单次会话请求上限 **20** 次、每日请求上限 **100** 次，超了**直接停**并提示「今天用完了」，不继续烧钱 |

---

## M6 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | 已完成（前��） |
| M2 题库 | 复活三个死脚本 + 存量题解导入 | 已完成（前置） |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | 已完成（前置） |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | 已完成（前置） |
| M5 诊断 | 掌握度模型 + 诊断页 | 已完成（前置） |
| **M6 LLM** | provider + 讲解/求助/造题/补全缺口 | ✅ **本计划** |

**M6 做完的验收线：** `node tests/run-all.js` 全绿；**关掉 LLM（删掉所有密钥）后 app 照常起得来、题库照常读写、判题与复习照常跑**；开着 LLM 时五个场景都能跑通，造出来的题真的落在 `learning/bank/` 里。

**M6 明确不做（YAGNI）：**
- 不做流式输出（SSE）——一次一个完整回答，够用。
- 不做多轮对话上下文——每个场景都是单轮，问完就走。
- 不做向量检索 / RAG——设计文档 §1.3 已经明说不用 `engine/db` 当检索层。
- 不做提示词管理界面——提示词写在 `core/llm/prompts.js` 里，改就改代码，改完跑测试。
- 不做多 provider 并存/故障转移——一次只用一个 provider，出错就报错，不自动切换。
- 不做 API Key 的加密存储——密钥只从环境变量读，设置页只写「密钥来源说明」。

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── core/
│   └── llm/                       M6 新增：整个 LLM 增强层
│       ├── prompts.js             提示词构造与响应解析（纯函数，不联网）
│       ├── client.js              ArkClient / AnthropicClient / NullClient
│       ├── guard.js               成本护栏（会话上限 + 每日上限）
│       └── service.js             五个场景的服务层 + 落盘 + 可追溯
├── server/
│   ├── api-llm.js                 M6 新增：5 个场景接口 + 2 个 LLM 设置接口
│   ├── api.js                     M6 **不改**（M2–M5 也要加路由，分开放不抢文件）
│   ├── app.js                     M6 追加：装配 LLM 客户端与服务层
│   └── main.js                    M6 追加：加载 .env + 打印 LLM 状态
├── web/
│   ├── llm.js                     M6 新增：LLM 工作台（讲解/求助/造题/补全/设置）
│   ├── index.html                 M6 追加一行 <script src="/llm.js"></script>
│   ├── app.js                     M6 **不改**（llm.js 自挂载，详见 Task 7）
│   └── style.css                  M6 追加：LLM 面板样式
├── tools/
│   └── llm-check.js               M6 新增：离线自检脚本（不发请求，只查配置）
└── tests/
    ├── llm-prompts.test.js        M6：提示词纯函数、防泄题
    ├── llm-client.test.js         M6：三个客户端 + 假 fetch
    ├── llm-guard.test.js          M6：配额护栏
    ├── llm-service.test.js        M6：五个场景 + 落盘 + 可追溯
    ├── llm-api.test.js            M6：HTTP 接口形状
    ├── llm-off.test.js            M6：关掉 LLM 也能用（硬约束专测）
    ├── llm-web.test.js            M6：前端纯逻辑（四档解锁等）
    └── llm-e2e.test.js            M6：端到端
```

**归属：** 本计划只改 `projects/` 子模块。`learning/` 子模块只被**写入新题文件**
（`learning/bank/<track>/<id>.md`），**绝不自动 commit**（G11）——写不写、什么时候提交，由用户决定。

---

## 实地勘察备忘（写这份计划前实际查过，不猜）

### 1. 本仓**没有**既有的 LLM 客户端

全仓搜过 `arkcli` / `ark.cn` / `anthropic` / `api.anthropic` / `ARK_API_KEY` / `ANTHROPIC_API_KEY` /
`base_url` / `chat/completions` / `volces` / `doubao` 等关键词，命中的是这些**都不是可复用的 LLM 客户端**：

| 文件 | 命中内容 | 结论 |
|---|---|---|
| `projects/engine/src/sdk/extra/embedding_openai.c` | `getenv("MMDB_OPENAI_API_KEY")`，但函数直接返回 `MMDB_ERR_NOT_IMPLEMENTED`，**从不发 HTTP** | C 侧占位实现，与本 app（Node/JS）无关，**不可复用** |
| `projects/engine/include/db/rag_executor.h` | `rag_llm_config_t{model, base_url, max_tokens, temperature, ...}` 结构体定义 | 只有配置结构体，**没有实现**，也不在 `apps/` 下 |
| `projects/engine/src/db/executor/rag/generate_op.c` | `RAG_LLM_OPENAI` / `RAG_LLM_ANTHROPIC` 分支 | 分支**未实现**，只有 Ollama 桩 |
| `projects/apps/knowledge-hub/core/stores.js:616` | `apiConfig: { apiKey: '', apiUrl: '', model: '' }` | 空占位默认值，全仓**没有任何地方**拿它发请求 |
| `projects/docs/analysis/rag.md` | 提到 `langchain-openai/anthropic/cohere` 等 | 文档里的对比清单，**不是代码** |
| `learning/notes/.obsidian/plugins/obsidian-excalidraw-plugin/*` | 第三方 Obsidian 插件包里出现 `api.anthropic.com/v1` | 第三方产物，与本仓无关 |

**结论：本仓无既有 LLM 客户端，以下约定为本计划新建。**
但**约定本身不另发明**——直接沿用本机已装好的 `arkcli` 工具链与 Anthropic 官方的调用形状（见下）。

### 2. 调用形状与默认值（来源是本机真实存在的文档，不是记忆）

**火山方舟（Ark）** — 来源 `C:/Users/yinch/.claude/skills/arkcli-code-example/assets/demo-code/python.py`
与 `C:/Users/yinch/.claude/skills/arkcli-config/references/arkcli-config-init.md`：

```
base URL : https://ark.cn-beijing.volces.com/api/v3      （区域形式 https://ark.<region>.volces.com/api/v3）
端点     : POST {base}/chat/completions                  （OpenAI 兼容入口；另有 /responses）
认证头   : Authorization: Bearer $ARK_API_KEY
请求体   : { model, messages: [{role:"system"|"user", content}], temperature, max_tokens, stream:false }
读响应   : choices[0].message.content
密钥变量 : ARK_API_KEY        （优先级 --api-key > ARK_API_KEY > profile > identity store > 产品 .env）
地址变量 : ARK_BASE_URL
模型名   : 必须是完整版本化 ID（如 doubao-seed-1-6-251015）或接入点 ID（ep-xxx）。
           直接传族名（doubao-seed-1-8）会 404 InvalidEndpointOrModel.NotFound。
```

**Anthropic** — 来源 `claude-api` skill 的 `curl/examples.md`（本机 `~/.claude/bundled-skills/.../claude-api/curl/examples.md`）：

```
端点     : POST https://api.anthropic.com/v1/messages
认证头   : x-api-key: $ANTHROPIC_API_KEY
版本头   : anthropic-version: 2023-06-01
请求体   : { model, max_tokens, system, messages: [{role:"user", content}] }
读响应   : content[] 里 type=="text" 的 text 拼起来（.content[0].text 是第一块）
模型名   : claude-opus-5 / claude-sonnet-5 / claude-haiku-4-5（完整 ID，不加日期后缀）
采样参数 : claude-opus-5 与 claude-sonnet-5 **已移除 temperature/top_p/top_k**，传了返回 400。
           → 本计划的 AnthropicClient **不发送 temperature**（接口签名保留该字段但不透传）。
```

### 3. API Key 的存放与读取惯例（仓库既有做法）

- `projects/.gitignore` 里已经有这一段：

  ```
  # ---- 本地环境变量（可能含密钥，严禁提交） ----
  .env
  .env.local
  .env.*.local
  ```

  → **仓库约定就是：本地密钥放 `.env` 文件，`.env` 被 gitignore 挡住。**
- **仓库里目前没有任何 `.env` / `.env.example` 文件**（`find` 全仓无命中）。根仓 `StillEvolving/.gitignore`
  与 `learning/.gitignore` 都**没有**任何密钥相关的条目。
- 仓库里读环境变量的既有写法是 **`process.env`**（M1 的 `core/paths.js` 读 `env.ALGO_PLAN_LEARNING_ROOT`），
  变量名用**大写 + 应用前缀**（`ALGO_PLAN_LEARNING_ROOT`）。
- C 侧唯一的密钥读取是 `getenv("MMDB_OPENAI_API_KEY")`，也是**大写 + 模块前缀**。

**因此 M6 的约定（不另发明一套）：**

| 变量 | 谁定的 | 说明 | 默认 |
|---|---|---|---|
| `ARK_API_KEY` | **arkcli 官方** | 方舟密钥 | 无 |
| `ARK_BASE_URL` | **arkcli 官方** | 方舟地址 | `https://ark.cn-beijing.volces.com/api/v3` |
| `ANTHROPIC_API_KEY` | **Anthropic 官方** | Anthropic 密钥 | 无 |
| `ALGO_PLAN_LLM_ENABLED` | M6 新建 | 总开关，`0`/`false`/`off` = 关 | 未设＝按密钥自动判断 |
| `ALGO_PLAN_LLM_PROVIDER` | M6 新建 | `ark` / `anthropic` / `null` | 未设＝按密钥推断 |
| `ALGO_PLAN_LLM_MODEL` | M6 新建 | 模型名 | 按 provider 取默认 |
| `ALGO_PLAN_LLM_BASE_URL` | M6 新建 | 覆盖地址（两个 provider 通用） | 未设＝按 provider 取默认 |
| `ALGO_PLAN_LLM_SESSION_LIMIT` | M6 新建 | 单次会话请求上限 | `20` |
| `ALGO_PLAN_LLM_DAILY_LIMIT` | M6 新建 | 每日请求上限 | `100` |

**密钥文件放法：** 需要在本机跑真 LLM 时，在 `projects/apps/algo-plan/` 下建一个 `.env`（**已被 `projects/.gitignore` 忽略**）：

```
ARK_API_KEY=在这里填你的方舟密钥
```

Node 不会自动读 `.env`（零依赖，不引 `dotenv`）。**由启动脚本显式加载**：`server/main.js` 里在 `createApp()` 之前
读一次 `.env` 并塞进 `process.env`。本计划 Task 5 会把这段加载代码写死。

### 4. 提交与注释风格（`projects/CLAUDE.md`）

- 所有对话、解释、建议用**简体中文**；代码注释用中文；Commit Message 用中文。
- 提交格式：`<type>(<scope>): <中文一句话>` + 中文 `-` 要点正文，**commit 完立刻 `git push origin main`**。
  `scope` 用模块名，本计划统一用 `algo-plan`。
- 根目录准入白名单：**不要**在 `projects/` 根目录放新文件（G6）。

---

## Task 1: 提示词纯函数（core/llm/prompts.js）

设计文档 §6.4：「提示词是纯函数，**改动能用 Node 单测钉住，不需要联网测**」。
这个 task 把五个场景的提示词全部写成纯函数，并用测试把**不主动泄题**这条纪律钉死（G24）。

**Files:**
- Create: `projects/apps/algo-plan/core/llm/prompts.js`
- Test: `projects/apps/algo-plan/tests/llm-prompts.test.js`

**Interfaces:**
- Consumes:
  - `core/bank/problem.js` 的 `normalizeTopics(list) -> string[]` 与常量 `DIFFICULTIES`（M1 已冻结，**只读不改**）
- Produces:
  - `buildPrompt(kind, context) -> {system: string, user: string}`，`kind ∈ "explain" | "hint" | "grade-idea" | "generate" | "fill"`
  - `parseResponse(text, kind) -> object`，解析不出来给 `{ok: false, reason: "中文原因"}`
  - `EXPLAIN_LEVELS -> ["思路", "代码"]`
  - `HINT_LEVELS -> ["方向", "思路", "伪码", "代码"]`
  - `KINDS -> ["explain", "hint", "grade-idea", "generate", "fill"]`

**这个 task 的边界：** 只写提示词与解析，**不碰网络、不碰环境变量、不碰文件、不碰时间**。
网络在 Task 2，编排（拼上下文、查配额、落盘）在 Task 4。

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-prompts.test.js`**

创建 `projects/apps/algo-plan/tests/llm-prompts.test.js`：

```javascript
"use strict"
/**
 * llm-prompts.test.js —— 提示词纯函数测试（**不联网**）
 *
 * 钉住三件事：
 *   1. 五种 kind 的 buildPrompt 都返回 {system, user}，且是纯函数；
 *   2. 不主动泄题（G24）：非「代码」档禁止给代码；explain / hint 的提示词里
 *      **根本不会**出现参考解法（哪怕调用方硬塞了 context.solution）；
 *   3. parseResponse 对脏输入给出 ok:false 与中文原因，不抛异常。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  buildPrompt,
  parseResponse,
  EXPLAIN_LEVELS,
  HINT_LEVELS,
  KINDS,
} = require("../core/llm/prompts.js")

/** 一道普通的题，带参考解法 */
const 题 = {
  id: "lc-00001",
  title: "两数之和",
  difficulty: "easy",
  topics: ["哈希表", "数组"],
  tracks: ["interview"],
  statement: "给定整数数组 nums 和整数 target，找出数组中和为 target 的两个整数的下标。",
  cases: [{ input: "[2,7,11,15], 9", expect: "[0,1]", tol: null }],
  solution: "int main(){ /* 参考答案 */ return 0; }",
  solutionLang: "cpp",
}

/** 禁止给代码时 system 里必须出现的句子 */
const NO_CODE = "绝不给出任何可编译的完整代码"
/** 允许给代码时 system 里必须出现的句子 */
const ALLOW_CODE = "本次允许给出完整代码"

test("档位枚举固定：讲解两档、求助四档", function () {
  assert.deepEqual(EXPLAIN_LEVELS, ["思路", "代码"])
  assert.deepEqual(HINT_LEVELS, ["方向", "思路", "伪码", "代码"])
  assert.deepEqual(KINDS, ["explain", "hint", "grade-idea", "generate", "fill"])
})

test("buildPrompt 对五种 kind 都返回非空的 system 与 user", function () {
  const ctx = {
    title: 题.title,
    difficulty: 题.difficulty,
    topics: 题.topics,
    statement: 题.statement,
    level: "思路",
    idea: "用哈希表把出现过的数存起来",
    track: "interview",
    cases: 题.cases,
    solution: 题.solution,
    solutionLang: 题.solutionLang,
  }
  for (const kind of KINDS) {
    const p = buildPrompt(kind, ctx)
    assert.equal(typeof p.system, "string", kind + " 的 system 必须是字符串")
    assert.equal(typeof p.user, "string", kind + " 的 user 必须是字符串")
    assert.ok(p.system.length > 0, kind + " 的 system 不该为空")
    assert.ok(p.user.length > 0, kind + " 的 user 不该为空")
  }
})

test("buildPrompt 是纯函数：同样输入永远同样输出", function () {
  const ctx = { title: "t", statement: "s", level: "思路", topics: ["a"], difficulty: "easy" }
  assert.deepEqual(buildPrompt("explain", ctx), buildPrompt("explain", ctx))
  assert.deepEqual(buildPrompt("generate", ctx), buildPrompt("generate", ctx))
})

test("不主动泄题：非『代码』档的 system 明确禁止给代码", function () {
  const 思路 = buildPrompt("explain", { title: "t", statement: "s", level: "思路" })
  assert.ok(思路.system.includes(NO_CODE), "讲解-思路 档应禁止给代码")

  const 方向 = buildPrompt("hint", { title: "t", statement: "s", level: "方向" })
  assert.ok(方向.system.includes(NO_CODE), "求助-方向 档应禁止给代码")

  const 伪码 = buildPrompt("hint", { title: "t", statement: "s", level: "伪码" })
  assert.ok(伪码.system.includes(NO_CODE), "求助-伪码 档应禁止给可编译代码")
})

test("不主动泄题：只有显式选『代码』档才放开给代码", function () {
  const 代码 = buildPrompt("explain", { title: "t", statement: "s", level: "代码" })
  assert.ok(代码.system.includes(ALLOW_CODE), "讲解-代码 档应放开给代码")
  assert.ok(!代码.system.includes(NO_CODE), "讲解-代码 档不该再出现禁止条款")

  const 求助代码 = buildPrompt("hint", { title: "t", statement: "s", level: "代码" })
  assert.ok(求助代码.system.includes(ALLOW_CODE), "求助-代码 档应放开给代码")
  assert.ok(!求助代码.system.includes(NO_CODE), "求助-代码 档不该再出现禁止条款")
})

test("不主动泄题：explain / hint 的提示词里绝不出现参考解法", function () {
  const 组合 = []
  for (const level of EXPLAIN_LEVELS) 组合.push(["explain", level])
  for (const level of HINT_LEVELS)    组合.push(["hint", level])
  for (const [kind, level] of 组合) {
    const p = buildPrompt(kind, {
      title: 题.title,
      difficulty: 题.difficulty,
      topics: 题.topics,
      statement: 题.statement,
      level: level,
      // 故意把参考解法塞进来，验证 buildPrompt 根本不读它
      solution: 题.solution,
      solutionLang: 题.solutionLang,
    })
    assert.ok(!p.user.includes("参考答案"), kind + "/" + level + " 的 user 不该出现参考解法")
    assert.ok(!p.user.includes("int main"), kind + "/" + level + " 的 user 不该出现参考解法代码")
    assert.ok(!p.system.includes("参考答案"), kind + "/" + level + " 的 system 不该出现参考解法")
  }
})

test("buildPrompt 的 grade-idea 会带上用户思路", function () {
  const p = buildPrompt("grade-idea", { title: "t", statement: "s", idea: "用两个指针" })
  assert.ok(p.user.includes("用两个指针"), "grade-idea 的 user 应带上用户思路")
  assert.ok(p.user.includes("verdict"), "grade-idea 的 user 应要求返回 JSON")
})

test("buildPrompt 的 generate 会要求 JSON 与题面自包含", function () {
  const p = buildPrompt("generate", { track: "interview", topics: ["哈希表"], difficulty: "easy" })
  assert.ok(p.user.includes("interview"), "generate 的 user 应带上轨道")
  assert.ok(p.user.includes("哈希表"), "generate 的 user 应带上知识点")
  assert.ok(p.user.includes("JSON"), "generate 的 user 应要求返回 JSON")
  assert.ok(p.user.includes("stdin"), "generate 的 user 应交代 stdin/stdout 判题契约")
})

test("buildPrompt 的 fill 会带上参考解法", function () {
  const p = buildPrompt("fill", {
    title: "t",
    statement: "",
    cases: [],
    solution: "int main(){return 0;}",
    solutionLang: "cpp",
  })
  assert.ok(p.user.includes("int main"), "fill 的 user 应带上参考解法")
  assert.ok(p.user.includes("JSON"), "fill 的 user 应要求返回 JSON")
})

test("parseResponse 解析讲解与求助：原样返回文本", function () {
  const r = parseResponse("  先用哈希表  ", "explain")
  assert.equal(r.ok, true)
  assert.equal(r.text, "先用哈希表")
})

test("parseResponse 对空回复给出 ok:false 与中文原因", function () {
  const r = parseResponse("", "explain")
  assert.equal(r.ok, false)
  assert.ok(r.reason.length > 0, "失败时必须给出原因")
})

test("parseResponse 解析 grade-idea：认 verdict 枚举", function () {
  const r = parseResponse('{"verdict":"correct","comment":"思路没问题"}', "grade-idea")
  assert.equal(r.ok, true)
  assert.equal(r.verdict, "correct")
  assert.equal(r.comment, "思路没问题")
})

test("parseResponse 能剥掉 ```json 围栏", function () {
  const r = parseResponse('```json\n{"verdict":"partial","comment":"漏了边界"}\n```', "grade-idea")
  assert.equal(r.ok, true)
  assert.equal(r.verdict, "partial")
  assert.equal(r.comment, "漏了边界")
})

test("parseResponse 解析 grade-idea：不是 JSON 就给 ok:false，不抛异常", function () {
  const r = parseResponse("我觉得挺对的", "grade-idea")
  assert.equal(r.ok, false)
  assert.ok(r.reason.length > 0)
})

test("parseResponse 解析 generate：产出题目骨架", function () {
  const r = parseResponse(JSON.stringify({
    title: "两数之和",
    statement: "给定数组…",
    difficulty: "easy",
    topics: ["哈希表"],
    cases: [{ input: "[2,7], 9", expect: "[0,1]" }],
    solution: "int main(){return 0;}",
    solutionLang: "cpp",
  }), "generate")
  assert.equal(r.ok, true)
  assert.equal(r.problem.title, "两数之和")
  assert.equal(r.problem.statement, "给定数组…")
  assert.equal(r.problem.cases.length, 1)
  assert.equal(r.problem.cases[0].input, "[2,7], 9")
  assert.equal(r.problem.solutionLang, "cpp")
})

test("parseResponse 解析 generate：缺测试用例就报 ok:false", function () {
  const r = parseResponse(JSON.stringify({ title: "t", statement: "s", solution: "c" }), "generate")
  assert.equal(r.ok, false)
  assert.ok(r.reason.includes("测试用例"), "原因里应点明缺测试用例")
})

test("parseResponse 解析 fill：产出补全补丁", function () {
  const r = parseResponse(JSON.stringify({
    statement: "补出来的题面",
    cases: [{ input: "1 2", expect: "3" }],
  }), "fill")
  assert.equal(r.ok, true)
  assert.equal(r.patch.statement, "补出来的题面")
  assert.equal(r.patch.cases.length, 1)
  assert.equal(r.patch.cases[0].expect, "3")
})

test("parseResponse 对未知 kind 返回 ok:false", function () {
  const r = parseResponse("随便", "不存在的种类")
  assert.equal(r.ok, false)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-prompts.test.js` 报 `Cannot find module '../core/llm/prompts.js'`。

- [ ] **Step 3: 写实现 `core/llm/prompts.js`**

创建 `projects/apps/algo-plan/core/llm/prompts.js`：

```javascript
"use strict"
/**
 * prompts.js —— 提示词构造与响应解析（**纯函数，不联网**）
 *
 * 设计文档 §6.4：提示词是纯函数，改动用 Node 单测钉住，不需要联网测。
 *
 * 纪律在这里就落一半（G24）：
 *   1. 不主动泄题 —— 只有「代码」档的 system 提示才放开给代码；
 *      其它档位一律禁止给代码；并且 explain / hint 分支**根本不读**
 *      context.solution，参考解法进不了提示词。
 *   2. 产出全部可追溯 —— 提示词里带上题号与档位，方便回查。
 *
 * 纯函数边界：不联网、不读环境变量、不读文件、不取当前时间。
 */

const { normalizeTopics, DIFFICULTIES } = require("../bank/problem.js")

/** 讲解的档位：先思路，后代码 */
const EXPLAIN_LEVELS = ["思路", "代码"]

/** 求助的档位：方向 → 思路 → 伪码 → 代码，逐级解锁 */
const HINT_LEVELS = ["方向", "思路", "伪码", "代码"]

/** 全部提示词种类 */
const KINDS = ["explain", "hint", "grade-idea", "generate", "fill"]

/** 禁止给代码时，system 提示里必须出现的句子（测试钉住它） */
const NO_CODE_RULE = "绝不给出任何可编译的完整代码"

/** 允许给代码时，system 提示里必须出现的句子（测试钉住它） */
const ALLOW_CODE_RULE = "本次允许给出完整代码"

/** 各档位对模型的具体要求 */
const LEVEL_BRIEF = {
  方向: "只点一个大方向（往哪类思路想、用什么数据结构），不要展开推导，不要给伪代码。",
  思路: "讲清楚完整的解题思路与关键推导，但不要写任何代码，连伪代码也不要写。",
  伪码: "给出算法伪代码或步骤分解，可以用接近自然语言描述流程，但不要写可编译的完整实现。",
  代码: "给出可直接提交的完整代码：自带 main 函数，从 stdin 读入、从 stdout 输出，不要写 class Solution 包装。",
}

const SYSTEM_EXPLAIN = [
  "你是一位算法辅导老师，要给正在做题的人讲清「为什么这么想」。",
  "纪律：" + NO_CODE_RULE + "、函数实现或伪代码，只讲到思路层面。",
  "除非用户明确要求「代码」档，否则你只能讲思路。",
  "输出用简体中文，分点讲清，不要复述题面。",
].join("\n")

const SYSTEM_EXPLAIN_CODE = [
  "你是一位算法辅导老师，要给正在做题的人讲清「为什么这么想」。",
  ALLOW_CODE_RULE + "：用户明确选了「代码」档。",
  "判题契约：stdin 读入、stdout 输出，程序自带 main 函数，不要写 class Solution 包装。",
  "输出用简体中文，先讲思路，再给完整代码。",
].join("\n")

const SYSTEM_HINT = [
  "你是一位算法辅导老师。用户已经卡住了，在向你要提示。",
  "纪律：" + NO_CODE_RULE + "、函数实现或伪代码。",
  "除非用户明确要求「代码」档，否则你只能给到本档允许的内容。",
  "不要重复题面，不要重新讲一遍题目。",
  "输出用简体中文，简短直接。",
].join("\n")

const SYSTEM_HINT_PSEUDO = [
  "你是一位算法辅导老师。用户已经卡住了，在向你要提示。",
  "纪律：" + NO_CODE_RULE + "。本档允许给伪代码与步骤分解。",
  "不要重复题面，不要重新讲一遍题目。",
  "输出用简体中文，简短直接。",
].join("\n")

const SYSTEM_HINT_CODE = [
  "你是一位算法辅导老师。用户已经卡住了，在向你要提示。",
  ALLOW_CODE_RULE + "：用户明确选了「代码」档。",
  "判题契约：stdin 读入、stdout 输出，程序自带 main 函数，不要写 class Solution 包装。",
  "输出用简体中文，先讲思路，再给完整代码。",
].join("\n")

const SYSTEM_GRADE = [
  "你是一位算法老师，负责批改用户的解题思路。",
  "你只判断思路对不对，不给完整代码，不重写解法。",
  "输出必须是且只是一个 JSON 对象，字段为 verdict 与 comment，不要加解释性前后缀，不要用代码块围栏。",
  "输出用简体中文。",
].join("\n")

const SYSTEM_GENERATE = [
  "你是一位算法出题老师，要出一道能独立完成、能自动判题的算法题。",
  "输出必须是且只是一个 JSON 对象，字段为 title、statement、difficulty、topics、cases、solution、solutionLang。",
  "不要加解释性前后缀，不要用代码块围栏。",
].join("\n")

const SYSTEM_FILL = [
  "你是一位算法老师，要根据已有的参考解法反推出一道题的题面与测试用例。",
  "输出必须是且只是一个 JSON 对象，字段为 statement 与 cases。",
  "不要加解释性前后缀，不要用代码块围栏。",
].join("\n")

/** 知识点拼成一行；空则写「未标注」 */
function topicText(topics) {
  const list = Array.isArray(topics) ? normalizeTopics(topics) : []
  return list.length ? list.join("、") : "未标注"
}

/** 题面、标题、难度这些公共部分 */
function baseUser(ctx) {
  const lines = []
  if (ctx.title) lines.push("题目：" + ctx.title)
  if (ctx.difficulty) lines.push("难度：" + ctx.difficulty)
  if (Array.isArray(ctx.topics) && ctx.topics.length) lines.push("知识点：" + topicText(ctx.topics))
  if (ctx.statement) lines.push("题面：\n" + String(ctx.statement).trim())
  return lines.join("\n")
}

/**
 * 构造提示词。
 * @param {"explain"|"hint"|"grade-idea"|"generate"|"fill"} kind
 * @param {object} context
 *   explain / hint：{title, difficulty, topics, statement, level}
 *   grade-idea   ：{title, statement, idea}
 *   generate     ：{track, topics, difficulty}
 *   fill         ：{title, difficulty, topics, statement, cases, solution, solutionLang}
 * @returns {{system: string, user: string}}
 */
function buildPrompt(kind, context) {
  const ctx = context || {}

  if (kind === "explain") {
    const level = EXPLAIN_LEVELS.indexOf(ctx.level) !== -1 ? ctx.level : "思路"
    return {
      system: level === "代码" ? SYSTEM_EXPLAIN_CODE : SYSTEM_EXPLAIN,
      user: [
        baseUser(ctx),
        "",
        "请按「" + level + "」档讲解本题。",
        LEVEL_BRIEF[level],
        "再提醒一次纪律：" + (level === "代码" ? ALLOW_CODE_RULE : NO_CODE_RULE) + "。",
      ].join("\n"),
    }
  }

  if (kind === "hint") {
    const level = HINT_LEVELS.indexOf(ctx.level) !== -1 ? ctx.level : "方向"
    const system = level === "代码"
      ? SYSTEM_HINT_CODE
      : (level === "伪码" ? SYSTEM_HINT_PSEUDO : SYSTEM_HINT)
    return {
      system: system,
      user: [
        baseUser(ctx),
        "",
        "请按「" + level + "」档给提示。用户已经卡住了，这一档只解决一个层次的问题。",
        LEVEL_BRIEF[level],
        "纪律：" + (level === "代码" ? ALLOW_CODE_RULE : NO_CODE_RULE) + "。",
      ].join("\n"),
    }
  }

  if (kind === "grade-idea") {
    const idea = String(ctx.idea || "").trim()
    return {
      system: SYSTEM_GRADE,
      user: [
        baseUser(ctx),
        "",
        "用户的解题思路：",
        idea || "（用户没有写思路）",
        "",
        "请判断这个思路是否可行：能不能得到正确答案，复杂度是否可接受，有没有漏掉边界情况。",
        "只输出一个 JSON 对象，不要任何多余文字，也不要用代码块围栏：",
        '{"verdict":"correct|partial|wrong","comment":"中文点评，一到三句"}',
        "verdict 只能取 correct、partial、wrong 三个值之一。",
      ].join("\n"),
    }
  }

  if (kind === "generate") {
    const track = String(ctx.track || "").trim() || "未指定"
    const difficulty = DIFFICULTIES.indexOf(String(ctx.difficulty)) !== -1
      ? String(ctx.difficulty)
      : "medium"
    return {
      system: SYSTEM_GENERATE,
      user: [
        "请出一道新的算法练习题。",
        "",
        "所属轨道：" + track,
        "知识点：" + topicText(ctx.topics),
        "难度：" + difficulty,
        "",
        "要求：",
        "1. 题面必须自包含：说清输入、输出、约束，不能依赖上下文。",
        "2. 判题契约：用户程序从 stdin 读入、从 stdout 输出，程序自带 main 函数。",
        "3. 至少给 3 个测试用例，其中至少 1 个是边界情况。",
        "4. 给一份 C++ 参考解法（cpp），是带 main 函数的完整程序。",
        "5. 题目要有明确答案，不能出无解或多解的题。",
        "",
        "只输出一个 JSON 对象，不要任何多余文字，也不要用代码块围栏：",
        '{"title":"题目名","statement":"完整题面","difficulty":"easy|medium|hard","topics":["知识点"],"cases":[{"input":"...","expect":"..."}],"solution":"完整 cpp 程序","solutionLang":"cpp"}',
      ].join("\n"),
    }
  }

  if (kind === "fill") {
    const cases = Array.isArray(ctx.cases) ? ctx.cases : []
    const lang = String(ctx.solutionLang || "cpp")
    const 用例行 = cases.length
      ? cases.map(function (c) { return "- " + c.input + " → " + c.expect }).join("\n")
      : "（缺失，需要你补）"
    return {
      system: SYSTEM_FILL,
      user: [
        "下面是一道题的原题解，题面与测试用例可能有缺失，请反推并补全。",
        "",
        "标题：" + String(ctx.title || "未命名"),
        "难度：" + String(ctx.difficulty || "未标注"),
        "知识点：" + topicText(ctx.topics),
        "当前题面：",
        String(ctx.statement || "").trim() || "（缺失，需要你补）",
        "",
        "当前测试用例（input → expect）：",
        用例行,
        "",
        "参考解法（" + lang + "）：",
        "```" + lang,
        String(ctx.solution || "").trim() || "（缺失）",
        "```",
        "",
        "要求：",
        "1. 补出完整题面：说清输入、输出、约束。",
        "2. 补出至少 3 个测试用例，期望输出必须与参考解法一致。",
        "3. 不要修改参考解法。",
        "4. 题面若已存在就原样保留，只补缺失的部分。",
        "",
        "只输出一个 JSON 对象，不要任何多余文字，也不要用代码块围栏：",
        '{"statement":"完整题面","cases":[{"input":"...","expect":"..."}]}',
      ].join("\n"),
    }
  }

  return { system: "", user: "" }
}

/** 从可能带围栏、前后缀的文本里抠出 JSON 对象；抠不出返回 null */
function extractJson(text) {
  const raw = String(text === null || text === undefined ? "" : text)
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(raw)
  const body = fenced ? fenced[1] : raw
  const start = body.indexOf("{")
  const end = body.lastIndexOf("}")
  if (start === -1 || end === -1 || end <= start) return null
  try {
    return JSON.parse(body.slice(start, end + 1))
  } catch (err) {
    return null
  }
}

/** 把模型给的各种说法归一成四种判定之一 */
function normalizeVerdict(value) {
  const text = String(value === null || value === undefined ? "" : value).trim().toLowerCase()
  if (text === "correct" || text === "正确" || text === "对" || text === "可行") return "correct"
  if (text === "wrong" || text === "错误" || text === "不对" || text === "不正确" || text === "不可行") return "wrong"
  if (text === "partial" || text === "部分正确" || text === "部分对" || text === "部分可行") return "partial"
  return "unknown"
}

/** 用例列表归一：丢掉空壳，tol 非法就置 null */
function normalizeCaseList(list) {
  const out = []
  if (!Array.isArray(list)) return out
  list.forEach(function (item) {
    if (!item || typeof item !== "object") return
    const input = String(item.input === undefined || item.input === null ? "" : item.input).trim()
    const expect = String(item.expect === undefined || item.expect === null ? "" : item.expect).trim()
    if (input === "" && expect === "") return
    let tol = null
    if (item.tol !== undefined && item.tol !== null && item.tol !== "") {
      const value = Number(item.tol)
      tol = Number.isFinite(value) ? value : null
    }
    out.push({ input: input, expect: expect, tol: tol })
  })
  return out
}

/** generate 的解析结果 → 题目骨架 */
function buildGenerated(obj) {
  const title = String(obj.title || "").trim()
  if (title === "") return { ok: false, reason: "生成结果缺标题" }
  const statement = String(obj.statement || "").trim()
  if (statement === "") return { ok: false, reason: "生成结果缺题面" }
  const cases = normalizeCaseList(obj.cases)
  if (cases.length === 0) return { ok: false, reason: "生成结果缺测试用例" }
  const solution = String(obj.solution || "").trim()
  if (solution === "") return { ok: false, reason: "生成结果缺参考解法" }
  const difficulty = DIFFICULTIES.indexOf(String(obj.difficulty)) !== -1
    ? String(obj.difficulty)
    : "medium"
  const topics = topicText(obj.topics) === "未标注" ? [] : normalizeTopics(obj.topics)
  return {
    ok: true,
    problem: {
      title: title,
      statement: statement,
      cases: cases,
      solution: solution,
      solutionLang: String(obj.solutionLang || "cpp").trim() || "cpp",
      difficulty: difficulty,
      topics: topics,
    },
  }
}

/** fill 的解析结果 → 补全补丁 */
function buildFillPatch(obj) {
  const statement = String(obj.statement || "").trim()
  if (statement === "") return { ok: false, reason: "补全结果缺题面" }
  const cases = normalizeCaseList(obj.cases)
  if (cases.length === 0) return { ok: false, reason: "补全结果缺测试用例" }
  const patch = { statement: statement, cases: cases }
  const solution = String(obj.solution || "").trim()
  if (solution !== "") {
    patch.solution = solution
    patch.solutionLang = String(obj.solutionLang || "cpp").trim() || "cpp"
  }
  return { ok: true, patch: patch }
}

/**
 * 解析模型回复。
 * @param {string} text
 * @param {"explain"|"hint"|"grade-idea"|"generate"|"fill"} kind
 * @returns {object} 成功时带 ok:true；失败时带 ok:false 与中文 reason
 */
function parseResponse(text, kind) {
  const raw = text === null || text === undefined ? "" : String(text).trim()

  if (kind === "explain" || kind === "hint") {
    if (raw === "") return { ok: false, kind: kind, reason: "模型没有返回内容" }
    return { ok: true, kind: kind, text: raw }
  }

  if (kind === "grade-idea") {
    const obj = extractJson(raw)
    if (!obj) {
      return { ok: false, kind: kind, reason: "模型返回的不是结构化结果，无法判定思路对错", raw: raw }
    }
    const comment = String(obj.comment || obj.remark || obj.explanation || "").trim()
    if (comment === "") {
      return { ok: false, kind: kind, reason: "模型没有给出点评", raw: raw }
    }
    return { ok: true, kind: kind, verdict: normalizeVerdict(obj.verdict), comment: comment }
  }

  if (kind === "generate") {
    const obj = extractJson(raw)
    if (!obj) {
      return { ok: false, kind: kind, reason: "模型返回的不是合法 JSON，无法生成题目", raw: raw }
    }
    const built = buildGenerated(obj)
    if (!built.ok) return { ok: false, kind: kind, reason: built.reason, raw: raw }
    return { ok: true, kind: kind, problem: built.problem }
  }

  if (kind === "fill") {
    const obj = extractJson(raw)
    if (!obj) {
      return { ok: false, kind: kind, reason: "模型返回的不是合法 JSON，无法补全题目", raw: raw }
    }
    const patch = buildFillPatch(obj)
    if (!patch.ok) return { ok: false, kind: kind, reason: patch.reason, raw: raw }
    return { ok: true, kind: kind, patch: patch.patch }
  }

  return { ok: false, kind: kind, reason: "未知的提示词种类：" + String(kind) }
}

module.exports = {
  buildPrompt: buildPrompt,
  parseResponse: parseResponse,
  EXPLAIN_LEVELS: EXPLAIN_LEVELS,
  HINT_LEVELS: HINT_LEVELS,
  KINDS: KINDS,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-prompts.test.js` 套件全绿（PASS），`node tests/run-all.js` 退出码 0。
（总套件数由 M1–M5 决定，M6 不写死；只要新的 `llm-prompts.test.js` 是 PASS 且退出码是 0 就算通过。）

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/core/llm/prompts.js apps/algo-plan/tests/llm-prompts.test.js
git commit -m "feat(algo-plan): 新增 LLM 提示词纯函数与防泄题测试

- core/llm/prompts.js：buildPrompt / parseResponse 覆盖讲解、求助、批改思路、造题、补全五个场景
- 只有显式选「代码」档才放开给代码，非代码档在提示词里明确禁止
- explain / hint 分支不读取参考解法，参考解法进不了提示词
- 提示词与解析全部纯函数，用 node:test 钉住，不联网"
git push origin main
```

---

## Task 2: LLM 客户端（core/llm/client.js）

接口契约 §5 冻结了 `createLlmClient({provider, apiKey, baseUrl, model}) -> client`，
`client.complete({system, user, temperature}) -> Promise<string>`，`client.name -> "ark" | "anthropic" | "null"`。

本 task 在这四个参数之外**加**三个字段（不冲突、不替换）：`env`（指定读哪个环境变量对象，便于测试）、
`fetchImpl`（注入假 fetch，**测试绝不联网**）、`enabled`（总开关）。

**Files:**
- Create: `projects/apps/algo-plan/core/llm/client.js`
- Test: `projects/apps/algo-plan/tests/llm-client.test.js`

**Interfaces:**
- Consumes: 无（只依赖 Node 内置的全局 `fetch`，不 require 任何仓库模块）
- Produces:
  - `createLlmClient({provider?, apiKey?, baseUrl?, model?, env?, fetchImpl?, enabled?}) -> client`
  - `class ArkClient`：`name === "ark"`，公开属性 `apiKey` / `baseUrl` / `model` / `maxTokens` / `fetchImpl`
  - `class AnthropicClient`：`name === "anthropic"`，同上
  - `class NullClient`：`name === "null"`，公开属性 `reason`（关闭原因）
  - `keySourceOf(provider, env) -> string`（只说密钥来自哪个环境变量，**绝不**回显密钥本身）
  - `ARK_DEFAULT_BASE_URL` / `ARK_DEFAULT_MODEL` / `ANTHROPIC_DEFAULT_BASE_URL` / `ANTHROPIC_DEFAULT_MODEL`

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-client.test.js`**

创建 `projects/apps/algo-plan/tests/llm-client.test.js`：

```javascript
"use strict"
/**
 * llm-client.test.js —— LLM 客户端测试（**注入假 fetch，全程不联网**）
 *
 * 钉住：
 *   1. 关闭态（NullClient）返回明确中文提示且不抛错；
 *   2. provider 与密钥的解析顺序：显式 > 环境变量 > 按密钥推断；
 *   3. 方舟走 OpenAI 兼容的 /chat/completions，Anthropic 走 /v1/messages；
 *   4. Anthropic **不发 temperature**（claude-opus-5 已移除采样参数，传了 400）。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  createLlmClient,
  ArkClient,
  AnthropicClient,
  NullClient,
  keySourceOf,
  ARK_DEFAULT_BASE_URL,
  ARK_DEFAULT_MODEL,
  ANTHROPIC_DEFAULT_BASE_URL,
  ANTHROPIC_DEFAULT_MODEL,
} = require("../core/llm/client.js")

/** 造一个假 fetch：记录请求，返回指定响应。测试全程不发起真实请求。 */
function makeFakeFetch(payload, status) {
  const records = []
  const fn = async function (url, options) {
    records.push({ url: url, options: options })
    const text = typeof payload === "string" ? payload : JSON.stringify(payload)
    const code = status === undefined ? 200 : status
    return {
      ok: code < 400,
      status: code,
      text: async function () { return text },
    }
  }
  fn.records = records
  return fn
}

test("NullClient 返回明确的中文提示，且不抛错", async function () {
  const client = new NullClient("没有配置密钥")
  assert.equal(client.name, "null")
  const text = await client.complete({ system: "s", user: "u" })
  assert.equal(typeof text, "string")
  assert.ok(text.includes("LLM 未启用"), "提示里应写明 LLM 未启用")
  assert.ok(text.includes("没有配置密钥"), "提示里应写明关闭原因")
  assert.ok(text.includes("不受影响"), "提示里应说明其余功能不受影响")
})

test("createLlmClient：没有任何配置时降级成 null 客户端", function () {
  const client = createLlmClient({ env: {} })
  assert.equal(client.name, "null")
})

test("createLlmClient：有 ARK_API_KEY 就用 ark", function () {
  const client = createLlmClient({ env: { ARK_API_KEY: "k" } })
  assert.equal(client.name, "ark")
  assert.equal(client.model, ARK_DEFAULT_MODEL)
})

test("createLlmClient：有 ANTHROPIC_API_KEY 就用 anthropic", function () {
  const client = createLlmClient({ env: { ANTHROPIC_API_KEY: "k" } })
  assert.equal(client.name, "anthropic")
  assert.equal(client.model, ANTHROPIC_DEFAULT_MODEL)
})

test("createLlmClient：显式 provider 优先于环境变量推断", function () {
  const client = createLlmClient({ provider: "anthropic", env: { ARK_API_KEY: "k" } })
  assert.equal(client.name, "anthropic")
})

test("createLlmClient：provider 指定了但没有密钥，降级成 null 而不是抛错", function () {
  const client = createLlmClient({ provider: "ark", env: {} })
  assert.equal(client.name, "null")
  assert.ok(client.reason.includes("API Key"), "关闭原因里应提到 API Key")
})

test("createLlmClient：ALGO_PLAN_LLM_ENABLED=0 强制关闭", function () {
  const client = createLlmClient({ env: { ARK_API_KEY: "k", ALGO_PLAN_LLM_ENABLED: "0" } })
  assert.equal(client.name, "null")
})

test("createLlmClient：enabled=false 显式关闭", function () {
  const client = createLlmClient({ enabled: false, env: { ARK_API_KEY: "k" } })
  assert.equal(client.name, "null")
})

test("createLlmClient：provider 写 null 强制关闭", function () {
  const client = createLlmClient({ provider: "null", env: { ARK_API_KEY: "k" } })
  assert.equal(client.name, "null")
})

test("createLlmClient：未知 provider 降级成 null 而不是抛错", function () {
  const client = createLlmClient({ provider: "gemini", env: { ARK_API_KEY: "k" } })
  assert.equal(client.name, "null")
  assert.ok(client.reason.includes("provider"), "关闭原因里应提到 provider")
})

test("createLlmClient：环境变量可以覆盖地址与模型", function () {
  const client = createLlmClient({
    env: { ARK_API_KEY: "k", ARK_BASE_URL: "https://ark.test/api/v3", ALGO_PLAN_LLM_MODEL: "my-model" },
  })
  assert.equal(client.name, "ark")
  assert.equal(client.baseUrl, "https://ark.test/api/v3")
  assert.equal(client.model, "my-model")
})

test("默认地址与模型名固定", function () {
  assert.equal(ARK_DEFAULT_BASE_URL, "https://ark.cn-beijing.volces.com/api/v3")
  assert.equal(ANTHROPIC_DEFAULT_BASE_URL, "https://api.anthropic.com")
  assert.equal(ARK_DEFAULT_MODEL, "doubao-seed-1-6-251015")
  assert.equal(ANTHROPIC_DEFAULT_MODEL, "claude-opus-5")
})

test("ArkClient：按方舟的 OpenAI 兼容形状发请求，读 choices[0].message.content", async function () {
  const fake = makeFakeFetch({ choices: [{ message: { content: "  答案  " } }] })
  const client = new ArkClient({ apiKey: "secret", fetchImpl: fake })
  const text = await client.complete({ system: "系统提示", user: "用户提示", temperature: 0.4 })
  assert.equal(text, "答案")
  assert.equal(fake.records.length, 1)
  const req = fake.records[0]
  assert.equal(req.url, ARK_DEFAULT_BASE_URL + "/chat/completions")
  assert.equal(req.options.method, "POST")
  assert.equal(req.options.headers.authorization, "Bearer secret")
  assert.equal(req.options.headers["content-type"], "application/json")
  const body = JSON.parse(req.options.body)
  assert.equal(body.model, ARK_DEFAULT_MODEL)
  assert.deepEqual(body.messages, [
    { role: "system", content: "系统提示" },
    { role: "user", content: "用户提示" },
  ])
  assert.equal(body.temperature, 0.4)
  assert.equal(body.stream, false)
})

test("ArkClient：没给 temperature 就不发这个字段", async function () {
  const fake = makeFakeFetch({ choices: [{ message: { content: "x" } }] })
  const client = new ArkClient({ apiKey: "secret", fetchImpl: fake })
  await client.complete({ system: "s", user: "u" })
  const body = JSON.parse(fake.records[0].options.body)
  assert.ok(!("temperature" in body), "没给 temperature 时不该发这个字段")
})

test("ArkClient：baseUrl 与 model 可以覆盖", async function () {
  const fake = makeFakeFetch({ choices: [{ message: { content: "x" } }] })
  const client = new ArkClient({
    apiKey: "secret",
    baseUrl: "https://example.test/v1/",
    model: "my-model",
    fetchImpl: fake,
  })
  await client.complete({ system: "s", user: "u" })
  const req = fake.records[0]
  assert.equal(req.url, "https://example.test/v1/chat/completions")
  assert.equal(JSON.parse(req.options.body).model, "my-model")
})

test("AnthropicClient：按 Messages API 形状发请求，读 content[] 里的 text", async function () {
  const fake = makeFakeFetch({
    content: [
      { type: "text", text: "第一段" },
      { type: "text", text: "第二段" },
    ],
  })
  const client = new AnthropicClient({ apiKey: "secret", fetchImpl: fake })
  const text = await client.complete({ system: "系统提示", user: "用户提示", temperature: 0.4 })
  assert.equal(text, "第一段\n第二段")
  const req = fake.records[0]
  assert.equal(req.url, ANTHROPIC_DEFAULT_BASE_URL + "/v1/messages")
  assert.equal(req.options.headers["x-api-key"], "secret")
  assert.equal(req.options.headers["anthropic-version"], "2023-06-01")
  const body = JSON.parse(req.options.body)
  assert.equal(body.model, ANTHROPIC_DEFAULT_MODEL)
  assert.equal(body.system, "系统提示")
  assert.deepEqual(body.messages, [{ role: "user", content: "用户提示" }])
  assert.ok(!("temperature" in body), "claude-opus-5 已移除采样参数，不能发 temperature")
})

test("AnthropicClient：忽略非 text 类型的 content 块", async function () {
  const fake = makeFakeFetch({
    content: [{ type: "thinking", thinking: "…" }, { type: "text", text: "正文" }],
  })
  const client = new AnthropicClient({ apiKey: "secret", fetchImpl: fake })
  const text = await client.complete({ system: "s", user: "u" })
  assert.equal(text, "正文")
})

test("客户端在接口报错时抛出带状态码的中文错误", async function () {
  const fake = makeFakeFetch({ error: { message: "InvalidEndpointOrModel.NotFound" } }, 404)
  const client = new ArkClient({ apiKey: "secret", fetchImpl: fake })
  await assert.rejects(
    function () { return client.complete({ system: "s", user: "u" }) },
    function (err) {
      assert.ok(err instanceof Error)
      assert.ok(err.message.includes("404"), "错误信息里应带状态码")
      assert.ok(err.message.includes("InvalidEndpointOrModel.NotFound"), "错误信息里应带上游返回的详情")
      return true
    }
  )
})

test("客户端在响应里没有文本时抛出中文错误", async function () {
  const fake = makeFakeFetch({ choices: [] })
  const client = new ArkClient({ apiKey: "secret", fetchImpl: fake })
  await assert.rejects(function () { return client.complete({ system: "s", user: "u" }) }, /没有返回文本/)
})

test("keySourceOf 说明密钥来源，绝不回显密钥本身", function () {
  assert.equal(keySourceOf("ark", { ARK_API_KEY: "secret" }), "环境变量 ARK_API_KEY")
  assert.equal(keySourceOf("anthropic", { ANTHROPIC_API_KEY: "secret" }), "环境变量 ANTHROPIC_API_KEY")
  assert.ok(keySourceOf("ark", {}).includes("未配置"))
  assert.ok(!keySourceOf("ark", { ARK_API_KEY: "secret" }).includes("secret"))
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-client.test.js` 报 `Cannot find module '../core/llm/client.js'`。

- [ ] **Step 3: 写实现 `core/llm/client.js`**

创建 `projects/apps/algo-plan/core/llm/client.js`：

```javascript
"use strict"
/**
 * client.js —— LLM 客户端：ArkClient / AnthropicClient / NullClient
 *
 * 统一接口（接口契约 §5）：
 *   client.complete({system, user, temperature}) -> Promise<string>
 *   client.name -> "ark" | "anthropic" | "null"
 *
 * 零 npm 依赖，用 Node 24 内置的全局 fetch。
 *
 * 调用形状的来源（实地勘察出来的，不是凭记忆写的）：
 *   方舟：arkcli 自带示例 C:/Users/yinch/.claude/skills/arkcli-code-example/assets/demo-code/python.py
 *         base https://ark.cn-beijing.volces.com/api/v3，
 *         POST {base}/chat/completions，头 Authorization: Bearer $ARK_API_KEY，
 *         请求体 {model, messages:[{role,content}], temperature, max_tokens, stream:false}，
 *         读 choices[0].message.content。
 *         模型名必须是完整版本化 ID 或 ep- 接入点 ID，族名会 404。
 *   Anthropic：claude-api skill 的 curl/examples.md
 *         POST https://api.anthropic.com/v1/messages，
 *         头 x-api-key 与 anthropic-version: 2023-06-01，
 *         请求体 {model, max_tokens, system, messages:[{role:"user",content}]}，
 *         读 content[] 里 type=="text" 的 text。
 *         claude-opus-5 与 claude-sonnet-5 **已移除 temperature/top_p/top_k**，
 *         传了返回 400，所以本实现**不转发 temperature**。
 *
 * 密钥只从环境变量读（ARK_API_KEY / ANTHROPIC_API_KEY），
 * **绝不**写进 settings 表、**绝不**写进代码、**绝不**进 git（G27）。
 */

const ARK_DEFAULT_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
const ARK_DEFAULT_MODEL = "doubao-seed-1-6-251015"
const ANTHROPIC_DEFAULT_BASE_URL = "https://api.anthropic.com"
const ANTHROPIC_DEFAULT_MODEL = "claude-opus-5"
const ARK_MAX_TOKENS = 4096
const ANTHROPIC_MAX_TOKENS = 16000
const ANTHROPIC_VERSION = "2023-06-01"

/**
 * 关闭态客户端：不联网、不抛错，返回明确的中文提示。
 * 这是「把 LLM 关掉，app 仍然完整可用」（G23）的最后一档兜底。
 */
class NullClient {
  constructor(reason) {
    this.name = "null"
    this.model = "null"
    this.reason = reason || "LLM 未启用"
  }

  async complete() {
    return "【LLM 未启用】" + this.reason + "。App 的其余功能（排程、判题、复习、进度）不受影响。"
  }
}

/** 火山方舟客户端：OpenAI 兼容的 /chat/completions */
class ArkClient {
  constructor(opts) {
    const o = opts || {}
    this.name = "ark"
    this.apiKey = o.apiKey || ""
    this.baseUrl = stripTrailingSlash(o.baseUrl || ARK_DEFAULT_BASE_URL)
    this.model = o.model || ARK_DEFAULT_MODEL
    this.maxTokens = o.maxTokens || ARK_MAX_TOKENS
    this.fetchImpl = o.fetchImpl || globalThis.fetch
  }

  async complete(request) {
    const req = request || {}
    const body = {
      model: this.model,
      messages: [
        { role: "system", content: String(req.system || "") },
        { role: "user", content: String(req.user || "") },
      ],
      max_tokens: this.maxTokens,
      stream: false,
    }
    if (typeof req.temperature === "number" && Number.isFinite(req.temperature)) {
      body.temperature = req.temperature
    }
    const res = await this.fetchImpl(this.baseUrl + "/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer " + this.apiKey,
      },
      body: JSON.stringify(body),
    })
    const payload = await readBody(res)
    if (!res.ok) {
      throw new Error("方舟接口返回 " + res.status + "：" + errorText(payload))
    }
    const message = payload && payload.choices && payload.choices[0] ? payload.choices[0].message : null
    const content = message ? message.content : null
    if (typeof content !== "string" || content.trim() === "") {
      throw new Error("方舟接口没有返回文本内容")
    }
    return content.trim()
  }
}

/** Anthropic 客户端：Messages API */
class AnthropicClient {
  constructor(opts) {
    const o = opts || {}
    this.name = "anthropic"
    this.apiKey = o.apiKey || ""
    this.baseUrl = stripTrailingSlash(o.baseUrl || ANTHROPIC_DEFAULT_BASE_URL)
    this.model = o.model || ANTHROPIC_DEFAULT_MODEL
    this.maxTokens = o.maxTokens || ANTHROPIC_MAX_TOKENS
    this.fetchImpl = o.fetchImpl || globalThis.fetch
  }

  async complete(request) {
    const req = request || {}
    // 故意不转发 temperature：claude-opus-5 / claude-sonnet-5 已移除采样参数，传了会 400
    const body = {
      model: this.model,
      max_tokens: this.maxTokens,
      system: String(req.system || ""),
      messages: [{ role: "user", content: String(req.user || "") }],
    }
    const res = await this.fetchImpl(this.baseUrl + "/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(body),
    })
    const payload = await readBody(res)
    if (!res.ok) {
      throw new Error("Anthropic 接口返回 " + res.status + "：" + errorText(payload))
    }
    const blocks = payload && Array.isArray(payload.content) ? payload.content : []
    const text = blocks
      .filter(function (b) { return b && b.type === "text" && typeof b.text === "string" })
      .map(function (b) { return b.text })
      .join("\n")
      .trim()
    if (text === "") {
      throw new Error("Anthropic 接口没有返回文本内容")
    }
    return text
  }
}

/** 去掉地址结尾多余的斜杠 */
function stripTrailingSlash(url) {
  return String(url).replace(/\/+$/, "")
}

/** 读响应体：解析成 JSON；解析不了就包成 {raw}；读失败返回 null */
async function readBody(res) {
  let text = ""
  try {
    text = await res.text()
  } catch (err) {
    return null
  }
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch (err) {
    return { raw: text }
  }
}

/** 从错误响应里抠出一句能给人看的详情 */
function errorText(payload) {
  if (payload && payload.error && payload.error.message) return String(payload.error.message)
  if (payload && payload.message) return String(payload.message)
  if (payload && payload.raw) return String(payload.raw)
  return "没有返回错误详情"
}

/** 总开关：环境变量 ALGO_PLAN_LLM_ENABLED，0/false/off/no 表示关 */
function readEnabledFlag(env) {
  const raw = env.ALGO_PLAN_LLM_ENABLED
  if (raw === undefined || raw === null || String(raw).trim() === "") return true
  const text = String(raw).trim().toLowerCase()
  if (text === "0" || text === "false" || text === "off" || text === "no") return false
  return true
}

/** 归一 provider 名字；认不出来的原样返回，由调用方降级 */
function normalizeProvider(value) {
  if (value === undefined || value === null) return ""
  const text = String(value).trim().toLowerCase()
  if (text === "") return ""
  if (text === "ark" || text === "volcengine" || text === "volc" || text === "doubao") return "ark"
  if (text === "anthropic" || text === "claude") return "anthropic"
  if (text === "null" || text === "none" || text === "off" || text === "false" || text === "disabled") return "null"
  return text
}

/** 地址：显式 > ALGO_PLAN_LLM_BASE_URL > ARK_BASE_URL > 内置默认 */
function resolveBaseUrl(o, env, provider) {
  if (o.baseUrl) return o.baseUrl
  if (env.ALGO_PLAN_LLM_BASE_URL) return env.ALGO_PLAN_LLM_BASE_URL
  if (provider === "ark" && env.ARK_BASE_URL) return env.ARK_BASE_URL
  if (provider === "ark") return ARK_DEFAULT_BASE_URL
  return ANTHROPIC_DEFAULT_BASE_URL
}

/** 模型：显式 > ALGO_PLAN_LLM_MODEL > 内置默认 */
function resolveModel(o, env, provider) {
  if (o.model) return o.model
  if (env.ALGO_PLAN_LLM_MODEL) return env.ALGO_PLAN_LLM_MODEL
  return provider === "ark" ? ARK_DEFAULT_MODEL : ANTHROPIC_DEFAULT_MODEL
}

/**
 * 造一个 LLM 客户端。
 * @param {{provider?: string, apiKey?: string, baseUrl?: string, model?: string,
 *          env?: object, fetchImpl?: Function, enabled?: boolean}} opts
 *   provider / apiKey / baseUrl / model 的含义与接口契约 §5 一致；
 *   env / fetchImpl / enabled 是 M6 为可测试性与总开关新增的字段。
 * @returns {{complete: Function, name: string}}
 */
function createLlmClient(opts) {
  const o = opts || {}
  const env = o.env || process.env
  const fetchImpl = o.fetchImpl || globalThis.fetch

  // 1. 总开关
  if (o.enabled === false) return new NullClient("已在设置里关闭 LLM")
  if (readEnabledFlag(env) === false) return new NullClient("环境变量 ALGO_PLAN_LLM_ENABLED 把 LLM 关了")

  // 2. provider：显式 > 环境变量 > 按密钥推断
  let provider = normalizeProvider(o.provider || env.ALGO_PLAN_LLM_PROVIDER)
  if (!provider) {
    if (env.ARK_API_KEY) provider = "ark"
    else if (env.ANTHROPIC_API_KEY) provider = "anthropic"
  }
  if (provider === "null") return new NullClient("provider 设为 null")
  if (!provider) return new NullClient("没有配置 provider，也没有找到 ARK_API_KEY 或 ANTHROPIC_API_KEY")
  if (provider !== "ark" && provider !== "anthropic") {
    return new NullClient("未知的 LLM provider：" + provider)
  }

  // 3. 密钥：只从环境变量读
  const apiKey = o.apiKey || (provider === "ark" ? env.ARK_API_KEY : env.ANTHROPIC_API_KEY)
  if (!apiKey) {
    return new NullClient("provider 是 " + provider + "，但没有配置对应的 API Key")
  }

  // 4. 地址与模型
  const common = {
    apiKey: apiKey,
    baseUrl: resolveBaseUrl(o, env, provider),
    model: resolveModel(o, env, provider),
    fetchImpl: fetchImpl,
  }
  return provider === "ark" ? new ArkClient(common) : new AnthropicClient(common)
}

/**
 * 说明密钥来自哪里。**只说变量名，绝不回显密钥本身**（G27）。
 * @param {string} provider
 * @param {object} env
 * @returns {string}
 */
function keySourceOf(provider, env) {
  const e = env || process.env
  if (provider === "ark") {
    return e.ARK_API_KEY ? "环境变量 ARK_API_KEY" : "未配置（需要环境变量 ARK_API_KEY）"
  }
  if (provider === "anthropic") {
    return e.ANTHROPIC_API_KEY ? "环境变量 ANTHROPIC_API_KEY" : "未配置（需要环境变量 ANTHROPIC_API_KEY）"
  }
  return "未配置"
}

module.exports = {
  createLlmClient: createLlmClient,
  ArkClient: ArkClient,
  AnthropicClient: AnthropicClient,
  NullClient: NullClient,
  keySourceOf: keySourceOf,
  ARK_DEFAULT_BASE_URL: ARK_DEFAULT_BASE_URL,
  ARK_DEFAULT_MODEL: ARK_DEFAULT_MODEL,
  ANTHROPIC_DEFAULT_BASE_URL: ANTHROPIC_DEFAULT_BASE_URL,
  ANTHROPIC_DEFAULT_MODEL: ANTHROPIC_DEFAULT_MODEL,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-client.test.js` 与 `llm-prompts.test.js` 两个套件全绿（PASS），退出码 0。

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/core/llm/client.js apps/algo-plan/tests/llm-client.test.js
git commit -m "feat(algo-plan): 新增方舟、Anthropic 与关闭态三套 LLM 客户端

- ArkClient 走方舟 OpenAI 兼容的 /chat/completions，AnthropicClient 走 /v1/messages
- Anthropic 不转发 temperature，避免 claude-opus-5 采样参数被移除后返回 400
- NullClient 返回明确中文提示且不抛错，没有密钥时自动降级
- 密钥只从 ARK_API_KEY / ANTHROPIC_API_KEY 读取，测试全部注入假 fetch 不联网"
git push origin main
```

---

## Task 3: 成本护栏（core/llm/guard.js）

设计文档 §6.6：「单次会话请求上限 + 每日请求上限，超了直接停并提示『今天用完了』」。
接口契约 §5 冻结了 `checkQuota(store, key) -> {ok, used, limit}` 与 `consumeQuota(store, key, n) -> {used, limit}`。

**计数落在 M1 已有的 `settings` 表里**（G30）：**不新增数据表**。

| settings 键 | 含义 | 默认 |
|---|---|---|
| `llm.quota.session_limit` | 单次会话请求上限 | 20 |
| `llm.quota.daily_limit` | 每日请求上限 | 100 |
| `llm.quota.session.<sessionId>` | 本次会话已用次数 | 0 |
| `llm.quota.daily.<YYYY-MM-DD>` | 今天已用次数 | 0 |

**Files:**
- Create: `projects/apps/algo-plan/core/llm/guard.js`
- Test: `projects/apps/algo-plan/tests/llm-guard.test.js`

**Interfaces:**
- Consumes:
  - `core/bank/problem.js` 的 `today() -> "YYYY-MM-DD"`（M1 已冻结，只读不改）
  - `store.getSetting(key, fallback?) -> string|null` 与 `store.setSetting(key, value)`（M1 已冻结的 `settings` 表）
- Produces:
  - `checkQuota(store, key) -> {ok: boolean, used: number, limit: number}`
  - `consumeQuota(store, key, n) -> {used: number, limit: number}`
  - `sessionKey(sessionId) -> string`
  - `dailyKey(date) -> string`
  - `checkAll(store, sessionId, date) -> {ok, session: {ok, used, limit}, daily: {ok, used, limit}, message}`
  - `consumeAll(store, sessionId, date) -> {session: {used, limit}, daily: {used, limit}}`
  - `limits(store) -> {sessionLimit: number, dailyLimit: number}`
  - `seedLimits(store, env)` —— 启动时把环境变量里的配额写进 settings 表（**只在键不存在时写**）

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-guard.test.js`**

创建 `projects/apps/algo-plan/tests/llm-guard.test.js`：

```javascript
"use strict"
/**
 * llm-guard.test.js —— 成本护栏测试（**不联网、不起服务**）
 *
 * 钉住：
 *   1. 单次会话上限 20 次、每日上限 100 次（G31）；
 *   2. 超了 ok 变 false，且每日超限时提示里含「今天用完了」；
 *   3. 计数真的落在 settings 表里（这里用一个最小的假 store）。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  checkQuota,
  consumeQuota,
  sessionKey,
  dailyKey,
  checkAll,
  consumeAll,
  limits,
  seedLimits,
} = require("../core/llm/guard.js")

/** 最小假 store：只实现 settings 表的两个方法，接口与 M1 冻结的一致 */
function makeStore(initial) {
  const data = Object.assign({}, initial || {})
  return {
    data: data,
    getSetting: function (key, fallback) {
      if (Object.prototype.hasOwnProperty.call(data, key)) return data[key]
      return fallback === undefined ? null : fallback
    },
    setSetting: function (key, value) { data[key] = String(value) },
  }
}

test("默认上限：单次会话 20 次、每日 100 次", function () {
  const store = makeStore()
  const l = limits(store)
  assert.equal(l.sessionLimit, 20)
  assert.equal(l.dailyLimit, 100)
})

test("checkQuota：新会话还没用就是 ok，用满了就 false", function () {
  const store = makeStore()
  const key = sessionKey("s1")
  const before = checkQuota(store, key)
  assert.equal(before.ok, true)
  assert.equal(before.used, 0)
  assert.equal(before.limit, 20)

  consumeQuota(store, key, 20)
  const after = checkQuota(store, key)
  assert.equal(after.ok, false)
  assert.equal(after.used, 20)
})

test("consumeQuota：计数累加，并写回 settings 表", function () {
  const store = makeStore()
  const key = sessionKey("s2")
  consumeQuota(store, key)
  consumeQuota(store, key)
  assert.equal(store.getSetting(key), "2")
  const r = consumeQuota(store, key, 3)
  assert.equal(r.used, 5)
  assert.equal(r.limit, 20)
})

test("上限可以在 settings 表里调，调完立即生效", function () {
  const store = makeStore({ "llm.quota.session_limit": "2" })
  const key = sessionKey("s3")
  consumeQuota(store, key)
  consumeQuota(store, key)
  assert.equal(checkQuota(store, key).ok, false)
  assert.equal(checkQuota(store, key).limit, 2)
})

test("sessionKey 与 dailyKey 的键名固定", function () {
  assert.equal(sessionKey("abc"), "llm.quota.session.abc")
  assert.equal(sessionKey(""), "llm.quota.session.default")
  assert.equal(sessionKey(undefined), "llm.quota.session.default")
  assert.ok(dailyKey("2026-11-11").startsWith("llm.quota.daily."))
  assert.equal(dailyKey("2026-11-11"), "llm.quota.daily.2026-11-11")
})

test("checkAll：两个额度都没超就 ok，message 为空", function () {
  const store = makeStore()
  const r = checkAll(store, "s4", "2026-11-11")
  assert.equal(r.ok, true)
  assert.equal(r.message, "")
  assert.equal(r.session.limit, 20)
  assert.equal(r.daily.limit, 100)
})

test("checkAll：会话额度用完时提示会话上限", function () {
  const store = makeStore()
  consumeQuota(store, sessionKey("s5"), 20)
  const r = checkAll(store, "s5", "2026-11-11")
  assert.equal(r.ok, false)
  assert.ok(r.message.includes("本次会话"), "提示里应说明是会话额度用完：" + r.message)
  assert.ok(!r.message.includes("今天用完了"), "会话额度用完不该说『今天用完了』")
})

test("checkAll：每日额度用完时提示『今天用完了』", function () {
  const store = makeStore()
  consumeQuota(store, dailyKey("2026-11-11"), 100)
  const r = checkAll(store, "s6", "2026-11-11")
  assert.equal(r.ok, false)
  assert.ok(r.message.includes("今天用完了"), "提示里应包含『今天用完了』：" + r.message)
  assert.equal(r.daily.ok, false)
})

test("consumeAll：会话与每日两个计数同时扣", function () {
  const store = makeStore()
  consumeAll(store, "s7", "2026-11-11")
  assert.equal(store.getSetting(sessionKey("s7")), "1")
  assert.equal(store.getSetting(dailyKey("2026-11-11")), "1")
})

test("seedLimits：环境变量里的配额写进 settings 表，但不覆盖已有的值", function () {
  const store = makeStore({ "llm.quota.session_limit": "7" })
  seedLimits(store, { ALGO_PLAN_LLM_SESSION_LIMIT: "30", ALGO_PLAN_LLM_DAILY_LIMIT: "200" })
  assert.equal(store.getSetting("llm.quota.session_limit"), "7", "已有的值不该被环境变量覆盖")
  assert.equal(store.getSetting("llm.quota.daily_limit"), "200", "没有的值应从环境变量写入")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-guard.test.js` 报 `Cannot find module '../core/llm/guard.js'`。

- [ ] **Step 3: 写实现 `core/llm/guard.js`**

创建 `projects/apps/algo-plan/core/llm/guard.js`：

```javascript
"use strict"
/**
 * guard.js —— 成本护栏：单次会话请求上限 + 每日请求上限
 *
 * 设计文档 §6.6：单次会话请求上限 + 每日请求上限，超了直接停并提示「今天用完了」。
 *
 * 计数落在 M1 已有的 settings 表里（G30），**不新增数据表**：
 *   llm.quota.session_limit         单次会话请求上限，默认 20
 *   llm.quota.daily_limit           每日请求上限，默认 100
 *   llm.quota.session.<sessionId>   本次会话已用次数
 *   llm.quota.daily.<YYYY-MM-DD>    今天已用次数
 */

const { today } = require("../bank/problem.js")

const DEFAULT_SESSION_LIMIT = 20
const DEFAULT_DAILY_LIMIT = 100
const SESSION_LIMIT_KEY = "llm.quota.session_limit"
const DAILY_LIMIT_KEY = "llm.quota.daily_limit"
const SESSION_PREFIX = "llm.quota.session."
const DAILY_PREFIX = "llm.quota.daily."

/** 会话计数键；没给 sessionId 就落到 default */
function sessionKey(sessionId) {
  return SESSION_PREFIX + (sessionId ? String(sessionId) : "default")
}

/** 每日计数键；没给日期就落到今天 */
function dailyKey(date) {
  return DAILY_PREFIX + (date ? String(date) : today())
}

/** 这个键是会话计数还是每日计数 */
function isSessionKey(key) {
  return String(key).indexOf(SESSION_PREFIX) === 0
}

/** 读这个键对应的上限；settings 表里没配就用默认值 */
function limitFor(store, key) {
  const session = isSessionKey(key)
  const settingKey = session ? SESSION_LIMIT_KEY : DAILY_LIMIT_KEY
  const fallback = session ? DEFAULT_SESSION_LIMIT : DEFAULT_DAILY_LIMIT
  const raw = store.getSetting(settingKey, String(fallback))
  const value = Number(raw)
  return Number.isFinite(value) && value >= 0 ? value : fallback
}

/** 读计数，脏值当 0 */
function readCount(store, key) {
  const raw = store.getSetting(key, "0")
  const value = Number(raw)
  return Number.isFinite(value) && value > 0 ? value : 0
}

/** 步长归一：非法值当 1 */
function normalizeStep(n) {
  if (n === undefined || n === null) return 1
  const value = Number(n)
  return Number.isFinite(value) && value > 0 ? value : 1
}

/**
 * 查配额。
 * @param {{getSetting: Function}} store
 * @param {string} key 会话键或每日键
 * @returns {{ok: boolean, used: number, limit: number}}
 */
function checkQuota(store, key) {
  const used = readCount(store, key)
  const limit = limitFor(store, key)
  return { ok: used < limit, used: used, limit: limit }
}

/**
 * 扣配额。
 * @param {{getSetting: Function, setSetting: Function}} store
 * @param {string} key
 * @param {number} [n] 本次扣几个，默认 1
 * @returns {{used: number, limit: number}}
 */
function consumeQuota(store, key, n) {
  const used = readCount(store, key) + normalizeStep(n)
  store.setSetting(key, String(used))
  return { used: used, limit: limitFor(store, key) }
}

/** 额度用完时给用户看的中文提示 */
function quotaMessage(session, daily) {
  if (!daily.ok) {
    return "今天用完了：LLM 每日请求次数已达上限（" + daily.limit + " 次）。明天再来，或者调高每日配额。"
  }
  return "本次会话的 LLM 请求次数已用完（上限 " + session.limit + " 次）。换个会话再来，或者调高单次会话配额。"
}

/**
 * 同时查会话与每日两个配额。
 * @returns {{ok: boolean, session: object, daily: object, message: string}}
 */
function checkAll(store, sessionId, date) {
  const session = checkQuota(store, sessionKey(sessionId))
  const daily = checkQuota(store, dailyKey(date))
  const ok = session.ok && daily.ok
  return {
    ok: ok,
    session: session,
    daily: daily,
    message: ok ? "" : quotaMessage(session, daily),
  }
}

/** 同时扣会话与每日两个计数 */
function consumeAll(store, sessionId, date) {
  return {
    session: consumeQuota(store, sessionKey(sessionId), 1),
    daily: consumeQuota(store, dailyKey(date), 1),
  }
}

/** 当前生效的两个上限 */
function limits(store) {
  return {
    sessionLimit: limitFor(store, sessionKey("probe")),
    dailyLimit: limitFor(store, dailyKey("probe")),
  }
}

/**
 * 启动时把环境变量里的配额写进 settings 表。
 * **只在键不存在时写**：设置页里改过的值优先，不被环境变量覆盖。
 * @param {{getSetting: Function, setSetting: Function}} store
 * @param {object} env
 */
function seedLimits(store, env) {
  const e = env || {}
  const session = Number(e.ALGO_PLAN_LLM_SESSION_LIMIT)
  if (Number.isFinite(session) && session > 0 && !store.getSetting(SESSION_LIMIT_KEY, "")) {
    store.setSetting(SESSION_LIMIT_KEY, String(Math.floor(session)))
  }
  const daily = Number(e.ALGO_PLAN_LLM_DAILY_LIMIT)
  if (Number.isFinite(daily) && daily > 0 && !store.getSetting(DAILY_LIMIT_KEY, "")) {
    store.setSetting(DAILY_LIMIT_KEY, String(Math.floor(daily)))
  }
}

module.exports = {
  checkQuota: checkQuota,
  consumeQuota: consumeQuota,
  sessionKey: sessionKey,
  dailyKey: dailyKey,
  checkAll: checkAll,
  consumeAll: consumeAll,
  limits: limits,
  seedLimits: seedLimits,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-guard.test.js`、`llm-client.test.js`、`llm-prompts.test.js` 三个套件全绿（PASS），退出码 0。

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/core/llm/guard.js apps/algo-plan/tests/llm-guard.test.js
git commit -m "feat(algo-plan): 新增 LLM 成本护栏与会话每日双配额

- 单次会话上限 20 次、每日上限 100 次，超了直接停并提示「今天用完了」
- 计数落在已有的 settings 表，不新增数据表
- 上限可在 settings 表里调整，环境变量只在键不存在时兜底写入
- 导出 checkQuota / consumeQuota，与接口契约的签名一致"
git push origin main
```

---

## Task 4: LLM 服务层（core/llm/service.js）

把提示词、客户端、护栏、题库串起来，做成五个场景：
**讲解 / 分级求助 / 批改思路 / 现造新题 / 补全缺口**。

这个 task 落地两条纪律（G24 / G25）：
- **不主动泄题**：service 构造上下文时**只挑安全字段**，参考解法进不了提示词（第二道闸）。
- **产出全部可追溯**：现造的新题**落盘进 `learning/bank/`**（`source: llm`，id 用 M1 的 `makeLlmId`）；
  每次讲解/求助/批改都记 **model + prompt 摘要**到 settings 表。

**Files:**
- Create: `projects/apps/algo-plan/core/llm/service.js`
- Test: `projects/apps/algo-plan/tests/llm-service.test.js`

**Interfaces:**
- Consumes:
  - `core/llm/prompts.js` 的 `buildPrompt(kind, context)`、`parseResponse(text, kind)`、`EXPLAIN_LEVELS`、`HINT_LEVELS`（Task 1）
  - `core/llm/client.js` 的 `NullClient`、`keySourceOf(provider, env)`（Task 2）
  - `core/llm/guard.js` 的 `checkAll(store, sessionId, date)`、`consumeAll(store, sessionId, date)`、`limits(store)`（Task 3）
  - `core/bank/problem.js` 的 `makeLlmId(seed)`、`createProblem(input)`、`normalizeTopics(list)`、`TRACKS`、`DIFFICULTIES`（M1 已冻结，只读不改）
  - `core/bank/provider.js` 的 `provider.get(id)` 与 `provider.put(problem)`（M1 已冻结）
- Produces:
  - `createLlmService({client?, getClient?, store, provider, env?, now?}) -> service`
  - `service.explain({problem, level?, sessionId?}) -> Promise<{text, model}>`
  - `service.hint({problem, level?, sessionId?}) -> Promise<{text, model}>`
  - `service.gradeIdea({problem, idea, sessionId?}) -> Promise<{verdict, comment, model}>`
  - `service.generate({track, topics?, difficulty?, sessionId?}) -> Promise<{problem, model, file}>`
  - `service.fill({problem, sessionId?}) -> Promise<{problem, model, file}>`
  - `service.describe(sessionId?) -> object`（给设置页看：开关、provider、模型、密钥来源、剩余配额）
  - `readLlmSettings(store) -> {enabled, provider, model, baseUrl}`
  - `writeLlmSettings(store, patch) -> {enabled, provider, model, baseUrl}`（**只管这四项，绝不写密钥**）

**错误约定：** 业务错误统一抛 `Error`，并在错误对象上挂 `status`：
`400` 参数不对、`429` 配额用完、`503` LLM 没开。前端只看 `status` 决定提示语。

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-service.test.js`**

创建 `projects/apps/algo-plan/tests/llm-service.test.js`：

```javascript
"use strict"
/**
 * llm-service.test.js —— LLM 服务层测试（**注入假 client，不联网**）
 *
 * 钉住：
 *   1. 五个场景的行为与返回形状；
 *   2. 不主动泄题：service 构造的提示词里没有参考解法；
 *   3. 产出可追溯：造的新题真的落盘进 bank（source=llm，id 走 makeLlmId），
 *      讲解记下 model + prompt 摘要；
 *   4. 成本护栏：超配额直接停并提示「今天用完了」；
 *   5. LLM 关着：explain/hint/gradeIdea 返回明确中文提示，generate/fill 报 503，都不崩。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const { createLlmService } = require("../core/llm/service.js")

/** 最小假 store：只实现 settings 表的两个方法 */
function makeStore(initial) {
  const data = Object.assign({}, initial || {})
  return {
    data: data,
    getSetting: function (key, fallback) {
      if (Object.prototype.hasOwnProperty.call(data, key)) return data[key]
      return fallback === undefined ? null : fallback
    },
    setSetting: function (key, value) { data[key] = String(value) },
  }
}

/** 假题库 provider：把题存在内存 Map 里 */
function makeProvider() {
  const files = new Map()
  return {
    files: files,
    list: async function () { return Array.from(files.values()) },
    get: async function (id) { return files.get(id) },
    put: async function (problem) {
      files.set(problem.id, problem)
      return "learning/bank/" + (problem.tracks[0] || "misc") + "/" + problem.id + ".md"
    },
    stats: async function () {
      return { fileCount: files.size, problemCount: files.size, warnings: [] }
    },
  }
}

/** 假客户端：记录每次请求，返回预置回复 */
function makeClient(reply, name) {
  const calls = []
  return {
    name: name || "ark",
    model: "fake-model",
    calls: calls,
    complete: async function (req) {
      calls.push(req)
      return typeof reply === "function" ? reply(req) : reply
    },
  }
}

/** 一道普通题 */
function makeProblem() {
  return {
    id: "lc-00001",
    source: "leetcode",
    title: "两数之和",
    difficulty: "easy",
    topics: ["哈希表"],
    tracks: ["interview"],
    status: "todo",
    needsFill: false,
    created: "2026-11-01",
    updated: "2026-11-01",
    statement: "给定整数数组 nums 和整数 target，找出和为 target 的两个整数的下标。",
    cases: [{ input: "[2,7,11,15], 9", expect: "[0,1]", tol: null }],
    solution: "int main(){ /* 参考答案 */ return 0; }",
    solutionLang: "cpp",
    extraSections: [],
  }
}

/** 造一个服务层 */
function makeService(reply, options) {
  const o = options || {}
  const store = o.store || makeStore()
  const provider = o.provider || makeProvider()
  const client = o.client || makeClient(reply)
  const service = createLlmService({
    client: client,
    store: store,
    provider: provider,
    env: o.env || {},
    now: o.now || function () { return new Date("2026-11-11T08:00:00Z") },
  })
  return { service: service, store: store, provider: provider, client: client }
}

test("explain：返回文本，并记下 model 与 prompt 摘要", async function () {
  const s = makeService("先扫一遍数组，用哈希表存见过的数。")
  const result = await s.service.explain({ problem: makeProblem(), level: "思路", sessionId: "s1" })
  assert.equal(result.text, "先扫一遍数组，用哈希表存见过的数。")
  assert.equal(result.model, "fake-model")
  const trace = JSON.parse(s.store.getSetting("llm.trace.lc-00001", "[]"))
  assert.equal(trace.length, 1)
  assert.equal(trace[0].kind, "explain")
  assert.equal(trace[0].level, "思路")
  assert.equal(trace[0].model, "fake-model")
  assert.ok(trace[0].prompt.digest.length > 0, "trace 里应记 prompt 摘要")
  assert.ok(trace[0].prompt.length > 0)
})

test("不主动泄题：service 发出去的提示词里没有参考解法", async function () {
  const s = makeService("随便讲讲")
  await s.service.explain({ problem: makeProblem(), level: "思路", sessionId: "s1" })
  await s.service.hint({ problem: makeProblem(), level: "方向", sessionId: "s1" })
  assert.equal(s.client.calls.length, 2)
  for (const call of s.client.calls) {
    assert.ok(!call.user.includes("参考答案"), "提示词里不该出现参考解法")
    assert.ok(!call.user.includes("int main"), "提示词里不该出现参考解法代码")
    assert.ok(!call.system.includes("参考答案"), "系统提示里不该出现参考解法")
  }
})

test("只有显式选『代码』档才放开给代码", async function () {
  const s = makeService("讲思路的正文")
  await s.service.explain({ problem: makeProblem(), level: "思路", sessionId: "s1" })
  const 思路档 = s.client.calls[0]
  assert.ok(思路档.system.includes("绝不给出任何可编译的完整代码"))

  await s.service.explain({ problem: makeProblem(), level: "代码", sessionId: "s1" })
  const 代码档 = s.client.calls[1]
  assert.ok(代码档.system.includes("本次允许给出完整代码"))
})

test("hint：档位非法就报错，合法就返回文本", async function () {
  const s = makeService("提示内容")
  const r = await s.service.hint({ problem: makeProblem(), level: "伪码", sessionId: "s1" })
  assert.equal(r.text, "提示内容")
  await assert.rejects(
    function () { return s.service.hint({ problem: makeProblem(), level: "神级", sessionId: "s1" }) },
    function (err) { return err.status === 400 }
  )
})

test("gradeIdea：解析出 verdict 与 comment", async function () {
  const s = makeService('{"verdict":"partial","comment":"思路对，但漏了重复元素"}')
  const r = await s.service.gradeIdea({ problem: makeProblem(), idea: "用两个指针", sessionId: "s1" })
  assert.equal(r.verdict, "partial")
  assert.equal(r.comment, "思路对，但漏了重复元素")
  assert.equal(r.model, "fake-model")
})

test("gradeIdea：模型不给 JSON 时返回 unknown，不崩", async function () {
  const s = makeService("看起来挺有道理的")
  const r = await s.service.gradeIdea({ problem: makeProblem(), idea: "用两个指针", sessionId: "s1" })
  assert.equal(r.verdict, "unknown")
  assert.ok(r.comment.length > 0)
})

test("gradeIdea：思路为空就报 400", async function () {
  const s = makeService("{}")
  await assert.rejects(
    function () { return s.service.gradeIdea({ problem: makeProblem(), idea: "  ", sessionId: "s1" }) },
    function (err) { return err.status === 400 }
  )
})

test("generate：新题落盘进 bank，source 是 llm，id 走 makeLlmId", async function () {
  const s = makeService(JSON.stringify({
    title: "三数之和",
    statement: "给一个数组，找出所有和为 0 的三元组。",
    difficulty: "medium",
    topics: ["双指针"],
    cases: [
      { input: "[-1,0,1,2,-1,-4]", expect: "[[-1,-1,2],[-1,0,1]]" },
      { input: "[0,0,0]", expect: "[[0,0,0]]" },
    ],
    solution: "int main(){ return 0; }",
    solutionLang: "cpp",
  }))
  const r = await s.service.generate({ track: "interview", topics: ["双指针"], difficulty: "medium", sessionId: "s1" })
  assert.equal(r.problem.source, "llm")
  assert.ok(r.problem.id.startsWith("llm-"), "id 应是 llm- 前缀：" + r.problem.id)
  assert.deepEqual(r.problem.tracks, ["interview"])
  assert.equal(r.problem.needsFill, false)
  assert.equal(s.provider.files.size, 1, "新题应真的落进题库")
  assert.ok(s.provider.files.has(r.problem.id))
})

test("generate：同一句题面再生成一次要报错，不覆盖已有文件", async function () {
  const 回复 = JSON.stringify({
    title: "三数之和",
    statement: "给一个数组，找出所有和为 0 的三元组。",
    difficulty: "medium",
    topics: ["双指针"],
    cases: [{ input: "[0]", expect: "[]" }],
    solution: "int main(){ return 0; }",
  })
  const s = makeService(回复)
  await s.service.generate({ track: "interview", difficulty: "medium", sessionId: "s1" })
  await assert.rejects(
    function () { return s.service.generate({ track: "interview", difficulty: "medium", sessionId: "s1" }) },
    function (err) { return err.status === 400 && err.message.includes("已经生成过") }
  )
  assert.equal(s.provider.files.size, 1, "重复生成不该多出文件")
})

test("generate：轨道非法就报 400", async function () {
  const s = makeService("{}")
  await assert.rejects(
    function () { return s.service.generate({ track: "不存在", difficulty: "easy", sessionId: "s1" }) },
    function (err) { return err.status === 400 }
  )
})

test("fill：补上缺失的题面与用例，needsFill 变 false 并落盘", async function () {
  const 题 = makeProblem()
  题.statement = ""
  题.cases = []
  题.needsFill = true
  const s = makeService(JSON.stringify({
    statement: "补出来的题面：从数组里找两个数。",
    cases: [{ input: "[2,7], 9", expect: "[0,1]" }],
  }))
  const r = await s.service.fill({ problem: 题, sessionId: "s1" })
  assert.equal(r.problem.statement, "补出来的题面：从数组里找两个数。")
  assert.equal(r.problem.cases.length, 1)
  assert.equal(r.problem.needsFill, false)
  assert.equal(s.provider.files.get(题.id).statement, r.problem.statement, "补全结果应落盘")
})

test("fill：本来就有题面与用例时保留原来的，只补缺口", async function () {
  const 题 = makeProblem()
  题.needsFill = true
  const s = makeService(JSON.stringify({
    statement: "模型另写的题面",
    cases: [{ input: "999", expect: "0" }],
  }))
  const r = await s.service.fill({ problem: 题, sessionId: "s1" })
  assert.equal(r.problem.statement, 题.statement, "已有的题面不该被改写")
  assert.equal(r.problem.cases.length, 1)
  assert.equal(r.problem.cases[0].input, "[2,7,11,15], 9", "已有的用例不该被改写")
})

test("成本护栏：每日额度用完时直接停，提示『今天用完了』", async function () {
  const store = makeStore({ "llm.quota.daily_limit": "0" })
  const s = makeService("随便", { store: store })
  await assert.rejects(
    function () { return s.service.explain({ problem: makeProblem(), level: "思路", sessionId: "s1" }) },
    function (err) {
      assert.equal(err.status, 429)
      assert.ok(err.message.includes("今天用完了"), "提示里应包含『今天用完了』：" + err.message)
      return true
    }
  )
})

test("成本护栏：会话额度用完时直接停", async function () {
  const store = makeStore({ "llm.quota.session_limit": "0" })
  const s = makeService("随便", { store: store })
  await assert.rejects(
    function () { return s.service.hint({ problem: makeProblem(), level: "方向", sessionId: "s1" }) },
    function (err) { return err.status === 429 }
  )
})

test("LLM 关着：explain / hint / gradeIdea 返回明确中文提示，不抛错", async function () {
  const client = makeClient("不会用到", "null")
  client.reason = "没有配置密钥"
  const s = makeService(null, { client: client })
  const e = await s.service.explain({ problem: makeProblem(), level: "思路", sessionId: "s1" })
  assert.ok(e.text.includes("LLM 未启用"), "提示里应写明 LLM 未启用：" + e.text)
  assert.ok(e.text.includes("不受影响"))

  const h = await s.service.hint({ problem: makeProblem(), level: "方向", sessionId: "s1" })
  assert.ok(h.text.includes("LLM 未启用"))

  const g = await s.service.gradeIdea({ problem: makeProblem(), idea: "用哈希表", sessionId: "s1" })
  assert.equal(g.verdict, "unknown")
  assert.ok(g.comment.includes("LLM 未启用"))
  assert.equal(client.calls.length, 0, "LLM 关着时不该发起任何请求")
})

test("LLM 关着：generate / fill 报 503 并且不写任何文件", async function () {
  const client = makeClient("不会用到", "null")
  client.reason = "没有配置密钥"
  const s = makeService(null, { client: client })
  await assert.rejects(
    function () { return s.service.generate({ track: "interview", difficulty: "easy", sessionId: "s1" }) },
    function (err) { return err.status === 503 }
  )
  await assert.rejects(
    function () { return s.service.fill({ problem: makeProblem(), sessionId: "s1" }) },
    function (err) { return err.status === 503 }
  )
  assert.equal(s.provider.files.size, 0, "LLM 关着时不该写题库")
})

test("describe：报告当前开关、provider、密钥来源与配额，不泄露密钥", async function () {
  const s = makeService("x", { env: { ARK_API_KEY: "super-secret" } })
  const d = s.service.describe("s1")
  assert.equal(d.effectiveProvider, "ark")
  assert.equal(d.keySource, "环境变量 ARK_API_KEY")
  assert.ok(!JSON.stringify(d).includes("super-secret"), "describe 里绝不能出现密钥本身")
  assert.equal(d.quota.sessionLimit, 20)
  assert.equal(d.quota.dailyLimit, 100)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-service.test.js` 报 `Cannot find module '../core/llm/service.js'`。

- [ ] **Step 3: 写实现 `core/llm/service.js`**

创建 `projects/apps/algo-plan/core/llm/service.js`：

```javascript
"use strict"
/**
 * service.js —— LLM 服务层：把提示词、客户端、成本护栏、题库串成五个场景
 *
 * 五个场景（设计文档 §6.2）：讲解 / 分级求助 / 批改思路 / 现造新题 / 补全缺口。
 *
 * 两条纪律（设计文档 §6.3，本文件是落地的地方）：
 *   1. 不主动泄题（G24）—— 讲解只到思路层；只有显式选「代码」档才给代码。
 *      这里构造上下文时**只挑安全字段**，参考解法根本不进提示词。
 *   2. 产出全部可追溯（G25）—— 现造的新题落盘进 learning/bank/（source: llm，
 *      id 用 M1 的 makeLlmId）；每次请求都记 model + prompt 摘要到 settings 表。
 *
 * LLM 关着时（client.name === "null"）：explain / hint / gradeIdea 返回明确的中文提示，
 * generate / fill 抛 503。两种情况都不崩，其余功能不受影响（G23）。
 */

const crypto = require("node:crypto")

const { buildPrompt, parseResponse, EXPLAIN_LEVELS, HINT_LEVELS } = require("./prompts.js")
const { NullClient, keySourceOf } = require("./client.js")
const { checkAll, consumeAll, limits, sessionKey, dailyKey } = require("./guard.js")
const {
  makeLlmId,
  createProblem,
  normalizeTopics,
  TRACKS,
  DIFFICULTIES,
} = require("../bank/problem.js")

/** 每道题最多留多少条调用记录 */
const MAX_TRACE_PER_PROBLEM = 20

/** settings 表里存 LLM 设置的键；**绝不**存密钥（G27） */
const LLM_SETTING_KEYS = {
  enabled: "llm.enabled",
  provider: "llm.provider",
  model: "llm.model",
  baseUrl: "llm.base_url",
}

/** 业务错误：400 参数不对 */
function badRequest(message) {
  const err = new Error(message)
  err.status = 400
  return err
}

/** 配额用完：429 */
function quotaError(message) {
  const err = new Error(message)
  err.status = 429
  err.quota = true
  return err
}

/** LLM 没开：503 */
function serviceUnavailable(message) {
  const err = new Error(message)
  err.status = 503
  return err
}

/** 日期格式化成 YYYY-MM-DD（与 M1 的 today() 保持一致） */
function dateStr(date) {
  const d = date instanceof Date ? date : new Date(date)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return y + "-" + m + "-" + day
}

/** 读 LLM 设置 */
function readLlmSettings(store) {
  const enabledRaw = String(store.getSetting(LLM_SETTING_KEYS.enabled, "1")).trim().toLowerCase()
  return {
    enabled: !(enabledRaw === "0" || enabledRaw === "false" || enabledRaw === "off"),
    provider: String(store.getSetting(LLM_SETTING_KEYS.provider, "") || ""),
    model: String(store.getSetting(LLM_SETTING_KEYS.model, "") || ""),
    baseUrl: String(store.getSetting(LLM_SETTING_KEYS.baseUrl, "") || ""),
  }
}

/**
 * 写 LLM 设置。**只认这四个字段，密钥永远不写进来**（G27）。
 * @param {{getSetting: Function, setSetting: Function}} store
 * @param {{enabled?: boolean, provider?: string, model?: string, baseUrl?: string}} patch
 */
function writeLlmSettings(store, patch) {
  const p = patch || {}
  if (p.enabled !== undefined) {
    store.setSetting(LLM_SETTING_KEYS.enabled, p.enabled ? "1" : "0")
  }
  if (p.provider !== undefined) {
    store.setSetting(LLM_SETTING_KEYS.provider, String(p.provider))
  }
  if (p.model !== undefined) {
    store.setSetting(LLM_SETTING_KEYS.model, String(p.model))
  }
  if (p.baseUrl !== undefined) {
    store.setSetting(LLM_SETTING_KEYS.baseUrl, String(p.baseUrl))
  }
  return readLlmSettings(store)
}

/**
 * 造一个服务层。
 * @param {{client?: object, getClient?: Function, store: object, provider: object,
 *          env?: object, now?: Function}} opts
 *   client：固定客户端（测试用）；getClient：每次请求都调一次拿当前客户端（设置页改完立即生效）。
 * @returns {object} 服务层
 */
function createLlmService(opts) {
  const o = opts || {}
  const store = o.store
  const provider = o.provider
  const env = o.env || process.env
  const fixedClient = o.client || null
  const getClient = typeof o.getClient === "function"
    ? o.getClient
    : function () { return fixedClient }
  const now = typeof o.now === "function" ? o.now : function () { return new Date() }

  /** 取当前客户端；没装配就用关闭态客户端兜底 */
  function currentClient() {
    const client = getClient()
    if (!client) return new NullClient("LLM 服务没有装配客户端")
    return client
  }

  /** 关闭态的统一提示语 */
  function offMessage(client) {
    const reason = (client && client.reason) || "LLM 未启用"
    return "【LLM 未启用】" + reason + "。App 的其余功能（排程、判题、复习、进度）不受影响。"
  }

  /** 防泄题第一道闸：只挑安全字段，参考解法根本不进来（G24） */
  function safeContext(problem, level) {
    return {
      title: problem.title,
      difficulty: problem.difficulty,
      topics: problem.topics,
      statement: problem.statement,
      level: level,
    }
  }

  /** 提示词摘要：只留指纹、长度和开头一小截，不整段存（G25） */
  function summarizePrompt(prompt) {
    const full = String((prompt && prompt.system) || "") + "\n" + String((prompt && prompt.user) || "")
    const digest = crypto.createHash("sha1").update(full).digest("hex").slice(0, 10)
    return {
      digest: digest,
      length: full.length,
      head: full.replace(/\s+/g, " ").slice(0, 120),
    }
  }

  /** 记一次调用：model + prompt 摘要 + 档位，落 settings 表（G25） */
  function recordTrace(problemId, kind, level, model, prompt) {
    if (!problemId) return
    const key = "llm.trace." + problemId
    let list = []
    const raw = store.getSetting(key, "")
    if (raw) {
      try {
        const parsed = JSON.parse(raw)
        if (Array.isArray(parsed)) list = parsed
      } catch (err) {
        list = []
      }
    }
    list.push({
      ts: now().toISOString(),
      kind: kind,
      level: level || "",
      model: model || "",
      prompt: summarizePrompt(prompt),
    })
    while (list.length > MAX_TRACE_PER_PROBLEM) list.shift()
    store.setSetting(key, JSON.stringify(list))
  }

  /** 扣配额前先查；超了直接停并提示（G31） */
  function ensureQuota(sessionId) {
    const quota = checkAll(store, sessionId, dateStr(now()))
    if (!quota.ok) throw quotaError(quota.message)
    return quota
  }

  /**
   * 讲解：先思路后代码。
   * @param {{problem: object, level?: string, sessionId?: string}} req
   * @returns {Promise<{text: string, model: string}>}
   */
  async function explain(req) {
    const r = req || {}
    const problem = r.problem
    if (!problem) throw badRequest("缺少题目")
    const level = EXPLAIN_LEVELS.indexOf(r.level) !== -1 ? r.level : "思路"
    const client = currentClient()
    if (client.name === "null") {
      return { text: offMessage(client), model: client.model || "null" }
    }
    ensureQuota(r.sessionId)
    const prompt = buildPrompt("explain", safeContext(problem, level))
    const raw = await client.complete({ system: prompt.system, user: prompt.user, temperature: 0.4 })
    const parsed = parseResponse(raw, "explain")
    if (!parsed.ok) throw new Error("讲解失败：" + parsed.reason)
    consumeAll(store, r.sessionId, dateStr(now()))
    recordTrace(problem.id, "explain", level, client.model, prompt)
    return { text: parsed.text, model: client.model }
  }

  /**
   * 分级求助：方向 → 思路 → 伪码 → 代码，逐级解锁。
   * @param {{problem: object, level?: string, sessionId?: string}} req
   * @returns {Promise<{text: string, model: string}>}
   */
  async function hint(req) {
    const r = req || {}
    const problem = r.problem
    if (!problem) throw badRequest("缺少题目")
    if (HINT_LEVELS.indexOf(r.level) === -1) {
      throw badRequest("求助档位非法：" + String(r.level))
    }
    const level = r.level
    const client = currentClient()
    if (client.name === "null") {
      return { text: offMessage(client), model: client.model || "null" }
    }
    ensureQuota(r.sessionId)
    const prompt = buildPrompt("hint", safeContext(problem, level))
    const raw = await client.complete({ system: prompt.system, user: prompt.user, temperature: 0.3 })
    const parsed = parseResponse(raw, "hint")
    if (!parsed.ok) throw new Error("求助失败：" + parsed.reason)
    consumeAll(store, r.sessionId, dateStr(now()))
    recordTrace(problem.id, "hint", level, client.model, prompt)
    return { text: parsed.text, model: client.model }
  }

  /**
   * 批改思路：只判断思路对不对，不给完整代码。
   * @param {{problem: object, idea: string, sessionId?: string}} req
   * @returns {Promise<{verdict: string, comment: string, model: string}>}
   */
  async function gradeIdea(req) {
    const r = req || {}
    const problem = r.problem
    if (!problem) throw badRequest("缺少题目")
    const idea = String(r.idea || "").trim()
    if (idea === "") throw badRequest("思路内容不能为空")
    const client = currentClient()
    if (client.name === "null") {
      return { verdict: "unknown", comment: offMessage(client), model: client.model || "null" }
    }
    ensureQuota(r.sessionId)
    const prompt = buildPrompt("grade-idea", {
      title: problem.title,
      difficulty: problem.difficulty,
      topics: problem.topics,
      statement: problem.statement,
      idea: idea,
    })
    const raw = await client.complete({ system: prompt.system, user: prompt.user, temperature: 0.2 })
    const parsed = parseResponse(raw, "grade-idea")
    consumeAll(store, r.sessionId, dateStr(now()))
    recordTrace(problem.id, "grade-idea", "", client.model, prompt)
    if (!parsed.ok) {
      return {
        verdict: "unknown",
        comment: "模型没给出可判定的结论：" + parsed.reason,
        model: client.model,
      }
    }
    return { verdict: parsed.verdict, comment: parsed.comment, model: client.model }
  }

  /**
   * 现造新题：真的落盘进 learning/bank/（G25）。
   * @param {{track: string, topics?: string[], difficulty?: string, sessionId?: string}} req
   * @returns {Promise<{problem: object, model: string, file: string}>}
   */
  async function generate(req) {
    const r = req || {}
    const track = String(r.track || "").trim()
    if (TRACKS.indexOf(track) === -1) {
      throw badRequest("轨道非法：" + (track || "（空）"))
    }
    const difficulty = DIFFICULTIES.indexOf(String(r.difficulty)) !== -1
      ? String(r.difficulty)
      : "medium"
    const topics = normalizeTopics(r.topics)
    const client = currentClient()
    if (client.name === "null") throw serviceUnavailable(offMessage(client))
    ensureQuota(r.sessionId)

    const prompt = buildPrompt("generate", {
      track: track,
      topics: topics,
      difficulty: difficulty,
    })
    const raw = await client.complete({ system: prompt.system, user: prompt.user, temperature: 0.8 })
    const parsed = parseResponse(raw, "generate")
    if (!parsed.ok) throw new Error("造题失败：" + parsed.reason)

    const id = makeLlmId(parsed.problem.statement)
    const existing = await provider.get(id)
    if (existing) {
      throw badRequest("这道题已经生成过了（题号 " + id + "），换个知识点再试。")
    }

    let finalTopics = parsed.problem.topics.length ? parsed.problem.topics : topics
    if (finalTopics.length === 0) finalTopics = ["未分类"]

    const day = dateStr(now())
    let problem
    try {
      problem = createProblem({
        id: id,
        source: "llm",
        title: parsed.problem.title,
        difficulty: parsed.problem.difficulty || difficulty,
        topics: finalTopics,
        tracks: [track],
        status: "todo",
        needsFill: false,
        created: day,
        updated: day,
        statement: parsed.problem.statement,
        cases: parsed.problem.cases,
        solution: parsed.problem.solution,
        solutionLang: parsed.problem.solutionLang,
        extraSections: [],
      })
    } catch (err) {
      throw badRequest("模型造的题不合规：" + err.message)
    }

    const file = await provider.put(problem)
    consumeAll(store, r.sessionId, day)
    recordTrace(id, "generate", track, client.model, prompt)
    return { problem: problem, model: client.model, file: file }
  }

  /**
   * 补全缺口：把缺题面或缺用例的题补齐，写回题库。
   * **只补缺的部分**：原来有的题面与用例一律保留（G25：补缺口，不是重写）。
   * @param {{problem: object, sessionId?: string}} req
   * @returns {Promise<{problem: object, model: string, file: string}>}
   */
  async function fill(req) {
    const r = req || {}
    const problem = r.problem
    if (!problem) throw badRequest("缺少题目")
    const client = currentClient()
    if (client.name === "null") throw serviceUnavailable(offMessage(client))
    ensureQuota(r.sessionId)

    const prompt = buildPrompt("fill", {
      title: problem.title,
      difficulty: problem.difficulty,
      topics: problem.topics,
      statement: problem.statement,
      cases: problem.cases,
      solution: problem.solution,
      solutionLang: problem.solutionLang,
    })
    const raw = await client.complete({ system: prompt.system, user: prompt.user, temperature: 0.4 })
    const parsed = parseResponse(raw, "fill")
    if (!parsed.ok) throw new Error("补全失败：" + parsed.reason)

    const statement = String(problem.statement || "").trim() !== ""
      ? problem.statement
      : parsed.patch.statement
    const cases = Array.isArray(problem.cases) && problem.cases.length > 0
      ? problem.cases
      : parsed.patch.cases
    const solution = parsed.patch.solution || problem.solution
    const solutionLang = parsed.patch.solutionLang || problem.solutionLang

    const day = dateStr(now())
    let updated
    try {
      updated = createProblem({
        id: problem.id,
        source: problem.source,
        title: problem.title,
        difficulty: problem.difficulty,
        topics: problem.topics,
        tracks: problem.tracks,
        status: problem.status,
        needsFill: false,
        created: problem.created,
        updated: day,
        statement: statement,
        cases: cases,
        solution: solution,
        solutionLang: solutionLang,
        extraSections: problem.extraSections || [],
      })
    } catch (err) {
      throw badRequest("补全后题目不合规：" + err.message)
    }

    const file = await provider.put(updated)
    consumeAll(store, r.sessionId, day)
    recordTrace(problem.id, "fill", "", client.model, prompt)
    return { problem: updated, model: client.model, file: file }
  }

  /**
   * 当前 LLM 状态，给设置页与前端看。
   * **只报密钥来自哪个环境变量，绝不回显密钥**（G27）。
   */
  function describe(sessionId) {
    const client = currentClient()
    const s = readLlmSettings(store)
    const l = limits(store)
    const usedSession = Number(store.getSetting(sessionKey(sessionId), "0")) || 0
    const usedDaily = Number(store.getSetting(dailyKey(dateStr(now())), "0")) || 0
    return {
      enabled: s.enabled,
      provider: s.provider,
      model: s.model,
      baseUrl: s.baseUrl,
      effectiveProvider: client.name,
      effectiveModel: client.model,
      keySource: keySourceOf(s.provider || client.name, env),
      reason: client.name === "null" ? String(client.reason || "") : "",
      quota: {
        sessionLimit: l.sessionLimit,
        dailyLimit: l.dailyLimit,
        usedSession: usedSession,
        usedDaily: usedDaily,
      },
    }
  }

  return {
    explain: explain,
    hint: hint,
    gradeIdea: gradeIdea,
    generate: generate,
    fill: fill,
    describe: describe,
    currentClient: currentClient,
  }
}

module.exports = {
  createLlmService: createLlmService,
  readLlmSettings: readLlmSettings,
  writeLlmSettings: writeLlmSettings,
  LLM_SETTING_KEYS: LLM_SETTING_KEYS,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-service.test.js` 及其余三个 llm 套件全绿（PASS），退出码 0。

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/core/llm/service.js apps/algo-plan/tests/llm-service.test.js
git commit -m "feat(algo-plan): 新增 LLM 服务层，接通五个场景并保证产出可追溯

- 讲解、求助、批改思路、造题、补全缺口五个场景各有独立入口
- 现造的新题落盘进 learning/bank，source 为 llm，题号走 makeLlmId
- 每次调用记录 model 与提示词摘要到 settings 表，便于回查
- 构造提示词时不带参考解法，讲解默认只到思路层
- LLM 关闭时返回明确中文提示，造题与补全返回 503，都不会崩"
git push origin main
```

---

## Task 5: 五个场景的 HTTP 接口（server/api-llm.js + server/app.js + server/main.js）

接口契约 §5 冻结了 M6 的五个接口的**入参与响应形状**，本 task 一个字都不改：

| 接口 | 入参 | 响应 |
|---|---|---|
| `POST /api/llm/explain` | `{problemId, level}` | `{text, model}` |
| `POST /api/llm/hint` | `{problemId, level}` | `{text, model}` |
| `POST /api/llm/grade-idea` | `{problemId, idea}` | `{verdict, comment, model}` |
| `POST /api/bank/llm-generate` | `{track, topics[], difficulty}` | `{problem, model}` |
| `POST /api/llm/fill` | `{problemId}` | `{problem, model}` |

**两个额外的可选字段（契约没写，但必需）：** 所有接口都接受可选的 `sessionId`（字符串）。
成本护栏要按「单次会话」计数，没有会话号就没法算（G31）。不传就落到 `default` 桶。

**为什么不改 M1 的 `server/api.js`：** M2–M5 也会往那个文件里加路由。
M6 把自己的路由放在独立文件 `server/api-llm.js` 里，再在 `server/app.js` 里合并，
**与其它里程碑零冲突**。M1 冻结的 `buildRoutes` 与 `SAMPLE_CASE_COUNT` 一个字都不动。

**两个额外的接口（不在契约 §5 清单里，是 M6 为了设置页新增的）：**

| 接口 | 入参 | 响应 |
|---|---|---|
| `GET /api/llm/settings` | — | `{enabled, provider, model, baseUrl, effectiveProvider, effectiveModel, keySource, reason, quota:{sessionLimit, dailyLimit, usedSession, usedDaily}}` |
| `PUT /api/llm/settings` | `{enabled?, provider?, model?, baseUrl?}` | `{ok: true, settings: {enabled, provider, model, baseUrl}}` |

> **为什么不复用设计文档 §7.2 的 `GET/PUT /api/settings`：** 那个接口归设置页所在的里程碑（M4），
> 它管判题超时、每日配额、learning 仓路径等全套设置。M6 只管 LLM 这一小块，
> 另开 `/api/llm/settings` 两个计划不会抢同一个路由，字段也不打架。
>
> **这两个接口绝不接受也不返回密钥**（G27）：只认 `enabled` / `provider` / `model` / `baseUrl` 四项。

**Files:**
- Create: `projects/apps/algo-plan/server/api-llm.js`
- Modify: `projects/apps/algo-plan/server/app.js`（三处加法，见 Step 4）
- Modify: `projects/apps/algo-plan/server/main.js`（加载 `.env` + 打印 LLM 状态，见 Step 5）
- Test: `projects/apps/algo-plan/tests/llm-api.test.js`

**Interfaces:**
- Consumes:
  - `core/llm/service.js` 的 `createLlmService(...)`、`readLlmSettings(store)`、`writeLlmSettings(store, patch)`（Task 4）
  - `core/llm/client.js` 的 `createLlmClient({...})`（Task 2）
  - `core/llm/guard.js` 的 `seedLimits(store, env)`（Task 3）
  - `server/router.js` 的 `readJsonBody(req) -> Promise<object>`（M1 已冻结）
  - `core/bank/provider.js` 的 `provider.get(id)` / `provider.put(problem)`（M1 已冻结）
- Produces:
  - `server/api-llm.js` 导出 `buildLlmRoutes(ctx) -> Array<{method, pattern, handler}>`
  - `server/app.js` 的 `createApp({dbPath?, learningRoot?, env?, llmClient?})` **新增**返回字段 `llm`（加法，不破坏 M1 冻结的字段）
  - `server/main.js` **新增**导出 `loadDotEnv(file?) -> object`

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-api.test.js`**

创建 `projects/apps/algo-plan/tests/llm-api.test.js`：

```javascript
"use strict"
/**
 * llm-api.test.js —— M6 的 HTTP 接口测试（**注入假 client，不联网**）
 *
 * 钉住：
 *   1. 五个接口的路径、入参与响应形状，严格照接口契约 §5；
 *   2. 造出来的新题真的落盘；落盘后 GET /api/problem/:id 仍不泄露参考解法（G14）；
 *   3. LLM 设置能读能写，但**接口里绝不出现密钥**。
 */

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")

/** 造一个带一道题的 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-llm-"))
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
      "## 测试用例",
      "",
      "| input | expect |",
      "|---|---|",
      "| [2,7,11,15], 9 | [0,1]|",
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

/** 假客户端：按 system 提示里的关键词分派回复 */
function makeFakeClient() {
  const calls = []
  return {
    name: "ark",
    model: "fake-model",
    calls: calls,
    complete: async function (req) {
      calls.push(req)
      const sys = String(req.system || "")
      if (sys.includes("出题老师")) {
        return JSON.stringify({
          title: "三数之和",
          statement: "给一个数组，找出所有和为 0 的三元组。",
          difficulty: "medium",
          topics: ["双指针"],
          cases: [{ input: "[0,0,0]", expect: "[[0,0,0]]" }],
          solution: "int main(){ return 0; }",
          solutionLang: "cpp",
        })
      }
      if (sys.includes("批改用户的解题思路")) {
        return JSON.stringify({ verdict: "correct", comment: "思路没问题" })
      }
      if (sys.includes("反推出一道题")) {
        return JSON.stringify({
          statement: "补出来的题面",
          cases: [{ input: "[2,7], 9", expect: "[0,1]" }],
        })
      }
      return "这是一段模型回答。"
    },
  }
}

async function withApp(fn, opts) {
  const app = createApp(
    Object.assign(
      { dbPath: ":memory:", learningRoot: tempLearning(), llmClient: makeFakeClient(), env: {} },
      opts || {}
    )
  )
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port, app)
  } finally {
    await app.close()
  }
}

test("POST /api/llm/explain 返回 {text, model}", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/explain", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "思路", sessionId: "s1" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(typeof body.text, "string")
    assert.ok(body.text.length > 0)
    assert.equal(body.model, "fake-model")
    assert.deepEqual(Object.keys(body).sort(), ["model", "text"])
  })
})

test("POST /api/llm/explain 题目不存在返回 404", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/explain", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "不存在", level: "思路" }),
    })
    assert.equal(res.status, 404)
  })
})

test("POST /api/llm/hint 返回 {text, model}，档位非法返回 400", async function () {
  await withApp(async function (base) {
    const ok = await fetch(base + "/api/llm/hint", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "方向", sessionId: "s1" }),
    })
    assert.equal(ok.status, 200)
    const body = await ok.json()
    assert.deepEqual(Object.keys(body).sort(), ["model", "text"])

    const bad = await fetch(base + "/api/llm/hint", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "神级", sessionId: "s1" }),
    })
    assert.equal(bad.status, 400)
    const err = await bad.json()
    assert.ok(err.error.includes("求助档位非法"), "错误信息应为中文说明：" + err.error)
  })
})

test("POST /api/llm/grade-idea 返回 {verdict, comment, model}", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/grade-idea", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", idea: "用哈希表", sessionId: "s1" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.deepEqual(Object.keys(body).sort(), ["comment", "model", "verdict"])
    assert.equal(body.verdict, "correct")
    assert.equal(body.comment, "思路没问题")
  })
})

test("POST /api/bank/llm-generate 返回 {problem, model}，且题目真的落盘", async function () {
  await withApp(async function (base, app) {
    const res = await fetch(base + "/api/bank/llm-generate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ track: "interview", topics: ["双指针"], difficulty: "medium", sessionId: "s1" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.deepEqual(Object.keys(body).sort(), ["model", "problem"])
    assert.equal(body.problem.source, "llm")
    assert.ok(body.problem.id.startsWith("llm-"))
    const 文件 = path.join(app.learning.root, "bank", "interview", body.problem.id + ".md")
    assert.ok(fs.existsSync(文件), "新题应落盘到 learning/bank：" + 文件)
  })
})

test("造完题后 GET /api/problem/:id 仍然不泄露参考解法（G14）", async function () {
  await withApp(async function (base) {
    const made = await fetch(base + "/api/bank/llm-generate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ track: "interview", difficulty: "medium", sessionId: "s1" }),
    })
    const madeBody = await made.json()
    const id = madeBody.problem.id
    const res = await fetch(base + "/api/problem/" + id)
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(body.solution, undefined, "单题接口不许返回参考解法")
    assert.equal(body.cases.total, 1)
    assert.equal(body.cases.sample.length, 1)
  })
})

test("POST /api/llm/fill 返回 {problem, model}，needsFill 变 false", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/fill", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", sessionId: "s1" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.deepEqual(Object.keys(body).sort(), ["model", "problem"])
    assert.equal(body.problem.needsFill, false)
  })
})

test("GET /api/llm/settings 返回开关、provider、密钥来源与配额", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/settings")
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(body.effectiveProvider, "ark")
    assert.equal(body.effectiveModel, "fake-model")
    assert.equal(body.quota.sessionLimit, 20)
    assert.equal(body.quota.dailyLimit, 100)
    assert.ok(!JSON.stringify(body).includes("super-secret"))
  })
})

test("PUT /api/llm/settings 能保存开关与模型名", async function () {
  await withApp(async function (base) {
    const res = await fetch(base + "/api/llm/settings", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ enabled: false, provider: "anthropic", model: "claude-opus-5" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(body.ok, true)
    assert.equal(body.settings.enabled, false)
    assert.equal(body.settings.provider, "anthropic")
    assert.equal(body.settings.model, "claude-opus-5")

    const again = await fetch(base + "/api/llm/settings")
    const after = await again.json()
    assert.equal(after.enabled, false)
    assert.equal(after.provider, "anthropic")
  })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-api.test.js` 报 404（`/api/llm/explain` 还没有路由）。

- [ ] **Step 3: 写实现 `server/api-llm.js`**

创建 `projects/apps/algo-plan/server/api-llm.js`：

```javascript
"use strict"
/**
 * api-llm.js —— M6 的 LLM 接口
 *
 * 单独一个文件，**不动 M1 的 server/api.js**：M2–M5 也会往那个文件里加路由，
 * 分开放可以彻底避免抢同一个文件。
 *
 * 五个场景接口的入参与响应形状严格照接口契约 §5：
 *   POST /api/llm/explain       {problemId, level}                    -> {text, model}
 *   POST /api/llm/hint          {problemId, level}                    -> {text, model}
 *   POST /api/llm/grade-idea    {problemId, idea}                     -> {verdict, comment, model}
 *   POST /api/bank/llm-generate {track, topics[], difficulty}         -> {problem, model}
 *   POST /api/llm/fill          {problemId}                           -> {problem, model}
 *
 * 额外允许一个可选字段 sessionId：成本护栏按「单次会话」计数要用（G31）。
 * 不传就落到 default 桶。
 */

const { readJsonBody } = require("./router.js")
const { writeLlmSettings } = require("../core/llm/service.js")

/**
 * 组装 M6 的路由表。
 * @param {{store: object, provider: object, llm: object, sendJson: Function, env?: object}} ctx
 * @returns {Array<{method: string, pattern: string, handler: Function}>}
 */
function buildLlmRoutes(ctx) {
  const routes = []

  /** 没装配 LLM 服务时统一回 503，不影响其它接口 */
  function needLlm(res) {
    if (ctx.llm) return true
    ctx.sendJson(res, 503, { error: "LLM 功能未装配" })
    return false
  }

  /** 按题号取题，取不到回 404 */
  async function loadProblem(res, body) {
    const id = String(body.problemId || "")
    const problem = await ctx.provider.get(id)
    if (!problem) {
      ctx.sendJson(res, 404, { error: "题目不存在", id: id })
      return null
    }
    return problem
  }

  routes.push({
    method: "POST",
    pattern: "/api/llm/explain",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const problem = await loadProblem(res, body)
      if (!problem) return
      const result = await ctx.llm.explain({
        problem: problem,
        level: String(body.level || "思路"),
        sessionId: body.sessionId,
      })
      ctx.sendJson(res, 200, { text: result.text, model: result.model })
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/llm/hint",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const problem = await loadProblem(res, body)
      if (!problem) return
      const result = await ctx.llm.hint({
        problem: problem,
        level: String(body.level || "方向"),
        sessionId: body.sessionId,
      })
      ctx.sendJson(res, 200, { text: result.text, model: result.model })
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/llm/grade-idea",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const problem = await loadProblem(res, body)
      if (!problem) return
      const result = await ctx.llm.gradeIdea({
        problem: problem,
        idea: String(body.idea || ""),
        sessionId: body.sessionId,
      })
      ctx.sendJson(res, 200, {
        verdict: result.verdict,
        comment: result.comment,
        model: result.model,
      })
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/bank/llm-generate",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const topics = Array.isArray(body.topics) ? body.topics : []
      const result = await ctx.llm.generate({
        track: String(body.track || ""),
        topics: topics,
        difficulty: String(body.difficulty || "medium"),
        sessionId: body.sessionId,
      })
      ctx.sendJson(res, 200, { problem: result.problem, model: result.model })
    },
  })

  routes.push({
    method: "POST",
    pattern: "/api/llm/fill",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const problem = await loadProblem(res, body)
      if (!problem) return
      const result = await ctx.llm.fill({
        problem: problem,
        sessionId: body.sessionId,
      })
      ctx.sendJson(res, 200, { problem: result.problem, model: result.model })
    },
  })

  // ---- LLM 设置（M6 新增的两个接口；**绝不接受也不返回密钥**） ----

  routes.push({
    method: "GET",
    pattern: "/api/llm/settings",
    handler: async function (req, res, params, query) {
      if (!needLlm(res)) return
      const sessionId = query.get("sessionId")
      ctx.sendJson(res, 200, ctx.llm.describe(sessionId || undefined))
    },
  })

  routes.push({
    method: "PUT",
    pattern: "/api/llm/settings",
    handler: async function (req, res) {
      if (!needLlm(res)) return
      const body = await readJsonBody(req)
      const patch = {}
      if (body.enabled !== undefined) {
        patch.enabled = body.enabled === true || body.enabled === 1 || body.enabled === "1"
      }
      if (body.provider !== undefined) patch.provider = String(body.provider)
      if (body.model !== undefined) patch.model = String(body.model)
      if (body.baseUrl !== undefined) patch.baseUrl = String(body.baseUrl)
      const settings = writeLlmSettings(ctx.store, patch)
      ctx.sendJson(res, 200, { ok: true, settings: settings })
    },
  })

  return routes
}

module.exports = { buildLlmRoutes: buildLlmRoutes }
```

- [ ] **Step 4: 改 `server/app.js`（三处加法）**

`server/app.js` 是 M1 建的文件，**只做加法**，M1 冻结的导出与字段一个字都不动。

**改动 A —— 在 `createApp` 里补三个 require。**
把这一段：

```javascript
  const { resolveLearningRoot } = require("../core/paths.js")
  const { FileProvider } = require("../core/bank/provider.js")
  const { openDb, createStore } = require("./db.js")
```

改成：

```javascript
  const { resolveLearningRoot } = require("../core/paths.js")
  const { FileProvider } = require("../core/bank/provider.js")
  const { openDb, createStore } = require("./db.js")
  const { createLlmClient } = require("../core/llm/client.js")
  const { createLlmService, readLlmSettings } = require("../core/llm/service.js")
  const { seedLimits } = require("../core/llm/guard.js")
```

**改动 B —— 在 `buildRoutes` 之后合并 M6 的路由。**
把这一段：

```javascript
  const routes = require("./api.js").buildRoutes({
    store: store,
    provider: provider,
    learning: learning,
    sendJson: sendJson,
  })
```

改成：

```javascript
  const env = options.env || process.env

  // 配额上限：环境变量只在 settings 表里没有这项时才写入
  seedLimits(store, env)

  // LLM 服务层：没有注入固定客户端时，每次请求按当前设置重建客户端，
  // 设置页改完 provider / 模型名 / 开关之后立即生效，不用重启。
  const fixedClient = options.llmClient || null
  const llm = createLlmService({
    client: fixedClient,
    getClient: fixedClient ? undefined : function () {
      const s = readLlmSettings(store)
      return createLlmClient({
        provider: s.provider || undefined,
        model: s.model || undefined,
        baseUrl: s.baseUrl || undefined,
        enabled: s.enabled,
        env: env,
      })
    },
    store: store,
    provider: provider,
    env: env,
  })

  const routes = require("./api.js").buildRoutes({
    store: store,
    provider: provider,
    learning: learning,
    sendJson: sendJson,
  })
  routes.push.apply(routes, require("./api-llm.js").buildLlmRoutes({
    store: store,
    provider: provider,
    llm: llm,
    sendJson: sendJson,
    env: env,
  }))
```

**改动 C —— 返回对象里多带一个 `llm`。**
把这一段：

```javascript
    db: db,
    store: store,
    provider: provider,
    learning: learning,
  })
```

改成：

```javascript
    db: db,
    store: store,
    provider: provider,
    learning: learning,
    llm: llm,
  })
```

> **若 M2–M5 已经改过上面这些片段：** 按同样的语义合并即可——
> `buildRoutes` 的 `ctx` 仍然保留 `store` / `provider` / `learning` / `sendJson` 四个字段，
> M6 的路由用 `routes.push.apply(routes, ...)` 追加在 `createServer({routes})` **之前**。

- [ ] **Step 5: 改 `server/main.js`（加载 .env + 打印 LLM 状态）**

**改动 A —— 顶部加 `.env` 读取器。**
把这一段：

```javascript
const { createApp } = require("./app.js")
```

改成：

```javascript
const fs = require("node:fs")
const path = require("node:path")

const { createApp } = require("./app.js")

/**
 * 读取 .env 文件，把里面的键塞进 process.env。
 *
 * 仓库惯例：本地密钥放在 .env 里（projects/.gitignore 已经忽略 .env 与 .env.local）。
 * 已经存在的环境变量优先，.env 不覆盖——命令行传的值永远最大。
 *
 * @param {string} [file] 默认读 apps/algo-plan/.env
 * @returns {object} 读到的键值对
 */
function loadDotEnv(file) {
  const target = file || path.join(__dirname, "..", ".env")
  let text
  try {
    text = fs.readFileSync(target, "utf8")
  } catch (err) {
    return {}
  }
  const loaded = {}
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (line === "" || line.charAt(0) === "#") continue
    const eq = line.indexOf("=")
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    if (key === "") continue
    let value = line.slice(eq + 1).trim()
    if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') {
      value = value.slice(1, -1)
    }
    loaded[key] = value
    if (process.env[key] === undefined) process.env[key] = value
  }
  return loaded
}
```

**改动 B —— `main()` 里加载 .env 并打印 LLM 状态。**
把这一段：

```javascript
function main() {
  checkNodeVersion()
  const app = createApp()
  const port = Number(process.env.PORT || 5173)
  app.listen(port).then(function (p) {
    console.log("算法能力计划 App 已启动：http://127.0.0.1:" + p)
    if (app.learning.ok) {
      console.log("learning 仓：" + app.learning.root)
    } else {
      console.log("未连接 learning 仓（纯本地模式）：" + app.learning.reason)
    }
  })
}
```

改成：

```javascript
function main() {
  checkNodeVersion()
  loadDotEnv()
  const app = createApp()
  const port = Number(process.env.PORT || 5173)
  app.listen(port).then(function (p) {
    console.log("算法能力计划 App 已启动：http://127.0.0.1:" + p)
    if (app.learning.ok) {
      console.log("learning 仓：" + app.learning.root)
    } else {
      console.log("未连接 learning 仓（纯本地模式）：" + app.learning.reason)
    }
    const info = app.llm.describe()
    if (info.effectiveProvider === "null") {
      console.log("LLM 未启用：" + info.reason + "（其余功能照常可用）")
    } else {
      console.log("LLM 已就绪：" + info.effectiveProvider + " / " + info.effectiveModel)
    }
  })
}
```

**改动 C —— 导出 `loadDotEnv`。**
把这一段：

```javascript
module.exports = { main: main, checkNodeVersion: checkNodeVersion }
```

改成：

```javascript
module.exports = { main: main, checkNodeVersion: checkNodeVersion, loadDotEnv: loadDotEnv }
```

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-api.test.js` 套件全绿（PASS），退出码 0。

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/server/api-llm.js apps/algo-plan/server/app.js apps/algo-plan/server/main.js apps/algo-plan/tests/llm-api.test.js
git commit -m "feat(algo-plan): 接入五个 LLM 场景接口与设置接口

- 讲解、求助、批改思路、造题、补全缺口五个接口的响应形状照接口契约
- 路由单独放 server/api-llm.js，不动 M1 的 server/api.js，避免与其它里程碑冲突
- 新增 GET/PUT /api/llm/settings，只存开关、provider、模型名与地址，绝不存密钥
- 启动时读 apps/algo-plan/.env，密钥来源沿用仓库既有的 .env 惯例"
git push origin main
```

---

## Task 6: 把 LLM 关掉，app 仍然完整可用（硬约束专测）

设计文档 §6.1 的硬要求：**「把 LLM 关掉，app 仍然完整可用」**。
这个 task 专门验证它，**不写任何新功能**，只写测试 + 必要的兜底。

要验证的四件事：
1. 关掉 LLM 时 `NullClient` 返回**明确的中文提示**，不抛错；
2. 关掉 LLM 时 app **起得来、页面能开、接口能调**，一个都不崩；
3. 关掉 LLM 时 LLM 相关的接口要么返回中文提示（200），要么返回 503 的中文错误，**不返回 500**；
4. 关掉 LLM 时**题库一个文件都不多写**（造题、补全都不落盘）。

**Files:**
- Test: `projects/apps/algo-plan/tests/llm-off.test.js`
- Modify: 无（本 task 只加测试；若测试暴露问题，就地修，前提是不破坏前面的契约）

**Interfaces:**
- Consumes:
  - `core/llm/client.js` 的 `createLlmClient({...})`、`NullClient`（Task 2）
  - `server/app.js` 的 `createApp({dbPath?, learningRoot?, env?, llmClient?})`（Task 5）
- Produces: 无新导出，只新增测试套件

---

- [ ] **Step 1: 写测试 `tests/llm-off.test.js`**

创建 `projects/apps/algo-plan/tests/llm-off.test.js`：

```javascript
"use strict"
/**
 * llm-off.test.js —— 「把 LLM 关掉，app 仍然完整可用」的专项测试（**不联网**）
 *
 * 这是设计文档 §6.1 的硬要求，本文件是它的验收证据。
 * 覆盖：
 *   1. 没有密钥 / 环境变量关掉 / 设置页关掉，三种关法都降级成 NullClient；
 *   2. 关掉后 app 起得来，页面、题库、单题接口一个都不崩；
 *   3. LLM 接口返回明确的中文提示（200）或 503 中文错误，**不返回 500**；
 *   4. 关掉时题库一个文件都不多写。
 */

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")
const { createLlmClient, NullClient } = require("../core/llm/client.js")

/** 造一个带一道题的 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-off-"))
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
      "## 测试用例",
      "",
      "| input | expect |",
      "|---|---|",
      "| [2,7,11,15], 9 | [0,1]|",
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

/** 数一数题库目录里有多少个 md 文件 */
function countBankFiles(root) {
  const dir = path.join(root, "bank")
  let total = 0
  for (const name of fs.readdirSync(dir)) {
    const sub = path.join(dir, name)
    if (fs.statSync(sub).isDirectory()) {
      total += fs.readdirSync(sub).filter(function (f) { return f.endsWith(".md") }).length
    }
  }
  return total
}

/** 起一个**没有 LLM** 的 app：env 里没有任何密钥 */
async function withOffApp(fn) {
  const root = tempLearning()
  const app = createApp({ dbPath: ":memory:", learningRoot: root, env: {} })
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port, app, root)
  } finally {
    await app.close()
  }
}

test("没有密钥时降级成 NullClient，返回明确的中文提示", async function () {
  const client = createLlmClient({ env: {} })
  assert.equal(client.name, "null")
  assert.ok(client instanceof NullClient)
  const text = await client.complete({ system: "s", user: "u" })
  assert.ok(text.includes("LLM 未启用"), "提示里应写明 LLM 未启用：" + text)
  assert.ok(text.includes("不受影响"), "提示里应说明其余功能不受影响：" + text)
})

test("三种关法都降级成 NullClient：没密钥、环境变量关、设置页关", function () {
  assert.equal(createLlmClient({ env: {} }).name, "null")
  assert.equal(createLlmClient({ env: { ARK_API_KEY: "k", ALGO_PLAN_LLM_ENABLED: "0" } }).name, "null")
  assert.equal(createLlmClient({ enabled: false, env: { ARK_API_KEY: "k" } }).name, "null")
})

test("LLM 关着时 app 照常起得来：页面、题库、单题接口全都不崩", async function () {
  await withOffApp(async function (base) {
    const page = await fetch(base + "/")
    assert.equal(page.status, 200, "首页应该照常能打开")

    const health = await fetch(base + "/api/health")
    assert.equal(health.status, 200)
    const healthBody = await health.json()
    assert.equal(healthBody.ok, true)
    assert.equal(healthBody.bank.problemCount, 1)

    const bank = await fetch(base + "/api/bank")
    assert.equal(bank.status, 200)
    const bankBody = await bank.json()
    assert.equal(bankBody.total, 1)

    const one = await fetch(base + "/api/problem/lc-00001")
    assert.equal(one.status, 200)
    const oneBody = await one.json()
    assert.equal(oneBody.id, "lc-00001")
  })
})

test("LLM 关着时，讲解与求助返回明确的中文提示，不返回 500", async function () {
  await withOffApp(async function (base) {
    const explain = await fetch(base + "/api/llm/explain", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "思路" }),
    })
    assert.equal(explain.status, 200)
    const explainBody = await explain.json()
    assert.ok(explainBody.text.includes("LLM 未启用"), "应返回明确的中文提示：" + explainBody.text)

    const hint = await fetch(base + "/api/llm/hint", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "方向" }),
    })
    assert.equal(hint.status, 200)
    const hintBody = await hint.json()
    assert.ok(hintBody.text.includes("LLM 未启用"))
  })
})

test("LLM 关着时，批改思路返回 unknown 与中文提示，不返回 500", async function () {
  await withOffApp(async function (base) {
    const res = await fetch(base + "/api/llm/grade-idea", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", idea: "用哈希表" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(body.verdict, "unknown")
    assert.ok(body.comment.includes("LLM 未启用"))
  })
})

test("LLM 关着时，造题与补全返回 503 中文错误，题库一个文件都不多写", async function () {
  await withOffApp(async function (base, app, root) {
    const before = countBankFiles(root)

    const gen = await fetch(base + "/api/bank/llm-generate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ track: "interview", difficulty: "medium" }),
    })
    assert.equal(gen.status, 503, "应返回 503，不是 500")
    const genBody = await gen.json()
    assert.ok(typeof genBody.error === "string" && genBody.error.length > 0, "应给出中文错误说明")

    const fill = await fetch(base + "/api/llm/fill", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001" }),
    })
    assert.equal(fill.status, 503, "应返回 503，不是 500")

    assert.equal(countBankFiles(root), before, "LLM 关着时题库不该多出文件")
  })
})

test("设置页把 LLM 关掉之后，所有 LLM 接口依然是中文提示，不是 500", async function () {
  await withOffApp(async function (base) {
    const put = await fetch(base + "/api/llm/settings", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ enabled: false }),
    })
    assert.equal(put.status, 200)

    const info = await fetch(base + "/api/llm/settings")
    const infoBody = await info.json()
    assert.equal(infoBody.enabled, false)
    assert.equal(infoBody.effectiveProvider, "null")
    assert.ok(infoBody.reason.length > 0, "应说明为什么没启用")

    const res = await fetch(base + "/api/llm/explain", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ problemId: "lc-00001", level: "思路" }),
    })
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.ok(body.text.includes("LLM 未启用"))
  })
})

test("LLM 关着时，题库读取与 health 都不受任何影响", async function () {
  await withOffApp(async function (base) {
    const first = await fetch(base + "/api/bank")
    const second = await fetch(base + "/api/bank")
    assert.equal(first.status, 200)
    assert.equal(second.status, 200)
    const a = await first.json()
    const b = await second.json()
    assert.deepEqual(a, b, "题库内容不该因为 LLM 关着而变化")
  })
})
```

- [ ] **Step 2: 跑测试确认失败（如果有测试直接过，说明前面的 task 已经满足这条硬约束）**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: `llm-off.test.js` 全绿（PASS），退出码 0。

> **如果这里有红的**：多半是 Task 2/4/5 里「LLM 关着」的处理没写全。
> 修的时候**只改 M6 自己的代码**（`core/llm/*`、`server/api-llm.js`），
> 不许改 M1 冻结的 `server/app.js` 导出结构，也不许改 M1 冻结的三个接口。

- [ ] **Step 3: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/tests/llm-off.test.js
git commit -m "test(algo-plan): 补上关闭 LLM 后 app 仍完整可用的专项测试

- 没有密钥、环境变量关、设置页关三种关法都降级成 NullClient
- 关掉后首页、题库、单题接口照常工作，LLM 接口返回中文提示或 503 而不是 500
- 关掉时题库一个文件都不多写"
git push origin main
```

---

## Task 7: 前端 —— 作答页的「讲解」与「求助」（web/llm.js）

**前端接入约定（重要，不依赖 M2–M5 的内部函数名）：**

M6 的前端**全部集中在一个新文件 `web/llm.js`** 里，`web/app.js` **一个字都不改**。
理由：M2–M5 会各自重写 `web/app.js` 的页面渲染代码，M6 进去改就会冲突。
`web/llm.js` 自己挂载：

1. `DOMContentLoaded` 之后把「LLM 工作台」挂到 `main#view` **顶部**；
2. 用 `MutationObserver` 盯着 `main#view`：M2–M5 的 app.js 每次重渲染都会清空 `#view`，
   面板被清掉就重新挂一次；
3. 页面上出现带 `data-problem-id` 的元素时，自动把它当作「当前题」；
4. 就算 M2–M5 **没有**这个属性，工作台自带的题目下拉框（从 `/api/bank` 拉）照样能用。

**纪律在前端的落地：**
- **不主动泄题**：「讲思路」是默认按钮；「直接给代码」是**另一个独立按钮**，
  点之前要 `confirm` 一次；求助**四档逐级解锁**——用完「方向」才放开「思路」，
  用完「思路」才放开「伪码」，以此类推。解锁进度存在 `sessionStorage`，关掉浏览器就没了。
- **产出可追溯**：造题与补全都由后端落盘，前端只显示结果与落盘位置。

**Files:**
- Create: `projects/apps/algo-plan/web/llm.js`
- Modify: `projects/apps/algo-plan/web/index.html`（加一行 `<script>`）
- Modify: `projects/apps/algo-plan/web/style.css`（末尾追加 LLM 面板样式）
- Test: `projects/apps/algo-plan/tests/llm-web.test.js`

**Interfaces:**
- Consumes:
  - 后端接口 `POST /api/llm/explain`（`{problemId, level, sessionId}` → `{text, model}`）
  - 后端接口 `POST /api/llm/hint`（`{problemId, level, sessionId}` → `{text, model}`）
  - 后端接口 `GET /api/bank`（取题目列表）、`GET /api/llm/settings`（取当前 LLM 状态）
- Produces:
  - 浏览器全局 `window.AlgoPlanLlm`
  - `window.AlgoPlanLlm` 上导出：`HINT_LEVELS`、`EXPLAIN_LEVELS`、`hintLevelIndex(level)`、
    `isHintLevelUnlocked(unlockedIndex, level)`、`nextUnlockedIndex(currentIndex, level)`、
    `explainRequestBody(problemId, level, sessionId)`、`hintRequestBody(problemId, level, sessionId)`、
    `getUnlocked(problemId)`、`setUnlocked(problemId, index)`、`resetUnlocks()`、`sessionId()`
  - DOM 契约：`main#view` 里带 `data-problem-id="<题号>"` 的元素 = 当前题

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-web.test.js`**

创建 `projects/apps/algo-plan/tests/llm-web.test.js`：

```javascript
"use strict"
/**
 * llm-web.test.js —— 前端纯逻辑测试（**不联网、不碰 DOM**）
 *
 * web/llm.js 里的「纯逻辑区」不依赖 document，可以直接在 Node 里 require 进来测。
 * 钉住：
 *   1. 四档求助的顺序与「逐级解锁」规则；
 *   2. 讲解默认只到思路层，代码那一档必须显式传；
 *   3. 请求体一定带题号与会话号（成本护栏要用会话号）。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const Llm = require("../web/llm.js")

test("web/llm.js 在 Node 里 require 不会崩，也没有碰 DOM", function () {
  assert.ok(Llm, "模块应当导出对象")
  assert.equal(typeof Llm.hintLevelIndex, "function")
})

test("求助四档固定：方向 → 思路 → 伪码 → 代码", function () {
  assert.deepEqual(Llm.HINT_LEVELS, ["方向", "思路", "伪码", "代码"])
})

test("讲解两档固定：先思路，后代码", function () {
  assert.deepEqual(Llm.EXPLAIN_LEVELS, ["思路", "代码"])
})

test("一开始只有「方向」那一档能用", function () {
  assert.equal(Llm.isHintLevelUnlocked(0, "方向"), true)
  assert.equal(Llm.isHintLevelUnlocked(0, "思路"), false)
  assert.equal(Llm.isHintLevelUnlocked(0, "伪码"), false)
  assert.equal(Llm.isHintLevelUnlocked(0, "代码"), false)
})

test("解锁只前进不回退：方向 → 思路 → 伪码 → 代码", function () {
  var idx = 0
  idx = Llm.nextUnlockedIndex(idx, "方向")
  assert.equal(idx, 1, "用过方向之后，思路这一档应解锁")
  assert.equal(Llm.isHintLevelUnlocked(idx, "思路"), true)
  assert.equal(Llm.isHintLevelUnlocked(idx, "伪码"), false)

  idx = Llm.nextUnlockedIndex(idx, "思路")
  assert.equal(idx, 2)
  assert.equal(Llm.isHintLevelUnlocked(idx, "伪码"), true)
  assert.equal(Llm.isHintLevelUnlocked(idx, "代码"), false)

  idx = Llm.nextUnlockedIndex(idx, "伪码")
  assert.equal(idx, 3)
  assert.equal(Llm.isHintLevelUnlocked(idx, "代码"), true)

  idx = Llm.nextUnlockedIndex(idx, "代码")
  assert.equal(idx, 3, "最高档用完也不该越界")

  idx = Llm.nextUnlockedIndex(idx, "方向")
  assert.equal(idx, 3, "解锁进度不该回退")
})

test("档位下标：认不出来的返回 -1", function () {
  assert.equal(Llm.hintLevelIndex("方向"), 0)
  assert.equal(Llm.hintLevelIndex("代码"), 3)
  assert.equal(Llm.hintLevelIndex("神级"), -1)
  assert.equal(Llm.isHintLevelUnlocked(3, "神级"), false)
})

test("讲解默认只到思路层，要代码必须显式传", function () {
  assert.equal(Llm.explainRequestBody("lc-00001", undefined, "s1").level, "思路")
  assert.equal(Llm.explainRequestBody("lc-00001", "思路", "s1").level, "思路")
  assert.equal(Llm.explainRequestBody("lc-00001", "代码", "s1").level, "代码")
})

test("请求体带题号与档位", function () {
  assert.deepEqual(Llm.explainRequestBody("lc-00001", "思路", "s1"), {
    problemId: "lc-00001",
    level: "思路",
    sessionId: "s1",
  })
  assert.deepEqual(Llm.hintRequestBody("lc-00001", "伪码", "s1"), {
    problemId: "lc-00001",
    level: "伪码",
    sessionId: "s1",
  })
})

test("解锁进度按题号分别记，互不影响", function () {
  Llm.resetUnlocks()
  Llm.setUnlocked("lc-00001", 2)
  assert.equal(Llm.getUnlocked("lc-00001"), 2)
  assert.equal(Llm.getUnlocked("lc-00002"), 0)
  Llm.resetUnlocks()
  assert.equal(Llm.getUnlocked("lc-00001"), 0)
})

test("会话号是稳定的（同一个会话里不变）", function () {
  const a = Llm.sessionId()
  const b = Llm.sessionId()
  assert.equal(a, b)
  assert.ok(a.length > 0)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-web.test.js` 报 `Cannot find module '../web/llm.js'`。

- [ ] **Step 3: 写 `web/llm.js`**

创建 `projects/apps/algo-plan/web/llm.js`：

```javascript
"use strict"
/**
 * llm.js —— LLM 工作台：讲解 / 求助 / 造题 / 补全 / 设置
 *
 * 零构建、零依赖的原生 JS。整个模块挂到 window.AlgoPlanLlm。
 *
 * 页面接入约定（**不依赖 M2–M5 的内部函数名**）：
 *   - 本文件在 DOMContentLoaded 之后自动把「LLM 工作台」挂到 main#view 顶部；
 *   - app.js 每次重渲染会清空 #view，本文件用 MutationObserver 重新挂载；
 *   - 页面上出现带 data-problem-id 的元素时，自动把它当作「当前题」；
 *   - 就算没有那个属性，工作台自带的题目下拉框（从 /api/bank 拉）照样能用。
 *
 * 纪律：
 *   - 不主动泄题：讲解默认「讲思路」；「直接给代码」是另一个独立按钮，点之前要 confirm；
 *     求助四档逐级解锁，用完一档才放开下一档。
 *   - 产出可追溯：造题与补全由后端落盘，前端只显示结果与落盘位置。
 */
;(function (global) {
  /** 求助的四档：方向 → 思路 → 伪码 → 代码 */
  var HINT_LEVELS = ["方向", "思路", "伪码", "代码"]

  /** 讲解的两档：先思路，后代码 */
  var EXPLAIN_LEVELS = ["思路", "代码"]

  /** 讲解按钮上的字 */
  var EXPLAIN_LABELS = { 思路: "讲思路", 代码: "直接给代码" }

  /** 逐级解锁的进度存在 sessionStorage 里，键前缀 */
  var UNLOCK_KEY_PREFIX = "algo-plan-llm-unlock-"

  /** 会话号：成本护栏按会话计数，所有请求都要带着 */
  var SESSION_ID_KEY = "algo-plan-llm-session-id"

  /** 没有 sessionStorage 时（比如被 node:test 直接 require）用内存兜底 */
  var memoryStore = {}

  // ------------------------------------------------------------
  // 纯逻辑区：这一段不碰 DOM，可以被 node:test 直接测
  // ------------------------------------------------------------

  /** 档位在四档里的下标；认不出来的返回 -1 */
  function hintLevelIndex(level) {
    for (var i = 0; i < HINT_LEVELS.length; i += 1) {
      if (HINT_LEVELS[i] === level) return i
    }
    return -1
  }

  /** 这一档现在能不能用：下标不超过已解锁到的下标 */
  function isHintLevelUnlocked(unlockedIndex, level) {
    var idx = hintLevelIndex(level)
    if (idx === -1) return false
    return idx <= unlockedIndex
  }

  /**
   * 用完某一档之后，下一档解锁到哪儿。
   * 解锁进度只前进不回退；最高档用完也不越界。
   */
  function nextUnlockedIndex(currentIndex, level) {
    var idx = hintLevelIndex(level)
    if (idx === -1) return currentIndex
    var next = idx + 1
    if (next > HINT_LEVELS.length - 1) next = HINT_LEVELS.length - 1
    return next > currentIndex ? next : currentIndex
  }

  /** 讲解请求体。**默认只到思路层**；要代码必须显式传 level="代码"。 */
  function explainRequestBody(problemId, level, sid) {
    var lv = EXPLAIN_LEVELS.indexOf(level) !== -1 ? level : "思路"
    return { problemId: problemId, level: lv, sessionId: sid }
  }

  /** 求助请求体 */
  function hintRequestBody(problemId, level, sid) {
    return { problemId: problemId, level: level, sessionId: sid }
  }

  /** 取 sessionStorage；没有或被浏览器禁用就返回 null */
  function getSessionStorage() {
    try {
      return global.sessionStorage || null
    } catch (err) {
      return null
    }
  }

  /** 某题已经解锁到第几档；默认 0（只有「方向」可用） */
  function getUnlocked(problemId) {
    var key = UNLOCK_KEY_PREFIX + problemId
    var ss = getSessionStorage()
    if (ss) {
      try {
        var raw = ss.getItem(key)
        return raw === null ? 0 : (Number(raw) || 0)
      } catch (err) {
        // 落到内存兜底
      }
    }
    return Number(memoryStore[key] || 0)
  }

  /** 记下某题解锁到第几档 */
  function setUnlocked(problemId, index) {
    var key = UNLOCK_KEY_PREFIX + problemId
    var ss = getSessionStorage()
    if (ss) {
      try {
        ss.setItem(key, String(index))
        return
      } catch (err) {
        // 落到内存兜底
      }
    }
    memoryStore[key] = index
  }

  /** 清掉所有解锁进度（测试与「重置」按钮用） */
  function resetUnlocks() {
    var ss = getSessionStorage()
    if (ss) {
      try {
        for (var i = 0; i < ss.length; i += 1) {
          var k = ss.key(i)
          if (k && k.indexOf(UNLOCK_KEY_PREFIX) === 0) ss.removeItem(k)
        }
      } catch (err) {
        // 忽略
      }
    }
    for (var name in memoryStore) {
      if (Object.prototype.hasOwnProperty.call(memoryStore, name) && name.indexOf(UNLOCK_KEY_PREFIX) === 0) {
        delete memoryStore[name]
      }
    }
  }

  /** 造一个会话号 */
  function newSessionId() {
    return "s-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8)
  }

  /** 本次会话的会话号：成本护栏按它计数 */
  function sessionId() {
    var ss = getSessionStorage()
    if (ss) {
      try {
        var id = ss.getItem(SESSION_ID_KEY)
        if (id) return id
        id = newSessionId()
        ss.setItem(SESSION_ID_KEY, id)
        return id
      } catch (err) {
        // 落到内存兜底
      }
    }
    if (!memoryStore[SESSION_ID_KEY]) {
      memoryStore[SESSION_ID_KEY] = newSessionId()
    }
    return memoryStore[SESSION_ID_KEY]
  }

  // ------------------------------------------------------------
  // DOM 区
  // ------------------------------------------------------------

  /** 造元素；attrs 里 text 设文字、on* 绑事件 */
  function el(tag, attrs, children) {
    var node = global.document.createElement(tag)
    if (attrs) {
      for (var key in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, key)) continue
        var value = attrs[key]
        if (value === null || value === undefined) continue
        if (key === "class") node.className = value
        else if (key === "text") node.textContent = value
        else if (key.indexOf("on") === 0 && typeof value === "function") {
          node.addEventListener(key.slice(2).toLowerCase(), value)
        } else node.setAttribute(key, value)
      }
    }
    if (children !== null && children !== undefined) {
      var list = Array.isArray(children) ? children : [children]
      for (var i = 0; i < list.length; i += 1) {
        var child = list[i]
        if (child === null || child === undefined) continue
        node.appendChild(typeof child === "string" ? global.document.createTextNode(child) : child)
      }
    }
    return node
  }

  /** 调后端；失败时抛一个带 message 与 status 的 Error */
  function call(path, body) {
    var opts = {
      method: body === undefined ? "GET" : "POST",
      headers: { "content-type": "application/json" },
    }
    if (body !== undefined) opts.body = JSON.stringify(body)
    return global.fetch(path, opts).then(function (res) {
      return res.text().then(function (text) {
        var data = null
        try {
          data = text ? JSON.parse(text) : null
        } catch (err) {
          data = null
        }
        if (!res.ok) {
          var message = data && data.error
            ? String(data.error)
            : ("请求失败（HTTP " + res.status + "）")
          var failure = new Error(message)
          failure.status = res.status
          throw failure
        }
        return data
      })
    })
  }

  /** 当前状态 */
  var state = {
    problems: [],
    currentId: "",
    settings: null,
  }

  /** 主容器 */
  function getView() {
    if (!global.document) return null
    return global.document.getElementById("view")
  }

  /** 页面上带 data-problem-id 的元素 */
  function findProblemIdInView(view) {
    if (!view || !view.querySelector) return ""
    var node = view.querySelector("[data-problem-id]")
    if (!node) return ""
    return node.getAttribute("data-problem-id") || ""
  }

  /** 地址栏里的题号 */
  function findProblemIdInHash() {
    var hash = (global.location && global.location.hash) || ""
    var m = /(?:^|[#\/=])(lc|nc|jz|self|llm)-[0-9a-z]{5,12}/.exec(hash)
    return m ? m[0] : ""
  }

  /** 当前题号：优先页面上标出来的，其次地址栏，最后下拉框 */
  function currentProblemId() {
    var fromView = findProblemIdInView(getView())
    if (fromView) return fromView
    var fromHash = findProblemIdInHash()
    if (fromHash) return fromHash
    return state.currentId
  }

  /** 状态栏 */
  function setStatus(text) {
    var node = global.document.getElementById("llm-status")
    if (node) node.textContent = text || ""
  }

  // ------------------------------------------------------------
  // 讲解（先思路后代码）
  // ------------------------------------------------------------

  function onExplain(problemId, level) {
    if (!problemId) {
      setStatus("请先选一道题")
      return
    }
    if (level === "代码") {
      var ok = global.confirm
        ? global.confirm("确定直接看代码？这题基本等于抄答案了。")
        : false
      if (!ok) return
    }
    var body = explainRequestBody(problemId, level, sessionId())
    setStatus("正在讲解……")
    call("/api/llm/explain", body).then(function (data) {
      var out = global.document.getElementById("llm-explain-out")
      if (out) out.textContent = data.text
      var meta = global.document.getElementById("llm-explain-meta")
      if (meta) meta.textContent = "模型：" + data.model
      setStatus("讲解完成")
    }).catch(function (err) {
      var out = global.document.getElementById("llm-explain-out")
      if (out) out.textContent = "讲解失败：" + err.message
      setStatus("讲解失败")
    })
  }

  function renderExplainButtons(problemId) {
    var wrap = el("div", { class: "llm-buttons", id: "llm-explain-buttons" })
    EXPLAIN_LEVELS.forEach(function (level) {
      wrap.appendChild(el("button", {
        class: "btn" + (level === "代码" ? " btn-warn" : ""),
        type: "button",
        text: EXPLAIN_LABELS[level],
        onclick: function () { onExplain(problemId, level) },
      }))
    })
    return wrap
  }

  // ------------------------------------------------------------
  // 求助（四档逐级解锁）
  // ------------------------------------------------------------

  function onHint(problemId, level) {
    if (!problemId) {
      setStatus("请先选一道题")
      return
    }
    var unlocked = getUnlocked(problemId)
    if (!isHintLevelUnlocked(unlocked, level)) {
      setStatus("求助是逐级解锁的：先用「" + (HINT_LEVELS[unlocked] || "方向") + "」那一档")
      return
    }
    var body = hintRequestBody(problemId, level, sessionId())
    setStatus("正在给提示……")
    call("/api/llm/hint", body).then(function (data) {
      var next = nextUnlockedIndex(unlocked, level)
      var out = global.document.getElementById("llm-hint-out")
      if (out) out.textContent = data.text
      var meta = global.document.getElementById("llm-hint-meta")
      if (meta) meta.textContent = "模型：" + data.model + "；已解锁到「" + HINT_LEVELS[next] + "」那档"
      setUnlocked(problemId, next)
      refreshHintButtons(problemId)
      setStatus("提示已给出")
    }).catch(function (err) {
      var out = global.document.getElementById("llm-hint-out")
      if (out) out.textContent = "求助失败：" + err.message
      setStatus("求助失败")
    })
  }

  function renderHintButtons(problemId) {
    var wrap = el("div", { class: "llm-buttons", id: "llm-hint-buttons" })
    var unlocked = getUnlocked(problemId)
    HINT_LEVELS.forEach(function (level) {
      var usable = isHintLevelUnlocked(unlocked, level)
      var attrs = {
        class: "btn" + (usable ? "" : " btn-off"),
        type: "button",
        text: usable ? level : level + "（未解锁）",
        onclick: function () { onHint(problemId, level) },
      }
      if (!usable) attrs.disabled = "disabled"
      wrap.appendChild(el("button", attrs))
    })
    return wrap
  }

  /** 求助用完一档后，刷新按钮的解锁状态 */
  function refreshHintButtons(problemId) {
    var holder = global.document.getElementById("llm-hint-buttons")
    if (!holder || !holder.parentNode) return
    holder.parentNode.replaceChild(renderHintButtons(problemId), holder)
  }

  // ------------------------------------------------------------
  // 题目选择
  // ------------------------------------------------------------

  function renderProblemPicker() {
    var select = el("select", {
      id: "llm-problem",
      onchange: function (ev) {
        state.currentId = ev.target.value
        refreshForProblem()
      },
    })
    state.problems.forEach(function (p) {
      var label = p.title + "（" + p.id + "）" + (p.needsFill ? " ⚠ 缺题面或用例" : "")
      select.appendChild(el("option", { value: p.id, text: label }))
    })
    if (!state.currentId && state.problems.length > 0) {
      state.currentId = state.problems[0].id
    }
    if (state.currentId) select.value = state.currentId
    return select
  }

  /** 当前题变了，刷新讲解与求助的按钮 */
  function refreshForProblem() {
    var problemId = currentProblemId()
    var explainHolder = global.document.getElementById("llm-explain-buttons")
    if (explainHolder && explainHolder.parentNode) {
      explainHolder.parentNode.replaceChild(renderExplainButtons(problemId), explainHolder)
    }
    var hintHolder = global.document.getElementById("llm-hint-buttons")
    if (hintHolder && hintHolder.parentNode) {
      hintHolder.parentNode.replaceChild(renderHintButtons(problemId), hintHolder)
    }
  }

  // ------------------------------------------------------------
  // 面板与挂载
  // ------------------------------------------------------------

  function renderPanel() {
    var parts = []
    parts.push(el("h2", { text: "LLM 工作台" }))
    parts.push(el("p", {
      class: "muted",
      text: "LLM 是可选增强：关掉也不影响排程、判题、复习与进度。",
    }))
    parts.push(el("div", { class: "llm-row" }, [
      el("span", { class: "llm-label", text: "当前题目" }),
      renderProblemPicker(),
      el("button", {
        class: "btn",
        type: "button",
        text: "刷新题库",
        onclick: function () { mount() },
      }),
      el("span", { id: "llm-status", class: "muted", text: "" }),
    ]))

    parts.push(el("div", { class: "llm-row" }, [
      el("strong", { text: "讲解" }),
      renderExplainButtons(currentProblemId()),
      el("span", { class: "muted", text: "默认只讲思路；「直接给代码」要自己点。" }),
    ]))
    parts.push(el("pre", { id: "llm-explain-out", class: "llm-out", text: "" }))
    parts.push(el("div", { id: "llm-explain-meta", class: "llm-meta muted", text: "" }))

    parts.push(el("div", { class: "llm-row" }, [
      el("strong", { text: "求助" }),
      renderHintButtons(currentProblemId()),
      el("span", { class: "muted", text: "四档逐级解锁：用完一档才放开下一档。" }),
    ]))
    parts.push(el("pre", { id: "llm-hint-out", class: "llm-out", text: "" }))
    parts.push(el("div", { id: "llm-hint-meta", class: "llm-meta muted", text: "" }))

    // >>> M6-TASK8 在这里追加造题、补全、设置三块 <<<

    return el("section", { class: "panel llm-panel", id: "llm-panel" }, parts)
  }

  /** 把面板挂到 main#view 顶部 */
  function mountPanel() {
    var view = getView()
    if (!view) return
    var old = global.document.getElementById("llm-panel")
    if (old && old.parentNode) old.parentNode.removeChild(old)
    view.insertBefore(renderPanel(), view.firstChild)
    if (state.settings) {
      var st = global.document.getElementById("llm-status")
      if (st && !st.textContent) {
        st.textContent = state.settings.effectiveProvider === "null"
          ? ("LLM 未启用：" + state.settings.reason)
          : ("LLM：" + state.settings.effectiveProvider + " / " + state.settings.effectiveModel)
      }
    }
  }

  /** 拉题库 */
  function loadBank() {
    return call("/api/bank").then(function (data) {
      state.problems = data && data.items ? data.items : []
      return state.problems
    }).catch(function () {
      state.problems = []
      return state.problems
    })
  }

  /** 拉 LLM 设置 */
  function loadSettings() {
    return call("/api/llm/settings").then(function (data) {
      state.settings = data
      return data
    }).catch(function () {
      state.settings = null
      return null
    })
  }

  var mounting = false

  /** 挂载入口：拉设置与题库，然后挂面板 */
  function mount() {
    if (mounting) return
    mounting = true
    loadSettings()
      .then(function () { return loadBank() })
      .then(function () {
        mounting = false
        mountPanel()
      })
      .catch(function () {
        mounting = false
      })
  }

  /** 页面上出现带 data-problem-id 的元素时，同步当前题 */
  function enhance() {
    var id = findProblemIdInView(getView())
    if (id && id !== state.currentId) {
      state.currentId = id
      refreshForProblem()
    }
  }

  var exported = {
    HINT_LEVELS: HINT_LEVELS,
    EXPLAIN_LEVELS: EXPLAIN_LEVELS,
    hintLevelIndex: hintLevelIndex,
    isHintLevelUnlocked: isHintLevelUnlocked,
    nextUnlockedIndex: nextUnlockedIndex,
    explainRequestBody: explainRequestBody,
    hintRequestBody: hintRequestBody,
    getUnlocked: getUnlocked,
    setUnlocked: setUnlocked,
    resetUnlocks: resetUnlocks,
    sessionId: sessionId,
    // >>> M6-TASK8 在这里追加导出 <<<
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = exported
  }
  global.AlgoPlanLlm = exported

  // 浏览器里自动挂载；被 node:test require 时这段不执行
  if (typeof global.document !== "undefined" && global.document.addEventListener) {
    global.document.addEventListener("DOMContentLoaded", function () {
      mount()
      var view = getView()
      if (view && global.MutationObserver) {
        var observer = new global.MutationObserver(function () {
          if (!global.document.getElementById("llm-panel")) {
            mount()
            return
          }
          enhance()
        })
        observer.observe(view, { childList: true, subtree: true })
      }
    })
  }
})(typeof globalThis !== "undefined" ? globalThis : this)
```

- [ ] **Step 4: 改 `web/index.html`（加一行）**

把这一段：

```html
  <script src="/app.js"></script>
```

改成：

```html
  <script src="/app.js"></script>
  <script src="/llm.js"></script>
```

> **为什么加在 `app.js` 后面：** 让 app.js 先把自己的页面渲染出来，
> llm.js 再把工作台插到 `#view` 顶部，顺序更自然。

- [ ] **Step 5: 在 `web/style.css` 末尾追加 LLM 面板样式**

在 `projects/apps/algo-plan/web/style.css` **末尾追加**下面这段：

```css
/* ---- M6：LLM 工作台 ---- */
.llm-panel h2 { color: var(--accent); }
.llm-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px 12px;
  margin: 10px 0;
}
.llm-label { color: var(--muted); font-size: 13px; }
.llm-buttons { display: inline-flex; flex-wrap: wrap; gap: 8px; }
.llm-panel .btn {
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 6px;
  color: var(--fg);
  padding: 4px 12px;
  font-size: 13px;
  cursor: pointer;
}
.llm-panel .btn:hover { border-color: var(--accent); color: var(--accent); }
.llm-panel .btn-warn { color: var(--warn); border-color: var(--warn); }
.llm-panel .btn-off { color: var(--muted); cursor: not-allowed; opacity: 0.6; }
.llm-panel .btn-off:hover { border-color: var(--line); color: var(--muted); }
.llm-panel select {
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 6px;
  color: var(--fg);
  padding: 4px 8px;
  font-size: 13px;
  min-width: 260px;
}
.llm-out {
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 10px 12px;
  margin: 8px 0 4px;
  white-space: pre-wrap;
  word-break: break-word;
  font-size: 13px;
  max-height: 320px;
  overflow: auto;
}
.llm-meta { margin-bottom: 12px; }
```

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
node --check web/llm.js
```

Expected: `llm-web.test.js` 套件全绿（PASS），`node --check web/llm.js` 无输出（语法正确），退出码 0。

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/web/llm.js apps/algo-plan/web/index.html apps/algo-plan/web/style.css apps/algo-plan/tests/llm-web.test.js
git commit -m "feat(algo-plan): 新增 LLM 工作台前端，接入讲解与四档逐级求助

- web/llm.js 自挂载，不改 app.js，避免与其它里程碑的页面代码冲突
- 讲解默认只到思路层，直接给代码是独立按钮且要点确认
- 求助四档逐级解锁，用完一档才放开下一档，进度存 sessionStorage
- 纯逻辑区用 node:test 钉住，四档顺序与解锁规则不会悄悄改坏"
git push origin main
```

---

## Task 8: 前端 —— 题库页的「来一题新的」与「让 LLM 补全」，以及设置页

本 task 补齐设计文档 §7.1 要求的另外两块前端：
- **题库页**：`needs-fill` 标记、**「来一题新的」**入口、**「让 LLM 补全」**入口；
- **设置页**：LLM provider 与开关、模型名、**密钥来源说明**。

**仍然是加法：** `web/app.js` 一个字都不改，全部代码塞进 `web/llm.js`，
靠 Task 7 留好的三个锚点插进去。

**这个 task 的两处后端加法：**
1. `GET /api/llm/settings` 的响应里多两个字段 `tracks` 与 `difficulties`——
   前端要靠它渲染「轨道」「难度」下拉框，**值直接来自 M1 冻结的 `TRACKS` / `DIFFICULTIES`**，
   前端不自己硬编码一份轨道名（否则两边会漂）。
2. `core/llm/service.js` 的 `describe()` 多返回这两个字段。

**Files:**
- Modify: `projects/apps/algo-plan/core/llm/service.js`（`describe()` 多两个字段）
- Modify: `projects/apps/algo-plan/web/llm.js`（四处加法，见 Step 4）
- Modify: `projects/apps/algo-plan/web/style.css`（末尾追加样式）
- Test: `projects/apps/algo-plan/tests/llm-web-bank.test.js`

**Interfaces:**
- Consumes:
  - 后端接口 `POST /api/bank/llm-generate`（`{track, topics[], difficulty, sessionId}` → `{problem, model}`）
  - 后端接口 `POST /api/llm/fill`（`{problemId, sessionId}` → `{problem, model}`）
  - 后端接口 `GET /api/llm/settings`（新增 `tracks`、`difficulties` 两个字段）
  - 后端接口 `PUT /api/llm/settings`（`{enabled?, provider?, model?, baseUrl?}` → `{ok, settings}`）
- Produces:
  - `window.AlgoPlanLlm` 新增导出：`needsFillList(problems)`、`generateRequestBody(track, topics, difficulty, sessionId)`、
    `fillRequestBody(problemId, sessionId)`、`settingsRequestBody(patch)`、`describeKeySource(settings)`
  - DOM：题库下拉框里 `needsFill` 的题带「⚠ 缺题面或用例」标记；
    缺题目的题后面跟一个「让 LLM 补全」按钮；设置区有开关、provider 下拉、模型名输入框

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-web-bank.test.js`**

创建 `projects/apps/algo-plan/tests/llm-web-bank.test.js`：

```javascript
"use strict"
/**
 * llm-web-bank.test.js —— 题库页与设置页的前端纯逻辑测试（**不联网、不碰 DOM**）
 *
 * 钉住：
 *   1. needs-fill 的题能从列表里挑出来；
 *   2. 造题与补全的请求体形状；
 *   3. 设置请求体只留四个白名单字段，**任何像密钥的字段一律丢掉**（G27）。
 */

const test = require("node:test")
const assert = require("node:assert/strict")

const Llm = require("../web/llm.js")

test("needsFillList 只挑出缺题面或缺用例的题", function () {
  const list = [
    { id: "lc-00001", title: "正常的题", needsFill: false },
    { id: "lc-00002", title: "缺题面的题", needsFill: true },
    { id: "llm-0000000001", title: "缺用例的题", needsFill: true },
  ]
  const missing = Llm.needsFillList(list)
  assert.equal(missing.length, 2)
  assert.deepEqual(missing.map(function (p) { return p.id }), ["lc-00002", "llm-0000000001"])
  assert.deepEqual(Llm.needsFillList([]), [])
  assert.deepEqual(Llm.needsFillList(null), [])
})

test("造题请求体：轨道、知识点、难度、会话号", function () {
  assert.deepEqual(Llm.generateRequestBody("interview", ["哈希表"], "medium", "s1"), {
    track: "interview",
    topics: ["哈希表"],
    difficulty: "medium",
    sessionId: "s1",
  })
})

test("造题请求体：知识点不是数组就当空的，难度缺省 medium", function () {
  const body = Llm.generateRequestBody("interview", "哈希表", undefined, "s1")
  assert.deepEqual(body.topics, [])
  assert.equal(body.difficulty, "medium")
})

test("补全请求体：题号与会话号", function () {
  assert.deepEqual(Llm.fillRequestBody("lc-00002", "s1"), {
    problemId: "lc-00002",
    sessionId: "s1",
  })
})

test("设置请求体只留四个白名单字段，密钥字段一律丢掉（G27）", function () {
  const body = Llm.settingsRequestBody({
    enabled: true,
    provider: "ark",
    model: "doubao-seed-1-6-251015",
    baseUrl: "https://ark.cn-beijing.volces.com/api/v3",
    apiKey: "super-secret",
    key: "super-secret",
    token: "super-secret",
    ANTHROPIC_API_KEY: "super-secret",
  })
  assert.deepEqual(Object.keys(body).sort(), ["baseUrl", "enabled", "model", "provider"])
  assert.ok(!JSON.stringify(body).includes("super-secret"), "请求体里绝不能出现密钥")
})

test("设置请求体：没传的字段就不出现", function () {
  assert.deepEqual(Llm.settingsRequestBody({ enabled: false }), { enabled: false })
  assert.deepEqual(Llm.settingsRequestBody({}), {})
})

test("密钥来源说明是人话，而且不含密钥本身", function () {
  const 说明 = Llm.describeKeySource({
    effectiveProvider: "ark",
    effectiveModel: "doubao-seed-1-6-251015",
    keySource: "环境变量 ARK_API_KEY",
    reason: "",
  })
  assert.ok(说明.includes("ARK_API_KEY"), "说明里要点名密钥来自哪个变量：" + 说明)
  assert.ok(说明.includes("doubao-seed-1-6-251015"), "说明里要报当前模型：" + 说明)

  const 关闭 = Llm.describeKeySource({ effectiveProvider: "null", reason: "没有配置密钥" })
  assert.ok(关闭.includes("LLM 未启用"), "关掉时要说明未启用：" + 关闭)
  assert.ok(关闭.includes("没有配置密钥"), "关掉时要说明原因：" + 关闭)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-web-bank.test.js` 报 `TypeError: Llm.needsFillList is not a function`。

- [ ] **Step 3: 改 `core/llm/service.js`（`describe()` 多两个字段）**

把这一段：

```javascript
      keySource: keySourceOf(s.provider || client.name, env),
      reason: client.name === "null" ? String(client.reason || "") : "",
      quota: {
```

改成：

```javascript
      keySource: keySourceOf(s.provider || client.name, env),
      reason: client.name === "null" ? String(client.reason || "") : "",
      tracks: TRACKS,
      difficulties: DIFFICULTIES,
      quota: {
```

> `TRACKS` 与 `DIFFICULTIES` 是 Task 4 已经从 `core/bank/problem.js` import 进来的 M1 冻结常量，
> 这里只是把它们透给前端，前端**不硬编码**轨道名与难度名。

- [ ] **Step 4: 改 `web/llm.js`（四处加法）**

**改动 A —— 先让 `call()` 支持自定义方法（PUT 要用）。**
把这一段：

```javascript
  /** 调后端；失败时抛一个带 message 与 status 的 Error */
  function call(path, body) {
    var opts = {
      method: body === undefined ? "GET" : "POST",
      headers: { "content-type": "application/json" },
    }
```

改成：

```javascript
  /** 调后端；失败时抛一个带 message 与 status 的 Error */
  function call(path, body, method) {
    var opts = {
      method: method || (body === undefined ? "GET" : "POST"),
      headers: { "content-type": "application/json" },
    }
```

**改动 B —— 插入造题、补全、设置三块的功能代码。**
把这一段：

```javascript
  // ------------------------------------------------------------
  // 面板与挂载
  // ------------------------------------------------------------
```

改成：

```javascript
  // ------------------------------------------------------------
  // 造题、补全、设置
  // ------------------------------------------------------------

  /** 可选的 provider 列表；"null" 表示干脆不接 LLM */
  var PROVIDERS = ["ark", "anthropic", "null"]

  /** 从题目列表里挑出缺题面或缺用例的（needs_fill: true） */
  function needsFillList(problems) {
    var list = Array.isArray(problems) ? problems : []
    return list.filter(function (p) { return !!p && p.needsFill === true })
  }

  /** 造题请求体 */
  function generateRequestBody(track, topics, difficulty, sid) {
    return {
      track: String(track || ""),
      topics: Array.isArray(topics) ? topics.slice() : [],
      difficulty: String(difficulty || "medium"),
      sessionId: sid,
    }
  }

  /** 补全请求体 */
  function fillRequestBody(problemId, sid) {
    return { problemId: String(problemId || ""), sessionId: sid }
  }

  /**
   * 设置请求体：**只保留四个白名单字段**，
   * 任何像密钥的字段（apiKey / key / token / secret）一律丢掉（G27）。
   */
  function settingsRequestBody(patch) {
    var p = patch || {}
    var out = {}
    if (p.enabled !== undefined) out.enabled = !!p.enabled
    if (p.provider !== undefined) out.provider = String(p.provider)
    if (p.model !== undefined) out.model = String(p.model)
    if (p.baseUrl !== undefined) out.baseUrl = String(p.baseUrl)
    return out
  }

  /** 把后端报的密钥来源讲成人话 */
  function describeKeySource(settings) {
    var s = settings || {}
    if (!s.effectiveProvider || s.effectiveProvider === "null") {
      return "LLM 未启用：" + (s.reason || "没有配置密钥")
    }
    return "密钥来自 " + (s.keySource || "环境变量")
      + "；当前 provider 是 " + s.effectiveProvider
      + "，模型 " + (s.effectiveModel || "（未设置）")
  }

  /** 把输入框里的知识点拆成数组（顿号、逗号、空格都算分隔符） */
  function splitTopics(text) {
    return String(text || "")
      .split(/[,，、\s]+/)
      .filter(function (t) { return t !== "" })
  }

  /** 「来一题新的」：调后端造题，**由后端落盘进 learning/bank**（G25） */
  function onGenerate() {
    var track = global.document.getElementById("llm-gen-track")
    var difficulty = global.document.getElementById("llm-gen-difficulty")
    var topicsInput = global.document.getElementById("llm-gen-topics")
    var body = generateRequestBody(
      track ? track.value : "",
      splitTopics(topicsInput ? topicsInput.value : ""),
      difficulty ? difficulty.value : "medium",
      sessionId()
    )
    setStatus("正在造题……")
    call("/api/bank/llm-generate", body).then(function (data) {
      state.currentId = data.problem.id
      var out = global.document.getElementById("llm-gen-out")
      if (out) {
        out.textContent = "《" + data.problem.title + "》（" + data.problem.id
          + "）已生成并落盘进 learning/bank/。\n模型：" + data.model
      }
      setStatus("造题完成")
      return loadBank()
    }).then(function () {
      refreshBankViews()
    }).catch(function (err) {
      var out = global.document.getElementById("llm-gen-out")
      if (out) out.textContent = "造题失败：" + err.message
      setStatus("造题失败")
    })
  }

  /** 缺题面的题列表，每条后面跟一个「让 LLM 补全」 */
  function renderFillList() {
    var list = el("div", { class: "llm-row", id: "llm-fill-list" })
    var missing = needsFillList(state.problems)
    if (missing.length === 0) {
      list.appendChild(el("span", { class: "muted", text: "题库里没有缺题面或缺用例的题。" }))
      return list
    }
    missing.forEach(function (p) {
      list.appendChild(el("span", { class: "llm-fill-item" }, [
        el("span", { text: p.title + "（" + p.id + "）" }),
        el("button", {
          class: "btn",
          type: "button",
          text: "让 LLM 补全",
          onclick: function () { onFill(p.id) },
        }),
      ]))
    })
    return list
  }

  /** 「让 LLM 补全」：调后端补全，**由后端写回题库**（G25） */
  function onFill(problemId) {
    var body = fillRequestBody(problemId, sessionId())
    setStatus("正在补全……")
    call("/api/llm/fill", body).then(function (data) {
      state.currentId = data.problem.id
      var out = global.document.getElementById("llm-fill-out")
      if (out) {
        out.textContent = "《" + data.problem.title + "》（" + data.problem.id
          + "）已补全并写回题库。\n模型：" + data.model
      }
      setStatus("补全完成")
      return loadBank()
    }).then(function () {
      refreshBankViews()
    }).catch(function (err) {
      var out = global.document.getElementById("llm-fill-out")
      if (out) out.textContent = "补全失败：" + err.message
      setStatus("补全失败")
    })
  }

  /** 保存 LLM 设置 */
  function onSaveSettings() {
    var enabledBox = global.document.getElementById("llm-set-enabled")
    var providerSelect = global.document.getElementById("llm-set-provider")
    var modelInput = global.document.getElementById("llm-set-model")
    var patch = {}
    if (enabledBox) patch.enabled = !!enabledBox.checked
    if (providerSelect) patch.provider = providerSelect.value
    if (modelInput) patch.model = modelInput.value
    var body = settingsRequestBody(patch)
    setStatus("正在保存设置……")
    call("/api/llm/settings", body, "PUT").then(function () {
      setStatus("设置已保存")
      return loadSettings()
    }).then(function () {
      mountPanel()
    }).catch(function (err) {
      setStatus("保存失败：" + err.message)
    })
  }

  /** 造题区块 */
  function renderGenerateSection() {
    var settings = state.settings || {}
    var tracks = Array.isArray(settings.tracks) ? settings.tracks : []
    var difficulties = Array.isArray(settings.difficulties) ? settings.difficulties : ["easy", "medium", "hard"]
    var trackSelect = el("select", { id: "llm-gen-track" })
    tracks.forEach(function (t) {
      trackSelect.appendChild(el("option", { value: String(t), text: String(t) }))
    })
    var diffSelect = el("select", { id: "llm-gen-difficulty" })
    difficulties.forEach(function (d) {
      diffSelect.appendChild(el("option", { value: String(d), text: String(d) }))
    })
    return el("div", { class: "llm-block" }, [
      el("div", { class: "llm-row" }, [
        el("strong", { text: "来一题新的" }),
        el("span", { class: "muted", text: "轨道" }),
        trackSelect,
        el("span", { class: "muted", text: "难度" }),
        diffSelect,
        el("span", { class: "muted", text: "知识点（顿号或逗号隔开）" }),
        el("input", { id: "llm-gen-topics", type: "text", placeholder: "哈希表、数组" }),
        el("button", {
          class: "btn",
          type: "button",
          text: "来一题新的",
          onclick: onGenerate,
        }),
      ]),
      el("pre", { id: "llm-gen-out", class: "llm-out", text: "" }),
    ])
  }

  /** 补全区块 */
  function renderFillSection() {
    return el("div", { class: "llm-block" }, [
      el("div", { class: "llm-row" }, [
        el("strong", { text: "补全缺口" }),
        el("span", { class: "muted", text: "题面或测试用例缺失的题，可以让 LLM 反推补齐。" }),
      ]),
      renderFillList(),
      el("pre", { id: "llm-fill-out", class: "llm-out", text: "" }),
    ])
  }

  /** 设置区块 */
  function renderSettingsSection() {
    var s = state.settings || {}
    var enabledBox = el("input", { id: "llm-set-enabled", type: "checkbox" })
    if (s.enabled) enabledBox.checked = true
    var providerSelect = el("select", { id: "llm-set-provider" })
    PROVIDERS.forEach(function (p) {
      var label = p === "null" ? "关闭（不接 LLM）" : p
      providerSelect.appendChild(el("option", { value: p, text: label }))
    })
    if (s.provider) providerSelect.value = s.provider
    var modelInput = el("input", { id: "llm-set-model", type: "text", placeholder: "留空用默认模型" })
    if (s.model) modelInput.value = s.model
    return el("div", { class: "llm-block" }, [
      el("div", { class: "llm-row" }, [
        el("strong", { text: "LLM 设置" }),
        el("span", { class: "muted", text: "启用" }),
        enabledBox,
        el("span", { class: "muted", text: "provider" }),
        providerSelect,
        el("span", { class: "muted", text: "模型名" }),
        modelInput,
        el("button", { class: "btn", type: "button", text: "保存", onclick: onSaveSettings }),
      ]),
      el("div", { class: "llm-meta muted", text: describeKeySource(s) }),
      el("div", {
        class: "llm-meta muted",
        text: "密钥不进这个页面，也不进 settings 表：只从环境变量读。",
      }),
    ])
  }

  /** 造题或补全之后，只刷新题库相关的两块（讲解与求助的输出不动） */
  function refreshBankViews() {
    var picker = global.document.getElementById("llm-problem")
    if (picker && picker.parentNode) {
      picker.parentNode.replaceChild(renderProblemPicker(), picker)
    }
    var fillList = global.document.getElementById("llm-fill-list")
    if (fillList && fillList.parentNode) {
      fillList.parentNode.replaceChild(renderFillList(), fillList)
    }
  }

  // ------------------------------------------------------------
  // 面板与挂载
  // ------------------------------------------------------------
```

**改动 C —— 把三块塞进面板。**
把这一段：

```javascript
    // >>> M6-TASK8 在这里追加造题、补全、设置三块 <<<
```

改成：

```javascript
    parts.push(renderGenerateSection())
    parts.push(renderFillSection())
    parts.push(renderSettingsSection())
```

**改动 D —— 补上导出。**
把这一段：

```javascript
    // >>> M6-TASK8 在这里追加导出 <<<
```

改成：

```javascript
    needsFillList: needsFillList,
    generateRequestBody: generateRequestBody,
    fillRequestBody: fillRequestBody,
    settingsRequestBody: settingsRequestBody,
    describeKeySource: describeKeySource,
```

- [ ] **Step 5: 在 `web/style.css` 末尾追加样式**

在 `projects/apps/algo-plan/web/style.css` **末尾追加**下面这段：

```css
/* ---- M6：题库造题、补全与设置 ---- */
.llm-block {
  border-top: 1px solid var(--line);
  margin-top: 14px;
  padding-top: 12px;
}
.llm-fill-item {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  border: 1px solid var(--warn);
  border-radius: 999px;
  padding: 2px 6px 2px 12px;
  font-size: 13px;
  color: var(--warn);
}
.llm-panel input[type="text"] {
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 6px;
  color: var(--fg);
  padding: 4px 8px;
  font-size: 13px;
  min-width: 200px;
}
.llm-panel input[type="checkbox"] {
  width: 16px;
  height: 16px;
  vertical-align: middle;
}
```

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
node --check web/llm.js
```

Expected: `llm-web-bank.test.js` 套件全绿（PASS），`node --check web/llm.js` 无输出，退出码 0。

- [ ] **Step 7: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/core/llm/service.js apps/algo-plan/web/llm.js apps/algo-plan/web/style.css apps/algo-plan/tests/llm-web-bank.test.js
git commit -m "feat(algo-plan): 补上题库造题入口、缺口补全入口与 LLM 设置面板

- 题库页新增「来一题新的」与「让 LLM 补全」，缺题面的题在列表里带标记
- 设置区提供 LLM 开关、provider 下拉、模型名输入框与密钥来源说明
- 设置请求体只保留四个白名单字段，任何像密钥的字段一律丢掉
- 轨道与难度选项直接取后端给的 TRACKS 与 DIFFICULTIES，前端不硬编码"
git push origin main
```

---

## Task 9: 端到端验收、离线自检工具与 README

本 task 不加新功能，只做三件事：
1. **端到端验收**：起真服务，走一遍完整链路，验 M6 的四条硬线；
2. **离线自检工具** `tools/llm-check.js`：只读不写，**不发任何网络请求**，
   用来回答「我到底配对了没有」；
3. **README** 补上 LLM 一节。

**Files:**
- Create: `projects/apps/algo-plan/tests/llm-e2e.test.js`
- Create: `projects/apps/algo-plan/tools/llm-check.js`
- Modify: `projects/apps/algo-plan/README.md`（三处加法，见 Step 5）

**Interfaces:**
- Consumes:
  - `server/app.js` 的 `createApp({dbPath?, learningRoot?, env?, llmClient?})`（Task 5）
  - `server/main.js` 的 `loadDotEnv(file?)`（Task 5）
  - `core/llm/client.js` 的 `createLlmClient({env})`、`keySourceOf(provider, env)`（Task 2）
  - `core/llm/prompts.js` 的 `buildPrompt(kind, context)`、`KINDS`（Task 1）
  - `core/llm/guard.js` 的 `limits(store)`（Task 3）
  - `core/bank/problem.js` 的 `makeLlmId(seed)`（M1 已冻结）
- Produces:
  - `tools/llm-check.js` 导出 `check() -> boolean`；命令行直接跑时按结果给退出码
  - `tests/llm-e2e.test.js`：M6 的端到端验收证据

---

- [ ] **Step 1: 写会失败的测试 `tests/llm-e2e.test.js`**

创建 `projects/apps/algo-plan/tests/llm-e2e.test.js`：

```javascript
"use strict"
/**
 * llm-e2e.test.js —— M6 端到端验收（**注入假 client，全程不联网**）
 *
 * 走一遍完整链路：起服务 → 读题库 → 讲解 → 求助 → 批改思路 → 造题（落盘）→ 补全（写回）。
 * 验 M6 的四条硬线：
 *   1. 五个场景都跑通，响应形状与接口契约 §5 一致；
 *   2. 造出来的新题真的落在 learning/bank/ 里，文件里写着 source: llm；
 *   3. 讲解记下了 model 与提示词摘要（可追溯）；
 *   4. 成本护栏真的拦得住：单次会话第 21 次请求被挡住并提示。
 */

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")

/** 造一个带一道题的 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-e2e-"))
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
      "tracks: [interview]",
      "status: todo",
      "needs_fill: true",
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
      "| [2,7,11,15], 9 | [0,1]|",
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

/** 假客户端：按 system 提示里的关键词分派回复 */
function makeFakeClient() {
  const calls = []
  return {
    name: "ark",
    model: "fake-model",
    calls: calls,
    complete: async function (req) {
      calls.push(req)
      const sys = String(req.system || "")
      if (sys.includes("出题老师")) {
        return JSON.stringify({
          title: "三数之和",
          statement: "给一个数组，找出所有和为 0 的三元组。",
          difficulty: "medium",
          topics: ["双指针"],
          cases: [{ input: "[0,0,0]", expect: "[[0,0,0]]" }],
          solution: "int main(){ return 0; }",
          solutionLang: "cpp",
        })
      }
      if (sys.includes("批改用户的解题思路")) {
        return JSON.stringify({ verdict: "correct", comment: "思路没问题" })
      }
      if (sys.includes("反推出一道题")) {
        return JSON.stringify({
          statement: "补出来的题面",
          cases: [{ input: "[2,7], 9", expect: "[0,1]" }],
        })
      }
      return "这是一段模型回答。"
    },
  }
}

/** 发一个 POST 并把状态码与 JSON 一起返回 */
async function post(base, p, body) {
  const res = await fetch(base + p, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
  return { status: res.status, body: await res.json() }
}

test("端到端：五个场景跑通，造题落盘，讲解留痕", async function () {
  const root = tempLearning()
  const client = makeFakeClient()
  const app = createApp({
    dbPath: ":memory:",
    learningRoot: root,
    llmClient: client,
    env: {},
  })
  const port = await app.listen(0)
  const base = "http://127.0.0.1:" + port
  try {
    // 1. 题库读得到
    const bank = await (await fetch(base + "/api/bank")).json()
    assert.equal(bank.total, 1)

    // 2. 讲解
    const explain = await post(base, "/api/llm/explain", {
      problemId: "lc-00001",
      level: "思路",
      sessionId: "e2e",
    })
    assert.equal(explain.status, 200)
    assert.deepEqual(Object.keys(explain.body).sort(), ["model", "text"])
    assert.equal(explain.body.model, "fake-model")

    // 3. 求助
    const hint = await post(base, "/api/llm/hint", {
      problemId: "lc-00001",
      level: "方向",
      sessionId: "e2e",
    })
    assert.equal(hint.status, 200)
    assert.deepEqual(Object.keys(hint.body).sort(), ["model", "text"])

    // 4. 批改思路
    const grade = await post(base, "/api/llm/grade-idea", {
      problemId: "lc-00001",
      idea: "用哈希表",
      sessionId: "e2e",
    })
    assert.equal(grade.status, 200)
    assert.deepEqual(Object.keys(grade.body).sort(), ["comment", "model", "verdict"])
    assert.equal(grade.body.verdict, "correct")

    // 5. 造题并落盘
    const gen = await post(base, "/api/bank/llm-generate", {
      track: "interview",
      topics: ["双指针"],
      difficulty: "medium",
      sessionId: "e2e",
    })
    assert.equal(gen.status, 200)
    assert.deepEqual(Object.keys(gen.body).sort(), ["model", "problem"])
    assert.equal(gen.body.problem.source, "llm")
    assert.ok(gen.body.problem.id.startsWith("llm-"), "题号应是 llm- 前缀：" + gen.body.problem.id)
    const 新题文件 = path.join(root, "bank", "interview", gen.body.problem.id + ".md")
    assert.ok(fs.existsSync(新题文件), "新题应落盘进 learning/bank：" + 新题文件)
    const 文件内容 = fs.readFileSync(新题文件, "utf8")
    assert.ok(文件内容.includes("source: llm"), "落盘文件里 source 应是 llm")
    assert.ok(文件内容.includes(gen.body.problem.id), "落盘文件里应带着题号")

    // 6. 补全并写回
    const fill = await post(base, "/api/llm/fill", {
      problemId: "lc-00001",
      sessionId: "e2e",
    })
    assert.equal(fill.status, 200)
    assert.equal(fill.body.problem.needsFill, false)
    const 补全后的文件 = fs.readFileSync(path.join(root, "bank", "interview", "lc-00001.md"), "utf8")
    // 原始文件写的是 needs_fill: true，写回后变成 false —— 这才证明文件真被重写了
    assert.ok(补全后的文件.includes("needs_fill: false"), "写回后 needs_fill 应从 true 变成 false")
    assert.ok(!补全后的文件.includes("needs_fill: true"), "写回后不该还留着 needs_fill: true")

    // 7. 讲解留痕：model + 提示词摘要
    const trace = JSON.parse(app.store.getSetting("llm.trace.lc-00001", "[]"))
    assert.ok(trace.length >= 3, "讲解、求助、批改都应留痕，实际 " + trace.length + " 条")
    const 讲解记录 = trace.filter(function (t) { return t.kind === "explain" })[0]
    assert.ok(讲解记录, "讲解应有记录")
    assert.equal(讲解记录.model, "fake-model")
    assert.ok(讲解记录.prompt.digest.length > 0, "记录里应有提示词摘要")
    assert.ok(讲解记录.prompt.length > 0, "记录里应有提示词长度")

    // 8. 配额计数落 settings 表
    assert.equal(app.store.getSetting("llm.quota.session.e2e"), "5")
    const 全部设置 = app.store.allSettings()
    const 每日键 = Object.keys(全部设置).filter(function (k) {
      return k.indexOf("llm.quota.daily.") === 0
    })
    assert.equal(每日键.length, 1, "应正好有一个每日计数键")
    assert.equal(全部设置[每日键[0]], "5")
  } finally {
    await app.close()
  }
})

test("端到端：单次会话第 21 次请求被护栏挡住，提示会话额度用完", async function () {
  const root = tempLearning()
  const app = createApp({
    dbPath: ":memory:",
    learningRoot: root,
    llmClient: makeFakeClient(),
    env: {},
  })
  const port = await app.listen(0)
  const base = "http://127.0.0.1:" + port
  try {
    for (let i = 0; i < 20; i += 1) {
      const r = await post(base, "/api/llm/explain", {
        problemId: "lc-00001",
        level: "思路",
        sessionId: "cap",
      })
      assert.equal(r.status, 200, "第 " + (i + 1) + " 次应当成功")
    }
    const 第21次 = await post(base, "/api/llm/explain", {
      problemId: "lc-00001",
      level: "思路",
      sessionId: "cap",
    })
    assert.equal(第21次.status, 429, "第 21 次应被护栏挡住")
    assert.ok(第21次.body.error.includes("本次会话"), "提示里应说明是会话额度用完：" + 第21次.body.error)
  } finally {
    await app.close()
  }
})

test("端到端：造出来的题不会从单题接口泄露参考解法（G14）", async function () {
  const root = tempLearning()
  const app = createApp({
    dbPath: ":memory:",
    learningRoot: root,
    llmClient: makeFakeClient(),
    env: {},
  })
  const port = await app.listen(0)
  const base = "http://127.0.0.1:" + port
  try {
    const gen = await post(base, "/api/bank/llm-generate", {
      track: "interview",
      difficulty: "medium",
      sessionId: "g14",
    })
    const res = await fetch(base + "/api/problem/" + gen.body.problem.id)
    assert.equal(res.status, 200)
    const body = await res.json()
    assert.equal(body.solution, undefined, "单题接口不许返回参考解法")
    assert.equal(body.cases.total, 1)
    assert.ok(body.cases.sample.length <= 2, "样例用例最多给 2 个")
  } finally {
    await app.close()
  }
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
```

Expected: FAIL —— `llm-e2e.test.js` 报 `Cannot find module '../server/app.js'`（Task 5 没做）或者断言失败。

> 如果 Task 1–8 都按计划做完了，这一步**本来就该直接通过**——
> Task 9 是「验收」task，它的作用是把「应该成立」变成「已经验过」。

- [ ] **Step 3: 写 `tools/llm-check.js`**

创建 `projects/apps/algo-plan/tools/llm-check.js`：

```javascript
"use strict"
/**
 * llm-check.js —— LLM 配置离线自检（**不发任何网络请求，不改任何文件**）
 *
 * 用法：
 *   node tools/llm-check.js
 *
 * 打印三块：
 *   1. 当前 provider、模型名、地址、密钥来源（**只报变量名，绝不报密钥本身**）；
 *   2. 成本护栏的会话上限与每日上限；
 *   3. 五个提示词的纯函数自检：同样输入两次构造必须得到同样的指纹。
 *
 * 退出码：0 表示自检通过；1 表示提示词不是纯函数（构造结果不稳定）。
 * 「LLM 未启用」**不算失败**——那是合法的关闭状态，app 照常可用。
 */

const crypto = require("node:crypto")
const path = require("node:path")

const { loadDotEnv } = require("../server/main.js")
const { createLlmClient, keySourceOf } = require("../core/llm/client.js")
const { buildPrompt, KINDS } = require("../core/llm/prompts.js")
const { limits } = require("../core/llm/guard.js")

/** 只读的假 store：只为拿到配额上限，不写任何东西 */
function fakeStore() {
  return {
    getSetting: function (key, fallback) {
      return fallback === undefined ? null : fallback
    },
    setSetting: function () {},
  }
}

/** 提示词的指纹：同样的输入必须得到同样的指纹 */
function digest(prompt) {
  return crypto
    .createHash("sha1")
    .update(String(prompt.system) + "\n" + String(prompt.user))
    .digest("hex")
    .slice(0, 12)
}

/**
 * 跑一遍自检并打印报告。
 * @returns {boolean} 提示词自检通过返回 true
 */
function check() {
  loadDotEnv(path.join(__dirname, "..", ".env"))
  const client = createLlmClient({ env: process.env })
  const quota = limits(fakeStore())

  console.log("==== LLM 配置自检 ====")
  console.log("provider ：" + client.name)
  console.log("模型     ：" + client.model)
  console.log("地址     ：" + (client.baseUrl || "（未启用）"))
  console.log("密钥来源 ：" + keySourceOf(client.name, process.env))
  if (client.name === "null") {
    console.log("状态     ：未启用 —— " + client.reason)
    console.log("           app 的其余功能（排程、判题、复习、进度）照常可用。")
  }
  console.log("会话上限 ：" + quota.sessionLimit + " 次")
  console.log("每日上限 ：" + quota.dailyLimit + " 次")

  console.log("")
  console.log("==== 提示词自检（纯函数：同样输入两次构造必须一致） ====")
  const context = {
    title: "两数之和",
    difficulty: "easy",
    topics: ["哈希表"],
    statement: "给定数组与目标值，找出和为目标值的两个下标。",
    level: "思路",
    idea: "用哈希表存见过的数",
    track: "interview",
    cases: [{ input: "[2,7], 9", expect: "[0,1]" }],
    solution: "int main(){ return 0; }",
    solutionLang: "cpp",
  }
  let ok = true
  KINDS.forEach(function (kind) {
    const first = buildPrompt(kind, context)
    const second = buildPrompt(kind, context)
    const same = digest(first) === digest(second)
    if (!same) ok = false
    console.log(
      (same ? "[通过] " : "[失败] ")
      + kind + "：system " + String(first.system.length).padStart(4) + " 字"
      + " / user " + String(first.user.length).padStart(4) + " 字"
      + " / 指纹 " + digest(first)
    )
  })
  console.log("")
  console.log(ok ? "提示词自检通过。" : "提示词自检失败：同样的输入构造出了不同的提示词。")
  return ok
}

if (require.main === module) {
  process.exit(check() ? 0 : 1)
}

module.exports = { check: check }
```

- [ ] **Step 4: 跑测试与自检工具确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node tests/run-all.js
node --check tools/llm-check.js
node tools/llm-check.js
```

Expected:
- `node tests/run-all.js` 退出码 0，`llm-e2e.test.js` 套件 PASS；
- `node --check tools/llm-check.js` 无输出；
- `node tools/llm-check.js` 打印「LLM 配置自检」与「提示词自检」两段，
  末尾打印 `提示词自检通过。`，退出码 0。
  （本机没有配置密钥时，「状态」那段会显示「未启用 —— 没有配置 provider，也没有找到 ARK_API_KEY 或 ANTHROPIC_API_KEY」，
  **这是正常的**，退出码仍然是 0。）

- [ ] **Step 5: 改 `README.md`（三处加法）**

`README.md` 是 M1 建的文件，M6 只**加**内容。

**改动 A —— 环境变量表补上 LLM 的变量。**
把这一段：

```
| `ALGO_PLAN_LEARNING_ROOT` | learning 仓根目录。**不硬编码相对路径** | 无（未设＝纯本地模式） |
| `PORT` | 服务端口 | `5173` |
```

改成：

```
| `ALGO_PLAN_LEARNING_ROOT` | learning 仓根目录。**不硬编码相对路径** | 无（未设＝纯本地模式） |
| `PORT` | 服务端口 | `5173` |
| `ARK_API_KEY` | 火山方舟密钥（**只从环境变量读**） | 无 |
| `ARK_BASE_URL` | 方舟地址 | `https://ark.cn-beijing.volces.com/api/v3` |
| `ANTHROPIC_API_KEY` | Anthropic 密钥（**只从环境变量读**） | 无 |
| `ALGO_PLAN_LLM_ENABLED` | LLM 总开关，`0`/`false`/`off` = 关 | 未设＝按密钥自动判断 |
| `ALGO_PLAN_LLM_PROVIDER` | `ark` / `anthropic` / `null` | 未设＝按密钥推断 |
| `ALGO_PLAN_LLM_MODEL` | 模型名 | 按 provider 取默认 |
| `ALGO_PLAN_LLM_BASE_URL` | 覆盖地址 | 按 provider 取默认 |
| `ALGO_PLAN_LLM_SESSION_LIMIT` | 单次会话请求上限 | `20` |
| `ALGO_PLAN_LLM_DAILY_LIMIT` | 每日请求上限 | `100` |
```

**改动 B —— 接口表补上 M6 的接口。**
把这一段：

```
| GET | `/api/problem/:id` | 单题详情。**只回前 2 个样例用例 + 用例总数，不回参考解法** |
```

改成：

```
| GET | `/api/problem/:id` | 单题详情。**只回前 2 个样例用例 + 用例总数，不回参考解法** |
| POST | `/api/llm/explain` | 讲解。入参 `{problemId, level}`，回 `{text, model}` |
| POST | `/api/llm/hint` | 分级求助。入参 `{problemId, level}`，回 `{text, model}` |
| POST | `/api/llm/grade-idea` | 批改思路。入参 `{problemId, idea}`，回 `{verdict, comment, model}` |
| POST | `/api/bank/llm-generate` | 现造新题并**落盘**。入参 `{track, topics, difficulty}`，回 `{problem, model}` |
| POST | `/api/llm/fill` | 补全缺口并**写回**。入参 `{problemId}`，回 `{problem, model}` |
| GET | `/api/llm/settings` | LLM 开关、provider、模型名、密钥来源、配额 |
| PUT | `/api/llm/settings` | 保存 LLM 开关、provider、模型名、地址。**不接受密钥** |
```

**改动 C —— 在「## 测试」之前插入「## LLM 增强（M6）」一节。**
把这一段：

```
## 测试
```

改成：

````markdown
## LLM 增强（M6）

LLM 是**可选增强**：不配密钥也能用，app 的排程、判题、复习、进度一项不少。
关掉之后点「讲解」或「求助」，会得到一句明确的中文提示，而不是报错或空白。

### 五个场景

| 场景 | 接口 | 前端入口 |
|---|---|---|
| 讲解 | `POST /api/llm/explain` | 作答页「讲思路」/「直接给代码」 |
| 分级求助 | `POST /api/llm/hint` | 作答页「求助」四档：方向 → 思路 → 伪码 → 代码 |
| 批改思路 | `POST /api/llm/grade-idea` | 作答页的思路输入框 |
| 现造新题 | `POST /api/bank/llm-generate` | 题库页「来一题新的」 |
| 补全缺口 | `POST /api/llm/fill` | 题库页缺题面的题后面的「让 LLM 补全」 |

**不主动泄题**：讲解默认只到思路层；「直接给代码」是另一个独立按钮，点之前要确认一次。
求助四档**逐级解锁**——用完「方向」才放开「思路」，解锁进度存在 `sessionStorage`，关掉浏览器就没了。

**产出全部可追溯**：现造的新题**落盘进 `learning/bank/<track>/<id>.md`**
（`source: llm`，题号是 `llm-<内容哈希>`），不是一次性玩具；
每次讲解都记下 **model + 提示词摘要**到 `settings` 表。

### 配置密钥

密钥**只从环境变量读**，不写进代码、不写进 settings 表、不进 git。
在本目录下建一个 `.env`（`projects/.gitignore` 已经忽略它）：

```
ARK_API_KEY=你的方舟密钥
```

或者：

```
ANTHROPIC_API_KEY=你的 Anthropic 密钥
```

启动时会自动读 `.env`；也可以直接用环境变量：

```bash
ARK_API_KEY=xxx node server/main.js
```

### provider 与模型

| provider | 默认地址 | 默认模型 |
|---|---|---|
| `ark` | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-seed-1-6-251015` |
| `anthropic` | `https://api.anthropic.com` | `claude-opus-5` |

模型名要写**完整版本化 ID**：方舟写 `doubao-seed-1-6-251015` 这种，
直接写族名会返回 `404 InvalidEndpointOrModel.NotFound`。

设置页可以切 provider、改模型名、开关 LLM；**密钥不在设置页里填**——
设置页只显示「密钥来自哪个环境变量」。

### 成本护栏

- 单次会话最多 **20** 次请求；
- 每天最多 **100** 次请求；
- 超了**直接停**，提示「今天用完了」，不会继续烧钱；
- 计数落在 `settings` 表，键是 `llm.quota.session.*` 与 `llm.quota.daily.*`；
- 上限可以在设置页，或用 `ALGO_PLAN_LLM_SESSION_LIMIT` / `ALGO_PLAN_LLM_DAILY_LIMIT` 调。

### 离线自检

```bash
node tools/llm-check.js
```

只读不写：**不发任何网络请求**，只打印当前 provider、模型名、密钥来源、配额，
并对五个提示词做纯函数自检（同样输入两次构造必须一致）。

## 测试
````

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan/tests/llm-e2e.test.js apps/algo-plan/tools/llm-check.js apps/algo-plan/README.md
git commit -m "feat(algo-plan): 补上 M6 端到端验收、离线自检工具与 README

- llm-e2e.test.js：五个场景跑通、造题落盘、讲解留痕、配额拦截逐条验收
- tools/llm-check.js：只读不写的离线自检，不发任何网络请求
- README 补上 LLM 一节：五个场景、密钥配置、provider 与模型、成本护栏"
git push origin main
```

- [ ] **Step 7: 更新父仓的 submodule 指针**

```bash
cd /c/code/StillEvolving
git add projects
git commit -m "chore(submodule): 更新 projects 子模块指针（algo-plan M6 LLM）"
git push origin main
```

---

## M6 验收清单

全部满足才算 M6 完成：

| # | 验收项 | 怎么验 |
|---|---|---|
| 1 | 服务起得来 | `node server/main.js` 打印启动地址，并打印 LLM 是否就绪 |
| 2 | 测试全绿 | `node tests/run-all.js` 退出码 0；M6 新增 9 个套件（prompts / client / guard / service / api / off / web / web-bank / e2e）全 PASS |
| 3 | 零 npm 依赖 | `package.json` 无 `dependencies`；`node_modules/` 不存在 |
| 4 | **关掉 LLM 仍完整可用** | `llm-off.test.js`：删掉所有密钥后，首页、`/api/health`、`/api/bank`、`/api/problem/:id` 全 200；LLM 接口返回中文提示或 503，**没有 500**；题库一个文件都不多写 |
| 5 | **不主动泄题** | `llm-prompts.test.js`：非「代码」档的 system 里明确禁止给代码；`explain`/`hint` 的提示词里搜不到参考解法；只有显式传 `level="代码"` 才放开 |
| 6 | **产出可追溯** | `llm-e2e.test.js`：造出来的题落在 `learning/bank/<track>/<id>.md`，文件里有 `source: llm`；讲解记录里有 `model` 与 `prompt.digest` |
| 7 | 五场景接口形状对得上契约 | `llm-api.test.js`：`/api/llm/explain`、`/api/llm/hint` 回 `{text, model}`；`/api/llm/grade-idea` 回 `{verdict, comment, model}`；`/api/bank/llm-generate`、`/api/llm/fill` 回 `{problem, model}` |
| 8 | 成本护栏拦得住 | `llm-e2e.test.js`：单次会话第 21 次请求返回 429 并提示「本次会话」；每日超限提示「今天用完了」 |
| 9 | 提示词是纯函数 | `llm-prompts.test.js` 全程不联网；`node tools/llm-check.js` 五个提示词两次构造指纹一致 |
| 10 | 密钥不入库 | 全仓搜 `ARK_API_KEY=` / `ANTHROPIC_API_KEY=` 的**赋值**：只在 `projects/apps/algo-plan/.env`（被 gitignore）与文档示例里；`settings` 表里没有密钥；`GET /api/llm/settings` 响应里没有密钥 |
| 11 | 测试不联网 | 全部 LLM 测试注入假 `fetch` 或假 `complete`；`node tests/run-all.js` 在断网机器上照样全绿 |
| 12 | 不自动 commit | `git -C learning status` 里 M6 不会产生自动提交；造题与补全只写文件，不 commit、不 push |
| 13 | 前端接上了 | 作答页有「讲思路」/「直接给代码」与四档「求助」；题库页有「来一题新的」与缺题面标记；设置页有 LLM 开关、provider、模型名、密钥来源说明 |
| 14 | 不改 M1–M5 的冻结物 | `core/paths.js`、`core/bank/*`、`server/router.js`、`server/db.js`、`server/api.js` 的导出签名与三个接口的响应形状**一字未改**；M6 只在 `server/app.js` 上做了三处加法 |

---

## 执行提示

- 本计划只改 `projects/` 子模块（`projects/apps/algo-plan/`）。
  `learning/` 子模块只被**写入新题文件**（`learning/bank/<track>/<id>.md`），
  **绝不自动 commit、绝不 push**（G11）——写不写、什么时候提交，由用户决定。
- 本计划**不新增任何 npm 依赖、不引入任何构建步骤**。LLM 调用用 Node 内置的全局 `fetch`。
- **所有 LLM 测试都不联网**：客户端测试注入假 `fetch`，服务层测试注入假 `complete`。
  断网机器上 `node tests/run-all.js` 必须照样全绿。
- **密钥只从环境变量读**：`ARK_API_KEY` / `ANTHROPIC_API_KEY`。
  要在本机跑真 LLM，就在 `projects/apps/algo-plan/` 下建 `.env`（已被 `projects/.gitignore` 忽略），
  **不要**把密钥写进代码、settings 表或任何会被提交的文件。
- **Anthropic 客户端不发送 `temperature`**：`claude-opus-5` 与 `claude-sonnet-5` 已移除采样参数，
  传了会返回 400。改 `core/llm/client.js` 时别把这个「不转发」改回去。
- **方舟的模型名必须写完整版本化 ID**（如 `doubao-seed-1-6-251015`）或接入点 ID（`ep-xxx`），
  直接写族名会返回 `404 InvalidEndpointOrModel.NotFound`。
- **四档求助的「逐级解锁」是前端的规则**（状态在 `sessionStorage`），
  后端只校验档位是不是四档之一。后端不再另存一份解锁状态——**两个真相源反而会打架**。
  「不主动泄题」这条硬约束由**提示词层**保证：非「代码」档的 system 里明确禁止给代码，
  且 `explain`/`hint` 的上下文里根本没有参考解法。这两处都有测试钉住。
- **M6 只在 `server/app.js` 上做了三处加法**（三处 require、一段路由合并、返回值多一个 `llm`）。
  M1 冻结的 `buildRoutes` 签名与三个接口的响应形状一个字都没动。
  如果 M2–M5 已经改过 `server/app.js` 里的这几段，按同样的语义合并即可。
- **M6 的前端全部在 `web/llm.js` 里，`web/app.js` 一个字都没改**——
  避免和 M2–M5 的页面代码抢同一个文件。`web/llm.js` 自己挂载到 `main#view` 顶部，
  并用 `MutationObserver` 在 app.js 重渲染后重新挂载。
- 计划写完了，不要在没跑通测试前合并。










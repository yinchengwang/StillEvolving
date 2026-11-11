# 算法能力提升计划 App —— M3 判题实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M3 里程碑——一个能真的判题的本地执行器：C++/Python 代码提交进来，真实编译、真实跑用例、真实比对，产出五类 verdict（`pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error`），并把结果面板显示在页面上。

**Architecture:** 分两层。`core/judge-spec/` 是**纯函数层**（用例归一化、输出比对规则），可脱离 IO 单测；`judge/` 是**执行层**（临时目录、工具链探测、带超时杀进程树的子进程、编排器），真跑 `g++` 与 Python。HTTP 侧只在 M1 已有的三个接口上**加**一个 `POST /api/attempt`，响应形状照跨计划接口契约 §2 冻结的八字段。

**Tech Stack:** Node.js ≥ 24（内置 `node:child_process` / `node:fs` / `node:os` / `node:test`）、原生 JS + CSS、零 npm 依赖、零构建。本机编译器 `g++`（mingw64 14.2.0），本机 Python 走 `python` / `py -3` 探测。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划只覆盖其中 §5 判题契约、§7.2 的 `POST /api/attempt`、§9 测试策略里的「判题器」一行、§10 分期里的 **M3**）

**接口契约:** `docs/superpowers/plans/2026-11-11-algo-plan-app-接口契约.md`（本计划严格遵守其 §0 / §2 / §6 / §7）

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）

---

## Global Constraints

M1 的 **G1–G16 全部继续生效**（零 npm 依赖、零构建、Node ≥ 24、中文注释与提交、提交即推送、产物只在 `projects/apps/algo-plan/`、learning 仓路径不硬编码、稳定题目 ID、测试入口 `node tests/run-all.js`、中文输出、不自动 commit、SQLite 类型约束等，逐条见 M1 计划的 Global Constraints 表）。接口契约 §6 的 **G17–G22** 五份计划共用，M3 同样遵守。下面是 M3 自己追加的条目。

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测，第一个能 `--version` 的胜出；探测结果可缓存进 `settings`（键 `judge.python.cmd`） |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序，用户自己写 `main()`；不注入 Solution 包装、不自动生成 main |
| G22 | **零第三方图表** | 不引任何第三方库（M3 不画图，但同样不许引） |
| G23 | **编译命令固定** | `g++ -std=c++17 -O2 main.cpp -o main`。**不加** `-Werror`、**不加** `-Wall`——用户的题解不该因 warning 判错 |
| G24 | **单用例超时** | 默认 **2000ms**（`settings` 键 `judge.timeout_ms` 可改）；超时必须杀**整棵进程树**：Windows 用 `taskkill /T /F`，POSIX 用进程组 kill |
| G25 | **临时目录** | 每题一个独立临时目录；编译产物与临时目录**判完即删**，不留在工作区 |
| G26 | **安全边界** | 判题**不是安全沙箱**：它防的是「跑飞、死循环、爆内存、编译出一堆垃圾」，**不防恶意代码**。用户代码以当前用户权限在临时目录里跑 |
| G27 | **verdict 字符串** | 只有五个：`pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error`。与接口契约 §2 逐字一致，不许新增、不许改写 |
| G28 | **Python 编码** | 跑 Python 时子进程环境**必须**带 `PYTHONIOENCODING=utf-8`。本机是中文 Windows，Python 默认按 GBK 读写管道，不加这一条中文输入输出全是乱码（实测见下） |
| G29 | **spawn 可执行文件用绝对路径** | `spawn` 的命令名是相对**父进程** cwd 解析的，`cwd` 选项只影响子进程自己的工作目录。跑编译产物必须用 `path.join(dir, "main.exe")` 这种绝对路径，用相对名会 ENOENT（实测见下） |

---

## M3 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | ✅ 已由 M1 计划交付 |
| M2 题库 | 复活三个死脚本 + 存量题解导入 | ❌ 另出计划 |
| **M3 判题** | **C++/Python 判题器 + verdict + 结果面板** | ✅ **本计划** |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | ❌ 另出计划 |
| M5 诊断 | 掌握度模型 + 诊断页 | ❌ 另出计划 |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | ❌ 另出计划 |

**M3 做完的验收线：** 浏览器里提交一段 C++ 代码，页面上出现「通过 / 答案错误 / 超时 / 编译失败 / 运行时错误」五选一的结果面板，失败时能看到期望 vs 实际、编译错误原文与错误行号；`node tests/run-all.js` 全绿。

**M3 明确不碰：** 复习卡片、SM-2、轮次、掌握度、LLM、题库导入（M2）。本计划只往 `attempts` 表写流水，不碰 `review_cards` 与 `topics`（那是 M4/M5 的事）。

---

## 判题契约（硬约束，G18）

**提交给判题器的必须是「stdin 进、stdout 出」的完整程序，用户自己写 `main()`。**

- 判题器**不注入**任何 Solution 包装，**不自动生成** `main()`，**不猜测**方法名。
- 判题器**不管**输入的格式（是「n 个数一行」还是「第一行 n 第二行数组」都随题面），只负责把用例的 `input` 原样喂进 stdin，把 stdout 原样取出来比对。
- 提交 `class Solution { ... }` 这种没有 `main()` 的代码，**编译必然失败**，这是有意的：它把「写完整程序」这件事逼出来，也避免判题器去猜「该调哪个方法」。

**正例（C++）——这就是一份合法的提交物：**

```cpp
#include <iostream>
#include <vector>
using namespace std;

int main() {
    int n;
    if (!(cin >> n)) return 0;
    vector<int> nums(n);
    for (int i = 0; i < n; ++i) cin >> nums[i];
    int target;
    cin >> target;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (nums[i] + nums[j] == target) {
                cout << i << " " << j << endl;
                return 0;
            }
        }
    }
    cout << "-1 -1" << endl;
    return 0;
}
```

**正例（Python）——同样自己写入口（读 stdin 的是 `input()`）：**

```python
s = input()
print(s[::-1])
```

**反例（会被判成 `compile_error`，且面板上会明确告诉你原因）：**

```cpp
class Solution {
public:
    int twoSum(vector<int>& nums, int target) { return 0; }
};
```

实测（mingw g++ 14.2.0）这种代码链接期报 `undefined reference to 'WinMain'` / `undefined reference to 'main'`，
判题器会把它翻译成中文面板文案：「没有 main 函数：判题契约要求提交完整的 stdin→stdout 程序，用户自己写 main()」。

---

## 安全边界：这不是沙箱（G26）

**必须如实告知使用者：判题不是安全沙箱。**

| 它防什么 | 它不防什么 |
|---|---|
| 程序跑飞（往终端乱喷、写到临时目录外） | 恶意代码：删文件、改注册表、联网、挖矿、读别人的密钥 |
| 死循环（超时杀整棵进程树） | 主动 fork 出 daemon 躲过超时 |
| 爆内存（靠超时兜底，Windows 上做不了精确内存限制） | 占满磁盘 |
| 编译出一堆垃圾（编译产物在临时目录里，判完即删） | 挖矿式的 CPU 占用（只能靠超时截断） |

用户代码**以当前用户权限**在系统临时目录里跑。要真隔离得上 Docker 或受限账号——那是另一个项目，不塞进这里（设计文档 §5.4、§11）。

---

## 实地勘察结论（本机实测，2026-11-11）

写计划前在本机真跑了一遍，下面是**原始输出**，不是推断：

### 1. 编译器

```console
$ g++ --version
g++.exe (MinGW-W64 x86_64-msvcrt-posix-seh, built by Brecht Sanders, r3) 14.2.0
Copyright (C) 2024 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

$ where g++
C:\mingw64\bin\g++.exe
```

- `-std=c++17` **可用**：实测 `g++ -std=c++17 -O2 t.cpp -o t` 编译通过、运行输出正确。
- **mingw 会自动补 `.exe`**：`g++ ... -o m` 产出的文件叫 `m.exe`（不是 `m`）。Node 的 `spawn` 不像 bash 那样自动补后缀，所以判题器必须自己算出可执行文件路径（Task 4）。
- 编译错误的格式（实测）：

  ```console
  $ g++ -std=c++17 -O2 bad.cpp -o bad
  bad.cpp:4:5: error: 'undefined_function_call' was not declared in this scope
      4 |     undefined_function_call();
        |     ^~~~~~~~~~~~~~~~~~~~~~~
  ```

  即 `<文件>:<行>:<列>: error: <原因>`。行号、列号都要能从这段文本里解析出来（Task 4）。

### 2. Python 解释器——`python3` 是空占位符

```console
$ python3 --version
（没有任何输出）
$ echo $?
49

$ python --version
Python 3.11.15

$ py -3 --version
Python 3.12.3

$ which python3
/c/Users/yinch/AppData/Local/Microsoft/WindowsApps/python3
$ file $(which python3)
/c/Users/yinch/AppData/Local/Microsoft/WindowsApps/python3: symbolic link to
  /c/Program Files/WindowsApps/.../AppInstallerPythonRedirector.exe
```

- `python3` 指向 **Microsoft Store 的 App Installer 重定向器**：能启动、能退出，但**不打印版本号**，退出码 **49**。
- 真身是 `python`（3.11.15）与 `py -3`（3.12.3）。
- 所以判题器**必须**按 `python3` → `python` → `py -3` 依次探测，且判据是「`--version` 退出码为 0 **且** 有输出」（G17）。
> **与 spec §5.1 的有意偏离**：spec 里写的是「Python：`python3`」，本机 `python3` 是 Store 的空占位符，
> 照抄会让**每一次 Python 判题都失败**。所以按 G17 改成「依次探测，第一个能 `--version` 的胜出」，
> 语义等价（还是那条 Python），只是不写死命令名。

- 实测：往 `python` 管道里灌中文，`PYTHONIOENCODING=utf-8` 与不设的差别是**实打实的乱码**：

  ```console
  $ printf '练字\n' | python pycn.py | xxd
  00000000: ad97 83e5 e7bb 0d0a          # GBK，Node 按 UTF-8 解就是乱码
  $ printf '练字\n' | PYTHONIOENCODING=utf-8 python pycn.py | xxd
  00000000: e5ad 97e7 bb83 0d0a          # 正确的 UTF-8
  ```

  → **G28：跑 Python 必须设 `PYTHONIOENCODING=utf-8`。**

### 3. 进程与退出码

```console
$ where taskkill
C:\Windows\System32\taskkill.exe
```

- C++ 未捕获异常（`throw`）：Node 观察到 `code = 3`、`signal = null` → 判 `runtime_error` 成立。
- Python 未捕获异常：退出码 **1**，stderr 含 `ValueError: boom` → 判 `runtime_error` 成立。
- C++ 程序 `cout` 出来的是 `\r\n`（Windows 文本模式）→ 比对规则里的「统一换行 + 去行尾空白」不是可选项，是**必须**。
- **`spawn` 的可执行文件必须给绝对路径**（实测）：

  ```console
  $ node -e "spawn('main.exe', [], {cwd: '/tmp/xxx'})"   # 相对名
  → spawn main.exe ENOENT
  $ node -e "spawn('/tmp/xxx/main.exe', [], {cwd: '/tmp/xxx'})"   # 绝对名
  → 正常跑起来，退出码 3
  ```

  命令名是相对**父进程** cwd 解析的，`cwd` 选项只改子进程自己的工作目录 → **G29**。

### 4. 存量题解的真实代码形态

`learning/code-solutions/` 与 `learning/algo-c/` 下**没有一份代码能直接提交判题**：

| 文件 | 形态 | 有 `main()` 吗 | 能独立编译吗 |
|---|---|---|---|
| `learning/code-solutions/c/src/cpp/leetcode_1_100.cpp` | `LeetCode_Solution::twoSumEnum(...)` 成员函数形式，`#include "leetcode/leetcode_cpp.h"` | **没有** | **不能**——那个头文件在仓里不存在 |
| `learning/code-solutions/c/src/c/leetcode_1_100.c` | 自由函数形式（`merge` / `sortColors`），`#include "common.h"` | **没有** | **不能**——`common.h` 不存在 |
| `learning/algo-c/problems/leetcode_326/leetcode_326.cpp` | `class Solution { public: ... }` | **没有** | 能编译，但链接期缺 `main` |
| `learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp` | `class Solution { public: ... }` | **没有** | 同上 |
| `learning/code-solutions/interview/interview_17_10/interview_17_10.cpp` | `class Solution { ... }` + 一个 `main()` | **有**，但 `main()` 里**硬编码了输入**，不是 stdin 驱动 | 能编译，但不能当判题提交物 |

全仓 `grep -rn "int main" learning/code-solutions/` 只命中 2 个文件（`interview_17_10` 的 `.c` 与 `.cpp`），其余全是「没有入口」或「入口不读 stdin」。

**结论（写进 G18 的依据）：** 存量题解是「方法库」不是「程序」。判题器要能自动包一层 `main()`，就得知道方法名、参数形状、期望输出格式——做不到自动生成。所以契约只能是「用户自己写 `main()`」，并且这条要在界面上明说。

### 5. 本计划的代码已在本机实跑验证过

写这份计划时，计划里的**每一段代码都从这份文档里抠出来在本机跑过**（Node v24.17.0 / mingw64 g++ 14.2.0 / Python 3.11.15），
实测结果如下。实现时如果行为对不上，先怀疑环境，再怀疑代码。

| 套件 | 实跑结果 |
|---|---|
| `tests/judge-spec.test.js` | 16 / 16 通过 |
| `tests/sandbox.test.js` | 13 / 13 通过（含「超时后整棵进程树都被杀掉（孙进程也停）」） |
| `tests/judge-fixtures.test.js` | 8 / 8 通过（三类负例都真的坏） |
| `tests/runner.test.js` | 16 / 16 通过（五类 verdict 全部真跑出来） |
| `tests/web-panel.test.js` | 7 / 7 通过 |

实跑中抓到并已修掉的四个问题（**别再踩**）：

1. `detectCompiler` / `detectPython` 原本 `await` 了一个异步的 `runCommand` 却没 `await`，
   结果永远拿不到退出码 → 改成同步的 `spawnSync`（契约里这两个函数本来就是非 Promise 的）。
2. `parseCompilerError` 的正则有 4 个捕获组，代码却按 3 个取 → 错误行号变成 `NaN`。
3. `cpp-runtime-error.cpp` fixture 少写了 `using namespace std;` → 它编不过，压根到不了运行时异常那一步。
4. `spawn` 的可执行文件用相对名（`main.exe`）会 ENOENT → 必须给绝对路径（G29）。

五类 verdict 的实跑输出（截自真实运行）：

```
pass          → 通过：全部 3 个用例通过
wrong_answer  → 答案错误：第 1 个用例不通过：输出与期望不一致
               （failedCase = {"index":1,"input":"4 2 7 11 15 9","expected":"0 1","actual":"0 0\r\n"}）
timeout       → 超时：第 1 个用例超时：运行超过 800ms 后被强制结束
compile_error → 编译失败：第 4 行：'undefined_function_call' was not declared in this scope
runtime_error → 运行时错误：第 1 个用例运行失败（退出码 3）：terminate called after throwing an instance of 'std::runtime_error'
缺 main       → 编译失败：没有 main 函数：判题契约要求提交完整的 stdin→stdout 程序，用户自己写 main()
```

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── core/
│   └── judge-spec/               纯函数层：可脱离 IO 单测
│       ├── cases.js              用例归一化：index 从 1 开始、跳过空行、容差归一化
│       └── compare.js            输出比对：去首尾空白 + 忽略末尾空行 + 数值容差
├── judge/                        执行层：真编译、真执行
│   ├── sandbox.js                临时目录、工具链探测、带超时杀整棵进程树的子进程执行
│   └── runner.js                 编排：写文件 → 编译 → 逐用例执行 → 比对 → verdict
├── server/
│   └── api.js                    （改）M1 三个接口 + 新增 POST /api/attempt
├── web/
│   ├── app.js                    （改）加「作答」页与判题结果面板
│   └── style.css                 （改）结果面板样式
├── fixtures/
│   └── judge/
│       ├── manifest.js           fixture 路径表
│       ├── problems/             题面 + 用例 + 参考解法（题库 markdown 格式）
│       │   ├── interview/self-00010.md
│       │   └── fundamentals/self-00011.md
│       └── code/                 「用户的提交物」：正例 + 三类负例
│           ├── cpp-ok.cpp
│           ├── cpp-wrong-answer.cpp
│           ├── cpp-compile-error.cpp
│           ├── cpp-timeout.cpp
│           ├── cpp-runtime-error.cpp
│           ├── python-ok.py
│           ├── python-wrong-answer.py
│           └── python-runtime-error.py
└── tests/
    ├── run-all.js                一键跑全部（M1 已建，不改）
    ├── judge-spec.test.js        （新）用例归一化 + 输出比对
    ├── sandbox.test.js           （新）探测、临时目录、喂 stdin、超时杀进程树
    ├── judge-fixtures.test.js    （新）fixture 自检：正例对、三类负例确实坏
    ├── runner.test.js            （新）五类 verdict 端到端
    ├── attempt.test.js           （新）POST /api/attempt
    └── web-panel.test.js         （新）结果面板数据整理（纯函数）
```

**归属**：本计划只改 `projects/` 子模块。`learning/` 子模块只被**读**（Task 3 有一处可选的一次性导入动作，由用户自己决定是否提交；app 与本计划都不碰 learning 的 git 历史）。

---

## Task 1: 判题契约的纯函数层——用例归一化与输出比对

**Files:**
- Create: `projects/apps/algo-plan/core/judge-spec/cases.js`
- Create: `projects/apps/algo-plan/core/judge-spec/compare.js`
- Create: `projects/apps/algo-plan/tests/judge-spec.test.js`

**Interfaces:**
- Consumes: 无（纯函数，无 IO，不依赖 M1 的任何模块）
- Produces:
  - `core/judge-spec/cases.js` 导出
    - `normalizeCases(cases) -> [{index: number, expect: string, input: string, tol: number|null}]`，**index 从 1 开始**
    - `normalizeTol(value) -> number|null`
  - `core/judge-spec/compare.js` 导出
    - `compareOutput(actual, expected, tol) -> {equal: boolean, reason: string}`
    - `normalizeText(text) -> string`（归一化文本：统一换行符 → 去每行行尾空白 → 去首尾空白）
    - `toNumber(text) -> number|null`（严格数值解析；空串返回 `null` 而不是 `0`）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/judge-spec.test.js`：

```javascript
"use strict"
/**
 * judge-spec.test.js —— 判题契约的纯函数层：用例归一化 + 输出比对
 */

const test = require("node:test")
const assert = require("node:assert")

const cases = require("../core/judge-spec/cases.js")
const compare = require("../core/judge-spec/compare.js")

test("normalizeCases 的 index 从 1 开始", function () {
  const out = cases.normalizeCases([
    { input: "1 2", expect: "3", tol: null },
    { input: "4 5", expect: "9", tol: null },
  ])
  assert.strictEqual(out.length, 2)
  assert.deepStrictEqual(out.map(function (c) { return c.index }), [1, 2])
  assert.deepStrictEqual(Object.keys(out[0]).sort(), ["expect", "index", "input", "tol"])
})

test("normalizeCases 跳过输入与期望都空的行", function () {
  const out = cases.normalizeCases([
    { input: "", expect: "", tol: null },
    { input: "1", expect: "1", tol: null },
    { input: "  ", expect: "", tol: null },
  ])
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].index, 1, "跳过的空行不占号")
})

test("normalizeCases 去掉输入与期望的首尾空白", function () {
  const out = cases.normalizeCases([{ input: "  3 2 4 6  ", expect: "  1 2 ", tol: null }])
  assert.strictEqual(out[0].input, "3 2 4 6")
  assert.strictEqual(out[0].expect, "1 2")
})

test("normalizeCases 归一化容差", function () {
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: "1e-6" }])[0].tol, 1e-6)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: 0.5 }])[0].tol, 0.5)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: null }])[0].tol, null)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b" }])[0].tol, null)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: "" }])[0].tol, null)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: -1 }])[0].tol, null)
  assert.strictEqual(cases.normalizeCases([{ input: "a", expect: "b", tol: "abc" }])[0].tol, null)
})

test("normalizeCases 容忍非数组输入", function () {
  assert.deepStrictEqual(cases.normalizeCases(null), [])
  assert.deepStrictEqual(cases.normalizeCases(undefined), [])
  assert.deepStrictEqual(cases.normalizeCases("不是数组"), [])
})

test("compareOutput 完全一致时相等", function () {
  const r = compare.compareOutput("0 1", "0 1", null)
  assert.strictEqual(r.equal, true)
  assert.ok(r.reason.length > 0, "必须给出中文说明")
})

test("compareOutput 忽略行尾空白与末尾空行", function () {
  assert.strictEqual(compare.compareOutput("0 1   \n\n\n", "0 1", null).equal, true)
  assert.strictEqual(compare.compareOutput("0 1\n", "0 1\n\n", null).equal, true)
  assert.strictEqual(compare.compareOutput("0 1", "0 1\n", null).equal, true)
})

test("compareOutput 统一 CRLF 与 LF", function () {
  assert.strictEqual(compare.compareOutput("0 1\r\n", "0 1\n", null).equal, true)
  assert.strictEqual(compare.compareOutput("a\r\nb\r\n", "a\nb", null).equal, true)
})

test("compareOutput 去掉首尾空白", function () {
  assert.strictEqual(compare.compareOutput("   0 1   ", "0 1", null).equal, true)
  assert.strictEqual(compare.compareOutput("\n\n0 1\n\n", "0 1", null).equal, true)
})

test("compareOutput 内容不同则不等", function () {
  const r = compare.compareOutput("0 2", "0 1", null)
  assert.strictEqual(r.equal, false)
  assert.ok(r.reason.indexOf("不一致") !== -1, r.reason)
})

test("compareOutput 顺序不同则不等", function () {
  assert.strictEqual(compare.compareOutput("1 0", "0 1", null).equal, false)
  assert.strictEqual(compare.compareOutput("a\nb", "b\na", null).equal, false)
})

test("compareOutput 容差之内相等", function () {
  const r = compare.compareOutput("3.0000000001", "3", 1e-6)
  assert.strictEqual(r.equal, true)
  assert.ok(r.reason.indexOf("容差") !== -1, r.reason)
})

test("compareOutput 超出容差则不等", function () {
  const r = compare.compareOutput("3.1", "3", 1e-6)
  assert.strictEqual(r.equal, false)
  assert.ok(r.reason.indexOf("容差") !== -1, r.reason)
})

test("compareOutput 期望是数值但实际不是数值则不等", function () {
  const r = compare.compareOutput("abc", "3", 1e-6)
  assert.strictEqual(r.equal, false)
  assert.ok(r.reason.indexOf("不是数值") !== -1, r.reason)
})

test("compareOutput 期望不是数值时退化成精确匹配", function () {
  assert.strictEqual(compare.compareOutput("abc", "abc", 1e-6).equal, true)
  assert.strictEqual(compare.compareOutput("abc", "abd", 1e-6).equal, false)
})

test("toNumber 不把空串当数字 0", function () {
  assert.strictEqual(compare.toNumber(""), null)
  assert.strictEqual(compare.toNumber("   "), null)
  assert.strictEqual(compare.toNumber("abc"), null)
  assert.strictEqual(compare.toNumber("3"), 3)
  assert.strictEqual(compare.toNumber("-2.5"), -2.5)
  assert.strictEqual(compare.toNumber("1e-6"), 1e-6)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/judge-spec/cases.js'`

- [ ] **Step 3: 写 core/judge-spec/cases.js**

Create `projects/apps/algo-plan/core/judge-spec/cases.js`：

```javascript
"use strict"
/**
 * cases.js —— 判题用例的归一化
 *
 * 纯函数，无 IO。题库里的用例长这样（core/bank/parse.js 解析出来的）：
 *   [{input: "[2,7,11,15], 9", expect: "[0,1]", tol: null}]
 * 归一化之后补上从 1 开始的 index——面板上「第几个用例挂的」用的就是它。
 */

/**
 * 归一化容差：非有限数、负数、空串一律当作「没有容差」。
 * @param {*} value
 * @returns {number|null}
 */
function normalizeTol(value) {
  if (value === null || value === undefined || value === "") return null
  const tol = Number(value)
  if (!Number.isFinite(tol) || tol < 0) return null
  return tol
}

/**
 * 归一化一组用例。
 * 规则：
 *   - 非对象条目跳过
 *   - input / expect 转字符串并去首尾空白
 *   - input 与 expect 都空的行是表格里的空行，跳过且不占号
 *   - tol 归一化成 number 或 null
 *   - index 从 1 开始连续编号
 * @param {Array<{input?: string, expect?: string, tol?: number|string|null}>} cases
 * @returns {Array<{index: number, expect: string, input: string, tol: number|null}>}
 */
function normalizeCases(cases) {
  const list = Array.isArray(cases) ? cases : []
  const out = []
  list.forEach(function (raw) {
    if (!raw || typeof raw !== "object") return
    const input = raw.input === null || raw.input === undefined ? "" : String(raw.input).trim()
    const expect = raw.expect === null || raw.expect === undefined ? "" : String(raw.expect).trim()
    if (input === "" && expect === "") return
    out.push({
      index: out.length + 1,
      expect: expect,
      input: input,
      tol: normalizeTol(raw.tol),
    })
  })
  return out
}

module.exports = { normalizeCases: normalizeCases, normalizeTol: normalizeTol }
```

- [ ] **Step 4: 写 core/judge-spec/compare.js**

Create `projects/apps/algo-plan/core/judge-spec/compare.js`：

```javascript
"use strict"
/**
 * compare.js —— 输出比对规则
 *
 * 纯函数，无 IO。规则照设计文档 §5.3：
 *   默认：去首尾空白 + 忽略末尾空行后精确匹配
 *   tol != null：数值容差比较
 *
 * 「归一化」的确切定义（面板上要能说清楚，所以写死在这里）：
 *   1. \r\n 与 \r 统一成 \n
 *   2. 每行去掉行尾的空格与制表符
 *   3. 整个文本去掉首尾空白（等价于 trim）——末尾的空行因此被忽略
 */

/**
 * 归一化文本。
 * @param {string} text
 * @returns {string}
 */
function normalizeText(text) {
  if (text === null || text === undefined) return ""
  return String(text)
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map(function (line) {
      return line.replace(/[ \t\r]+$/, "")
    })
    .join("\n")
    .trim()
}

/**
 * 严格数值解析：不是合法数字就返回 null。
 * 特意不用 Number()——Number("") 是 0，会把「程序什么都没输出」误当成数字 0。
 * @param {string} text
 * @returns {number|null}
 */
function toNumber(text) {
  const s = String(text === null || text === undefined ? "" : text).trim()
  if (s === "") return null
  if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) return null
  const value = Number(s)
  return Number.isFinite(value) ? value : null
}

/**
 * 比对实际输出与期望输出。
 * @param {string} actual 程序 stdout
 * @param {string} expected 用例里的期望输出
 * @param {number|string|null|undefined} tol 数值容差；null/undefined 表示精确匹配
 * @returns {{equal: boolean, reason: string}} reason 是中文说明
 */
function compareOutput(actual, expected, tol) {
  const a = normalizeText(actual)
  const e = normalizeText(expected)

  const hasTol = tol !== null && tol !== undefined && tol !== ""
  if (hasTol) {
    const av = toNumber(a)
    const ev = toNumber(e)
    if (av !== null && ev !== null) {
      const diff = Math.abs(av - ev)
      if (diff <= Number(tol)) {
        return { equal: true, reason: "数值偏差 " + diff + "，在容差 " + tol + " 之内" }
      }
      return { equal: false, reason: "数值偏差 " + diff + "，超过容差 " + tol }
    }
    if (ev !== null) {
      return { equal: false, reason: "期望是数值，但实际输出不是数值，无法按容差比较" }
    }
  }

  if (a === e) {
    return { equal: true, reason: "输出一致（已忽略首尾空白与末尾空行）" }
  }
  return { equal: false, reason: "输出与期望不一致" }
}

module.exports = {
  compareOutput: compareOutput,
  normalizeText: normalizeText,
  toNumber: toNumber,
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `9 / 9 套件通过`，退出码 0

- [ ] **Step 6: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加判题契约的纯函数层

- core/judge-spec/cases.js：用例归一化，index 从 1 开始，空行跳过且不占号
- 容差归一化：非有限数、负数、空串一律当作没有容差
- core/judge-spec/compare.js：统一换行符、去行尾空白、去首尾空白后精确匹配
- tol 存在时按数值容差比较，期望是数值而实际不是数值时明确报不等
- 数值解析不用 Number()，避免把空输出误当成数字 0
- 测试：归一化 6 条断言、比对 12 条断言"
git push origin main
```

---

## Task 2: 判题沙箱——临时目录、工具链探测、超时杀整棵进程树

**Files:**
- Create: `projects/apps/algo-plan/judge/sandbox.js`
- Create: `projects/apps/algo-plan/tests/sandbox.test.js`

**Interfaces:**
- Consumes: 无（只用 Node 内置模块）
- Produces:
  - `judge/sandbox.js` 导出
    - `detectCompiler() -> {cmd: "g++", version: string} | null`（**同步**，用 `spawnSync`）
    - `detectPython(override?) -> {cmd: string, args: string[], version: string} | null`（**同步**，用 `spawnSync`）
      （`override` 形如 `"py -3"`；给定时**先**试它，失败再回落到标准顺序）
    - `createSandbox() -> {dir: string, cleanup(): void}`
    - `runCommand(cmd, args, {cwd?, input?, timeoutMs?, env?}) -> Promise<{code: number|null, stdout: string, stderr: string, durationMs: number, timedOut: boolean, signal: string|null}>`
    - `killTree(child) -> void`
    - `resolveToolchain(options?) -> {compiler: object|null, python: object|null}`（**同步**）
    - `resetDetectionCache() -> void`
    - 常量 `DEFAULT_TIMEOUT_MS = 2000`、`PYTHON_CANDIDATES`
  - **探测为什么用 `spawnSync`**：接口契约把 `detectCompiler` / `detectPython` 定成**非 Promise** 的同步返回，
    所以这两个函数不能 `await runCommand`（`runCommand` 是异步的），必须走同步的 `spawnSync`。
    探测只是跑一次 `--version`，同步完全够用，而且省掉一整层 await 传染。
  - **相对接口契约 §2 的增补**（不改动契约里已有的字段名与含义，只做加法）：
    - `runCommand` 的返回值**追加** `signal` 字段（POSIX 上被信号杀死时 `code` 为 `null`、`signal` 是信号名）
    - `runCommand` 的选项**追加** `env`（子进程环境变量，Python 判题要用它带 `PYTHONIOENCODING=utf-8`）
    - `detectPython` **追加**可选参数 `override`（用户在设置里指定的解释器，如 `"py -3"`）；
      不传时的行为与契约完全一致（`python3` → `python` → `py -3` 依次探测）
    - **新增** `resolveToolchain(options?)`：一次性拿到 `{compiler, python}`，
      API 层用它把 `settings` 里的解释器缓存喂给判题器
    - **新增** `parseCandidate(text)`（把 `"py -3"` 拆成 `{cmd, args}`）与
      `resetDetectionCache()`（测试用）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/sandbox.test.js`：

```javascript
"use strict"
/**
 * sandbox.test.js —— 判题沙箱：工具链探测、临时目录、喂 stdin、超时杀整棵进程树
 *
 * 这个套件**真的**会编译、真的会跑子进程、真的会在 Windows 上 taskkill 进程树。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const sandbox = require("../judge/sandbox.js")

test("detectCompiler 找到本机的 g++ 并给出版本", function () {
  const compiler = sandbox.detectCompiler()
  assert.ok(compiler, "本机应能找到 g++")
  assert.strictEqual(compiler.cmd, "g++")
  assert.ok(compiler.version.indexOf("g++") !== -1, compiler.version)
})

test("detectPython 选到的是**真的能跑**的解释器（不是 Store 占位符）", async function () {
  const python = sandbox.detectPython()
  assert.ok(python, "本机应能找到可用的 Python")
  assert.ok(
    ["python3", "python", "py"].indexOf(python.cmd) !== -1,
    "探测顺序只能是 python3 / python / py，实际是 " + python.cmd
  )
  const run = await sandbox.runCommand(python.cmd, python.args.concat(["-c", "print(6 * 7)"]), {})
  assert.strictEqual(run.code, 0)
  assert.strictEqual(run.stdout.trim(), "42", "选中的解释器必须能真的执行代码")
})

test("detectPython 的版本号形如 Python 3.x", function () {
  const python = sandbox.detectPython()
  assert.ok(/^Python 3\./.test(python.version), python.version)
})

test("detectPython 支持用户指定解释器 py -3", function () {
  const python = sandbox.detectPython("py -3")
  assert.strictEqual(python.cmd, "py")
  assert.deepStrictEqual(python.args, ["-3"])
})

test("detectPython 指定的解释器不能用时回落到标准顺序", function () {
  const python = sandbox.detectPython("根本不存在的解释器-xyz")
  assert.ok(python, "应回落到 python3 / python / py -3")
  assert.ok(["python3", "python", "py"].indexOf(python.cmd) !== -1, python.cmd)
})

test("createSandbox 建出临时目录，cleanup 后目录消失", function () {
  const box = sandbox.createSandbox()
  assert.ok(fs.existsSync(box.dir), "临时目录应存在")
  assert.ok(box.dir.indexOf("algo-plan-judge-") !== -1, box.dir)
  box.cleanup()
  assert.strictEqual(fs.existsSync(box.dir), false, "cleanup 后目录应被删掉")
})

test("cleanup 调两次不会报错", function () {
  const box = sandbox.createSandbox()
  box.cleanup()
  box.cleanup()
})

test("runCommand 捕获 stdout 与退出码", async function () {
  const run = await sandbox.runCommand(process.execPath, ["-e", "console.log('hello')"], {})
  assert.strictEqual(run.code, 0)
  assert.strictEqual(run.stdout.trim(), "hello")
  assert.strictEqual(run.timedOut, false)
  assert.ok(run.durationMs >= 0)
})

test("runCommand 把 input 喂进 stdin", async function () {
  const run = await sandbox.runCommand(
    process.execPath,
    ["-e", "process.stdin.on('data', function (d) { process.stdout.write('got:' + d) })"],
    { input: "abc" }
  )
  assert.strictEqual(run.code, 0)
  assert.ok(run.stdout.indexOf("got:abc") !== -1, run.stdout)
})

test("runCommand 捕获非零退出码", async function () {
  const run = await sandbox.runCommand(process.execPath, ["-e", "process.exit(3)"], {})
  assert.strictEqual(run.code, 3)
  assert.strictEqual(run.timedOut, false)
})

test("runCommand 传入 env 后子进程能看到", async function () {
  const run = await sandbox.runCommand(
    process.execPath,
    ["-e", "process.stdout.write(String(process.env.ALGO_PLAN_TEST_ENV || ''))"],
    { env: Object.assign({}, process.env, { ALGO_PLAN_TEST_ENV: "看得见" }) }
  )
  assert.strictEqual(run.stdout, "看得见")
})

test("runCommand 超时会掐断子进程并标记 timedOut", async function () {
  const run = await sandbox.runCommand(process.execPath, ["-e", "setInterval(function () {}, 1000)"], {
    timeoutMs: 600,
  })
  assert.strictEqual(run.timedOut, true)
  assert.ok(run.durationMs >= 600, "耗时 " + run.durationMs + " 应不少于 600")
})

test("超时后整棵进程树都被杀掉（孙进程也停）", async function () {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-tree-"))
  const log = path.join(dir, "grandchild.log")
  const parent = path.join(dir, "parent.js")
  const grandchild = path.join(dir, "grandchild.js")

  // 孙进程：每 100ms 往日志里追加一行，只要它活着，日志就在长
  fs.writeFileSync(
    grandchild,
    [
      '"use strict"',
      'const fs = require("node:fs")',
      'setInterval(function () { fs.appendFileSync(process.argv[2], "x\\n") }, 100)',
    ].join("\n"),
    "utf8"
  )
  // 父进程：拉起孙进程，然后自己永远活着
  fs.writeFileSync(
    parent,
    [
      '"use strict"',
      'const { spawn } = require("node:child_process")',
      'spawn(process.execPath, [process.argv[2], process.argv[3]], { stdio: "ignore", windowsHide: true })',
      'setInterval(function () {}, 1000)',
    ].join("\n"),
    "utf8"
  )
  fs.writeFileSync(log, "", "utf8")

  const run = await sandbox.runCommand(process.execPath, [parent, grandchild, log], {
    cwd: dir,
    timeoutMs: 1200,
  })
  assert.strictEqual(run.timedOut, true)

  const size1 = fs.statSync(log).size
  await new Promise(function (resolve) { setTimeout(resolve, 700) })
  const size2 = fs.statSync(log).size
  assert.strictEqual(size2, size1, "孙进程还在写日志，说明整棵进程树没被杀干净")
})
```

> **说明**：最后一个用例在 Windows 上会真的调用 `taskkill /T /F` 杀掉一棵进程树。
> 如果执行环境的权限策略拦下了 `taskkill`，这个用例会失败——那说明环境有问题，不是代码有问题，
> 需要放开该命令后重跑。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../judge/sandbox.js'`

- [ ] **Step 3: 写 judge/sandbox.js**

Create `projects/apps/algo-plan/judge/sandbox.js`：

```javascript
"use strict"
/**
 * sandbox.js —— 判题沙箱：临时目录、工具链探测、带超时的子进程执行
 *
 * ⚠ 这不是安全沙箱。用户代码以当前用户权限在系统临时目录里跑。
 *   它防的是：跑飞、死循环、爆内存、编译出一堆垃圾。
 *   它不防：恶意代码（删文件、联网、挖矿）。真隔离要上 Docker 或受限账号
 *   ——那是另一个项目，不塞进这里（设计文档 §5.4）。
 */

const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawn, spawnSync } = require("node:child_process")

/** 单用例默认超时（毫秒） */
const DEFAULT_TIMEOUT_MS = 2000

/** 探测工具链时的超时（毫秒） */
const DETECT_TIMEOUT_MS = 5000

/**
 * Python 解释器的探测顺序。
 * 本机 python3 是 Microsoft Store 的空占位符（无输出、退出码 49），
 * 真身是 python（3.11.15）与 py -3（3.12.3），所以必须依次试（G17）。
 */
const PYTHON_CANDIDATES = [
  { cmd: "python3", args: [] },
  { cmd: "python", args: [] },
  { cmd: "py", args: ["-3"] },
]

/** 探测结果缓存，避免每次判题都 spawn 一遍探测 */
const detectionCache = { compiler: undefined, python: undefined }

/** 清空探测缓存（测试用） */
function resetDetectionCache() {
  detectionCache.compiler = undefined
  detectionCache.python = undefined
}

/**
 * 探测 C/C++ 编译器。
 * 同步实现（spawnSync）：接口契约把 detectCompiler/detectPython 定成非 Promise，
 * 探测本身也只是跑一次 --version，同步更省事。
 * @returns {{cmd: string, version: string}|null}
 */
function detectCompiler() {
  if (detectionCache.compiler !== undefined) return detectionCache.compiler
  const run = spawnSync("g++", ["--version"], {
    timeout: DETECT_TIMEOUT_MS,
    encoding: "utf8",
    windowsHide: true,
  })
  const stdout = String((run && run.stdout) || "")
  if (!run || run.error || run.status !== 0 || stdout.trim() === "") {
    detectionCache.compiler = null
    return null
  }
  detectionCache.compiler = {
    cmd: "g++",
    version: stdout.trim().split("\n")[0].trim(),
  }
  return detectionCache.compiler
}

/**
 * 把 "py -3" 这种用户输入拆成 {cmd, args}。
 * @param {string} text
 * @returns {{cmd: string, args: string[]}}
 */
function parseCandidate(text) {
  const parts = String(text === null || text === undefined ? "" : text)
    .trim()
    .split(/\s+/)
    .filter(function (s) { return s !== "" })
  return { cmd: parts[0] || "python", args: parts.slice(1) }
}

/**
 * 探测 Python 解释器。
 * 同步实现（spawnSync）：接口契约把 detectPython 定成非 Promise。
 * @param {string|null} [override] 用户在设置里指定的解释器，形如 "python" 或 "py -3"
 * @returns {{cmd: string, args: string[], version: string}|null}
 */
function detectPython(override) {
  // 没指定解释器时，缓存里已经探到就直接用，不重复 spawn
  if (!override && detectionCache.python) return detectionCache.python

  const candidates = override
    ? [parseCandidate(override)].concat(PYTHON_CANDIDATES)
    : PYTHON_CANDIDATES

  for (const candidate of candidates) {
    const run = spawnSync(candidate.cmd, candidate.args.concat(["--version"]), {
      timeout: DETECT_TIMEOUT_MS,
      encoding: "utf8",
      windowsHide: true,
    })
    const stdout = String((run && run.stdout) || "")
    // 判据是「退出码 0 且有输出」——Store 占位符 python3 退出码是 49 且无输出，会被正确跳过
    if (run && !run.error && run.status === 0 && stdout.trim() !== "") {
      const found = {
        cmd: candidate.cmd,
        args: candidate.args.slice(),
        version: stdout.trim().split("\n")[0].trim(),
      }
      detectionCache.python = found
      return found
    }
  }

  detectionCache.python = null
  return null
}

/**
 * 组装判题要用的工具链。
 * @param {{pythonOverride?: string|null}} [options]
 * @returns {{compiler: object|null, python: object|null}}
 */
function resolveToolchain(options) {
  const opts = options || {}
  return {
    compiler: detectCompiler(),
    python: detectPython(opts.pythonOverride || null),
  }
}

/**
 * 建一个临时目录。判完必须调 cleanup()（G25）。
 * @returns {{dir: string, cleanup: () => void}}
 */
function createSandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-judge-"))
  let cleaned = false
  return {
    dir: dir,
    cleanup: function () {
      if (cleaned) return
      cleaned = true
      try {
        fs.rmSync(dir, { recursive: true, force: true })
      } catch (e) {
        // 临时目录删不掉不算失败：判题结果已经拿到手了
      }
    },
  }
}

/**
 * 杀整棵进程树。
 * Windows：taskkill /T /F；POSIX：杀整个进程组（spawn 时开了 detached）。
 * @param {import("node:child_process").ChildProcess} child
 */
function killTree(child) {
  if (!child || !child.pid) return
  const pid = child.pid
  if (process.platform === "win32") {
    try {
      spawnSync("taskkill", ["/PID", String(pid), "/T", "/F"], {
        stdio: "ignore",
        windowsHide: true,
      })
    } catch (e) {
      // 进程可能已经自己退了，杀不掉就算了
    }
    return
  }
  try { process.kill(-pid, "SIGKILL") } catch (e) {}
  try { process.kill(pid, "SIGKILL") } catch (e) {}
}

/**
 * 跑一个子进程，带超时。超时后杀整棵进程树并把 timedOut 置 true。
 * @param {string} cmd
 * @param {string[]} args
 * @param {{cwd?: string, input?: string, timeoutMs?: number, env?: object}} [options]
 * @returns {Promise<{code: number|null, stdout: string, stderr: string, durationMs: number, timedOut: boolean, signal: string|null}>}
 */
function runCommand(cmd, args, options) {
  const opts = options || {}
  const timeoutMs = Number(opts.timeoutMs) > 0 ? Number(opts.timeoutMs) : DEFAULT_TIMEOUT_MS
  const started = Date.now()

  return new Promise(function (resolve) {
    let child
    try {
      child = spawn(cmd, args || [], {
        cwd: opts.cwd,
        // POSIX 上开新进程组，超时时能整组杀；Windows 上不能开（会弹新控制台）
        detached: process.platform !== "win32",
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
        env: opts.env || process.env,
      })
    } catch (e) {
      resolve({
        code: null,
        stdout: "",
        stderr: String((e && e.message) || e),
        durationMs: Date.now() - started,
        timedOut: false,
        signal: null,
      })
      return
    }

    const outChunks = []
    const errChunks = []
    let timedOut = false
    let settled = false

    const timer = setTimeout(function () {
      timedOut = true
      killTree(child)
    }, timeoutMs)

    function finish(code, signal, spawnError) {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({
        code: code === undefined ? null : code,
        stdout: Buffer.concat(outChunks).toString("utf8"),
        stderr: spawnError ? String(spawnError) : Buffer.concat(errChunks).toString("utf8"),
        durationMs: Date.now() - started,
        timedOut: timedOut,
        signal: signal === undefined ? null : signal,
      })
    }

    if (child.stdout) {
      child.stdout.on("data", function (chunk) { outChunks.push(chunk) })
    }
    if (child.stderr) {
      child.stderr.on("data", function (chunk) { errChunks.push(chunk) })
    }
    child.on("error", function (err) {
      finish(null, null, (err && err.message) || String(err))
    })
    child.on("close", function (code, signal) {
      finish(code, signal, null)
    })

    if (child.stdin) {
      // 子进程提前退出时写 stdin 会 EPIPE，这里把错误吞掉
      child.stdin.on("error", function () {})
      if (opts.input !== undefined && opts.input !== null) {
        child.stdin.write(String(opts.input))
      }
      child.stdin.end()
    }
  })
}

module.exports = {
  DEFAULT_TIMEOUT_MS: DEFAULT_TIMEOUT_MS,
  DETECT_TIMEOUT_MS: DETECT_TIMEOUT_MS,
  PYTHON_CANDIDATES: PYTHON_CANDIDATES,
  detectCompiler: detectCompiler,
  detectPython: detectPython,
  parseCandidate: parseCandidate,
  resolveToolchain: resolveToolchain,
  createSandbox: createSandbox,
  killTree: killTree,
  runCommand: runCommand,
  resetDetectionCache: resetDetectionCache,
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
git commit -m "feat(algo-plan): 增加判题沙箱与工具链探测

- judge/sandbox.js：临时目录、g++/Python 探测、带超时的子进程执行
- Python 按 python3 → python → py -3 依次探测，判据是退出码 0 且有输出
- Store 占位符 python3（无输出、退出码 49）会被正确跳过
- 超时后杀整棵进程树：Windows taskkill /T /F，POSIX 杀进程组
- runCommand 支持喂 stdin、传 env，追加 signal 字段
- 注释里明写：这不是安全沙箱，防跑飞不防恶意代码
- 测试：探测、临时目录、喂 stdin、超时、杀进程树共 13 条断言"
git push origin main
```

---

## Task 3: 判题 fixture 题库与自检

**Files:**
- Create: `projects/apps/algo-plan/fixtures/judge/manifest.js`
- Create: `projects/apps/algo-plan/fixtures/judge/problems/interview/self-00010.md`
- Create: `projects/apps/algo-plan/fixtures/judge/problems/fundamentals/self-00011.md`
- Create: `projects/apps/algo-plan/fixtures/judge/code/cpp-ok.cpp`
- Create: `projects/apps/algo-plan/fixtures/judge/code/cpp-wrong-answer.cpp`
- Create: `projects/apps/algo-plan/fixtures/judge/code/cpp-compile-error.cpp`
- Create: `projects/apps/algo-plan/fixtures/judge/code/cpp-timeout.cpp`
- Create: `projects/apps/algo-plan/fixtures/judge/code/cpp-runtime-error.cpp`
- Create: `projects/apps/algo-plan/fixtures/judge/code/python-ok.py`
- Create: `projects/apps/algo-plan/fixtures/judge/code/python-wrong-answer.py`
- Create: `projects/apps/algo-plan/fixtures/judge/code/python-runtime-error.py`
- Create: `projects/apps/algo-plan/tests/judge-fixtures.test.js`

**Interfaces:**
- Consumes: Task 2 的 `judge/sandbox.js`（`runCommand`）、M1 的 `core/bank/parse.js`（`parseProblemMarkdown`）
- Produces:
  - `fixtures/judge/manifest.js` 导出
    - `ROOT`：fixture 根目录绝对路径
    - `PROBLEMS`：`{cppSum, pythonReverse}` → 题面文件的绝对路径
    - `CODE`：`{cppOk, cppWrongAnswer, cppCompileError, cppTimeout, cppRuntimeError, pythonOk, pythonWrongAnswer, pythonRuntimeError}` → 提交物的绝对路径
  - 两道**题库格式**的题目（frontmatter + 「## 题面」「## 测试用例」「## 参考解法」）：
    - `self-00010`「两数之和（裸程序契约正例）」，C++，3 个用例
    - `self-00011`「字符串反转（裸程序契约正例）」，Python，2 个用例（其中一个是中文）
  - 八份**提交物**代码：一正例、一答案错误、一编译错误、一超时、一运行时错误（C++ 与 Python 各覆盖）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/judge-fixtures.test.js`：

```javascript
"use strict"
/**
 * judge-fixtures.test.js —— 判题 fixture 自检
 *
 * 这套测试保证 fixture 本身没坏：
 *   - 题面文件是合法的题库 markdown，用例齐全，参考解法与 code/ 里的正例逐字一致
 *   - 三类负例**真的**坏：编译错误真的编不过、死循环真的跑不完、运行时异常真的非零退出
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const { parseProblemMarkdown } = require("../core/bank/parse.js")
const { validateProblem } = require("../core/bank/problem.js")
const sandbox = require("../judge/sandbox.js")
const manifest = require("../fixtures/judge/manifest.js")

function read(file) {
  return fs.readFileSync(file, "utf8")
}

test("fixture 清单里的文件全都存在", function () {
  const all = Object.keys(manifest.PROBLEMS).map(function (k) { return manifest.PROBLEMS[k] })
    .concat(Object.keys(manifest.CODE).map(function (k) { return manifest.CODE[k] }))
  all.forEach(function (file) {
    assert.ok(fs.existsSync(file), "缺文件：" + file)
  })
})

test("self-00010 是合法的题库题目且用例齐全", function () {
  const parsed = parseProblemMarkdown(read(manifest.PROBLEMS.cppSum))
  const problem = parsed.problem
  assert.deepStrictEqual(parsed.warnings, [])
  assert.strictEqual(problem.id, "self-00010")
  assert.strictEqual(problem.title, "两数之和（裸程序契约正例）")
  assert.ok(validateProblem(problem).ok, "题目字段应合法")
  assert.strictEqual(problem.cases.length, 3)
  assert.strictEqual(problem.solutionLang, "cpp")
  assert.ok(problem.statement.indexOf("main") !== -1, "题面要写清是裸程序契约")
})

test("self-00011 是合法的题库题目且用例齐全", function () {
  const parsed = parseProblemMarkdown(read(manifest.PROBLEMS.pythonReverse))
  const problem = parsed.problem
  assert.deepStrictEqual(parsed.warnings, [])
  assert.strictEqual(problem.id, "self-00011")
  assert.strictEqual(problem.cases.length, 2)
  assert.strictEqual(problem.solutionLang, "python")
  assert.strictEqual(problem.cases[1].expect, "字练", "第二个用例必须是中文，验证 UTF-8 处理")
})

test("题库里的参考解法与 code/ 里的正例逐字一致", function () {
  const cpp = parseProblemMarkdown(read(manifest.PROBLEMS.cppSum)).problem
  const py = parseProblemMarkdown(read(manifest.PROBLEMS.pythonReverse)).problem
  assert.strictEqual(cpp.solution.trim(), read(manifest.CODE.cppOk).trim())
  assert.strictEqual(py.solution.trim(), read(manifest.CODE.pythonOk).trim())
})

test("负例：cpp-compile-error 真的编不过", async function () {
  const dir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "algo-plan-fx-"))
  const source = path.join(dir, "main.cpp")
  fs.copyFileSync(manifest.CODE.cppCompileError, source)
  const run = await sandbox.runCommand(
    "g++",
    ["-std=c++17", "-O2", "main.cpp", "-o", "main"],
    { cwd: dir, timeoutMs: 10000 }
  )
  assert.notStrictEqual(run.code, 0, "编译错误 fixture 必须编不过")
  assert.ok(run.stderr.indexOf("error:") !== -1, run.stderr)
})

test("负例：cpp-timeout 真的停不下来", async function () {
  const dir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "algo-plan-fx-"))
  const source = path.join(dir, "main.cpp")
  fs.copyFileSync(manifest.CODE.cppTimeout, source)
  const compile = await sandbox.runCommand(
    "g++",
    ["-std=c++17", "-O2", "main.cpp", "-o", "main"],
    { cwd: dir, timeoutMs: 10000 }
  )
  assert.strictEqual(compile.code, 0, "超时 fixture 本身必须能编译过：" + compile.stderr)
  // 必须用绝对路径：spawn 的可执行文件是相对**父进程** cwd 解析的，cwd 选项只影响子进程自己的工作目录
  const binary = path.join(dir, fs.existsSync(path.join(dir, "main.exe")) ? "main.exe" : "main")
  const run = await sandbox.runCommand(binary, [], { cwd: dir, timeoutMs: 800 })
  assert.strictEqual(run.timedOut, true, "死循环 fixture 必须跑不完")
})

test("负例：cpp-runtime-error 真的非零退出", async function () {
  const dir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "algo-plan-fx-"))
  const source = path.join(dir, "main.cpp")
  fs.copyFileSync(manifest.CODE.cppRuntimeError, source)
  const compile = await sandbox.runCommand(
    "g++",
    ["-std=c++17", "-O2", "main.cpp", "-o", "main"],
    { cwd: dir, timeoutMs: 10000 }
  )
  assert.strictEqual(compile.code, 0, compile.stderr)
  // 绝对路径，见上面那条注释
  const binary = path.join(dir, fs.existsSync(path.join(dir, "main.exe")) ? "main.exe" : "main")
  const run = await sandbox.runCommand(binary, [], { cwd: dir, timeoutMs: 5000 })
  assert.notStrictEqual(run.code, 0, "运行时异常 fixture 必须非零退出")
  assert.ok(run.stderr.length > 0, "必须留下错误输出")
})

test("负例：python-runtime-error 真的非零退出并留下 traceback", async function () {
  const python = sandbox.detectPython()
  assert.ok(python)
  const dir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "algo-plan-fx-"))
  const source = path.join(dir, "main.py")
  fs.copyFileSync(manifest.CODE.pythonRuntimeError, source)
  const run = await sandbox.runCommand(python.cmd, python.args.concat(["main.py"]), {
    cwd: dir,
    timeoutMs: 5000,
    env: Object.assign({}, process.env, { PYTHONIOENCODING: "utf-8" }),
  })
  assert.strictEqual(run.code, 1)
  assert.ok(run.stderr.indexOf("ValueError") !== -1, run.stderr)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../fixtures/judge/manifest.js'`

- [ ] **Step 3: 写 fixtures/judge/manifest.js**

Create `projects/apps/algo-plan/fixtures/judge/manifest.js`：

```javascript
"use strict"
/**
 * manifest.js —— 判题 fixture 的路径表
 *
 * fixture 分两类：
 *   problems/ —— 题面 + 用例 + 参考解法（题库 markdown 格式，可直接导入 learning/bank）
 *   code/     —— 「用户的提交物」：正例与三类负例（编译错误 / 超时 / 运行时异常）
 */

const path = require("node:path")

const ROOT = __dirname

module.exports = {
  ROOT: ROOT,
  PROBLEMS: {
    cppSum: path.join(ROOT, "problems", "interview", "self-00010.md"),
    pythonReverse: path.join(ROOT, "problems", "fundamentals", "self-00011.md"),
  },
  CODE: {
    cppOk: path.join(ROOT, "code", "cpp-ok.cpp"),
    cppWrongAnswer: path.join(ROOT, "code", "cpp-wrong-answer.cpp"),
    cppCompileError: path.join(ROOT, "code", "cpp-compile-error.cpp"),
    cppTimeout: path.join(ROOT, "code", "cpp-timeout.cpp"),
    cppRuntimeError: path.join(ROOT, "code", "cpp-runtime-error.cpp"),
    pythonOk: path.join(ROOT, "code", "python-ok.py"),
    pythonWrongAnswer: path.join(ROOT, "code", "python-wrong-answer.py"),
    pythonRuntimeError: path.join(ROOT, "code", "python-runtime-error.py"),
  },
}
```

- [ ] **Step 4: 写两道 fixture 题**

Create `projects/apps/algo-plan/fixtures/judge/problems/interview/self-00010.md`：

````markdown
---
id: self-00010
source: self
title: 两数之和（裸程序契约正例）
difficulty: easy
topics: [哈希表, 数组]
tracks: [interview, fundamentals]
status: todo
needs_fill: false
created: 2026-11-11
updated: 2026-11-11
---
## 题面

给定一个整数数组 `nums` 和一个整数 `target`，请在数组中找出和为目标值的两个整数，
并返回它们的下标（小的在前）。同一个元素不能重复使用。

**判题契约**：提交的是完整的 stdin→stdout 程序，必须自己写 `main()`。

**输入格式**：一个整数 `n`（数组长度），接着 `n` 个整数（数组元素），最后一个整数是 `target`。
所有数字用空格分隔，怎么排都行（按空白读即可）。

**输出格式**：两个下标，中间一个空格；找不到就输出 `-1 -1`。

## 测试用例

| input | expect |
|---|---|
| 4 2 7 11 15 9 | 0 1 |
| 3 3 4 8 7 | 0 1 |
| 1 5 5 | -1 -1 |

## 参考解法

```cpp
#include <iostream>
#include <vector>
using namespace std;

int main() {
    int n;
    if (!(cin >> n)) return 0;
    vector<int> nums(n);
    for (int i = 0; i < n; ++i) cin >> nums[i];
    int target;
    cin >> target;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (nums[i] + nums[j] == target) {
                cout << i << " " << j << endl;
                return 0;
            }
        }
    }
    cout << "-1 -1" << endl;
    return 0;
}
```
````

Create `projects/apps/algo-plan/fixtures/judge/problems/fundamentals/self-00011.md`：

````markdown
---
id: self-00011
source: self
title: 字符串反转（裸程序契约正例）
difficulty: easy
topics: [字符串]
tracks: [fundamentals]
status: todo
needs_fill: false
created: 2026-11-11
updated: 2026-11-11
---
## 题面

给定一个字符串 `s`，输出它的反转结果。

**判题契约**：提交的是完整的 stdin→stdout 程序，必须自己写 `main()`（读 stdin、写 stdout）。

**输入格式**：一行一个字符串（不含空格）。

**输出格式**：一行一个字符串。

## 测试用例

| input | expect |
|---|---|
| hello | olleh |
| 练字 | 字练 |

## 参考解法

```python
# 字符串反转：stdin 读一行，stdout 输出一行
s = input()
print(s[::-1])
```
````

- [ ] **Step 5: 写八份提交物代码**

Create `projects/apps/algo-plan/fixtures/judge/code/cpp-ok.cpp`：

```cpp
#include <iostream>
#include <vector>
using namespace std;

int main() {
    int n;
    if (!(cin >> n)) return 0;
    vector<int> nums(n);
    for (int i = 0; i < n; ++i) cin >> nums[i];
    int target;
    cin >> target;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (nums[i] + nums[j] == target) {
                cout << i << " " << j << endl;
                return 0;
            }
        }
    }
    cout << "-1 -1" << endl;
    return 0;
}
```

Create `projects/apps/algo-plan/fixtures/judge/code/cpp-wrong-answer.cpp`：

```cpp
#include <iostream>
#include <vector>
using namespace std;

int main() {
    int n;
    if (!(cin >> n)) return 0;
    vector<int> nums(n);
    for (int i = 0; i < n; ++i) cin >> nums[i];
    int target;
    cin >> target;
    // 故意写错：不管输入是什么，一律输出 0 0
    cout << "0 0" << endl;
    return 0;
}
```

Create `projects/apps/algo-plan/fixtures/judge/code/cpp-compile-error.cpp`：

```cpp
#include <iostream>

int main() {
    undefined_function_call();
    return 0;
}
```

Create `projects/apps/algo-plan/fixtures/judge/code/cpp-timeout.cpp`：

```cpp
#include <iostream>

// 死循环用的自增变量：volatile 保证优化器不会把它删掉
volatile long long spin = 0;

int main() {
    // 故意死循环：用来触发 timeout
    for (;;) {
        spin = spin + 1;
    }
    return 0;
}
```

Create `projects/apps/algo-plan/fixtures/judge/code/cpp-runtime-error.cpp`：

```cpp
#include <iostream>
#include <stdexcept>

int main() {
    std::cout << "start" << std::endl;
    // 故意抛一个没人接的异常：进程非零退出（实测退出码 3）
    throw std::runtime_error("boom");
}
```

Create `projects/apps/algo-plan/fixtures/judge/code/python-ok.py`：

```python
# 字符串反转：stdin 读一行，stdout 输出一行
s = input()
print(s[::-1])
```

Create `projects/apps/algo-plan/fixtures/judge/code/python-wrong-answer.py`：

```python
# 故意写错：原样输出，不反转
s = input()
print(s)
```

Create `projects/apps/algo-plan/fixtures/judge/code/python-runtime-error.py`：

```python
# 故意抛异常：进程以退出码 1 结束，stderr 里有 traceback
raise ValueError("boom")
```

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `11 / 11 套件通过`，退出码 0

- [ ] **Step 7: 把 fixture 题导入 learning 仓（一次性动作）**

M1 的 `tools/seed-bank.js` 命令行只认 `--dry-run` / `--force` 两个开关，换目录要用编程接口
`seed.run({ fixturesDir })`。先试运行：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node -e "const seed=require('./tools/seed-bank.js');const r=seed.run({env:{ALGO_PLAN_LEARNING_ROOT:'/c/code/StillEvolving/learning'},fixturesDir:'./fixtures/judge/problems',dryRun:true});console.log(JSON.stringify(r,null,2))"
```

Expected: 打印 `"written"` 里两个 `learning/bank/.../self-00010.md` 与 `self-00011.md` 路径，
`"errors"` 是空数组。试运行不会真的写盘。

确认无误后去掉 `dryRun:true` 再跑一次，就是真的导入：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
node -e "const seed=require('./tools/seed-bank.js');const r=seed.run({env:{ALGO_PLAN_LEARNING_ROOT:'/c/code/StillEvolving/learning'},fixturesDir:'./fixtures/judge/problems'});console.log(JSON.stringify(r,null,2))"
```

> **这一步会往 learning 仓写入新文件。** 写不写、什么时候提交，由你决定——
> **app 和本计划都不会自动 `git commit`**（G11）。

- [ ] **Step 8: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加判题 fixture 题库与自检

- fixtures/judge/problems/：2 道题库格式的题（C++ 两数之和、Python 字符串反转）
- 题面写明判题契约：提交完整 stdin→stdout 程序，自己写 main()
- fixtures/judge/code/：正例、答案错误、编译错误、死循环、运行时异常共 8 份提交物
- tests/judge-fixtures.test.js：参考解法与正例逐字一致，三类负例实测确实坏
- 死循环用 volatile 自增防止被优化器删掉；中文用例验证 UTF-8 处理"
git push origin main
```

---

## Task 4: 判题编排器——五分类 verdict

**Files:**
- Create: `projects/apps/algo-plan/judge/runner.js`
- Create: `projects/apps/algo-plan/tests/runner.test.js`

**Interfaces:**
- Consumes: Task 1 的 `core/judge-spec/cases.js`（`normalizeCases`）与 `core/judge-spec/compare.js`（`compareOutput`）；Task 2 的 `judge/sandbox.js`（`createSandbox` / `runCommand` / `resolveToolchain`）；Task 3 的 fixture
- Produces:
  - `judge/runner.js` 导出
    - `judge({problem, code, language, timeoutMs, toolchain}) -> Promise<{verdict, passedCases, totalCases, durationMs, failedCase, message, compilerOutput}>`
      - `verdict` 只会是 `"pass"` / `"wrong_answer"` / `"timeout"` / `"compile_error"` / `"runtime_error"`（G27）
      - `failedCase` 是 `{index, input, expected, actual}` 或 `null`
      - `message` 是中文说明，形如「答案错误：第 2 个用例不通过：输出与期望不一致」
      - `compilerOutput` 是编译错误原文 / stderr；通过与答案错误时是空串
    - `VERDICTS`：五个 verdict 字符串的数组
    - `VERDICT_PANEL`：`{verdict: {title, tone, hint}}`，每类的中文面板文案
    - `LANGUAGES`：`["cpp", "python"]`
    - `parseCompilerError(output) -> {line: number|null, column: number|null, text: string}`
    - `DEFAULT_CASE_TIMEOUT_MS = 2000`、`COMPILE_TIMEOUT_MS = 10000`
  - **相对接口契约 §2 的增补**（只做加法，不改动契约里已有的字段名与含义）：
    - `judge()` 的入参**追加**可选字段 `toolchain`（`{compiler, python}`；缺省就现场探测），
      这样 API 层可以先按 `settings` 里的缓存决定解释器，再传给判题器（G17）。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/runner.test.js`：

```javascript
"use strict"
/**
 * runner.test.js —— 判题编排器：五类 verdict 端到端（真编译、真执行）
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")

const { parseProblemMarkdown } = require("../core/bank/parse.js")
const runner = require("../judge/runner.js")
const manifest = require("../fixtures/judge/manifest.js")

function loadProblem(file) {
  return parseProblemMarkdown(fs.readFileSync(file, "utf8")).problem
}

function loadCode(file) {
  return fs.readFileSync(file, "utf8")
}

test("verdict 只有五个，且与契约逐字一致", function () {
  assert.deepStrictEqual(runner.VERDICTS, [
    "pass",
    "wrong_answer",
    "timeout",
    "compile_error",
    "runtime_error",
  ])
})

test("五类 verdict 都备了中文面板文案", function () {
  runner.VERDICTS.forEach(function (v) {
    const panel = runner.VERDICT_PANEL[v]
    assert.ok(panel, "缺少 " + v + " 的面板文案")
    assert.ok(panel.title && panel.title.length > 0, v + " 缺标题")
    assert.ok(panel.hint && panel.hint.length > 0, v + " 缺提示")
    assert.ok(["ok", "bad", "warn"].indexOf(panel.tone) !== -1, v + " 的色调不合法")
  })
})

test("parseCompilerError 能取出行号、列号与原因", function () {
  const out = runner.parseCompilerError(
    "main.cpp:4:5: error: 'undefined_function_call' was not declared in this scope\n    4 |     undefined_function_call();\n"
  )
  assert.strictEqual(out.line, 4)
  assert.strictEqual(out.column, 5)
  assert.ok(out.text.indexOf("undefined_function_call") !== -1, out.text)
})

test("parseCompilerError 对缺 main 的链接期错误给中文说明", function () {
  const out = runner.parseCompilerError(
    "C:/mingw64/bin/ld.exe: undefined reference to `main'\ncollect2.exe: error: ld returned 1 exit status\n"
  )
  assert.strictEqual(out.line, null)
  assert.ok(out.text.indexOf("main") !== -1, out.text)
  assert.ok(out.text.indexOf("自己写 main()") !== -1, "要提醒用户自己写 main()：" + out.text)
})

test("C++ 正例判为 pass", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppOk),
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "pass")
  assert.strictEqual(out.passedCases, 3)
  assert.strictEqual(out.totalCases, 3)
  assert.strictEqual(out.failedCase, null)
  assert.strictEqual(out.compilerOutput, "")
  assert.ok(out.message.indexOf("通过") !== -1, out.message)
  assert.ok(out.durationMs >= 0)
})

test("C++ 答案错误：报告第几个用例挂的、期望 vs 实际", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppWrongAnswer),
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "wrong_answer")
  assert.strictEqual(out.passedCases, 0)
  assert.strictEqual(out.totalCases, 3)
  assert.ok(out.failedCase, "必须给出失败用例")
  assert.strictEqual(out.failedCase.index, 1)
  assert.strictEqual(out.failedCase.expected, "0 1")
  assert.ok(out.failedCase.actual.indexOf("0 0") !== -1, out.failedCase.actual)
  assert.ok(out.failedCase.input.indexOf("2 7 11 15") !== -1, out.failedCase.input)
  assert.ok(out.message.indexOf("第 1 个用例") !== -1, out.message)
})

test("C++ 编译错误：给出编译器原文与错误行号", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppCompileError),
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "compile_error")
  assert.strictEqual(out.passedCases, 0)
  assert.ok(out.compilerOutput.indexOf("error:") !== -1, out.compilerOutput)
  // fixture 里 undefined_function_call() 在第 4 行，行号必须解析对
  assert.ok(out.message.indexOf("第 4 行") !== -1, "要给出正确的错误行号：" + out.message)
  assert.ok(out.message.indexOf("undefined_function_call") !== -1, out.message)
})

test("判题契约：class Solution 没有 main() 一律编译失败，不注入包装", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: [
      "class Solution {",
      "public:",
      "    int twoSum(int a, int b) { return a + b; }",
      "};",
    ].join("\n"),
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "compile_error")
  assert.ok(out.message.indexOf("main") !== -1, "面板要说明缺 main：" + out.message)
})

test("C++ 死循环判为 timeout，并说明超时上限", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppTimeout),
    language: "cpp",
    timeoutMs: 800,
  })
  assert.strictEqual(out.verdict, "timeout")
  assert.ok(out.message.indexOf("超时") !== -1, out.message)
  assert.ok(out.message.indexOf("800") !== -1, "要说明超时上限：" + out.message)
})

test("C++ 运行时异常判为 runtime_error，并带上错误输出", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppRuntimeError),
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "runtime_error")
  assert.strictEqual(out.passedCases, 0)
  assert.ok(out.compilerOutput.length > 0, "必须带 stderr 原文")
})

test("Python 正例判为 pass（含中文用例）", async function () {
  const problem = loadProblem(manifest.PROBLEMS.pythonReverse)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.pythonOk),
    language: "python",
  })
  assert.strictEqual(out.verdict, "pass")
  assert.strictEqual(out.passedCases, 2)
  assert.strictEqual(out.totalCases, 2)
})

test("Python 答案错误判为 wrong_answer", async function () {
  const problem = loadProblem(manifest.PROBLEMS.pythonReverse)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.pythonWrongAnswer),
    language: "python",
  })
  assert.strictEqual(out.verdict, "wrong_answer")
  assert.strictEqual(out.failedCase.index, 1)
  assert.strictEqual(out.failedCase.expected, "olleh")
  assert.strictEqual(out.failedCase.actual.trim(), "hello")
})

test("Python 运行时异常判为 runtime_error，并带上 traceback", async function () {
  const problem = loadProblem(manifest.PROBLEMS.pythonReverse)
  const out = await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.pythonRuntimeError),
    language: "python",
  })
  assert.strictEqual(out.verdict, "runtime_error")
  assert.ok(out.compilerOutput.indexOf("ValueError") !== -1, out.compilerOutput)
})

test("不认识的语言直接报编译错误，不 spawn 任何东西", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const out = await runner.judge({
    problem: problem,
    code: "print(1)",
    language: "rust",
  })
  assert.strictEqual(out.verdict, "compile_error")
  assert.ok(out.message.indexOf("rust") !== -1, out.message)
})

test("没有测试用例的题目给出明确说明", async function () {
  const out = await runner.judge({
    problem: { id: "self-09999", cases: [] },
    code: "int main(){}",
    language: "cpp",
  })
  assert.strictEqual(out.verdict, "wrong_answer")
  assert.ok(out.message.indexOf("没有测试用例") !== -1, out.message)
})

test("判完临时目录被删掉，不留编译垃圾", async function () {
  const problem = loadProblem(manifest.PROBLEMS.cppSum)
  const before = fs.readdirSync(require("node:os").tmpdir()).filter(function (name) {
    return name.indexOf("algo-plan-judge-") === 0
  }).length
  await runner.judge({
    problem: problem,
    code: loadCode(manifest.CODE.cppOk),
    language: "cpp",
  })
  const after = fs.readdirSync(require("node:os").tmpdir()).filter(function (name) {
    return name.indexOf("algo-plan-judge-") === 0
  }).length
  assert.strictEqual(after, before, "临时目录判完必须删掉")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../judge/runner.js'`

- [ ] **Step 3: 写 judge/runner.js**

Create `projects/apps/algo-plan/judge/runner.js`：

```javascript
"use strict"
/**
 * runner.js —— 判题编排器：写文件 → 编译 → 逐用例执行 → 比对 → verdict
 *
 * 判题契约（硬约束，见设计文档 §5.1 与接口契约 G18）：
 *   提交的是「stdin 进、stdout 出」的裸程序，用户自己写 main()。
 *   本文件绝不注入 Solution 包装、绝不自动生成 main。
 *   存量 LeetCode 风格题解是 class Solution { ... }（没有 main），
 *   那种代码提交进来必然编译失败——这是有意的。
 *
 * ⚠ 这不是安全沙箱：用户代码以当前用户权限在系统临时目录里跑（设计文档 §5.4）。
 */

const fs = require("node:fs")
const path = require("node:path")

const { normalizeCases } = require("../core/judge-spec/cases.js")
const { compareOutput } = require("../core/judge-spec/compare.js")
const { createSandbox, runCommand, resolveToolchain } = require("./sandbox.js")

/** 支持的语言 */
const LANGUAGES = ["cpp", "python"]

/** 五类 verdict，顺序即面板展示顺序 */
const VERDICTS = ["pass", "wrong_answer", "timeout", "compile_error", "runtime_error"]

/** 每类 verdict 的中文面板文案 */
const VERDICT_PANEL = {
  pass: {
    title: "通过",
    tone: "ok",
    hint: "全部用例通过，程序行为符合预期。",
  },
  wrong_answer: {
    title: "答案错误",
    tone: "bad",
    hint: "程序编译通过、也正常退出了，但输出与期望不一致。",
  },
  timeout: {
    title: "超时",
    tone: "warn",
    hint: "单个用例的运行时间超过了上限，已强制结束整棵进程树。",
  },
  compile_error: {
    title: "编译失败",
    tone: "bad",
    hint: "代码没能编译成可执行文件，下面是编译器原文。",
  },
  runtime_error: {
    title: "运行时错误",
    tone: "bad",
    hint: "程序运行时报错或以非零状态退出，下面是错误输出。",
  },
}

/** 单用例默认超时（毫秒） */
const DEFAULT_CASE_TIMEOUT_MS = 2000

/** 编译超时（毫秒）：编译比单个用例慢得多，单独给一份预算 */
const COMPILE_TIMEOUT_MS = 10000

/**
 * 取第一行非空文本。
 * @param {string} text
 * @returns {string}
 */
function firstNonEmptyLine(text) {
  const lines = String(text === null || text === undefined ? "" : text).split(/\r?\n/)
  for (const line of lines) {
    const trimmed = line.trim()
    if (trimmed !== "") return trimmed
  }
  return ""
}

/**
 * 从编译器输出里解析第一个错误位置。
 * g++ 的格式是 "main.cpp:4:5: error: 'xxx' was not declared in this scope"。
 * 链接期错误（缺 main）没有行号，这时退化成中文说明。
 * @param {string} output
 * @returns {{line: number|null, column: number|null, text: string}}
 */
function parseCompilerError(output) {
  const text = String(output || "")

  // 捕获组：1=文件名 2=行号 3=列号（可选） 4=原因
  const located = /(\S+\.(?:cpp|cc|cxx|c|h|hpp)):(\d+)(?::(\d+))?:\s*(?:fatal\s+)?error:\s*(.*)$/m.exec(text)
  if (located) {
    return {
      line: Number(located[2]),
      column: located[3] === undefined ? null : Number(located[3]),
      text: located[4].trim(),
    }
  }

  // 缺 main：mingw 报 WinMain，Linux 报 main，两种都要认
  if (/undefined reference to [`'"]?(Win)?main[`'"]?/i.test(text)) {
    return {
      line: null,
      column: null,
      text: "没有 main 函数：判题契约要求提交完整的 stdin→stdout 程序，用户自己写 main()",
    }
  }

  const plain = /(?:^|\n)([^\n]*error:[^\n]*)/i.exec(text)
  if (plain) {
    return { line: null, column: null, text: plain[1].trim() }
  }

  const symbol = /undefined reference to [`'"]?([^`'"\s(]+)/.exec(text)
  if (symbol) {
    return { line: null, column: null, text: "undefined reference to " + symbol[1] }
  }

  return { line: null, column: null, text: firstNonEmptyLine(text) }
}

/**
 * 组装判题结果。message 统一以 verdict 的中文标题开头，面板直接用它当标题。
 */
function makeResult(verdict, passedCases, totalCases, started, failedCase, detail, compilerOutput) {
  const panel = VERDICT_PANEL[verdict]
  return {
    verdict: verdict,
    passedCases: passedCases,
    totalCases: totalCases,
    durationMs: Date.now() - started,
    failedCase: failedCase,
    message: panel.title + "：" + detail,
    compilerOutput: compilerOutput || "",
  }
}

/**
 * 找可执行文件。mingw 编译 -o main 产出的是 main.exe。
 * @param {string} dir
 * @returns {string}
 */
function resolveBinary(dir) {
  const names = process.platform === "win32" ? ["main.exe", "main"] : ["main", "main.exe"]
  for (const name of names) {
    const file = path.join(dir, name)
    if (fs.existsSync(file)) return file
  }
  return path.join(dir, names[0])
}

/**
 * 判一道题。
 * @param {{problem: object, code: string, language: string, timeoutMs?: number, toolchain?: object}} params
 *   toolchain：{compiler, python}；缺省就现场探测
 * @returns {Promise<{
 *   verdict: string, passedCases: number, totalCases: number, durationMs: number,
 *   failedCase: {index: number, input: string, expected: string, actual: string}|null,
 *   message: string, compilerOutput: string
 * }>}
 */
async function judge(params) {
  const p = params || {}
  const problem = p.problem || {}
  const code = String(p.code === null || p.code === undefined ? "" : p.code)
  const language = String(p.language || "cpp").toLowerCase()
  const caseTimeoutMs = Number(p.timeoutMs) > 0 ? Number(p.timeoutMs) : DEFAULT_CASE_TIMEOUT_MS

  const cases = normalizeCases(problem.cases)
  const started = Date.now()

  // 语言不认识，直接报回去，不 spawn 任何东西
  if (LANGUAGES.indexOf(language) === -1) {
    return makeResult(
      "compile_error", 0, cases.length, started, null,
      "不支持的语言：" + language + "（只支持 cpp 与 python）", ""
    )
  }

  if (cases.length === 0) {
    // verdict 只有五类（G27），没有用例不属于任何一类，落到 wrong_answer 并说清原因。
    // 正常路径不会走到这里：server/api.js 的 POST /api/attempt 会先挡一道并返回 400。
    return makeResult(
      "wrong_answer", 0, 0, started, null,
      "题目没有测试用例，无法判定是否通过；请先在题库里补齐用例", ""
    )
  }

  const toolchain = p.toolchain || resolveToolchain({})
  const sandbox = createSandbox()

  try {
    let command = ""
    let args = []

    if (language === "cpp") {
      const compiler = toolchain.compiler
      if (!compiler) {
        return makeResult(
          "compile_error", 0, cases.length, started, null,
          "本机没有找到 g++，无法编译 C++ 代码", ""
        )
      }
      fs.writeFileSync(path.join(sandbox.dir, "main.cpp"), code, "utf8")
      const compiled = await runCommand(
        compiler.cmd,
        ["-std=c++17", "-O2", "main.cpp", "-o", "main"],
        { cwd: sandbox.dir, timeoutMs: COMPILE_TIMEOUT_MS }
      )
      if (compiled.timedOut) {
        return makeResult(
          "compile_error", 0, cases.length, started, null,
          "编译超时（超过 " + COMPILE_TIMEOUT_MS + "ms）", compiled.stderr
        )
      }
      if (compiled.code !== 0) {
        const detail = parseCompilerError(compiled.stderr)
        const where = detail.line === null ? "" : "第 " + detail.line + " 行："
        return makeResult(
          "compile_error", 0, cases.length, started, null,
          where + detail.text, compiled.stderr
        )
      }
      command = resolveBinary(sandbox.dir)
      args = []
    } else {
      const python = toolchain.python
      if (!python) {
        return makeResult(
          "compile_error", 0, cases.length, started, null,
          "本机没有找到可用的 Python 解释器（试过 python3 / python / py -3）", ""
        )
      }
      fs.writeFileSync(path.join(sandbox.dir, "main.py"), code, "utf8")
      command = python.cmd
      args = python.args.concat(["main.py"])
    }

    const pythonEnv = Object.assign({}, process.env, { PYTHONIOENCODING: "utf-8" })
    let passed = 0

    for (const item of cases) {
      const run = await runCommand(command, args, {
        cwd: sandbox.dir,
        input: item.input === "" ? "" : item.input + "\n",
        timeoutMs: caseTimeoutMs,
        env: language === "python" ? pythonEnv : process.env,
      })

      if (run.timedOut) {
        return makeResult(
          "timeout", passed, cases.length, started, null,
          "第 " + item.index + " 个用例超时：运行超过 " + caseTimeoutMs + "ms 后被强制结束",
          run.stderr
        )
      }

      if (run.code !== 0) {
        const how = run.code === null && run.signal
          ? "被信号 " + run.signal + " 终止"
          : "退出码 " + run.code
        return makeResult(
          "runtime_error", passed, cases.length, started, null,
          "第 " + item.index + " 个用例运行失败（" + how + "）：" + firstNonEmptyLine(run.stderr),
          run.stderr
        )
      }

      const cmp = compareOutput(run.stdout, item.expect, item.tol)
      if (!cmp.equal) {
        return makeResult(
          "wrong_answer", passed, cases.length, started,
          { index: item.index, input: item.input, expected: item.expect, actual: run.stdout },
          "第 " + item.index + " 个用例不通过：" + cmp.reason,
          run.stderr
        )
      }

      passed += 1
    }

    return makeResult(
      "pass", passed, cases.length, started, null,
      "全部 " + cases.length + " 个用例通过", ""
    )
  } finally {
    // G25：临时目录与编译产物判完即删
    sandbox.cleanup()
  }
}

module.exports = {
  LANGUAGES: LANGUAGES,
  VERDICTS: VERDICTS,
  VERDICT_PANEL: VERDICT_PANEL,
  DEFAULT_CASE_TIMEOUT_MS: DEFAULT_CASE_TIMEOUT_MS,
  COMPILE_TIMEOUT_MS: COMPILE_TIMEOUT_MS,
  judge: judge,
  parseCompilerError: parseCompilerError,
  firstNonEmptyLine: firstNonEmptyLine,
  resolveBinary: resolveBinary,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `12 / 12 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加判题编排器与五分类 verdict

- judge/runner.js：写文件 → 编译 → 逐用例执行 → 比对 → verdict
- verdict 固定五类：pass / wrong_answer / timeout / compile_error / runtime_error
- 每类 verdict 配中文面板文案（标题 + 提示 + 色调）
- 编译错误解析出文件、行号、列号与原因；缺 main 给出契约提示
- C++ 用 g++ -std=c++17 -O2，Python 子进程强制 PYTHONIOENCODING=utf-8
- 判完临时目录与编译产物即删，不留垃圾
- 判题契约写进文件头：裸程序，自己写 main，不注入 Solution 包装
- 测试：五类 verdict 端到端、契约反例、临时目录清理共 17 条断言"
git push origin main
```

---

## Task 5: `POST /api/attempt` 接口——提交代码、判题、记流水

**Files:**
- Modify: `projects/apps/algo-plan/server/api.js`
- Create: `projects/apps/algo-plan/tests/attempt.test.js`

**Interfaces:**
- Consumes: Task 4 的 `judge/runner.js`（`judge` / `LANGUAGES` / `DEFAULT_CASE_TIMEOUT_MS`）与 Task 2 的 `judge/sandbox.js`（`resolveToolchain`）；M1 的 `server/router.js`（`readJsonBody`）、`server/db.js`（`store.insertAttempt` / `store.getSetting` / `store.setSetting`）、`core/bank/provider.js`（`provider.get`）
- Produces:
  - `server/api.js` 导出 `buildRoutes(ctx)`（**在 M1 的三个接口之外追加** `POST /api/attempt`）、`SAMPLE_CASE_COUNT = 2`、`ATTEMPT_MODES = ["solve", "review", "probe"]`
  - `POST /api/attempt`
    - 入参：`{problemId: string, code: string, language: "cpp"|"python", mode?: "solve"|"review"|"probe"}`
    - 响应（**字段与顺序照接口契约 §2 冻结的八个，不多不少**）：
      `{attemptId, verdict, passedCases, totalCases, durationMs, failedCase, message, compilerOutput}`
    - `failedCase` 是 `{index, input, expected, actual}` 或 `null`
    - `verdict` 只会是五个固定字符串之一（G27）
  - 新增两个 `settings` 键：`judge.timeout_ms`（单用例超时毫秒，默认 `2000`）、`judge.python.cmd`（探测出来的解释器缓存）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/attempt.test.js`：

```javascript
"use strict"
/**
 * attempt.test.js —— POST /api/attempt：提交代码 → 真实判题 → 记流水
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const { createApp } = require("../server/app.js")
const manifest = require("../fixtures/judge/manifest.js")

/** 造一个带一道有用例的题的 learning 仓 */
function tempLearning() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-attempt-"))
  const dir = path.join(root, "bank", "interview")
  fs.mkdirSync(dir, { recursive: true })
  fs.copyFileSync(manifest.PROBLEMS.cppSum, path.join(dir, "self-00010.md"))
  return root
}

async function withApp(fn) {
  const app = createApp({ dbPath: ":memory:", learningRoot: tempLearning() })
  const port = await app.listen(0)
  try {
    await fn("http://127.0.0.1:" + port, app)
  } finally {
    await app.close()
  }
}

function post(base, body) {
  return fetch(base + "/api/attempt", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
}

function cppCode() {
  return fs.readFileSync(manifest.CODE.cppOk, "utf8")
}

test("POST /api/attempt 判一道 C++ 题，响应形状是契约冻结的八个字段", async function () {
  await withApp(async function (base) {
    const res = await post(base, {
      problemId: "self-00010",
      code: cppCode(),
      language: "cpp",
      mode: "solve",
    })
    assert.strictEqual(res.status, 200)
    const body = await res.json()
    assert.deepStrictEqual(
      Object.keys(body).sort(),
      [
        "attemptId", "compilerOutput", "durationMs", "failedCase",
        "message", "passedCases", "totalCases", "verdict",
      ].sort()
    )
    assert.strictEqual(body.verdict, "pass")
    assert.strictEqual(body.passedCases, 3)
    assert.strictEqual(body.totalCases, 3)
    assert.strictEqual(body.failedCase, null)
    assert.strictEqual(body.compilerOutput, "")
    assert.ok(body.message.indexOf("通过") !== -1, body.message)
    assert.ok(body.attemptId > 0, "要返回流水 id")
  })
})

test("作答流水真的写进 SQLite", async function () {
  await withApp(async function (base, app) {
    await post(base, { problemId: "self-00010", code: cppCode(), language: "cpp", mode: "review" })
    assert.strictEqual(app.store.countAttempts(), 1)
    const rows = app.store.listAttemptsByProblem("self-00010")
    assert.strictEqual(rows.length, 1)
    assert.strictEqual(rows[0].verdict, "pass")
    assert.strictEqual(rows[0].mode, "review")
    assert.strictEqual(rows[0].language, "cpp")
    assert.strictEqual(Number(rows[0].passed_cases), 3)
  })
})

test("题目不存在返回 404", async function () {
  await withApp(async function (base) {
    const res = await post(base, { problemId: "self-99999", code: "int main(){}", language: "cpp" })
    assert.strictEqual(res.status, 404)
    const body = await res.json()
    assert.strictEqual(body.error, "题目不存在")
  })
})

test("代码为空返回 400", async function () {
  await withApp(async function (base) {
    const res = await post(base, { problemId: "self-00010", code: "   ", language: "cpp" })
    assert.strictEqual(res.status, 400)
    const body = await res.json()
    assert.strictEqual(body.error, "代码不能为空")
  })
})

test("不支持的语言返回 400", async function () {
  await withApp(async function (base) {
    const res = await post(base, { problemId: "self-00010", code: "print(1)", language: "rust" })
    assert.strictEqual(res.status, 400)
    const body = await res.json()
    assert.ok(body.error.indexOf("rust") !== -1, body.error)
  })
})

test("非法 mode 返回 400", async function () {
  await withApp(async function (base) {
    const res = await post(base, { problemId: "self-00010", code: cppCode(), language: "cpp", mode: "随便写" })
    assert.strictEqual(res.status, 400)
    const body = await res.json()
    assert.ok(body.error.indexOf("mode") !== -1, body.error)
  })
})

test("没有测试用例的题目返回 400 并说清原因", async function () {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-attempt-"))
  const dir = path.join(root, "bank", "interview")
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(
    path.join(dir, "self-00011.md"),
    [
      "---",
      "id: self-00011",
      "source: self",
      "title: 没有用例的题",
      "difficulty: easy",
      "topics: [数组]",
      "tracks: [interview]",
      "status: todo",
      "needs_fill: true",
      "created: 2026-11-11",
      "updated: 2026-11-11",
      "---",
      "## 题面",
      "",
      "没有用例。",
      "",
      "## 测试用例",
      "",
      "| input | expect |",
      "|---|---|",
      "",
    ].join("\n"),
    "utf8"
  )
  const app = createApp({ dbPath: ":memory:", learningRoot: root })
  const port = await app.listen(0)
  try {
    const res = await post("http://127.0.0.1:" + port, {
      problemId: "self-00011",
      code: "int main(){}",
      language: "cpp",
    })
    assert.strictEqual(res.status, 400)
    const body = await res.json()
    assert.ok(body.error.indexOf("测试用例") !== -1, body.error)
  } finally {
    await app.close()
  }
})

test("编译错误：verdict 与编译器原文都回给前端", async function () {
  await withApp(async function (base) {
    const res = await post(base, {
      problemId: "self-00010",
      code: fs.readFileSync(manifest.CODE.cppCompileError, "utf8"),
      language: "cpp",
    })
    const body = await res.json()
    assert.strictEqual(body.verdict, "compile_error")
    assert.ok(body.compilerOutput.indexOf("error:") !== -1, body.compilerOutput)
    assert.ok(body.message.indexOf("第 4 行") !== -1, "要给出正确的错误行号：" + body.message)
  })
})

test("超时：settings 里的 judge.timeout_ms 生效", async function () {
  await withApp(async function (base, app) {
    app.store.setSetting("judge.timeout_ms", "800")
    const res = await post(base, {
      problemId: "self-00010",
      code: fs.readFileSync(manifest.CODE.cppTimeout, "utf8"),
      language: "cpp",
    })
    const body = await res.json()
    assert.strictEqual(body.verdict, "timeout")
    assert.ok(body.message.indexOf("800") !== -1, body.message)
  })
})

test("Python 提交走真实解释器，判为 pass", async function () {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-attempt-"))
  const dir = path.join(root, "bank", "fundamentals")
  fs.mkdirSync(dir, { recursive: true })
  fs.copyFileSync(manifest.PROBLEMS.pythonReverse, path.join(dir, "self-00011.md"))
  const app = createApp({ dbPath: ":memory:", learningRoot: root })
  const port = await app.listen(0)
  try {
    const res = await post("http://127.0.0.1:" + port, {
      problemId: "self-00011",
      code: fs.readFileSync(manifest.CODE.pythonOk, "utf8"),
      language: "python",
    })
    const body = await res.json()
    assert.strictEqual(body.verdict, "pass")
    assert.strictEqual(body.passedCases, 2)
    assert.ok(app.store.getSetting("judge.python.cmd"), "探测到的解释器要缓存进 settings")
  } finally {
    await app.close()
  }
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../judge/runner.js'`（api.js 里还没 require 它）

- [ ] **Step 3: 改写 server/api.js**

把 `projects/apps/algo-plan/server/api.js` 整体替换为：

```javascript
"use strict"
/**
 * api.js —— HTTP 接口层
 *
 * M1 三个接口：健康检查、题库列表、单题详情。
 * M3 加一个：POST /api/attempt —— 提交代码 → 真实编译执行 → 记流水。
 * 剩下的（推下一题、复习评分、轮次写回）属于 M4。
 *
 * 防作弊规则（设计文档 §7.2）：单题接口只返回前 2 个样例用例 + 用例总数，
 * 不返回全部用例、不返回参考解法。
 */

const { toSummary } = require("../core/bank/problem.js")
const { readJsonBody } = require("./router.js")
const { judge, LANGUAGES, DEFAULT_CASE_TIMEOUT_MS } = require("../judge/runner.js")
const { resolveToolchain } = require("../judge/sandbox.js")

/** 题面接口最多暴露几个样例用例 */
const SAMPLE_CASE_COUNT = 2

/** 作答模式 */
const ATTEMPT_MODES = ["solve", "review", "probe"]

/** settings 键：单用例超时（毫秒） */
const KEY_JUDGE_TIMEOUT = "judge.timeout_ms"

/** settings 键：探测出来的 Python 解释器（G17 的缓存位） */
const KEY_JUDGE_PYTHON = "judge.python.cmd"

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

  routes.push({
    method: "POST",
    pattern: "/api/attempt",
    handler: async function (req, res) {
      const body = await readJsonBody(req)

      const problemId = String(
        body.problemId === null || body.problemId === undefined ? "" : body.problemId
      ).trim()
      const code = String(body.code === null || body.code === undefined ? "" : body.code)
      const language = String(
        body.language === null || body.language === undefined ? "" : body.language
      ).trim().toLowerCase()
      const modeRaw =
        body.mode === null || body.mode === undefined || body.mode === ""
          ? "solve"
          : String(body.mode)

      if (problemId === "") {
        ctx.sendJson(res, 400, { error: "缺少 problemId" })
        return
      }
      if (ATTEMPT_MODES.indexOf(modeRaw) === -1) {
        ctx.sendJson(res, 400, { error: "mode 只能是 solve / review / probe", mode: modeRaw })
        return
      }
      if (LANGUAGES.indexOf(language) === -1) {
        ctx.sendJson(res, 400, { error: "不支持的语言：" + language, supported: LANGUAGES })
        return
      }
      if (code.trim() === "") {
        ctx.sendJson(res, 400, { error: "代码不能为空" })
        return
      }

      const problem = await ctx.provider.get(problemId)
      if (!problem) {
        ctx.sendJson(res, 404, { error: "题目不存在", id: problemId })
        return
      }
      if (!problem.cases || problem.cases.length === 0) {
        ctx.sendJson(res, 400, { error: "题目还没有测试用例，无法判题", id: problemId })
        return
      }

      // 单用例超时：默认 2000ms，可在 settings 里改
      const timeoutRaw = Number(
        ctx.store.getSetting(KEY_JUDGE_TIMEOUT, String(DEFAULT_CASE_TIMEOUT_MS))
      )
      const timeoutMs =
        Number.isFinite(timeoutRaw) && timeoutRaw > 0 ? timeoutRaw : DEFAULT_CASE_TIMEOUT_MS

      // 解释器：先按 settings 里的缓存试，不行再按 python3 → python → py -3 探测
      const pythonOverride = ctx.store.getSetting(KEY_JUDGE_PYTHON)
      const toolchain = resolveToolchain({ pythonOverride: pythonOverride })
      if (!pythonOverride && toolchain.python) {
        ctx.store.setSetting(
          KEY_JUDGE_PYTHON,
          toolchain.python.cmd +
            (toolchain.python.args.length ? " " + toolchain.python.args.join(" ") : "")
        )
      }

      const result = await judge({
        problem: problem,
        code: code,
        language: language,
        timeoutMs: timeoutMs,
        toolchain: toolchain,
      })

      const attemptId = ctx.store.insertAttempt({
        problem_id: problemId,
        ts: new Date().toISOString(),
        language: language,
        code: code,
        verdict: result.verdict,
        passed_cases: result.passedCases,
        total_cases: result.totalCases,
        duration_ms: result.durationMs,
        mode: modeRaw,
      })

      ctx.sendJson(res, 200, {
        attemptId: attemptId,
        verdict: result.verdict,
        passedCases: result.passedCases,
        totalCases: result.totalCases,
        durationMs: result.durationMs,
        failedCase: result.failedCase,
        message: result.message,
        compilerOutput: result.compilerOutput,
      })
    },
  })

  return routes
}

module.exports = {
  buildRoutes: buildRoutes,
  SAMPLE_CASE_COUNT: SAMPLE_CASE_COUNT,
  ATTEMPT_MODES: ATTEMPT_MODES,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `13 / 13 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加 POST /api/attempt 判题接口

- server/api.js：提交代码 → 真实编译执行 → 记 attempts 流水
- 入参 {problemId, code, language, mode}；mode 取 solve / review / probe
- 响应字段严格八个：attemptId/verdict/passedCases/totalCases/durationMs/failedCase/message/compilerOutput
- 参数校验：题目不存在 404、代码为空 400、语言不支持 400、mode 非法 400、题目没用例 400
- 判题超时读 settings 的 judge.timeout_ms，解释器缓存进 judge.python.cmd
- 测试：响应形状、流水落库、各类 400/404、超时、Python 提交共 10 条断言"
git push origin main
```

---

## Task 6: 结果面板（作答页 + 判题结果）

**Files:**
- Modify: `projects/apps/algo-plan/web/app.js`
- Modify: `projects/apps/algo-plan/web/style.css`
- Modify: `projects/apps/algo-plan/README.md`
- Create: `projects/apps/algo-plan/tests/web-panel.test.js`

**Interfaces:**
- Consumes: Task 5 的 `POST /api/attempt`（响应八字段）、M1 的 `GET /api/problem/:id` 与 `GET /api/bank`
- Produces:
  - `web/app.js` 导出（**仅在 Node 下**，浏览器里不挂全局）：
    - `describePanel(result) -> {verdict, tone, title, rows: [{label, value}], failed: {index, input, expected, actual}|null, compilerOutput}`
    - `truncate(text, limit) -> string`
    - 常量 `TONE_BY_VERDICT`、`PANEL_TEXT_LIMIT`
  - `web/app.js` 的新页面：**作答页**（题面 + 语言选择 + 代码框 + 提交按钮 + 结果面板），
    从「题库」列表的「作答」按钮进入
  - `web/style.css` 新增：代码框、原始输出块、提交按钮、表格内按钮的样式

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/web-panel.test.js`：

```javascript
"use strict"
/**
 * web-panel.test.js —— 结果面板的数据整理（纯函数，不碰 DOM）
 *
 * web/app.js 在 Node 下也能 require：文件末尾的 document / module 都做了存在性判断。
 */

const test = require("node:test")
const assert = require("node:assert")

const panel = require("../web/app.js")

test("五种 verdict 都有对应的面板色调", function () {
  const verdicts = ["pass", "wrong_answer", "timeout", "compile_error", "runtime_error"]
  verdicts.forEach(function (v) {
    assert.ok(panel.TONE_BY_VERDICT[v], v + " 缺色调")
    assert.ok(["ok", "bad", "warn"].indexOf(panel.TONE_BY_VERDICT[v]) !== -1, v + " 色调不合法")
  })
})

test("describePanel 给出用例数与耗时", function () {
  const p = panel.describePanel({
    verdict: "pass",
    passedCases: 3,
    totalCases: 3,
    durationMs: 123,
    message: "通过：全部 3 个用例通过",
    failedCase: null,
    compilerOutput: "",
  })
  assert.strictEqual(p.verdict, "pass")
  assert.strictEqual(p.tone, "ok")
  assert.strictEqual(p.title, "通过：全部 3 个用例通过")
  assert.deepStrictEqual(p.rows, [
    { label: "用例", value: "3 / 3 通过" },
    { label: "耗时", value: "123 ms" },
  ])
  assert.strictEqual(p.failed, null)
  assert.strictEqual(p.compilerOutput, "")
})

test("describePanel 把失败用例的期望与实际都带出来", function () {
  const p = panel.describePanel({
    verdict: "wrong_answer",
    passedCases: 0,
    totalCases: 3,
    durationMs: 20,
    message: "答案错误：第 1 个用例不通过：输出与期望不一致",
    failedCase: { index: 1, input: "4 2 7 11 15 9", expected: "0 1", actual: "0 0" },
    compilerOutput: "",
  })
  assert.strictEqual(p.tone, "bad")
  assert.strictEqual(p.failed.index, 1)
  assert.strictEqual(p.failed.expected, "0 1")
  assert.strictEqual(p.failed.actual, "0 0")
})

test("describePanel 带出编译错误原文", function () {
  const p = panel.describePanel({
    verdict: "compile_error",
    passedCases: 0,
    totalCases: 3,
    durationMs: 50,
    message: "编译失败：第 4 行：'undefined_function_call' was not declared in this scope",
    failedCase: null,
    compilerOutput: "main.cpp:4:5: error: 'undefined_function_call' was not declared in this scope",
  })
  assert.strictEqual(p.tone, "bad")
  assert.ok(p.compilerOutput.indexOf("main.cpp:4:5") !== -1, p.compilerOutput)
})

test("describePanel 对空结果不炸", function () {
  const p = panel.describePanel(null)
  assert.strictEqual(p.verdict, "")
  assert.strictEqual(p.tone, "")
  assert.strictEqual(p.failed, null)
  assert.deepStrictEqual(p.rows.length, 2)
})

test("超长输出会被截断并注明", function () {
  const long = "x".repeat(1000)
  const longer = "y".repeat(2000)
  const p = panel.describePanel({
    verdict: "wrong_answer",
    passedCases: 0,
    totalCases: 1,
    durationMs: 1,
    message: "答案错误",
    failedCase: { index: 1, input: "a", expected: "b", actual: long },
    compilerOutput: longer,
  })
  // 用例输出上限 400 字符，编译原文上限 1200 字符（PANEL_TEXT_LIMIT 的 3 倍）
  assert.ok(p.failed.actual.length < long.length, "实际输出应被截断")
  assert.ok(p.failed.actual.indexOf("已截断") !== -1, p.failed.actual)
  assert.ok(p.compilerOutput.length < longer.length, "编译原文应被截断")
  assert.ok(p.compilerOutput.indexOf("已截断") !== -1)
})

test("truncate 不动短文本", function () {
  assert.strictEqual(panel.truncate("abc", 10), "abc")
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `describePanel is not a function`

- [ ] **Step 3: 改写 web/app.js**

把 `projects/apps/algo-plan/web/app.js` 整体替换为：

```javascript
"use strict"
/**
 * app.js —— 前端逻辑（M3：今日页 + 题库页 + 作答页 + 判题结果面板）
 *
 * 原生 JS，无构建步骤。后续里程碑在这里接复习 / 轮次 / 诊断页。
 *
 * 判题契约（要显示给用户看）：
 *   提交的是完整的 stdin→stdout 程序，必须自己写 main()。
 *   系统不会替你生成入口，也不会注入 Solution 包装。
 */

/** verdict → 面板色调（与 judge/runner.js 的 VERDICT_PANEL.tone 对应） */
const TONE_BY_VERDICT = {
  pass: "ok",
  wrong_answer: "bad",
  timeout: "warn",
  compile_error: "bad",
  runtime_error: "bad",
}

/** 面板里期望/实际最多显示多少字符 */
const PANEL_TEXT_LIMIT = 400

/** 前端状态：当前正在作答的题目与语言 */
const state = {
  problemId: null,
  language: "cpp",
}

/** 当前视图：today / bank / practice */
let currentView = "today"

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

/** 提交 JSON，失败时抛出带中文说明的错误 */
async function postJson(url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error((data && data.error) || "请求失败：" + res.status)
  }
  return data
}

/** 截断过长文本并注明被截了多少 */
function truncate(text, limit) {
  const s = String(text === null || text === undefined ? "" : text)
  if (s.length <= limit) return s
  return s.slice(0, limit) + "\n…（已截断，原文共 " + s.length + " 字符）"
}

/**
 * 把判题结果整理成结果面板的数据（纯函数，不碰 DOM，便于单测）
 * @param {object} result POST /api/attempt 的响应
 */
function describePanel(result) {
  const r = result || {}
  const verdict = String(r.verdict || "")
  const failedCase = r.failedCase || null
  return {
    verdict: verdict,
    tone: TONE_BY_VERDICT[verdict] || "",
    title: String(r.message || ""),
    rows: [
      {
        label: "用例",
        value: String(r.passedCases || 0) + " / " + String(r.totalCases || 0) + " 通过",
      },
      { label: "耗时", value: String(r.durationMs || 0) + " ms" },
    ],
    failed: failedCase
      ? {
          index: failedCase.index,
          input: truncate(failedCase.input, PANEL_TEXT_LIMIT),
          expected: truncate(failedCase.expected, PANEL_TEXT_LIMIT),
          actual: truncate(failedCase.actual, PANEL_TEXT_LIMIT),
        }
      : null,
    compilerOutput: truncate(r.compilerOutput || "", PANEL_TEXT_LIMIT * 3),
  }
}

/** 渲染顶栏页签 */
function renderTabs() {
  const nav = document.getElementById("tabs")
  nav.textContent = ""
  const views = [
    { key: "today", label: "今日" },
    { key: "bank", label: "题库" },
    { key: "practice", label: "作答" },
  ]
  views.forEach(function (item) {
    const btn = document.createElement("button")
    btn.textContent = item.label
    if (item.key === currentView) btn.className = "active"
    btn.addEventListener("click", function () {
      currentView = item.key
      render()
    })
    nav.appendChild(btn)
  })
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

/** 渲染题库列表（每行带一个「作答」按钮） */
function renderBank(bank) {
  const items = (bank && bank.items) || []
  const rows = items.map(function (item) {
    const topics = (item.topics || []).map(function (t) {
      return el("span", { class: "badge", text: t })
    })
    const go = el("button", { text: "作答" })
    go.addEventListener("click", function () {
      state.problemId = item.id
      currentView = "practice"
      render()
    })
    return el("tr", {}, [
      el("td", { text: item.id }),
      el("td", { text: item.title }),
      el("td", { text: item.difficulty }),
      el("td", {}, topics),
      el("td", {}, [
        el("span", {
          class: item.needsFill ? "badge warn" : "badge",
          text: item.needsFill ? "待补全" : item.status,
        }),
      ]),
      el("td", {}, [go]),
    ])
  })
  return el("section", { class: "panel" }, [
    el("h2", { text: "题库（" + (bank ? bank.total : 0) + "）" }),
    items.length === 0
      ? el("p", {
          class: "muted",
          text: "题库还是空的。设置 ALGO_PLAN_LEARNING_ROOT 后运行 node tools/seed-bank.js 导入样板题。",
        })
      : el("table", {}, [
          el("thead", {}, [
            el("tr", {}, [
              el("th", { text: "ID" }),
              el("th", { text: "标题" }),
              el("th", { text: "难度" }),
              el("th", { text: "知识点" }),
              el("th", { text: "状态" }),
              el("th", { text: "操作" }),
            ]),
          ]),
          el("tbody", {}, rows),
        ]),
  ])
}

/** 渲染判题结果面板 */
function renderVerdictPanel(result) {
  const p = describePanel(result)
  const children = [
    el("h2", { text: p.title || "判题结果" }),
    el("div", { class: "kv" }, p.rows.map(function (row) {
      return el("div", {}, [
        document.createTextNode(row.label + "："),
        el("span", { text: row.value }),
      ])
    })),
  ]
  if (p.verdict) {
    children.push(el("span", { class: "badge " + (p.tone || ""), text: p.verdict }))
  }
  if (p.failed) {
    children.push(el("h2", { text: "失败用例" }))
    children.push(el("div", { class: "kv" }, [
      el("div", {}, [
        document.createTextNode("第 " + p.failed.index + " 个用例输入："),
        el("span", { text: p.failed.input }),
      ]),
      el("div", {}, [
        document.createTextNode("期望："),
        el("span", { text: p.failed.expected }),
      ]),
      el("div", {}, [
        document.createTextNode("实际："),
        el("span", { text: p.failed.actual }),
      ]),
    ]))
  }
  if (p.compilerOutput) {
    children.push(el("h2", { text: "编译 / 错误原文" }))
    children.push(el("pre", { class: "raw", text: p.compilerOutput }))
  }
  children.push(
    el("p", {
      class: "muted",
      text: "提示：判题不是安全沙箱，只防跑飞与死循环，不防恶意代码。",
    })
  )
  return el("section", { class: "panel" }, children)
}

/** 渲染作答页：题面 + 语言选择 + 代码框 + 提交按钮 + 结果面板 */
async function renderPractice() {
  const section = el("section", { class: "panel" })

  if (!state.problemId) {
    section.appendChild(el("h2", { text: "作答" }))
    section.appendChild(
      el("p", { class: "muted", text: "先在「题库」里点一道题的「作答」按钮。" })
    )
    return section
  }

  const problem = await getJson("/api/problem/" + encodeURIComponent(state.problemId))
  section.appendChild(el("h2", { text: problem.title + "（" + problem.id + "）" }))
  section.appendChild(el("pre", { class: "statement", text: problem.statement || "（题面为空）" }))
  section.appendChild(
    el("p", {
      class: "muted",
      text:
        "共 " +
        problem.cases.total +
        " 个用例，界面只展示前 " +
        problem.cases.sample.length +
        " 个样例（全部用例由服务端持有）。",
    })
  )

  const langSelect = el("select", { id: "judge-language" }, [
    el("option", { value: "cpp", text: "C++" }),
    el("option", { value: "python", text: "Python" }),
  ])
  langSelect.value = state.language
  langSelect.addEventListener("change", function () {
    state.language = langSelect.value
  })

  const editor = el("textarea", { id: "judge-code", rows: "18", spellcheck: "false" })
  const submit = el("button", { id: "judge-submit", text: "提交判题" })
  const resultBox = el("div", { id: "judge-result" })

  submit.addEventListener("click", async function () {
    submit.disabled = true
    submit.textContent = "判题中…"
    resultBox.textContent = ""
    try {
      const body = await postJson("/api/attempt", {
        problemId: state.problemId,
        code: editor.value,
        language: state.language,
        mode: "solve",
      })
      resultBox.appendChild(renderVerdictPanel(body))
    } catch (err) {
      resultBox.appendChild(
        el("section", { class: "panel" }, [
          el("h2", { text: "判题失败" }),
          el("p", { class: "error", text: String(err.message || err) }),
        ])
      )
    } finally {
      submit.disabled = false
      submit.textContent = "提交判题"
    }
  })

  section.appendChild(
    el("div", { class: "kv" }, [
      el("div", {}, [document.createTextNode("语言："), langSelect]),
    ])
  )
  section.appendChild(
    el("p", {
      class: "muted",
      text:
        "判题契约：提交的是完整的 stdin→stdout 程序，必须自己写 main()；" +
        "系统不会替你生成入口，也不会注入 Solution 包装。",
    })
  )
  section.appendChild(editor)
  section.appendChild(submit)
  section.appendChild(resultBox)

  return section
}

/** 主渲染 */
async function render() {
  const view = document.getElementById("view")
  view.textContent = ""
  renderTabs()
  try {
    if (currentView === "today") {
      view.appendChild(renderHealth(await getJson("/api/health")))
      view.appendChild(renderBank(await getJson("/api/bank")))
    } else if (currentView === "bank") {
      view.appendChild(renderBank(await getJson("/api/bank")))
    } else {
      view.appendChild(await renderPractice())
    }
  } catch (err) {
    view.appendChild(
      el("section", { class: "panel" }, [
        el("h2", { text: "加载失败" }),
        el("p", { class: "error", text: String(err.message || err) }),
      ])
    )
  }
}

if (typeof document !== "undefined") {
  document.addEventListener("DOMContentLoaded", function () {
    render()
  })
}

// Node 下（测试用）可以 require 本文件取纯函数；浏览器里不会执行这一段
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    describePanel: describePanel,
    truncate: truncate,
    TONE_BY_VERDICT: TONE_BY_VERDICT,
    PANEL_TEXT_LIMIT: PANEL_TEXT_LIMIT,
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node --check web/app.js && node tests/run-all.js
```

Expected: `node --check` 无输出；`14 / 14 套件通过`，退出码 0

- [ ] **Step 5: 给 web/style.css 补上面板样式**

在 `projects/apps/algo-plan/web/style.css` 的**末尾**追加：

```css
/* ---- M3：作答页与判题结果面板 ---- */
select {
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--line);
  border-radius: 6px;
  padding: 4px 8px;
}
textarea#judge-code {
  width: 100%;
  min-height: 320px;
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 12px;
  font: 13px/1.6 "Cascadia Mono", "Consolas", monospace;
  resize: vertical;
}
pre.statement, pre.raw {
  white-space: pre-wrap;
  word-break: break-word;
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 12px;
  margin: 0 0 12px;
  font: 13px/1.6 "Cascadia Mono", "Consolas", monospace;
}
button#judge-submit {
  margin: 10px 0 4px;
  padding: 8px 20px;
  border-radius: 8px;
  border: 1px solid var(--accent);
  background: var(--accent);
  color: #10131a;
  font-size: 14px;
  cursor: pointer;
}
button#judge-submit:disabled {
  opacity: 0.6;
  cursor: default;
}
td button {
  background: none;
  border: 1px solid var(--line);
  border-radius: 6px;
  color: var(--accent);
  padding: 2px 12px;
  font-size: 12px;
  cursor: pointer;
}
```

- [ ] **Step 6: 更新 README.md**

把 `projects/apps/algo-plan/README.md` 里的下面几段替换/插入（其余部分不动）：

**6.1** 把「当前进度」那一段替换为：

```markdown
当前进度：**M3 判题**（服务起得来 / SQLite schema / 题库 md 解析 / 真实编译执行的判题器 / 结果面板）。
题库导入属于 M2，复习与轮次闭环属于 M4，诊断属于 M5，LLM 属于 M6，尚未实现。
```

**6.2** 把「目录结构」代码块替换为：

````markdown
```
algo-plan/
├── core/            纯函数层：Problem 模型、markdown 解析、provider、路径解析
│   └── judge-spec/  判题契约纯函数：用例归一化、输出比对
├── server/          组合根、路由、API、SQLite 存储
├── judge/           判题执行器：沙箱（临时目录/探测/杀进程树）、编排器（verdict）
├── web/             原生 JS 单页（无构建）
├── tools/           seed-bank.js：把样板题导入 learning 仓
├── fixtures/        样板题 + 判题 fixture（题面、用例、正例与三类负例）
└── tests/           node:test 套件，一个命令跑全部
```
````

**6.3** 把「接口」表格替换为：

```markdown
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/health` | 运行状态、learning 仓连接情况、题库概况 |
| GET | `/api/bank` | 题库列表，支持 `track` / `topic` / `difficulty` / `status` / `prefix` / `limit` |
| GET | `/api/problem/:id` | 单题详情。**只回前 2 个样例用例 + 用例总数，不回参考解法** |
| POST | `/api/attempt` | 提交代码判题。入参 `{problemId, code, language, mode}`；响应 `{attemptId, verdict, passedCases, totalCases, durationMs, failedCase, message, compilerOutput}` |
```

**6.4** 在「题库格式」小节**之后**插入「判题契约」小节：

```markdown
## 判题契约

提交给判题器的是**完整的 stdin→stdout 程序，必须自己写 `main()`**。

- 判题器不注入 Solution 包装、不自动生成 `main()`、不猜方法名。
- C++ 走 `g++ -std=c++17 -O2`（不加 `-Werror`、不加 `-Wall`），Python 走
  `python3` → `python` → `py -3` 依次探测（第一个能 `--version` 的胜出）。
- 单用例默认超时 2000ms，超时杀整棵进程树（Windows `taskkill /T /F`，POSIX 进程组 kill）。
- verdict 只有五个：`pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error`。

**判题不是安全沙箱**：它防跑飞、死循环、爆内存、编译垃圾，**不防恶意代码**。
用户代码以当前用户权限在系统临时目录里跑，每题一个临时目录，判完即删。
```

**6.5** 把「测试」表格替换为：

```markdown
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
| `judge-spec.test.js` | 用例归一化、输出比对、容差比较 |
| `sandbox.test.js` | 工具链探测、临时目录、喂 stdin、超时杀进程树 |
| `judge-fixtures.test.js` | fixture 自检：正例对、三类负例确实坏 |
| `runner.test.js` | 五类 verdict 端到端、判题契约反例 |
| `attempt.test.js` | `POST /api/attempt` 的形状、校验、流水落库 |
| `web-panel.test.js` | 结果面板数据整理（纯函数） |
```

- [ ] **Step 7: 真起一次服务，人工看一眼页面**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning PORT=5173 node server/main.js
```

另开一个终端：

```bash
curl -s -X POST http://127.0.0.1:5173/api/attempt \
  -H "content-type: application/json" \
  -d '{"problemId":"self-00010","code":"#include <iostream>\nint main(){int n;std::cin>>n;std::cout<<n<<std::endl;return 0;}","language":"cpp","mode":"solve"}'
```

浏览器打开 `http://127.0.0.1:5173/`：

1. 顶栏出现「今日 / 题库 / 作答」三个页签
2. 点「题库」→ 找到 `self-00010` → 点「作答」
3. 作答页有题面、语言下拉、代码框、「提交判题」按钮
4. 把下面的代码粘进代码框点提交 → 面板显示「答案错误」并列出期望 vs 实际：

```cpp
#include <iostream>
int main() { std::cout << "0 0" << std::endl; return 0; }
```

5. 换成下面这段再提交 → 面板显示「通过：全部 3 个用例通过」：

```cpp
#include <iostream>
#include <vector>
using namespace std;
int main() {
    int n;
    if (!(cin >> n)) return 0;
    vector<int> nums(n);
    for (int i = 0; i < n; ++i) cin >> nums[i];
    int target;
    cin >> target;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            if (nums[i] + nums[j] == target) { cout << i << " " << j << endl; return 0; }
        }
    }
    cout << "-1 -1" << endl;
    return 0;
}
```

> `self-00010` 要是还没导入 learning 仓，先做 Task 3 的 Step 7。

- [ ] **Step 8: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加作答页与判题结果面板

- web/app.js：顶栏页签（今日/题库/作答）、题库行的作答按钮、作答页
- 结果面板展示 verdict、用例数、耗时、失败用例的期望 vs 实际、编译错误原文
- describePanel 是纯函数，在 Node 下可直接单测；长输出按 400 字符截断
- 面板上写明判题契约：必须自己写 main()，系统不注入 Solution 包装
- 面板上写明判题不是安全沙箱，只防跑飞不防恶意代码
- web/style.css：代码框、原始输出块、提交按钮、表格按钮样式
- README：补判题契约小节、新接口、新测试套件
- 测试：面板数据整理 7 条断言"
git push origin main
```

- [ ] **Step 9: 更新父仓的 submodule 指针**

M3 的代码在 `projects` 子模块里，父仓 `StillEvolving` 记的是子模块指针，要跟着更新：

```bash
cd /c/code/StillEvolving
git add projects
git commit -m "chore(submodule): 更新 projects 子模块指针（algo-plan M3 判题）"
git push origin main
```

---

## M3 验收清单

全部满足才算 M3 完成：

| # | 验收项 | 怎么验 |
|---|---|---|
| 1 | 服务起得来 | `node server/main.js` 打印启动地址 |
| 2 | 测试全绿 | `node tests/run-all.js` → `14 / 14 套件通过` |
| 3 | 零 npm 依赖 | `package.json` 无 `dependencies`；`node_modules/` 不存在 |
| 4 | 五类 verdict 都真跑出来 | `runner.test.js` 里 `pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error` 各有断言，且都真编译真执行 |
| 5 | 判题契约写死 | 作答页与 README 的「判题契约」都写明「必须自己写 `main()`」；`class Solution` 反例被判 `compile_error` |
| 6 | 超时能杀整棵进程树 | `sandbox.test.js` 的孙进程用例：超时后日志文件不再增长 |
| 7 | 临时目录判完即删 | `runner.test.js` 断言 sandbox 目录已不存在 |
| 8 | 解释器不写死 | 本机 `python3` 是 Store 占位符，`detectPython()` 必须选到 `python` / `py -3` |
| 9 | 结果面板信息齐 | 面板显示 verdict、用例通过数、耗时、失败用例的期望 vs 实际、编译错误原文与行号 |
| 10 | 不泄露答案 | 单题接口响应里搜不到参考解法（沿用 M1 G14） |
| 11 | 不自动 commit | `git -C learning status` 无自动提交；判题只在系统临时目录里写文件 |

---

## 后续里程碑备忘（M4–M6，写计划时直接用）

### M4 闭环

- **`attempts` 表已经被 M3 写起来了**：M1 建的 schema 是
  `attempts(id, problem_id, ts, language, code, verdict, passed_cases, total_cases, duration_ms, mode)`，
  M3 每次 `POST /api/attempt` 落一行，`mode` 存请求里的 `solve` / `review` / `probe`。
  M4 做 SM-2 时**直接读这十列**，不用另建表。
- **verdict ↔ SM-2 quality 的映射还没定，那是 M4 的活**。M3 只保证 verdict 是契约里那五个字符串，
  M4 要把它们映射到 `knowledge-hub/core/review.js` 的 5 档 quality：
  `pass` → 高档；`wrong_answer` → 中档（思路对、边界错）；
  `compile_error` / `runtime_error` → 低档（代码根本没跑起来）；
  `timeout` → 低档（可能死循环）。
  注意 `calculateNextReview` 的语义：`quality < 3` 会把间隔重置为 1、`repetitions` 归 0。
- **M3 立的两个 settings 键**：`judge.timeout_ms`（单用例超时，默认 `2000`）与
  `judge.python.cmd`（探测到的解释器缓存，值是字符串）。M4 写回 learning 仓时**不要碰这两个键**。
- **没有用例的题判不了**：M3 的 `POST /api/attempt` 对 0 用例的题返回 **400**。
  M1 的题库 md 里没写用例的题不少，M4 的「推下一题」必须**跳过没有用例的题**（或先补用例），
  否则复习轮次会一直撞 400。
- **`failedCase` 只带第一个失败用例**（`{index, input, expected, actual}`），不是全部用例的 diff。
  M4/M5 要做「多用例全量 diff」得自己再跑一次判题。
- **写回 learning 仓依然不自动 commit**（G11）；M3 已经把这条规矩写进 README 了。

### M5 诊断

- **M3 的 verdict 是最细的一层分类**：`pass` / `wrong_answer` / `timeout` / `compile_error` / `runtime_error`，
  再往下就是 `passed_cases / total_cases` 的比例。M5 的掌握度模型可以直接用这两个数当连续特征，
  不用重跑判题。
- **`duration_ms` 已经落在 `attempts` 表里**，M5 想做「耗时是否异常」的诊断直接聚合这张表。
- **`compilerOutput` 与 `message` 是分开的两份东西**：`compilerOutput` 是编译器/解释器的原始输出，
  `message` 是拼好中文文案的那一行（编译错误里已经带行号，形如 `编译失败：第 4 行：...`）。
  M5 的诊断页想显示原文就用 `compilerOutput`，想让 LLM 读就两个一起给。
- **G22（零第三方图表）**：M5 的图表必须手写 SVG，不要引 Chart.js 之类。

### M6 LLM

- **`POST /api/attempt` 的响应八字段已经冻结**：
  `attemptId, verdict, passedCases, totalCases, durationMs, failedCase, message, compilerOutput`。
  LLM 的「讲解 / 求助」功能直接拿这八个字段当上下文（尤其是 `failedCase.expected`、
  `failedCase.actual` 与 `compilerOutput`），**不要再改这个响应形状**。
- **判题契约对 LLM 同样成立**：LLM 生成的代码也是完整的 stdin→stdout 程序、也要自己写 `main()`。
  提示词里必须写死这条，否则模型会习惯性地只写 `class Solution`。
- **`judge/runner.js` 的 `VERDICT_PANEL` 是中文文案的唯一出处**，前端不许另写一份。
  LLM 生成的文案要统一语气也从这里取。
- **M3 没有引入任何 LLM provider 抽象**：M1 的 `core/bank/provider.js` 是**题库**的 provider
  （读写 `learning/bank/`），跟 LLM 没关系。M6 要另起一个 LLM provider，别混进 `core/bank/`。

---

## 执行提示

- 本计划只改 `projects/` 子模块（`projects/apps/algo-plan/`）。
  `learning/` 子模块只被读取（Task 3 的一次性导入是人工动作，判题全过程只写系统临时目录）。
- 每个 Task 结束都有「提交并推送」，Task 6 额外提醒更新父仓的 submodule 指针。
- 判题测试**依赖本机的 `g++` 与 Python**，换机器跑要先确认 `detectCompiler()` / `detectPython()` 能探到。
- 计划写完了，不要在没跑通测试前合并。

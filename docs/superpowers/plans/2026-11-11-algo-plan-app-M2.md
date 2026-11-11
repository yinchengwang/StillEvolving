# 算法能力提升计划 App —— M2 题库实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 M2 里程碑——把题库填满：复活 `projects/scripts/` 里三个死脚本的内联题目清单，导入 `learning/` 里的存量题解，全部落成 `learning/bank/<track>/<id>.md` 的题库文件，让 `GET /api/bank` 真的有几百道题可列。

**Architecture:** 两层。新增 `core/bank/legacy.js` 与 `core/bank/solutions-scan.js` 两个**纯函数层**模块：只吃字符串、不碰磁盘，可以脱离 IO 单测；新增 `tools/import-catalog.js` 与 `tools/import-solutions.js` 两个**导入器**：读源码 → 调纯函数 → 用 M1 的 `serializeProblemMarkdown` 写成题库文件。三个死脚本**绝不执行**，只做静态解析。

**Tech Stack:** Node.js ≥ 24（内置 `node:fs` / `node:path` / `node:test`）、CommonJS、零 npm 依赖、零构建。

**Spec:** `docs/superpowers/specs/2026-11-10-algo-plan-app-design.md`（本计划只覆盖其中 §10 的 **M2**，题库来源对应 §3.5 的 **B 路（复活死代码）** 与 **C 路（存量题解）**）

**接口契约:** `docs/superpowers/plans/2026-11-11-algo-plan-app-接口契约.md`（§0 M1 已冻结的导出、§1 M2 新增、§6 G17–G22、§7 写作规范）

**代码位置:** `projects/apps/algo-plan/`（在 `projects` 子模块里，提交与推送都在该子模块进行）；导入产物落在 `learning/bank/`（学习仓，**只写不提交**）

---

## Global Constraints

以下约束对**每一个** task 生效，写代码时不要违反。

### 继承自 M1 的 G1–G16（继续生效，不许放宽）

| # | 约束 | 精确值 |
|---|---|---|
| G1 | **零 npm 依赖** | 只用 Node 内置模块。不许 `npm install` 任何包 |
| G2 | **零构建** | 前端是原生 JS + HTML + CSS。不用 webpack/vite/esbuild，不用 TypeScript |
| G3 | **Node 版本下限** | ≥ 24。本机实测 `v24.17.0` |
| G4 | **注释与提交信息用中文** | 沿用 `projects/CLAUDE.md` |
| G5 | **提交即推送** | 每个 commit 完成后立刻 `git push origin main` |
| G6 | **产物路径** | 全部代码在 `projects/apps/algo-plan/`。**不要**在 `projects/` 根目录放新文件 |
| G7 | **learning 仓路径不硬编码** | 只认环境变量 `ALGO_PLAN_LEARNING_ROOT`。取不到就降级为「纯本地模式」 |
| G8 | **稳定题目 ID** | 格式 `<前缀>-<5 位数字>`，前缀：`leetcode→lc` / `nowcoder→nc` / `jz→jz` / `self→self` / `llm→llm`。是 git 侧与 SQLite 侧的唯一连接键 |
| G9 | **测试入口** | `node tests/run-all.js` 跑全部套件，自动发现 `tests/*.test.js` |
| G10 | **中文输出** | 面向用户的文案（错误提示、命令输出）全部中文 |
| G11 | **不自动 commit** | 导入器写回 learning 仓后**绝不**执行 `git commit`/`git push` |
| G12 | **运行产物不入库** | SQLite 落在 `projects/apps/algo-plan/data/app.db` |
| G13 | **题库目录容错** | `learning/bank/` 目录缺失时 provider 容忍：list 返回空数组、get 返回 undefined |
| G14 | **防作弊** | 单题接口默认只返回前 **2** 个样例用例 + 用例总数，不返回全部用例、不返回参考解法 |
| G15 | **SQL 类型** | `node:sqlite` 只接受 `null`/`number`/`bigint`/`string`/`Uint8Array` |
| G16 | **node:sqlite 导入** | `const { DatabaseSync } = require("node:sqlite")` |

### 契约 §6 里 M2–M6 共用的 G17–G22

| # | 约束 | 精确值 |
|---|---|---|
| G17 | **判题解释器不写死** | 按 `python3` → `python` → `py -3` 依次探测（M3 用，M2 只继承不实现） |
| G18 | **判题契约** | 「stdin 进、stdout 出」的裸程序（M3 用，M2 只继承不实现） |
| G19 | **导入 id 冲突** | 同 id 已存在则跳过并计入 `skipped`；只有 `force` 才覆盖 |
| G20 | **写回前查脏** | `git -c core.quotepath=false status --porcelain -z`，按 NUL 切分（M4 用，M2 只继承不实现） |
| G21 | **轮次解析容错** | 按列名关键词匹配，坏行跳过并计告警（M4 用，M2 只继承不实现） |
| G22 | **零第三方图表** | 雷达图、曲线一律手绘 SVG（M5 用，M2 只继承不实现） |

### M2 自己的 G23–G30

| # | 约束 | 精确值 |
|---|---|---|
| G23 | **绝不执行死脚本** | 三个死脚本只做**静态解析**。原因：`gen-practice-data.js` 里 6 处题号写成了未定义标识符（`offer22`/`offer18`/`deleteNode`/`offer23`/`offer09`/`offer30`），真跑会 `ReferenceError`；三个脚本还都读已删除的 `project/reading-radar/data/app/practice-data.js`，真跑会 `ENOENT` |
| G24 | **只写 `learning/bank/<track>/<id>.md`** | `learning/.gitignore` 忽略了 `data/`，**不要**建 `learning/bank/data/`。轨道目录只有 `interview` / `fundamentals` / `advanced` / `engineering` 四个 |
| G25 | **导入的题一律 `needsFill: true`** | 死脚本与存量题解**都没有题面与测试用例**，导入后必然缺内容 |
| G26 | **难度只有 easy / medium** | 实测死脚本里只有 `easy` 与 `medium`，**没有 hard**。存量题解查不到难度时默认 `medium`，不许造 `hard` |
| G27 | **id 冲突跳过，`--force` 才覆盖** | 已有同名文件 → 计入 `skipped` 并原样保留；`--force` 才覆盖写入 |
| G28 | **dry-run 不落盘** | `--dry-run` 只报告将要写哪些文件，一个字节都不写 |
| G29 | **纯函数层不碰 IO** | `core/bank/legacy.js` 与 `core/bank/solutions-scan.js` 不出现 `require("node:fs")`，输入输出全是字符串与普通对象 |
| G30 | **导入器不碰 learning 的 git** | 导入器不执行任何 git 命令，不提交 learning 仓。是否提交由人决定 |

---

## M2 的边界

设计文档 §10 的分期：

| 阶段 | 交付 | 本计划 |
|---|---|---|
| M1 骨架 | 服务起得来、SQLite schema、题库 md 解析、页面壳 | ✅ 已由 M1 计划交付 |
| **M2 题库** | **复活三个死脚本 + 存量题解导入** | ✅ **本计划** |
| M3 判题 | C++/Python 判题器 + verdict + 结果面板 | ❌ 另出计划 |
| M4 闭环 | 轮次 + 推下一题 + SM-2 复习 + 写回 md | ❌ 另出计划 |
| M5 诊断 | 掌握度模型 + 诊断页 | ❌ 另出计划 |
| M6 LLM | provider + 讲解/求助/造题/补全缺口 | ❌ 另出计划 |

**M2 做完的验收线：** `node tools/import-catalog.js` 与 `node tools/import-solutions.js` 能把题库填满
（`node tools/import-bank.js` 是把这两个按「先目录、后题解」串起来的一次性入口），
`learning/bank/<track>/` 下有几百个 `<id>.md`，`GET /api/bank` 返回的 `total` 跟落盘文件数对得上，
`node tests/run-all.js` 全绿。**判题、复习、轮次、诊断、LLM 一概不碰。**

**本计划明确不做的事：**

- 不造题（LLM 造题是 M6）
- 不补题面与测试用例（缺的就是缺的，靠 `needsFill: true` 标记，交给 M6 或人工）
- 不改 `learning/algo-c/*/README.md` 里那两张**坏掉的相对链接**（M1 勘察备忘提到「M2 可以顺手修」，
  但那是 learning 仓的文档维护，会额外产生一个需要人审阅的 diff；本计划只在 README 索引里**读**它们，不改它们）
- 不碰 `learning/algo-c/contest/` 与 `learning/algo-c/bit_operations/impl/`（不是 LeetCode 题，见勘察）
- 不做增量更新（每次导入都是全量扫描 + 冲突跳过；靠 `--force` 重来）

---

## 实地勘察（2026-11-11，全部读的是真实文件）

> 这一节是本计划的**事实基座**。下面的每一条都来自实际读过的文件，不是推测。
> 读不出来的地方写处理规则，不编数字。

### 一、三个死脚本的真实结构

三个脚本都在 `projects/scripts/`，**全部是 CommonJS、无 npm 依赖**，但**全部已经跑不起来**。

#### 1.1 `projects/scripts/gen-practice-data.js`（451 行）

文件开头的两个工厂函数（逐字引用，第 6–23 行）：

```javascript
function lc(title, id, diff, tags) {
  return {
    title,
    platform: "leetcode",
    problemId: id,
    difficulty: diff,
    tags: Array.isArray(tags) ? tags : [tags],
  };
}
function jz(title, id, diff, tags) {
  return {
    title: "剑指 Offer " + id + ". " + title,
    platform: "nowcoder",
    problemId: "" + id,
    difficulty: diff,
    tags: Array.isArray(tags) ? tags : [tags],
  };
}
```

**由此确定的事实：**

- 平台字面量只有两个：`"leetcode"` 与 `"nowcoder"`（**没有** `"jz"`）。
- `jz()` 的 `problemId` 是**字符串** `"JZ03"` 这种形式；`lc()` 的 `problemId` 是**数字** `1`。
- `jz()` 的标题在**运行时**才拼上 `"剑指 Offer " + id + ". "` 前缀——源码里的字面量是裸标题。
- 难度字面量只有 `"easy"` 与 `"medium"`。
- `tags` 是中文标签数组，形如 `["哈希表"]`、`["双指针", "从后往前"]`。

三个辅助函数（第 26–57 行）：

```javascript
function markRepeat(items) {
  items.forEach(function (item) {
    var key =
      item.platform === "leetcode"
        ? "lc:" + item.problemId
        : "jz:" + item.problemId;
    if (EXISTING.has(key)) item.repeat = true;
    EXISTING.add(key);
  });
  return items;
}
function dedup(items) {
  var seen = {};
  return items.filter(function (item) {
    var key = item.platform + ":" + item.problemId;
    if (seen[key]) {
      item.repeat = true;
      return false;
    }
    seen[key] = true;
    return true;
  });
}
function cat(id, title, phase, order, icon, desc, items) {
  items = dedup(items.sort(byDiff));
  markRepeat(items);
  return { id, title, phase, order, icon, desc, items };
}
```

**由此确定的事实：**

- **重复标记就是 `repeat: true`**（布尔字段），出现在被 `markRepeat` 标过的条目上。
- `dedup` 把**同分类内**的重复条目**剔除**（并标 `repeat: true`）；`markRepeat` 把**跨分类**的重复条目**标出来但保留**。
- 所以：**一道题出现在多个分类里时，原始数据里会有多条 `repeat: true` 的记录**。

题目清单是**字面量数组变量**（不是函数返回值），第 62 行起：

```javascript
var arrayItems = [
  lc("两数之和", 1, "easy", ["哈希表"]),
  lc("移除元素", 27, "easy", ["双指针"]),
  lc("搜索插入位置", 35, "easy", ["二分查找"]),
  ...
  jz("数组中重复的数字", "JZ03", "easy", ["哈希表"]),
  ...
];
```

分类数组在第 351 行起，形状是 `cat(slug, 中文标题, phase, order, icon, desc, items变量)`：

```javascript
var categories = [
  cat(
    "array",
    "数组",
    1,
    1,
    "📗",
    "数组是最基本的数据结构，连续内存存储、随机访问 O(1)。",
    arrayItems,
  ),
  cat(
    "string",
    "字符串",
    ...
```

**这个脚本里有 6 处题号写成了未定义标识符**（第 243/245/247/269/287/313 行），
直接执行必然 `ReferenceError`：

| 行号 | 原文 | 未定义标识符 |
|---|---|---|
| 243 | `lc("链表中倒数第k个节点", offer22, "easy", ["快慢指针"]),` | `offer22` |
| 245 | `lc("删除链表的节点", offer18, "easy", ["链表"]),` | `offer18` |
| 247 | `lc("删除中间节点", deleteNode, "easy", ["链表"]),` | `deleteNode` |
| 269 | `lc("链表中环的入口节点", offer23, "medium", ["快慢指针"]),` | `offer23` |
| 287 | `lc("化栈为队", offer09, "easy", ["设计"]),` | `offer09` |
| 313 | `lc("最小值栈", offer30, "easy", ["设计"]),` | `offer30` |

**处理规则：** 这 6 条**跳过并计入告警**，不做任何猜测（不猜它是 22 还是别的）。

#### 1.2 `projects/scripts/expand-practice.js`（1392 行）

第 40–57 行有**同样两个工厂函数** `lc()` / `jz()`（`lc` 的 `problemId` 写成 `Number(id)`，`jz` 写成 `String(id)`），
第 63 行起是：

```javascript
function addProblems(catId, newItems) {
  var cat = cats.filter(function (c) {
    return c.id === catId;
  })[0];
  ...
}
```

调用点形状是 `addProblems("slug", [ ... ])`，第 104 行起：

```javascript
// 1.1 数组
addProblems("array", [
  lc("合并两个有序数组", 88, "easy", ["双指针"]),
  lc("杨辉三角", 118, "easy", ["模拟"]),
  ...
]);
```

**注意：这个脚本里 `addProblems()` 一共出现了 69 次，其中 5 个 slug（`array`/`string`/`linked-list`/`stack`/`queue`）
出现了多次**——同一分类会被追加好几批题目。所以解析时**必须按 slug 合并**，不能一个调用当一个分类。

#### 1.3 `projects/scripts/split-practice-data.js`（97 行）

**这个脚本里没有任何内联题目清单。** 它只做两件事：读已删除的 `practice-data.js`，按分类拆成一个个文件：

```javascript
var SRC = path.resolve(
  __dirname,
  "..",
  "project",
  "reading-radar",
  "data",
  "app",
  "practice-data.js",
);
var src = fs.readFileSync(SRC, "utf-8");
```

它的 `serialize()` 函数倒是**确认了落盘数据的字段形状**：

```javascript
      s += "      title: " + JSON.stringify(it.title) + ",\n";
      s += "      platform: " + JSON.stringify(it.platform) + ",\n";
      s += "      problemId: " + ... + ",\n";
      s += "      difficulty: " + JSON.stringify(it.difficulty) + ",\n";
      s += "      tags: " + JSON.stringify(it.tags || []) + ",\n";
      if (it.repeat) s += "      repeat: true,\n";
      if (it.url) s += "      url: " + JSON.stringify(it.url) + ",\n";
```

**处理规则：** `split-practice-data.js` 解析出 0 个分类 → **记一条告警，不算错误**（它本来就不含清单，
只是「按分类拆文件」的工具，题目清单由前两个脚本提供）。

#### 1.4 实测数字（2026-11-11 用一个只读探针统计得到）

| 项 | 数值 |
|---|---|
| `gen-practice-data.js` 的 `cat()` 调用数 | 5（`array`/`string`/`linked-list`/`stack`/`queue`） |
| `gen-practice-data.js` 的 `var` 数组 | 6（`arrayItems`/`stringItems`/`linkedListItems`/`stackItems`/`queueItems`/`categories`） |
| `expand-practice.js` 的 `addProblems()` 调用数 | 69 |
| 解析出的分类条目合计 | 74（去重后 **25 个 slug**） |
| `lc()`/`jz()` 调用总数 | **1247** |
| 题号不可用（未定义标识符）被跳过 | **6** |
| 可用条目 | **1241** |
| 按 `(platform, problemId)` 去重后的**题目数** | **672** |
| 其中 leetcode / nowcoder | **615 / 57** |
| 其中 easy / medium | **253 / 419**（**没有 hard**） |
| 出现在多个分类里的题 | **378** |
| 原始中文标签写法 | **78 种** |

`nowcoder` 的 57 道题题号全部是 `JZxx` 形式（`JZ03`…`JZ77`），**没有一个是纯数字题号**。

### 二、存量题解的真实结构

`learning/` 下有两种**完全不同**的题解命名形态。

#### 2.1 区间文件 + 标记注释（`learning/code-solutions/c/src/`）

`learning/code-solutions/c/src/README.md` 写明了规则：

> - `c/` — C 语言实现，文件按题号范围命名（如 `leetcode_1_100.c`、`leetcode_2000_2100.c`）
> - `cpp/` — C++ 实现（子目录）
>
> 文件名格式：`leetcode_<start>_<end>.c`（或 `.cpp`）。

实测：`c/` 下 14 个文件、`cpp/` 下 11 个文件，**共 25 个**（外加 `CMakeLists.txt`）。

**定位题目的注释长这样**（`c/leetcode_1_100.c` 第 1–8 行，逐字）：

```c
#include <stdlib.h>
#include <math.h>

#include "common.h"

// leetcode 56

int **merge(int **intervals, int intervalsSize, int *intervalsColSize, int **returnColumnSizes)
```

`cpp/leetcode_1_100.cpp` 里标记后面**还带解法说明**（逐字）：

```cpp
#include "leetcode/leetcode_cpp.h"

// leetcode 1 枚举法
vector<int> LeetCode_Solution::twoSumEnum(vector<int>& nums, int target) {
```

**实测统计：**

| 项 | 数值 |
|---|---|
| 有 `// leetcode <题号>` 标记的文件 | 9 |
| 标记总数 | 21 |
| **去重后的题号** | **19**（`1,2,3,4,5,6,7,8,9,10,56,75,118,231,1323,2048,2348,3169,3452`） |
| 标记后带解法说明的 | 10 处（如 `// leetcode 1 hash map`） |

**两个必须跳过的文件：**

- `c/interview_17.c` 与 `cpp/interview_17.cpp`：里面的标记是 `// 17.14` 这种**面经章节号**，不是 LeetCode 题号。
- 区间文件里**一个标记都没有**的（如 `leetcode_1300_1400.c` 之外的若干文件）：跳过并记告警。

#### 2.2 单题文件（`learning/algo-c/`）

实测 `learning/algo-c/` 下有 4 个目录：`bit_operations/`、`contest/`、`prefix_sum/`、`problems/`、`sliding_window/`。

- `algo-c/problems/`：**8 个目录，一题一文件**，文件名就是题号：
  `leetcode_1455/leetcode_1455.cpp`、`leetcode_2070/leetcode_2070.c`、`leetcode_2512/leetcode_2512.cpp`、
  `leetcode_3138/leetcode_3138.c`、`leetcode_326/leetcode_326.cpp`、`leetcode_3280/leetcode_3280.c`、
  `leetcode_624/leetcode_624.cpp`、`leetcode_729/leetcode_729.cpp`
- `algo-c/<专题>/problems/`：**4 个文件**，在专题目录下：
  `sliding_window/problems/1984_minimum_difference/leetcode_1984.cpp`、
  `sliding_window/problems/2270_ways_to_split/leetcode_2270.cpp`、
  `sliding_window/problems/3297_count_matching/leetcode_3297.cpp`、
  `prefix_sum/problems/3159_query_results/leetcode_3159.cpp`

单题文件的内容长这样（`algo-c/problems/leetcode_1455/leetcode_1455.cpp` 第 1–12 行，逐字）：

```cpp
#include <iostream>
#include <string>
using namespace std;

class Solution {
public:
    bool isPrefix(string sentence, int start, int end, string searchWord)
    {
        for (int i = 0; i < searchWord.size(); i++) {
```

**注意：单题文件里没有 `// leetcode` 标记，题号只能从文件名读。**

#### 2.3 必须跳过的两处

| 路径 | 为什么跳过 |
|---|---|
| `learning/algo-c/contest/**`（5 个文件，如 `contest/Biweekly_match/148/148_1/148_1.cpp`、`contest/Weekly_match/433/433_1.cpp`） | 文件名不是 `leetcode_<题号>` 约定；首行注释是中文标题（`// 循环数组中相邻元素的最大差值`）但没有可靠的题号来源 |
| `learning/algo-c/bit_operations/impl/state_compression.c` | 是「状态压缩技法演示」文档式代码，不是题目 |

**处理规则：** 收录范围 = **文件基名匹配 `leetcode_<题号>.<ext>` 或 `leetcode_<起>_<止>.<ext>`** 的 `.c`/`.cpp` 文件。
其余文件一律跳过并记一条告警（告警里写明路径与跳过原因）。

#### 2.4 存量题解的总账

| 项 | 数值 |
|---|---|
| `code-solutions` 区间文件里的**去重题号** | 19 |
| `algo-c/problems/` 单题 | 8 |
| `algo-c/<专题>/problems/` 单题 | 4 |
| **合计去重题目** | **31** |
| 其中与死脚本清单**同 id** 的 | **16**（`lc-00001`…`lc-00009`、`lc-00056`、`lc-00075`、`lc-00118`、`lc-00231`、`lc-00326`、`lc-00729`、`lc-01455`） |

### 三、`learning/algo-c/*/README.md` 的索引表

两张表的表头**逐字**都是 `| 题号 | 题目 | 难度 |`：

`learning/algo-c/sliding_window/README.md` 结尾：

```markdown
## LeetCode 题目

| 题号 | 题目 | 难度 |
|------|------|------|
| 1984 | [学生分数的最小差值](../1984_minimum_difference/) | 简单 |
| 2270 | [分割数组的方案数](../2270_ways_to_split/) | 中等 |
| 3297 | [统计相似字符串对的数目](../3297_count_matching/) | 简单 |
```

`learning/algo-c/prefix_sum/README.md` 结尾：

```markdown
| 题号 | 题目 | 难度 |
|------|------|------|
| 3159 | [查询运算后球的价值](../3159_query_results/) | 中等 |
```

**由此确定的事实：**

- 难度是**中文**：`简单` / `中等`。
- 相对链接**是坏的**（少了 `problems/` 一层）——本计划只读不修。
- 这 4 个题号**正好就是** `algo-c/<专题>/problems/` 下那 4 个文件——索引表就是那 4 道题的题名与难度来源。

### 四、`learning/.gitignore` 的真实规则

```
# 测试与运行时数据
test-results/
*.db
*.db.wal
*.db.bin
test_dir/
test_data/
data/
```

**`data/` 被忽略**（第 36 行）⇒ 题目文件**只能**放 `learning/bank/<track>/<id>.md`，
**不要**建 `learning/bank/data/`（G24）。

---

## 25 个分类 slug → 四条轨道的映射表

设计文档有四条轨道（`interview` / `fundamentals` / `advanced` / `engineering`），
**死脚本里没有这条映射**，必须自己定。下表是本计划钉死的映射，写进 `core/bank/legacy.js` 的
`CATEGORY_TRACK_MAP`（**25 个 slug 全覆盖**，缺一个 `mapCategoryToTrack` 就落到 `interview` 并计告警）。

| # | slug | 轨道 | 归类理由 | 题数 |
|---|---|---|---|---|
| 1 | `array` | fundamentals | 数组是最基础的数据结构 | 126 |
| 2 | `string` | fundamentals | 字符串是基础容器 | 73 |
| 3 | `linked-list` | fundamentals | 链表是基础链表结构 | 37 |
| 4 | `stack` | fundamentals | 栈是基础数据结构 | 35 |
| 5 | `queue` | fundamentals | 队列是基础数据结构 | 27 |
| 6 | `sorting` | fundamentals | 排序是基础算法 | 16 |
| 7 | `binary-tree` | fundamentals | 二叉树是树形结构的基础形态 | 41 |
| 8 | `bst` | fundamentals | 二叉搜索树是树形结构的基础形态 | 18 |
| 9 | `heap` | fundamentals | 堆是基础容器 | 17 |
| 10 | `bit-manipulation` | fundamentals | 位运算基础技巧 | 16 |
| 11 | `two-pointers` | interview | 面试高频双指针套路 | 10 |
| 12 | `sliding-window` | interview | 面试高频滑动窗口套路 | 10 |
| 13 | `prefix-sum` | interview | 面试高频前缀和套路 | 8 |
| 14 | `hash-table` | interview | 面试高频哈希套路 | 19 |
| 15 | `binary-search` | interview | 面试高频二分套路 | 25 |
| 16 | `dfs` | interview | 面试高频深搜套路 | 14 |
| 17 | `bfs` | interview | 面试高频广搜套路 | 8 |
| 18 | `backtracking` | interview | 面试高频回溯套路 | 20 |
| 19 | `interview-classic` | interview | 面经经典题，天然面试向 | 44 |
| 20 | `greedy` | advanced | 贪心需要证明，入门到进阶 | 20 |
| 21 | `dp-basic` | advanced | 基础 DP 是进阶题型 | 18 |
| 22 | `dp-advanced` | advanced | 进阶 DP | 23 |
| 23 | `union-find` | advanced | 并查集偏进阶 | 15 |
| 24 | `graph` | advanced | 图论偏进阶 | 14 |
| 25 | `math` | advanced | 数学题（找规律、位运算应用）偏进阶 | 18 |

**合计 672 道**（一道题出现在多个分类时只算它**首次出现**的那个分类）。
按轨道汇总：**fundamentals 406 / interview 158 / advanced 108 / engineering 0**。

**`engineering` 轨道本批为空**——死脚本和存量题解里**都没有工程化分类**（没有「系统设计」「并发」「工程实践」这类 slug）。
这是实测结论，不是遗漏。`engineering` 轨道留空，等 M6 的 LLM 造题或后续人工补。

**未知 slug 的兜底：** `mapCategoryToTrack("不存在的 slug")` → `"interview"`（契约 §1 钉死），
并在导入器里**计一条告警**（告警里写明是哪个 slug），避免静默归错轨道。

---

## 标签归一化：78 种写法 → 71 种

设计文档 §3.4 写死了：**「topic 的 key 就是标签文本本身」**，所以**同一知识点只能有一种写法**，
导入器必须归一化。实测死脚本里一共 **78 种**中文/英文混写的标签写法。

**处理规则（写进 `core/bank/legacy.js` 的 `TOPIC_ALIASES`）：**

1. 先走 M1 的 `normalizeTopic()`（去首尾空白、内部连续空白压成一个空格）；
2. 再查别名表，命中就换成统一写法，没命中就原样保留。

**别名表（16 条，穷举；实测能把 78 种写法收敛到 71 种）：**

| 原始写法 | 统一成 | 为什么合并 |
|---|---|---|
| `哈希` | `哈希表` | 同一件事的简称 |
| `哈希映射` | `哈希表` | 同一件事的另一种叫法 |
| `二分` | `二分查找` | 同一件事的简称 |
| `标准二分` | `二分查找` | 二分查找的标准写法 |
| `变体二分` | `二分查找` | 二分查找的变体写法 |
| `答案二分` | `二分答案` | 二分答案的另一种写法 |
| `DP` | `动态规划` | 英文缩写与中文名统一 |
| `BFS` | `广度优先搜索` | 英文缩写与中文名统一 |
| `DFS` | `深度优先搜索` | 英文缩写与中文名统一 |
| `BST` | `二叉搜索树` | 英文缩写与中文名统一 |
| `双射` | `双射哈希` | 同一件事的简称 |
| `归并` | `归并排序` | 同一件事的简称 |
| `变长` | `变长窗口` | 同一件事的简称 |
| `定长` | `定长窗口` | 同一件事的简称 |
| `从后往前` | `倒序遍历` | 同一件事的另一种说法 |
| `原地标记` | `原地哈希` | 同一件事的另一种说法 |

**刻意不合并的（保持区分）：**

| 保持独立的写法 | 为什么不合并 |
|---|---|
| `哈希集合` vs `哈希表` | Set 与 Map 是两种容器 |
| `二分查找` vs `二分答案` | 一个是找位置，一个是找答案，思路完全不同 |
| `抽样` vs `蓄水池抽样` | 蓄水池抽样是特定算法 |
| `变长窗口` vs `定长窗口` vs `滑动窗口` | 三种不同的窗口题 |
| `桶排序` vs `桶计数` | 两种不同的做法 |

**归一化后的完整标签表（71 种，导入后 bank 里只会出现这 71 种写法）：**

```
KMP | 三指针 | 中序遍历 | 中心扩展 | 二分查找 | 二分答案 | 二叉搜索树 | 二维前缀和 | 位运算 | 倒序遍历 |
入度 | 分治 | 分组 | 前缀和 | 剪枝 | 动态规划 | 区间 | 单调栈 | 单调队列 | 原地哈希 |
双射哈希 | 双指针 | 反转 | 变长窗口 | 合并 | 哈希表 | 哈希集合 | 回溯 | 图 | 堆 |
字符串 | 定长窗口 | 对撞指针 | 差分 | 并查集 | 广度优先搜索 | 异或 | 归并排序 | 快慢指针 | 快速幂 |
找规律 | 投票 | 抽样 | 拓扑排序 | 排序 | 数学 | 数组 | 映射 | 最短路径 | 染色 |
栈 | 桶排序 | 桶计数 | 模拟 | 欧拉路径 | 深度优先搜索 | 滑动窗口 | 状态压缩 | 矩阵 | 空间优化 |
翻转 | 蓄水池抽样 | 计数 | 设计 | 贪心 | 边界 | 递归 | 遍历 | 链表 | 队列 | 随机
```

---

## 文件结构总览（先锁定边界，再写任务）

```
projects/apps/algo-plan/
├── core/
│   ├── paths.js                     M1：learning 仓路径解析
│   └── bank/
│       ├── problem.js               M1：Problem 模型、稳定 ID、topic 归一化
│       ├── parse.js                 M1：markdown ↔ Problem 双向转换
│       ├── provider.js              M1：FileProvider / NullProvider
│       ├── legacy.js                ★M2：死脚本静态解析 + slug→track + 标签归一化（纯函数）
│       └── solutions-scan.js        ★M2：存量题解静态扫描 + README 索引解析（纯函数）
├── server/                          M1：组合根、路由、API、SQLite 存储
├── web/                             M1：原生 JS 单页
├── tools/
│   ├── seed-bank.js                 M1：样板题导入
│   ├── import-catalog.js            ★M2：死脚本清单 → learning/bank
│   ├── import-solutions.js          ★M2：存量题解 → learning/bank
│   ├── import-bank.js               ★M2：一次性导入入口（先目录、后题解）
│   └── bank-files.js                ★M2：按 id 索引题库里已有的题目（两个导入器共用）
├── fixtures/
│   └── seed-bank/                   M1：2 道样板题
└── tests/
    ├── run-all.js                   M1：一键跑全部
    └── *.test.js                    M1 的 8 个 + M2 新增 5 个 = 13 个套件
```

**归属**：本计划只改 `projects/` 子模块。`learning/` 子模块在本计划里**只被写**
（导入器把题写进 `learning/bank/`），但**绝不碰 learning 的 git 历史**——
app 与本计划都不执行 learning 仓的 `git commit`，由人自己 review 后决定（G11、G30）。

---

## Task 1: 死脚本静态解析层 `core/bank/legacy.js`

**Files:**
- Create: `projects/apps/algo-plan/core/bank/legacy.js`
- Create: `projects/apps/algo-plan/tests/legacy.test.js`

**Interfaces:**
- Consumes: M1 的 `core/bank/problem.js` 的 `makeId(source, number)` 与 `normalizeTopic(text)`
- Produces:
  - `core/bank/legacy.js` 导出：
    - `CATEGORY_TRACK_MAP` —— `{categorySlug: track}`，**25 个 slug 全覆盖**
    - `FALLBACK_TRACK` —— `"interview"`（未知 slug 的兜底轨道）
    - `TOPIC_ALIASES` —— `{原始写法: 统一写法}`，16 条
    - `parseLegacyCategories(text) -> {categories: [{slug, title, items}], warnings: string[]}`
    - `parseLegacyPracticeData(text) -> {items: [{platform, problemId, title, difficulty, tags[], repeat}], warnings: string[]}`（契约 §1 钉死的形状）
    - `mapCategoryToTrack(slug) -> track`
    - `legacyIdOf(item) -> string`
    - `normalizeLegacyTopic(text) -> string`、`normalizeLegacyTopics(list) -> string[]`

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/legacy.test.js`：

```javascript
"use strict"
/**
 * legacy.test.js —— 死脚本内联题目清单的静态解析
 *
 * 本套件不碰磁盘：只把真实源码片段当字符串喂给纯函数。
 */

const test = require("node:test")
const assert = require("node:assert")

const legacy = require("../core/bank/legacy.js")

// 真实片段：projects/scripts/gen-practice-data.js（第 6–23 行的工厂函数 + 数组分类）
// 逐字抄自真实文件，只截取一部分；`offer22` 那条是真实文件里就有的坏数据。
const GEN_EXCERPT = `
function lc(title, id, diff, tags) {
  return {
    title,
    platform: "leetcode",
    problemId: id,
    difficulty: diff,
    tags: Array.isArray(tags) ? tags : [tags],
  };
}
function jz(title, id, diff, tags) {
  return {
    title: "剑指 Offer " + id + ". " + title,
    platform: "nowcoder",
    problemId: "" + id,
    difficulty: diff,
    tags: Array.isArray(tags) ? tags : [tags],
  };
}

var arrayItems = [
  lc("两数之和", 1, "easy", ["哈希表"]),
  lc("移除元素", 27, "easy", ["双指针"]),
  lc("搜索插入位置", 35, "easy", ["二分查找"]),
  jz("数组中重复的数字", "JZ03", "easy", ["哈希表"]),
  lc("链表中倒数第k个节点", offer22, "easy", ["快慢指针"]),
];

var categories = [
  cat(
    "array",
    "数组",
    1,
    1,
    "📗",
    "数组是最基本的数据结构，连续内存存储、随机访问 O(1)。",
    arrayItems,
  ),
];
`

// 真实片段：projects/scripts/expand-practice.js 的 addProblems() 调用形状
const EXP_EXCERPT = `
function addProblems(catId, newItems) {
  var cat = cats.filter(function (c) {
    return c.id === catId;
  })[0];
}

addProblems("two-pointers", [
  lc("三数之和", 15, "medium", ["排序", "双指针"]),
  lc("两数之和 II", 167, "easy", ["对撞指针"]),
  jz("合并两个排序的链表", "JZ25", "easy", ["链表"]),
]);
`

// 真实片段：projects/scripts/split-practice-data.js —— 它没有内联清单
const SPLIT_EXCERPT = `
var SRC = path.resolve(
  __dirname,
  "..",
  "project",
  "reading-radar",
  "data",
  "app",
  "practice-data.js",
);
var src = fs.readFileSync(SRC, "utf-8");
`

test("cat() 形状：解析出分类与题目，跳过未定义标识符的题号", function () {
  const parsed = legacy.parseLegacyCategories(GEN_EXCERPT)
  assert.strictEqual(parsed.categories.length, 1)
  assert.strictEqual(parsed.categories[0].slug, "array")
  assert.strictEqual(parsed.categories[0].title, "数组")
  // 5 条里 1 条题号是未定义标识符（offer22），必须跳过
  assert.strictEqual(parsed.categories[0].items.length, 4)
  assert.strictEqual(parsed.warnings.length, 1)
  assert.ok(parsed.warnings[0].indexOf("offer22") !== -1, parsed.warnings[0])
})

test("题目条目字段与契约一致：platform/problemId/title/difficulty/tags/repeat", function () {
  const parsed = legacy.parseLegacyCategories(GEN_EXCERPT)
  const first = parsed.categories[0].items[0]
  assert.deepStrictEqual(Object.keys(first).sort(), [
    "difficulty", "platform", "problemId", "repeat", "tags", "title",
  ])
  assert.strictEqual(first.platform, "leetcode")
  assert.strictEqual(first.problemId, 1)
  assert.strictEqual(first.title, "两数之和")
  assert.strictEqual(first.difficulty, "easy")
  assert.deepStrictEqual(first.tags, ["哈希表"])
  assert.strictEqual(first.repeat, false)
})

test("jz() 的题号取末尾数字，标题按运行时的样子还原前缀", function () {
  const parsed = legacy.parseLegacyCategories(GEN_EXCERPT)
  const jzItem = parsed.categories[0].items.filter(function (i) {
    return i.platform === "nowcoder"
  })[0]
  assert.strictEqual(jzItem.problemId, 3)
  assert.strictEqual(jzItem.title, "剑指 Offer JZ03. 数组中重复的数字")
})

test("addProblems() 形状：解析出分类与题目", function () {
  const parsed = legacy.parseLegacyCategories(EXP_EXCERPT)
  assert.strictEqual(parsed.categories.length, 1)
  assert.strictEqual(parsed.categories[0].slug, "two-pointers")
  assert.strictEqual(parsed.categories[0].items.length, 3)
  assert.strictEqual(parsed.categories[0].items[0].problemId, 15)
})

test("没有内联清单的脚本：0 个分类 + 1 条告警，不算错误", function () {
  const parsed = legacy.parseLegacyCategories(SPLIT_EXCERPT)
  assert.strictEqual(parsed.categories.length, 0)
  assert.strictEqual(parsed.warnings.length, 1)
  assert.ok(parsed.warnings[0].indexOf("没有找到内联题目清单") !== -1, parsed.warnings[0])
})

test("parseLegacyPracticeData 返回扁平题目清单（契约形状）", function () {
  const parsed = legacy.parseLegacyPracticeData(GEN_EXCERPT)
  assert.strictEqual(parsed.items.length, 4)
  assert.strictEqual(parsed.items[0].platform, "leetcode")
  assert.ok(Array.isArray(parsed.items[0].tags))
})

test("legacyIdOf 用 M1 的 makeId 生成稳定 ID", function () {
  assert.strictEqual(
    legacy.legacyIdOf({ platform: "leetcode", problemId: 1 }),
    "lc-00001"
  )
  assert.strictEqual(
    legacy.legacyIdOf({ platform: "leetcode", problemId: 1455 }),
    "lc-01455"
  )
  assert.strictEqual(
    legacy.legacyIdOf({ platform: "nowcoder", problemId: 3 }),
    "nc-00003"
  )
})

test("mapCategoryToTrack 覆盖 25 个 slug，未知 slug 落到 interview", function () {
  assert.strictEqual(Object.keys(legacy.CATEGORY_TRACK_MAP).length, 25)
  assert.strictEqual(legacy.mapCategoryToTrack("array"), "fundamentals")
  assert.strictEqual(legacy.mapCategoryToTrack("dp-advanced"), "advanced")
  assert.strictEqual(legacy.mapCategoryToTrack("interview-classic"), "interview")
  assert.strictEqual(legacy.mapCategoryToTrack("根本没有这个分类"), "interview")
  assert.strictEqual(legacy.FALLBACK_TRACK, "interview")
})

test("标签归一化：别名表生效，没命中的原样保留", function () {
  assert.strictEqual(legacy.normalizeLegacyTopic("哈希"), "哈希表")
  assert.strictEqual(legacy.normalizeLegacyTopic("DP"), "动态规划")
  assert.strictEqual(legacy.normalizeLegacyTopic("二分"), "二分查找")
  assert.strictEqual(legacy.normalizeLegacyTopic("  双指针 "), "双指针")
  assert.deepStrictEqual(
    legacy.normalizeLegacyTopics(["哈希", "哈希表", "双指针"]),
    ["哈希表", "双指针"]
  )
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/bank/legacy.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/bank/legacy.js`：

```javascript
"use strict"
/**
 * legacy.js —— 死脚本内联题目清单的静态解析（纯函数层，无 IO）
 *
 * 对应设计文档 §3.5 的「B 路：复活死代码」。
 *
 * 为什么必须静态解析、绝不执行被解析的脚本：
 *   1. 三个脚本都读已删除的 project/reading-radar/data/app/practice-data.js，直接跑必然 ENOENT；
 *   2. gen-practice-data.js 里有 6 处题号写成了未定义标识符
 *      （offer22 / offer18 / deleteNode / offer23 / offer09 / offer30），真跑会 ReferenceError；
 *   3. 死脚本唯一的价值就是「源码里的内联清单」，执行它们反而多余。
 *
 * 本模块只做「按下面的规则解析源码文本」：
 *   - cat("slug", "标题", phase, order, icon, desc, items变量)   → gen-practice-data.js
 *   - addProblems("slug", [ ... ])                              → expand-practice.js
 *   - 两种都没有                                                  → split-practice-data.js（记告警）
 */

const { makeId, normalizeTopic } = require("./problem.js")

/** 分类 slug → 轨道。25 个 slug 全覆盖，理由见 M2 计划的映射表。 */
const CATEGORY_TRACK_MAP = {
  // fundamentals：基础数据结构与基础算法
  "array": "fundamentals",
  "string": "fundamentals",
  "linked-list": "fundamentals",
  "stack": "fundamentals",
  "queue": "fundamentals",
  "sorting": "fundamentals",
  "binary-tree": "fundamentals",
  "bst": "fundamentals",
  "heap": "fundamentals",
  "bit-manipulation": "fundamentals",
  // interview：面试高频套路
  "two-pointers": "interview",
  "sliding-window": "interview",
  "prefix-sum": "interview",
  "hash-table": "interview",
  "binary-search": "interview",
  "dfs": "interview",
  "bfs": "interview",
  "backtracking": "interview",
  "interview-classic": "interview",
  // advanced：需要证明或套路偏深的题型
  "greedy": "advanced",
  "dp-basic": "advanced",
  "dp-advanced": "advanced",
  "union-find": "advanced",
  "graph": "advanced",
  "math": "advanced",
}

/** 未知 slug 的兜底轨道（契约 §1 钉死） */
const FALLBACK_TRACK = "interview"

/**
 * 标签别名表：原始写法 → 统一写法。
 * 设计文档 §3.4 要求「同一知识点只能有一种写法」。
 * 刻意不合并的：哈希集合/哈希表、二分查找/二分答案、抽样/蓄水池抽样。
 */
const TOPIC_ALIASES = {
  "哈希": "哈希表",
  "哈希映射": "哈希表",
  "二分": "二分查找",
  "标准二分": "二分查找",
  "变体二分": "二分查找",
  "答案二分": "二分答案",
  "DP": "动态规划",
  "BFS": "广度优先搜索",
  "DFS": "深度优先搜索",
  "BST": "二叉搜索树",
  "双射": "双射哈希",
  "归并": "归并排序",
  "变长": "变长窗口",
  "定长": "定长窗口",
  "从后往前": "倒序遍历",
  "原地标记": "原地哈希",
}

/**
 * 从 open 处的括号开始，找到配对的右括号位置。
 * 同时统计 () [] {} 三种括号，并跳过字符串字面量里的括号。
 * 反引号模板字符串不做插值处理（死脚本里没有用到）。
 * @param {string} text
 * @param {number} open 左括号下标
 * @returns {number} 配对右括号下标；找不到返回 -1
 */
function findClosing(text, open) {
  let depth = 0
  let quote = null
  for (let i = open; i < text.length; i++) {
    const ch = text[i]
    if (quote) {
      if (ch === "\\") { i++; continue }
      if (ch === quote) quote = null
      continue
    }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; continue }
    if (ch === "(" || ch === "[" || ch === "{") {
      depth++
    } else if (ch === ")" || ch === "]" || ch === "}") {
      depth--
      if (depth === 0) return i
    }
  }
  return -1
}

/**
 * 按顶层逗号切分实参（字符串里的逗号、括号里的逗号都不算）。
 * @param {string} text
 * @returns {string[]}
 */
function splitArgs(text) {
  const args = []
  let depth = 0
  let quote = null
  let cur = ""
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quote) {
      cur += ch
      if (ch === "\\") { cur += text[++i] || ""; continue }
      if (ch === quote) quote = null
      continue
    }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; cur += ch; continue }
    if (ch === "(" || ch === "[" || ch === "{") { depth++; cur += ch; continue }
    if (ch === ")" || ch === "]" || ch === "}") { depth--; cur += ch; continue }
    if (ch === "," && depth === 0) { args.push(cur); cur = ""; continue }
    cur += ch
  }
  if (cur.trim() !== "") args.push(cur)
  return args
}

/**
 * 实参是不是字符串字面量？是则返回内容，否则返回 null。
 * @param {string} arg
 * @returns {string|null}
 */
function readStringLiteral(arg) {
  const s = String(arg === undefined || arg === null ? "" : arg).trim()
  if (s.length < 2) return null
  const quote = s[0]
  if (quote !== '"' && quote !== "'" && quote !== "`") return null
  if (s[s.length - 1] !== quote) return null
  return s.slice(1, -1)
}

/**
 * 找出源码里所有 `var|let|const 名字 = [` 的数组字面量。
 * @param {string} src
 * @returns {Object<string,string>} 名字 → 数组体文本（不含最外层方括号）
 */
function harvestVarArrays(src) {
  const out = Object.create(null)
  const re = /(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*\[/g
  let m
  while ((m = re.exec(src))) {
    const open = src.indexOf("[", m.index)
    const close = findClosing(src, open)
    if (close === -1) continue
    out[m[1]] = src.slice(open + 1, close)
  }
  return out
}

/**
 * 找出源码里所有 `fnName(` 调用（跳过函数定义本身），返回实参文本列表。
 * @param {string} src
 * @param {string} fnName
 * @returns {string[]}
 */
function findCalls(src, fnName) {
  const out = []
  const re = new RegExp("\\b" + fnName + "\\s*\\(", "g")
  let m
  while ((m = re.exec(src))) {
    const before = src.slice(Math.max(0, m.index - 12), m.index)
    if (/function\s+$/.test(before)) continue
    const open = src.indexOf("(", m.index)
    const close = findClosing(src, open)
    if (close === -1) continue
    out.push(src.slice(open + 1, close))
  }
  return out
}

/**
 * 题号 → 数字。
 *   56      → 56
 *   "JZ03"  → 3（剑指 Offer 的题号写法，取末尾数字）
 *   offer22 → null（未定义标识符，脚本里根本没定义这个变量，不猜）
 * @param {string} raw
 * @returns {{number: number, raw: string}|null}
 */
function problemIdOf(raw) {
  const s = String(raw === undefined || raw === null ? "" : raw).trim()
  if (/^\d+$/.test(s)) return { number: Number(s), raw: s }
  const quoted = readStringLiteral(s)
  if (quoted !== null) {
    const m = /(\d+)\s*$/.exec(quoted)
    if (m) return { number: Number(m[1]), raw: quoted }
    return null
  }
  return null
}

/**
 * 从一段数组体文本里解析出 lc(...) / jz(...) 条目。
 * @param {string} body
 * @returns {{items: object[], warnings: string[]}}
 */
function parseItemCalls(body) {
  const items = []
  const warnings = []
  const re = /\b(lc|jz)\s*\(/g
  let m
  while ((m = re.exec(body))) {
    const before = body.slice(Math.max(0, m.index - 12), m.index)
    if (/function\s+$/.test(before)) continue
    const open = body.indexOf("(", m.index)
    const close = findClosing(body, open)
    if (close === -1) {
      warnings.push("括号不配对，已跳过：" + body.slice(m.index, m.index + 30))
      continue
    }
    const args = splitArgs(body.slice(open + 1, close))
    const bareTitle = readStringLiteral(args[0])
    const difficulty = readStringLiteral(args[2])
    if (bareTitle === null || difficulty === null) {
      warnings.push("标题或难度不是字符串字面量，已跳过：" + body.slice(m.index, m.index + 40))
      continue
    }
    const pid = problemIdOf(args[1])
    if (pid === null) {
      warnings.push(
        "题号不是数字（" + String(args[1] === undefined ? "" : args[1]).trim() +
        "），已跳过：" + bareTitle
      )
      continue
    }
    const tags = []
    const tagRe = /"([^"]*)"|'([^']*)'/g
    let tm
    while ((tm = tagRe.exec(args[3] || ""))) {
      tags.push(tm[1] !== undefined ? tm[1] : tm[2])
    }
    // jz() 在运行时才给标题加 "剑指 Offer <题号>. " 前缀，静态解析要还原成同样的样子
    const title = m[1] === "jz"
      ? "剑指 Offer " + pid.raw + ". " + bareTitle
      : bareTitle
    items.push({
      platform: m[1] === "lc" ? "leetcode" : "nowcoder",
      problemId: pid.number,
      title: title,
      difficulty: difficulty,
      tags: tags,
      repeat: false,
    })
  }
  return { items: items, warnings: warnings }
}

/**
 * 解析一个死脚本的源码文本 → 分类列表。
 * @param {string} text 源码全文
 * @returns {{categories: Array<{slug: string, title: string|null, items: object[]}>, warnings: string[]}}
 */
function parseLegacyCategories(text) {
  const src = String(text === undefined || text === null ? "" : text)
  const warnings = []
  const categories = []
  const vars = harvestVarArrays(src)

  // 形状一：cat("slug", "标题", phase, order, icon, desc, items变量)
  findCalls(src, "cat").forEach(function (argsText) {
    const args = splitArgs(argsText)
    const slug = readStringLiteral(args[0])
    if (slug === null) {
      warnings.push("cat() 的第一个实参不是字符串字面量，已跳过")
      return
    }
    const title = readStringLiteral(args[1])
    const itemsArg = String(args[6] === undefined ? "" : args[6]).trim()
    let body = null
    if (itemsArg.startsWith("[")) {
      body = itemsArg.slice(1, itemsArg.lastIndexOf("]"))
    } else {
      const name = itemsArg.replace(/;$/, "").trim()
      body = vars[name]
      if (body === undefined) {
        warnings.push("cat(" + slug + ") 的题目数组变量 " + name + " 找不到，已跳过")
        return
      }
    }
    const parsed = parseItemCalls(body)
    parsed.warnings.forEach(function (w) { warnings.push(slug + "：" + w) })
    categories.push({ slug: slug, title: title, items: parsed.items })
  })

  // 形状二：addProblems("slug", [ ... ])
  findCalls(src, "addProblems").forEach(function (argsText) {
    const args = splitArgs(argsText)
    const slug = readStringLiteral(args[0])
    if (slug === null) {
      warnings.push("addProblems() 的第一个实参不是字符串字面量，已跳过")
      return
    }
    const arr = String(args[1] === undefined ? "" : args[1]).trim()
    const body = arr.startsWith("[") ? arr.slice(1, arr.lastIndexOf("]")) : ""
    const parsed = parseItemCalls(body)
    parsed.warnings.forEach(function (w) { warnings.push(slug + "：" + w) })
    categories.push({ slug: slug, title: null, items: parsed.items })
  })

  // 同一个 slug 可能被追加好几批（expand-practice.js 里 5 个 slug 各追加过多次）→ 按 slug 合并
  const merged = []
  categories.forEach(function (cat) {
    const exist = merged.filter(function (c) { return c.slug === cat.slug })[0]
    if (!exist) {
      merged.push({ slug: cat.slug, title: cat.title, items: cat.items.slice() })
      return
    }
    if (!exist.title && cat.title) exist.title = cat.title
    exist.items = exist.items.concat(cat.items)
  })

  // repeat 标记：同一个 (platform, problemId) 第二次出现即为重复
  const seen = Object.create(null)
  merged.forEach(function (cat) {
    cat.items.forEach(function (item) {
      const key = item.platform + ":" + item.problemId
      if (seen[key]) item.repeat = true
      else seen[key] = true
    })
  })

  if (merged.length === 0) {
    warnings.push("脚本里没有找到内联题目清单（既没有 cat() 也没有 addProblems() 调用）")
  }
  return { categories: merged, warnings: warnings }
}

/**
 * 解析死脚本源码文本 → 扁平题目清单（契约 §1 钉死的形状）。
 * @param {string} text
 * @returns {{items: Array<{platform, problemId, title, difficulty, tags, repeat}>, warnings: string[]}}
 */
function parseLegacyPracticeData(text) {
  const parsed = parseLegacyCategories(text)
  const items = []
  parsed.categories.forEach(function (cat) {
    cat.items.forEach(function (item) { items.push(item) })
  })
  return { items: items, warnings: parsed.warnings }
}

/**
 * 分类 slug → 轨道。未知 slug 落到 FALLBACK_TRACK（调用方负责计告警）。
 * @param {string} slug
 * @returns {string}
 */
function mapCategoryToTrack(slug) {
  const key = String(slug === undefined || slug === null ? "" : slug)
  if (Object.prototype.hasOwnProperty.call(CATEGORY_TRACK_MAP, key)) {
    return CATEGORY_TRACK_MAP[key]
  }
  return FALLBACK_TRACK
}

/**
 * 死脚本条目 → 稳定 ID（用 M1 的 makeId）。
 * platform: leetcode → lc，nowcoder → nc（契约 §1 钉死）。
 * @param {{platform: string, problemId: number|string}} item
 * @returns {string}
 */
function legacyIdOf(item) {
  if (!item) throw new Error("条目为空")
  const platform = String(item.platform || "")
  const pid = problemIdOf(item.problemId)
  if (pid === null) throw new Error("题号取不到数字：" + item.problemId)
  return makeId(platform, pid.number)
}

/**
 * 标签归一化：先走 M1 的 normalizeTopic，再查别名表。
 * @param {string} text
 * @returns {string}
 */
function normalizeLegacyTopic(text) {
  const base = normalizeTopic(text)
  if (base === "") return ""
  if (Object.prototype.hasOwnProperty.call(TOPIC_ALIASES, base)) {
    return TOPIC_ALIASES[base]
  }
  return base
}

/**
 * 标签列表归一化：去空、去重、保序。
 * @param {string[]|string} list
 * @returns {string[]}
 */
function normalizeLegacyTopics(list) {
  const input = Array.isArray(list) ? list : list ? [list] : []
  const seen = Object.create(null)
  const out = []
  input.forEach(function (item) {
    const topic = normalizeLegacyTopic(item)
    if (topic === "" || seen[topic]) return
    seen[topic] = true
    out.push(topic)
  })
  return out
}

module.exports = {
  CATEGORY_TRACK_MAP: CATEGORY_TRACK_MAP,
  FALLBACK_TRACK: FALLBACK_TRACK,
  TOPIC_ALIASES: TOPIC_ALIASES,
  parseLegacyCategories: parseLegacyCategories,
  parseLegacyPracticeData: parseLegacyPracticeData,
  mapCategoryToTrack: mapCategoryToTrack,
  legacyIdOf: legacyIdOf,
  normalizeLegacyTopic: normalizeLegacyTopic,
  normalizeLegacyTopics: normalizeLegacyTopics,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `9 / 9 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加死脚本题目清单的静态解析层

- core/bank/legacy.js：纯函数解析 gen-practice-data.js 的 cat() 与 expand-practice.js 的 addProblems()
- 括号配对 + 字符串感知的实参切分，能识别数组变量、嵌套标签数组与带说明的调用
- 题号是未定义标识符时跳过并计告警，不猜题号（源码里确有 6 处这样的坏数据）
- jz() 的标题按运行时的样子还原「剑指 Offer <题号>. 」前缀
- CATEGORY_TRACK_MAP 覆盖全部 25 个分类 slug，未知 slug 落到 interview
- TOPIC_ALIASES 16 条别名，把 78 种标签写法收敛到 71 种
- 测试：两种脚本形状、坏题号跳过、README 索引、ID 生成、轨道映射、标签归一化共 8 条断言"
git push origin main
```

---

## Task 2: 存量题解扫描层 `core/bank/solutions-scan.js`

**Files:**
- Create: `projects/apps/algo-plan/core/bank/solutions-scan.js`
- Create: `projects/apps/algo-plan/tests/solutions-scan.test.js`

**Interfaces:**
- Consumes: M1 的 `core/bank/problem.js` 的 `makeId(source, number)`
- Produces:
  - `core/bank/solutions-scan.js` 导出：
    - `MARKER_PATTERN` —— 匹配 `// leetcode <题号> [解法说明]` 的正则
    - `FILENAME_PATTERN` —— 匹配单题文件名 `leetcode_<题号>.<ext>`
    - `RANGE_FILENAME_PATTERN` —— 匹配区间文件名 `leetcode_<起>_<止>.<ext>`
    - `DIFFICULTY_BY_CN` —— `{简单: "easy", 中等: "medium", 困难: "hard"}`
    - `SOLUTION_TOPIC_BY_DIR` —— `{sliding_window: "滑动窗口", prefix_sum: "前缀和"}`
    - `DEFAULT_SOLUTION_TOPIC` —— `"未分类"`
    - `DEFAULT_SOLUTION_TRACK` —— `"fundamentals"`
    - `SOLUTION_TRACK_BY_TOPIC` —— `{滑动窗口: "interview", 前缀和: "interview"}`
    - `splitByMarker(text) -> Array<{id: number, rest: string, code: string}>`
    - `idFromFileName(name) -> number|null`
    - `langOf(filePath) -> string`
    - `topicOfSolutionFile(filePath) -> string`
    - `trackOfSolutionTopic(topic) -> string`
    - `parseSolutionIndex(files) -> {byId: Object, warnings: string[]}`
    - `parseSolutionFiles(files) -> {items: Array<{source, sourceId, title, lang, code, file}>, warnings: string[]}`（契约 §1 钉死的形状）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/solutions-scan.test.js`：

```javascript
"use strict"
/**
 * solutions-scan.test.js —— 存量题解的静态扫描
 *
 * 夹具全是真实文件的节选：learning/code-solutions/c/src/ 与 learning/algo-c/ 下的原文。
 */

const test = require("node:test")
const assert = require("node:assert")

const scan = require("../core/bank/solutions-scan.js")

// 真实片段：learning/code-solutions/c/src/c/leetcode_1_100.c（第 1–40 行，逐字）
const C_RANGE_EXCERPT = `#include <stdlib.h>
#include <math.h>

#include "common.h"

// leetcode 56

int **merge(int **intervals, int intervalsSize, int *intervalsColSize, int **returnColumnSizes)
{
    (void)intervalsColSize; // Suppress unused parameter warning

    int **ans = malloc(sizeof(int *) * intervalsSize);
    *returnColumnSizes = malloc(sizeof(int) * intervalsSize);

    for (int i = 0; i < intervalsSize; i++) {
        ans[i] = (int *)malloc(sizeof(int) * 2);
    }

    qsort(intervals, intervalsSize, sizeof(int *), int_cmp);

    int count = 0;
    for (int i = 0; i < intervalsSize; i++) {
        int L = intervals[i][0], R = intervals[i][1];
        if (count == 0 || ans[count - 1][1] < L) {
            returnColumnSizes[0][count] = 2;
            ans[count][0] = L;
            ans[count][1] = R;
            count++;
        } else {
            ans[count - 1][1] = fmax(ans[count - 1][1], R);
        }
    }

    *returnSize = count;
    return ans;
}

// leetcode 75
void sortColors_qsort(int *nums, int numsSize)
{
}
`

// 真实片段：learning/code-solutions/c/src/cpp/leetcode_1_100.cpp（第 1–22 行，逐字）
const CPP_RANGE_EXCERPT = `#include "leetcode/leetcode_cpp.h"

// leetcode 1 枚举法
vector<int> LeetCode_Solution::twoSumEnum(vector<int>& nums, int target) {
    vector<int> res;
    for (int i = 0; i < nums.size(); i++) {
        for (int j = i + 1; j < nums.size(); j++) {
            if (nums[i] + nums[j] == target) {
                res.push_back(i);
                res.push_back(j);
                return res;
            }
        }
    }

    return res;
}

// leetcode 1 hash map
vector<int> LeetCode_Solution::twoSumHash(vector<int>& nums, int target)
{
}
`

// 真实片段：learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp（第 1–12 行，逐字）
const SINGLE_FILE_EXCERPT = `#include <iostream>
#include <string>
using namespace std;

class Solution {
public:
    bool isPrefix(string sentence, int start, int end, string searchWord)
    {
        for (int i = 0; i < searchWord.size(); i++) {
            if (start + i > end || sentence[i] != searchWord[i]) {
                return false;
            }
        }
    }
}
`

// 真实片段：learning/algo-c/sliding_window/README.md 的「LeetCode 题目」表（逐字）
const README_EXCERPT = `# 滑动窗口 (Sliding Window)

## LeetCode 题目

| 题号 | 题目 | 难度 |
|------|------|------|
| 1984 | [学生分数的最小差值](../1984_minimum_difference/) | 简单 |
| 2270 | [分割数组的方案数](../2270_ways_to_split/) | 中等 |
| 3297 | [统计相似字符串对的数目](../3297_count_matching/) | 简单 |
`

test("区间文件按 // leetcode 标记切分，id 与解法说明都对得上", function () {
  const blocks = scan.splitByMarker(C_RANGE_EXCERPT)
  assert.strictEqual(blocks.length, 2)
  assert.strictEqual(blocks[0].id, 56)
  assert.strictEqual(blocks[0].rest, "")
  assert.strictEqual(blocks[1].id, 75)
  assert.ok(blocks[0].code.indexOf("int **merge(") !== -1, "第一段应含 merge 实现")
  assert.ok(blocks[1].code.indexOf("sortColors_qsort") !== -1, "第二段应含 sortColors 实现")
})

test("区间文件第一段带上文件头的 #include", function () {
  const blocks = scan.splitByMarker(C_RANGE_EXCERPT)
  assert.ok(blocks[0].code.indexOf("#include <stdlib.h>") !== -1, "第一段应含 #include")
  assert.ok(blocks[0].code.indexOf("#include \"common.h\"") !== -1, "第一段应含 common.h")
})

test("标记后面带解法说明时，说明被记进 rest", function () {
  const blocks = scan.splitByMarker(CPP_RANGE_EXCERPT)
  assert.strictEqual(blocks.length, 2)
  assert.strictEqual(blocks[0].id, 1)
  assert.strictEqual(blocks[0].rest, "枚举法")
  assert.strictEqual(blocks[1].rest, "hash map")
})

test("文件名能读出题号，语言也能读出来", function () {
  assert.strictEqual(scan.idFromFileName("leetcode_1455.cpp"), 1455)
  assert.strictEqual(scan.idFromFileName("leetcode_2070.c"), 2070)
  assert.strictEqual(scan.idFromFileName("leetcode_1_100.c"), null)
  assert.strictEqual(scan.idFromFileName("interview_17.c"), null)
  assert.strictEqual(scan.langOf("a/leetcode_1455.cpp"), "cpp")
  assert.strictEqual(scan.langOf("a/leetcode_2070.c"), "c")
})

test("专题目录能认出标签，algo-c/problems 根目录认不出", function () {
  assert.strictEqual(
    scan.topicOfSolutionFile("learning/algo-c/sliding_window/problems/1984_minimum_difference/leetcode_1984.cpp"),
    "滑动窗口"
  )
  assert.strictEqual(
    scan.topicOfSolutionFile("learning/algo-c/prefix_sum/problems/3159_query_results/leetcode_3159.cpp"),
    "前缀和"
  )
  assert.strictEqual(
    scan.topicOfSolutionFile("learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp"),
    ""
  )
  assert.strictEqual(
    scan.topicOfSolutionFile("learning/code-solutions/c/src/c/leetcode_1_100.c"),
    ""
  )
})

test("README 索引表能读出中文题名与难度", function () {
  const index = scan.parseSolutionIndex([
    { path: "learning/algo-c/sliding_window/README.md", text: README_EXCERPT },
  ])
  assert.strictEqual(index.byId[1984].title, "学生分数的最小差值")
  assert.strictEqual(index.byId[1984].difficulty, "easy")
  assert.strictEqual(index.byId[2270].difficulty, "medium")
  assert.strictEqual(index.byId[3297].title, "统计相似字符串对的数目")
})

test("parseSolutionFiles 产出契约形状的条目", function () {
  const parsed = scan.parseSolutionFiles([
    { path: "learning/code-solutions/c/src/c/leetcode_1_100.c", text: C_RANGE_EXCERPT },
    { path: "learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp", text: SINGLE_FILE_EXCERPT },
  ])
  assert.strictEqual(parsed.items.length, 3)
  const first = parsed.items[0]
  assert.deepStrictEqual(Object.keys(first).sort(), [
    "code", "file", "lang", "source", "sourceId", "title",
  ])
  assert.strictEqual(first.source, "leetcode")
  assert.strictEqual(first.sourceId, "56")
  assert.strictEqual(first.title, "LeetCode 56")
  assert.strictEqual(first.lang, "c")
  assert.strictEqual(parsed.items[2].sourceId, "1455")
  assert.strictEqual(parsed.items[2].title, "LeetCode 1455")
})

test("索引里有的题用中文题名，没有的用 LeetCode <题号>", function () {
  const index = scan.parseSolutionIndex([
    { path: "learning/algo-c/sliding_window/README.md", text: README_EXCERPT },
  ])
  const parsed = scan.parseSolutionFiles(
    [
      { path: "learning/algo-c/sliding_window/problems/1984_minimum_difference/leetcode_1984.cpp", text: SINGLE_FILE_EXCERPT },
    ],
    index.byId
  )
  assert.strictEqual(parsed.items[0].title, "学生分数的最小差值")
})

test("命名不符合约定的文件不产出条目，只记告警", function () {
  const parsed = scan.parseSolutionFiles([
    { path: "learning/code-solutions/c/src/c/interview_17.c", text: "// 17.14\n" },
    { path: "learning/algo-c/contest/Weekly_match/433/433_1.cpp", text: "// 100548. 变长子数组求和\n" },
  ])
  assert.strictEqual(parsed.items.length, 0)
  assert.strictEqual(parsed.warnings.length, 2)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../core/bank/solutions-scan.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/core/bank/solutions-scan.js`：

```javascript
"use strict"
/**
 * solutions-scan.js —— 存量题解的静态扫描（纯函数层，无 IO）
 *
 * 对应设计文档 §3.5 的「C 路：存量题解」。
 *
 * 两种命名形态，各有各的取题号办法：
 *   1. 区间文件 learning/code-solutions/c/src/{c,cpp}/leetcode_<起>_<止>.{c,cpp}
 *      —— 靠 `// leetcode <题号>` 注释定位，文件里可能有多道题；
 *   2. 单题文件 learning/algo-c/**/leetcode_<题号>.{c,cpp}
 *      —— 文件名就是题号，整个文件是一道题的解法。
 *
 * 收录范围 = 文件基名匹配 FILENAME_PATTERN 或 RANGE_FILENAME_PATTERN 的 .c/.cpp 文件。
 * 其余文件（interview_17.c 的面经章节号、contest/ 的竞赛题、bit_operations/ 的演示代码）一律跳过。
 */

const { makeId } = require("./problem.js")

/** 标记注释：// leetcode 56 / // leetcode 1 hash map */
const MARKER_PATTERN = /^[ \t]*\/\/[ \t]*leetcode[ \t]+(\d+)[ \t]*(.*)$/gm

/** 单题文件名：leetcode_1455.cpp */
const FILENAME_PATTERN = /^leetcode_(\d+)\.(c|cpp)$/

/** 区间文件名：leetcode_1_100.c */
const RANGE_FILENAME_PATTERN = /^leetcode_\d+_\d+\.(c|cpp)$/

/** 中文难度 → 难度枚举 */
const DIFFICULTY_BY_CN = {
  "简单": "easy",
  "中等": "medium",
  "困难": "hard",
}

/** algo-c 专题目录 → 标签 */
const SOLUTION_TOPIC_BY_DIR = {
  "sliding_window": "滑动窗口",
  "prefix_sum": "前缀和",
}

/** 没有专题信息时的默认标签 */
const DEFAULT_SOLUTION_TOPIC = "未分类"

/** 没有专题信息时的默认轨道 */
const DEFAULT_SOLUTION_TRACK = "fundamentals"

/** 标签 → 轨道 */
const SOLUTION_TRACK_BY_TOPIC = {
  "滑动窗口": "interview",
  "前缀和": "interview",
}

/**
 * 按 `// leetcode <题号>` 标记把一个区间文件切成若干段。
 * 每段保留自己的标记注释；第一段额外带上文件头的 #include。
 * @param {string} text
 * @returns {Array<{id: number, rest: string, code: string}>}
 */
function splitByMarker(text) {
  const src = String(text === undefined || text === null ? "" : text)
  const re = new RegExp(MARKER_PATTERN.source, "gm")
  const marks = []
  let m
  while ((m = re.exec(src))) {
    marks.push({
      id: Number(m[1]),
      rest: String(m[2] || "").trim(),
      start: m.index,
    })
  }
  const out = []
  marks.forEach(function (mark, i) {
    const end = i + 1 < marks.length ? marks[i + 1].start : src.length
    let code = src.slice(mark.start, end).replace(/\s+$/, "")
    if (i === 0) {
      // 文件头的 #include 属于第一段
      const head = src.slice(0, mark.start).split(/\r?\n/)
      const includes = head.filter(function (line) { return /^[ \t]*#include/.test(line) })
      if (includes.length > 0) code = includes.join("\n") + "\n\n" + code
    }
    out.push({ id: mark.id, rest: mark.rest, code: code })
  })
  return out
}

/**
 * 从文件名取题号。不是 leetcode_<题号>.<ext> 就返回 null。
 * @param {string} name
 * @returns {number|null}
 */
function idFromFileName(name) {
  const m = FILENAME_PATTERN.exec(String(name === undefined || name === null ? "" : name))
  return m ? Number(m[1]) : null
}

/**
 * 语言：.c → c，.cpp → cpp。
 * @param {string} filePath
 * @returns {string}
 */
function langOf(filePath) {
  const m = /\.(c|cpp)$/i.exec(String(filePath === undefined || filePath === null ? "" : filePath))
  return m ? m[1].toLowerCase() : ""
}

/**
 * 从路径里认出 algo-c 的专题目录。
 * 规则：路径里有 "problems" 目录，它的上一级目录名若在 SOLUTION_TOPIC_BY_DIR 里，就是专题。
 * @param {string} filePath
 * @returns {string} 标签；认不出返回空串
 */
function topicOfSolutionFile(filePath) {
  const parts = String(filePath === undefined || filePath === null ? "" : filePath).split(/[\\/]+/)
  const idx = parts.lastIndexOf("problems")
  if (idx <= 0) return ""
  const dir = parts[idx - 1]
  if (Object.prototype.hasOwnProperty.call(SOLUTION_TOPIC_BY_DIR, dir)) {
    return SOLUTION_TOPIC_BY_DIR[dir]
  }
  return ""
}

/**
 * 标签 → 轨道。认不出的标签落到默认轨道。
 * @param {string} topic
 * @returns {string}
 */
function trackOfSolutionTopic(topic) {
  const key = String(topic === undefined || topic === null ? "" : topic)
  if (Object.prototype.hasOwnProperty.call(SOLUTION_TRACK_BY_TOPIC, key)) {
    return SOLUTION_TRACK_BY_TOPIC[key]
  }
  return DEFAULT_SOLUTION_TRACK
}

/**
 * 解析 README 里的「题号 / 题目 / 难度」表。
 * @param {Array<{path: string, text: string}>} files
 * @returns {{byId: Object, warnings: string[]}}
 */
function parseSolutionIndex(files) {
  const byId = Object.create(null)
  const warnings = []
  ;(files || []).forEach(function (file) {
    const text = String((file && file.text) || "")
    const path = String((file && file.path) || "")
    text.split(/\r?\n/).forEach(function (line) {
      const m = /^\|\s*(\d+)\s*\|\s*(?:\[([^\]]*)\]\([^)]*\)|([^|]*?))\s*\|\s*([^|]+?)\s*\|/.exec(line)
      if (!m) return
      const id = Number(m[1])
      const title = String(m[2] !== undefined ? m[2] : m[3]).trim()
      const cn = String(m[4]).trim()
      const difficulty = DIFFICULTY_BY_CN[cn]
      if (!difficulty) {
        warnings.push("难度写法不认识：" + cn + "（" + path + "）")
        return
      }
      if (byId[id]) {
        warnings.push("题号在索引里重复：" + id + "（" + path + "）")
        return
      }
      byId[id] = { title: title, difficulty: difficulty }
    })
  })
  return { byId: byId, warnings: warnings }
}

/**
 * 扫描题解文件 → 题目条目（契约 §1 钉死的形状）。
 * @param {Array<{path: string, text: string}>} files
 * @param {Object} [index] parseSolutionIndex 产出的 byId，用来取中文题名
 * @returns {{items: Array<{source, sourceId, title, lang, code, file}>, warnings: string[]}}
 */
function parseSolutionFiles(files, index) {
  const items = []
  const warnings = []
  const byId = index || Object.create(null)
  ;(files || []).forEach(function (file) {
    const path = String((file && file.path) || "")
    const text = String((file && file.text) || "")
    const base = path.split(/[\\/]+/).pop()

    const single = FILENAME_PATTERN.exec(base)
    if (single) {
      const id = Number(single[1])
      const meta = byId[id] ? byId[id] : null
      items.push({
        source: "leetcode",
        sourceId: String(id),
        title: meta ? meta.title : "LeetCode " + id,
        lang: single[2].toLowerCase(),
        code: text.replace(/\s+$/, ""),
        file: path,
      })
      return
    }

    if (RANGE_FILENAME_PATTERN.test(base)) {
      const blocks = splitByMarker(text)
      if (blocks.length === 0) {
        warnings.push("区间文件里没有找到 // leetcode 标记，已跳过：" + path)
        return
      }
      blocks.forEach(function (block) {
        const meta = byId[block.id] ? byId[block.id] : null
        const baseTitle = meta ? meta.title : "LeetCode " + block.id
        items.push({
          source: "leetcode",
          sourceId: String(block.id),
          title: block.rest ? baseTitle + "（" + block.rest + "）" : baseTitle,
          lang: langOf(path),
          code: block.code,
          file: path,
        })
      })
      return
    }

    warnings.push("文件名不符合 leetcode_<题号> 约定，已跳过：" + path)
  })
  return { items: items, warnings: warnings }
}

/**
 * 题解条目 → 稳定 ID（用 M1 的 makeId）。
 * @param {{source: string, sourceId: string}} item
 * @returns {string}
 */
function solutionIdOf(item) {
  if (!item) throw new Error("条目为空")
  return makeId(String(item.source || ""), Number(item.sourceId))
}

module.exports = {
  MARKER_PATTERN: MARKER_PATTERN,
  FILENAME_PATTERN: FILENAME_PATTERN,
  RANGE_FILENAME_PATTERN: RANGE_FILENAME_PATTERN,
  DIFFICULTY_BY_CN: DIFFICULTY_BY_CN,
  SOLUTION_TOPIC_BY_DIR: SOLUTION_TOPIC_BY_DIR,
  DEFAULT_SOLUTION_TOPIC: DEFAULT_SOLUTION_TOPIC,
  DEFAULT_SOLUTION_TRACK: DEFAULT_SOLUTION_TRACK,
  SOLUTION_TRACK_BY_TOPIC: SOLUTION_TRACK_BY_TOPIC,
  splitByMarker: splitByMarker,
  idFromFileName: idFromFileName,
  langOf: langOf,
  topicOfSolutionFile: topicOfSolutionFile,
  trackOfSolutionTopic: trackOfSolutionTopic,
  parseSolutionIndex: parseSolutionIndex,
  parseSolutionFiles: parseSolutionFiles,
  solutionIdOf: solutionIdOf,
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
git commit -m "feat(algo-plan): 增加存量题解的静态扫描层

- core/bank/solutions-scan.js：纯函数解析区间文件（// leetcode 标记）与单题文件（文件名题号）
- 第一段代码补上文件头的 #include，每段保留自己的标记注释与解法说明
- README 的「题号 / 题目 / 难度」表读成索引，难度按 简单/中等/困难 映射成 easy/medium/hard
- 专题目录 sliding_window / prefix_sum 认成标签，其余落到「未分类」
- 命名不符合 leetcode_<题号> 约定的文件（interview_17.c、contest/）跳过并记告警
- 测试：标记切分、include 归位、文件名取号、专题识别、索引解析、条目形状共 8 条断言"
git push origin main
```

---

## Task 3: 目录导入器 `tools/import-catalog.js`

**Files:**
- Create: `projects/apps/algo-plan/tools/import-catalog.js`
- Create: `projects/apps/algo-plan/tests/import-catalog.test.js`

**Interfaces:**
- Consumes: Task 1 的 `core/bank/legacy.js`；M1 的 `core/paths.js` 的 `resolveLearningRoot(env, override)`、
  `core/bank/parse.js` 的 `serializeProblemMarkdown(problem)`、`core/bank/problem.js` 的 `createProblem(input)`
- Produces:
  - `tools/import-catalog.js` 导出：
    - `run(opts) -> {written: string[], skipped: string[], errors: string[], warnings: string[]}`
      （契约 §1 钉死的形状；`opts = {env, dryRun?, force?, scriptsDir?, learningRoot?}`）
    - `SCRIPT_FILES` —— `["gen-practice-data.js", "expand-practice.js", "split-practice-data.js"]`
    - `DEFAULT_SCRIPTS_DIR` —— `projects/scripts`
    - `main()` —— 命令行入口
  - `learning/bank/<track>/<id>.md` 里的**题库元数据文件**（`needs_fill: true`，无题面无用例）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/import-catalog.test.js`：

```javascript
"use strict"
/**
 * import-catalog.test.js —— 死脚本清单导入 learning/bank
 *
 * 夹具是真实源码片段，落进临时的 scripts 目录与临时的 learning 根目录。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const catalog = require("../tools/import-catalog.js")

// 与 tests/legacy.test.js 里同一份真实片段
const GEN_EXCERPT = `
function lc(title, id, diff, tags) {
  return { title, platform: "leetcode", problemId: id, difficulty: diff,
    tags: Array.isArray(tags) ? tags : [tags] };
}
function jz(title, id, diff, tags) {
  return { title: "剑指 Offer " + id + ". " + title, platform: "nowcoder",
    problemId: "" + id, difficulty: diff, tags: Array.isArray(tags) ? tags : [tags] };
}

var arrayItems = [
  lc("两数之和", 1, "easy", ["哈希表"]),
  lc("移除元素", 27, "easy", ["双指针"]),
  lc("搜索插入位置", 35, "easy", ["二分查找"]),
  jz("数组中重复的数字", "JZ03", "easy", ["哈希表"]),
  lc("链表中倒数第k个节点", offer22, "easy", ["快慢指针"]),
];

var categories = [
  cat("array", "数组", 1, 1, "📗",
    "数组是最基本的数据结构，连续内存存储、随机访问 O(1)。", arrayItems),
];
`

const EXP_EXCERPT = `
function addProblems(catId, newItems) {
  var cat = cats.filter(function (c) { return c.id === catId; })[0];
}

addProblems("two-pointers", [
  lc("三数之和", 15, "medium", ["排序", "双指针"]),
  lc("两数之和 II", 167, "easy", ["对撞指针"]),
  jz("合并两个排序的链表", "JZ25", "easy", ["链表"]),
]);
`

const SPLIT_EXCERPT = `
var SRC = path.resolve(
  __dirname, "..", "project", "reading-radar", "data", "app", "practice-data.js",
);
var src = fs.readFileSync(SRC, "utf-8");
`

function tempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix))
}

/** 造一个临时 scripts 目录，把三个死脚本的片段放进去 */
function tempScriptsDir() {
  const dir = tempDir("algo-plan-scripts-")
  fs.writeFileSync(path.join(dir, "gen-practice-data.js"), GEN_EXCERPT, "utf8")
  fs.writeFileSync(path.join(dir, "expand-practice.js"), EXP_EXCERPT, "utf8")
  fs.writeFileSync(path.join(dir, "split-practice-data.js"), SPLIT_EXCERPT, "utf8")
  return dir
}

test("导入器把题目写进 learning/bank/<track>/<id>.md", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  const result = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })

  assert.deepStrictEqual(result.errors, [])
  assert.strictEqual(result.written.length, 7)
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00001.md")))
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "nc-00003.md")))
  assert.ok(fs.existsSync(path.join(root, "bank", "interview", "lc-00015.md")))
  assert.ok(fs.existsSync(path.join(root, "bank", "interview", "nc-00025.md")))
  // 绝不能出现 learning/bank/data/（learning/.gitignore 忽略了 data/）
  assert.ok(!fs.existsSync(path.join(root, "bank", "data")))
})

test("落盘的题目 needs_fill 为 true，难度与标签都对", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })

  const text = fs.readFileSync(path.join(root, "bank", "fundamentals", "lc-00001.md"), "utf8")
  assert.ok(text.indexOf("needs_fill: true") !== -1, text)
  assert.ok(text.indexOf("title: 两数之和") !== -1, text)
  assert.ok(text.indexOf("difficulty: easy") !== -1, text)
  assert.ok(text.indexOf("source: leetcode") !== -1, text)
  assert.ok(text.indexOf("tracks: [fundamentals]") !== -1, text)

  const jzText = fs.readFileSync(path.join(root, "bank", "fundamentals", "nc-00003.md"), "utf8")
  assert.ok(jzText.indexOf("source: nowcoder") !== -1, jzText)
  assert.ok(jzText.indexOf("title: 剑指 Offer JZ03. 数组中重复的数字") !== -1, jzText)
})

test("题号不可用的条目被跳过并记告警，不猜题号", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  const result = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })
  assert.ok(!fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00022.md")))
  const joined = result.warnings.join("\n")
  assert.ok(joined.indexOf("offer22") !== -1, joined)
})

test("没有内联清单的脚本记告警，不算错误", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  const result = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })
  assert.deepStrictEqual(result.errors, [])
  const joined = result.warnings.join("\n")
  assert.ok(joined.indexOf("split-practice-data.js") !== -1, joined)
  assert.ok(joined.indexOf("没有找到内联题目清单") !== -1, joined)
})

test("重复导入默认跳过，--force 才覆盖", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })

  const again = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root })
  assert.strictEqual(again.written.length, 0)
  assert.strictEqual(again.skipped.length, 7)

  const forced = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root, force: true })
  assert.strictEqual(forced.written.length, 7)
  assert.strictEqual(forced.skipped.length, 0)
})

test("dry-run 只报告，不落盘", function () {
  const root = tempDir("algo-plan-bank-")
  const scripts = tempScriptsDir()
  const result = catalog.run({ env: {}, scriptsDir: scripts, learningRoot: root, dryRun: true })
  assert.strictEqual(result.written.length, 7)
  assert.strictEqual(fs.readdirSync(path.join(root, "bank", "fundamentals")).length, 0)
})

test("没设 learning 仓时导入报错而不是静默成功", function () {
  const result = catalog.run({ env: {} })
  assert.strictEqual(result.written.length, 0)
  assert.strictEqual(result.errors.length, 1)
})

test("死脚本目录不存在时记错误", function () {
  const root = tempDir("algo-plan-bank-")
  const result = catalog.run({ env: {}, scriptsDir: path.join(root, "根本没有这个目录"), learningRoot: root })
  assert.strictEqual(result.written.length, 0)
  assert.strictEqual(result.errors.length, 1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../tools/import-catalog.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/tools/import-catalog.js`：

```javascript
"use strict"
/**
 * import-catalog.js —— 把三个死脚本里的内联题目清单导入 learning/bank/
 *
 * 对应设计文档 §3.5 的 B 路（复活死代码）。
 *
 * 用法：
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-catalog.js --dry-run
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-catalog.js
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-catalog.js --force
 *
 * 死脚本**绝不执行**，只做静态解析（原因见 core/bank/legacy.js 的注释）。
 * 本工具**绝不**碰 learning 仓的 git（不 commit、不 push）。
 */

const fs = require("node:fs")
const path = require("node:path")

const { resolveLearningRoot } = require("../core/paths.js")
const { serializeProblemMarkdown } = require("../core/bank/parse.js")
const { createProblem } = require("../core/bank/problem.js")
const legacy = require("../core/bank/legacy.js")

/** 要扫的三个死脚本，顺序固定 */
const SCRIPT_FILES = ["gen-practice-data.js", "expand-practice.js", "split-practice-data.js"]

/** 死脚本默认在 projects/scripts/ */
const DEFAULT_SCRIPTS_DIR = path.resolve(__dirname, "..", "..", "..", "scripts")

/**
 * 主流程。
 * @param {{env?: object, dryRun?: boolean, force?: boolean, scriptsDir?: string, learningRoot?: string}} opts
 * @returns {{written: string[], skipped: string[], errors: string[], warnings: string[]}}
 */
function run(opts) {
  const options = opts || {}
  const written = []
  const skipped = []
  const errors = []
  const warnings = []

  const learning = resolveLearningRoot(options.env || process.env, options.learningRoot)
  if (!learning.ok) {
    return { written: written, skipped: skipped, errors: [learning.reason], warnings: warnings }
  }

  const scriptsDir = options.scriptsDir || DEFAULT_SCRIPTS_DIR
  const sources = []
  SCRIPT_FILES.forEach(function (name) {
    const file = path.join(scriptsDir, name)
    if (!fs.existsSync(file)) {
      warnings.push("死脚本不存在，已跳过：" + file)
      return
    }
    sources.push({ name: name, file: file })
  })
  if (sources.length === 0) {
    errors.push("死脚本目录里一个脚本都没找到：" + scriptsDir)
    return { written: written, skipped: skipped, errors: errors, warnings: warnings }
  }

  // 1. 逐个脚本静态解析
  const categories = []
  sources.forEach(function (src) {
    const parsed = legacy.parseLegacyCategories(fs.readFileSync(src.file, "utf8"))
    parsed.warnings.forEach(function (w) { warnings.push(src.name + "：" + w) })
    parsed.categories.forEach(function (cat) {
      categories.push({ slug: cat.slug, title: cat.title, items: cat.items })
    })
  })
  if (categories.length === 0) {
    errors.push("三个死脚本里没解析出任何分类")
    return { written: written, skipped: skipped, errors: errors, warnings: warnings }
  }

  // 2. 同一道题出现在多个分类 → 轨道取并集、标签取并集，只写一个文件
  const byId = Object.create(null)
  const order = []
  const unknownSlugs = Object.create(null)
  categories.forEach(function (cat) {
    const track = legacy.mapCategoryToTrack(cat.slug)
    if (!Object.prototype.hasOwnProperty.call(legacy.CATEGORY_TRACK_MAP, cat.slug)) {
      unknownSlugs[cat.slug] = true
    }
    cat.items.forEach(function (item) {
      let id
      try {
        id = legacy.legacyIdOf(item)
      } catch (e) {
        warnings.push("ID 生成失败，已跳过：" + item.title + "（" + e.message + "）")
        return
      }
      const exist = byId[id]
      if (!exist) {
        byId[id] = {
          id: id,
          source: item.platform,
          title: item.title,
          difficulty: item.difficulty,
          tracks: [track],
          topics: legacy.normalizeLegacyTopics(item.tags),
        }
        order.push(id)
        return
      }
      if (exist.tracks.indexOf(track) === -1) exist.tracks.push(track)
      item.tags.forEach(function (tag) {
        const topic = legacy.normalizeLegacyTopic(tag)
        if (topic !== "" && exist.topics.indexOf(topic) === -1) exist.topics.push(topic)
      })
    })
  })
  Object.keys(unknownSlugs).forEach(function (slug) {
    warnings.push("分类 slug 不在映射表里，已落到兜底轨道 " + legacy.FALLBACK_TRACK + "：" + slug)
  })

  // 3. 落盘
  const bankDir = path.join(learning.root, "bank")
  order.forEach(function (id) {
    const data = byId[id]
    let problem
    try {
      problem = createProblem({
        id: data.id,
        source: data.source,
        title: data.title,
        // 实测死脚本里只有 easy / medium，没有 hard
        difficulty: data.difficulty === "easy" ? "easy" : "medium",
        topics: data.topics.length > 0 ? data.topics : ["未分类"],
        tracks: data.tracks,
        status: "todo",
        // 死脚本只有元数据，没有题面与测试用例
        needsFill: true,
        statement: "",
        cases: [],
        solution: "",
        solutionLang: "",
      })
    } catch (e) {
      errors.push(data.id + " 字段非法：" + e.message)
      return
    }
    const target = path.join(bankDir, problem.tracks[0], problem.id + ".md")
    if (fs.existsSync(target) && !options.force) {
      skipped.push(target)
      return
    }
    if (!options.dryRun) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, serializeProblemMarkdown(problem), "utf8")
    }
    written.push(target)
  })

  return { written: written, skipped: skipped, errors: errors, warnings: warnings }
}

/**
 * 命令行入口。
 */
function main() {
  const argv = process.argv.slice(2)
  const dryRun = argv.indexOf("--dry-run") !== -1
  const force = argv.indexOf("--force") !== -1
  const result = run({ dryRun: dryRun, force: force })

  if (result.errors.length > 0) {
    console.error("导入失败：")
    result.errors.forEach(function (line) { console.error("  · " + line) })
    process.exit(1)
  }

  console.log((dryRun ? "（试运行）将要写入：" : "已写入：") + result.written.length + " 道题")
  result.written.forEach(function (line) { console.log("  + " + line) })
  if (result.skipped.length > 0) {
    console.log("已存在跳过：" + result.skipped.length + " 道（要覆盖加 --force）")
  }
  if (result.warnings.length > 0) {
    console.log("告警 " + result.warnings.length + " 条：")
    result.warnings.slice(0, 20).forEach(function (line) { console.log("  ! " + line) })
    if (result.warnings.length > 20) {
      console.log("  （其余 " + (result.warnings.length - 20) + " 条省略）")
    }
  }
  console.log("提示：导入器不碰 learning 仓的 git，是否提交由你自己决定。")
}

if (require.main === module) {
  main()
}

module.exports = {
  run: run,
  main: main,
  SCRIPT_FILES: SCRIPT_FILES,
  DEFAULT_SCRIPTS_DIR: DEFAULT_SCRIPTS_DIR,
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `11 / 11 套件通过`，退出码 0

- [ ] **Step 5: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加死脚本题库的导入器

- tools/import-catalog.js：静态解析三个死脚本，写出 learning/bank/<track>/<id>.md
- 同一题出现在多个分类时轨道与标签取并集，只写一个文件
- 未知分类 slug 落到兜底轨道 interview 并计告警
- 导入的题一律 needs_fill=true，难度只有 easy/medium，标签走别名表归一化
- id 冲突默认跳过计入 skipped，--force 才覆盖；--dry-run 只报告不落盘
- 没设 learning 仓时直接报错，不静默成功
- 测试：落盘位置、needs_fill、坏题号跳过、无清单脚本告警、重复导入、dry-run 共 8 条断言"
git push origin main
```

---

## Task 4: 题解导入器 `tools/import-solutions.js`

**Files:**
- Create: `projects/apps/algo-plan/tools/import-solutions.js`
- Create: `projects/apps/algo-plan/tests/import-solutions.test.js`

**Interfaces:**
- Consumes: Task 2 的 `core/bank/solutions-scan.js`；M1 的 `core/paths.js`、`core/bank/parse.js`、`core/bank/problem.js`
- Produces:
  - `tools/import-solutions.js` 导出：
    - `run(opts) -> {written: string[], skipped: string[], errors: string[], warnings: string[]}`
      （与 `import-catalog.js` 同形；`opts = {env, dryRun?, force?, scriptsDir?, learningRoot?}`，
      本工具**不用** `scriptsDir`——它的来源就是 learning 仓本身）
    - `SCAN_ROOTS` —— `["code-solutions/c/src", "algo-c"]`（相对 learning 根目录）
    - `main()` —— 命令行入口
  - `learning/bank/<track>/<id>.md` 里的**带参考解法的题目文件**（`needs_fill: true`）

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/import-solutions.test.js`：

```javascript
"use strict"
/**
 * import-solutions.test.js —— 存量题解导入 learning/bank
 *
 * 夹具是 learning 仓里的真实文件节选，落进临时的 learning 根目录。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const solutions = require("../tools/import-solutions.js")

// 真实片段：learning/code-solutions/c/src/c/leetcode_1_100.c
const C_RANGE_EXCERPT = `#include <stdlib.h>
#include <math.h>

#include "common.h"

// leetcode 56

int **merge(int **intervals, int intervalsSize, int *intervalsColSize, int **returnColumnSizes)
{
    (void)intervalsColSize; // Suppress unused parameter warning

    int **ans = malloc(sizeof(int *) * intervalsSize);
    *returnColumnSizes = malloc(sizeof(int) * intervalsSize);

    for (int i = 0; i < intervalsSize; i++) {
        ans[i] = (int *)malloc(sizeof(int) * 2);
    }

    qsort(intervals, intervalsSize, sizeof(int *), int_cmp);

    int count = 0;
    for (int i = 0; i < intervalsSize; i++) {
        int L = intervals[i][0], R = intervals[i][1];
        if (count == 0 || ans[count - 1][1] < L) {
            returnColumnSizes[0][count] = 2;
            ans[count][0] = L;
            ans[count][1] = R;
            count++;
        } else {
            ans[count - 1][1] = fmax(ans[count - 1][1], R);
        }
    }

    *returnSize = count;
    return ans;
}

// leetcode 75
void sortColors_qsort(int *nums, int numsSize)
{
}
`

// 真实片段：learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp
const SINGLE_FILE_EXCERPT = `#include <iostream>
#include <string>
using namespace std;

class Solution {
public:
    bool isPrefix(string sentence, int start, int end, string searchWord)
    {
        for (int i = 0; i < searchWord.size(); i++) {
            if (start + i > end || sentence[i] != searchWord[i]) {
                return false;
            }
        }
    }
}
`

// 真实片段：learning/algo-c/sliding_window/README.md 的题号表
const README_EXCERPT = `# 滑动窗口 (Sliding Window)

## LeetCode 题目

| 题号 | 题目 | 难度 |
|------|------|------|
| 1984 | [学生分数的最小差值](../1984_minimum_difference/) | 简单 |
`

function tempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix))
}

/** 造一个临时的 learning 仓根目录，塞进真实的题解文件片段 */
function tempLearningRoot() {
  const root = tempDir("algo-plan-sol-")
  const cDir = path.join(root, "code-solutions", "c", "src", "c")
  fs.mkdirSync(cDir, { recursive: true })
  fs.writeFileSync(path.join(cDir, "leetcode_1_100.c"), C_RANGE_EXCERPT, "utf8")

  const singleDir = path.join(root, "algo-c", "problems", "leetcode_1455")
  fs.mkdirSync(singleDir, { recursive: true })
  fs.writeFileSync(path.join(singleDir, "leetcode_1455.cpp"), SINGLE_FILE_EXCERPT, "utf8")

  const topicDir = path.join(root, "algo-c", "sliding_window", "problems", "1984_minimum_difference")
  fs.mkdirSync(topicDir, { recursive: true })
  fs.writeFileSync(path.join(topicDir, "leetcode_1984.cpp"), SINGLE_FILE_EXCERPT, "utf8")
  fs.writeFileSync(
    path.join(root, "algo-c", "sliding_window", "README.md"),
    README_EXCERPT,
    "utf8"
  )
  return root
}

test("题解导入器把题目写进 learning/bank/<track>/<id>.md", function () {
  const root = tempLearningRoot()
  const result = solutions.run({ env: {}, learningRoot: root })

  assert.deepStrictEqual(result.errors, [])
  assert.strictEqual(result.written.length, 4)
  // 区间文件里的两道题
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00056.md")))
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00075.md")))
  // 单题文件（没有专题信息 → 落到默认轨道）
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-01455.md")))
  // 专题目录里的题（滑动窗口 → interview 轨道）
  assert.ok(fs.existsSync(path.join(root, "bank", "interview", "lc-01984.md")))
})

test("落盘的题带参考解法，needs_fill 为 true", function () {
  const root = tempLearningRoot()
  solutions.run({ env: {}, learningRoot: root })

  const text = fs.readFileSync(path.join(root, "bank", "fundamentals", "lc-00056.md"), "utf8")
  assert.ok(text.indexOf("needs_fill: true") !== -1, text)
  assert.ok(text.indexOf("## 参考解法") !== -1, text)
  assert.ok(text.indexOf("```c") !== -1, text)
  assert.ok(text.indexOf("int **merge(") !== -1, text)
  assert.ok(text.indexOf("int main") === -1, "存量题解没有 main，不该凭空生成")
})

test("README 索引里的中文题名与难度被用上", function () {
  const root = tempLearningRoot()
  solutions.run({ env: {}, learningRoot: root })

  const text = fs.readFileSync(path.join(root, "bank", "interview", "lc-01984.md"), "utf8")
  assert.ok(text.indexOf("title: 学生分数的最小差值") !== -1, text)
  assert.ok(text.indexOf("difficulty: easy") !== -1, text)
  assert.ok(text.indexOf("topics: [滑动窗口]") !== -1, text)
  assert.ok(text.indexOf("tracks: [interview]") !== -1, text)
})

test("命名不符合约定的文件被跳过并记告警", function () {
  const root = tempLearningRoot()
  const interviewDir = path.join(root, "code-solutions", "c", "src", "c")
  fs.writeFileSync(path.join(interviewDir, "interview_17.c"), "// 17.14\n", "utf8")

  const result = solutions.run({ env: {}, learningRoot: root })
  assert.deepStrictEqual(result.errors, [])
  const joined = result.warnings.join("\n")
  assert.ok(joined.indexOf("interview_17.c") !== -1, joined)
})

test("重复导入默认跳过，--force 才覆盖", function () {
  const root = tempLearningRoot()
  solutions.run({ env: {}, learningRoot: root })

  const again = solutions.run({ env: {}, learningRoot: root })
  assert.strictEqual(again.written.length, 0)
  assert.strictEqual(again.skipped.length, 4)

  const forced = solutions.run({ env: {}, learningRoot: root, force: true })
  assert.strictEqual(forced.written.length, 4)
})

test("dry-run 只报告，不落盘", function () {
  const root = tempLearningRoot()
  const result = solutions.run({ env: {}, learningRoot: root, dryRun: true })
  assert.strictEqual(result.written.length, 4)
  assert.ok(!fs.existsSync(path.join(root, "bank")))
})

test("没设 learning 仓时导入报错而不是静默成功", function () {
  const result = solutions.run({ env: {} })
  assert.strictEqual(result.written.length, 0)
  assert.strictEqual(result.errors.length, 1)
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: FAIL，错误信息含 `Cannot find module '../tools/import-solutions.js'`

- [ ] **Step 3: 写实现**

Create `projects/apps/algo-plan/tools/import-solutions.js`：

```javascript
"use strict"
/**
 * import-solutions.js —— 把 learning 仓里的存量题解导入 learning/bank/
 *
 * 对应设计文档 §3.5 的 C 路（存量题解）。
 *
 * 用法：
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-solutions.js --dry-run
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-solutions.js
 *
 * 扫描范围（相对 learning 根目录）：
 *   code-solutions/c/src —— 区间文件，靠 `// leetcode <题号>` 标记定位
 *   algo-c               —— 单题文件（文件名即题号）与专题目录
 * 命名不符合 leetcode_<题号> 约定的文件（interview_17.c、contest/、bit_operations/）一律跳过。
 *
 * 本工具**绝不**碰 learning 仓的 git（不 commit、不 push）。
 */

const fs = require("node:fs")
const path = require("node:path")

const { resolveLearningRoot } = require("../core/paths.js")
const { serializeProblemMarkdown } = require("../core/bank/parse.js")
const { createProblem } = require("../core/bank/problem.js")
const scan = require("../core/bank/solutions-scan.js")

/** 扫描范围（相对 learning 根目录） */
const SCAN_ROOTS = ["code-solutions/c/src", "algo-c"]

/** 递归列出目录下的 .c / .cpp 文件 */
function listSourceFiles(dir, out) {
  const result = out || []
  let entries
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
  } catch (e) {
    return result
  }
  entries.forEach(function (entry) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      listSourceFiles(abs, result)
      return
    }
    if (entry.isFile() && /\.(c|cpp)$/i.test(entry.name)) result.push(abs)
  })
  return result
}

/** 收集 learning/algo-c/*/README.md（专题索引表） */
function listIndexFiles(algoRoot) {
  const out = []
  let entries
  try {
    entries = fs.readdirSync(algoRoot, { withFileTypes: true })
  } catch (e) {
    return out
  }
  entries.forEach(function (entry) {
    if (!entry.isDirectory()) return
    const file = path.join(algoRoot, entry.name, "README.md")
    if (fs.existsSync(file)) out.push(file)
  })
  return out
}

/**
 * 主流程。
 * @param {{env?: object, dryRun?: boolean, force?: boolean, scriptsDir?: string, learningRoot?: string}} opts
 * @returns {{written: string[], skipped: string[], errors: string[], warnings: string[]}}
 */
function run(opts) {
  const options = opts || {}
  const written = []
  const skipped = []
  const errors = []
  const warnings = []

  const learning = resolveLearningRoot(options.env || process.env, options.learningRoot)
  if (!learning.ok) {
    return { written: written, skipped: skipped, errors: [learning.reason], warnings: warnings }
  }

  // 1. 读专题索引表（README 里的「题号 / 题目 / 难度」）
  const algoRoot = path.join(learning.root, "algo-c")
  const indexFiles = listIndexFiles(algoRoot).map(function (file) {
    return { path: file, text: fs.readFileSync(file, "utf8") }
  })
  const index = scan.parseSolutionIndex(indexFiles)
  index.warnings.forEach(function (w) { warnings.push(w) })

  // 2. 收集候选文件：基名匹配 leetcode_<题号> 或 leetcode_<起>_<止>
  const candidates = []
  const rejected = []
  SCAN_ROOTS.forEach(function (rel) {
    listSourceFiles(path.join(learning.root, rel)).forEach(function (file) {
      const base = path.basename(file)
      if (scan.FILENAME_PATTERN.test(base) || scan.RANGE_FILENAME_PATTERN.test(base)) {
        candidates.push({ path: file, text: fs.readFileSync(file, "utf8") })
        return
      }
      rejected.push(file)
    })
  })
  rejected.forEach(function (file) {
    warnings.push("文件名不符合 leetcode_<题号> 约定，已跳过：" + path.relative(learning.root, file))
  })

  // 3. 解析成题目条目
  const parsed = scan.parseSolutionFiles(candidates, index.byId)
  parsed.warnings.forEach(function (w) { warnings.push(w) })

  // 4. 落盘（同一题号只写一份，后出现的记 skipped）
  const bankDir = path.join(learning.root, "bank")
  const seen = Object.create(null)
  parsed.items.forEach(function (item) {
    let id
    try {
      id = scan.solutionIdOf(item)
    } catch (e) {
      warnings.push("ID 生成失败，已跳过：" + item.title + "（" + e.message + "）")
      return
    }
    if (seen[id]) {
      skipped.push(id + "（同一题号有多个解法，保留先出现的：" + seen[id] + "）")
      return
    }
    seen[id] = item.file

    const topic = scan.topicOfSolutionFile(item.file) || scan.DEFAULT_SOLUTION_TOPIC
    const track = scan.trackOfSolutionTopic(topic)
    const meta = index.byId[Number(item.sourceId)] ? index.byId[Number(item.sourceId)] : null

    let problem
    try {
      problem = createProblem({
        id: id,
        source: item.source,
        title: item.title,
        // 查不到难度时默认 medium（存量题解本身没有难度信息）
        difficulty: meta ? meta.difficulty : "medium",
        topics: [topic],
        tracks: [track],
        status: "todo",
        // 题面与测试用例本来就缺
        needsFill: true,
        statement: "",
        cases: [],
        solution: item.code,
        solutionLang: item.lang,
      })
    } catch (e) {
      errors.push(id + " 字段非法：" + e.message)
      return
    }

    const target = path.join(bankDir, problem.tracks[0], problem.id + ".md")
    if (fs.existsSync(target) && !options.force) {
      skipped.push(target)
      return
    }
    if (!options.dryRun) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, serializeProblemMarkdown(problem), "utf8")
    }
    written.push(target)
  })

  return { written: written, skipped: skipped, errors: errors, warnings: warnings }
}

/**
 * 命令行入口。
 */
function main() {
  const argv = process.argv.slice(2)
  const dryRun = argv.indexOf("--dry-run") !== -1
  const force = argv.indexOf("--force") !== -1
  const result = run({ dryRun: dryRun, force: force })

  if (result.errors.length > 0) {
    console.error("导入失败：")
    result.errors.forEach(function (line) { console.error("  · " + line) })
    process.exit(1)
  }

  console.log((dryRun ? "（试运行）将要写入：" : "已写入：") + result.written.length + " 道题")
  result.written.forEach(function (line) { console.log("  + " + line) })
  if (result.skipped.length > 0) {
    console.log("已存在跳过：" + result.skipped.length + " 道（要覆盖加 --force）")
  }
  if (result.warnings.length > 0) {
    console.log("告警 " + result.warnings.length + " 条：")
    result.warnings.slice(0, 20).forEach(function (line) { console.log("  ! " + line) })
    if (result.warnings.length > 20) {
      console.log("  （其余 " + (result.warnings.length - 20) + " 条省略）")
    }
  }
  console.log("提示：导入器不碰 learning 仓的 git，是否提交由你自己决定。")
}

if (require.main === module) {
  main()
}

module.exports = {
  run: run,
  main: main,
  SCAN_ROOTS: SCAN_ROOTS,
  listSourceFiles: listSourceFiles,
  listIndexFiles: listIndexFiles,
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
git commit -m "feat(algo-plan): 增加存量题解的导入器

- tools/import-solutions.js：扫 learning 的 code-solutions 与 algo-c，写出 learning/bank/<track>/<id>.md
- 收录基名匹配 leetcode_<题号> 或 leetcode_<起>_<止> 的 .c/.cpp，其余文件跳过并记告警
- 专题目录 sliding_window / prefix_sum 认成标签与轨道，其余落到「未分类」与 fundamentals
- 参考解法原样带进「## 参考解法」段落，语言按 .c / .cpp 记
- 同一题号有多个解法时保留先出现的，后出现的计入 skipped
- 导入的题一律 needs_fill=true，难度查不到时默认 medium
- 测试：落盘位置、参考解法、索引题名难度、命名过滤、重复导入、dry-run 共 7 条断言"
git push origin main
```

---

## Task 5: 端到端验收、README 与一次性真实导入

**Files:**
- Create: `projects/apps/algo-plan/tests/m2-e2e.test.js`
- Modify: `projects/apps/algo-plan/README.md`

**Interfaces:**
- Consumes: Task 3 的 `tools/import-catalog.js` 的 `run(opts)`、Task 4 的 `tools/import-solutions.js` 的 `run(opts)`、M1 的 `core/bank/parse.js` 的 `parseProblemMarkdown(text)`、M1 的 `core/bank/problem.js` 的 `isValidId(id)`
- Produces: `projects/apps/algo-plan/tools/bank-files.js`（`indexExistingProblems(bankDir)`，按 id 找已存在的题库文件）、`projects/apps/algo-plan/tools/import-bank.js`（`run(opts)` / `main()`，一次性把两路来源都导进去）、`projects/apps/algo-plan/tests/m2-e2e.test.js`（14 个用例）、改用 id 级冲突判断的 `tools/import-catalog.js` 与 `tools/import-solutions.js`、更新后的 `projects/apps/algo-plan/README.md`、`learning/bank/<track>/<id>.md`（一次性真实导入的产物）

> **本 Task 顺带修一个真实的冲突漏洞。** Task 3 / Task 4 判断冲突时只看「自己算出来的那条路径」
> （`bank/<自己那条轨道>/<id>.md`）。但同一道题在两路来源里算出来的轨道**可能不一样**，
> 只查自己那条路径就会漏判，**同一个 id 会写出两份文件**，provider 列表里就重了，
> `GET /api/problem/:id` 也会指向不确定的那一份。
> 契约 §6 的 G19 写的是「**同 id** 已存在则跳过」，所以必须按 id 找——本 Task 把两个导入器都改成按 id 找。
>
> **这不是假想问题，真实数据里就有 5 道：** 存量题解那 31 道题在目录来源里也有 16 道同 id，
> 其中 5 道的轨道对不上（目录来源按**首次出现**的分类定轨道，题解来源没有专题信息就落 `fundamentals`）：
>
> | id | 目录来源首次出现的分类 | 目录来源的轨道 | 题解来源算出的轨道 | 只按路径判冲突的后果 |
> |---|---|---|---|---|
> | `lc-00004` | `binary-search` | `interview` | `fundamentals` | 写出两份同 id 的文件 |
> | `lc-00007` | `math` | `advanced` | `fundamentals` | 写出两份同 id 的文件 |
> | `lc-00009` | `math` | `advanced` | `fundamentals` | 写出两份同 id 的文件 |
> | `lc-00075` | `two-pointers` | `interview` | `fundamentals` | 写出两份同 id 的文件 |
> | `lc-00326` | `math` | `advanced` | `fundamentals` | 写出两份同 id 的文件 |
>
> 其余 11 道重叠题的轨道都是 `fundamentals`，路径撞上了，本来就能被跳过。
> 改成按 id 找之后，这 16 道题一律只留一份（见 `tests/m2-e2e.test.js` 里的
> 「与目录同 id 的题按 id 判冲突，不写出第二份」）。

- [ ] **Step 1: 写失败的测试**

Create `projects/apps/algo-plan/tests/m2-e2e.test.js`：

```javascript
"use strict"
/**
 * m2-e2e.test.js —— M2 端到端：死脚本 / 存量题解 → learning/bank/<track>/<id>.md → 再读回来
 *
 * 全程用临时目录当 learning 仓，绝不碰真实的 C:/code/StillEvolving/learning。
 * 夹具是真实文件格式的小样本：死脚本 4 道题、题解 4 个文件。
 */

const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const importBank = require("../tools/import-bank.js")
const importCatalog = require("../tools/import-catalog.js")
const importSolutions = require("../tools/import-solutions.js")
const { parseProblemMarkdown } = require("../core/bank/parse.js")
const { isValidId } = require("../core/bank/problem.js")

/** 建临时目录 */
function tmpDir(tag) {
  return fs.mkdtempSync(path.join(os.tmpdir(), "algo-plan-m2-" + tag + "-"))
}

/** 写文件（自动建目录） */
function writeFile(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, text, "utf8")
}

/** 死脚本夹具：照抄 projects/scripts/gen-practice-data.js 的真实写法 */
const FIXTURE_SCRIPT = [
  'function lc(title, id, diff, tags) {',
  '  return {',
  '    title,',
  '    platform: "leetcode",',
  '    problemId: id,',
  '    difficulty: diff,',
  '    tags: Array.isArray(tags) ? tags : [tags],',
  '  };',
  '}',
  'var arrayItems = [',
  '  lc("两数之和", 1, "easy", ["哈希表"]),',
  '  lc("移除元素", 27, "easy", ["双指针"]),',
  '  lc("三数之和", 15, "medium", ["排序"]),',
  '];',
  'var hashItems = [',
  '  lc("两数之和", 1, "easy", ["哈希表"]),',
  '];',
  'var dpItems = [',
  '  lc("爬楼梯", 70, "easy", ["动态规划"]),',
  '];',
  'var categories = [',
  '  cat("array", "数组", 1, 1, "📗", "数组是最基本的数据结构。", arrayItems),',
  '  cat("hash-table", "哈希表", 2, 2, "📕", "哈希表。", hashItems),',
  '  cat("dp-basic", "动态规划", 3, 3, "📘", "动态规划。", dpItems),',
  '];',
  '',
].join("\n")

/** 题解夹具 1：区间文件 + 标记注释（照抄 learning/code-solutions/c/src/c/leetcode_1_100.c） */
const FIXTURE_RANGE_C = [
  '#include <stdlib.h>',
  '#include <math.h>',
  '',
  '#include "common.h"',
  '',
  '// leetcode 56',
  '',
  'int **merge(int **intervals, int intervalsSize, int *intervalsColSize, int **returnColumnSizes)',
  '{',
  '    return intervals;',
  '}',
  '',
].join("\n")

/** 题解夹具 2：单题文件（照抄 learning/algo-c/problems/leetcode_1455/leetcode_1455.cpp） */
const FIXTURE_SINGLE_CPP = [
  '#include <iostream>',
  '#include <string>',
  'using namespace std;',
  '',
  'class Solution {',
  'public:',
  '    bool isPrefix(string sentence, int start, int end, string searchWord)',
  '    {',
  '        for (int i = 0; i < searchWord.size(); i++) {',
  '        }',
  '        return true;',
  '    }',
  '};',
  '',
].join("\n")

/** 题解夹具 3：专题目录下的单题文件（照抄 learning/algo-c/sliding_window/problems/1984_minimum_difference/leetcode_1984.cpp） */
const FIXTURE_TOPIC_CPP = [
  '#include <vector>',
  '#include <algorithm>',
  'using namespace std;',
  '',
  'class Solution {',
  'public:',
  '    int minimumDifference(vector<int>& nums, int k) {',
  '        sort(nums.begin(), nums.end());',
  '        return 0;',
  '    }',
  '};',
  '',
].join("\n")

/** 题解夹具 4：与目录来源同 id 的题（lc-00070），两边算出的轨道不同，专门验 id 级冲突判断
 *  （真实数据里同样的情况有 5 道：lc-00004 / lc-00007 / lc-00009 / lc-00075 / lc-00326） */
const FIXTURE_SAME_ID_CPP = [
  '#include <vector>',
  'using namespace std;',
  '',
  'class Solution {',
  'public:',
  '    int climbStairs(int n) {',
  '        return n <= 2 ? n : climbStairs(n - 1) + climbStairs(n - 2);',
  '    }',
  '};',
  '',
].join("\n")

/** 专题索引表：照抄 learning/algo-c/sliding_window/README.md 结尾的表 */
const FIXTURE_INDEX_README = [
  '# 滑动窗口',
  '',
  '## LeetCode 题目',
  '',
  '| 题号 | 题目 | 难度 |',
  '|------|------|------|',
  '| 1984 | [学生分数的最小差值](../1984_minimum_difference/) | 简单 |',
  '',
].join("\n")

/** 必须跳过的两个文件：竞赛题与面经章节号（照抄真实文件名反例） */
const FIXTURE_CONTEST = '// 循环数组中相邻元素的最大差值\nint main() { return 0; }\n'
const FIXTURE_INTERVIEW = '// 17.14\nint main() { return 0; }\n'

/** 建一个带夹具的 learning 仓 */
function makeLearning() {
  const root = tmpDir("learning")
  writeFile(path.join(root, "code-solutions", "c", "src", "c", "leetcode_1_100.c"), FIXTURE_RANGE_C)
  writeFile(path.join(root, "code-solutions", "c", "src", "c", "interview_17.c"), FIXTURE_INTERVIEW)
  writeFile(path.join(root, "algo-c", "problems", "leetcode_1455", "leetcode_1455.cpp"), FIXTURE_SINGLE_CPP)
  writeFile(path.join(root, "algo-c", "problems", "leetcode_70", "leetcode_70.cpp"), FIXTURE_SAME_ID_CPP)
  writeFile(path.join(root, "algo-c", "sliding_window", "problems", "1984_minimum_difference", "leetcode_1984.cpp"), FIXTURE_TOPIC_CPP)
  writeFile(path.join(root, "algo-c", "sliding_window", "README.md"), FIXTURE_INDEX_README)
  writeFile(path.join(root, "algo-c", "contest", "Weekly_match", "433", "433_1.cpp"), FIXTURE_CONTEST)
  return root
}

/** 建一个带夹具的死脚本目录 */
function makeScripts() {
  const dir = tmpDir("scripts")
  writeFile(path.join(dir, "gen-practice-data.js"), FIXTURE_SCRIPT)
  return dir
}

/** 列出 bank 下的全部文件（绝对路径） */
function listBankFiles(root) {
  const out = []
  function walk(dir) {
    let entries
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true })
    } catch (e) {
      return
    }
    entries.forEach(function (entry) {
      const abs = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        walk(abs)
        return
      }
      out.push(abs)
    })
  }
  walk(path.join(root, "bank"))
  return out
}

/** 读回一个题库文件并解析 */
function readProblem(root, track, id) {
  const file = path.join(root, "bank", track, id + ".md")
  return { file: file, parsed: parseProblemMarkdown(fs.readFileSync(file, "utf8")) }
}

test("目录导入：死脚本的题落成 learning/bank/<track>/<id>.md", function () {
  const root = makeLearning()
  const result = importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  assert.deepStrictEqual(result.errors, [], result.errors.join("\n"))
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00027.md")), "移除元素应落在 fundamentals")
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-00015.md")), "三数之和应落在 fundamentals")
  assert.ok(fs.existsSync(path.join(root, "bank", "advanced", "lc-00070.md")), "爬楼梯属 dp-basic，应落在 advanced")
})

test("目录导入：frontmatter 里 needs_fill 为 true", function () {
  const root = makeLearning()
  importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  const text = fs.readFileSync(path.join(root, "bank", "fundamentals", "lc-00027.md"), "utf8")
  assert.ok(text.indexOf("needs_fill: true") !== -1, text)
})

test("目录导入：题库文件能被 M1 的 parseProblemMarkdown 读回来", function () {
  const root = makeLearning()
  importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  const parsed = readProblem(root, "fundamentals", "lc-00015").parsed
  assert.deepStrictEqual(parsed.warnings, [], parsed.warnings.join("\n"))
  assert.strictEqual(parsed.problem.id, "lc-00015")
  assert.strictEqual(parsed.problem.title, "三数之和")
  assert.strictEqual(parsed.problem.difficulty, "medium")
  assert.deepStrictEqual(parsed.problem.topics, ["排序"])
  assert.strictEqual(parsed.problem.needsFill, true)
})

test("目录导入：同一题出现在两个分类时只写一个文件，轨道取并集", function () {
  const root = makeLearning()
  importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  const files = listBankFiles(root)
  const ones = files.filter(function (f) { return path.basename(f) === "lc-00001.md" })
  assert.strictEqual(ones.length, 1, "lc-00001 只应有一个文件，实际 " + ones.length)
  const parsed = parseProblemMarkdown(fs.readFileSync(ones[0], "utf8"))
  assert.ok(parsed.problem.tracks.indexOf("fundamentals") !== -1, parsed.problem.tracks.join(","))
  assert.ok(parsed.problem.tracks.indexOf("interview") !== -1, parsed.problem.tracks.join(","))
})

test("目录导入：dry-run 一个字节都不写", function () {
  const root = makeLearning()
  const result = importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts(), dryRun: true })
  assert.strictEqual(result.written.length, 4, "应报告将要写 4 道")
  assert.strictEqual(fs.existsSync(path.join(root, "bank")), false, "dry-run 不该建 bank 目录")
})

test("目录导入：id 冲突跳过，--force 才覆盖", function () {
  const root = makeLearning()
  const scripts = makeScripts()
  importCatalog.run({ env: {}, learningRoot: root, scriptsDir: scripts })
  const target = path.join(root, "bank", "fundamentals", "lc-00027.md")
  fs.writeFileSync(target, "改坏了", "utf8")
  const second = importCatalog.run({ env: {}, learningRoot: root, scriptsDir: scripts })
  assert.ok(second.skipped.some(function (p) { return p === target }), second.skipped.join("\n"))
  assert.strictEqual(fs.readFileSync(target, "utf8"), "改坏了", "没加 force 不该覆盖")
  const third = importCatalog.run({ env: {}, learningRoot: root, scriptsDir: scripts, force: true })
  assert.ok(third.written.some(function (p) { return p === target }), third.written.join("\n"))
  assert.ok(fs.readFileSync(target, "utf8").indexOf("id: lc-00027") !== -1, "force 后应写回题库文件")
})

test("题解导入：单题文件按文件名取题号", function () {
  const root = makeLearning()
  const result = importSolutions.run({ env: {}, learningRoot: root })
  assert.deepStrictEqual(result.errors, [], result.errors.join("\n"))
  assert.ok(fs.existsSync(path.join(root, "bank", "fundamentals", "lc-01455.md")), "leetcode_1455 应落成 lc-01455")
})

test("题解导入：区间文件按 // leetcode 标记切分", function () {
  const root = makeLearning()
  importSolutions.run({ env: {}, learningRoot: root })
  const target = path.join(root, "bank", "fundamentals", "lc-00056.md")
  assert.ok(fs.existsSync(target), "leetcode_1_100.c 里的 // leetcode 56 应落成 lc-00056")
  assert.ok(fs.readFileSync(target, "utf8").indexOf("int **merge") !== -1, "参考解法应带上原代码")
})

test("题解导入：专题目录认成标签与轨道", function () {
  const root = makeLearning()
  importSolutions.run({ env: {}, learningRoot: root })
  const target = path.join(root, "bank", "interview", "lc-01984.md")
  assert.ok(fs.existsSync(target), "sliding_window 专题应落成 interview 轨道")
  const parsed = parseProblemMarkdown(fs.readFileSync(target, "utf8"))
  assert.deepStrictEqual(parsed.problem.topics, ["滑动窗口"])
})

test("题解导入：README 索引里的中文题名与难度被带进来", function () {
  const root = makeLearning()
  importSolutions.run({ env: {}, learningRoot: root })
  const parsed = readProblem(root, "interview", "lc-01984").parsed
  assert.strictEqual(parsed.problem.title, "学生分数的最小差值")
  assert.strictEqual(parsed.problem.difficulty, "easy")
})

test("题解导入：参考解法写进「## 参考解法」段落", function () {
  const root = makeLearning()
  importSolutions.run({ env: {}, learningRoot: root })
  const text = fs.readFileSync(path.join(root, "bank", "interview", "lc-01984.md"), "utf8")
  assert.ok(text.indexOf("## 参考解法") !== -1, text)
  assert.ok(text.indexOf("```cpp") !== -1, text)
  assert.ok(text.indexOf("minimumDifference") !== -1, text)
})

test("题解导入：命名不合约定的文件跳过并记告警，且不建 bank/data 目录", function () {
  const root = makeLearning()
  const result = importSolutions.run({ env: {}, learningRoot: root })
  assert.ok(result.warnings.some(function (w) { return w.indexOf("interview_17.c") !== -1 }), result.warnings.join("\n"))
  assert.ok(result.warnings.some(function (w) { return w.indexOf("433_1.cpp") !== -1 }), result.warnings.join("\n"))
  assert.strictEqual(fs.existsSync(path.join(root, "bank", "data")), false, "不许建 bank/data 目录")
})

test("题解导入：与目录同 id 的题按 id 判冲突，不写出第二份", function () {
  const root = makeLearning()
  importCatalog.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  const result = importSolutions.run({ env: {}, learningRoot: root })
  assert.ok(
    result.skipped.some(function (item) { return item.indexOf("lc-00070") !== -1 }),
    "lc-00070 应被跳过：" + result.skipped.join("\n")
  )
  const sevens = listBankFiles(root).filter(function (f) { return path.basename(f) === "lc-00070.md" })
  assert.strictEqual(sevens.length, 1, "lc-00070 只应有一份，实际 " + sevens.length + "：" + sevens.join(", "))
})

test("import-bank.js：先目录后题解，一次把两路来源都导进去", function () {
  const root = makeLearning()
  const result = importBank.run({ env: {}, learningRoot: root, scriptsDir: makeScripts() })
  assert.ok(result.learningRoot, "应解析出 learning 根目录")
  assert.strictEqual(result.catalog.written.length, 4, "目录来源应写 4 道")
  assert.strictEqual(result.solutions.written.length, 3, "题解来源应写 3 道（lc-00070 与目录同 id，被跳过）")
  const files = listBankFiles(root)
  assert.strictEqual(files.length, 7, "两路来源合计 7 个题库文件")
  files.forEach(function (file) {
    const parsed = parseProblemMarkdown(fs.readFileSync(file, "utf8"))
    assert.ok(isValidId(parsed.problem.id), "id 非法：" + parsed.problem.id)
    assert.ok(
      parsed.problem.difficulty === "easy" || parsed.problem.difficulty === "medium",
      "难度只能 easy/medium：" + parsed.problem.difficulty
    )
    assert.ok(
      ["interview", "fundamentals", "advanced", "engineering"].indexOf(parsed.problem.tracks[0]) !== -1,
      "轨道非法：" + parsed.problem.tracks[0]
    )
  })
})
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/m2-e2e.test.js
```

Expected: 报错 `Error: Cannot find module 'C:\code\StillEvolving\projects\apps\algo-plan\tools\import-bank.js'`，
退出码 1（`tools/import-bank.js` 还没建，`tests/m2-e2e.test.js` 整个加载不起来）。

- [ ] **Step 3: 写实现（一）：按 id 找已存在的题库文件**

Create `projects/apps/algo-plan/tools/bank-files.js`：

```javascript
"use strict"
/**
 * bank-files.js —— 题库目录里已有题目的索引（两个导入器共用）
 *
 * 为什么必须按 id 找、不能只按「自己算出来的那条路径」找：
 * 同一道题在两路来源里算出来的轨道可能不一样。
 * 例：lc-00070（爬楼梯）在目录来源里属于 dp-basic → advanced，
 *     在题解来源里没有专题信息 → 未分类 → fundamentals。
 * 只查自己那条路径会漏判冲突，结果同一个 id 写出两份文件，
 * provider 列表里就重了，GET /api/problem/:id 也会指向不确定的那一份。
 * 契约 §6 的 G19 写的是「同 id 已存在则跳过」，所以按 id 找。
 */

const fs = require("node:fs")
const path = require("node:path")

/**
 * 扫一遍题库目录，返回已有题目的 id → 文件绝对路径。
 * 题库布局是 bank/<track>/<id>.md，这里递归扫，认不准的目录也一并看掉。
 * @param {string} bankDir learning/bank 目录（可以不存在）
 * @returns {Object<string,string>} id → 文件绝对路径
 */
function indexExistingProblems(bankDir) {
  const out = Object.create(null)
  function walk(dir) {
    let entries
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true })
    } catch (e) {
      return
    }
    entries.forEach(function (entry) {
      const abs = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        walk(abs)
        return
      }
      if (!/\.md$/i.test(entry.name)) return
      const id = entry.name.slice(0, -3)
      if (!Object.prototype.hasOwnProperty.call(out, id)) out[id] = abs
    })
  }
  walk(String(bankDir || ""))
  return out
}

module.exports = {
  indexExistingProblems: indexExistingProblems,
}
```

Modify `projects/apps/algo-plan/tools/import-catalog.js`——三处改动。

第一处，在顶部 `require` 区加一行：

```javascript
const bankFiles = require("./bank-files.js")
```

第二处，把落盘那一段（`// 3. 落盘` 开头）整段换成：

```javascript
  // 3. 落盘（冲突按 id 判断：已存在的同 id 文件一律跳过，--force 才覆盖）
  const bankDir = path.join(learning.root, "bank")
  const existing = bankFiles.indexExistingProblems(bankDir)
  order.forEach(function (id) {
    const data = byId[id]
    let problem
    try {
      problem = createProblem({
        id: data.id,
        source: data.source,
        title: data.title,
        // 实测死脚本里只有 easy / medium，没有 hard
        difficulty: data.difficulty === "easy" ? "easy" : "medium",
        topics: data.topics.length > 0 ? data.topics : ["未分类"],
        tracks: data.tracks,
        status: "todo",
        // 死脚本只有元数据，没有题面与测试用例
        needsFill: true,
        statement: "",
        cases: [],
        solution: "",
        solutionLang: "",
      })
    } catch (e) {
      errors.push(data.id + " 字段非法：" + e.message)
      return
    }
    const existFile = existing[problem.id]
    if (existFile && !options.force) {
      skipped.push(existFile)
      return
    }
    // 覆盖时写回它自己那个文件，不在别的轨道另开一份
    const target = existFile || path.join(bankDir, problem.tracks[0], problem.id + ".md")
    if (!options.dryRun) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, serializeProblemMarkdown(problem), "utf8")
    }
    written.push(target)
  })
```

第三处，把 `module.exports` 补上 `bankFiles`，方便别处复用：

```javascript
module.exports = {
  run: run,
  main: main,
  SCRIPT_FILES: SCRIPT_FILES,
  DEFAULT_SCRIPTS_DIR: DEFAULT_SCRIPTS_DIR,
  bankFiles: bankFiles,
}
```

Modify `projects/apps/algo-plan/tools/import-solutions.js`——同样三处。

第一处，顶部 `require` 区加一行：

```javascript
const bankFiles = require("./bank-files.js")
```

第二处，把落盘那一段（`// 4. 落盘` 开头）整段换成：

```javascript
  // 4. 落盘（同一题号只写一份；与目录来源同 id 的题也只留一份）
  const bankDir = path.join(learning.root, "bank")
  const existing = bankFiles.indexExistingProblems(bankDir)
  const seen = Object.create(null)
  parsed.items.forEach(function (item) {
    let id
    try {
      id = scan.solutionIdOf(item)
    } catch (e) {
      warnings.push("ID 生成失败，已跳过：" + item.title + "（" + e.message + "）")
      return
    }
    if (seen[id]) {
      skipped.push(id + "（同一题号有多个解法，保留先出现的：" + seen[id] + "）")
      return
    }
    seen[id] = item.file

    const topic = scan.topicOfSolutionFile(item.file) || scan.DEFAULT_SOLUTION_TOPIC
    const track = scan.trackOfSolutionTopic(topic)
    const meta = index.byId[Number(item.sourceId)] ? index.byId[Number(item.sourceId)] : null

    let problem
    try {
      problem = createProblem({
        id: id,
        source: item.source,
        title: item.title,
        // 查不到难度时默认 medium（存量题解本身没有难度信息）
        difficulty: meta ? meta.difficulty : "medium",
        topics: [topic],
        tracks: [track],
        status: "todo",
        // 题面与测试用例本来就缺
        needsFill: true,
        statement: "",
        cases: [],
        solution: item.code,
        solutionLang: item.lang,
      })
    } catch (e) {
      errors.push(id + " 字段非法：" + e.message)
      return
    }

    const existFile = existing[problem.id]
    if (existFile && !options.force) {
      skipped.push(existFile)
      return
    }
    // 覆盖时写回它自己那个文件，不在别的轨道另开一份
    const target = existFile || path.join(bankDir, problem.tracks[0], problem.id + ".md")
    if (!options.dryRun) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, serializeProblemMarkdown(problem), "utf8")
    }
    written.push(target)
  })
```

第三处，`module.exports` 补一行：

```javascript
module.exports = {
  run: run,
  main: main,
  SCAN_ROOTS: SCAN_ROOTS,
  listSourceFiles: listSourceFiles,
  listIndexFiles: listIndexFiles,
  bankFiles: bankFiles,
}
```

- [ ] **Step 4: 写实现（二）：一次性导入入口 `tools/import-bank.js`**

Create `projects/apps/algo-plan/tools/import-bank.js`：

```javascript
"use strict"
/**
 * import-bank.js —— 一次性把两路题库来源都导进 learning/bank/
 *
 * 对应设计文档 §3.5 的 B 路（复活死代码）与 C 路（存量题解）。
 *
 * 顺序固定：先目录（tools/import-catalog.js），再题解（tools/import-solutions.js）。
 * 先目录的理由：目录那边的元数据（题名、难度、标签、轨道）更全，题解那边只有代码；
 * 反过来写，「同 id 已存在就跳过」的规则会把目录那边的题挡住，参考解法就丢了。
 *
 * 用法：
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js --dry-run
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js
 *   ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js --force
 *
 * 本工具**绝不**碰 learning 仓的 git（不 commit、不 push）。
 */

const { resolveLearningRoot } = require("../core/paths.js")
const catalog = require("./import-catalog.js")
const solutions = require("./import-solutions.js")

/**
 * 主流程：先目录、后题解。
 * @param {{env?: object, dryRun?: boolean, force?: boolean, scriptsDir?: string, learningRoot?: string}} opts
 * @returns {{learningRoot: string|null, catalog: object, solutions: object}}
 */
function run(opts) {
  const options = opts || {}
  const learning = resolveLearningRoot(options.env || process.env, options.learningRoot)
  if (!learning.ok) {
    return {
      learningRoot: null,
      catalog: { written: [], skipped: [], errors: [learning.reason], warnings: [] },
      solutions: { written: [], skipped: [], errors: [], warnings: [] },
    }
  }
  return {
    learningRoot: learning.root,
    catalog: catalog.run(options),
    solutions: solutions.run(options),
  }
}

/**
 * 命令行入口。
 */
function main() {
  const argv = process.argv.slice(2)
  const dryRun = argv.indexOf("--dry-run") !== -1
  const force = argv.indexOf("--force") !== -1
  const result = run({ dryRun: dryRun, force: force })

  const errors = result.catalog.errors.concat(result.solutions.errors)
  if (errors.length > 0) {
    console.error("导入失败：")
    errors.forEach(function (line) { console.error("  · " + line) })
    process.exit(1)
  }

  const tag = dryRun ? "（试运行）" : ""
  const warnings = result.catalog.warnings.concat(result.solutions.warnings)
  console.log(tag + "learning 仓：" + (result.learningRoot || "未接入"))
  console.log(
    tag + "目录来源：写入 " + result.catalog.written.length + " 道，跳过 " +
    result.catalog.skipped.length + " 道，告警 " + result.catalog.warnings.length + " 条"
  )
  console.log(
    tag + "题解来源：写入 " + result.solutions.written.length + " 道，跳过 " +
    result.solutions.skipped.length + " 道，告警 " + result.solutions.warnings.length + " 条"
  )
  console.log(tag + "合计写入 " + (result.catalog.written.length + result.solutions.written.length) + " 道题")
  console.log("")
  console.log("目录来源前 10 条：")
  result.catalog.written.slice(0, 10).forEach(function (line) { console.log("  + " + line) })
  console.log("题解来源：")
  result.solutions.written.forEach(function (line) { console.log("  + " + line) })
  if (warnings.length > 0) {
    console.log("")
    console.log("告警前 20 条（共 " + warnings.length + " 条）：")
    warnings.slice(0, 20).forEach(function (line) { console.log("  ! " + line) })
  }
  console.log("")
  console.log("提示：导入器不碰 learning 仓的 git，是否提交由你自己决定。")
}

if (require.main === module) {
  main()
}

module.exports = {
  run: run,
  main: main,
}
```

- [ ] **Step 5: 更新 README.md**

Modify `projects/apps/algo-plan/README.md`，整体替换成下面这份：

`````markdown
# algo-plan · 算法能力提升计划 App

本机运行的算法学习助手：本地静态题库打底，LLM 做增强，判题走真实编译执行，
进度与错题写回 learning 仓进 git。

当前进度：**M2 题库**（题库能从死脚本与存量题解批量导入，`learning/bank/` 下有几百道题）。
判题、复习、轮次、诊断、LLM 属于 M3–M6，尚未实现。

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
│   └── bank/        legacy.js：死脚本内联清单的静态解析
│                    solutions-scan.js：存量题解的静态扫描
├── server/          组合根、路由、API、SQLite 存储
├── judge/           判题执行器（M3 才建）
├── web/             原生 JS 单页（无构建）
├── tools/           seed-bank.js / import-catalog.js / import-solutions.js / import-bank.js
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

## 题库导入（M2）

题库有两路来源，都由 `tools/` 下的导入器负责。**导入器一律不碰 learning 仓的 git**：

| 工具 | 来源 | 产出 |
|---|---|---|
| `tools/import-catalog.js` | `projects/scripts/` 三个死脚本里的内联题目清单 | `learning/bank/<track>/<id>.md`（只有元数据） |
| `tools/import-solutions.js` | `learning/code-solutions/` 与 `learning/algo-c/` 里的存量题解 | 同上，多一段「## 参考解法」 |
| `tools/import-bank.js` | 上面两个，按「先目录、后题解」的顺序跑一遍 | 同上 |

```bash
# 先试运行，看要写哪些文件
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js --dry-run

# 真导入
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js

# 已有同名文件时强制覆盖（默认是跳过并计入 skipped）
ALGO_PLAN_LEARNING_ROOT=/path/to/learning node tools/import-bank.js --force
```

导入的题**一律 `needs_fill: true`**：死脚本与存量题解里都只有元数据与代码，
没有题面和测试用例，补内容是后面的活。

导入器**绝不执行** `projects/scripts/` 里的死脚本——那三个脚本都指向已删除的
`practice-data.js`，而且里面有 6 处题号写成了未定义标识符（`offer22` / `offer18` /
`deleteNode` / `offer23` / `offer09` / `offer30`），跑起来必然 `ReferenceError`。
题目清单是**静态解析**出来的。

同 id 的冲突按 **id** 判断（不按路径）：同一个 id 在两路来源里算出来的轨道可能不同，
只看自己那条路径会漏判，会写出两份同 id 的文件。

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
| `legacy.test.js` | 死脚本内联清单的静态解析：分类合并、题号提取、标题还原、标签归一化 |
| `solutions-scan.test.js` | 存量题解扫描：标记切分、文件名取号、专题识别、索引解析 |
| `import-catalog.test.js` | 目录导入器：落盘位置、needs_fill、坏题号跳过、冲突跳过、dry-run |
| `import-solutions.test.js` | 题解导入器：落盘位置、参考解法、索引题名难度、命名过滤、重复导入 |
| `m2-e2e.test.js` | 端到端：死脚本 / 题解 → 题库文件 → 读回来 |

## 归属

- 服务端、判题器、前端、测试 → `projects/apps/algo-plan/`（本仓）
- 题目本体、轮次清单、错题订正 → `learning/bank/`、`learning/progress/`、`learning/notes/`（学习仓）
`````

- [ ] **Step 6: 跑测试确认通过**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan && node tests/run-all.js
```

Expected: `13 / 13 套件通过`，退出码 0

- [ ] **Step 7: 一次性真实导入到真实 learning 仓**

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning node tools/import-bank.js --dry-run
```

Expected（关键三行，数字来自本计划的勘察表）：

```
（试运行）目录来源：写入 672 道，跳过 0 道，告警 N 条
（试运行）题解来源：写入 15 道，跳过 18 道，告警 M 条
（试运行）合计写入 687 道题
```

- **672** = 三个死脚本里 `lc()` / `jz()` 调用 1247 条 → 去掉 6 条题号不可用的 → 1241 条 →
  按 `(platform, problemId)` 去重。
- **15** = 存量题解去重后 31 道 − 16 道与目录来源同 id（被 G19 挡下）。
- **18** = 跳过条数 = 16（同 id）+ 2（同一题号有多个解法；勘察表里标记 21 条去重成 19 个题号）。
- **N / M** 是告警条数，随源文件变动，不写死；导入器会把前 20 条告警打出来。

确认清单没问题后再真导入：

```bash
cd /c/code/StillEvolving/projects/apps/algo-plan
ALGO_PLAN_LEARNING_ROOT=/c/code/StillEvolving/learning node tools/import-bank.js
```

Expected: 同样三行，但少了「（试运行）」前缀；末尾打印
「提示：导入器不碰 learning 仓的 git，是否提交由你自己决定。」

然后核对产物：

```bash
cd /c/code/StillEvolving/learning
ls bank
find bank -name "*.md" | wc -l
```

Expected:

```
advanced  fundamentals  interview
687
```

- 只有 3 个轨道目录：**`engineering` 是空的**——死脚本与存量题解里都没有工程化分类，
  导入器不会建这个目录（这是实测结论，不是遗漏）。
- **实测**（2026-11-11，用真实题解副本在临时 learning 仓跑完整导入）：`fundamentals 420` /
  `interview 164` / `advanced 103`，合计 687。
  跟勘察表的推算（417 / 162 / 108）有 5 道出入，以实测为准。

> **这一步会往 learning 仓写入 687 个新文件。** 写不写、什么时候提交，由你决定——
> **导入器和本计划都不会自动 `git commit`**（G11 / G30）。

- [ ] **Step 8: 提交并推送**

```bash
cd /c/code/StillEvolving/projects
git add apps/algo-plan
git commit -m "feat(algo-plan): 增加一次性题库导入入口与端到端验收

- tools/import-bank.js：先导目录、再导题解，打印两路来源的写入/跳过/告警总数
- tools/bank-files.js：按 id 索引题库里已有的题目，两个导入器共用
- 导入器的冲突判断改成按 id 找，不再只看自己那条路径：
  同一道题在两路来源里轨道可能不同，只看路径会漏判，会写出两份同 id 的文件
- 覆盖时写回它自己那个文件，不在别的轨道另开一份
- tests/m2-e2e.test.js：临时 learning 仓跑通「死脚本 / 题解 → 题库文件 → 读回来」全链路
- 校验落盘位置、needs_fill、id 合法、难度只有 easy/medium、dry-run 不落盘、
  冲突跳过、--force 覆盖、与目录同 id 只留一份，共 14 个用例
- README 补上题库导入用法与 13 个测试套件清单"
git push origin main
```

- [ ] **Step 9: 更新父仓的 submodule 指针**

M2 的代码在 `projects` 子模块里，父仓 `StillEvolving` 记的是子模块指针，要跟着更新：

```bash
cd /c/code/StillEvolving
git add projects
git commit -m "chore(submodule): 更新 projects 子模块指针（algo-plan M2 题库）"
git push origin main
```

---

## M2 验收清单

全部满足才算 M2 完成：

| # | 验收项 | 怎么验 |
|---|---|---|
| 1 | 测试全绿 | `node tests/run-all.js` → `13 / 13 套件通过` |
| 2 | 题库真的填上了 | `find learning/bank -name "*.md" | wc -l` → `687` |
| 3 | 落盘位置对 | 文件都在 `learning/bank/<track>/<id>.md`；**没有** `learning/bank/data/` |
| 4 | 轨道目录只有三个 | `ls learning/bank` → `advanced  fundamentals  interview`（engineering 本批为空） |
| 5 | 导入的题都要补 | 题库文件里 `needs_fill: true` 一条不缺 |
| 6 | 难度只有两档 | 抽查 frontmatter，`difficulty` 只有 `easy` / `medium`，没有 `hard` |
| 7 | id 合法且唯一 | 文件名去掉 `.md` 全部匹配 `^(lc\|nc\|jz\|self\|llm)-[0-9a-z]{5,12}$`，且全局不重号 |
| 8 | 死脚本没被执行 | 导入器里没有 `child_process`；`projects/scripts/*.js` 没有被跑过 |
| 9 | 重复导入不覆盖 | 再跑一次 `import-bank.js`，全部计入 `skipped`，文件内容不变 |
| 10 | dry-run 不落盘 | `--dry-run` 跑一遍，题库文件数与内容都不变 |
| 11 | 没碰 learning 的 git | `git -C learning status` 只多出 `bank/`，没有自动 commit |
| 12 | 同一 id 只有一份 | 目录来源与题解来源同 id 的 16 道题，各只有一个文件 |

---

## M2 留给 M3–M6 的备忘

下面是 M2 做完之后**实测得到**的事实，M3–M6 直接用，不用重新摸。

### 题库现状

- 题库规模 **687 道**：`learning/bank/fundamentals` 420 道、`interview` 164 道、`advanced` 103 道，
  **`engineering` 0 道**（没有工程化分类，是实测结论）。
  M5 的「知识点覆盖率」分母不要按四条轨道平摊算，`engineering` 的期望题数是 0。
- **全部 `needs_fill: true`**：死脚本与存量题解里都只有元数据与代码，**一道题面都没有、一个用例都没有**。
  → M3 的 `POST /api/attempt` 对这些题会返回 400（0 个用例判不了）；
  → M4 的「推下一题」**必须跳过没有用例的题**，否则复习轮次会一直撞 400。
  → M6 的 `POST /api/llm/fill` 的现实用途就是补这 687 道题的题面与用例。
- **只有 15 道题带「## 参考解法」**（存量题解里与目录同 id 的 16 道被 G19 挡下了，
  参考解法没进去；想拿回来只能对那 16 道单独跑 `--force`）。
  存量解法是 `class Solution { ... }` 风格、**没有 `main()`**，
  与 M3 的判题契约（stdin 进、stdout 出）对不上，**别拿它们当判题基准**。
- **id 前缀**：目录来源里 nowcoder 的 57 道剑指 Offer 题是 `nc-XXXXX`（契约 §1 钉死 nowcoder→nc），
  题名保留「剑指 Offer JZ03. 」前缀。设计文档 §3.4 里写的 `jz-00015` **没有启用**——
  M4/M5/M6 看到 `nc-` 前缀要知道它就是剑指 Offer。

### 标签与轨道

- 原始标签 **78 种写法归一成 71 种**，别名表在 `core/bank/legacy.js` 的 `TOPIC_ALIASES`（16 条）。
  **刻意没合并**的三组：哈希集合/哈希表、二分查找/二分答案、抽样/蓄水池抽样——
  M5 统计知识点时别把它们当同义词。
- 分类 slug → 轨道的映射在 `core/bank/legacy.js` 的 `CATEGORY_TRACK_MAP`（**25 个 slug 全覆盖**）。
  未知 slug 落到 `interview` 并计告警——导入结果里出现 `interview` 里混着陌生 slug 的题，
  就是这个兜底在起作用。
- **一条标签归一化规则**：`legacy.js` 先走 M1 的 `normalizeTopic`（去空白、压内部空格），
  再查别名表。M4/M5 拿到的标签文本与 M1 的 `normalizeTopic` 口径一致。

### 导入器行为

- **导入顺序固定「先目录、后题解」**：反过来写会被 G19 挡掉，参考解法就丢了。
- **冲突按 id 判断，不按路径**（`tools/bank-files.js`）：同一个 id 在两路来源里算出来的轨道可能不同
  （真实数据里 `lc-00004` / `lc-00007` / `lc-00009` / `lc-00075` / `lc-00326` 这 5 道就是这种情况：
  目录来源在 `interview` 或 `advanced`，题解来源没有专题信息 → `fundamentals`），
  只查自己那条路径会写出两份同 id 的文件。M3–M6 要是自己写导入/更新脚本，也要按 id 找。
- **导入器不碰 learning 的 git**：新增的 687 个 `.md` 留在工作区里，
  要不要提交、什么时候提交，由人决定（G11 / G30）。
- `learning/.gitignore` 只忽略 `data/`（第 36 行），**`bank/` 不在忽略列表里**，
  所以题库文件是可以正常入库的。

---

## 执行提示

- 本计划只改 `projects/` 子模块（`projects/apps/algo-plan/`）。
  `learning/` 子模块被写入的只有 `bank/` 目录，**只写不提交**（G11 / G30）。
- 每个 Task 结束都有「提交并推送」，Task 5 额外提醒更新父仓的 submodule 指针。
- **三个死脚本只解析、不执行**：改代码时别顺手 `node projects/scripts/gen-practice-data.js`——
  它会 `ReferenceError`（6 处题号写成了未定义标识符），而且读的 `practice-data.js` 早就删了。
- 导入到真实 learning 仓是**一次性动作**（Task 5 的 Step 7）。要重来先 `--dry-run` 看清单，
  再决定要不要 `--force`；`--force` 会覆盖已有文件，别对不认识的目录乱用。
- 计划写完了，不要在没跑通测试前合并。

 
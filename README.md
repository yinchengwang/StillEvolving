# StillEvolving

个人项目的顶层聚合仓。这里不放业务代码，只放**四个仓库之间的关系**。

## 四个仓库

| 仓 | 路径 | 获取方式 | 放什么 |
|---|---|---|---|
| projects | `projects/` | submodule | 引擎代码、小程序、项目文档、agent 规约 |
| learning | `learning/` | submodule | 学习笔记、脚手架、算法题解 |
| ai-docs | `ai-docs/` | submodule | 跨项目复用的模板与方法论 |
| reference | `../reference/` | 独立仓 + 清单拉取 | 第三方源码镜像 + 源码笔记 |

## 仓库之间的关系

```
StillEvolving/              ← 父仓：只放关系，不放业务代码
├── projects/               ← submodule ──▶ github.com/yinchengwang/projects.git
│   ├── vendor/third_part/googletest   ← 嵌套 submodule（各仓自理）
│   └── engine/third_part/uthash       ← 嵌套 submodule（各仓自理）
├── learning/               ← submodule ──▶ github.com/yinchengwang/learning.git
│   └── third_part/googletest          ← 嵌套 submodule（各仓自理）
└── ai-docs/                ← submodule ──▶ github.com/yinchengwang/AI-DOCS.git

../reference/               ← 独立仓（平级，【不进】submodule 树）
                             ──▶ github.com/yinchengwang/reference.git
    └── reference/<model>/<name>/       ← 95 个上游库 submodule，按需拉取
```

三类关系，性质不同：

| 关系 | 载体 | 父仓管不管 |
|---|---|---|
| 父仓 → 三个子仓 | `.gitmodules` + `gitlink` pin | 管：pin commit、bootstrap、一致性校验 |
| 父仓 → reference | `repos.yaml` 的 `upstream` 字段 + `catalog.yml` 的 commit pin | 管：清单与 pin，但**不**把 reference 挂进 submodule 树 |
| 子仓 → 嵌套 submodule | 各仓自己的 `.gitmodules` | 不管：父仓只管到第二层 |

**为什么 reference 不在 submodule 树里**：它内部有 95 个第三方库 submodule，
嵌套进去会让 `git clone --recurse-submodules` 一次性拉取约 25 GB / 53.6 万文件。
因此 reference 独立 clone，位置由使用者决定（推荐与 StillEvolving 平级但**不在**其内），
其上游库由 `reference/reference/catalog.yml` 声明 commit、按需克隆。

### 关系的权威定义在哪

| 文件 | 作用 |
|---|---|
| [`repos.yaml`](repos.yaml) | 机器可读的四仓清单 —— **唯一权威的「关系」定义**（URL / 角色 / 拉取策略 / `must_contain`） |
| [`docs/architecture.md`](docs/architecture.md) | 目录树与归属判定规则总览 |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | 切仓设计与决策原件（2026-10-25） |
| `.gitmodules` | git 原生事实：3 条子仓 pin |

`.gitmodules` 是 git 的原生机制，但表达不了 `fetch: manifest` 这种策略，也放不了
「这个仓该放什么」的语义说明。**`repos.yaml` 承载语义，`.gitmodules` 承载 git 事实**，
两者由 `scripts/check_consistency.py` 保证不漂移。

## 快速开始

```bash
# 1) 拉起三个 submodule
git clone --recurse-submodules https://github.com/yinchengwang/StillEvolving.git
# 或先 clone 再初始化
git submodule update --init

# 2) 单独 clone reference 仓 —— 切勿加 --recurse-submodules，理由见下节
git clone https://github.com/yinchengwang/reference.git ../reference
```

第 1 步的 `--recurse-submodules` 只作用于**本仓的 3 个 submodule**
（projects / learning / ai-docs），是安全的 —— 最坏情况再多带出 3 个嵌套库
（uthash + 两份 googletest，实测 checkout 约 8.9 MB、git 对象约 32 MB）。

第 2 步的 `reference` **绝不能**加 `--recurse-submodules`：它内部还有 95 个上游 submodule。

一键引导（拉 submodule + 校验四仓一致性）：

```bash
bash scripts/bootstrap.sh                 # POSIX
scripts/bootstrap.ps1                     # Windows（PowerShell 执行）
```

### 第三方库拉取

```bash
# 按 catalog.yml 拉取第三方库到指定 commit
bash scripts/fetch-reference.sh --tier core
```

其他常用形式：

```bash
bash scripts/fetch-reference.sh --name faiss      # 拉单个库
bash scripts/fetch-reference.sh --model vector    # 按分类拉
bash scripts/fetch-reference.sh --check           # 只校验清单与磁盘，不拉取
bash scripts/fetch-reference.sh --all --yes       # 全量（91 个，需二次确认）
```

> 第 2 步 clone 到的 `../reference` 只有**清单层与笔记层**，源码层一律由该脚本按需拉取。

## 三个容易混淆的数字

`reference` 的规模有三个口径，各有各的含义，**不要混用**：

| 数字 | 含义 | 出处 |
|---|---|---|
| **97** | `catalog.yml` 条目总数（含 2 条无源码镜像的占位） | `reference/reference/catalog.yml` |
| **95** | 有真实上游源码的库数 = `.gitmodules` 条目数 | `reference/.gitmodules` |
| **91** | `pin_status: valid` 的条目数 = `--all` 实际能拉到的数量 | `catalog.yml` 的 `pin_status` 字段 |

97 = 91（valid）+ 4（broken）+ 2（unresolvable）= 95（`source: mirror`）+ 2（`source: none`）。

拉取时被跳过的 6 条：

| 状态 | 库 | 原因 |
|---|---|---|
| `broken` | `druid`、`pebble`、`tdengine`、`dragonfly` | 上游不存在该 commit，gitlink SHA 失效 |
| `unresolvable` | `oceanbase`、`pklite` | `source: none` —— 无源码镜像，仅有笔记 |

> `broken` 条目**只标注不重选** —— 拉 HEAD 冒充 pin 会让笔记里的行号引用全体漂移。
> `unresolvable` 条目在 `.gitmodules` 中没有对应 submodule 定义。

## 一致性校验

```bash
python scripts/check_consistency.py          # 校验四仓关系与 catalog 一致性
python scripts/test_check_consistency.py     # 其单元测试
bash scripts/test_fetch_reference.sh         # fetch-reference.sh 的契约测试
```

`check_consistency.py` 会校验 `repos.yaml` ↔ 实际目录 ↔ `catalog.yml` ↔ `.gitmodules` 四方不漂移，
退出码 0 表示全部一致（警告不算不一致）。

当前已知会打印 6 条**提示性警告**：

```
[reference] clone_url 与 .gitmodules url 不一致: chroma / elasticsearch / milvus / mysql / neo4j / openGauss
```

这是**预期行为**，不是不一致：`catalog.yml` 的 `clone_url` 优先于 `.gitmodules` 的 `url`，
因为部分 `.gitmodules` 条目指向不含该 pin 的镜像（如 mysql 指向 gitee 镜像，取不到 pinned SHA）。
`fetch-reference.sh` 在拉取时会主动把 submodule 的 url 改写成 catalog 的 `clone_url`。

## ⚠️ 禁止 `git submodule update --init --recursive`

**作用域是 `../reference` 仓。** reference 内部有 95 个第三方库 submodule，
递归初始化会一次性拉取约 25 GB / 53.6 万文件。
需要哪个库就用 `scripts/fetch-reference.sh --name <名字>` 单独拉取。

在本仓（StillEvolving）内递归是安全的：本仓 `.gitmodules` 只有 3 条
（projects / learning / ai-docs），且**不含** `reference`，
递归最多再多带出 3 个嵌套库（uthash + 两份 googletest），
与 reference 的 25 GB 不在一个量级。

`git submodule add` 与 `git submodule status` **不带** `--recursive` 是安全的。

## 目录规范

见 [`docs/architecture.md`](docs/architecture.md)；机器可读版见
[`repos.yaml`](repos.yaml) 的 `must_contain` 字段。

各子仓的 README 内也各带一份归属判定表（人进到 `projects/` 里看不到父仓的
`docs/architecture.md`，所以每仓 README 必须自带一份）。

**判定口诀：换个项目还用得上 → ai-docs；只对这个项目有意义 → 留在本仓。**

## 许可

MIT（见 [`LICENSE`](LICENSE)）。各 submodule 遵循其上游项目自身的许可协议。

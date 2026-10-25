# StillEvolving

个人项目的顶层聚合仓。这里不放业务代码，只放**四个仓库之间的关系**。

## 四个仓库

| 仓 | 路径 | 获取方式 | 放什么 |
|---|---|---|---|
| projects | `projects/` | submodule | 引擎代码、小程序、项目文档、agent 规约 |
| learning | `learning/` | submodule | 学习笔记、脚手架、算法题解 |
| ai-docs | `ai-docs/` | submodule | 跨项目复用的模板与方法论 |
| reference | `../reference/` | 独立仓 + 清单拉取 | 第三方源码镜像 + 源码笔记 |

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

### 第三方库拉取（Task 5 后可用）

```bash
# 按 catalog.yml 拉取第三方库到指定 commit
bash scripts/fetch-reference.sh --tier core
```

> `scripts/fetch-reference.sh` 由 Task 5 交付。在此之前，上面第 2 步 clone 到的
> `../reference` 只有清单层与笔记层，源码层要等该脚本就绪后再按需拉取。

## ⚠️ 禁止 `git submodule update --init --recursive`

**作用域是 `../reference` 仓。** reference 内部有 95 个第三方库 submodule，
递归初始化会一次性拉取约 25 GB / 53.6 万文件。
需要哪个库就用 `scripts/fetch-reference.sh --name <名字>` 单独拉取。

在本仓（StillEvolving）内递归是安全的：本仓 `.gitmodules` 只有 3 条
（projects / learning / ai-docs），且**不含** `reference`，
递归最多再多带出 3 个嵌套库（uthash + 两份 googletest），
与 reference 的 25 GB 不在一个量级。

## 目录规范

见 `docs/architecture.md`；机器可读版见 `repos.yaml` 的 `must_contain` 字段。

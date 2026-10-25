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

# 2) 按需拉取第三方库（不要用 --recursive，会拉 25 GB）
bash scripts/fetch-reference.sh --tier core
```

## ⚠️ 禁止 `git submodule update --init --recursive`

reference 内部有 95 个第三方库 submodule，递归初始化会一次性拉取约 25 GB / 53.6 万文件。
需要哪个库就用 `scripts/fetch-reference.sh --name <名字>` 单独拉取。

## 目录规范

见 `docs/architecture.md`；机器可读版见 `repos.yaml` 的 `must_contain` 字段。

# 一键引导 StillEvolving 工作树（Windows 原生）
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host '==> 初始化 submodule' -ForegroundColor Cyan
# 注意：绝不带 --recursive
git submodule update --init
if ($LASTEXITCODE -ne 0) { throw "submodule 初始化失败" }

Write-Host '==> 校验四仓一致性' -ForegroundColor Cyan
python scripts/check_consistency.py
if ($LASTEXITCODE -ne 0) { throw "一致性校验失败" }

Write-Host '==> 完成' -ForegroundColor Green
Write-Host '按需拉第三方库: bash scripts/fetch-reference.sh --tier core'

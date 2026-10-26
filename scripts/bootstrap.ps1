# 一键引导 StillEvolving 工作树（Windows 原生）
#
# 注意：本文件必须存为 UTF-8 **带 BOM** + CRLF。
# Windows PowerShell 5.1 会把无 BOM 的 .ps1 按系统 ANSI 码页（本机 CP936）解码，
# 中文的多字节序列会吞掉后面的引号，导致整段脚本 ParserError、根本不会执行。

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# 找 Python：Windows 上可能是 python3 / python / py -3
$Py = $null
foreach ($candidate in @('python3', 'python', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $Py = $candidate
        break
    }
}
if (-not $Py) {
    throw '找不到 Python 解释器（试过 python3 / python / py）'
}

Write-Host '==> 初始化 submodule' -ForegroundColor Cyan
# 注意：绝不带 --recursive
git submodule update --init
if ($LASTEXITCODE -ne 0) { throw "submodule 初始化失败" }

Write-Host '==> 校验四仓一致性' -ForegroundColor Cyan
if ($Py -eq 'py') { py -3 scripts/check_consistency.py } else { & $Py scripts/check_consistency.py }
if ($LASTEXITCODE -ne 0) { throw "一致性校验失败" }

Write-Host '==> 完成' -ForegroundColor Green
Write-Host '按需拉第三方库: bash scripts/fetch-reference.sh --tier core'

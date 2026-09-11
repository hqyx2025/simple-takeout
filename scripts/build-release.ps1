<#
.SYNOPSIS
  构建简单外卖 Release 安装包（HAP / APP），并校验签名结果。

.DESCRIPTION
  前置条件：已执行 scripts/enable-release-signing.ps1 接入发布证书与 Profile。
  未接入签名时 hvigor 仍会产出 entry-default-unsigned.hap，但该包无法安装真机、不能上架，
  脚本会明确提示并返回失败码，避免误把 unsigned 包当成上架包。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/build-release.ps1 -App
#>
[CmdletBinding()]
param(
  # 额外构建 APP 包（AGC 上架需上传 .app）
  [switch]$App,
  # 跳过签名前置校验（仅用于确认未签名包能编译通过）
  [switch]$AllowUnsigned
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$buildProfile = [System.IO.File]::ReadAllText((Join-Path $root 'build-profile.json5'), $utf8)
$signingConfigured = -not ($buildProfile -match '"signingConfigs"\s*:\s*\[\s*\]')

if (-not $signingConfigured) {
  Write-Host '[FAIL] 未配置发布签名：build-profile.json5 的 signingConfigs 为空。' -ForegroundColor Red
  Write-Host '       请先执行：powershell -ExecutionPolicy Bypass -File scripts/enable-release-signing.ps1 ...' -ForegroundColor Yellow
  Write-Host '       证书申请流程见 md/上架体检与Release签名.md。' -ForegroundColor Yellow
  if (-not $AllowUnsigned) {
    exit 1
  }
  Write-Host '[WARN] 已指定 -AllowUnsigned：将构建未签名包，仅用于验证 Release 编译通过。' -ForegroundColor Yellow
}

$devEco = 'C:\Program Files\Huawei\DevEco Studio'
$node = Join-Path $devEco 'tools\node\node.exe'
$hvigor = Join-Path $devEco 'tools\hvigor\bin\hvigorw.js'
if (-not (Test-Path $node) -or -not (Test-Path $hvigor)) {
  throw "未找到 DevEco 工具链：$devEco（可通过环境变量 DEVECO_HOME 指定安装目录后重试）"
}
$env:DEVECO_SDK_HOME = Join-Path $devEco 'sdk'

$task = if ($App) { 'assembleApp' } else { 'assembleHap' }
Write-Host "=== Release 构建（$task, buildMode=release）===" -ForegroundColor Cyan

Push-Location $root
try {
  $log = & $node $hvigor --mode module -p module=entry@default -p product=default `
    -p buildMode=release -p requiredDeviceType=phone $task `
    --analyze=normal --parallel --no-daemon 2>&1
  $log | ForEach-Object { Write-Host $_ }
  if (($log | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] 构建失败' -ForegroundColor Red
    exit 1
  }
} finally {
  Pop-Location
}

Write-Host ''
Write-Host '=== 产物校验 ===' -ForegroundColor Cyan
$signed = @(Get-ChildItem $root -Recurse -Include '*-signed.hap', '*-signed.app' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notlike '*\oh_modules\*' })
$unsigned = @(Get-ChildItem $root -Recurse -Filter '*unsigned.hap' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notlike '*\oh_modules\*' })

foreach ($item in $signed) {
  Write-Host ("[OK] 已签名产物：{0}（{1:N0} KB）" -f $item.FullName, ($item.Length / 1KB)) -ForegroundColor Green
}
foreach ($item in $unsigned) {
  Write-Host ("[WARN] 未签名产物：{0}（{1:N0} KB，不可安装真机/上架）" -f $item.FullName, ($item.Length / 1KB)) -ForegroundColor Yellow
}

if ($signed.Count -eq 0) {
  Write-Host '[FAIL] 未产出已签名包：Release 签名未生效。' -ForegroundColor Red
  exit 1
}
Write-Host ''
Write-Host '下一步：把已签名的 .app 上传到 AppGallery Connect（详见 md/上架体检与Release签名.md）。' -ForegroundColor Cyan

<#
.SYNOPSIS
  一键在模拟器/真机上实测「简单外卖」：启动模拟器 → 构建 → 安装 → 拉起 → 截图 → 读界面。

.DESCRIPTION
  关键结论（已实测确认）：
    * 华为模拟器**不校验发布签名**，未签名的 entry-default-unsigned.hap 可以直接 hdc install，
      因此设备实测完全不需要发布证书，也不需要 AGC。
    * 模拟器必须用 -noWindow 启动（带窗口时本机会报 GLib 断言并退出）；
      启动约需 40-60 秒才会出现在 hdc list targets 中。
    * 应用访问宿主机后端用 http://10.0.2.2:9000（模拟器 NAT 别名），后端需先启动：
      mvn -f server/pom.xml spring-boot:run

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-test.ps1            # 全流程（设备已启动时）
  powershell -ExecutionPolicy Bypass -File scripts/device-test.ps1 -Start     # 顺带启动模拟器
  powershell -ExecutionPolicy Bypass -File scripts/device-test.ps1 -Dump      # 只读当前界面文本（排障用）
  powershell -ExecutionPolicy Bypass -File scripts/device-test.ps1 -Stop      # 关闭模拟器
#>
[CmdletBinding()]
param(
  [string]$EmulatorName = 'Pura X View',
  [string]$Bundle = 'com.example.jiandanwaimai',
  [string]$Ability = 'EntryAbility',
  [switch]$Start,
  [switch]$Install,
  [switch]$Launch,
  [switch]$Dump,
  [switch]$Stop
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$emulatorExe = 'C:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe'
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
# 临时产物统一放 TemporaryCacheStorage（不入库，详见 AGENTS.md「项目约束」）
$tempDir = Join-Path $root 'TemporaryCacheStorage'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Force -Path $tempDir | Out-Null }
$shotPath = Join-Path $tempDir 'agent-device-screenshot.jpeg'
$layoutHost = Join-Path $tempDir 'agent-ui-layout.json'

function Get-Targets {
  return ((& $hdc list targets 2>&1 | Out-String).Trim())
}

function Wait-Device([int]$Seconds = 90) {
  for ($i = 0; $i -lt [Math]::Ceiling($Seconds / 6); $i++) {
    $t = Get-Targets
    if ($t -ne '' -and $t -notmatch '\[Empty\]') { return $t }
    Start-Sleep -Seconds 6
  }
  return ''
}

function Show-UiText {
  & $hdc shell uitest dumpLayout -p /data/local/tmp/layout.json 2>&1 | Out-Null
  & $hdc file recv /data/local/tmp/layout.json $layoutHost 2>&1 | Out-Null
  if (-not (Test-Path $layoutHost)) { Write-Host '[WARN] 未能获取界面布局' -ForegroundColor Yellow; return }
  # 必须用 .NET 按 UTF-8 读取：PS 5.1 的 Get-Content 会按 ANSI 解码导致中文乱码
  $raw = [System.IO.File]::ReadAllText($layoutHost, [System.Text.Encoding]::UTF8)
  $texts = [regex]::Matches($raw, '"text":"([^"]{1,40})"') |
    ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '' } | Select-Object -Unique
  Write-Host ("[界面] 共 {0} 个文本节点：" -f $texts.Count) -ForegroundColor Cyan
  Write-Host ('  ' + ($texts -join ' | '))
}

if ($Stop) {
  & $emulatorExe -stop $EmulatorName 2>&1 | Out-Null
  Write-Host "[OK] 已请求关闭模拟器 $EmulatorName" -ForegroundColor Green
  exit 0
}

if ($Dump) {
  if ((Get-Targets) -match '\[Empty\]') { Write-Host '[FAIL] 没有已连接设备，先执行 -Start' -ForegroundColor Red; exit 1 }
  Show-UiText
  exit 0
}

# ---------- 1. 设备 ----------
$target = Get-Targets
if ($target -eq '' -or $target -match '\[Empty\]') {
  if (-not $Start) {
    Write-Host '[FAIL] 没有已连接设备。加 -Start 自动启动模拟器，或插上真机开启 USB 调试。' -ForegroundColor Red
    exit 1
  }
  Write-Host "[1/5] 启动模拟器 $EmulatorName（无窗口模式，约 40-60 秒）..." -ForegroundColor Cyan
  Start-Process -FilePath $emulatorExe -ArgumentList @('-start', $EmulatorName, '-noWindow') -WindowStyle Hidden
  $target = Wait-Device 120
  if ($target -eq '') { Write-Host '[FAIL] 模拟器 120 秒内未就绪' -ForegroundColor Red; exit 1 }
} else {
  Write-Host "[1/5] 复用已连接设备：$target" -ForegroundColor Cyan
}
Write-Host ("      型号 {0} / API {1}" -f (& $hdc shell param get const.product.model 2>&1).Trim(), (& $hdc shell param get const.ohos.apiversion 2>&1).Trim())

# ---------- 2. 后端连通性 ----------
try {
  $probe = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/api/auth/login' -Method Post -ContentType 'application/json' `
    -Body '{"phone":"13800138000","password":"123456"}' -TimeoutSec 5
  Write-Host '[2/5] 后端在线（127.0.0.1:9000 可登录）' -ForegroundColor Green
} catch {
  Write-Host '[2/5] [WARN] 宿主机后端未响应，应用内所有接口都会失败。请先运行：mvn -f server/pom.xml spring-boot:run' -ForegroundColor Yellow
}

# ---------- 3. 构建 ----------
if ($Install -or -not $Dump) {
  Write-Host '[3/5] 构建 HAP（debug）...' -ForegroundColor Cyan
  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  Push-Location $root
  $out = & $node $hvigor --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone `
    assembleHap --analyze=normal --parallel --incremental --daemon 2>&1
  Pop-Location
  if (($out | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] 构建失败' -ForegroundColor Red
    ($out | Select-Object -Last 6) | ForEach-Object { Write-Host "  $_" }
    exit 1
  }
  Write-Host '      BUILD SUCCESSFUL' -ForegroundColor Green
}

# ---------- 4. 安装 ----------
$hap = Join-Path $root 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not (Test-Path $hap)) { Write-Host "[FAIL] 未找到产物 $hap" -ForegroundColor Red; exit 1 }
Write-Host '[4/5] 安装 HAP（模拟器不校验发布签名，unsigned 可直接安装）...' -ForegroundColor Cyan
$installOut = & $hdc install $hap 2>&1 | Out-String
if ($installOut -notmatch 'successfully') {
  Write-Host '[FAIL] 安装失败：' -ForegroundColor Red
  Write-Host "  $($installOut.Trim())"
  exit 1
}
Write-Host '      install bundle successfully' -ForegroundColor Green

# ---------- 5. 拉起 + 截图 + 读界面 ----------
if ($Launch -or -not $Dump) {
  & $hdc shell aa force-stop $Bundle 2>&1 | Out-Null
  Start-Sleep -Seconds 2
  Write-Host '[5/5] 拉起应用并截图...' -ForegroundColor Cyan
  & $hdc shell aa start -a $Ability -b $Bundle 2>&1 | Out-Null
  Start-Sleep -Seconds 12
  & $hdc shell snapshot_display -f /data/local/tmp/shot.jpeg 2>&1 | Out-Null
  & $hdc file recv /data/local/tmp/shot.jpeg $shotPath 2>&1 | Out-Null
  if (Test-Path $shotPath) { Write-Host "      截图：$shotPath" -ForegroundColor Green }
  Show-UiText
}

Write-Host ''
Write-Host '提示：应用冷启动后停在登录页，可用一键登录按钮进入对应角色；也可用 uitest 直接点按（坐标为 1320x2232 基准）：' -ForegroundColor Gray
Write-Host '  hdc shell uitest uiInput click <x> <y>' -ForegroundColor Gray
Write-Host "  关闭模拟器：scripts/device-test.ps1 -Stop" -ForegroundColor Gray

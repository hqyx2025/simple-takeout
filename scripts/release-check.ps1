<#
.SYNOPSIS
  简单外卖 App 上架前体检（Release 就绪度 + 签名 + 产物），可选执行 Release 构建。

.DESCRIPTION
  逐项检查上架/发布阻塞项并输出 Markdown 报告；退出码 = FAIL 项数量（0 表示无阻塞项）。
  检查项覆盖：应用信息、权限与隐私、签名配置、网络配置（HTTPS）、页面注册、构建产物签名状态。
  说明：DevEco 的 AppAnalyzer / Code Linter 目前只能在 IDE 内运行（CLI 无法脱离 IDE 独立执行），
  本脚本用可复现的静态检查覆盖同类上架阻塞项，IDE 体检仍建议在发布前各跑一次。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1 -Build -OutFile md\上架体检报告.md
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [string]$OutFile = 'md\上架体检报告.md'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$results = New-Object System.Collections.ArrayList

function Add-Result([string]$Level, [string]$Item, [string]$Detail) {
  [void]$results.Add([pscustomobject]@{ Level = $Level; Item = $Item; Detail = $Detail })
}

function Read-Json([string]$relativePath) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path $path)) {
    return $null
  }
  return (Get-Content -Raw -Encoding UTF8 $path) | ConvertFrom-Json
}

function Read-Raw([string]$relativePath) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path $path)) {
    return ''
  }
  return [System.IO.File]::ReadAllText($path, $utf8)
}

Write-Host '=== 简单外卖 上架体检 ===' -ForegroundColor Cyan

# ---------- 1. 应用信息 ----------
$app = Read-Json 'AppScope\app.json5'
if ($null -eq $app) {
  Add-Result 'FAIL' '应用信息' 'AppScope/app.json5 不存在'
} else {
  $info = $app.app
  if ([string]::IsNullOrWhiteSpace($info.bundleName)) {
    Add-Result 'FAIL' '包名' 'bundleName 未配置'
  } elseif ($info.bundleName -like '*example*') {
    Add-Result 'WARN' '包名' "bundleName=$($info.bundleName) 含 example，上架前建议改为自有域名反写（需与 AGC 应用一致）"
  } else {
    Add-Result 'PASS' '包名' "bundleName=$($info.bundleName)"
  }
  if ([int]$info.versionCode -le 0) {
    Add-Result 'FAIL' '版本号' 'versionCode 必须为正整数'
  } else {
    Add-Result 'PASS' '版本号' "versionCode=$($info.versionCode) versionName=$($info.versionName)"
  }
  if ([string]::IsNullOrWhiteSpace($info.icon) -or [string]::IsNullOrWhiteSpace($info.label)) {
    Add-Result 'FAIL' '应用图标/名称' 'icon 或 label 未配置'
  } else {
    Add-Result 'PASS' '应用图标/名称' "icon=$($info.icon) label=$($info.label)"
  }
  if ([string]::IsNullOrWhiteSpace($info.vendor)) {
    Add-Result 'WARN' '厂商信息' 'vendor 未配置（AGC 应用信息需要）'
  } else {
    Add-Result 'PASS' '厂商信息' "vendor=$($info.vendor)"
  }
}

# ---------- 2. 权限与隐私 ----------
$module = Read-Json 'entry\src\main\module.json5'
if ($null -eq $module) {
  Add-Result 'FAIL' '模块配置' 'entry/src/main/module.json5 不存在'
} else {
  $mod = $module.module
  $permissions = @()
  if ($null -ne $mod.requestPermissions) {
    $permissions = @($mod.requestPermissions)
  }
  $risky = @('ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION',
    'ohos.permission.CAMERA', 'ohos.permission.READ_MEDIA', 'ohos.permission.WRITE_MEDIA')
  $declaredRisky = @($permissions | Where-Object { $risky -contains $_.name })
  $missingReason = @($declaredRisky | Where-Object { [string]::IsNullOrWhiteSpace($_.reason) })
  if ($missingReason.Count -gt 0) {
    Add-Result 'FAIL' '敏感权限说明' ('缺少 reason 的权限：' + (($missingReason | ForEach-Object { $_.name }) -join ', '))
  } else {
    Add-Result 'PASS' '敏感权限说明' ("已声明 $($declaredRisky.Count) 个敏感权限且均带 reason（用户可感知）")
  }
  Add-Result 'PASS' '权限清单' (($permissions | ForEach-Object { $_.name }) -join ', ')
  if ($null -ne $mod.abilities -and @($mod.abilities).Count -gt 0) {
    Add-Result 'PASS' '入口 Ability' "mainElement=$($mod.mainElement)"
  } else {
    Add-Result 'FAIL' '入口 Ability' '未声明 abilities'
  }
  if ($null -ne $mod.pages) {
    Add-Result 'PASS' '页面路由表' "pages=$($mod.pages)"
  } else {
    Add-Result 'FAIL' '页面路由表' '未配置 pages'
  }
}

# ---------- 3. 页面注册一致性 ----------
$mainPages = Read-Json 'entry\src\main\resources\base\profile\main_pages.json'
$etsDir = Join-Path $root 'entry\src\main\ets\pages'
if ($null -ne $mainPages -and (Test-Path $etsDir)) {
  # 只有 @Entry 页面必须注册路由；被当作组件复用的页面（如 LoginPage）无需注册
  $entryPages = @()
  foreach ($file in Get-ChildItem $etsDir -Filter '*.ets') {
    if ((Read-Raw "entry\src\main\ets\pages\$($file.Name)") -match '@Entry') {
      $entryPages += "pages/$($file.BaseName)"
    }
  }
  $registered = @($mainPages.src)
  $missing = @($entryPages | Where-Object { $registered -notcontains $_ })
  $stale = @($registered | Where-Object { -not (Test-Path (Join-Path $etsDir "$($_.Replace('pages/', '')).ets")) })
  if ($missing.Count -gt 0) {
    Add-Result 'FAIL' '页面注册' ('以下 @Entry 页面未注册到 main_pages.json：' + ($missing -join ', '))
  } else {
    Add-Result 'PASS' '页面注册' "共 $($entryPages.Count) 个 @Entry 页面均已注册（路由表 $($registered.Count) 项）"
  }
  if ($stale.Count -gt 0) {
    Add-Result 'FAIL' '页面注册' ('main_pages.json 中存在无对应文件的条目（启动会失败）：' + ($stale -join ', '))
  }
} else {
  Add-Result 'WARN' '页面注册' '未找到 main_pages.json，跳过检查'
}

# ---------- 4. 网络与安全 ----------
$constants = Read-Raw 'entry\src\main\ets\common\Constants.ets'
if ($constants -eq '') {
  Add-Result 'FAIL' '网络配置' '未找到 common/Constants.ets'
} else {
  if ($constants -match 'USE_HTTPS:\s*boolean\s*=\s*true') {
    Add-Result 'PASS' 'HTTPS 开关' 'API_CONFIG.USE_HTTPS=true'
  } else {
    Add-Result 'FAIL' 'HTTPS 开关' 'API_CONFIG.USE_HTTPS 仍为 false，发布包必须使用 HTTPS 域名'
  }
  if ($constants -match 'api\.example\.com') {
    Add-Result 'FAIL' '发布域名' 'RELEASE_BASE_URL 仍为示例域名 https://api.example.com，需替换为真实备案域名'
  } else {
    Add-Result 'PASS' '发布域名' 'RELEASE_BASE_URL 已替换为真实域名'
  }
  if ($constants -match 'MAP_JS_KEY:\s*string\s*=\s*''([^'']+)''') {
    Add-Result 'PASS' '高德 Key' "已配置（$($Matches[1].Substring(0, [Math]::Min(6, $Matches[1].Length)))***）"
  } else {
    Add-Result 'WARN' '高德 Key' '未检测到 MAP_JS_KEY'
  }
}
$httpsYml = Test-Path (Join-Path $root 'server\src\main\resources\application-https.yml')
Add-Result ($(if ($httpsYml) { 'PASS' } else { 'WARN' })) '后端 HTTPS 配置' $(if ($httpsYml) { 'server/application-https.yml 已提供' } else { '缺少 HTTPS 配置' })

# ---------- 5. 签名配置 ----------
$buildProfile = Read-Raw 'build-profile.json5'
$signingDir = Join-Path $root 'signing'
$p12 = @(Get-ChildItem $signingDir -Filter '*.p12' -ErrorAction SilentlyContinue)
$p7b = @(Get-ChildItem $signingDir -Filter '*.p7b' -ErrorAction SilentlyContinue)
$cer = @(Get-ChildItem $signingDir -Filter '*.cer' -ErrorAction SilentlyContinue)
$hasSigningMaterial = ($p12.Count -gt 0 -and $p7b.Count -gt 0 -and $cer.Count -gt 0)
if ($buildProfile -match '"signingConfigs"\s*:\s*\[\s*\]') {
  if ($hasSigningMaterial) {
    Add-Result 'WARN' '签名配置' 'signing/ 下已有证书材料，但 build-profile.json5 未接入，请执行 scripts/enable-release-signing.ps1'
  } else {
    Add-Result 'FAIL' '签名配置' '未配置发布证书（signing/ 下缺少 .p12/.cer/.p7b），当前只能产出 unsigned 包，无法安装真机/上架'
  }
} else {
  if ($hasSigningMaterial) {
    Add-Result 'PASS' '签名配置' 'build-profile.json5 已接入签名材料'
  } else {
    Add-Result 'WARN' '签名配置' 'build-profile.json5 已写入签名配置，但 signing/ 下未找到证书文件，构建会失败'
  }
}

# ---------- 6. Release 构建与产物 ----------
$outputDir = Join-Path $root 'entry\build\default\outputs\default'
if ($Build) {
  Write-Host '--- 执行 Release 构建（hvigor assembleHap -p buildMode=release）...' -ForegroundColor Cyan
  $devEco = 'C:\Program Files\Huawei\DevEco Studio'
  $node = Join-Path $devEco 'tools\node\node.exe'
  $hvigor = Join-Path $devEco 'tools\hvigor\bin\hvigorw.js'
  if (-not (Test-Path $node) -or -not (Test-Path $hvigor)) {
    Add-Result 'WARN' 'Release 构建' "未找到 DevEco 工具链（$devEco），跳过构建"
  } else {
    $env:DEVECO_SDK_HOME = Join-Path $devEco 'sdk'
    Push-Location $root
    # hvigor 会把 WARN 写到 stderr，PS 5.1 在 Stop 策略下会把原生命令 stderr 当成终止错误，这里局部放开
    $prevPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $log = & $node $hvigor --mode module -p module=entry@default -p product=default `
        -p buildMode=release -p requiredDeviceType=phone assembleHap `
        --analyze=normal --parallel --no-daemon 2>&1
      $logText = ($log | Out-String)
      if ($logText -match 'BUILD SUCCESSFUL') {
        Add-Result 'PASS' 'Release 构建' 'BUILD SUCCESSFUL（buildMode=release）'
      } else {
        $tail = (($log | Select-Object -Last 8) -join ' | ')
        Add-Result 'FAIL' 'Release 构建' "构建失败：$tail"
      }
    } finally {
      $ErrorActionPreference = $prevPreference
      Pop-Location
    }
  }
}

if (Test-Path $outputDir) {
  $haps = @(Get-ChildItem $outputDir -Filter '*.hap' -ErrorAction SilentlyContinue)
  if ($haps.Count -eq 0) {
    Add-Result 'WARN' '构建产物' '未找到 HAP 产物，请先执行构建'
  } else {
    foreach ($hap in $haps) {
      $signed = $hap.Name -notlike '*unsigned*'
      Add-Result ($(if ($signed) { 'PASS' } else { 'WARN' })) '构建产物' `
        ("{0}（{1:N0} KB，{2}）" -f $hap.Name, ($hap.Length / 1KB), $(if ($signed) { '已签名' } else { '未签名，仅可用于本地调试验证' }))
    }
  }
  $apps = @(Get-ChildItem (Join-Path $root 'build\outputs') -Recurse -Filter '*.app' -ErrorAction SilentlyContinue)
  if ($apps.Count -gt 0) {
    Add-Result 'PASS' 'APP 包' (($apps | ForEach-Object { $_.Name }) -join ', ')
  } else {
    Add-Result 'WARN' 'APP 包' '未找到 .app 包（上架需 Build APP(s)；配置签名后执行 scripts/build-release.ps1）'
  }
}

# ---------- 7. 人工项 ----------
Add-Result 'MANUAL' '隐私政策网址' 'AGC 上架必填，需可公网访问（项目内已有 PrivacyPolicyPage，需另行部署网页版）'
Add-Result 'MANUAL' '软件著作权' 'AGC 版权信息需要软著证书或代理证书'
Add-Result 'MANUAL' 'APP 备案' '工信部 APP 备案，未备案无法上架，建议尽早启动'
Add-Result 'MANUAL' '应用截图与描述' 'AGC 需提供各分辨率截图、应用简介、分类'
Add-Result 'MANUAL' 'IDE 体检' 'DevEco Studio → Code → Inspect Code（Code Linter）与 Tools → AppAnalyzer 上架前体检需在 IDE 内执行'

# ---------- 输出 ----------
$failCount = @($results | Where-Object { $_.Level -eq 'FAIL' }).Count
$warnCount = @($results | Where-Object { $_.Level -eq 'WARN' }).Count
$passCount = @($results | Where-Object { $_.Level -eq 'PASS' }).Count

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('# 简单外卖 App 上架体检报告')
[void]$lines.Add('')
[void]$lines.Add("生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$lines.Add('')
[void]$lines.Add("结论：PASS $passCount 项 / WARN $warnCount 项 / FAIL $failCount 项 / 人工项 " + @($results | Where-Object { $_.Level -eq 'MANUAL' }).Count + ' 项')
[void]$lines.Add('')
[void]$lines.Add('| 级别 | 检查项 | 说明 |')
[void]$lines.Add('| --- | --- | --- |')
foreach ($r in $results) {
  [void]$lines.Add("| $($r.Level) | $($r.Item) | $($r.Detail) |")
}
[void]$lines.Add('')
if ($failCount -gt 0) {
  [void]$lines.Add('## 阻塞项（必须处理）')
  [void]$lines.Add('')
  foreach ($r in @($results | Where-Object { $_.Level -eq 'FAIL' })) {
    [void]$lines.Add("- **$($r.Item)**：$($r.Detail)")
  }
  [void]$lines.Add('')
}
[void]$lines.Add('## 复现方式')
[void]$lines.Add('')
[void]$lines.Add('```powershell')
[void]$lines.Add('# 仅静态体检')
[void]$lines.Add('powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1')
[void]$lines.Add('')
[void]$lines.Add('# 体检 + Release 构建')
[void]$lines.Add('powershell -ExecutionPolicy Bypass -File scripts/release-check.ps1 -Build')
[void]$lines.Add('```')
[void]$lines.Add('')
[void]$lines.Add('> 签名材料（.p12/.cer/.p7b）必须在华为开发者账号下申请，见 `md/上架体检与Release签名.md`。')

$outPath = Join-Path $root $OutFile
[System.IO.File]::WriteAllText($outPath, ($lines -join "`r`n"), $utf8)

foreach ($r in $results) {
  $color = switch ($r.Level) {
    'FAIL' { 'Red' }
    'WARN' { 'Yellow' }
    'PASS' { 'Green' }
    default { 'Gray' }
  }
  Write-Host ("[{0}] {1}：{2}" -f $r.Level, $r.Item, $r.Detail) -ForegroundColor $color
}
Write-Host ''
Write-Host "报告已写入：$outPath" -ForegroundColor Cyan
Write-Host "阻塞项 $failCount 项，警告 $warnCount 项" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

exit $failCount

<#
.SYNOPSIS
  Device regression driver for the rider (骑手端) and admin (管理端) roles.

.DESCRIPTION
  Rider fixture (backend API only): user orders + pays (1) -> merchant accepts (2) -> merchant marks
  出餐完成/ready (still 2, ready_time set) so the order enters the rider pool.
  Then, per role, the app data is wiped to the guest state and the case logs in with the matching
  一键登录 button:
    * RiderFlow : 上线开关（API 核对 online 0→1）→ 抢单大厅抢单 → 我的配送单取餐 → 送达
      host checks: order status 2→3→4, rider assigned, rider 累计配送/收入 +1
    * AdminFlow : 平台管理页（C 端入口必须不出现）→ 十个模块入口齐全 → 逐个进入 6 个代表页并断言标题

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-role-regression.ps1 -Build
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$SkipInstall,
  [long]$StoreId = 1,
  [long]$GoodsId = 7,
  [long]$AddressId = 1,
  [string]$ApiBase = 'http://127.0.0.1:9000',
  [string]$Bundle = 'com.example.jiandanwaimai',
  [string]$Ability = 'EntryAbility'
)

$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
Set-Location (Split-Path -Parent $PSScriptRoot)

$script:failures = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) { Write-Host ("[PASS] {0} : {1}" -f $name, $detail) -ForegroundColor Green }
  else { Write-Host ("[FAIL] {0} : {1}" -f $name, $detail) -ForegroundColor Red; $script:failures = $script:failures + 1 }
}

function Login([string]$phone) {
  $body = '{"phone":"' + $phone + '","password":"123456"}'
  return Invoke-RestMethod -Uri "$ApiBase/api/auth/login" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20
}

function Invoke-Api([string]$method, [string]$path, [string]$token, [string]$body) {
  $headers = @{ Authorization = "Bearer $token" }
  if ($null -eq $body -or $body -eq '') {
    return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -TimeoutSec 20
  }
  return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
}

function Reset-ToGuest {
  & $hdc shell bm clean -n $Bundle -d | Out-Null
  Start-Sleep -Seconds 2
  & $hdc shell aa force-stop $Bundle | Out-Null
  Start-Sleep -Seconds 2
  & $hdc shell aa start -a $Ability -b $Bundle | Out-Null
  Start-Sleep -Seconds 14
  & $hdc shell hilog -r | Out-Null
  Start-Sleep -Seconds 2
}

function Run-Class([string]$testClass) {
  $out = & $hdc shell "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner -s class $testClass -s timeout 300000" 2>&1 | Out-String
  $out -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|stream=|stack=' } | ForEach-Object { Write-Host "  $_" }
  $pass = 0; $fail = 0; $err = 0
  if ($out -match 'Pass:\s*(\d+)') { $pass = [int]$Matches[1] }
  if ($out -match 'Failure:\s*(\d+)') { $fail = [int]$Matches[1] }
  if ($out -match 'Error:\s*(\d+)') { $err = [int]$Matches[1] }
  Check ("uitest-{0}-passed" -f $testClass) ($pass -ge 1 -and $fail -eq 0 -and $err -eq 0) ("pass={0} failure={1} error={2}" -f $pass, $fail, $err)
}

# ---------- 1. build ----------
if ($Build) {
  Write-Host '=== [1/6] build ===' -ForegroundColor Cyan
  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  $mainOut = & $node $hvigor --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon 2>&1
  if (($mainOut | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] main build failed' -ForegroundColor Red
    ($mainOut | Select-String -Pattern 'ERROR|Error Message') | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
    exit 1
  }
  $testOut = & $node $hvigor --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon 2>&1
  if (($testOut | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] ohosTest build failed' -ForegroundColor Red
    ($testOut | Select-String -Pattern 'ERROR|Error Message') | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
    exit 1
  }
  Write-Host '  BUILD SUCCESSFUL (main + ohosTest)' -ForegroundColor Green
} else {
  Write-Host '=== [1/6] build skipped ===' -ForegroundColor DarkGray
}

if (-not $SkipInstall) {
  Write-Host '=== [2/6] install ===' -ForegroundColor Cyan
  & $hdc install entry\build\default\outputs\default\entry-default-unsigned.hap
  & $hdc install entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
} else {
  Write-Host '=== [2/6] install skipped ===' -ForegroundColor DarkGray
}

# ---------- 2. rider fixture：出餐完成、未分配骑手 ----------
Write-Host '=== [3/6] rider fixture: order ready in pool, rider offline ===' -ForegroundColor Cyan
$userToken = (Login '13800138000').data.token
$merchantToken = (Login '13600136000').data.token
$riderLogin = Login '13300133000'
$riderToken = $riderLogin.data.token
Invoke-Api 'POST' '/api/auth/recharge' $userToken '{"amount":200}' | Out-Null
# 骑手先下线，保证用例里的「上线开关」有真实的状态变化可断言
Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":0}' | Out-Null

$goods = (Invoke-Api 'GET' "/api/stores/$StoreId/goods" $userToken '').data | Where-Object { $_.id -eq $GoodsId }
$orderBody = '{{"storeId":{0},"items":[{{"goodsId":{1},"goodsName":"DSH rider fixture","price":{2},"quantity":1,"image":"","specId":0,"specName":"","seckillId":0}}],"addressId":{3},"couponId":0,"remark":"dsh rider fixture","checkoutGoodsIds":[],"expectTime":""}}' -f $StoreId, $GoodsId, $goods.price, $AddressId
$orderId = (Invoke-Api 'POST' '/api/orders' $userToken $orderBody).data.id
Invoke-Api 'POST' "/api/orders/$orderId/pay" $userToken '' | Out-Null
Invoke-Api 'PUT' "/api/merchant/orders/$orderId/accept" $merchantToken '' | Out-Null
$ready = (Invoke-Api 'PUT' "/api/merchant/orders/$orderId/ready" $merchantToken '').data
# 待取餐池接口要求骑手在线（离线会 500），所以先上线查一次，再下线，让用例里的「上线开关」有真实状态变化
Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":1}' | Out-Null
$pool = @((Invoke-Api 'GET' '/api/rider/orders/pool' $riderToken '').data)
$poolHit = @($pool | Where-Object { [long]$_.id -eq $orderId })
Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":0}' | Out-Null
$riderBefore = (Invoke-Api 'GET' '/api/rider/profile' $riderToken '').data
Write-Host ("  order {0} status={1}; rider pool={2} (contains fixture={3}); rider online before={4} totalOrders={5} income={6}" -f `
  $orderId, $ready.status, $pool.Count, ($poolHit.Count -ge 1), $riderBefore.online, $riderBefore.totalOrders, $riderBefore.totalIncome)
Check 'fixture-order-in-pool' (([int]$ready.status -eq 2) -and ($poolHit.Count -ge 1)) `
  ("order {0} status={1}, present in rider pool={2}" -f $orderId, $ready.status, ($poolHit.Count -ge 1))

# ---------- 3. rider case ----------
Write-Host '=== [4/6] RiderFlow ===' -ForegroundColor Cyan
Reset-ToGuest
Run-Class 'RiderFlow'
$riderAfter = (Invoke-Api 'GET' '/api/rider/profile' $riderToken '').data
$orderAfter = (Invoke-Api 'GET' "/api/orders/$orderId" $userToken '').data
Write-Host ("  rider online after={0} totalOrders={1} income={2}" -f $riderAfter.online, $riderAfter.totalOrders, $riderAfter.totalIncome)
Write-Host ("  order {0} status={1}" -f $orderId, $orderAfter.status)
Check 'rider-went-online' ([int]$riderAfter.online -eq 1) ("online {0} -> {1}" -f $riderBefore.online, $riderAfter.online)
Check 'order-picked-up-and-delivered' ([int]$orderAfter.status -eq 4) ("status {0} -> {1} (4 = 已送达待确认收货)" -f $ready.status, $orderAfter.status)
Check 'rider-totals-increased' ([int]$riderAfter.totalOrders -eq [int]$riderBefore.totalOrders + 1 -and [double]$riderAfter.totalIncome -gt [double]$riderBefore.totalIncome) `
  ("totalOrders {0} -> {1}, income {2} -> {3}" -f $riderBefore.totalOrders, $riderAfter.totalOrders, $riderBefore.totalIncome, $riderAfter.totalIncome)

# ---------- 4. admin case ----------
Write-Host '=== [5/6] AdminFlow ===' -ForegroundColor Cyan
Reset-ToGuest
Run-Class 'AdminFlow'

Write-Host '=== [6/6] done ===' -ForegroundColor Cyan
Write-Host ''
if ($script:failures -eq 0) {
  Write-Host 'RESULT: all checks passed' -ForegroundColor Green
  exit 0
}
Write-Host ("RESULT: {0} check(s) failed" -f $script:failures) -ForegroundColor Red
exit 1

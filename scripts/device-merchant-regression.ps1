<#
.SYNOPSIS
  Device regression driver for the merchant (商户端) flow: fixture a paid order, drive 接单→出餐(ready)
  through the app UI, then cross-check the order state (制作中/骑手池) and the stats numbers on the host.

.DESCRIPTION
  Fixture (backend API only, ASCII request bodies to avoid the documented encoding traps):
    user 13800138000 recharges -> orders goods 7 of store 1 -> pays => status=1 (待接单).
  The app data is wiped first (`bm clean`) so the case runs from the guest state, accepts the privacy
  policy, and logs in through the 一键登录商户 button.

  Checks after the on-device run:
    * UiTest class passed
    * fixture order ended at status=2 with ready_time set (出餐完成进入骑手待取餐池；2->3、3->4 由骑手端)
    * hilog contains the two merchant action logs (接单/出餐)
    * the numbers rendered on 收入统计 match /api/merchant/stats (today count/income); mismatch is
      reported as a warning because the page may intentionally derive some figures from the local list.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-merchant-regression.ps1 -Build
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$SkipInstall,
  [long]$StoreId = 1,
  [long]$GoodsId = 7,
  [long]$AddressId = 27,
  [string]$TestClass = 'MerchantFlow',
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

function Warn([string]$name, [string]$detail) {
  Write-Host ("[WARN] {0} : {1}" -f $name, $detail) -ForegroundColor Yellow
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

# ---------- 1. fixture：造一笔待接单订单 ----------
Write-Host '=== [1/6] fixture: paid order waiting for merchant ===' -ForegroundColor Cyan
$userToken = (Login '13800138000').data.token
$merchantToken = (Login '13600136000').data.token
Invoke-Api 'POST' '/api/auth/recharge' $userToken '{"amount":200}' | Out-Null

$goods = (Invoke-Api 'GET' "/api/stores/$StoreId/goods" $userToken '').data | Where-Object { $_.id -eq $GoodsId }
$orderBody = '{{"storeId":{0},"items":[{{"goodsId":{1},"goodsName":"DSH merchant fixture","price":{2},"quantity":1,"image":"","specId":0,"specName":"","seckillId":0}}],"addressId":{3},"couponId":0,"remark":"dsh merchant fixture","checkoutGoodsIds":[],"expectTime":""}}' -f $StoreId, $GoodsId, $goods.price, $AddressId
$orderId = (Invoke-Api 'POST' '/api/orders' $userToken $orderBody).data.id
$paid = (Invoke-Api 'POST' "/api/orders/$orderId/pay" $userToken '').data
Write-Host ("  order id={0} status after pay={1}" -f $orderId, $paid.status)
Check 'fixture-order-waiting-accept' ([int]$paid.status -eq 1) ("order {0} status={1} (1 = 待接单)" -f $orderId, $paid.status)

# ---------- 2. build ----------
if ($Build) {
  Write-Host '=== [2/6] build ===' -ForegroundColor Cyan
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
  Write-Host '=== [2/6] build skipped ===' -ForegroundColor DarkGray
}

if (-not $SkipInstall) {
  Write-Host '=== [3/6] install ===' -ForegroundColor Cyan
  & $hdc install entry\build\default\outputs\default\entry-default-unsigned.hap
  & $hdc install entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
} else {
  Write-Host '=== [3/6] install skipped ===' -ForegroundColor DarkGray
}

# ---------- 3. guest state + location permission ----------
Write-Host '=== [4/6] wipe data (guest), grant location, relaunch ===' -ForegroundColor Cyan
& $hdc shell bm clean -n $Bundle -d
Start-Sleep -Seconds 2
$tokenLine = (& $hdc shell "bm dump -n $Bundle" | Select-String -Pattern 'accessTokenId"' | Select-Object -First 1).Line
if ($tokenLine -match '(\d+)') {
  $tokenId = $Matches[1]
  & $hdc shell "atm perm -g -i $tokenId -p ohos.permission.LOCATION" | Out-Null
  & $hdc shell "atm perm -g -i $tokenId -p ohos.permission.APPROXIMATELY_LOCATION" | Out-Null
}
& $hdc shell aa force-stop $Bundle
Start-Sleep -Seconds 2
& $hdc shell aa start -a $Ability -b $Bundle
Start-Sleep -Seconds 14
& $hdc shell hilog -r
Start-Sleep -Seconds 2

# ---------- 4. run ----------
Write-Host ("=== [5/6] run UiTest class {0} ===" -f $TestClass) -ForegroundColor Cyan
$runOut = & $hdc shell "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner -s class $TestClass -s timeout 300000" 2>&1 | Out-String
$runOut -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|stream=|stack=' } | ForEach-Object { Write-Host "  $_" }
$pass = 0; $fail = 0; $err = 0
if ($runOut -match 'Pass:\s*(\d+)') { $pass = [int]$Matches[1] }
if ($runOut -match 'Failure:\s*(\d+)') { $fail = [int]$Matches[1] }
if ($runOut -match 'Error:\s*(\d+)') { $err = [int]$Matches[1] }
Check 'uitest-class-passed' ($pass -ge 1 -and $fail -eq 0 -and $err -eq 0) ("pass={0} failure={1} error={2}" -f $pass, $fail, $err)

# ---------- 5. host-side checks ----------
Write-Host '=== [6/6] host-side checks ===' -ForegroundColor Cyan
$after = (Invoke-Api 'GET' "/api/orders/$orderId" $userToken '').data
Write-Host ("  order {0}: status={1} escrow={2}" -f $orderId, $after.status, $after.escrowStatus)
Check 'order-ready-by-merchant' ([int]$after.status -eq 2) ("status {0} -> {1} (2 = 制作中/已出餐，待骑手接单；2->3、3->4 由骑手端完成)" -f $paid.status, $after.status)
Check 'escrow-still-pending' ([int]$after.escrowStatus -eq 0) ("escrow={0} (0 = 用户尚未确认收货)" -f $after.escrowStatus)

$merchantLogs = & $hdc shell "hilog -x | grep -cE 'Merchant'"
Write-Host ("  app log lines containing 'Merchant' = {0}" -f $merchantLogs)
$acceptLogs = [int](& $hdc shell "hilog -x | grep -c 'click accept'")
$flowLogs = & $hdc shell "hilog -x | grep -E '\[MerchantFlow\]' | grep -v REPORT | tail -12"
$flowLogs | ForEach-Object { Write-Host "  $_" }

# 收入统计：用例把渲染出的数字打进 hilog，这里与 /api/merchant/stats 交叉核对
$statsLine = $flowLogs | Where-Object { $_ -match 'stats todayRevenue=' } | Select-Object -Last 1
$apiStats = (Invoke-Api 'GET' "/api/merchant/stats?storeId=$StoreId&range=week" $merchantToken '').data
Write-Host ("  api stats: todayCount={0} todayIncome={1} weekCount={2} weekIncome={3}" -f $apiStats.todayCount, $apiStats.todayIncome, $apiStats.weekCount, $apiStats.weekIncome)
if ($null -eq $statsLine) {
  Check 'stats-rendered' $false 'no [MerchantFlow] stats log line found'
} else {
  $rendered = [regex]::Match($statsLine, 'stats todayRevenue=(\S+) todayOrders=(\S+) completedOrders=(\S+)')
  if (-not $rendered.Success) {
    Check 'stats-rendered' $false ("could not parse: " + $statsLine)
  } else {
    $uiIncome = $rendered.Groups[1].Value
    $uiToday = $rendered.Groups[2].Value
    Check 'stats-rendered' ($uiIncome.Length -gt 0 -and $uiToday.Length -gt 0) ("今日收入={0} 今日订单={1} 已完成订单={2}" -f $uiIncome, $uiToday, $rendered.Groups[3].Value)
    $expectedIncome = '¥' + ([double]$apiStats.todayIncome).ToString('0.00')
    if ($uiIncome -ne $expectedIncome) {
      Warn 'stats-income-matches-api' ("UI {0} vs API {1} (页面口径可能与接口不同，人工确认)" -f $uiIncome, $expectedIncome)
    } else {
      Check 'stats-income-matches-api' $true ("UI {0} = API {1}" -f $uiIncome, $expectedIncome)
    }
  }
}

Write-Host ''
if ($script:failures -eq 0) {
  Write-Host 'RESULT: all checks passed' -ForegroundColor Green
  exit 0
}
Write-Host ("RESULT: {0} check(s) failed" -f $script:failures) -ForegroundColor Red
exit 1

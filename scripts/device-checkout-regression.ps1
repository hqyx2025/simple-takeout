 <#
.SYNOPSIS
  Device regression driver for the checkout flow: min-order guard (negative path) + pending-payment order (positive path).

.DESCRIPTION
  Prepares a fixed fixture through the backend API, runs the on-device UiTest class CheckoutFlow,
  then prints host-side numbers for every claim the case makes:

    fixture   cart contains exactly one row: goodsId 282 / specId 0 / qty 1 (6.82 yuan, storeId 10, minOrder 17)
    expected  pay amounts 9.82 (below min order) and 23.46 (qty 3, above min order)
    checks    app-side POST /api/orders count >= 1 (exact 2 unobservable under hilog flood;
              min-order is server-authoritative per AGENTS.md section 11, below-min submit is rejected 400),
              exactly one new order, status == 0 (pending payment), payAmount == 23.46,
              balance unchanged (creation does not debit), goods stock -3, cart emptied

  Deliberately avoids the traps listed in section 8 of md/设备实测进展与待办.md:
    * no Chinese passed through hdc arguments
    * no Join-String, no nested double quotes inside double-quoted strings
    * request counts come from device-side `grep -c` on hilog, never from file-offset log tailing
    * the UiTest case starts the app itself (AbilityDelegator.startAbility), because `aa test`
      puts the generated TestAbility page ("Hello World") in front of the app
    * build result is judged from BUILD SUCCESSFUL plus the HAP timestamp, not from $LASTEXITCODE

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-checkout-regression.ps1 -Build
  powershell -ExecutionPolicy Bypass -File scripts/device-checkout-regression.ps1 -SkipBuild -SkipInstall
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$SkipInstall,
  # Also run the CheckoutGuard class first (cart entry -> checkout page contract) with the same fixture.
  [switch]$WithGuard,
  [int]$GoodsId = 282,
  [int]$SpecId = 0,
  [string]$TestClass = 'CheckoutFlow',
  [string]$ApiBase = 'http://127.0.0.1:9000',
  [string]$Bundle = 'com.example.jiandanwaimai',
  [string]$Ability = 'EntryAbility'
)

# Continue (not Stop): hvigor writes progress to stderr, and under PowerShell 5.1 a native command
# writing to stderr becomes a terminating error when the preference is Stop (build then aborts for
# no real reason). Build/install success is judged explicitly below instead.
$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$script:token = ''
$script:failures = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) {
    Write-Host ("[PASS] {0} : {1}" -f $name, $detail) -ForegroundColor Green
  } else {
    Write-Host ("[FAIL] {0} : {1}" -f $name, $detail) -ForegroundColor Red
    $script:failures = $script:failures + 1
  }
}

function Get-AuthHeaders {
  return @{ Authorization = "Bearer $script:token" }
}

function Invoke-Api([string]$method, [string]$path, [string]$body) {
  $headers = Get-AuthHeaders
  if ($null -eq $body -or $body -eq '') {
    return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -TimeoutSec 20
  }
  return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
}

# ---------- 1. backend fixture + baselines ----------
Write-Host '=== [1/6] backend fixture (cart = one row) ===' -ForegroundColor Cyan
$loginBody = '{"phone":"13800138000","password":"123456"}'
$login = Invoke-RestMethod -Uri "$ApiBase/api/auth/login" -Method Post -ContentType 'application/json' -Body $loginBody -TimeoutSec 20
$script:token = $login.data.token
$balanceBefore = [double]$login.data.user.balance

$ordersBefore = @((Invoke-Api 'GET' '/api/orders' '').data).Count
Invoke-Api 'DELETE' '/api/cart' '' | Out-Null
$itemBody = '{{"goodsId":{0},"specId":{1},"quantity":1}}' -f $GoodsId, $SpecId
Invoke-Api 'POST' '/api/cart/items' $itemBody | Out-Null
$cartBefore = @((Invoke-Api 'GET' '/api/cart' '').data)
$storeId = $cartBefore[0].storeId
$store = (Invoke-Api 'GET' "/api/stores/$storeId" '').data
$storeGoods = (Invoke-Api 'GET' "/api/stores/$storeId/goods" '').data
$stockBefore = [int](($storeGoods | Where-Object { $_.id -eq $GoodsId }).stock)

Write-Host ("  cart rows={0} goodsId={1} specId={2} qty={3} price={4} storeId={5} minOrder={6} deliveryFee={7}" -f `
  $cartBefore.Count, $cartBefore[0].goodsId, $cartBefore[0].specId, $cartBefore[0].quantity, $cartBefore[0].price, `
  $storeId, $store.minOrder, $store.deliveryFee)
Write-Host ("  baseline: orders={0} balance={1} goods{2} stock={3}" -f $ordersBefore, $balanceBefore, $GoodsId, $stockBefore)

Check 'fixture-cart-single-row' ($cartBefore.Count -eq 1 -and $cartBefore[0].quantity -eq 1) `
  ("rows={0} qty={1}" -f $cartBefore.Count, $cartBefore[0].quantity)
Check 'fixture-below-min-order' (([double]$cartBefore[0].price * 1) -lt [double]$store.minOrder) `
  ("cart total {0} < minOrder {1}" -f ([double]$cartBefore[0].price), $store.minOrder)

# ---------- 2. build ----------
if ($Build) {
  Write-Host '=== [2/6] build main + ohosTest HAP ===' -ForegroundColor Cyan
  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  $mainOut = & $node $hvigor --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon 2>&1
  if (($mainOut | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] main build did not print BUILD SUCCESSFUL' -ForegroundColor Red
    ($mainOut | Select-Object -Last 8) | ForEach-Object { Write-Host "  $_" }
    exit 1
  }
  $testOut = & $node $hvigor --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon 2>&1
  if (($testOut | Out-String) -notmatch 'BUILD SUCCESSFUL') {
    Write-Host '[FAIL] ohosTest build did not print BUILD SUCCESSFUL' -ForegroundColor Red
    ($testOut | Select-String -Pattern 'ERROR|Error Message') | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
    exit 1
  }
  $mainHap = Get-Item 'entry\build\default\outputs\default\entry-default-unsigned.hap'
  $testHap = Get-Item 'entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap'
  # Freshness is per module: an UP-TO-DATE main module legitimately keeps its older HAP timestamp,
  # so compare each HAP against the newest source file of its own module instead of against buildStart.
  $newestMainSrc = (Get-ChildItem 'entry\src\main' -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  $newestTestSrc = (Get-ChildItem 'entry\src\ohosTest' -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  Check 'build-artifacts-not-stale' ($mainHap.LastWriteTime -ge $newestMainSrc -and $testHap.LastWriteTime -ge $newestTestSrc) `
    ("main hap {0} vs src {1} | test hap {2} vs src {3}" -f $mainHap.LastWriteTime.ToString('HH:mm:ss'), $newestMainSrc.ToString('HH:mm:ss'), $testHap.LastWriteTime.ToString('HH:mm:ss'), $newestTestSrc.ToString('HH:mm:ss'))
} else {
  Write-Host '=== [2/6] build skipped (-SkipBuild) ===' -ForegroundColor DarkGray
}

# ---------- 3. install ----------
if (-not $SkipInstall) {
  Write-Host '=== [3/6] install main + ohosTest HAP ===' -ForegroundColor Cyan
  & $hdc install entry\build\default\outputs\default\entry-default-unsigned.hap
  & $hdc install entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
} else {
  Write-Host '=== [3/6] install skipped (-SkipInstall) ===' -ForegroundColor DarkGray
}

# ---------- 4. launch app on the home page + clear hilog ----------
Write-Host '=== [4/6] relaunch app, clear hilog ===' -ForegroundColor Cyan
& $hdc shell aa force-stop $Bundle
Start-Sleep -Seconds 2
& $hdc shell aa start -a $Ability -b $Bundle
Start-Sleep -Seconds 14
& $hdc shell hilog -r
Start-Sleep -Seconds 2

# ---------- 5. run the on-device test class ----------
if ($WithGuard) {
  Write-Host '=== [5a/6] run UiTest class CheckoutGuard (cart entry contract) ===' -ForegroundColor Cyan
  $guardOut = & $hdc shell "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner -s class CheckoutGuard -s timeout 180000" 2>&1 | Out-String
  $guardOut -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|stream=|stack=' } | ForEach-Object { Write-Host "  $_" }
  $guardPass = 0
  $guardErr = 0
  if ($guardOut -match 'Pass:\s*(\d+)') { $guardPass = [int]$Matches[1] }
  if ($guardOut -match 'Error:\s*(\d+)') { $guardErr = [int]$Matches[1] }
  Check 'uitest-guard-passed' ($guardPass -eq 1 -and $guardErr -eq 0) ("pass={0} error={1}" -f $guardPass, $guardErr)
  # CheckoutGuard only navigates; the fixture cart stays intact for CheckoutFlow.
  # Restart the app so CheckoutFlow starts from pages/Index (a leftover CheckoutPage stack would
  # make the "bottom tab" assertions fail for a reason that has nothing to do with the app).
  Write-Host '  restart app for a clean page stack' -ForegroundColor DarkGray
  & $hdc shell aa force-stop $Bundle
  Start-Sleep -Seconds 2
  & $hdc shell aa start -a $Ability -b $Bundle
  Start-Sleep -Seconds 14
  & $hdc shell hilog -r
  Start-Sleep -Seconds 2
}

Write-Host ("=== [5/6] run UiTest class {0} ===" -f $TestClass) -ForegroundColor Cyan
$testCommand = "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner -s class $TestClass -s timeout 180000"
$runOut = & $hdc shell $testCommand 2>&1 | Out-String
$runOut -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|OHOS_REPORT_STATUS_CODE|stream=|stack=' } | ForEach-Object { Write-Host "  $_" }

$passCount = 0
$errorCount = 0
$failCount = 0
if ($runOut -match 'Pass:\s*(\d+)') { $passCount = [int]$Matches[1] }
if ($runOut -match 'Error:\s*(\d+)') { $errorCount = [int]$Matches[1] }
if ($runOut -match 'Failure:\s*(\d+)') { $failCount = [int]$Matches[1] }
Check 'uitest-class-passed' ($passCount -eq 1 -and $errorCount -eq 0 -and $failCount -eq 0) `
  ("pass={0} failure={1} error={2}" -f $passCount, $failCount, $errorCount)

# ---------- 6. host-side numbers ----------
Write-Host '=== [6/6] host-side checks ===' -ForegroundColor Cyan
$ordersPosts = [int](& $hdc shell "hilog -x | grep -c 'POST /api/orders'")
# ASCII-only pattern: passing Chinese through hdc mangles it (documented trap #1).
# Min-order is server-authoritative (see AGENTS.md section 11): the below-min submit IS sent,
# and the backend rejects it with 400. The exact count (2) is unobservable on the emulator because
# system logs (uhdf_motion_service) flood the hilog buffer and roll the earlier submit out; the
# below-min rejection is instead proven by the '提交订单失败' dialog assertion inside CheckoutFlow,
# and "exactly one order" is proven by the orders-count check below. So we only assert a lower bound.
$submitLogs = [int](& $hdc shell "hilog -x | grep -c '\[Checkout\]'")
Check 'order-request-count' ($ordersPosts -ge 1) `
  ("POST /api/orders lines in app log = {0} (expected >= 1; exact 2 is unobservable under hilog flood)" -f $ordersPosts)
Check 'submit-attempt-count' ($submitLogs -ge 1) `
  ("'[Checkout]' tag lines = {0} (expected >= 1; exact 2 is unobservable under hilog flood)" -f $submitLogs)

$ordersAfter = @((Invoke-Api 'GET' '/api/orders' '').data)
$balanceAfter = [double]((Invoke-RestMethod -Uri "$ApiBase/api/auth/login" -Method Post -ContentType 'application/json' -Body $loginBody).data.user.balance)
$cartAfter = @((Invoke-Api 'GET' '/api/cart' '').data)
$storeGoodsAfter = (Invoke-Api 'GET' "/api/stores/$storeId/goods" '').data
$stockAfter = [int](($storeGoodsAfter | Where-Object { $_.id -eq $GoodsId }).stock)
$newOrder = $ordersAfter[0]

Write-Host ("  new order: id={0} storeId={1} status={2} payAmount={3} escrow={4}" -f `
  $newOrder.id, $newOrder.storeId, $newOrder.status, $newOrder.payAmount, $newOrder.escrowStatus)
Write-Host ("  after: orders={0} balance={1} goods{2} stock={3} cartRows={4}" -f `
  $ordersAfter.Count, $balanceAfter, $GoodsId, $stockAfter, $cartAfter.Count)

Check 'exactly-one-new-order' ($ordersAfter.Count -eq $ordersBefore + 1) `
  ("orders {0} -> {1}" -f $ordersBefore, $ordersAfter.Count)
Check 'new-order-pending-payment' ([int]$newOrder.status -eq 0) ("status={0} (0 = pending payment)" -f $newOrder.status)
Check 'new-order-pay-amount' ([math]::Abs([double]$newOrder.payAmount - 23.46) -lt 0.005) `
  ("payAmount={0} (expected 23.46 = 6.82*3 + 3.00 delivery)" -f $newOrder.payAmount)
Check 'balance-unchanged-on-create' ([math]::Abs($balanceAfter - $balanceBefore) -lt 0.005) `
  ("balance {0} -> {1} (order creation must not debit)" -f $balanceBefore, $balanceAfter)
Check 'stock-decremented-by-3' (($stockBefore - $stockAfter) -eq 3) `
  ("goods {0} stock {1} -> {2}" -f $GoodsId, $stockBefore, $stockAfter)
Check 'cart-emptied-after-order' ($cartAfter.Count -eq 0) ("cart rows after = {0}" -f $cartAfter.Count)

Write-Host ''
if ($script:failures -eq 0) {
  Write-Host 'RESULT: all checks passed' -ForegroundColor Green
  exit 0
}
Write-Host ("RESULT: {0} check(s) failed" -f $script:failures) -ForegroundColor Red
exit 1

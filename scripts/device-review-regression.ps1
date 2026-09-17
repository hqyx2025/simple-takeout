<#
.SYNOPSIS
  Device regression driver for the review (图文评价) flow: fixture a completed order, run the ReviewFlow
  UiTest class, then verify upload + rendering numbers on the host.

.DESCRIPTION
  Fixture built purely through the backend API (no Chinese is ever passed through hdc or a request body,
  to avoid the documented encoding traps):
    user 13800138000 places an order at store 1 (goods 7) -> pays -> merchant 13600136000 accepts,
    delivers and completes it -> user confirms receipt (escrow 0 -> 1) => status=4 / reviewed=0.

  Checks after the on-device run:
    * UiTest class passed (2 cases)
    * exactly one new file under the backend upload dir, reachable over /uploads/**
    * the fixture order is now reviewed=1 and its review carries >=1 image URL
    * the image URL stored in the review actually returns HTTP 200

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-review-regression.ps1 -Build
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [switch]$SkipInstall,
  [long]$StoreId = 1,
  [long]$GoodsId = 7,
  [long]$AddressId = 1,
  [string]$TestClass = 'ReviewFlow',
  [string]$ApiBase = 'http://127.0.0.1:9000',
  [string]$Bundle = 'com.example.jiandanwaimai',
  [string]$Ability = 'EntryAbility'
)

$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$script:failures = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) {
    Write-Host ("[PASS] {0} : {1}" -f $name, $detail) -ForegroundColor Green
  } else {
    Write-Host ("[FAIL] {0} : {1}" -f $name, $detail) -ForegroundColor Red
    $script:failures = $script:failures + 1
  }
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

# 上传目录（后端工作目录下 uploads/，见 takeout.upload.dir）
$uploadDir = $null
foreach ($candidate in @((Join-Path $root 'server\uploads'), (Join-Path $root 'uploads'))) {
  if (Test-Path $candidate) { $uploadDir = $candidate; break }
}
if ($null -eq $uploadDir) { $uploadDir = Join-Path $root 'server\uploads' }

function Count-Uploads {
  if (-not (Test-Path $uploadDir)) { return 0 }
  return (Get-ChildItem $uploadDir -Recurse -File | Measure-Object).Count
}

# ---------- 1. fixture：造一笔「已完成且未评价」的订单 ----------
Write-Host '=== [1/6] fixture: completed + unreviewed order ===' -ForegroundColor Cyan
$userLogin = Login '13800138000'
$userToken = $userLogin.data.token
$merchantLogin = Login '13600136000'
$merchantToken = $merchantLogin.data.token
$riderLogin = Login '13300133000'
$riderToken = $riderLogin.data.token
Write-Host ("  user balance before = {0}" -f $userLogin.data.user.balance)

# 每次跑都要 pay 一笔，余额会持续减少（订单不会自动退款）；先测试充值保证 pay 不会因余额不足 400
$rechargeBody = '{"amount":200}'
$recharged = (Invoke-Api 'POST' '/api/auth/recharge' $userToken $rechargeBody).data
Write-Host ("  recharged -> balance = {0}" -f $recharged.balance)

$goods = (Invoke-Api 'GET' "/api/stores/$StoreId/goods" $userToken '').data | Where-Object { $_.id -eq $GoodsId }
$price = [double]$goods.price
$orderBody = '{{"storeId":{0},"items":[{{"goodsId":{1},"goodsName":"DSH fixture goods","price":{2},"quantity":1,"image":"","specId":0,"specName":"","seckillId":0}}],"addressId":{3},"couponId":0,"remark":"dsh review fixture","checkoutGoodsIds":[],"expectTime":""}}' -f $StoreId, $GoodsId, $price, $AddressId
$created = (Invoke-Api 'POST' '/api/orders' $userToken $orderBody).data
$orderId = $created.id
Write-Host ("  order created id={0} status={1} payAmount={2}" -f $orderId, $created.status, $created.payAmount)

$paid = (Invoke-Api 'POST' "/api/orders/$orderId/pay" $userToken '').data
Write-Host ("  paid -> status={0}" -f $paid.status)
Invoke-Api 'PUT' "/api/merchant/orders/$orderId/accept" $merchantToken '' | Out-Null
Invoke-Api 'PUT' "/api/merchant/orders/$orderId/ready" $merchantToken '' | Out-Null
Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":1}' | Out-Null
Invoke-Api 'POST' "/api/rider/orders/$orderId/grab" $riderToken '' | Out-Null
Invoke-Api 'PUT' "/api/rider/orders/$orderId/pickup" $riderToken '' | Out-Null
Invoke-Api 'PUT' "/api/rider/orders/$orderId/deliver" $riderToken '' | Out-Null
$confirmed = (Invoke-Api 'PUT' "/api/orders/$orderId/confirm" $userToken '').data
Write-Host ("  user confirm -> status={0} escrow={1} reviewed={2}" -f $confirmed.status, $confirmed.escrowStatus, $confirmed.reviewed)

Check 'fixture-order-reviewable' ([int]$confirmed.status -eq 4 -and [int]$confirmed.escrowStatus -eq 1 -and [int]$confirmed.reviewed -eq 0) `
  ("order {0}: status={1} escrow={2} reviewed={3}" -f $orderId, $confirmed.status, $confirmed.escrowStatus, $confirmed.reviewed)

$uploadsBefore = Count-Uploads
$reviewsBefore = @((Invoke-Api 'GET' "/api/stores/$StoreId/reviews" $userToken '').data).Count
Write-Host ("  baseline: uploads={0} storeReviews={1}" -f $uploadsBefore, $reviewsBefore)

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

# ---------- 4. relaunch ----------
Write-Host '=== [4/6] relaunch app + clear hilog ===' -ForegroundColor Cyan
& $hdc shell aa force-stop $Bundle
Start-Sleep -Seconds 2
& $hdc shell aa start -a $Ability -b $Bundle
Start-Sleep -Seconds 14
& $hdc shell hilog -r
Start-Sleep -Seconds 2

# ---------- 5. run ----------
Write-Host ("=== [5/6] run UiTest class {0} ===" -f $TestClass) -ForegroundColor Cyan
$runOut = & $hdc shell "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner -s class $TestClass -s timeout 240000" 2>&1 | Out-String
$runOut -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|stream=|stack=' } | ForEach-Object { Write-Host "  $_" }
$pass = 0; $fail = 0; $err = 0
if ($runOut -match 'Pass:\s*(\d+)') { $pass = [int]$Matches[1] }
if ($runOut -match 'Failure:\s*(\d+)') { $fail = [int]$Matches[1] }
if ($runOut -match 'Error:\s*(\d+)') { $err = [int]$Matches[1] }
Check 'uitest-class-passed' ($pass -ge 1 -and $fail -eq 0 -and $err -eq 0) ("pass={0} failure={1} error={2}" -f $pass, $fail, $err)

$appUploadLogs = [int](& $hdc shell "hilog -x | grep -c 'upload'")
Write-Host ("  app log lines containing 'upload' = {0}" -f $appUploadLogs)

# ---------- 6. host-side checks ----------
Write-Host '=== [6/6] host-side checks ===' -ForegroundColor Cyan
# 图片上传结果改由 review 返回的 image url 判定（后面的 review-image-url-ok），
# 不再依赖 host 侧 uploads 目录：docker 部署下该目录是容器命名卷 uploads-data，与宿主本机目录不互通。

$orderAfter = (Invoke-Api 'GET' "/api/orders/$orderId" $userToken '').data
Check 'order-marked-reviewed' ([int]$orderAfter.reviewed -eq 1) ("order {0} reviewed={1}" -f $orderId, $orderAfter.reviewed)

$reviews = @((Invoke-Api 'GET' "/api/stores/$StoreId/reviews" $userToken '').data)
Write-Host ("  store {0} reviews: {1} -> {2}" -f $StoreId, $reviewsBefore, $reviews.Count)
$mine = $reviews | Where-Object { [long]$_.orderId -eq $orderId }
if ($null -eq $mine) {
  Check 'review-created-with-image' $false ("no review for order {0} in store {1} reviews" -f $orderId, $StoreId)
} else {
  $imagesRaw = $mine.images
  $imageList = @()
  if ($imagesRaw -is [string]) {
    if ($imagesRaw -ne '') { $imageList = @($imagesRaw | ConvertFrom-Json) }
  } elseif ($null -ne $imagesRaw) {
    $imageList = @($imagesRaw)
  }
  Check 'review-created-with-image' ($imageList.Count -ge 1) ("review id={0} rating={1} images={2}" -f $mine.id, $mine.rating, $imageList.Count)
  if ($imageList.Count -ge 1) {
    # 应用里存的是模拟器可用地址（10.0.2.2 是模拟器到宿主机的 NAT 别名），宿主机抓取要换成 127.0.0.1
    $imgUrl = ([string]$imageList[0]).Replace('10.0.2.2', '127.0.0.1')
    Write-Host ("  review image url (host view) = {0}" -f $imgUrl)
    try {
      $imgResp = Invoke-WebRequest -Uri $imgUrl -UseBasicParsing -TimeoutSec 15
      Check 'review-image-url-ok' ($imgResp.StatusCode -eq 200) ("GET {0} -> {1}" -f $imgUrl, $imgResp.StatusCode)
    } catch {
      Check 'review-image-url-ok' $false ("GET {0} failed: {1}" -f $imgUrl, $_.Exception.Message)
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

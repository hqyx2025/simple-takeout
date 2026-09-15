<#
.SYNOPSIS
  API-only end-to-end check of the rider delivery chain against a real backend + MySQL.

.DESCRIPTION
  Regression sentinel for the bug where the merchant 出餐 button called 'deliver' instead of 'ready':
  the rider pool filters on `status = 2 AND ready_time <> '' AND rider_id = 0`, so an order pushed to
  status=3 permanently skipped riders (empty 抢单大厅, every grab failed with "手慢了").

  Asserts the whole chain on real SQL (not mocked), in this order:
    1. user orders + pays            -> status 1
    2. merchant accepts              -> status 2
    3. merchant marks 出餐完成/ready  -> status STILL 2, ready_time set
    4. order appears in the rider pool
    5. rider grabs                   -> rider_id bound, customer sees rider name
    6. rider picks up                -> status 3
    7. rider delivers                -> status 4 + rider 累计单量/收入 +1
    8. merchant list exposes the rider (front-end hides merchant-side buttons)
    9. a rider-assigned order can no longer be advanced by the merchant (readable rejection)
   10. the OLD broken path is proven harmful: merchant 'deliver' keeps the order out of the pool

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File TemporaryCacheStorage/agent-rider-chain-e2e.ps1 -ApiBase http://127.0.0.1:9001
#>
[CmdletBinding()]
param(
  [long]$StoreId = 1,
  [long]$GoodsId = 7,
  [long]$AddressId = 27,
  [string]$ApiBase = 'http://127.0.0.1:9001'
)

$ErrorActionPreference = 'Continue'
$script:failures = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
  if ($ok) { Write-Host ("[PASS] {0} : {1}" -f $name, $detail) -ForegroundColor Green }
  else { Write-Host ("[FAIL] {0} : {1}" -f $name, $detail) -ForegroundColor Red; $script:failures++ }
}

function Login([string]$phone) {
  $body = '{"phone":"' + $phone + '","password":"123456"}'
  return (Invoke-RestMethod -Uri "$ApiBase/api/auth/login" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20).data.token
}

function Invoke-Api([string]$method, [string]$path, [string]$token, [string]$body) {
  $headers = @{ Authorization = "Bearer $token" }
  try {
    if ($null -eq $body -or $body -eq '') {
      return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -TimeoutSec 20
    }
    return Invoke-RestMethod -Uri "$ApiBase$path" -Method $method -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
  } catch {
    # 后端用 4xx + ApiResponse 表达业务拒绝，这里把响应体取出来当作返回值，便于断言错误文案
    $resp = $_.Exception.Response
    if ($null -ne $resp) {
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      return ($reader.ReadToEnd() | ConvertFrom-Json)
    }
    throw
  }
}

Write-Host "=== rider chain e2e against $ApiBase ===" -ForegroundColor Cyan

$userToken = Login '13800138000'
$merchantToken = Login '13600136000'
$riderToken = Login '13300133000'
Check 'login-three-roles' ($userToken.Length -gt 20 -and $merchantToken.Length -gt 20 -and $riderToken.Length -gt 20) 'user/merchant/rider tokens obtained'

Invoke-Api 'POST' '/api/auth/recharge' $userToken '{"amount":200}' | Out-Null

function New-PaidOrder() {
  $goods = (Invoke-Api 'GET' "/api/stores/$StoreId/goods" $userToken '').data | Where-Object { $_.id -eq $GoodsId }
  $orderBody = '{{"storeId":{0},"items":[{{"goodsId":{1},"goodsName":"DSH chain probe","price":{2},"quantity":1,"image":"","specId":0,"specName":"","seckillId":0}}],"addressId":{3},"couponId":0,"remark":"dsh chain probe","checkoutGoodsIds":[],"expectTime":""}}' -f $StoreId, $GoodsId, $goods.price, $AddressId
  $created = Invoke-Api 'POST' '/api/orders' $userToken $orderBody
  if ([int]$created.code -ne 200) { throw ("create order failed: " + $created.message) }
  $id = [long]$created.data.id
  Invoke-Api 'POST' "/api/orders/$id/pay" $userToken '' | Out-Null
  Invoke-Api 'PUT' "/api/merchant/orders/$id/accept" $merchantToken '' | Out-Null
  return $id
}

$riderBefore = (Invoke-Api 'GET' '/api/rider/profile' $riderToken '').data
Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":1}' | Out-Null

# ---------- happy path ----------
$orderId = New-PaidOrder
Write-Host "  fixture order id=$orderId" -ForegroundColor DarkGray

$ready = (Invoke-Api 'PUT' "/api/merchant/orders/$orderId/ready" $merchantToken '').data
Check 'ready-keeps-status-2' ([int]$ready.status -eq 2) ("status after 出餐完成 = {0} (must stay 2, 3 would skip the rider pool)" -f $ready.status)
Check 'ready-time-exposed' (([string]$ready.readyTime).Length -gt 0) ("readyTime = '{0}' (front-end uses it to show 已出餐，等待骑手接单)" -f $ready.readyTime)

$pool = @((Invoke-Api 'GET' '/api/rider/orders/pool' $riderToken '').data)
$inPool = @($pool | Where-Object { [long]$_.id -eq $orderId }).Count -ge 1
Check 'order-enters-rider-pool' $inPool ("pool size={0}, contains fixture={1}" -f $pool.Count, $inPool)

$grab = Invoke-Api 'POST' "/api/rider/orders/$orderId/grab" $riderToken ''
Check 'grab-succeeds' ([int]$grab.code -eq 200) ("code={0} message={1}" -f $grab.code, $grab.message)
Check 'grab-binds-rider' (([string]$grab.data.riderName).Length -gt 0) ("riderName = '{0}'" -f $grab.data.riderName)

$customerView = (Invoke-Api 'GET' "/api/orders/$orderId" $userToken '').data
Check 'customer-sees-rider' (([string]$customerView.riderName).Length -gt 0) ("customer order detail riderName = '{0}'" -f $customerView.riderName)

$merchantList = @((Invoke-Api 'GET' '/api/merchant/orders' $merchantToken '').data)
$mine = @($merchantList | Where-Object { [long]$_.id -eq $orderId })[0]
Check 'merchant-list-exposes-rider' ($null -ne $mine -and ([string]$mine.riderName).Length -gt 0) ("merchant list riderName = '{0}' (front-end hides merchant buttons)" -f $(if ($null -eq $mine) { '<missing>' } else { $mine.riderName }))

$blocked = Invoke-Api 'PUT' "/api/merchant/orders/$orderId/deliver" $merchantToken ''
Check 'merchant-cannot-advance-rider-order' ([int]$blocked.code -ne 200) ("code={0} message={1}" -f $blocked.code, $blocked.message)

$pickup = (Invoke-Api 'PUT' "/api/rider/orders/$orderId/pickup" $riderToken '').data
Check 'pickup-2-to-3' ([int]$pickup.status -eq 3) ("status = {0}" -f $pickup.status)

$delivered = (Invoke-Api 'PUT' "/api/rider/orders/$orderId/deliver" $riderToken '').data
Check 'deliver-3-to-4' ([int]$delivered.status -eq 4) ("status = {0} (4 = 已送达待确认收货)" -f $delivered.status)

$riderAfter = (Invoke-Api 'GET' '/api/rider/profile' $riderToken '').data
Check 'rider-totals-increased' (([int]$riderAfter.totalOrders -eq [int]$riderBefore.totalOrders + 1) -and ([double]$riderAfter.totalIncome -gt [double]$riderBefore.totalIncome)) `
  ("totalOrders {0} -> {1}, income {2} -> {3}" -f $riderBefore.totalOrders, $riderAfter.totalOrders, $riderBefore.totalIncome, $riderAfter.totalIncome)

# ---------- the old broken path, proven harmful ----------
$badId = New-PaidOrder
Invoke-Api 'PUT' "/api/merchant/orders/$badId/deliver" $merchantToken '' | Out-Null
$badPool = @((Invoke-Api 'GET' '/api/rider/orders/pool' $riderToken '').data)
$badInPool = @($badPool | Where-Object { [long]$_.id -eq $badId }).Count -ge 1
Check 'old-deliver-path-skips-rider' (-not $badInPool) ("order {0} advanced by merchant deliver is absent from pool={1} (this is exactly why 出餐 must use ready)" -f $badId, (-not $badInPool))

Invoke-Api 'PUT' '/api/rider/status' $riderToken '{"online":0}' | Out-Null

Write-Host ''
if ($script:failures -eq 0) { Write-Host 'ALL RIDER CHAIN CHECKS PASSED' -ForegroundColor Green }
else { Write-Host ("FAILURES: {0}" -f $script:failures) -ForegroundColor Red }
exit $script:failures
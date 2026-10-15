[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$NotifyUrl,
  [string]$KeyDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.takeout-secrets\alipay-sandbox\9021000169644800'),
  [int]$Port = 18088,
  [int]$DatabasePort = 3306
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$callback = [Uri]$NotifyUrl
if ((-not $callback.IsAbsoluteUri) -or $callback.Scheme -ne 'https' -or $callback.UserInfo -ne '' -or
    $callback.AbsolutePath -ne '/api/payment/alipay/notify') {
  throw 'NotifyUrl must be an HTTPS URL ending with /api/payment/alipay/notify'
}
if ($Port -lt 1024 -or $Port -gt 65535 -or $DatabasePort -lt 1 -or $DatabasePort -gt 65535) {
  throw 'Invalid sandbox service/database port'
}

function Read-SandboxKey([string]$name) {
  $value = [IO.File]::ReadAllText((Join-Path $KeyDirectory $name), [Text.Encoding]::UTF8).Trim()
  $value = $value -replace '-----BEGIN [^-]+-----|-----END [^-]+-----|\s', ''
  if ($value -eq '') { throw "Empty key file: $name" }
  return $value
}

$env:TAKEOUT_ALIPAY_APP_PRIVATE_KEY = Read-SandboxKey '支付宝应用私钥.txt'
$env:TAKEOUT_ALIPAY_PUBLIC_KEY = Read-SandboxKey '支付宝公钥.txt'
$env:TAKEOUT_ALIPAY_APP_ID = '9021000169644800'
$env:TAKEOUT_ALIPAY_SELLER_ID = '2088721115957570'
$env:TAKEOUT_ALIPAY_NOTIFY_URL = $NotifyUrl
$env:TAKEOUT_PAYMENT_REAL_ENABLED = 'true'
$env:TAKEOUT_PAYMENT_MOCK_ENABLED = 'false'
$env:TAKEOUT_PAYMENT_SANDBOX = 'true'
$env:SPRING_PROFILES_ACTIVE = 'sandbox'
$env:SPRING_DATASOURCE_URL = "jdbc:mysql://127.0.0.1:$DatabasePort/takeout_sandbox?createDatabaseIfNotExist=true&useSSL=false&serverTimezone=Asia/Shanghai&characterEncoding=utf8&allowPublicKeyRetrieval=true"
$env:TAKEOUT_JWT_SECRET = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
$env:TAKEOUT_APP_PORT = $Port.ToString()
$env:TAKEOUT_CACHE_ENABLED = 'false'
$env:TAKEOUT_MQ_ENABLED = 'false'
$env:TAKEOUT_RATE_LIMIT_ENABLED = 'false'
$env:TAKEOUT_JOB_LOCK_ENABLED = 'false'

$jar = Join-Path $root 'server\takeout-app\target\takeout-app-1.0.0.jar'
if (-not (Test-Path -LiteralPath $jar)) { throw 'Build the backend package before starting the sandbox' }
$cache = Join-Path $root 'TemporaryCacheStorage'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$runtimeJar = Join-Path $cache ('takeout-sandbox-' + [Guid]::NewGuid().ToString('N') + '.jar')
Copy-Item -LiteralPath $jar -Destination $runtimeJar
# Force the JDK's TCP fallback for the AF_UNIX loopback failure on this Windows host.
$socketFallback = '-Djdk.net.unixdomain.tmpdir=' + (Join-Path $cache 'no-unix-sockets')
Write-Host "Starting Alipay sandbox on 127.0.0.1:$Port; database=takeout_sandbox; Ctrl+C stops it."
& 'C:\Program Files\Java\jdk-25.0.2\bin\java.exe' $socketFallback -jar $runtimeJar --server.address=127.0.0.1

param(
  [Parameter(Mandatory=$true)][ValidateSet('app','erp','gateway')][string]$Service,
  [int]$Port=0,
  [switch]$RecordJfr,
  [switch]$HeapDumpOnOom
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$jar=Join-Path $root "server/takeout-$Service/target/takeout-$Service-1.0.0.jar"
if (-not (Test-Path -LiteralPath $jar)) { throw "Build first: mvn -f server/pom.xml -pl takeout-$Service -am package" }
$java=Join-Path $env:JAVA_HOME 'bin/java.exe'
if (-not (Test-Path -LiteralPath $java)) { throw 'Set JAVA_HOME to JDK 25.' }
$diagnostic=Join-Path $root "TemporaryCacheStorage/jvm/$Service"
New-Item -ItemType Directory -Force -Path $diagnostic | Out-Null
$size=(Get-ChildItem -LiteralPath $diagnostic -File | Measure-Object Length -Sum).Sum
if ($size -gt 1GB) { throw 'Diagnostic directory exceeds 1 GiB; review and remove old artifacts.' }
if ($Port -eq 0) { $Port=@{app=9100;erp=9200;gateway=8087}[$Service] }
if ($Service -eq 'app') { $env:TAKEOUT_APP_PORT="$Port" }
if ($Service -eq 'erp') { $env:TAKEOUT_ERP_PORT="$Port" }
if ($Service -eq 'gateway') { $env:TAKEOUT_GATEWAY_PORT="$Port" }
$heap=if ($Service -eq 'app') {384} else {192}
$options=@('-Dfile.encoding=UTF-8','-Duser.timezone=Asia/Shanghai',"-Djdk.net.unixdomain.tmpdir=$diagnostic",'-Xms64m',"-Xmx$($heap)m",'-XX:+ExitOnOutOfMemoryError',"-Xlog:gc*,safepoint:file=TemporaryCacheStorage/jvm/$Service/gc-%p.log:time,uptime,level,tags:filecount=5,filesize=5M", "-XX:ErrorFile=$diagnostic/hs_err_pid%p.log")
if ($RecordJfr) { $options+="-XX:StartFlightRecording=settings=profile,duration=60s,maxsize=64m,filename=$diagnostic/start-$([DateTimeOffset]::Now.ToUnixTimeSeconds()).jfr" }
if ($HeapDumpOnOom) {
  # At most one dump per start; kept private, requires explicit operator choice and disk budget.
  if ((Get-PSDrive -Name ([IO.Path]::GetPathRoot($diagnostic).Substring(0,1))).Free -lt 1GB) { throw 'Insufficient disk for a controlled heap dump.' }
  if ($size + $heap*1MB -gt 1GB) { throw 'OOM dump would exceed the 1 GiB diagnostic budget.' }
  $options+=@('-XX:+HeapDumpOnOutOfMemoryError',"-XX:HeapDumpPath=$diagnostic/oom-$([DateTimeOffset]::Now.ToUnixTimeSeconds()).hprof")
}
Set-Location $root
& $java @options -jar $jar
exit $LASTEXITCODE

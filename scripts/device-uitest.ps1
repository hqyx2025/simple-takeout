<#
.SYNOPSIS
  Generic on-device UiTest runner: build (optional) -> install (optional) -> launch app -> run a test class -> print result.

.DESCRIPTION
  Why a runner exists: `aa test` pulls the generated TestAbility page ("Hello World") in front of the
  app, so every case has to start the app itself (that is what UiTestHelper.launchAppUnderTest does).
  This script only owns the device/host plumbing, not the assertions.

  Traps avoided (section 8 of md/设备实测进展与待办.md):
    * never passes Chinese through hdc arguments
    * no Join-String, no nested double quotes inside double-quoted strings
    * build success is judged from BUILD SUCCESSFUL plus HAP timestamps, not from $LASTEXITCODE
    * -GuestClean uses `bm clean` (no UI coordinate chains) to get a deterministic guest state

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/device-uitest.ps1 -Class LoginFlow -GuestClean
  powershell -ExecutionPolicy Bypass -File scripts/device-uitest.ps1 -Class LocationFlow
  powershell -ExecutionPolicy Bypass -File scripts/device-uitest.ps1 -Build -Class Probe
#>
[CmdletBinding()]
param(
  # Test class (hypium describe name) to run; empty runs the whole aggregated suite.
  [string]$Class = '',
  [switch]$Build,
  [switch]$SkipInstall,
  # Wipe app data first (guest state: consent page -> login page). Also clears the login session.
  [switch]$GuestClean,
  # Pre-grant the location permissions. On a freshly installed/wiped app the first location request
  # raises a system permission dialog that COVERS the app window, so UiTest cannot find anything on
  # the location page (observed: "window is covered" + privacycenter window in the widget dump).
  [switch]$GrantLocation,
  [string]$Bundle = 'com.example.jiandanwaimai',
  [string]$Ability = 'EntryAbility',
  [int]$Timeout = 180000
)

# Continue (not Stop): hvigor writes progress to stderr and PowerShell 5.1 turns native stderr into a
# terminating error under 'Stop'. Success is judged explicitly below.
$ErrorActionPreference = 'Continue'
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
$hvigor = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
Set-Location (Split-Path -Parent $PSScriptRoot)

if ($Build) {
  Write-Host '=== build main + ohosTest HAP ===' -ForegroundColor Cyan
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
  $newestMain = (Get-ChildItem 'entry\src\main' -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  $newestTest = (Get-ChildItem 'entry\src\ohosTest' -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  $mainHap = (Get-Item 'entry\build\default\outputs\default\entry-default-unsigned.hap').LastWriteTime
  $testHap = (Get-Item 'entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap').LastWriteTime
  if ($mainHap -lt $newestMain -or $testHap -lt $newestTest) {
    Write-Host ("[FAIL] stale artifact: main hap {0} vs src {1} | test hap {2} vs src {3}" -f `
      $mainHap.ToString('HH:mm:ss'), $newestMain.ToString('HH:mm:ss'), $testHap.ToString('HH:mm:ss'), $newestTest.ToString('HH:mm:ss')) -ForegroundColor Red
    exit 1
  }
  Write-Host ("  BUILD SUCCESSFUL (main hap {0}, test hap {1})" -f $mainHap.ToString('HH:mm:ss'), $testHap.ToString('HH:mm:ss')) -ForegroundColor Green
}

if (-not $SkipInstall) {
  Write-Host '=== install main + ohosTest HAP ===' -ForegroundColor Cyan
  & $hdc install entry\build\default\outputs\default\entry-default-unsigned.hap
  & $hdc install entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
}

if ($GuestClean) {
  Write-Host '=== wipe app data (guest state) ===' -ForegroundColor Cyan
  & $hdc shell bm clean -n $Bundle -d
  Start-Sleep -Seconds 2
}

if ($GrantLocation) {
  Write-Host '=== grant location permissions ===' -ForegroundColor Cyan
  $tokenLine = (& $hdc shell "bm dump -n $Bundle" | Select-String -Pattern 'accessTokenId"' | Select-Object -First 1).Line
  if ($tokenLine -match '(\d+)') {
    $tokenId = $Matches[1]
    Write-Host ("  accessTokenId={0}" -f $tokenId)
    & $hdc shell "atm perm -g -i $tokenId -p ohos.permission.LOCATION"
    & $hdc shell "atm perm -g -i $tokenId -p ohos.permission.APPROXIMATELY_LOCATION"
  } else {
    Write-Host '  [WARN] could not resolve accessTokenId; location page may stay behind a system dialog' -ForegroundColor Yellow
  }
}

Write-Host '=== relaunch app, clear hilog ===' -ForegroundColor Cyan
& $hdc shell aa force-stop $Bundle
Start-Sleep -Seconds 2
& $hdc shell aa start -a $Ability -b $Bundle
Start-Sleep -Seconds 14
& $hdc shell hilog -r
Start-Sleep -Seconds 2

$classArg = ''
if ($Class -ne '') { $classArg = " -s class $Class" }
Write-Host ("=== run UiTest{0} ===" -f $(if ($Class -ne '') { " class $Class" } else { ' (full suite)' })) -ForegroundColor Cyan
$runOut = & $hdc shell "aa test -b $Bundle -m entry_test -s unittest OpenHarmonyTestRunner$classArg -s timeout $Timeout" 2>&1 | Out-String
$runOut -split "`n" | Where-Object { $_ -match 'OHOS_REPORT_RESULT|OHOS_REPORT_STATUS_CODE|stream=|stack=|class=' } | ForEach-Object { Write-Host "  $_" }

if ($runOut -match 'Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+)') {
  $run = [int]$Matches[1]; $fail = [int]$Matches[2]; $err = [int]$Matches[3]; $pass = [int]$Matches[4]
  Write-Host ("  summary: run={0} pass={1} failure={2} error={3}" -f $run, $pass, $fail, $err)
  if ($err -eq 0 -and $fail -eq 0 -and $pass -gt 0) {
    Write-Host 'RESULT: passed' -ForegroundColor Green
    exit 0
  }
  Write-Host 'RESULT: failed' -ForegroundColor Red
  exit 1
}
Write-Host 'RESULT: could not parse test summary' -ForegroundColor Red
exit 1

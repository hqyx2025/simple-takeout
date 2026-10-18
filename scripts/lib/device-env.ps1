param()

$script:DevEcoHome = if ($env:DEVECO_HOME) { $env:DEVECO_HOME } else { 'C:\Program Files\Huawei\DevEco Studio' }
$script:DevEcoSdkHome = if ($env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME } else { Join-Path $script:DevEcoHome 'sdk' }
$script:DevEcoNode = Join-Path $script:DevEcoHome 'tools\node\node.exe'
$script:DevEcoHvigor = Join-Path $script:DevEcoHome 'tools\hvigor\bin\hvigorw.js'
$script:DevEcoHdc = Join-Path $script:DevEcoSdkHome 'default\openharmony\toolchains\hdc.exe'
$script:DevEcoEmulator = Join-Path $script:DevEcoHome 'tools\emulator\Emulator.exe'

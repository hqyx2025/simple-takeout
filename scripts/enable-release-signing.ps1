<#
.SYNOPSIS
  把 AppGallery Connect 下载的发布证书/Profile 接入本工程签名配置（Release 打包用）。

.DESCRIPTION
  上架包必须使用「发布证书 + 发布 Profile」签名，签名材料（.p12/.cer/.p7b）需要在
  华为开发者账号下生成并下载，无法由脚本代替申请。拿到材料后执行本脚本即可完成接入：

    1. 校验 .p12 / .cer / .p7b 三个文件是否存在；
    2. 生成 signing/release-signing.json5（含密码，已被 .gitignore 排除，不会提交）；
    3. 把签名配置写入 build-profile.json5 的 signingConfigs（幂等，可反复执行）；
    4. -Revert 可还原为未配置状态，保证日常 debug 构建不受影响。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/enable-release-signing.ps1 `
    -StoreFile D:\secure\takeout-release.p12 -StorePassword 'Abcd1234!' `
    -KeyAlias takeout_release_2026 -KeyPassword 'Abcd1234!' `
    -ProfileFile D:\secure\takeout-release.p7b -CertFile D:\secure\takeout-release.cer

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/enable-release-signing.ps1 -Revert
#>
[CmdletBinding()]
param(
  [string]$StoreFile,
  [string]$StorePassword,
  [string]$KeyAlias,
  [string]$KeyPassword,
  [string]$ProfileFile,
  [string]$CertFile,
  [string]$SignAlg = 'SHA256withECDSA',
  [string]$ConfigName = 'default',
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$buildProfile = Join-Path $root 'build-profile.json5'
$signingJson = Join-Path $root 'signing\release-signing.json5'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$path) {
  return [System.IO.File]::ReadAllText($path, $utf8)
}

function Write-Text([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, $text, $utf8)
}

function Set-SigningConfigs([string]$block) {
  $content = Read-Text $buildProfile
  $pattern = '"signingConfigs"\s*:\s*\[[\s\S]*?\]'
  if (-not [regex]::IsMatch($content, $pattern)) {
    throw "build-profile.json5 中未找到 signingConfigs 字段，请确认工程结构未被改动。"
  }
  $updated = [regex]::Replace($content, $pattern, $block, 1)
  Write-Text $buildProfile $updated
}

if ($Revert) {
  Set-SigningConfigs '"signingConfigs": []'
  if (Test-Path $signingJson) {
    Remove-Item $signingJson -Force
  }
  Write-Host '[OK] 已还原 build-profile.json5 的签名配置，并删除 signing/release-signing.json5'
  exit 0
}

foreach ($item in @(
  @{ Name = 'StoreFile'; Value = $StoreFile },
  @{ Name = 'StorePassword'; Value = $StorePassword },
  @{ Name = 'KeyAlias'; Value = $KeyAlias },
  @{ Name = 'KeyPassword'; Value = $KeyPassword },
  @{ Name = 'ProfileFile'; Value = $ProfileFile },
  @{ Name = 'CertFile'; Value = $CertFile })) {
  if ([string]::IsNullOrWhiteSpace($item.Value)) {
    throw "缺少必填参数 -$($item.Name)（可用 -Revert 还原签名配置）"
  }
}

foreach ($path in @($StoreFile, $ProfileFile, $CertFile)) {
  if (-not (Test-Path $path)) {
    throw "签名材料不存在：$path（请先在 AppGallery Connect 生成并下载）"
  }
}

$storePath = (Resolve-Path $StoreFile).Path.Replace('\', '/')
$profilePath = (Resolve-Path $ProfileFile).Path.Replace('\', '/')
$certPath = (Resolve-Path $CertFile).Path.Replace('\', '/')

# 1) 本地签名材料说明文件（含密码，勿提交）
$signingBody = @"
{
  // 由 scripts/enable-release-signing.ps1 生成，含密码，禁止提交到 Git（.gitignore 已忽略）。
  "storeFile": "$storePath",
  "storePassword": "$StorePassword",
  "keyAlias": "$KeyAlias",
  "keyPassword": "$KeyPassword",
  "signAlg": "$SignAlg",
  "profileFile": "$profilePath",
  "certpathFile": "$certPath"
}
"@
Write-Text $signingJson $signingBody

# 2) 写入 build-profile.json5（构建时读取；密码不落库到仓库，仅为本地工作区文件）
$block = @"
"signingConfigs": [
      {
        "name": "$ConfigName",
        "type": "HarmonyOS",
        "material": {
          "storeFile": "$storePath",
          "storePassword": "$StorePassword",
          "keyAlias": "$KeyAlias",
          "keyPassword": "$KeyPassword",
          "signAlg": "$SignAlg",
          "profile": "$profilePath",
          "certpath": "$certPath"
        }
      }
    ]
"@
Set-SigningConfigs $block

Write-Host '[OK] 发布签名配置已接入：'
Write-Host "     storeFile   : $storePath"
Write-Host "     profile     : $profilePath"
Write-Host "     certpath    : $certPath"
Write-Host "     keyAlias    : $KeyAlias"
Write-Host ''
Write-Host '下一步：执行 scripts/build-release.ps1 产出已签名的 Release 包。'
Write-Host '提示：签名材料与密码请勿提交到 Git；上架完成后可用 -Revert 还原。'

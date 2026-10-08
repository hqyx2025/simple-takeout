# 导出当前 Docker MySQL 的完整表结构和数据，产物保存在源码目录。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export-database.ps1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$exportDirectory = Join-Path $projectRoot 'server/database'
$exportPath = Join-Path $exportDirectory 'takeout-latest.sql'
$cacheDirectory = Join-Path $projectRoot 'TemporaryCacheStorage'
$exportId = [Guid]::NewGuid().ToString('N')
$remotePath = '/tmp/takeout-export-' + $exportId + '.sql'
$downloadPath = Join-Path $cacheDirectory ('database-export-' + $exportId + '.sql')
$preparedPath = Join-Path $cacheDirectory ('database-export-' + $exportId + '.tmp')
$previousPath = Join-Path $cacheDirectory ('database-export-' + $exportId + '.previous')
$mysqlContainer = ''

Push-Location $projectRoot
try {
    Get-Command docker -ErrorAction Stop | Out-Null
    $mysqlContainer = docker compose ps -q mysql
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mysqlContainer)) {
        throw 'Docker MySQL 未运行，请先启动项目的 mysql 服务。'
    }
    $mysqlContainer = $mysqlContainer.Trim()
    New-Item -ItemType Directory -Path $exportDirectory, $cacheDirectory -Force | Out-Null

    # 密码仅使用容器内已有环境变量，SQL 文件通过 docker cp 保持原始 UTF-8 字节。
    $dumpCommand = 'umask 077; MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --quick --default-character-set=utf8mb4 --set-gtid-purged=OFF --no-tablespaces --column-statistics=0 --hex-blob --routines --triggers --events --skip-add-drop-table --skip-add-locks --result-file="$1" takeout'
    docker exec $mysqlContainer sh -c $dumpCommand sh $remotePath
    if ($LASTEXITCODE -ne 0) { throw '数据库导出失败，已有 SQL 快照保持不变。' }
    docker cp ($mysqlContainer + ':' + $remotePath) $downloadPath
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $downloadPath) -or (Get-Item -LiteralPath $downloadPath).Length -eq 0) {
        throw 'SQL 下载失败，已有 SQL 快照保持不变。'
    }

    $header = "-- Restore this snapshot into a new/empty database.`r`n" +
        "-- AI configuration requires the original TAKEOUT_JWT_SECRET; otherwise re-enter the API Key.`r`n"
    $output = [System.IO.File]::Create($preparedPath)
    try {
        $headerBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($header)
        $output.Write($headerBytes, 0, $headerBytes.Length)
        $inputStream = [System.IO.File]::OpenRead($downloadPath)
        try { $inputStream.CopyTo($output) } finally { $inputStream.Dispose() }
    } finally { $output.Dispose() }

    # 同一工作区磁盘上原子替换；失败时保留上一次成功导出的文件。
    if (Test-Path -LiteralPath $exportPath) {
        [System.IO.File]::Replace($preparedPath, $exportPath, $previousPath)
    } else {
        [System.IO.File]::Move($preparedPath, $exportPath)
    }
    Write-Host ('[OK] 已导出：' + $exportPath) -ForegroundColor Green
    Write-Host ('[OK] 文件大小：' + (Get-Item -LiteralPath $exportPath).Length + ' 字节，UTF-8')
    Write-Host '用于新建或空数据库；恢复 AI 配置需保留原 TAKEOUT_JWT_SECRET。'
} catch {
    Write-Host ('[FAIL] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (![string]::IsNullOrWhiteSpace($mysqlContainer)) {
        try { docker exec $mysqlContainer rm -f -- $remotePath 2>$null | Out-Null } catch { }
    }
    foreach ($temporaryPath in @($downloadPath, $preparedPath, $previousPath)) {
        try {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        } catch { Write-Warning ('临时文件清理失败：' + $temporaryPath) }
    }
    Pop-Location
}

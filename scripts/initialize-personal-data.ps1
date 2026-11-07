param([string]$Path = '.env')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskTarget = [System.IO.Path]::GetFullPath((Join-Path $taskRoot $Path))
Push-Location -LiteralPath $taskRoot
try {
    & git check-ignore --quiet -- $taskTarget
    if ($LASTEXITCODE -ne 0) { throw 'The key file must be ignored by Git. Never write keys into tracked configuration.' }
    $taskText = if (Test-Path -LiteralPath $taskTarget) { [System.IO.File]::ReadAllText($taskTarget, [System.Text.Encoding]::UTF8) } else { '' }
    $taskChanged = @()
    foreach ($taskName in @('TAKEOUT_PERSONAL_DATA_ENCRYPTION_SECRET', 'TAKEOUT_PERSONAL_DATA_INDEX_SECRET')) {
        $taskPattern = '(?m)^' + [regex]::Escape($taskName) + '=([^\r\n]*)'
        if ([regex]::Matches($taskText, $taskPattern).Count -gt 1) { throw "Duplicate key name: $taskName. Resolve duplicate configuration before initializing keys." }
        $taskMatch = [regex]::Match($taskText, $taskPattern)
        if ($taskMatch.Success -and -not [string]::IsNullOrWhiteSpace($taskMatch.Groups[1].Value)) { continue }
        $taskBytes = New-Object byte[] 32
        $taskGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $taskGenerator.GetBytes($taskBytes) } finally { $taskGenerator.Dispose() }
        $taskValue = [Convert]::ToBase64String($taskBytes)
        $taskLine = $taskName + '=' + $taskValue
        if ($taskMatch.Success) { $taskText = [regex]::Replace($taskText, $taskPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $taskLine }) }
        else { $taskText = $taskText.TrimEnd("`r", "`n") + "`n" + $taskLine + "`n" }
        $taskChanged += $taskName
    }
    if ($taskChanged.Count -gt 0) {
        $taskCache = Join-Path $taskRoot 'TemporaryCacheStorage'
        [System.IO.Directory]::CreateDirectory($taskCache) | Out-Null
        $taskTemporary = Join-Path $taskCache ('personal-keys-' + [guid]::NewGuid().ToString('N') + '.env')
        [System.IO.File]::WriteAllText($taskTemporary, $taskText, [System.Text.UTF8Encoding]::new($false))
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $taskTarget)) | Out-Null
        Move-Item -LiteralPath $taskTemporary -Destination $taskTarget -Force
        Write-Output ('Initialized names only: ' + ($taskChanged -join ', '))
    } else { Write-Output 'Personal data keys already exist; preserved without rotation.' }
} finally { Pop-Location }

param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [ValidateSet('snapshot','jfr','threads','heap')][string]$Action='snapshot',
  [string]$DiagnosticDirectory='TemporaryCacheStorage/jvm',
  [ValidateRange(10,300)][int]$Seconds=60
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=[IO.Path]::GetFullPath((Join-Path $root $DiagnosticDirectory))
$allowed=([IO.Path]::GetFullPath((Join-Path $root 'TemporaryCacheStorage')))+[IO.Path]::DirectorySeparatorChar
if (-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Diagnostics must stay in private TemporaryCacheStorage, outside published assets and uploads.' }
New-Item -ItemType Directory -Force -Path $target | Out-Null
$jcmd=Join-Path $env:JAVA_HOME 'bin/jcmd.exe'
if (-not (Test-Path -LiteralPath $jcmd)) { throw 'Set JAVA_HOME to JDK 25.' }
$owned=Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId"
if (-not $owned -or $owned.Name -ne 'java.exe' -or $owned.CommandLine -notmatch 'takeout-(app|erp|gateway)') { throw 'Select a local takeout Java process.' }
$size=(Get-ChildItem -LiteralPath $target -File | Measure-Object Length -Sum).Sum
if ($size -gt 1GB) { throw 'Diagnostic directory is above 1 GiB. Review and remove old artifacts first.' }
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
if ($Action -eq 'heap') {
  # Explicit opt-in only: heap files can contain tokens, personal data and encryption keys.
  $flags=(& $jcmd $ProcessId VM.flags | Out-String)
  if ($flags -notmatch 'MaxHeapSize=(\d+)') { throw 'Cannot determine the heap dump capacity budget.' }
  $heapBytes=[int64]$Matches[1]
  if ($heapBytes+$size -gt 1GB) { throw 'Heap dump would exceed the 1 GiB diagnostic budget.' }
  if ((Get-PSDrive -Name ([IO.Path]::GetPathRoot($target).Substring(0,1))).Free -lt ($heapBytes*2+64MB)) { throw 'Insufficient private disk space for the configured heap.' }
  & $jcmd $ProcessId GC.heap_dump (Join-Path $target "heap-$ProcessId-$stamp.hprof")
} elseif ($Action -eq 'jfr') {
  & $jcmd $ProcessId JFR.start name=takeout-diagnostic settings=profile "duration=$($Seconds)s" maxsize=64m "filename=$(Join-Path $target "profile-$ProcessId-$stamp.jfr")"
} elseif ($Action -eq 'threads') {
  & $jcmd $ProcessId Thread.print -l | Out-File -Encoding utf8 (Join-Path $target "threads-$ProcessId-$stamp.txt")
} else {
  foreach ($command in @('VM.version','VM.flags','GC.heap_info','Thread.print','VM.native_memory summary')) {
    & $jcmd $ProcessId $command.Split(' ') | Out-File -Append -Encoding utf8 (Join-Path $target "snapshot-$ProcessId-$stamp.txt")
  }
}
if ($LASTEXITCODE -ne 0) { throw "jcmd failed: $LASTEXITCODE" }
Write-Output "Diagnostics saved privately to $target"

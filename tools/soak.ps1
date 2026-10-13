param(
    [string]$Executable = "$PSScriptRoot/../build/candidate_windows/Rimgate.exe",
    [string]$ReportPrefix = "$PSScriptRoot/../build/reports/ai_contract_soak"
)
$ErrorActionPreference = 'Stop'
$gamePath = [IO.Path]::GetFullPath($Executable)
$reportBase = [IO.Path]::GetFullPath($ReportPrefix)
$runtimePath = "$reportBase.json"
$memoryPath = "$reportBase-process.json"
$logPath = "$reportBase.log"
if (!(Test-Path -LiteralPath $gamePath)) { throw "Missing game: $gamePath" }
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($reportBase)) | Out-Null
$pckPath = [IO.Path]::ChangeExtension($gamePath, '.pck')
$pckHash = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash
$startedUtc = [DateTime]::UtcNow
$gameRun = Start-Process -FilePath $gamePath -WorkingDirectory ([IO.Path]::GetDirectoryName($gamePath)) -WindowStyle Hidden -PassThru -ArgumentList @(
    '--resolution', '1920x1080', '--log-file', ('"{0}"' -f $logPath), '--',
    '--qa-mode=soak', '--qa-duration=1800', ('--qa-report="{0}"' -f $runtimePath)
)
$null = $gameRun.Handle
$samples = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$watch = [Diagnostics.Stopwatch]::StartNew()
$nextSample = 0.0
$result = [ordered]@{
    executable = $gamePath; pck_sha256 = $pckHash; process_id = $gameRun.Id
    started_utc = $startedUtc.ToString('o'); completed = $false
    elapsed_seconds = 0.0; samples = $samples; failures = $issues
    memory_rule = 'Private bytes: last five samples versus samples 5-9; growth allowance max(64 MiB,25%). Working set also recorded. No allocator metric is treated as zero when unavailable.'
}
Write-Output "SOAK_STARTED game_pid=$($gameRun.Id) pck=$pckHash"
while ($true) {
    $gameRun.Refresh()
    if ($gameRun.HasExited) { break }
    if ($watch.Elapsed.TotalSeconds -ge $nextSample) {
        $samples.Add([ordered]@{
            seconds = $watch.Elapsed.TotalSeconds; working_set_bytes = $gameRun.WorkingSet64
            private_bytes = $gameRun.PrivateMemorySize64; cpu_seconds = $gameRun.TotalProcessorTime.TotalSeconds
            responding = $gameRun.Responding
        })
        $result.elapsed_seconds = $watch.Elapsed.TotalSeconds
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $memoryPath -Encoding utf8
        $nextSample += 30.0
    }
    if ($watch.Elapsed.TotalSeconds -gt 1860) {
        $issues.Add('Game did not exit within the soak duration plus sixty seconds.')
        break
    }
    Start-Sleep -Milliseconds 500
}
$result.elapsed_seconds = $watch.Elapsed.TotalSeconds
$result.completed = $gameRun.HasExited
if ($gameRun.HasExited) {
    $gameRun.WaitForExit()
    $result['game_exit_code'] = $gameRun.ExitCode
    if ($gameRun.ExitCode -ne 0) { $issues.Add("Game exited with $($gameRun.ExitCode)") }
}
if (!(Test-Path -LiteralPath $runtimePath)) {
    $issues.Add('Runtime report is missing.')
} else {
    $runtimeReport = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
    if ((Get-Item -LiteralPath $runtimePath).LastWriteTimeUtc -lt $startedUtc.AddSeconds(-2)) { $issues.Add('Runtime report predates this execution.') }
    if ($runtimeReport.pck_sha256 -ne $pckHash -or (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash -ne $pckHash) { $issues.Add('Runtime PCK binding changed.') }
    foreach ($issue in $runtimeReport.failures) { $issues.Add("Runtime: $issue") }
    if ($runtimeReport.elapsed_seconds -lt 1800 -or $runtimeReport.restarts -lt 5) { $issues.Add('Runtime duration or restart gate was not met.') }
}
if ($samples.Count -lt 15 -or ($samples | Where-Object { $_.private_bytes -le 0 }).Count -gt 0) {
    $issues.Add('Insufficient nonzero process-memory evidence.')
} else {
    # Measure explicit numbers: Windows PowerShell does not measure dictionary keys as properties.
    $early = ($samples.GetRange(4, 5) | ForEach-Object { [double]$_['private_bytes'] } | Measure-Object -Average).Average
    $late = ($samples.GetRange($samples.Count - 5, 5) | ForEach-Object { [double]$_['private_bytes'] } | Measure-Object -Average).Average
    if ($null -eq $early -or $null -eq $late -or $early -le 0 -or $late -le 0) { throw 'Process-memory averaging did not produce nonzero values.' }
    $allowance = [Math]::Max(64MB, $early * 0.25)
    $result['private_bytes_early_mean'] = $early
    $result['private_bytes_late_mean'] = $late
    $result['private_bytes_growth'] = $late - $early
    $result['private_bytes_growth_allowance'] = $allowance
    if ($late - $early -gt $allowance) { $issues.Add('Process private bytes exceeded the documented growth allowance.') }
}
if (Test-Path -LiteralPath $logPath) {
    $runtimeLog = Get-Content -LiteralPath $logPath -Raw
    if ($runtimeLog -match 'SCRIPT ERROR|ERROR:|ObjectDB instances were leaked|resources still in use at exit') {
        $issues.Add('Runtime log contains an error or exit resource leak warning.')
    }
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $memoryPath -Encoding utf8
Write-Output "SOAK_FINISHED seconds=$($result.elapsed_seconds) failures=$($issues.Count) report=$memoryPath"
if ($issues.Count -gt 0) { exit 1 }
exit 0

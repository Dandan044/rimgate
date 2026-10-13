param([string]$Executable = "$PSScriptRoot/../build/release_v0.3_windows/Rimgate.exe", [switch]$SkipMotion)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$taskExe = [IO.Path]::GetFullPath($Executable)
$taskReports = Join-Path $taskRoot 'build/reports'
$taskEvidence = Join-Path $taskRoot 'build/v3_evidence'
$taskPck = [IO.Path]::ChangeExtension($taskExe, '.pck')
$taskHash = (Get-FileHash -LiteralPath $taskPck -Algorithm SHA256).Hash
New-Item -ItemType Directory -Force -Path $taskReports, $taskEvidence | Out-Null
function Start-GameCheck([string]$Mode, [string[]]$EngineArguments = @()) {
    $taskArgs = @('--resolution', '1920x1080', '--log-file', ('"{0}"' -f (Join-Path $taskReports "v3_final_$Mode.log"))) + $EngineArguments + @('--', "--qa-mode=$Mode", ('--qa-report="{0}"' -f (Join-Path $taskReports "v3_final_$Mode.json")))
    if ($Mode -eq 'motion') { $taskArgs += '--qa-offline-movie' }
    $taskProcess = Start-Process -FilePath $taskExe -WorkingDirectory (Split-Path -Parent $taskExe) -WindowStyle Hidden -PassThru -ArgumentList $taskArgs
    Write-Output "V3_RUNTIME_STARTED mode=$Mode pid=$($taskProcess.Id) pck=$taskHash"
    return $taskProcess
}
function Confirm-GameCheck([string]$Mode, $Process) {
    $Process.WaitForExit()
    $taskResult = Get-Content -LiteralPath (Join-Path $taskReports "v3_final_$Mode.json") -Raw | ConvertFrom-Json
    if ($Process.ExitCode -ne 0 -or @($taskResult.failures).Count -gt 0 -or $taskResult.pck_sha256 -ne $taskHash) { throw "Runtime $Mode failed or refers to a different PCK." }
    $taskLog = Get-Content -LiteralPath (Join-Path $taskReports "v3_final_$Mode.log") -Raw
    if ($taskLog -match 'SCRIPT ERROR|ERROR:|ObjectDB instances were leaked|resources still in use at exit') { throw "Runtime $Mode log contains an error or resource leak." }
    Write-Output "V3_RUNTIME_PASSED mode=$Mode elapsed=$($taskResult.elapsed_seconds)"
}
if (!$SkipMotion) {
    $taskMotion = Start-GameCheck 'motion' @('--write-movie', ('"{0}"' -f (Join-Path $taskEvidence 'motion.avi')), '--fixed-fps', '60', '--disable-vsync')
    # The logger output is a string; the last pipeline object is the process.
    $taskMotion = @($taskMotion)[-1]
    Confirm-GameCheck 'motion' $taskMotion
}
$taskMonitorArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $taskRoot 'tools/soak.ps1')), '-Executable', ('"{0}"' -f $taskExe), '-ReportPrefix', ('"{0}"' -f (Join-Path $taskReports 'v3_final_soak')))
$taskSoak = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -ArgumentList $taskMonitorArgs -RedirectStandardOutput (Join-Path $taskReports 'v3_final_soak-monitor.log') -RedirectStandardError (Join-Path $taskReports 'v3_final_soak-monitor-errors.log')
$taskVictory = @(Start-GameCheck 'victory')[-1]
$taskShort = @(Start-GameCheck 'short')[-1]
Write-Output "V3_LONG_CHECKS_LIVE soak_monitor_pid=$($taskSoak.Id) victory_pid=$($taskVictory.Id) short_pid=$($taskShort.Id)"
$taskWatch = [Diagnostics.Stopwatch]::StartNew()
$taskNextStatus = 0.0
while ($true) {
    $taskSoak.Refresh(); $taskVictory.Refresh(); $taskShort.Refresh()
    if ($taskWatch.Elapsed.TotalSeconds -ge $taskNextStatus) {
        Write-Output "V3_LONG_CHECKS_PROGRESS seconds=$([int]$taskWatch.Elapsed.TotalSeconds) soak_live=$(!$taskSoak.HasExited) victory_live=$(!$taskVictory.HasExited) short_live=$(!$taskShort.HasExited)"
        $taskNextStatus += 60.0
    }
    if ($taskSoak.HasExited -and $taskVictory.HasExited -and $taskShort.HasExited) { break }
    if ($taskWatch.Elapsed.TotalSeconds -gt 1900.0) { throw 'A runtime check exceeded its declared process timeout. Inspect live process handles before restarting.' }
    Start-Sleep -Milliseconds 500
}
Confirm-GameCheck 'victory' $taskVictory
Confirm-GameCheck 'short' $taskShort
$taskSoak.WaitForExit()
if ($taskSoak.ExitCode -ne 0) { throw 'The actual soak monitor reported a failure.' }
& "$PSScriptRoot/check_soak_memory.ps1" -ReportPrefix (Join-Path $taskReports 'v3_final_soak')
if ($LASTEXITCODE -ne 0) { throw 'Independent process-memory recheck failed.' }
if ((Get-FileHash -LiteralPath $taskPck -Algorithm SHA256).Hash -ne $taskHash) { throw 'Candidate PCK changed during final checks.' }
Write-Output 'V3_RUNTIME_CHECKS_PASSED'

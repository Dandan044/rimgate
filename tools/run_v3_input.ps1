param([string]$Executable = "$PSScriptRoot/../build/release_v0.3_windows/Rimgate.exe")
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$taskExe = [IO.Path]::GetFullPath($Executable)
$taskPck = [IO.Path]::ChangeExtension($taskExe, '.pck')
$taskRaw = Join-Path $taskRoot 'build/reports/v3_final_input_raw.json'
$taskFinal = Join-Path $taskRoot 'build/reports/v3_final_input.json'
$taskCapture = Join-Path $taskRoot 'build/v3_evidence/ui-v3'
$taskLog = Join-Path $taskRoot 'build/reports/v3_final_input.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $taskRaw), (Split-Path -Parent $taskCapture) | Out-Null
$taskArgs = @('--log-file', ('"{0}"' -f $taskLog), '--', '--qa-mode=input_v3', ('--report="{0}"' -f $taskRaw), ('--capture="{0}"' -f $taskCapture))
$taskHash = (Get-FileHash -LiteralPath $taskPck -Algorithm SHA256).Hash
$taskRun = Start-Process -FilePath $taskExe -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -ArgumentList $taskArgs
Write-Output "V3_INPUT_STARTED pid=$($taskRun.Id) pck=$taskHash"
$taskRun.WaitForExit()
if (!(Test-Path -LiteralPath $taskRaw)) { throw 'Exported-package input test did not write its report.' }
$taskResult = Get-Content -LiteralPath $taskRaw -Raw | ConvertFrom-Json
if ($taskResult.pck_sha256 -ne $taskHash) { throw 'Embedded input harness identified a different executable/PCK pair.' }
$taskResult | Add-Member -Force -NotePropertyName pck_sha256 -NotePropertyValue $taskHash
$taskResult | Add-Member -Force -NotePropertyName raw_report_sha256 -NotePropertyValue (Get-FileHash -LiteralPath $taskRaw -Algorithm SHA256).Hash
$taskResult | Add-Member -Force -NotePropertyName executable -NotePropertyValue $taskExe
$taskResult | Add-Member -Force -NotePropertyName executed_arguments -NotePropertyValue $taskArgs
$taskResult | Add-Member -Force -NotePropertyName process_exit_code -NotePropertyValue $taskRun.ExitCode
$taskResult | Add-Member -Force -NotePropertyName binding_method -NotePropertyValue 'Opt-in input harness embedded in this native release EXE/PCK ran actual Viewport events and reported its own adjacent PCK hash. Raw verdict/checks are unchanged.'
$taskResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $taskFinal -Encoding utf8
if ($taskRun.ExitCode -ne 0 -or !$taskResult.passed -or (Get-FileHash -LiteralPath $taskPck -Algorithm SHA256).Hash -ne $taskHash) { throw 'Actual exported-package input test failed or its PCK changed.' }
Write-Output "V3_INPUT_PASSED checks=$(@($taskResult.checks).Count) report=$taskFinal"

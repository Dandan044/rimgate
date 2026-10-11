param([string]$ReportPrefix = "$PSScriptRoot/../build/reports/ai_contract_soak")
$ErrorActionPreference = 'Stop'
$prefix = [IO.Path]::GetFullPath($ReportPrefix)
$inputPath = "$prefix-process.json"
$raw = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath "$prefix.json" -Raw | ConvertFrom-Json
$issues = [Collections.Generic.List[string]]::new()
if (!$raw.completed -or $raw.game_exit_code -ne 0 -or $runtime.elapsed_seconds -lt 1800 -or $runtime.restarts -lt 5) { $issues.Add('Incomplete or failed stability run.') }
foreach ($issue in $raw.failures) { $issues.Add("Process: $issue") }
foreach ($issue in $runtime.failures) { $issues.Add("Runtime: $issue") }
$samples = @($raw.samples)
if ($samples.Count -lt 15 -or @($samples | Where-Object { $_.private_bytes -le 0 }).Count -gt 0) { throw 'Missing actual process-memory samples.' }
$early = ($samples[4..8] | ForEach-Object { [double]$_.private_bytes } | Measure-Object -Average).Average
$late = ($samples[($samples.Count - 5)..($samples.Count - 1)] | ForEach-Object { [double]$_.private_bytes } | Measure-Object -Average).Average
if ($null -eq $early -or $null -eq $late -or $early -le 0 -or $late -le 0) { throw 'Invalid memory averages.' }
$allowance = [Math]::Max(64MB, $early * 0.25)
if ($late - $early -gt $allowance) { $issues.Add('Process private bytes exceeded the growth allowance.') }
$logText = Get-Content -LiteralPath "$prefix.log" -Raw
if ($logText -match 'SCRIPT ERROR|ERROR:|ObjectDB instances were leaked|resources still in use at exit') { $issues.Add('Runtime log contains an error or exit leak warning.') }
$result = [ordered]@{
    method = 'Independent offline aggregation of unchanged recorded process samples; does not rerun or edit the original monitor report.'
    input_report_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $inputPath).Hash
    pck_sha256 = $raw.pck_sha256; sample_count = $samples.Count
    private_bytes_early_mean = $early; private_bytes_late_mean = $late
    private_bytes_growth = $late - $early; private_bytes_growth_allowance = $allowance
    runtime_seconds = $runtime.elapsed_seconds; restarts = $runtime.restarts
    failures = $issues
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$prefix-memory-recheck.json" -Encoding utf8
$result | ConvertTo-Json -Depth 6
if ($issues.Count) { exit 1 }

param([string]$Godot = "$PSScriptRoot/../.tools/godot/Godot_v4.7.2-stable_win64_console.exe")
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$enginePath = [IO.Path]::GetFullPath($Godot)
if (!(Test-Path -LiteralPath $enginePath)) { throw 'Provide a Godot 4.7.2 console executable with -Godot.' }
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Path '.tools' -Force | Out-Null
    & $enginePath --headless --path $projectRoot --editor --quit --log-file "$projectRoot/.tools/test_import.log"
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    $importLog = Get-Content -LiteralPath .tools/test_import.log -Raw
    if ($importLog -match 'SCRIPT ERROR|Parse Error|Failed loading resource|Error compiling') { throw 'Godot import reported a resource or script error.' }
    & $enginePath --headless --path $projectRoot --script res://tests/run_tests.gd --log-file "$projectRoot/.tools/tests.log"
    if ($LASTEXITCODE -ne 0) { throw 'Godot regression suite failed.' }
    $testLog = Get-Content -LiteralPath .tools/tests.log -Raw
    if ($testLog -notmatch 'RIMGATE_TESTS_PASSED' -or $testLog -match 'SCRIPT ERROR|Parse Error') { throw 'Missing success marker or runtime script errors.' }
} finally { Pop-Location }

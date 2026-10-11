param([string]$Godot = "$PSScriptRoot/../.tools/godot/Godot_v4.7.2-stable_win64_console.exe", [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$enginePath = [IO.Path]::GetFullPath($Godot)
Push-Location $projectRoot
try {
    if (!$SkipTests) { & "$PSScriptRoot/test.ps1" -Godot $enginePath }
    if (!(Test-Path -LiteralPath '.tools/templates/windows_release_x86_64.exe')) { throw 'Extract matching Godot 4.7.2 templates first: python tools/extract_templates.py' }
    New-Item -ItemType Directory -Path 'build/windows' -Force | Out-Null
    & $enginePath --headless --path $projectRoot --export-release 'Windows Desktop' "$projectRoot/build/windows/Rimgate.exe" --log-file "$projectRoot/.tools/export.log"
    if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
    $exportLog = Get-Content -LiteralPath .tools/export.log -Raw
    if ($exportLog -match 'SCRIPT ERROR|Parse Error|Export failed') { throw 'Windows export reported errors.' }
    Copy-Item -LiteralPath 'README.md' -Destination 'build/windows/README.md'
    Copy-Item -LiteralPath 'docs/ASSETS.md' -Destination 'build/windows/ASSETS.md'
    Copy-Item -LiteralPath 'assets/fonts/LICENSE.txt' -Destination 'build/windows/FONT_LICENSE.txt'
    Copy-Item -LiteralPath 'docs/GODOT_LICENSE.txt' -Destination 'build/windows/GODOT_LICENSE.txt'
    Compress-Archive -Path 'build/windows/*' -DestinationPath 'build/Rimgate-demo-v0.1.0-windows-x64.zip' -Force
    $sourceFiles = @('project.godot', 'main.tscn', 'export_presets.cfg', 'scripts', 'assets', 'tests', 'tools', 'docs', 'README.md', 'DEMO_PLAN.md', 'GAME_DESIGN.md')
    Compress-Archive -LiteralPath $sourceFiles -DestinationPath 'build/Rimgate-demo-v0.1.0-source.zip' -Force
    Get-FileHash -Algorithm SHA256 -LiteralPath 'build/Rimgate-demo-v0.1.0-windows-x64.zip', 'build/Rimgate-demo-v0.1.0-source.zip' | Format-Table
} finally { Pop-Location }

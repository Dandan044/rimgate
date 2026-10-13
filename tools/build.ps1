param(
    [string]$Godot = "$PSScriptRoot/../.tools/godot/Godot_v4.7.2-stable_win64_console.exe",
    [switch]$SkipTests,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?$')][string]$Version = '0.3.0',
    [string]$ExportDirectory = 'build/release_v0.3_windows',
    [string]$TestReport = '',
    [string]$EvidenceDirectory = '',
    [switch]$PackageOnly,
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$enginePath = [IO.Path]::GetFullPath($Godot)
Push-Location $projectRoot
try {
    if ($PackageOnly -and $ExportOnly) { throw 'Choose PackageOnly or ExportOnly.' }
    $series = $Version.Split('.')[1]
    if (!$TestReport) { $TestReport = "docs/V${series}_TEST_REPORT.md" }
    if (!$EvidenceDirectory) { $EvidenceDirectory = "build/v${series}_delivery_evidence/build" }
    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Build from a Git checkout so the source revision can be identified.' }
    $dirty = & git status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Commit project changes before building a versioned release.' }
    function Get-ProductFingerprint {
        $sourcePaths = & git ls-files -- project.godot main.tscn export_presets.cfg scripts assets
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate product source.' }
        $entries = foreach ($sourcePath in ($sourcePaths | Sort-Object -CaseSensitive)) {
            "$sourcePath $((Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash)"
        }
        $digest = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($entries -join "`n")))).Replace('-', '') } finally { $digest.Dispose() }
    }
    $productFingerprint = Get-ProductFingerprint
    $exportRoot = if ([IO.Path]::IsPathRooted($ExportDirectory)) { [IO.Path]::GetFullPath($ExportDirectory) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ExportDirectory)) }
    $executable = Join-Path $exportRoot 'Rimgate.exe'
    $pck = Join-Path $exportRoot 'Rimgate.pck'
    if (!$PackageOnly) {
        if (!$SkipTests) { & "$PSScriptRoot/test.ps1" -Godot $enginePath }
        if (!(Test-Path -LiteralPath '.tools/templates/windows_release_x86_64.exe')) { throw 'Extract matching Godot 4.7.2 templates first: python tools/extract_templates.py' }
        New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
        & $enginePath --headless --path $projectRoot --export-release 'Windows Desktop' $executable --log-file "$projectRoot/.tools/export.log"
        if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
        $exportLog = Get-Content -LiteralPath .tools/export.log -Raw
        if ($exportLog -match 'SCRIPT ERROR|Parse Error|Export failed') { throw 'Windows export reported errors.' }
        if ((Get-ProductFingerprint) -ne $productFingerprint) { throw 'Product source changed during export.' }
        [ordered]@{
            version = $Version; export_source_commit = $commit; product_source_sha256 = $productFingerprint
            exported_utc = [DateTime]::UtcNow.ToString('o')
            executable_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $executable).Hash
            pck_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pck).Hash
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $exportRoot 'EXPORT.json') -Encoding utf8
    }
    if (!(Test-Path -LiteralPath $executable) -or !(Test-Path -LiteralPath $pck)) { throw 'Missing Windows executable/PCK pair.' }
    $exportInfoPath = Join-Path $exportRoot 'EXPORT.json'
    if (!(Test-Path -LiteralPath $exportInfoPath)) { throw 'Missing EXPORT.json. Export with this script before reusing the build.' }
    $exportInfo = Get-Content -LiteralPath $exportInfoPath -Raw | ConvertFrom-Json
    if ($exportInfo.product_source_sha256 -ne $productFingerprint -or $exportInfo.executable_sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $executable).Hash -or $exportInfo.pck_sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $pck).Hash) { throw 'Export does not match current product source or its recorded binary hashes.' }
    if ($exportInfo.version -and $exportInfo.version -ne $Version) { throw 'Export version does not match requested package version.' }
    if ($ExportOnly) { $exportInfo; return }
    if (!(Test-Path -LiteralPath $TestReport)) { throw "Missing final test report: $TestReport" }
    $branch = (& git branch --show-current).Trim()
    $manifest = [ordered]@{
        version = $Version; source_commit = $commit; branch = $branch
        export_source_commit = $exportInfo.export_source_commit
        product_source_sha256 = $productFingerprint
        engine = '4.7.2.stable.official.ed1daf0bf'; renderer = 'Compatibility / OpenGL 3.3'
        packaged_utc = [DateTime]::UtcNow.ToString('o')
        reused_export = [bool]$PackageOnly
        executable_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $executable).Hash
        pck_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pck).Hash
        test_report = $TestReport
    }
    # A unique staging folder avoids stale files without recursive deletion.
    $stage = Join-Path $projectRoot ("build/package-$Version-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -LiteralPath $executable, $pck -Destination $stage
    Copy-Item -LiteralPath 'README.md', 'DEMO_PLAN.md', 'GAME_DESIGN.md', 'DEMO_V2_PLAN.md' -Destination $stage
    if (Test-Path -LiteralPath 'DEMO_V3_PLAN.md') { Copy-Item -LiteralPath 'DEMO_V3_PLAN.md' -Destination $stage }
    $stageDocs = Join-Path $stage 'docs'
    New-Item -ItemType Directory -Path $stageDocs -Force | Out-Null
    # Review originals belong in the source ZIP, not the playable download.
    Get-ChildItem -LiteralPath 'docs' -File | Where-Object { $_.Extension -in '.md', '.txt' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stageDocs }
    Copy-Item -LiteralPath 'assets/audio/LICENSES.txt' -Destination (Join-Path $stage 'AUDIO_LICENSES.txt')
    $audioNotices = Join-Path $stage 'source'
    New-Item -ItemType Directory -Path $audioNotices -Force | Out-Null
    Copy-Item -LiteralPath 'assets/audio/source/Tabasco-original-license.txt', 'assets/audio/source/Kenney-original-license.txt', 'assets/audio/source/MANIFEST.json' -Destination $audioNotices
    Copy-Item -LiteralPath 'assets/fonts/LICENSE.txt' -Destination (Join-Path $stage 'FONT_LICENSE.txt')
    # Optional generated evidence preserves the relative screenshot/report links.
    if (Test-Path -LiteralPath $EvidenceDirectory) {
        Copy-Item -LiteralPath $EvidenceDirectory -Destination $stage -Recurse
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'VERSION.json') -Encoding utf8
    $windowsZip = "$projectRoot/build/Rimgate-demo-v$Version-windows-x64.zip"
    $sourceZip = "$projectRoot/build/Rimgate-demo-v$Version-source.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $windowsZip -Force
    # Preserve committed bytes rather than applying this machine's CRLF checkout conversion.
    & git -c core.autocrlf=false archive --format=zip --output=$sourceZip HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Source archive failed.' }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$projectRoot/build/Rimgate-demo-v$Version-manifest.json" -Encoding utf8
    Get-FileHash -Algorithm SHA256 -LiteralPath $windowsZip, $sourceZip | Select-Object Path, Hash
} finally { Pop-Location }

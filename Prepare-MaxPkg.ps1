# Optional maintainer refresh; ordinary builds use checked-in maxpkg-assets.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$entryName = 'GC-Matterport-GLB-Converter.ms'
$source = [IO.File]::ReadAllText((Join-Path $projectRoot $entryName))
$assetRoot = Join-Path $projectRoot 'maxpkg-assets'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$packageFiles = [Collections.Generic.List[string]]::new()
$manifest = [regex]::Match($source, '(?s)\[FILES\](.*?)\[SCRIPT\]').Groups[1].Value
foreach ($match in [regex]::Matches($manifest, '(?m)^([^\r\n=]+)=')) {
    $fileName = $match.Groups[1].Value.Trim()
    if ([IO.Path]::GetFileName($fileName) -ne $fileName) { throw "Invalid manifest filename: $fileName" }
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $fileName) -PathType Leaf)) { throw "Missing runtime file: $fileName" }
    if (-not $fileName.EndsWith('.zip')) { $packageFiles.Add($fileName) }
}
if (-not $packageFiles.Contains($entryName)) { throw 'Entry is missing from [FILES].' }
foreach ($spec in @(@('model-viewer','GCMatterportViewerFiles'), @('playcanvas-viewer','GCMatterportPCViewerFiles'))) {
    $folderName = $spec[0]
    $functionName = $spec[1]
    $functionMatch = [regex]::Match($source, '(?s)fn\s+' + $functionName + '\s*=\s*\(\s*return\s*#\((.*?)\)\s*\)')
    if (-not $functionMatch.Success) { throw "Runtime whitelist not found: $functionName" }
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot ($folderName + '.zip')))
    try {
        foreach ($match in [regex]::Matches($functionMatch.Groups[1].Value, '"([^"]+)"')) {
            $relative = $match.Groups[1].Value.Replace('\\','/').Replace('\','/')
            $archiveEntry = $archive.GetEntry($relative)
            if ($null -eq $archiveEntry -or $archiveEntry.Length -le 0) { throw "Missing archive entry: $folderName/$relative" }
            $relativeOutput = 'maxpkg-assets/' + $folderName + '/' + $relative
            $destination = [IO.Path]::GetFullPath((Join-Path $projectRoot $relativeOutput))
            if (-not $destination.StartsWith($assetRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe asset path.' }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($archiveEntry, $destination, $true)
            $packageFiles.Add($relativeOutput.Replace('/','\'))
        }
    } finally { $archive.Dispose() }
}
# Preserve identity, licensing and other author choices while rebasing this checkout's paths.
$configPath = Join-Path $projectRoot 'maxpkg-packager.ini'
$config = [IO.File]::ReadAllText($configPath)
foreach ($pair in @(@('outputFolder',(Join-Path $projectRoot 'dist')), @('svgIcon',(Join-Path $projectRoot 'maxpkg-icon.svg')), @('customUninstallScript',(Join-Path $projectRoot 'maxpkg-cleanup.ms')))) {
    $pattern = '(?m)^' + [regex]::Escape($pair[0]) + '=.*$'
    $replacement = $pair[0] + '=' + $pair[1]
    $config = [regex]::Replace($config, $pattern, [Text.RegularExpressions.MatchEvaluator]{param($m) $replacement})
}
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('[files]')
$lines.Add('count=' + $packageFiles.Count)
for ($index=0; $index -lt $packageFiles.Count; $index++) {
    $lines.Add(($index+1).ToString() + '_abs=' + (Join-Path $projectRoot $packageFiles[$index]))
    $lines.Add(($index+1).ToString() + '_rel=' + $packageFiles[$index])
}
$fileSection = ($lines -join "`r`n") + "`r`n"
$config = [regex]::Replace($config, '(?ms)^\[files\].*?(?=^\[|\z)', [Text.RegularExpressions.MatchEvaluator]{param($m) $fileSection})
[IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
Write-Output ('Prepared ' + $packageFiles.Count + ' runtime files. Run maxpkg-packager.ms in 3ds Max, reload and validate before Build MZP.')
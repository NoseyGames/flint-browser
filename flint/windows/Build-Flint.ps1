#Requires -Version 5.1
[CmdletBinding()]
param([switch] $Package)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The Windows .NET Framework 4.x x64 compiler is required.' }
$browser = & (Join-Path $PSScriptRoot 'Install-Runtime.ps1')
$version = [IO.Directory]::GetParent($browser).Name
$build = Join-Path $repo ('build\flint-launcher-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($build)
$pin = Join-Path $build 'engine.txt'
$output = Join-Path $build 'Flint.exe'
$backup = Join-Path $build 'previous.exe'
$destination = Join-Path $repo 'Flint.exe'
try {
    [IO.File]::WriteAllText($pin, $version)
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll `
        "/win32icon:$PSScriptRoot\Flint.ico" "/resource:$pin,Flint.Engine" "/out:$output" (Join-Path $PSScriptRoot 'Flint.cs')
    if ($LASTEXITCODE -ne 0) { throw "C# compilation failed ($LASTEXITCODE)." }
    try {
        [IO.File]::Move($output, $destination)
    } catch [IO.IOException] {
        if (![IO.File]::Exists($destination)) { throw }
        [IO.File]::Replace($output, $destination, $backup)
    }
    Write-Output $destination
    if ($Package) {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zipPath = Join-Path $build 'Flint-Windows-x64.zip'
        $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $extension = Join-Path $repo 'flint\extension'
            $metadata = (Join-Path $extension '_metadata') + '\'
            $files = @((Get-Item -LiteralPath $destination), (Get-Item -LiteralPath (Join-Path $repo 'README.md')), (Get-Item -LiteralPath (Join-Path $repo 'LICENSE')))
            $files += @(Get-ChildItem -LiteralPath $extension -File -Recurse | Where-Object { !$_.FullName.StartsWith($metadata, [StringComparison]::OrdinalIgnoreCase) })
            $files += @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Name -eq 'initial_preferences' -or $_.Extension -in '.ps1', '.cs', '.ico' })
            $files += @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($browser)) -File -Recurse)
            foreach ($file in $files) {
                $entry = $file.FullName.Substring($repo.Length + 1).Replace('\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
            }
        } finally { $zip.Dispose() }
        $packagePath = Join-Path $repo 'build\Flint-Windows-x64.zip'
        try { [IO.File]::Move($zipPath, $packagePath) }
        catch [IO.IOException] {
            if (![IO.File]::Exists($packagePath)) { throw }
            [IO.File]::Replace($zipPath, $packagePath, (Join-Path $build 'previous.zip'))
        }
        Write-Output $packagePath
    }
} finally {
    [IO.File]::Delete($output)
    [IO.File]::Delete($backup)
    [IO.File]::Delete((Join-Path $build 'Flint-Windows-x64.zip'))
    [IO.File]::Delete((Join-Path $build 'previous.zip'))
    [IO.File]::Delete($pin)
    [IO.Directory]::Delete($build)
}

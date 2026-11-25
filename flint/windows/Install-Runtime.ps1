#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$release = '158.0.8127.36-1.1'
$chromiumVersion = '158.0.8127.36'
$archiveName = "ungoogled-chromium_${release}_windows_x64.zip"
$download = "https://github.com/ungoogled-software/ungoogled-chromium-windows/releases/download/$release/$archiveName"
$sha256 = 'bc78b9590881f8ca99aca29288d1b347ffdd689ca8a57384bb0bc113ef687b6b'
$runtime = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'runtime'))
$installed = Join-Path $runtime $release

function Test-BrowserDirectory([string]$Directory) {
    foreach ($file in 'chrome.exe', 'chrome.dll', 'icudtl.dat', 'resources.pak') {
        if (!(Test-Path -LiteralPath (Join-Path $Directory $file) -PathType Leaf)) { return $false }
    }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $Directory 'chrome.exe'))
    $version = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
    return $version -eq $chromiumVersion
}

function Install-InitialPreferences([string]$Directory) {
    $source = Join-Path $PSScriptRoot 'initial_preferences'
    $destination = Join-Path $Directory 'initial_preferences'
    $expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ([IO.File]::Exists($destination) -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $expected) { return }
    $temporary = Join-Path $Directory ('.flint-preferences-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::Copy($source, $temporary)
        if ([IO.File]::Exists($destination)) {
            [IO.File]::Replace($temporary, $destination, [NullString]::Value)
        } else {
            try { [IO.File]::Move($temporary, $destination) } catch [IO.IOException] {
                if (![IO.File]::Exists($destination) -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) { throw }
            }
        }
    } finally { [IO.File]::Delete($temporary) }
}

if (Test-BrowserDirectory $installed) {
    Install-InitialPreferences $installed
    return (Join-Path $installed 'chrome.exe')
}
if (Test-Path -LiteralPath $installed) {
    throw "Incomplete or unexpected browser at $installed. Move it aside and run the installer again."
}

[void][IO.Directory]::CreateDirectory($runtime)
$stage = Join-Path $runtime ('.install-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
try {
    $archive = Join-Path $stage $archiveName
    Write-Host "Downloading ungoogled Chromium $release for Windows x64..."
    $ProgressPreference = 'SilentlyContinue'
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $download -OutFile $archive -UseBasicParsing
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actual -ne $sha256) { throw "SHA-256 mismatch for $archiveName. Received $actual." }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $unpacked = Join-Path $stage 'unpacked'
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $unpacked)
    $browsers = @(Get-ChildItem -LiteralPath $unpacked -Filter chrome.exe -File -Recurse)
    if ($browsers.Count -ne 1 -or !(Test-BrowserDirectory $browsers[0].DirectoryName)) {
        throw "Archive does not contain the expected Chromium $chromiumVersion browser."
    }
    Install-InitialPreferences $browsers[0].DirectoryName
    try {
        [IO.Directory]::Move($browsers[0].DirectoryName, $installed)
    } catch [IO.IOException] {
        # A concurrent installation may have published the same release first.
        if (!(Test-BrowserDirectory $installed)) { throw }
    }
    Write-Host "Verified SHA-256 and installed Chromium $chromiumVersion."
    return (Join-Path $installed 'chrome.exe')
} finally {
    $stageInfo = Get-Item -LiteralPath $stage
    if ($stageInfo.Parent.FullName -eq $runtime -and $stageInfo.Name -match '^\.install-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $stageInfo.FullName -Recurse -Force
    }
}

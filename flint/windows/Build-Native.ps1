# Connect this checkout's shared patch series and native assets to the pinned
# Windows packager. Its stage action owns source retrieval, GN, Ninja and resume.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PlatformDirectory)

$ErrorActionPreference = 'Stop'
$platform = (Resolve-Path -LiteralPath $PlatformDirectory).Path
$commit = git -C $platform rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $commit -ne '76a692e3e39e1456e4691e7d9de28d32de1cdd87') {
    throw 'Expected ungoogled-chromium-windows 158.0.8127.36-1.1.'
}
$checkout = Join-Path $platform 'ungoogled-chromium'
$version = (Get-Content (Join-Path $checkout 'chromium_version.txt') -Raw).Trim()
if ($version -ne '158.0.8127.36') { throw "Unexpected Chromium version: $version" }
$hook = Join-Path $checkout 'flint\windows\Apply-NativeAssets.py'
if (!(Test-Path -LiteralPath $hook -PathType Leaf)) { throw "Missing native asset hook: $hook" }
$changes = Join-Path $PSScriptRoot 'windows-builder.patch'
git -C $platform apply --check $changes
if ($LASTEXITCODE -ne 0) { throw 'The pinned Windows build hook does not apply cleanly.' }
git -C $platform apply $changes
if ($LASTEXITCODE -ne 0) { throw 'Failed to integrate native Flint build steps.' }

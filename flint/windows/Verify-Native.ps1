[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory, [Parameter(Mandatory)][string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$archives = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.zip' -File)
$installers = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.exe' -File)
if ($archives.Count -ne 1 -or $installers.Count -ne 1) { throw 'Expected one x64 browser ZIP and one installer.' }
$output = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
$scratch = [IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) ('flint-verify-' + [Guid]::NewGuid().ToString('N')))).FullName
Expand-Archive -LiteralPath $archives[0].FullName -DestinationPath (Join-Path $scratch 'browser')
$binaries = @(Get-ChildItem -LiteralPath (Join-Path $scratch 'browser') -Filter chrome.exe -File -Recurse)
if ($binaries.Count -ne 1) { throw 'The package must contain one native chrome.exe.' }
$browser = $binaries[0]
$info = $browser.VersionInfo
if ($info.ProductName -notmatch 'Flint') { throw "Unexpected native product identity: $($info.ProductName)" }
if (!(Test-Path -LiteralPath (Join-Path $browser.DirectoryName 'chrome.dll') -PathType Leaf)) { throw 'Missing Chromium engine.' }
$art = Join-Path $PSScriptRoot '..\native\brand\mark-32.png'
python (Join-Path $PSScriptRoot 'verify-native-icon.py') $art $browser.FullName (Join-Path $browser.DirectoryName 'chrome.dll')
if ($LASTEXITCODE -ne 0) { throw 'The native browser icon differs from Flint artwork.' }

# Exercise the packaged binary with extensions disabled. The browser's own
# new-tab entry point must still deliver Flint's HTML from compiled resources.
$profile = Join-Path $scratch 'profile'
$domFile = Join-Path $scratch 'new-tab.html'
$errorFile = Join-Path $scratch 'browser.log'
$arguments = @('--headless', '--disable-extensions', '--force-first-run', '--no-default-browser-check',
    '--allow-chrome-scheme-url', '--dump-dom', '--virtual-time-budget=2000', "`"--user-data-dir=$profile`"", 'chrome://newtab/')
$process = Start-Process -FilePath $browser.FullName -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $domFile -RedirectStandardError $errorFile
if (!$process.WaitForExit(60000)) { $process.Kill($true); throw 'Native new-tab smoke test timed out.' }
$dom = Get-Content -LiteralPath $domFile -Raw
if ($process.ExitCode -ne 0 -or !$dom -or $dom -notmatch 'Pinned sites' -or $dom -notmatch 'Flint' -or $dom -notmatch 'Search DuckDuckGo or enter a URL') {
    Get-Content -LiteralPath $errorFile -Tail 20
    if ($dom) { Write-Host $dom.Substring(0, [Math]::Min(1000, $dom.Length)) }
    throw "Native chrome://newtab/ did not render Flint with the DuckDuckGo default and extensions disabled (exit $($process.ExitCode))."
}
node (Join-Path $PSScriptRoot 'verify-tracking.mjs') $browser.FullName $scratch
if ($LASTEXITCODE -ne 0) { throw 'Native tracking protection did not pass its network checks.' }

$zip = Join-Path $output 'Flint-Windows-x64.zip'
$setup = Join-Path $output 'Flint-Setup-x64.exe'
Copy-Item -LiteralPath $archives[0].FullName -Destination $zip
Copy-Item -LiteralPath $installers[0].FullName -Destination $setup
$hashes = foreach ($path in $zip, $setup) {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(), [IO.Path]::GetFileName($path)
}
$hashes | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
Write-Output "$($info.ProductName) $($info.ProductVersion) rendered its native new tab."
$hashes

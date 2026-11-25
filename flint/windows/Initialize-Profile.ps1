[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $UserDataDir
)

$ErrorActionPreference = 'Stop'
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($UserDataDir)
if ([IO.Directory]::Exists($destination)) {
    if ([IO.File]::Exists((Join-Path $destination 'Local State')) -or
        [IO.File]::Exists((Join-Path $destination 'Default\Preferences'))) {
        return
    }
    throw "An unrecognized directory already exists at '$destination'. Choose a new location for the Flint profile."
}

# Per-profile defaults are imported by Chromium from initial_preferences on
# first run. Memory Saver belongs to the separate browser-wide Local State.
$localState = @{ performance_tuning = @{ high_efficiency_mode = @{ state = 2; aggressiveness = 1 } } }

# Publish the fresh directory atomically; Chromium owns it from here on.
$parent = [IO.Path]::GetDirectoryName($destination)
$staging = Join-Path $parent ('.flint-profile-' + [Guid]::NewGuid().ToString('N'))
$stateFile = Join-Path $staging 'Local State'
$encoding = New-Object System.Text.UTF8Encoding($false)
try {
    [void][IO.Directory]::CreateDirectory($staging)
    [IO.File]::WriteAllText($stateFile, ($localState | ConvertTo-Json -Depth 8), $encoding)
    try {
        [IO.Directory]::Move($staging, $destination)
    } catch [IO.IOException] {
        if (-not [IO.File]::Exists((Join-Path $destination 'Local State'))) {
            throw
        }
    }
} finally {
    if ([IO.Directory]::Exists($staging)) {
        [IO.File]::Delete($stateFile)
        [IO.Directory]::Delete($staging)
    }
}

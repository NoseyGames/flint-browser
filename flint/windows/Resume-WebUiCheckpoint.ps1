# Reuse the source and Ninja objects from the stage before the WebUI lint failure.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Validate', 'Restore')][string]$Mode)

$ErrorActionPreference = 'Stop'
$checkout = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$base = 'f5396ed004728e99d40551e09feffa2c1aae288d'
$branch = 'codex/flint-native'
$repo = 'NoseyGames/flint-browser'
$newTabFiles = 'newtab.css', 'newtab.html', 'newtab.ts', 'flint-32.png', 'flint-48.png', 'obsidian.webp'
$nativeInputs = @($newTabFiles | ForEach-Object { "flint/native/newtab/$_" }) + 'flint/windows/initial_preferences'
if ($env:GITHUB_REPOSITORY -ne $repo -or $env:GITHUB_REF -cne "refs/heads/$branch" -or
    $env:GITHUB_EVENT_NAME -ne 'workflow_dispatch') {
    throw "Checkpoint recovery requires a manual build of $repo on $branch."
}

if ($Mode -eq 'Validate') {
    $head = git -C $checkout rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -cne $env:GITHUB_SHA) { throw 'Caller checkout does not match the dispatched commit.' }
    git -C $checkout merge-base --is-ancestor $base $head
    if ($LASTEXITCODE -ne 0) { throw "Checkpoint commit $base must be an ancestor of $head." }
    $ciFiles = @(
        '.github/workflows/flint-windows.yml', '.github/workflows/flint-stage.yml',
        '.github/workflows/ci.yml', 'README.md', 'flint/windows/Resume-WebUiCheckpoint.ps1',
        'flint/windows/Verify-Native.ps1', 'flint/windows/verify-tracking.mjs',
        'flint/windows/verify-native-icon.py'
    )
    $changes = @(git -C $checkout diff --name-status --no-renames $base $head --)
    if ($LASTEXITCODE -ne 0) { throw 'Could not compare the checkpoint and dispatched source.' }
    foreach ($change in $changes) {
        $status, $file = $change -split "`t", 2
        if ($file -cin $ciFiles -and $status -cin 'A', 'M') { continue }
        if ($file -cin $nativeInputs -and $status -ceq 'M') { continue }
        throw "Checkpoint cannot refresh '$change'. Dispatch a clean build."
    }
    $headers = @{ Authorization = "Bearer $env:GH_TOKEN"; Accept = 'application/vnd.github+json' }
    $artifact = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/actions/artifacts/15091017596" -Headers $headers
    $run = $artifact.workflow_run
    if ($artifact.id -ne 15091017596 -or $artifact.name -cne 'build-artifact' -or $artifact.expired -ne $false -or
        $artifact.size_in_bytes -ne 15664329463 -or
        $artifact.digest -cne 'sha256:a010bdc93170f519cea06f8f38cc6a526449353370deeec58519e1f05cc0df5c' -or
        $run.id -ne 45565539172 -or $run.repository_id -ne 1468880918 -or $run.head_repository_id -ne 1468880918 -or
        $run.head_sha -cne $base -or $run.head_branch -cne $branch) {
        throw 'The retained checkpoint does not match its pinned origin, size, and digest.'
    }
    Write-Host "Validated checkpoint $($artifact.id) from $base for $head."
    return
}

$build = 'C:\ungoogled-chromium-windows\build'
$archive = Join-Path $build 'artifacts.zip'
$source = Join-Path $build 'src'
if (!(Test-Path -LiteralPath $archive -PathType Leaf) -or (Test-Path -LiteralPath $source)) {
    throw "Expected the downloaded artifacts.zip and an empty source destination in $build."
}
& 7z x $archive "-o$build" -y -bso0
if ($LASTEXITCODE -ne 0) { throw '7-Zip failed to restore the verified checkpoint.' }
Remove-Item -LiteralPath $archive
foreach ($path in 'BUILD.gn', 'out/Default/build.ninja', 'out/Default/.ninja_log', 'out/Default/gn.exe',
                  'third_party/ninja/ninja.exe', 'chrome/app/flint_initial_preferences') {
    if (!(Test-Path -LiteralPath (Join-Path $source $path) -PathType Leaf)) { throw "Checkpoint is missing $path." }
}

# build.py skips source preparation when BUILD.gn is present in a CI build.
& python (Join-Path $PSScriptRoot 'Apply-NativeAssets.py') --source $source
if ($LASTEXITCODE -ne 0) { throw 'Failed to refresh the Chromium source overlay.' }
$newTab = Join-Path $source 'chrome/browser/resources/new_tab_page_third_party'
foreach ($inputPath in $nativeInputs) {
    $from = Join-Path $checkout $inputPath
    $to = if ($inputPath -ceq 'flint/windows/initial_preferences') {
        Join-Path $source 'chrome/app/flint_initial_preferences'
    } else {
        Join-Path $newTab (Split-Path $inputPath -Leaf)
    }
    if ((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $to).Hash) {
        throw "Restored Chromium input differs from the dispatched commit: $inputPath"
    }
}
$webuiTools = Join-Path $source 'ui/webui/resources/tools'
Push-Location (Join-Path $source 'out/Default')
try {
    & python (Join-Path $webuiTools 'stylelint.py') --config (Join-Path $webuiTools 'stylelint.config_base.mjs') `
        --in_folder $newTab --out_file (Join-Path $env:RUNNER_TEMP 'flint-newtab.stylelint') --in_files newtab.css
    if ($LASTEXITCODE -ne 0) { throw 'Chromium stylelint rejected the refreshed new tab stylesheet.' }
} finally {
    Pop-Location
}
Write-Host 'Checkpoint restored. Overlay hashes and Chromium WebUI stylelint passed.'

param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Sabado',
    [string]$Editor = 'C:\Program Files\Unity\Hub\Editor\6000.3.11f1'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'fetch-deps.ps1')
& (Join-Path $PSScriptRoot 'fetch-release-deps.ps1')
& (Join-Path $PSScriptRoot 'build.ps1') -Game $Game -Editor $Editor
& (Join-Path $root '.venv\Scripts\python.exe') (Join-Path $PSScriptRoot 'release.py')
if ($LASTEXITCODE -ne 0) { throw 'Release packaging failed.' }

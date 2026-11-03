$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $root 'vendor'
New-Item -ItemType Directory -Force -Path $vendor | Out-Null
$archive = Join-Path $vendor 'BepInEx_win_x64_5.4.23.6.zip'
$expected = '6c57a714a892efb4e9e1fef63d608a3391f30ec984031c465404e4ee381a0755'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri 'https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.6/BepInEx_win_x64_5.4.23.6.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'BepInEx archive SHA-256 mismatch; refusing to extract.'
}
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $vendor 'BepInEx') -Force
Write-Output 'Verified BepInEx 5.4.23.6 (Mono x64).'

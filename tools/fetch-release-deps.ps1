$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$archive = Join-Path $root 'vendor\UnityDoorstop-4.6.0-source.tar.gz'
[IO.Directory]::CreateDirectory((Split-Path -Parent $archive)) | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri 'https://codeload.github.com/NeighTools/UnityDoorstop/tar.gz/1c3ece1f1e6c20f4aa74d5402baabf8a0098d282' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'ba5bc290e6145e0b33e1b3cfd4de18698144f6dbe031a2278996cfc73036a3e6') {
    throw 'UnityDoorstop source archive SHA-256 mismatch.'
}
Write-Output 'Verified UnityDoorstop 4.6.0 source archive.'

param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Sabado',
    [string]$Editor = 'C:\Program Files\Unity\Hub\Editor\6000.3.11f1'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$managed = Join-Path $Game 'Sabado Day One_Data\Managed'
$core = Join-Path $root 'vendor\BepInEx\BepInEx\core'
$out = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$mono = Join-Path $Editor 'Editor\Data\MonoBleedingEdge\bin\mono.exe'
$compiler = Join-Path $Editor 'Editor\Data\MonoBleedingEdge\lib\mono\4.5\csc.exe'
foreach ($path in @($mono, $compiler, (Join-Path $core 'BepInEx.dll'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required build tool missing: $path" }
}
$arguments = @('-nologo', '-target:library', '-optimize+', '-deterministic+', '-nostdlib+', ('-out:"' + (Join-Path $out 'SabadoKorean.dll') + '"'))
$arguments += Get-ChildItem -LiteralPath $managed -Filter '*.dll' | ForEach-Object { '-r:"' + $_.FullName + '"' }
$arguments += @('-r:"' + (Join-Path $core 'BepInEx.dll') + '"', '-r:"' + (Join-Path $core '0Harmony.dll') + '"')
$arguments += '"' + (Join-Path $root 'src\KoreanPatch.cs') + '"'
$arguments += '"' + (Join-Path $root 'src\DisplayText.cs') + '"'
$arguments += '"' + (Join-Path $root 'src\TextureTranslations.cs') + '"'
$responseFile = Join-Path $out 'compile.rsp'
[IO.File]::WriteAllLines($responseFile, $arguments, [Text.UTF8Encoding]::new($false))
& $mono $compiler -noconfig ('@' + $responseFile)
if ($LASTEXITCODE -ne 0) { throw 'Plugin compilation failed.' }
Write-Output (Join-Path $out 'SabadoKorean.dll')

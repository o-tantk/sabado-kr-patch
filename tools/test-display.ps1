param([string]$Editor = 'C:\Program Files\Unity\Hub\Editor\6000.3.11f1')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mono = Join-Path $Editor 'Editor\Data\MonoBleedingEdge\bin\mono.exe'
$compiler = Join-Path $Editor 'Editor\Data\MonoBleedingEdge\lib\mono\4.5\csc.exe'
$out = Join-Path $root 'build\DisplayTextTests.exe'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
& $mono $compiler -nologo ('-out:' + $out) (Join-Path $root 'src\DisplayText.cs') (Join-Path $root 'tests\DisplayTextTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Display translation test compilation failed.' }
& $mono $out
if ($LASTEXITCODE -ne 0) { throw 'Display translation tests failed.' }

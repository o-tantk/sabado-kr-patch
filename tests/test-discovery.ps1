$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'installer\discovery.ps1')
$testRoot = Join-Path $root ('local\tests\discovery-' + [Guid]::NewGuid().ToString('N'))
$script:passed = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Put([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
function Game([string]$Library, [string]$Name = 'Sabado') {
    $path = Join-Path $Library ('steamapps\common\' + $Name)
    Put (Join-Path $path 'Sabado Day One.exe') 'test fixture, not executable'
    $path
}
function Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Output "PASS $Name"
}

Case 'case, slash and trailing separator variants represent one Steam directory' {
    $steam = Join-Path $testRoot 'Steam'
    $game = Game $steam
    $variants = @($steam.ToLowerInvariant().Replace('\', '/'), $steam, ($steam + '\'))
    Assert (@(Get-UniqueSteamPaths $variants).Count -eq 1) 'Steam directory duplicated'
    Assert ((Find-Sabado $variants) -eq $game) 'Did not auto-select the installed game'
}
Case 'registered secondary library and non-default game folder are found' {
    $steam = Join-Path $testRoot 'MainClient'
    $library = Join-Path $testRoot '한글 라이브러리 & (Steam)'
    $game = Game $library 'Sabado Custom'
    Put (Join-Path $steam 'steamapps\libraryfolders.vdf') ('"libraryfolders" { "1" { "path" "' + $library.Replace('\', '\\') + '" } }')
    Put (Join-Path $library 'steamapps\appmanifest_4986750.acf') '"AppState" { "appid" "4986750" "installdir" "Sabado Custom" }'
    Assert ((Find-Sabado @($steam)) -eq $game) 'Secondary library not found'
}
Case 'stale library does not hide a later valid library' {
    $steam = Join-Path $testRoot 'StaleClient'
    $library = Join-Path $testRoot 'ValidLibrary'
    $game = Game $library
    $missing = Join-Path $testRoot 'MissingLibrary'
    Put (Join-Path $steam 'steamapps\libraryfolders.vdf') ('"path" "' + $missing.Replace('\', '\\') + '" "path" "' + $library.Replace('\', '\\') + '"')
    Assert ((Find-Sabado @($steam)) -eq $game) 'Stale library blocked discovery'
}
Case 'two real installations still offer an automatic choice' {
    $steam = Join-Path $testRoot 'FirstInstall'
    $other = Join-Path $testRoot 'SecondInstall'
    $game = Game $steam
    Game $other | Out-Null
    $found = Find-Sabado @($steam, $other)
    Assert ($found -is [string] -and $found -eq $game) 'Multiple installations forced manual selection'
}
Case 'missing executable returns no automatic choice' {
    $steam = Join-Path $testRoot 'Uninstalled'
    Put (Join-Path $steam 'steamapps\appmanifest_4986750.acf') '"installdir" "Sabado"'
    Assert ($null -eq (Find-Sabado @($steam))) 'Uninstalled game selected'
}
Case 'no Steam installation falls back to manual selection' {
    Assert ($null -eq (Find-Sabado @())) 'Empty roots unexpectedly selected a game'
}
Write-Output "$script:passed Steam discovery scenarios passed (PowerShell $($PSVersionTable.PSVersion))."

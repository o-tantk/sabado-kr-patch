$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'installer\engine.ps1')
$script:testRoot = Join-Path $root ('local\tests\installer-' + [Guid]::NewGuid().ToString('N'))
$script:passed = 0
$script:RealCopy = ${function:Copy-PatchFile}

function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock]$Body) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true; $script:lastError = $_.Exception.Message }
    Assert $failed 'Expected operation to fail'
}
function Put([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Fixture {
    $script:base = Join-Path $script:testRoot ([Guid]::NewGuid().ToString('N') + ' 한글 & (배포)')
    $script:game = Join-Path $script:base 'game'
    $script:package = Join-Path $script:base 'package'
    $script:backups = Join-Path $script:base 'backups'
    Put (Join-Path $script:game 'game.bin') 'original game'
    $script:plugin = 'BepInEx/plugins/SabadoKorean/SabadoKorean.dll'
    $script:files = @('.doorstop_version', 'doorstop_config.ini', 'winhttp.dll', 'BepInEx/core/BepInEx.dll',
        $script:plugin, 'BepInEx/plugins/SabadoKorean/strings.tsv', 'BepInEx/plugins/SabadoKorean/ui.tsv',
        'BepInEx/plugins/SabadoKorean/textures.tsv', 'BepInEx/plugins/SabadoKorean/textures/second-floor-note.png')
    foreach ($relative in $script:files) { Put (Join-Path $script:package ('payload/' + $relative)) ('payload ' + $relative) }
    Save-Bundle
}
function Save-Bundle {
    $hashes = [ordered]@{}
    foreach ($relative in $script:files) { $hashes[$relative] = Get-PatchHash (Get-ChildPath (Join-Path $script:package 'payload') $relative) }
    Write-PatchJson (Join-Path $script:package 'package.json') @{ schema = 1; version = '0.1.4'; files = $hashes;
        target = @{ steam_build_id = 'test'; files = @{ 'game.bin' = (Get-PatchHash (Join-Path $script:game 'game.bin')) } } }
}
function Install-Test { Invoke-KoreanPatch Install $script:game $script:package $script:backups | Out-Null }
function Remove-Test { Invoke-KoreanPatch Remove $script:game $script:package $script:backups | Out-Null }
function Snapshot([string]$Directory) {
    $items = foreach ($file in Get-ChildItem -LiteralPath $Directory -Recurse -File -Force) {
        $file.FullName.Substring($Directory.Length) + ':' + (Get-PatchHash $file.FullName)
    }
    ($items | Sort-Object) -join "`n"
}
function Case([string]$Name, [scriptblock]$Body) {
    New-Fixture
    & $Body
    $script:passed++
    Write-Output "PASS $Name"
}

Case 'install, update, remove, reinstall in Unicode path; preserve unrelated files' {
    Put (Join-Path $script:game 'doorstop_config.ini') 'original config'
    Install-Test
    Put (Join-Path $script:game 'BepInEx/LogOutput.log') 'keep log'
    Put (Join-Path $script:game 'user-save.dat') 'keep save'
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'plugin v2'
    Save-Bundle
    Install-Test
    Remove-Test
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'doorstop_config.ini') -Raw) -eq 'original config') 'Original config lost'
    Assert ([IO.File]::Exists((Join-Path $script:game 'user-save.dat'))) 'Unrelated save lost'
    Assert ([IO.File]::Exists((Join-Path $script:game 'BepInEx/LogOutput.log'))) 'Log lost'
    Assert (-not [IO.File]::Exists((Join-Path $script:game 'winhttp.dll'))) 'Loader remains'
    Assert (-not [IO.File]::Exists((Get-ChildPath $script:game $script:files[-1]))) 'Texture remains'
    Install-Test
}
Case 'unsupported game makes no changes' {
    Put (Join-Path $script:game 'game.bin') 'different version'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Game changed'
}
Case 'corrupt payload makes no changes' {
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'corrupt'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Game changed'
}
Case 'other mod loader is not overwritten' {
    Put (Join-Path $script:game 'winhttp.dll') 'other loader'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Other loader changed'
}
Case 'modified installed file prevents update and removal' {
    Install-Test
    Put (Join-Path $script:game 'winhttp.dll') 'user modification'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Expect-Failure { Remove-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Modified file changed'
}
Case 'missing original backup prevents all removal writes' {
    Put (Join-Path $script:game 'doorstop_config.ini') 'original config'
    Install-Test
    $manifest = Read-InstallManifest $script:game
    [IO.File]::Delete($manifest.files.'doorstop_config.ini'.original.backup)
    $before = Snapshot $script:game
    Expect-Failure { Remove-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Partial removal'
}
Case 'path traversal and non-patch manifest entries rejected' {
    foreach ($path in @('../outside', '/outside', 'C:/outside', 'foo/../outside', 'BepInEx/core/../../game.bin', 'file:stream', 'foo\bar')) {
        Expect-Failure { Get-ChildPath $script:game $path }
    }
    Install-Test
    $manifest = Read-InstallManifest $script:game
    $manifest.files | Add-Member -NotePropertyName 'game.bin' -NotePropertyValue $manifest.files.'winhttp.dll'
    Write-PatchJson (Join-Path $script:game $script:ManifestName) $manifest
    $before = Snapshot $script:game
    Expect-Failure { Remove-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Unrelated file touched'
}
Case 'game file cannot be smuggled into package inventory' {
    $script:files += 'game.bin'
    Put (Join-Path $script:package 'payload/game.bin') 'malicious replacement'
    Save-Bundle
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Original overwritten'
}
Case 'install write failure rolls back all target bytes' {
    $script:failurePath = Get-ChildPath $script:game $script:plugin
    $script:failOnce = $true
    function Copy-PatchFile([string]$Source, [string]$Destination) {
        if ($Destination -eq $script:failurePath -and $script:failOnce) { $script:failOnce = $false; throw 'simulated write error' }
        & $script:RealCopy $Source $Destination
    }
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert (-not $script:failOnce) 'Fault was not injected'
    Assert ((Snapshot $script:game) -eq $before) 'Rollback changed target bytes'
}
Case 'failed update restores earlier manifest and plugin' {
    Install-Test
    $before = Snapshot $script:game
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'plugin v2'
    Save-Bundle
    $script:failurePath = Join-Path $script:game $script:ManifestName
    $script:failOnce = $true
    function Copy-PatchFile([string]$Source, [string]$Destination) {
        if ($Destination -eq $script:failurePath -and $script:failOnce) { $script:failOnce = $false; throw 'simulated manifest error' }
        & $script:RealCopy $Source $Destination
    }
    Expect-Failure { Install-Test }
    Assert (-not $script:failOnce) 'Fault was not injected'
    Assert ((Snapshot $script:game) -eq $before) ('Old installation not restored: ' + $script:lastError)
}
Case 'failed removal restores installed state' {
    Put (Join-Path $script:game 'doorstop_config.ini') 'original config'
    Install-Test
    $before = Snapshot $script:game
    $script:failurePath = Join-Path $script:game 'doorstop_config.ini'
    $script:failOnce = $true
    function Copy-PatchFile([string]$Source, [string]$Destination) {
        if ($Destination -eq $script:failurePath -and $script:failOnce) { $script:failOnce = $false; throw 'simulated removal error' }
        & $script:RealCopy $Source $Destination
    }
    Expect-Failure { Remove-Test }
    Assert (-not $script:failOnce) 'Fault was not injected'
    Assert ((Snapshot $script:game) -eq $before) 'Installed state not restored'
}
Case 'interrupted transaction can be recovered and repeated safely' {
    $changes = [ordered]@{ 'winhttp.dll' = (Join-Path $script:package 'payload/winhttp.dll');
        'doorstop_config.ini' = (Join-Path $script:package 'payload/doorstop_config.ini') }
    $backup = New-PatchBackup $script:game $script:backups
    $before = Snapshot $script:game
    function Copy-PatchFile([string]$Source, [string]$Destination) {
        if ($Destination -eq (Join-Path $script:game 'doorstop_config.ini')) { throw 'simulated interruption' }
        & $script:RealCopy $Source $Destination
    }
    function Restore-PatchTransaction([string]$Game) { throw 'simulated unavailable rollback' }
    Expect-Failure { Invoke-PatchTransaction $script:game $backup $changes }
    Assert ([IO.File]::Exists((Join-Path $script:game $script:PendingName))) 'Journal missing'
    Expect-Failure { Install-Test }
    # Remove the local fault hooks to use the real recovery implementation.
    Remove-Item Function:Copy-PatchFile
    Remove-Item Function:Restore-PatchTransaction
    Invoke-KoreanPatch Recover $script:game $script:package $script:backups | Out-Null
    Assert ((Snapshot $script:game) -eq $before) 'Recovery failed'
    Invoke-KoreanPatch Recover $script:game $script:package $script:backups | Out-Null
}
Case 'Python manifest originals migrate to persistent release backup' {
    Put (Join-Path $script:game 'doorstop_config.ini') 'original config'
    Install-Test
    $manifest = Read-InstallManifest $script:game
    $legacyBackup = $manifest.files.'doorstop_config.ini'.original.backup
    $manifest.PSObject.Properties.Remove('version')
    Write-PatchJson (Join-Path $script:game $script:ManifestName) $manifest
    Install-Test
    [IO.File]::Delete($legacyBackup)
    Remove-Test
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'doorstop_config.ini') -Raw) -eq 'original config') 'Legacy original not migrated'
}
Case 'removal works after game update and without payload' {
    Install-Test
    Put (Join-Path $script:game 'game.bin') 'new game version'
    Invoke-KoreanPatch Remove $script:game (Join-Path $script:base 'missing-package') $script:backups | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'game.bin') -Raw) -eq 'new game version') 'Updated game modified'
}
Case 'backup inside game is rejected' {
    $before = Snapshot $script:game
    Expect-Failure { Invoke-KoreanPatch Install $script:game $script:package (Join-Path $script:game 'backups') }
    Assert ((Snapshot $script:game) -eq $before) 'Game changed'
}
Case 'running game guard prevents changes' {
    function Assert-GameStopped { throw 'simulated running game' }
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Game changed'
}
Write-Output "$script:passed installer scenarios passed (Windows PowerShell $($PSVersionTable.PSVersion))."

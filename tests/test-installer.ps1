$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'installer\engine.ps1')
$script:testRoot = Join-Path $root ('local\tests\installer-' + [Guid]::NewGuid().ToString('N'))
$script:passed = 0
$script:RealCopy = ${function:Copy-PatchBytes}
$script:RealComplete = ${function:Complete-PatchCopy}
$script:RealRemove = ${function:Remove-PatchFile}
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
    $script:legacyRoot = Join-Path $script:base 'AppData\Local\SabadoKorean\Backups\B0052F88A6B12350'
    Put (Join-Path $script:game 'game.bin') 'original game'
    $script:plugin = 'BepInEx/plugins/SabadoKorean/SabadoKorean.dll'
    $script:files = @('.doorstop_version', 'doorstop_config.ini', 'winhttp.dll', 'BepInEx/core/BepInEx.dll',
        $script:plugin, 'BepInEx/plugins/SabadoKorean/strings.tsv', 'BepInEx/plugins/SabadoKorean/ui.tsv',
        'BepInEx/plugins/SabadoKorean/textures.tsv', 'BepInEx/plugins/SabadoKorean/textures/second-floor-note.png')
    foreach ($relative in $script:files) { Put (Join-Path $script:package ('payload/' + $relative)) ('payload ' + $relative) }
    Save-Bundle
}
function Get-LegacyBackupRoot([string]$Game) { $script:legacyRoot }
function Save-Bundle {
    $hashes = [ordered]@{}
    foreach ($relative in $script:files) { $hashes[$relative] = Get-PatchHash (Get-ChildPath (Join-Path $script:package 'payload') $relative) }
    Write-PatchJson (Join-Path $script:package 'package.json') @{ schema = 1; version = '0.1.6'; files = $hashes;
        target = @{ steam_build_id = 'test'; files = @{ 'game.bin' = (Get-PatchHash (Join-Path $script:game 'game.bin')) } } }
}
function Install-Test { Invoke-KoreanPatch Install $script:game $script:package | Out-Null }
function Recover-Test { Invoke-KoreanPatch Recover $script:game $script:package | Out-Null }
function Archives { @(Get-ChildItem -LiteralPath $script:package -Filter 'SabadoKorean-backup-*.zip' -File) }
function Snapshot([string]$Directory) {
    $items = foreach ($file in Get-ChildItem -LiteralPath $Directory -Recurse -File -Force) {
        $file.FullName.Substring($Directory.Length) + ':' + (Get-PatchHash $file.FullName)
    }
    ($items | Sort-Object) -join "`n"
}
function Add-LegacyBackup([switch]$Original) {
    $session = Join-Path $script:legacyRoot '20261104T0102031234567Z-12345678'
    Write-PatchJson (Join-Path $session 'recovery.json') @{owner=$script:Owner;game=$script:game;before=@{}}
    $manifest = Read-InstallManifest $script:game
    if ($Original) {
        $saved = Join-Path $session 'files/doorstop_config.ini'
        Put $saved 'original config'
        $manifest.files.'doorstop_config.ini'.original = [pscustomobject]@{exists=$true;backup=$saved;sha256=(Get-PatchHash $saved)}
    }
    $manifest | Add-Member -NotePropertyName last_backup -NotePropertyValue $session -Force
    Write-PatchJson (Join-Path $script:game $script:ManifestName) $manifest
    $session
}
function Case([string]$Name, [scriptblock]$Body) {
    New-Fixture
    & $Body
    $script:passed++
    Write-Output "PASS $Name"
}

Case 'install, update, unified recovery and reinstall preserve game and saves' {
    Install-Test
    Put (Join-Path $script:game 'BepInEx/LogOutput.log') 'keep log'
    Put (Join-Path $script:game 'user-save.dat') 'keep save'
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'plugin v2'
    Save-Bundle
    Install-Test
    Assert (@(Archives).Count -eq 0) 'Successful update left backup ZIP'
    Recover-Test
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'game.bin') -Raw) -eq 'original game') 'Original changed'
    Assert ([IO.File]::Exists((Join-Path $script:game 'user-save.dat'))) 'Save lost'
    Assert ([IO.File]::Exists((Join-Path $script:game 'BepInEx/LogOutput.log'))) 'Unrelated log lost'
    Assert (-not [IO.File]::Exists((Join-Path $script:game 'winhttp.dll'))) 'Loader remains'
    Assert (@(Archives).Count -eq 0) 'Successful recovery left backup ZIP'
    Install-Test
}
Case 'backup ZIP exists beside batch files during work and disappears on success' {
    $script:observed = $false
    function Copy-PatchBytes([byte[]]$Bytes, [string]$Destination) {
        if ($Destination -eq (Join-Path $script:game 'winhttp.dll')) {
            $archives = @(Archives)
            Assert ($archives.Count -eq 1) 'Expected one working backup'
            Assert ($archives[0].DirectoryName -eq $script:package) 'Backup is not beside launchers'
            $script:observed = $true
        }
        & $script:RealCopy $Bytes $Destination
    }
    Install-Test
    Assert $script:observed 'Backup not observed'
    Assert (@(Archives).Count -eq 0) 'Backup remains'
    Assert (-not (Test-Path -LiteralPath $script:legacyRoot)) 'Created AppData backup'
}
Case 'pre-existing unowned config is not overwritten or backed up permanently' {
    Put (Join-Path $script:game 'doorstop_config.ini') 'original config'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Original config changed'
    Assert (@(Archives).Count -eq 0) 'Preflight created backup'
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
Case 'modified installed file prevents update and recovery' {
    Install-Test
    Put (Join-Path $script:game 'winhttp.dll') 'user modification'
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Expect-Failure { Recover-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Modified file changed'
}
Case 'path traversal and non-patch manifest entries rejected' {
    foreach ($path in @('../outside', '/outside', 'C:/outside', 'foo/../outside', 'file:stream', 'foo\bar')) {
        Expect-Failure { Get-ChildPath $script:game $path }
    }
    Install-Test
    $manifest = Read-InstallManifest $script:game
    $manifest.files | Add-Member -NotePropertyName 'game.bin' -NotePropertyValue $manifest.files.'winhttp.dll'
    Write-PatchJson (Join-Path $script:game $script:ManifestName) $manifest
    $before = Snapshot $script:game
    Expect-Failure { Recover-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Unrelated file touched'
}
Case 'game assets cannot be included in the package inventory' {
    $script:files += 'game.bin'
    Put (Join-Path $script:package 'payload/game.bin') 'replacement'
    Save-Bundle
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Original overwritten'
}
Case 'failed install rolls back and retains its backup until successful recovery' {
    $script:failOnce = $true
    function Copy-PatchBytes([byte[]]$Bytes, [string]$Destination) {
        if ($Destination -eq (Get-ChildPath $script:game $script:plugin) -and $script:failOnce) { $script:failOnce = $false; throw 'simulated copy error' }
        & $script:RealCopy $Bytes $Destination
    }
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) ('Rollback failed: ' + $script:lastError)
    Assert (@(Archives).Count -eq 1) 'Failed task lost backup'
    Recover-Test
    Assert (@(Archives).Count -eq 0) 'Successful recovery retained backup'
}
Case 'failed update restores old manifest and zero-length file' {
    Put (Join-Path $script:package 'payload/BepInEx/plugins/SabadoKorean/strings.tsv') ''
    Save-Bundle
    Install-Test
    $before = Snapshot $script:game
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'plugin v2'
    Save-Bundle
    $script:failOnce = $true
    function Copy-PatchBytes([byte[]]$Bytes, [string]$Destination) {
        if ($Destination -eq (Join-Path $script:game $script:ManifestName) -and $script:failOnce) { $script:failOnce = $false; throw 'simulated manifest error' }
        & $script:RealCopy $Bytes $Destination
    }
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) ('Old installation not restored: ' + $script:lastError)
    Assert (@(Archives).Count -eq 1) 'Failure backup missing'
    Install-Test
    Assert (@(Archives).Count -eq 0) 'Successful retry retained backup'
}
Case 'failed removal restores installed state and retains backup' {
    Install-Test
    $before = Snapshot $script:game
    $script:failOnce = $true
    function Remove-PatchFile([string]$Path) {
        if ($Path -eq (Get-ChildPath $script:game $script:plugin) -and $script:failOnce) { $script:failOnce = $false; throw 'simulated delete error' }
        & $script:RealRemove $Path
    }
    Expect-Failure { Recover-Test }
    Assert ((Snapshot $script:game) -eq $before) ('Removal rollback failed: ' + $script:lastError)
    Assert (@(Archives).Count -eq 1) 'Failure backup missing'
    Recover-Test
    Assert (@(Archives).Count -eq 0) 'Recovery left backup'
}
Case 'interrupted work is restored and patch removed by the same recovery action' {
    Install-Test
    Put (Get-ChildPath (Join-Path $script:package 'payload') $script:plugin) 'plugin v2'
    Save-Bundle
    function Copy-PatchBytes([byte[]]$Bytes, [string]$Destination) {
        if ($Destination -eq (Join-Path $script:game $script:ManifestName)) { throw 'simulated interruption' }
        & $script:RealCopy $Bytes $Destination
    }
    function Restore-PatchTransaction([string]$Game) { throw 'simulated unavailable rollback' }
    Expect-Failure { Install-Test }
    Assert ([IO.File]::Exists((Join-Path $script:game $script:PendingName))) 'Pending record missing'
    Assert (@(Archives).Count -eq 1) 'Crash backup missing'
    Remove-Item Function:Copy-PatchBytes
    Remove-Item Function:Restore-PatchTransaction
    Recover-Test
    Assert (-not [IO.File]::Exists((Join-Path $script:game 'winhttp.dll'))) 'Recovery did not remove patch'
    Assert (@(Archives).Count -eq 0) 'Crash backup not cleaned'
    Recover-Test
}
Case 'legacy AppData backups are removed after a successful upgrade' {
    Install-Test
    Add-LegacyBackup | Out-Null
    Install-Test
    Assert (-not (Test-Path -LiteralPath $script:legacyRoot)) 'Legacy backup remains'
    Assert (-not (Read-InstallManifest $script:game).last_backup) 'Manifest retains backup dependency'
}
Case 'legacy original is restored before its AppData backup is removed' {
    Install-Test
    Add-LegacyBackup -Original | Out-Null
    Expect-Failure { Install-Test }
    Recover-Test
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'doorstop_config.ini') -Raw) -eq 'original config') 'Legacy original lost'
    Assert (-not (Test-Path -LiteralPath $script:legacyRoot)) 'Legacy backup remains'
}
Case 'missing legacy original prevents partial recovery' {
    Install-Test
    $session = Add-LegacyBackup -Original
    [IO.File]::Delete((Join-Path $session 'files/doorstop_config.ini'))
    $before = Snapshot $script:game
    Expect-Failure { Recover-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Partial recovery changed files'
}
Case 'unrecognized files prevent destructive legacy cleanup' {
    Install-Test
    $session = Add-LegacyBackup
    Put (Join-Path $session 'keep-me.txt') 'unrelated'
    Expect-Failure { Remove-LegacyBackups $script:game }
    Assert ([IO.File]::Exists((Join-Path $session 'keep-me.txt'))) 'Unrelated file deleted'
}
Case 'recovery works after game update without payload' {
    Install-Test
    Put (Join-Path $script:game 'game.bin') 'new game version'
    $onlyRecovery = Join-Path $script:base 'recovery-only'
    [IO.Directory]::CreateDirectory($onlyRecovery) | Out-Null
    Invoke-KoreanPatch Recover $script:game $onlyRecovery | Out-Null
    Assert ((Get-Content -LiteralPath (Join-Path $script:game 'game.bin') -Raw) -eq 'new game version') 'Game updated files changed'
    Assert (@(Get-ChildItem -LiteralPath $onlyRecovery -File).Count -eq 0) 'Backup left in new launcher folder'
}
Case 'running game guard prevents changes' {
    function Assert-GameStopped { throw 'simulated running game' }
    $before = Snapshot $script:game
    Expect-Failure { Install-Test }
    Assert ((Snapshot $script:game) -eq $before) 'Game changed'
}
Case 'temporary replacement errors are retried' {
    Install-Test
    $script:remainingFailures = 2
    function Complete-PatchCopy([string]$Temporary, [string]$Destination) {
        if ($Destination -eq (Join-Path $script:game 'doorstop_config.ini') -and $script:remainingFailures -gt 0) {
            $script:remainingFailures--
            throw [IO.IOException]::new('temporary replacement error', (-2147024896 + 1175))
        }
        & $script:RealComplete $Temporary $Destination
    }
    Install-Test
    Assert ($script:remainingFailures -eq 0) 'Failure not injected'
    Assert (@(Archives).Count -eq 0) 'Successful retry left backup'
}
Write-Output "$script:passed installer scenarios passed (Windows PowerShell $($PSVersionTable.PSVersion))."

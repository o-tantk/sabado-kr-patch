# Windows PowerShell 5.1. No Python, downloaded modules, or game assemblies required.
$ErrorActionPreference = 'Stop'
$script:Owner = 'local.sabado.korean'
$script:ManifestName = 'SabadoKorean.install.json'
$script:PendingName = 'SabadoKorean.pending.json'

function Read-PatchJson([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-PatchJson([string]$Path, $Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

function Get-NormalPath([string]$Path) {
    [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-NoLink([string]$Path) {
    $part = [IO.Path]::GetFullPath($Path)
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            $item = Get-Item -LiteralPath $part -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "링크/접합점 경로는 지원하지 않습니다: $part"
            }
        }
        $part = [IO.Path]::GetDirectoryName($part)
    }
}

function Get-ChildPath([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative -match '[:\\]' -or ($Relative.Split('/') | Where-Object { $_ -in @('', '.', '..') })) {
        throw "올바르지 않은 상대 경로: $Relative"
    }
    $rootPath = Get-NormalPath $Root
    $result = [IO.Path]::GetFullPath([IO.Path]::Combine($rootPath, $Relative))
    if (-not $result.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "폴더 밖 경로는 허용되지 않습니다: $Relative"
    }
    Assert-NoLink $result
    if (Test-Path -LiteralPath $result -PathType Container) { throw "파일 위치에 폴더가 있습니다: $result" }
    $result
}

function Get-PatchHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Hash([string]$Path, [string]$Expected) {
    if ($Expected -cnotmatch '^[a-f0-9]{64}$' -or -not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-PatchHash $Path) -ne $Expected) {
        throw "파일이 없거나 변경되었습니다: $Path"
    }
}

function Complete-PatchCopy([string]$Temporary, [string]$Destination) {
    if ([IO.File]::Exists($Destination)) { [IO.File]::Replace($Temporary, $Destination, [NullString]::Value) }
    else { [IO.File]::Move($Temporary, $Destination) }
}

function Copy-PatchFile([string]$Source, [string]$Destination) {
    Assert-NoLink $Destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
    $temporary = $Destination + '.sabado-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::Copy($Source, $temporary)
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Flush($true) } finally { $stream.Dispose() }
        $originalHash = if ([IO.File]::Exists($Destination)) { Get-PatchHash $Destination } else { $null }
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try { Complete-PatchCopy $temporary $Destination; break }
            catch {
                # Windows can temporarily refuse replacement while a file is in use.
                # Retry only sharing/lock/remove-replaced errors, without changing ACLs.
                $code = $_.Exception.GetBaseException().HResult -band 0xffff
                if ($attempt -eq 5 -or $code -notin @(32, 33, 1175) -or -not [IO.File]::Exists($temporary)) {
                    throw [IO.IOException]::new("파일을 교체할 수 없습니다: $Destination`n$($_.Exception.Message)", $_.Exception)
                }
                Start-Sleep -Milliseconds 100
                $currentHash = if ([IO.File]::Exists($Destination)) { Get-PatchHash $Destination } else { $null }
                if ($currentHash -ne $originalHash) { throw "재시도 중 파일이 변경되었습니다: $Destination" }
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Assert-ManagedPath([string]$Relative, [switch]$AllowManifest) {
    $valid = $Relative -cin @('winhttp.dll', 'doorstop_config.ini', '.doorstop_version') -or
        $Relative -cmatch '^BepInEx/core/[A-Za-z0-9_.-]+\.(dll|xml)$' -or
        $Relative -cmatch '^BepInEx/plugins/SabadoKorean/(SabadoKorean\.dll|strings\.tsv|ui\.tsv|textures\.tsv)$' -or
        $Relative -cmatch '^BepInEx/plugins/SabadoKorean/textures/(second-floor-note|tutorial-calm|tutorial-interact|tutorial-push)\.png$'
    if ($AllowManifest -and $Relative -ceq $script:ManifestName) { $valid = $true }
    if (-not $valid) { throw "패치 관리 대상이 아닌 파일입니다: $Relative" }
}

function Assert-GameStopped {
    if (Get-Process -Name 'Sabado Day One' -ErrorAction SilentlyContinue) {
        throw 'Sabado를 완전히 종료한 다음 다시 실행해 주세요.'
    }
}

function Assert-GameTarget([string]$Game, $Target) {
    if (-not $Target.files -or @($Target.files.PSObject.Properties).Count -eq 0) { throw '게임 호환 정보가 비어 있습니다.' }
    foreach ($entry in $Target.files.PSObject.Properties) {
        try { Assert-Hash (Get-ChildPath $Game $entry.Name) $entry.Value }
        catch { throw "지원하는 게임 버전과 다릅니다 (Steam build $($Target.steam_build_id)). 게임 업데이트 또는 원본 변경을 확인해 주세요.`n$($entry.Name)" }
    }
}

function Read-InstallManifest([string]$Game) {
    $path = Get-ChildPath $Game $script:ManifestName
    if (-not [IO.File]::Exists($path)) { return $null }
    $manifest = Read-PatchJson $path
    if ($manifest.owner -ne $script:Owner -or -not $manifest.game -or
        (Get-NormalPath $manifest.game) -ne (Get-NormalPath $Game) -or -not $manifest.files) {
        throw '설치 기록을 확인할 수 없습니다. 게임 폴더를 이동했다면 원래 위치에서 제거해 주세요.'
    }
    foreach ($entry in $manifest.files.PSObject.Properties) {
        Assert-ManagedPath $entry.Name
        Get-ChildPath $Game $entry.Name | Out-Null
        if (-not $entry.Value.original -or $entry.Value.installed_sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw '설치 기록이 손상되었습니다.'
        }
    }
    $manifest
}

function Assert-InstalledFiles([string]$Game, $Manifest, [switch]$AllowMissing) {
    if (-not $Manifest) { return }
    foreach ($entry in $Manifest.files.PSObject.Properties) {
        $destination = Get-ChildPath $Game $entry.Name
        if (-not $AllowMissing -or [IO.File]::Exists($destination)) {
            Assert-Hash $destination $entry.Value.installed_sha256
        }
        $original = $entry.Value.original
        if ($original.exists) {
            if (-not [IO.Path]::IsPathRooted($original.backup)) { throw '원본 백업 경로가 올바르지 않습니다.' }
            Assert-NoLink $original.backup
            Assert-Hash $original.backup $original.sha256
        }
    }
}

function Get-DefaultBackupRoot([string]$Game) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $id = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes((Get-NormalPath $Game).ToLowerInvariant()))).Replace('-', '').Substring(0, 16) }
    finally { $hasher.Dispose() }
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "SabadoKorean\Backups\$id"
}

function New-PatchBackup([string]$Game, [string]$BackupRoot) {
    if (-not $BackupRoot) { $BackupRoot = Get-DefaultBackupRoot $Game }
    $rootPath = Get-NormalPath $BackupRoot
    $gamePath = Get-NormalPath $Game
    if ($rootPath -eq $gamePath -or $rootPath.StartsWith($gamePath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '백업은 게임 폴더 밖에 보관해야 합니다.'
    }
    Assert-NoLink $rootPath
    $backup = Join-Path $rootPath ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $backup
}

function Restore-PatchTransaction([string]$Game) {
    $pending = Get-ChildPath $Game $script:PendingName
    if (-not [IO.File]::Exists($pending)) { return '복구할 중단 작업이 없습니다.' }
    Assert-GameStopped
    $journal = Read-PatchJson $pending
    if ($journal.owner -ne $script:Owner -or -not $journal.game -or
        (Get-NormalPath $journal.game) -ne (Get-NormalPath $Game) -or -not $journal.before) { throw '복구 기록이 올바르지 않습니다.' }
    # Validate every original and current file before restoring anything. Recovery is repeatable.
    foreach ($entry in $journal.before.PSObject.Properties) {
        Assert-ManagedPath $entry.Name -AllowManifest
        $destination = Get-ChildPath $Game $entry.Name
        $record = $entry.Value
        if ($record.exists) {
            if (-not [IO.Path]::IsPathRooted($record.backup)) { throw '복구 백업 경로가 올바르지 않습니다.' }
            Assert-NoLink $record.backup
            Assert-Hash $record.backup $record.sha256
        }
        $current = if ([IO.File]::Exists($destination)) { Get-PatchHash $destination } else { $null }
        $before = if ($record.exists) { $record.sha256 } else { $null }
        if ($current -ne $before -and $current -ne $record.after_sha256) {
            throw "중단 후 파일이 별도로 변경되어 자동 복구할 수 없습니다: $($entry.Name)"
        }
    }
    foreach ($entry in $journal.before.PSObject.Properties) {
        $destination = Get-ChildPath $Game $entry.Name
        if ($entry.Value.exists) { Copy-PatchFile $entry.Value.backup $destination }
        elseif ([IO.File]::Exists($destination)) { [IO.File]::Delete($destination) }
    }
    [IO.File]::Delete($pending)
    '중단된 작업 이전 상태로 복구했습니다. 설치 또는 제거를 다시 실행해 주세요.'
}

function Invoke-PatchTransaction([string]$Game, [string]$Backup, $Changes) {
    $pending = Get-ChildPath $Game $script:PendingName
    if ([IO.File]::Exists($pending)) { throw '중단된 작업이 있습니다. 먼저 복구.bat를 실행해 주세요.' }
    $before = [ordered]@{}
    $staged = [ordered]@{}
    foreach ($entry in $Changes.GetEnumerator()) {
        Assert-ManagedPath $entry.Key -AllowManifest
        $destination = Get-ChildPath $Game $entry.Key
        $present = [IO.File]::Exists($destination)
        $saved = Get-ChildPath $Backup ('files/' + $entry.Key)
        if ($present) { Copy-PatchFile $destination $saved }
        $source = $null
        if ($entry.Value) {
            $source = Get-ChildPath $Backup ('after/' + $entry.Key)
            Copy-PatchFile $entry.Value $source
        }
        $before[$entry.Key] = [ordered]@{ exists = $present; backup = $(if ($present) { $saved } else { $null });
            sha256 = $(if ($present) { Get-PatchHash $saved } else { $null });
            after_sha256 = $(if ($source) { Get-PatchHash $source } else { $null }) }
        $staged[$entry.Key] = $source
    }
    $journalPath = Join-Path $Backup 'recovery.json'
    Write-PatchJson $journalPath ([ordered]@{ owner = $script:Owner; game = $Game; before = $before })
    Copy-PatchFile $journalPath $pending
    try {
        foreach ($entry in $staged.GetEnumerator()) {
            $destination = Get-ChildPath $Game $entry.Key
            $current = if ([IO.File]::Exists($destination)) { Get-PatchHash $destination } else { $null }
            if ($current -ne $before[$entry.Key].sha256) { throw "작업 도중 파일이 변경되었습니다: $($entry.Key)" }
            if ($entry.Value) { Copy-PatchFile $entry.Value $destination }
            elseif ([IO.File]::Exists($destination)) { [IO.File]::Delete($destination) }
        }
        [IO.File]::Delete($pending)
    } catch {
        $failure = $_.Exception.Message
        try { Restore-PatchTransaction $Game | Out-Null }
        catch { throw "작업이 중단되었습니다. 복구.bat를 실행해 주세요.`n원인: $failure`n복구: $($_.Exception.Message)`n기록: $Backup" }
        throw "작업에 실패하여 이전 상태로 복구했습니다.`n$failure"
    }
}

function Install-KoreanPatch([string]$Game, [string]$PackageRoot, [string]$BackupRoot) {
    $Game = Get-NormalPath $Game
    Assert-GameStopped
    if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { throw '먼저 복구.bat로 중단 작업을 복구해 주세요.' }
    $bundle = Read-PatchJson (Join-Path $PackageRoot 'package.json')
    if ($bundle.schema -ne 1 -or -not $bundle.files) { throw '배포 패키지 정보가 올바르지 않습니다. ZIP 전체를 다시 풀어 주세요.' }
    Assert-GameTarget $Game $bundle.target
    $font = Join-Path $env:WINDIR 'Fonts\malgun.ttf'
    if (-not [IO.File]::Exists($font)) { throw '맑은 고딕이 없습니다. Windows 언어 설정에서 한국어 글꼴을 설치해 주세요.' }
    $previous = Read-InstallManifest $Game
    if (-not $previous) {
        $existingMods = [IO.File]::Exists((Get-ChildPath $Game 'winhttp.dll'))
        foreach ($folder in @('BepInEx\core', 'BepInEx\plugins', 'BepInEx\patchers')) {
            $modPath = Join-Path $Game $folder
            Assert-NoLink $modPath
            if (Test-Path -LiteralPath $modPath) {
                if (Get-ChildItem -LiteralPath $modPath -Filter '*.dll' -Recurse -File) { $existingMods = $true }
            }
        }
        if ($existingMods) { throw '다른 모드/로더가 설치되어 있습니다. 기존 모드를 먼저 제거해 주세요.' }
    }
    Assert-InstalledFiles $Game $previous
    $payload = Join-Path $PackageRoot 'payload'
    $changes = [ordered]@{}
    foreach ($entry in $bundle.files.PSObject.Properties) {
        Assert-ManagedPath $entry.Name
        $source = Get-ChildPath $payload $entry.Name
        Assert-Hash $source $entry.Value
        Get-ChildPath $Game $entry.Name | Out-Null
        $changes[$entry.Name] = $source
    }
    foreach ($required in @('winhttp.dll', 'doorstop_config.ini', '.doorstop_version', 'BepInEx/core/BepInEx.dll',
        'BepInEx/plugins/SabadoKorean/SabadoKorean.dll', 'BepInEx/plugins/SabadoKorean/strings.tsv',
        'BepInEx/plugins/SabadoKorean/ui.tsv', 'BepInEx/plugins/SabadoKorean/textures.tsv')) {
        if (-not $changes.Contains($required)) { throw "배포 파일이 빠졌습니다: $required" }
    }
    $backup = New-PatchBackup $Game $BackupRoot
    $final = [ordered]@{}
    if ($previous) { foreach ($entry in $previous.files.PSObject.Properties) { $final[$entry.Name] = $entry.Value } }
    foreach ($entry in $changes.GetEnumerator()) {
        $destination = Get-ChildPath $Game $entry.Key
        $original = if ($final.Contains($entry.Key)) { $final[$entry.Key].original } else { $null }
        if ($original -and $original.exists) {
            # Migrate Python-era originals into the persistent release backup folder.
            $savedOriginal = Get-ChildPath $backup ('originals/' + $entry.Key)
            Copy-PatchFile $original.backup $savedOriginal
            $original = [ordered]@{ exists = $true; backup = $savedOriginal; sha256 = $original.sha256 }
        }
        if (-not $original) {
            $present = [IO.File]::Exists($destination)
            $original = [ordered]@{ exists = $present; backup = $(if ($present) { Get-ChildPath $backup ('files/' + $entry.Key) } else { $null });
                sha256 = $(if ($present) { Get-PatchHash $destination } else { $null }) }
        }
        $final[$entry.Key] = [ordered]@{ original = $original; installed_sha256 = Get-PatchHash $entry.Value }
    }
    $nextManifest = Join-Path $backup 'new-manifest.json'
    Write-PatchJson $nextManifest ([ordered]@{ owner = $script:Owner; game = $Game; target_build = $bundle.target.steam_build_id;
        version = $bundle.version; last_backup = $backup; files = $final })
    $changes[$script:ManifestName] = $nextManifest
    Invoke-PatchTransaction $Game $backup $changes
    "한국어 패치 $($bundle.version) 설치가 완료되었습니다.`nSteam에서 게임을 시작하고 텍스트 언어를 한국어로 선택해 주세요.`n백업: $backup"
}

function Remove-KoreanPatch([string]$Game, [string]$BackupRoot) {
    $Game = Get-NormalPath $Game
    Assert-GameStopped
    if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { throw '먼저 복구.bat로 중단 작업을 복구해 주세요.' }
    $manifest = Read-InstallManifest $Game
    if (-not $manifest) { return '이 폴더에는 이 도구로 설치한 패치가 없습니다.' }
    Assert-InstalledFiles $Game $manifest -AllowMissing
    $changes = [ordered]@{}
    foreach ($entry in $manifest.files.PSObject.Properties) {
        $changes[$entry.Name] = if ($entry.Value.original.exists) { $entry.Value.original.backup } else { $null }
    }
    $changes[$script:ManifestName] = $null
    $backup = New-PatchBackup $Game $BackupRoot
    Invoke-PatchTransaction $Game $backup $changes
    "한국어 패치를 제거했습니다. 세이브와 게임 설정은 유지됩니다.`n생성된 로그·캐시·빈 폴더 및 복구 백업은 남겨 둡니다.`n백업: $backup"
}

function Invoke-KoreanPatch([string]$Action, [string]$Game, [string]$PackageRoot, [string]$BackupRoot) {
    $Game = Get-NormalPath $Game
    if (-not [IO.Directory]::Exists($Game)) { throw '게임 폴더가 없습니다.' }
    Assert-NoLink $Game
    # All launchers share one lock, including recovery and removal.
    $mutex = [Threading.Mutex]::new($false, 'Local\SabadoKoreanSetup')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw '다른 설치/제거 작업이 실행 중입니다. 작업이 끝난 후 다시 실행해 주세요.' }
        switch ($Action) {
            'Install' { Install-KoreanPatch $Game $PackageRoot $BackupRoot }
            'Remove' { Remove-KoreanPatch $Game $BackupRoot }
            'Recover' { Restore-PatchTransaction $Game }
            'Status' {
                if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { throw '중단된 작업이 있습니다. 복구.bat를 실행해 주세요.' }
                $manifest = Read-InstallManifest $Game
                Assert-InstalledFiles $Game $manifest
                if ($manifest) { '설치됨: ' + $(if ($manifest.version) { $manifest.version } else { '기존 Python 설치본' }) }
                else { '한국어 패치가 설치되어 있지 않습니다.' }
            }
            default { throw '알 수 없는 작업입니다.' }
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

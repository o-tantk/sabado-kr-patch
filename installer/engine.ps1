# Windows PowerShell 5.1. No Python, downloaded modules, or game assemblies required.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
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

function Copy-PatchBytes([byte[]]$Bytes, [string]$Destination) {
    Assert-NoLink $Destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination)) | Out-Null
    $temporary = $Destination + '.sabado-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
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

function Copy-PatchFile([string]$Source, [string]$Destination) {
    Copy-PatchBytes ([IO.File]::ReadAllBytes($Source)) $Destination
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

function Restore-LegacyTransaction([string]$Game) {
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

function Get-BytesHash([byte[]]$Bytes) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($hasher.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function ConvertTo-JsonBytes($Value) {
    ,([Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 20)))
}

function Remove-PatchFile([string]$Path) { [IO.File]::Delete($Path) }

function Get-LegacyBackupRoot([string]$Game) {
    # Read/cleanup compatibility only. New versions never create this directory.
    $id = (Get-BytesHash ([Text.Encoding]::UTF8.GetBytes((Get-NormalPath $Game).ToLowerInvariant()))).Substring(0, 16).ToUpperInvariant()
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "SabadoKorean\Backups\$id"
}

function Remove-LegacyBackups([string]$Game) {
    if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { return }
    $current = Read-InstallManifest $Game
    if ($current -and @($current.files.PSObject.Properties | Where-Object { $_.Value.original.exists }).Count) { return }
    $root = Get-NormalPath (Get-LegacyBackupRoot $Game)
    if (-not [IO.Directory]::Exists($root)) { return }
    Assert-NoLink $root
    # Only this game's recognized, owned legacy sessions may be deleted. Check
    # the resolved boundary and every entry before issuing any recursive delete.
    $sessions = @(Get-ChildItem -LiteralPath $root -Force)
    foreach ($session in $sessions) {
        $path = Get-NormalPath $session.FullName
        if (-not $session.PSIsContainer -or $session.Name -cnotmatch '^\d{8}T\d{13}Z-[a-f0-9]{8}$' -or
            -not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "기존 백업 폴더에 알 수 없는 항목이 있어 정리하지 않았습니다: $path"
        }
        Assert-NoLink $path
        $owned = $false
        foreach ($file in Get-ChildItem -LiteralPath $path -Recurse -Force) {
            Assert-NoLink $file.FullName
            $relative = $file.FullName.Substring($path.Length + 1).Replace('\', '/')
            if ($file.PSIsContainer) {
                if ($relative -cnotmatch '^(files|after|originals)(/BepInEx(/core|/plugins(/SabadoKorean(/textures)?)?)?)?$') {
                    throw "기존 백업에 알 수 없는 폴더가 있습니다: $($file.FullName)"
                }
                continue
            }
            if ($relative -cin @('recovery.json', 'new-manifest.json', 'previous-manifest.json')) {
                $metadata = Read-PatchJson $file.FullName
                if ($metadata.owner -ne $script:Owner -or -not $metadata.game -or (Get-NormalPath $metadata.game) -ne (Get-NormalPath $Game)) {
                    throw "다른 설치의 백업은 삭제하지 않습니다: $($file.FullName)"
                }
                $owned = $true
            } elseif ($relative -cmatch '^(files|after|originals)/(.+)$') {
                $managed = $Matches[2] -creplace '\.sabado-[a-f0-9]{32}\.tmp$', ''
                Assert-ManagedPath $managed -AllowManifest
            } else { throw "기존 백업에 알 수 없는 파일이 있습니다: $($file.FullName)" }
        }
        if (-not $owned) { throw "소유 기록이 없는 폴더는 삭제하지 않습니다: $path" }
    }
    foreach ($session in $sessions) { Remove-Item -LiteralPath $session.FullName -Recurse -Force }
    # Remove only empty parents, never another game's backups.
    foreach ($path in @($root, (Split-Path -Parent $root), (Split-Path -Parent (Split-Path -Parent $root)))) {
        if ([IO.Directory]::Exists($path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { [IO.Directory]::Delete($path) }
    }
}

function Write-ArchiveEntry($Archive, [string]$Name, [byte[]]$Bytes) {
    $entry = $Archive.CreateEntry($Name)
    $stream = $entry.Open()
    try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
}

function Read-ArchiveEntry($Archive, [string]$Name) {
    $entry = $Archive.GetEntry($Name)
    if (-not $entry) { throw "백업에 필요한 파일이 없습니다: $Name" }
    $source = $entry.Open()
    $memory = [IO.MemoryStream]::new()
    try { $source.CopyTo($memory); ,($memory.ToArray()) }
    finally { $source.Dispose(); $memory.Dispose() }
}

function Read-ArchiveJournal([string]$Path, [string]$Game) {
    if ([IO.Path]::GetFileName($Path) -cnotmatch '^SabadoKorean-backup-[a-f0-9]{32}\.zip$') { throw '백업 파일 이름이 올바르지 않습니다.' }
    Assert-NoLink $Path
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try { $journal = [Text.Encoding]::UTF8.GetString((Read-ArchiveEntry $zip 'recovery.json')) | ConvertFrom-Json }
    finally { $zip.Dispose() }
    if ($journal.schema -ne 2 -or $journal.owner -ne $script:Owner -or -not $journal.game -or
        (Get-NormalPath $journal.game) -ne (Get-NormalPath $Game) -or -not $journal.before) { throw '이 게임의 백업 파일이 아닙니다.' }
    $journal
}

function New-PatchArchive([string]$Game, [string]$PackageRoot, $Changes) {
    $PackageRoot = Get-NormalPath $PackageRoot
    Assert-NoLink $PackageRoot
    if (-not [IO.Directory]::Exists($PackageRoot)) { throw '배치 파일이 있는 폴더를 찾을 수 없습니다.' }
    $archivePath = Join-Path $PackageRoot ('SabadoKorean-backup-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $before = [ordered]@{}
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::Open($archivePath, 'Create')
        foreach ($entry in $Changes.GetEnumerator()) {
            Assert-ManagedPath $entry.Key -AllowManifest
            $destination = Get-ChildPath $Game $entry.Key
            $present = [IO.File]::Exists($destination)
            $hash = $null
            if ($present) {
                $bytes = [IO.File]::ReadAllBytes($destination)
                $hash = Get-BytesHash $bytes
                Write-ArchiveEntry $zip ('files/' + $entry.Key) $bytes
            }
            $before[$entry.Key] = @{ exists = $present; sha256 = $hash;
                after_sha256 = $(if ($null -ne $entry.Value) { Get-BytesHash $entry.Value } else { $null }) }
        }
        $journal = [ordered]@{ schema = 2; owner = $script:Owner; game = $Game; archive = $archivePath; before = $before }
        Write-ArchiveEntry $zip 'recovery.json' (ConvertTo-JsonBytes $journal)
        $zip.Dispose()
        $zip = $null
    } catch {
        if ($zip) { $zip.Dispose() }
        # No target files have changed before the archive is complete.
        if ([IO.File]::Exists($archivePath)) { [IO.File]::Delete($archivePath) }
        throw
    }
    $journal.archive_sha256 = Get-PatchHash $archivePath
    [pscustomobject]$journal
}

function Remove-PatchArchive([string]$Path, [string]$Game) {
    if ([IO.File]::Exists($Path)) {
        Read-ArchiveJournal $Path $Game | Out-Null
        Remove-Item -LiteralPath $Path
    }
}

function Remove-CompletedArchives([string]$Game, [string]$PackageRoot) {
    if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { return }
    foreach ($file in Get-ChildItem -LiteralPath $PackageRoot -Filter 'SabadoKorean-backup-*.zip' -File) {
        try { Read-ArchiveJournal $file.FullName $Game | Out-Null } catch { continue }
        Remove-PatchArchive $file.FullName $Game
    }
}

function Restore-PatchTransaction([string]$Game) {
    $pending = Get-ChildPath $Game $script:PendingName
    if (-not [IO.File]::Exists($pending)) { return }
    Assert-GameStopped
    $journal = Read-PatchJson $pending
    if ($journal.owner -ne $script:Owner -or -not $journal.game -or
        (Get-NormalPath $journal.game) -ne (Get-NormalPath $Game)) { throw '복구 기록이 올바르지 않습니다.' }
    if ($journal.schema -ne 2) {
        Restore-LegacyTransaction $Game | Out-Null
        return
    }
    Assert-Hash $journal.archive $journal.archive_sha256
    $savedJournal = Read-ArchiveJournal $journal.archive $Game
    if (($savedJournal.before | ConvertTo-Json -Depth 20 -Compress) -cne ($journal.before | ConvertTo-Json -Depth 20 -Compress)) {
        throw '백업과 복구 기록이 일치하지 않습니다.'
    }
    $saved = @{}
    $zip = [IO.Compression.ZipFile]::OpenRead($journal.archive)
    try {
        foreach ($entry in $journal.before.PSObject.Properties) {
            Assert-ManagedPath $entry.Name -AllowManifest
            $destination = Get-ChildPath $Game $entry.Name
            $record = $entry.Value
            if ($record.exists) {
                $bytes = Read-ArchiveEntry $zip ('files/' + $entry.Name)
                if ((Get-BytesHash $bytes) -ne $record.sha256) { throw "백업 파일이 손상되었습니다: $($entry.Name)" }
                $saved[$entry.Name] = $bytes
            }
            $current = if ([IO.File]::Exists($destination)) { Get-PatchHash $destination } else { $null }
            $before = if ($record.exists) { $record.sha256 } else { $null }
            if ($current -ne $before -and $current -ne $record.after_sha256) { throw "파일이 별도로 변경되어 복구하지 않았습니다: $($entry.Name)" }
        }
    } finally { $zip.Dispose() }
    foreach ($entry in $journal.before.PSObject.Properties) {
        $destination = Get-ChildPath $Game $entry.Name
        if ($entry.Value.exists) { Copy-PatchBytes $saved[$entry.Name] $destination }
        elseif ([IO.File]::Exists($destination)) { Remove-PatchFile $destination }
    }
    Remove-PatchFile $pending
    # The caller deletes this only after its complete requested task succeeds.
    $journal.archive
}

function Invoke-PatchTransaction([string]$Game, [string]$PackageRoot, $Changes) {
    $pending = Get-ChildPath $Game $script:PendingName
    if ([IO.File]::Exists($pending)) { throw '먼저 복구.bat를 실행해 주세요.' }
    $journal = New-PatchArchive $Game $PackageRoot $Changes
    try {
        Copy-PatchBytes (ConvertTo-JsonBytes $journal) $pending
        foreach ($entry in $Changes.GetEnumerator()) {
            $destination = Get-ChildPath $Game $entry.Key
            $current = if ([IO.File]::Exists($destination)) { Get-PatchHash $destination } else { $null }
            if ($current -ne $journal.before[$entry.Key].sha256) { throw "작업 도중 파일이 변경되었습니다: $($entry.Key)" }
            if ($null -ne $entry.Value) { Copy-PatchBytes $entry.Value $destination }
            elseif ([IO.File]::Exists($destination)) { Remove-PatchFile $destination }
        }
        Remove-PatchFile $pending
    } catch {
        $failure = $_.Exception.Message
        try { Restore-PatchTransaction $Game | Out-Null }
        catch { throw "작업이 중단되었습니다. 복구.bat를 실행해 주세요.`n원인: $failure`n복구: $($_.Exception.Message)`n백업: $($journal.archive)" }
        throw "작업에 실패하여 이전 상태로 되돌렸습니다.`n$failure`n백업: $($journal.archive)"
    }
    $journal.archive
}

function Install-KoreanPatch([string]$Game, [string]$PackageRoot) {
    $Game = Get-NormalPath $Game
    Assert-GameStopped
    if ([IO.File]::Exists((Get-ChildPath $Game $script:PendingName))) { throw '먼저 복구.bat를 실행해 주세요.' }
    $bundle = Read-PatchJson (Join-Path $PackageRoot 'package.json')
    if ($bundle.schema -ne 1 -or -not $bundle.files) { throw '배포 파일이 올바르지 않습니다. ZIP 전체를 다시 풀어 주세요.' }
    Assert-GameTarget $Game $bundle.target
    if (-not [IO.File]::Exists((Join-Path $env:WINDIR 'Fonts\malgun.ttf'))) { throw 'Windows 언어 설정에서 한국어 글꼴(맑은 고딕)을 설치해 주세요.' }
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
    if ($previous -and @($previous.files.PSObject.Properties | Where-Object { $_.Value.original.exists }).Count) {
        throw '이전 설치가 원래 있던 파일을 변경했습니다. 복구.bat로 원본을 먼저 복원해 주세요.'
    }
    $payload = Join-Path $PackageRoot 'payload'
    $changes = [ordered]@{}
    $final = [ordered]@{}
    if ($previous) { foreach ($entry in $previous.files.PSObject.Properties) { $final[$entry.Name] = $entry.Value } }
    foreach ($entry in $bundle.files.PSObject.Properties) {
        Assert-ManagedPath $entry.Name
        $source = Get-ChildPath $payload $entry.Name
        $bytes = [IO.File]::ReadAllBytes($source)
        if ((Get-BytesHash $bytes) -ne $entry.Value) { throw "배포 파일이 손상되었습니다: $($entry.Name)" }
        $destination = Get-ChildPath $Game $entry.Name
        if ([IO.File]::Exists($destination) -and -not $final.Contains($entry.Name)) {
            throw "원래 있던 파일은 덮어쓰지 않습니다: $($entry.Name)"
        }
        $changes[$entry.Name] = $bytes
        $final[$entry.Name] = @{ original = @{ exists = $false }; installed_sha256 = $entry.Value }
    }
    foreach ($required in @('winhttp.dll', 'doorstop_config.ini', '.doorstop_version', 'BepInEx/core/BepInEx.dll',
        'BepInEx/plugins/SabadoKorean/SabadoKorean.dll', 'BepInEx/plugins/SabadoKorean/strings.tsv',
        'BepInEx/plugins/SabadoKorean/ui.tsv', 'BepInEx/plugins/SabadoKorean/textures.tsv')) {
        if (-not $changes.Contains($required)) { throw "배포 파일이 빠졌습니다: $required" }
    }
    $manifest = @{ schema = 2; owner = $script:Owner; game = $Game; target_build = $bundle.target.steam_build_id;
        version = $bundle.version; files = $final }
    $changes[$script:ManifestName] = ConvertTo-JsonBytes $manifest
    $archive = Invoke-PatchTransaction $Game $PackageRoot $changes
    Remove-LegacyBackups $Game
    Remove-CompletedArchives $Game $PackageRoot
    "한국어 패치 $($bundle.version) 설치가 완료되었습니다.`n게임에서 텍스트 언어를 한국어로 선택해 주세요."
}

function Remove-KoreanPatch([string]$Game, [string]$PackageRoot) {
    $Game = Get-NormalPath $Game
    Assert-GameStopped
    $recoveredArchive = Restore-PatchTransaction $Game
    $manifest = Read-InstallManifest $Game
    if ($manifest) {
        Assert-InstalledFiles $Game $manifest -AllowMissing
        $changes = [ordered]@{}
        foreach ($entry in $manifest.files.PSObject.Properties) {
            $changes[$entry.Name] = if ($entry.Value.original.exists) { ,([IO.File]::ReadAllBytes($entry.Value.original.backup)) } else { $null }
        }
        $changes[$script:ManifestName] = $null
        $archive = Invoke-PatchTransaction $Game $PackageRoot $changes
    }
    Remove-LegacyBackups $Game
    Remove-CompletedArchives $Game $PackageRoot
    if ($recoveredArchive) { Remove-PatchArchive $recoveredArchive $Game }
    '한국어 패치를 제거하고 원래 게임 상태로 복구했습니다. 세이브와 게임 설정은 유지됩니다.'
}

function Invoke-KoreanPatch([string]$Action, [string]$Game, [string]$PackageRoot) {
    $Game = Get-NormalPath $Game
    if (-not [IO.Directory]::Exists($Game)) { throw '게임 폴더가 없습니다.' }
    Assert-NoLink $Game
    $mutex = [Threading.Mutex]::new($false, 'Local\SabadoKoreanSetup')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw '다른 설치/복구 작업이 실행 중입니다.' }
        switch ($Action) {
            'Install' { Install-KoreanPatch $Game $PackageRoot }
            'Remove' { Remove-KoreanPatch $Game $PackageRoot } # Compatibility with older command lines.
            'Recover' { Remove-KoreanPatch $Game $PackageRoot }
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

param(
    [ValidateSet('Install', 'Remove', 'Recover', 'Status')][string]$Action = 'Install',
    [string]$Game,
    [switch]$NonInteractive,
    [string]$BackupRoot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'engine.ps1')
. (Join-Path $PSScriptRoot 'discovery.ps1')
$packageRoot = Split-Path -Parent $PSScriptRoot
$title = 'Sabado 한국어 패치'
$actionName = @{ Install = '설치 / 업데이트'; Remove = '제거'; Recover = '중단 작업 복구'; Status = '설치 상태 확인' }[$Action]

function Select-Sabado {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'Sabado 게임 폴더의 Sabado Day One.exe를 선택해 주세요'
        $dialog.Filter = 'Sabado 실행 파일 (Sabado Day One.exe)|Sabado Day One.exe'
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
        Split-Path -Parent $dialog.FileName
    } finally { $dialog.Dispose() }
}

try {
    if (-not $NonInteractive) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.Application]::EnableVisualStyles()
        if (-not $Game) {
            $Game = Find-Sabado
        }
        if ($Game) {
            $answer = [Windows.Forms.MessageBox]::Show("$actionName 작업을 진행할까요?`n`n게임 폴더: $Game`n`n게임을 먼저 종료해 주세요.`n[아니요]를 누르면 다른 게임 폴더를 선택합니다.", $title, 'YesNoCancel', 'Question')
            if ($answer -eq 'Cancel') { exit 0 }
            if ($answer -eq 'No') { $Game = $null }
        }
        if (-not $Game) {
            $Game = Select-Sabado
            if (-not $Game) { exit 0 }
            if ([Windows.Forms.MessageBox]::Show("선택한 폴더에서 $actionName 작업을 진행합니다.`n`n$Game`n`n게임이 종료되어 있나요?", $title, 'OKCancel', 'Question') -ne 'OK') { exit 0 }
        }
    } elseif (-not $Game) { throw '자동 실행에는 -Game 경로가 필요합니다.' }
    $Game = Get-NormalPath $Game
    if (-not [IO.Directory]::Exists($Game)) { throw '게임 폴더가 없습니다.' }
    Assert-NoLink $Game
    Assert-GameStopped

    # Ask for elevation only when this chosen installation actually needs it.
    if (-not $NonInteractive -and $Action -ne 'Status') {
        $probe = Join-Path $Game ('.sabado-write-test-' + [Guid]::NewGuid().ToString('N'))
        try {
            $stream = [IO.File]::Open($probe, 'CreateNew', 'Write', 'None')
            $stream.Dispose()
            [IO.File]::Delete($probe)
        } catch [UnauthorizedAccessException] {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw }
            [Windows.Forms.MessageBox]::Show('이 게임 폴더에는 관리자 권한이 필요합니다. 다음 Windows 권한 요청을 승인한 뒤 열린 창에서 진행해 주세요.', $title, 'OK', 'Information') | Out-Null
            $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "' + $PSCommandPath + '" -Action ' + $Action + ' -Game "' + $Game + '"'
            $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            exit $child.ExitCode
        }
    }
    Write-Host "$title - $actionName"
    Write-Host "게임 폴더: $Game"
    Write-Host '파일 검사 및 백업 중입니다. 완료될 때까지 기다려 주세요.'
    $result = Invoke-KoreanPatch $Action $Game $packageRoot $BackupRoot
    Write-Host $result
    if (-not $NonInteractive) { [Windows.Forms.MessageBox]::Show($result, $title, 'OK', 'Information') | Out-Null }
    exit 0
} catch {
    $message = $_.Exception.Message
    Write-Host $message -ForegroundColor Red
    if (-not $NonInteractive) { [Windows.Forms.MessageBox]::Show($message, $title, 'OK', 'Error') | Out-Null }
    exit 1
}

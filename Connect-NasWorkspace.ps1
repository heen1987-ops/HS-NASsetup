#requires -Version 5.1
<#
.SYNOPSIS
NAS 작업 폴더 연결 계획을 표시하고, 지정한 경우에만 연결합니다.
.DESCRIPTION
기본 실행과 -WhatIf는 네트워크 접속 및 변경을 하지 않습니다.
-CheckConnection은 지정한 호스트의 TCP 445만 확인합니다.
-Connect는 암호를 대화형으로 입력받아 현재 사용자에게 드라이브를 연결합니다.
관리자가 아닌, Codex 등 작업 앱과 동일한 Windows 사용자로 실행하세요.
.EXAMPLE
.\Connect-NasWorkspace.ps1 -NasHost 'nas-name.example.ts.net'
.EXAMPLE
.\Connect-NasWorkspace.ps1 -NasHost 'nas-name.example.ts.net' -CheckConnection
.EXAMPLE
.\Connect-NasWorkspace.ps1 -NasHost 'nas-name.example.ts.net' -Connect -InitializeFolders
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NasHost,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$')]
    [string]$ShareName = 'AI-Workspace',

    [ValidatePattern('^[D-Zd-z]$')]
    [string]$DriveLetter = 'W',

    [switch]$CheckConnection,
    [switch]$Connect,
    [switch]$InitializeFolders
)

$ErrorActionPreference = 'Stop'
$hostKind = [Uri]::CheckHostName($NasHost)
if ($hostKind -notin @([UriHostNameType]::Dns, [UriHostNameType]::IPv4)) {
    throw 'NAS 호스트명 또는 IPv4 주소만 입력하세요. URL, 공유 경로, IPv6 주소는 받지 않습니다.'
}
if ($NasHost -match '[\\/:\s]') {
    throw 'NAS 호스트명에는 경로, 프로토콜 또는 공백을 넣을 수 없습니다.'
}
if ($InitializeFolders -and -not $Connect) {
    throw '-InitializeFolders는 -Connect와 함께 지정해야 합니다.'
}

$DriveLetter = $DriveLetter.ToUpperInvariant()
$localPath = $DriveLetter + ':'
$remotePath = '\\' + $NasHost + '\' + $ShareName
$folderNames = @('01_프로젝트', '02_생성물', '03_참고자료', '04_완료보관')

# 접근 불가능한 기존 연결도 점유 상태로 취급합니다.
$driveExists = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
$savedMapping = Test-Path -LiteralPath ('HKCU:\Network\' + $DriveLetter)
$smbMapping = @(Get-SmbMapping -ErrorAction Stop | Where-Object { $_.LocalPath -eq $localPath })
if ($driveExists -or $savedMapping -or $smbMapping.Count -gt 0) {
    throw "$localPath 드라이브가 이미 사용되거나 저장된 연결이 있습니다. 기존 연결은 변경하지 않았습니다. 다른 문자를 지정하세요."
}

[pscustomobject]@{
    '작업' = 'NAS 공유 폴더 연결 계획'
    '로컬경로' = $localPath + '\'
    'NAS경로' = $remotePath
    '연결실행요청' = [bool]$Connect
    '폴더생성요청' = [bool]$InitializeFolders
}

if ($WhatIfPreference) {
    Write-Host '미리보기: 네트워크 접속, 인증, 드라이브 연결, 폴더 생성을 수행하지 않았습니다.'
    return
}
if (-not $CheckConnection -and -not $Connect) {
    Write-Host '계획만 표시했습니다. 통신 검사에는 -CheckConnection, 실제 연결에는 -Connect를 지정하세요.'
    return
}
if (-not $PSCmdlet.ShouldProcess($remotePath, 'TCP 445 통신 검사')) { return }

$reachable = Test-NetConnection -ComputerName $NasHost -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $reachable) {
    throw 'NAS의 TCP 445에 연결하지 못했습니다. NAS 전원, Tailscale 연결, 호스트명, SMB 서비스와 방화벽을 확인하세요.'
}
Write-Host 'TCP 445 통신 성공. 계정 인증과 폴더 권한은 별도로 확인해야 합니다.'
if (-not $Connect) { return }
if (-not $PSCmdlet.ShouldProcess($remotePath, "$localPath 드라이브 영구 연결")) { return }

$credential = Get-Credential -Message 'NAS 작업용 일반 계정을 입력하세요. 관리자 계정은 사용하지 마세요.'
if ($null -eq $credential) { throw '인증 입력이 취소되어 연결하지 않았습니다.' }
try {
    New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $remotePath -Credential $credential -Persist -Scope Global -ErrorAction Stop | Out-Null
} finally {
    $credential = $null
}
Write-Host "$localPath 연결 명령이 완료되었습니다. 연결은 현재 Windows 사용자 세션에 적용됩니다."

if (-not (Test-Path -LiteralPath ($localPath + '\') -PathType Container)) {
    throw '연결 명령은 완료되었지만 공유 폴더 접근 검증에 실패했습니다. 생성된 연결 상태와 권한을 확인하세요. 자동 삭제하지 않았습니다.'
}
Write-Host '공유 폴더 경로 접근 확인 완료. 파일 쓰기와 앱별 접근은 아직 별도 검증이 필요합니다.'

if ($InitializeFolders) {
    foreach ($folderName in $folderNames) {
        $folderPath = Join-Path ($localPath + '\') $folderName
        if (Test-Path -LiteralPath $folderPath) {
            if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                throw "폴더 대신 같은 이름의 파일이 있습니다: $folderPath. 앞서 생성된 폴더와 연결은 유지됩니다."
            }
            continue
        }
        if ($PSCmdlet.ShouldProcess($folderPath, '새 작업 폴더 생성')) {
            New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop | Out-Null
        }
    }
    Write-Host '요청한 작업 폴더 생성 절차를 마쳤습니다. 기존 파일을 덮어쓰거나 삭제하지 않았습니다.'
}

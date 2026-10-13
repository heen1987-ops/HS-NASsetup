#requires -Version 5.1
<#
NAS 도착 전 PC의 Ubuntu WSL에서 준비용 컨테이너를 관리합니다.
Start: 두 웹 점검 컨테이너 시작. 공개 터널은 시작하지 않습니다.
Stop: 이 프로젝트의 컨테이너와 전용 WSL 유지 프로세스만 중지합니다.
Status: Docker 버전과 두 프로젝트의 상태를 표시합니다.
Test: 실제 동작과 격리 설정을 검사하고 JSON 결과를 저장합니다.
#>
[CmdletBinding()]
param([ValidateSet('Start', 'Stop', 'Status', 'Test')][string]$Action = 'Status')

$ErrorActionPreference = 'Stop'
$nasWsl = (Get-Command wsl.exe -ErrorAction Stop).Source
$nasStateDirectory = Join-Path $env:LOCALAPPDATA 'NasCloudPrep'
$nasKeeperFile = Join-Path $nasStateDirectory 'keeper.json'

function Invoke-NasWsl {
    param([string[]]$Arguments)
    & $nasWsl -d Ubuntu -u root -- @Arguments
    if ($LASTEXITCODE -ne 0) { throw "WSL 명령 실패 (종료 코드 $LASTEXITCODE)" }
}

function Get-NasKeeper {
    if (-not (Test-Path -LiteralPath $nasKeeperFile)) { return $null }
    $nasStored = Get-Content -LiteralPath $nasKeeperFile -Raw | ConvertFrom-Json
    $nasProcess = Get-Process -Id $nasStored.ProcessId -ErrorAction SilentlyContinue
    if ($nasProcess -and $nasProcess.ProcessName -eq 'wsl' -and
        $nasProcess.StartTime.ToUniversalTime().Ticks.ToString() -eq $nasStored.StartTicks) {
        return $nasProcess
    }
    return $null
}

function Start-NasKeeper {
    if (Get-NasKeeper) { return }
    # systemd 서비스만으로는 WSL 인스턴스 유지가 보장되지 않습니다.
    # 고정 인수만 사용하며 사용자 입력을 셸 코드로 결합하지 않습니다.
    $nasProcess = Start-Process -FilePath $nasWsl -ArgumentList @('-d', 'Ubuntu', '--exec', 'sleep', 'infinity') -WindowStyle Hidden -PassThru
    New-Item -ItemType Directory -Path $nasStateDirectory -Force | Out-Null
    [PSCustomObject]@{
        ProcessId = $nasProcess.Id
        StartTicks = $nasProcess.StartTime.ToUniversalTime().Ticks.ToString()
    } | ConvertTo-Json | Set-Content -LiteralPath $nasKeeperFile -Encoding UTF8
}

$nasLinuxProject = (& $nasWsl -d Ubuntu -- wslpath -a $PSScriptRoot).Trim()
if ($LASTEXITCODE -ne 0 -or -not $nasLinuxProject.StartsWith('/')) { throw '프로젝트 WSL 경로 확인 실패' }
$nasPrivateArguments = @('docker', 'compose', '-p', 'nas-cloud-local', '-f', ($nasLinuxProject + '/cloud/docker-compose.yml'))
# /dev/null은 Compose 변수 해석만 위한 비밀값 없는 경로입니다.
# public-web에 secret을 연결하지 않으며 cloudflared는 시작하지 않습니다.
$nasPublicArguments = @('env', 'TUNNEL_TOKEN_FILE=/dev/null', 'docker', 'compose', '-p', 'nas-public-check', '-f', ($nasLinuxProject + '/cloud/public/docker-compose.yml'))

switch ($Action) {
    'Start' {
        Start-NasKeeper
        Invoke-NasWsl -Arguments @('systemctl', 'start', 'docker')
        Invoke-NasWsl -Arguments ($nasPrivateArguments + @('config', '--quiet'))
        Invoke-NasWsl -Arguments ($nasPublicArguments + @('config', '--quiet'))
        Invoke-NasWsl -Arguments ($nasPrivateArguments + @('up', '-d', '--wait', '--wait-timeout', '60'))
        Invoke-NasWsl -Arguments ($nasPublicArguments + @('up', '-d', '--no-deps', '--wait', '--wait-timeout', '60', 'public-web'))
        # WSL의 Windows localhost 전달이 준비되는 짧은 지연을 허용합니다.
        $nasReady = $false
        for ($nasAttempt = 0; $nasAttempt -lt 15; $nasAttempt++) {
            $nasCode = & curl.exe --noproxy '*' --silent --output NUL --write-out '%{http_code}' --max-time 2 'http://127.0.0.1:18080/healthz'
            if ($LASTEXITCODE -eq 0 -and $nasCode -eq '200') { $nasReady = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $nasReady) { throw '컨테이너 시작 후 Windows localhost 접속을 확인하지 못했습니다. Test 결과를 확인하세요.' }
        Write-Output '시작 완료: http://127.0.0.1:18080 (이 PC에서 접속). 공개 터널은 실행하지 않았습니다.'
    }
    'Stop' {
        Invoke-NasWsl -Arguments ($nasPublicArguments + @('stop', 'public-web'))
        Invoke-NasWsl -Arguments ($nasPrivateArguments + @('stop'))
        $nasKeeper = Get-NasKeeper
        if ($nasKeeper) { Stop-Process -Id $nasKeeper.Id }
        if (Test-Path -LiteralPath $nasKeeperFile) { Remove-Item -LiteralPath $nasKeeperFile }
        Write-Output '준비용 컨테이너를 중지했습니다. 이미지·설정·데이터와 다른 WSL 작업은 삭제하지 않았습니다.'
    }
    'Status' {
        Invoke-NasWsl -Arguments @('docker', 'version', '--format', '{{.Server.Version}}')
        Invoke-NasWsl -Arguments @('docker', 'compose', 'version')
        Invoke-NasWsl -Arguments ($nasPrivateArguments + @('ps', '--all'))
        Invoke-NasWsl -Arguments ($nasPublicArguments + @('ps', '--all'))
        Write-Output ('WSL 유지 프로세스: ' + [bool](Get-NasKeeper))
    }
    'Test' {
        & python (Join-Path $PSScriptRoot 'scripts/verify-docker-runtime.py')
        if ($LASTEXITCODE -ne 0) { throw '런타임 검증 실패. cloud/validation/runtime-result.json을 확인하세요.' }
    }
}

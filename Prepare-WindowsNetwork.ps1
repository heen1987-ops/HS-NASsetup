#requires -Version 5.1
#requires -RunAsAdministrator
<#
원격 접속 준비를 위해 Windows 방화벽을 켭니다.
기존 허용 규칙·네트워크 프로필·공유 설정을 변경하지 않습니다.
실행 전 상태는 PC 로컬의 NasCloudPrep 폴더에 기록합니다.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$nasProfiles = @(Get-NetFirewallProfile)
if ($PSCmdlet.ShouldProcess('Windows 방화벽 Domain, Private, Public', '방화벽 사용 설정')) {
    $nasBackupDirectory = Join-Path $env:LOCALAPPDATA 'NasCloudPrep'
    New-Item -ItemType Directory -Path $nasBackupDirectory -Force | Out-Null
    $nasBackupPath = Join-Path $nasBackupDirectory ('firewall-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
    $nasProfiles | Select-Object Name, Enabled | ConvertTo-Json | Set-Content -LiteralPath $nasBackupPath -Encoding UTF8
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
    $nasAfter = @(Get-NetFirewallProfile)
    $nasAfter | Select-Object Name, Enabled
    if (@($nasAfter | Where-Object { $_.Enabled -ne $true }).Count -gt 0) {
        throw '일부 방화벽 프로필을 활성화하지 못했습니다. 정책과 권한을 확인하세요.'
    }
    Write-Output '방화벽 활성화 완료. 기존 규칙은 유지했습니다. 원격 연결은 별도로 점검해야 합니다.'
}

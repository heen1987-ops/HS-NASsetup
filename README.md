# NAS 서버 사전 세팅 — 현재 상태와 사용법

기준: 2026-10-13 / Synology DS225+ 배송 전 / 준비 PC: Windows 11 + Ubuntu 26.04 WSL2

**PC에 Docker를 설치하고 두 개의 컨테이너를 실행했다.** 이 문서가 이전 준비 문서보다 최신 상태를 나타낸다. NAS의 DSM·디스크·공유 폴더 설정과 실제 외부 접속은 장비 도착 후 진행한다.

## 지금 완료한 작업

| 구성 | 실제 상태 |
|---|---|
| Docker Engine | Ubuntu WSL에 공식 APT 저장소로 29.9.0 설치, 서비스 실행 및 자동 시작 설정 |
| Docker Compose | v5.6.0 설치 |
| 개인 클라우드 점검 서버 | `nas-cloud-local-cloud-probe-1`, Healthy, 이 PC의 `127.0.0.1:18080`에 연결 |
| 공개 웹 기본 서버 | `nas-public-check-public-web-1`, Healthy, 전용 내부 Docker 네트워크에서만 실행 |
| Cloudflare 연결 프로그램 | cloudflared 2026.10.0 이미지 다운로드·오프라인 실행 및 token-file 옵션 검증. 실제 터널 미생성 |
| 실행 도구 | `NasCloud.cmd`로 실행, 내부 `Manage-NasCloud.ps1`에 Start / Stop / Status / Test 구성 |
| NAS 작업 드라이브 | `Connect-NasWorkspace.ps1` 준비. NAS 도착 후 `AI-Workspace` 공유를 W:로 연결 |
| Windows 방화벽 | 관리자용 활성화 스크립트 준비. 사용 환경별 적용·검증 필요 |
| Tailscale | 서명 확인한 설치 프로그램 실행 중. 설치·로그인 완료 미확인 |

Docker Desktop은 설치하지 않았다. Docker 명령은 WSL의 Engine을 사용한다. Windows PowerShell에서 직접 사용할 때는 아래처럼 실행한다.

```powershell
wsl -d Ubuntu -u root -- docker ps
wsl -d Ubuntu -u root -- docker compose version
```

## PC에서 사용하기

현재 폴더를 터미널에서 열고 다음 명령을 실행한다. `NasCloud.cmd`는 이 PC의 Codex에 포함된 PowerShell 7을 사용한다. 이 환경은 기존 정책이 RemoteSigned이며, 이번 작업에서 실행 정책을 변경하지 않았다. Windows 기본 PowerShell 5.1은 Restricted 상태여서 `.ps1` 직접 실행 시험이 차단됐다. 스크립트 자체의 실행 검증은 PowerShell 7에서 수행했다. Codex 런타임 위치가 변경되면 실행 파일 경로를 다시 확인해야 한다.

```powershell
# 시작
.\NasCloud.cmd Start

# 상태
.\NasCloud.cmd Status

# 재검사 — 이 PC의 python 필요, 현재 PC에 설치되어 있음
.\NasCloud.cmd Test

# 사용 종료 — 컨테이너 중지, 데이터와 이미지 유지
.\NasCloud.cmd Stop
```

시작 후 브라우저에서 [점검 서버](http://127.0.0.1:18080/)와 [상태 확인](http://127.0.0.1:18080/healthz)을 연다. 다른 컴퓨터에서 접속하는 주소가 아니다.

WSL은 systemd 서비스만으로 계속 실행되지 않을 수 있어 Start가 숨겨진 전용 WSL 유지 프로세스를 만든다. Stop은 해당 프로세스의 PID와 시작 시각을 확인한 뒤 종료한다. 다른 Ubuntu 세션을 강제 종료하거나 Docker 전체를 중단하지 않는다. PC 재부팅 후에는 Start를 다시 실행한다. Windows 로그인 자동 실행이나 절전 방지 설정은 추가하지 않았다. [Microsoft WSL systemd 문서](https://learn.microsoft.com/en-us/windows/wsl/systemd/)

Docker 이미지·컨테이너 데이터는 기존 WSL Linux 디스크의 Docker 저장소를 사용한다. 설정 파일만 이 프로젝트에서 읽기 전용으로 마운트한다. 기존 Ubuntu 사용자를 docker 그룹에 추가하지 않았으며, 관리 스크립트는 WSL root로 정해진 Docker 명령을 실행한다.

## 원격 접속 준비의 남은 PC 단계

1. 열려 있는 Tailscale 설치 화면에서 설치를 마친 후 본인 계정으로 로그인한다. Windows 관리자 확인(UAC)이 뜨면 사용자가 직접 확인해야 한다. 비밀번호를 대화에 입력할 필요가 없다.
2. Windows 방화벽을 활성화한다. 아래 개별 명령은 관리자 PowerShell에서 실행한다. 별도로 준비한 `Prepare-WindowsNetwork.ps1`은 변경 전 상태 기록을 추가하며, 실행 정책이 해당 로컬 스크립트를 허용하는 관리자 PowerShell 환경에서 사용한다. 두 방식 모두 기존 허용 규칙은 유지한다.
3. 실제 NAS가 Tailscale에 연결된 후 허용 장치·NAS 방화벽·SMB 접근을 함께 확인한다.

```powershell
# 관리자 PowerShell에서 실행
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
Get-NetFirewallProfile | Select-Object Name,Enabled
```

방화벽 보호를 확인하기 전 PC에 외부 접속용 포트를 추가하지 않는다. 이번 Docker 포트는 loopback으로 제한했고 인터넷 터널은 생성하지 않았다. 실제 LAN의 다른 장치에서 접근 차단을 확인하는 시험은 아직 하지 않았다.

## NAS로 옮길 때

사용 용도는 **개인 파일 클라우드 + 개발 서버 + 공개 웹사이트**다. 개인 자료와 공개 웹 서비스를 아래처럼 분리한다.

| 경로 | 용도 | 연결 |
|---|---|---|
| `AI-Workspace` 공유 | Codex·Claude 작업과 생성물 | PC에서 W: 연결, 외부에서는 Tailscale |
| 개인 개발 프로젝트 | 시험 앱·API | Tailscale 및 앱 인증 |
| `cloud/public` 프로젝트 | 누구나 보는 웹사이트 | 도메인 → Cloudflare Tunnel → public-web |
| NAS 보호 경로 | 터널 토큰 등 비밀값 | 공개 공유·OneDrive·소스 저장소 밖에 보관 |

NAS 작업은 다음 순서로 수행한다.

1. 디스크 수량을 확인하고 스토리지 풀·볼륨·DSM을 초기 설정한다. RAID/SHR 구성은 실제 디스크 수량을 확인한 뒤 결정한다.
2. 사용자 계정·2단계 인증·권한·방화벽과 `AI-Workspace` 공유를 구성한다.
3. Tailscale 및 Container Manager를 설치하고 DSM에서 네트워크·이미지·마운트·자원 제한을 재검증한다.
4. `Connect-NasWorkspace.ps1`로 W: 연결을 시험하고 Codex/Claude에서 실제 읽기·쓰기·파일 잠금 동작을 확인한다.
5. 공개 도메인과 실제 앱을 정하고 공개용 콘텐츠·인증·DB·복구 정책을 구성한다.
6. 배포할 주소와 콘텐츠 및 검증 결과를 검토한 뒤, 사용자 운영 반영 승인 후 공개 터널을 연결한다.

현재 공개 웹은 `/healthz`만 200, 나머지는 ‘준비 중’ 503을 돌려주는 기반 구성이다. 실제 홈페이지, 로그인 앱, Nextcloud, DB 등의 업무 서비스는 아직 설치하지 않았다. 개인 파일 서비스는 Synology 기능을 우선 활용하고 앱·DB는 실제 필요에 맞춰 추가한다.

PC의 공개 웹 시험은 원본 Compose에서 `public-web`만 실행한다. `TUNNEL_TOKEN_FILE=/dev/null`은 이 시험의 변수 해석용 경로이며 실제 토큰이 아니다. cloudflared에는 이 경로로 연결을 시도하지 않았다.

## 검증과 판정

- 런타임 검사: **29/29 통과**. Engine·Compose, 두 웹 컨테이너 Healthy, Nginx 설정, 실제 HTTP, 비root·읽기 전용·권한·자원 제한, 마운트, 내부 네트워크와 cloudflared 실행을 확인했다.
- 사설 Compose 정적 검사: 7개 통과. 공개 Compose 정적 검사: 11개 통과.
- PowerShell 관리 스크립트 구문 검사와 Start → Stop → Start → Status 동작을 시험했다.
- 첫 Windows 접속 시험은 연결 거부가 발생했다. WSL 유지 프로세스와 시작 대기를 추가한 이후 Windows의 200/404 응답을 확인했다. 초기 실패의 단일 원인은 확정하지 않았다.
- 앱 내 브라우저 자동 미리보기 시도는 시간 초과로 화면 확인을 완료하지 못했다. Windows HTTP 접속 검사는 실제 통과했으며, 브라우저 화면의 수동 확인은 남아 있다.
- 현재 판정: **PC의 Docker 준비는 검증 통과. NAS 실제 구성과 인터넷 운영 배포는 보류.** 독립된 외부 평가나 침투 시험을 수행한 결과는 아니다.
- NAS 실기, 원격 SMB, Tailscale 장치 간 연결, 공개 HTTPS·도메인, LAN 접근 차단, 재부팅 후 운영 복구·성능·백업은 미검증이다.

근거 파일: `cloud/validation/runtime-result.json`, `cloud/validation/result.json`, `cloud/public/validation-result.json`, `NAS-준비-검증.json`.

진행 방식은 작은 구성부터 실행·검증하는 DevSecOps 절차를 적용했다. 이번에는 설정 → 설치 → 로컬 실행 → 기능/권한 검사 → 운영 스크립트 확인까지 완료했다. NAS 도착·Tailscale 로그인·도메인/앱 확정이 다음 단계의 입력이다. 지정된 공통 연구원칙 파일은 경로에 없어 읽지 못했으며, 본 설정은 실제 실행 결과와 공급사 공식 문서를 근거로 진행했다.

## 원복과 운영

- 실행을 멈출 때는 `NasCloud.cmd Stop`을 사용한다. `docker system prune`, 볼륨 삭제, Ubuntu 삭제 명령은 사용하지 않는다.
- 설치한 Docker 패키지와 다운로드한 이미지는 중지 후에도 남는다. 완전 제거가 필요하면 기존 Ubuntu의 다른 사용 여부를 확인한 뒤 별도로 수행한다.
- 웹 컨테이너는 각각 메모리 128MiB·CPU 0.5·PID 64 상한과 로그 순환을 적용했다. 이는 초기 시험값이며 실제 앱의 수용량을 보장하지 않는다.
- 이 PC를 상시 서버로 운영하는 설정은 아니다. PC 종료·절전·WSL 종료 시 점검 서비스가 중단될 수 있다.
- 원격 접속이 실패하면 외부 포트를 무작정 열지 않고 Tailscale 상태, NAS 권한, 방화벽 순서로 확인한다.

## 공식 자료

- [Docker Ubuntu 설치](https://docs.docker.com/engine/install/ubuntu/)
- [Docker 게시 포트 동작](https://docs.docker.com/engine/network/port-publishing/)
- [Tailscale Synology 설치](https://tailscale.com/docs/integrations/synology)
- [Cloudflare Tunnel 시작](https://developers.cloudflare.com/tunnel/get-started/)
- [공개 웹 운영 설계](NAS-공개웹-운영설계.md)
- [NAS 작업공간 준비](NAS-AI-작업공간-준비.md)

## 공개 저장소 범위

설정·관리 스크립트와 일반화한 사용 안내 및 검증 결과를 제공한다. PC의 내부 IP·개인 경로·상세 보안 상태가 담긴 사전점검 원본과 공개 전 문서 원본은 로컬에 보관하고 Git에서 제외한다. 설치 실행 파일, 실제 .env, 비밀키, 인증서 개인키, 터널 토큰도 포함하지 않는다. 과거 실행 결과는 문서의 기준일에 대한 기록이며 현재 서버 가동을 보장하지 않는다.

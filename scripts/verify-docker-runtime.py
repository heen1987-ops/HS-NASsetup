"""준비용 두 Docker 프로젝트만 검사한다. 터널 연결 및 인터넷 공개는 수행하지 않는다."""
import datetime
import json
from pathlib import Path
import subprocess
import sys

BASE = Path(__file__).resolve().parents[1]
PRIVATE = 'nas-cloud-local-cloud-probe-1'
PUBLIC = 'nas-public-check-public-web-1'
IMAGE = 'cloudflare/cloudflared@sha256:9b49eed8f62806d5d45ddf59ecefb5710429598ea6d3fcccd2af938f621b2b07'
checks = []


def run(args):
    return subprocess.run(args, capture_output=True, encoding='utf-8', errors='replace', timeout=30)


def docker(*args):
    return run(['wsl', '-d', 'Ubuntu', '-u', 'root', '--', 'docker', *args])


def check(name, passed, evidence=''):
    checks.append({'항목': name, '통과': bool(passed), '근거': evidence})


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    version = docker('version', '--format', '{{.Server.Version}}')
    compose = docker('compose', 'version')
    check('Docker Engine 응답', version.returncode == 0, version.stdout.strip())
    check('Docker Compose 실행', compose.returncode == 0, compose.stdout.strip())

    for name, label in [(PRIVATE, '사설 점검'), (PUBLIC, '공개 웹 내부 시험')]:
        result = docker('inspect', name)
        if result.returncode:
            check(label + ' 컨테이너 존재', False, result.stderr.strip())
            continue
        container = json.loads(result.stdout)[0]
        state, host = container['State'], container['HostConfig']
        check(label + ' 실행 및 Healthy', state['Running'] and state.get('Health', {}).get('Status') == 'healthy')
        check(label + ' 비root UID 설정', container['Config']['User'] == '101:101')
        check(label + ' 읽기 전용 루트', host['ReadonlyRootfs'])
        check(label + ' 권한 제한', host['CapDrop'] == ['ALL'] and 'no-new-privileges:true' in host['SecurityOpt'] and not host['Privileged'])
        check(label + ' 자원 제한', host['Memory'] == 128 * 1024 * 1024 and host['NanoCpus'] == 500000000 and host['PidsLimit'] == 64)
        mounts = [m for m in container['Mounts'] if m['Type'] == 'bind']
        check(label + ' 설정 파일만 읽기 전용 마운트', len(mounts) == 1 and mounts[0]['Destination'] == '/etc/nginx/nginx.conf' and not mounts[0]['RW'])
        ports = host.get('PortBindings') or {}
        if name == PRIVATE:
            check('사설 점검 포트는 loopback 전용', ports == {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '18080'}]})
        else:
            check('공개 웹의 호스트 게시 포트 없음', not ports)
            check('공개 웹은 전용 네트워크 하나만 사용', set(container['NetworkSettings']['Networks']) == {'nas-public-check_web-origin'})
        result = docker('exec', name, 'nginx', '-t')
        check(label + ' Nginx 설정 검사', result.returncode == 0, result.stderr.strip())
        result = docker('exec', name, 'wget', '-qO-', 'http://127.0.0.1:8080/healthz')
        check(label + ' healthz 실제 응답', result.returncode == 0 and json.loads(result.stdout or '{}').get('status') == 'ok')

    result = docker('network', 'inspect', 'nas-public-check_web-origin')
    check('공개 웹 네트워크 internal 적용', result.returncode == 0 and json.loads(result.stdout)[0]['Internal'])
    result = docker('exec', PUBLIC, 'wget', '-S', '-O', '/dev/null', 'http://public-web:8080/')
    check('준비 중 공개 웹은 DNS 이름으로 접속 시 503', result.returncode != 0 and '503 Service' in result.stderr)
    result = docker('ps', '--all', '--filter', 'label=com.docker.compose.project=nas-public-check', '--filter', 'label=com.docker.compose.service=cloudflared', '--format', '{{.ID}}')
    check('실제 cloudflared 터널 컨테이너 없음', result.returncode == 0 and not result.stdout.strip())

    for path, expected in [('/healthz', '200'), ('/', '200'), ('/does-not-exist', '404')]:
        result = run(['curl.exe', '--noproxy', '*', '--silent', '--show-error', '--output', 'NUL', '--write-out', '%{http_code}', '--max-time', '10', 'http://127.0.0.1:18080' + path])
        check('Windows HTTP ' + path, result.returncode == 0 and result.stdout == expected, '상태 ' + result.stdout)

    result = docker('run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--memory', '256m', '--pids-limit', '64', '--user', '65532:65532', IMAGE, 'version')
    check('cloudflared 네트워크 없이 실행', result.returncode == 0, result.stdout.strip())
    result = docker('run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--memory', '256m', '--pids-limit', '64', '--user', '65532:65532', IMAGE, 'tunnel', 'run', '--help')
    check('cloudflared token-file 지원', result.returncode == 0 and '--token-file' in result.stdout + result.stderr)

    report = {'검사시각': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              '환경': '이 PC의 Ubuntu WSL2. 실제 Synology NAS 검증 아님.',
              '검사': checks, '통과수': sum(c['통과'] for c in checks), '전체수': len(checks),
              'NAS실기검증': '미실행: NAS 배송 전', '인터넷공개': '미실행: 도메인 및 터널 없음'}
    destination = BASE / 'cloud/validation/runtime-result.json'
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if all(c['통과'] for c in checks) else 1


if __name__ == '__main__':
    raise SystemExit(main())

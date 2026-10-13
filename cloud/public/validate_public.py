"""공개 사이트 초안의 정적 검사. 터널·DNS·컨테이너를 실행하지 않는다."""
from copy import deepcopy
import json
from pathlib import Path
import sys

import jsonschema
import yaml

BASE = Path(__file__).resolve().parent
SCHEMA = json.loads((BASE.parent / "validation/compose-spec.schema.json").read_text(encoding="utf-8-sig"))
SOURCES = json.loads((BASE / "validation-sources.json").read_text(encoding="utf-8"))


def validate(config):
    errors = [e.message for e in jsonschema.Draft7Validator(SCHEMA).iter_errors(config)]
    services = config.get("services", {})
    if set(services) != {"public-web", "cloudflared"}:
        return errors + ["공개 웹 점검 서비스와 터널만 허용합니다."]
    for name, service in services.items():
        for forbidden in ("ports", "privileged", "network_mode", "pid", "devices", "cap_add"):
            if forbidden in service:
                errors.append(f"{name}: 공개 포트 또는 권한 확대 설정 금지: {forbidden}")
        if service.get("read_only") is not True or service.get("cap_drop") != ["ALL"]:
            errors.append(f"{name}: 읽기 전용·capability 제거 조건 필요")
        if service.get("security_opt") != ["no-new-privileges:true"]:
            errors.append(f"{name}: 권한 상승 방지 조건 필요")
        if service.get("platform") != "linux/amd64":
            errors.append(f"{name}: 대상 플랫폼 불일치")
        if not service.get("mem_limit") or not service.get("pids_limit"):
            errors.append(f"{name}: 자원 제한 필요")
    web = services["public-web"]
    tunnel = services["cloudflared"]
    if web.get("image") != SOURCES["nginx_image"] or tunnel.get("image") != SOURCES["cloudflared_image"]:
        errors.append("검증한 이미지 digest가 변경되었습니다.")
    if web.get("user") != "101:101" or tunnel.get("user") != "65532:65532":
        errors.append("비관리자 실행 UID/GID가 변경되었습니다.")
    if web.get("networks") != ["web-origin"] or tunnel.get("networks") != ["tunnel-egress", "web-origin"]:
        errors.append("공개 웹과 터널의 네트워크 경계가 변경되었습니다.")
    expected_networks = {"tunnel-egress": {"driver": "bridge"},
                         "web-origin": {"driver": "bridge", "internal": True}}
    if config.get("networks") != expected_networks:
        errors.append("네트워크의 외부 연결·내부망 구성이 변경되었습니다.")
    mounts = [{"type": "bind", "source": "./nginx.conf", "target": "/etc/nginx/nginx.conf", "read_only": True}]
    if web.get("volumes") != mounts or tunnel.get("volumes"):
        errors.append("공개 컨테이너에 작업 폴더·소켓 등 추가 마운트를 허용하지 않습니다.")
    if web.get("secrets") or tunnel.get("secrets") != ["cloudflare_tunnel_token"]:
        errors.append("토큰은 터널에만 제공해야 합니다.")
    expected_command = ["tunnel", "--no-autoupdate", "run", "--token-file", "/run/secrets/cloudflare_tunnel_token"]
    if tunnel.get("command") != expected_command or tunnel.get("environment"):
        errors.append("터널 토큰은 명령 인수·환경변수 값이 아닌 파일로 전달해야 합니다.")
    secret_path = config.get("secrets", {}).get("cloudflare_tunnel_token", {}).get("file", "")
    if not secret_path.startswith("${TUNNEL_TOKEN_FILE:?"):
        errors.append("보호된 토큰 파일 경로를 필수 입력으로 받아야 합니다.")
    return errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    config = yaml.safe_load((BASE / "docker-compose.yml").read_text(encoding="utf-8"))
    errors = validate(config)
    checks = [{"항목": "공식 Compose 스키마·공개 영역 경계", "통과": not errors}]
    mutations = [
        ("NAS 호스트 포트 게시 거부", "public-web", "ports", ["8080:8080"]),
        ("개인 작업 폴더 연결 거부", "public-web", "volumes", ["/volume1/AI-Workspace:/data"]),
        ("공개 웹에 토큰 노출 거부", "public-web", "secrets", ["cloudflare_tunnel_token"]),
        ("토큰 환경변수 입력 거부", "cloudflared", "environment", {"TUNNEL_TOKEN": "dummy-test-value"}),
        ("터널 host 네트워크 거부", "cloudflared", "network_mode", "host"),
        ("웹 외부 네트워크 직접 연결 거부", "public-web", "networks", ["tunnel-egress"]),
        ("root 실행 거부", "public-web", "user", "0:0"),
    ]
    for title, service, field, value in mutations:
        changed = deepcopy(config)
        changed["services"][service][field] = value
        checks.append({"항목": title, "통과": bool(validate(changed))})
    changed = deepcopy(config)
    changed["networks"]["web-origin"]["internal"] = False
    checks.append({"항목": "내부 웹 네트워크 보호 해제 거부", "통과": bool(validate(changed))})
    checks.append({"항목": "nginx 설정·환경변수 예시 파일 존재",
                   "통과": (BASE / "nginx.conf").is_file() and (BASE / ".env.example").is_file()})
    route_plan = json.loads((BASE / "route-plan.example.json").read_text(encoding="utf-8"))
    checks.append({"항목": "공개 경로 초안은 웹 컨테이너와 나머지 404만 지정",
                   "통과": route_plan.get("ingress") == [
                       {"hostname": "www.example.com", "service": "http://public-web:8080"},
                       {"service": "http_status:404"}]})
    result = {"정적검사": checks, "설정오류": errors,
              "컨테이너실행": "미실행", "터널및DNS변경": "미실행",
              "한계": "원격 Cloudflare 경로, NAS ACL, 실제 런타임 격리는 별도 검증 필요"}
    (BASE / "validation-result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if all(check["통과"] for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())

"""접속 점검용 Compose의 정적 검사. Docker나 NAS에 접속하지 않는다."""
from copy import deepcopy
import json
from pathlib import Path
import sys

import jsonschema
import yaml

BASE = Path(__file__).resolve().parent
SCHEMA = json.loads((BASE / "validation/compose-spec.schema.json").read_text(encoding="utf-8-sig"))
SOURCE = json.loads((BASE / "validation/sources.json").read_text(encoding="utf-8-sig"))


def validate(config):
    errors = [e.message for e in jsonschema.Draft7Validator(SCHEMA).iter_errors(config)]
    services = config.get("services", {})
    if set(services) != {"cloud-probe"}:
        return errors + ["점검용 서비스 하나만 허용합니다. 실제 앱 추가 시 별도 검토가 필요합니다."]
    service = services["cloud-probe"]
    required = {
        "image": SOURCE["Image"] + "@" + SOURCE["IndexDigest"],
        "platform": "linux/amd64",
        "user": "101:101",
        "read_only": True,
        "ports": ["127.0.0.1:18080:8080"],
        "cap_drop": ["ALL"],
        "security_opt": ["no-new-privileges:true"],
        "mem_limit": "128m",
        "cpus": 0.5,
        "pids_limit": 64,
    }
    for field, expected in required.items():
        if service.get(field) != expected:
            errors.append(f"준비 구성의 보호 조건이 변경되었습니다: {field}")
    for forbidden in ("privileged", "network_mode", "pid", "devices", "cap_add"):
        if forbidden in service:
            errors.append(f"허용하지 않는 설정입니다: {forbidden}")
    expected_mounts = [{"type": "bind", "source": "./nginx.conf",
                        "target": "/etc/nginx/nginx.conf", "read_only": True}]
    if service.get("volumes") != expected_mounts:
        errors.append("점검 서비스는 nginx.conf 읽기 전용 마운트만 허용합니다.")
    if not service.get("healthcheck") or not service.get("logging", {}).get("options", {}).get("max-size"):
        errors.append("상태 확인 및 로그 크기 제한이 필요합니다.")
    return errors


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    config = yaml.safe_load((BASE / "docker-compose.yml").read_text(encoding="utf-8-sig"))
    failures = validate(config)
    checks = [{"항목": "공식 Compose 스키마와 준비 구성 보호 조건", "통과": not failures}]
    mutations = [
        ("전체 인터페이스 포트 공개 거부", "ports", ["18080:8080"]),
        ("특권 컨테이너 거부", "privileged", True),
        ("Docker 소켓 연결 거부", "volumes", ["/var/run/docker.sock:/var/run/docker.sock"]),
        ("변동 이미지 태그 거부", "image", "nginx:latest"),
        ("메모리 제한 해제 거부", "mem_limit", None),
    ]
    for title, field, value in mutations:
        changed = deepcopy(config)
        changed["services"]["cloud-probe"][field] = value
        checks.append({"항목": title, "통과": bool(validate(changed))})
    checks.append({"항목": "마운트할 nginx.conf 존재", "통과": (BASE / "nginx.conf").is_file()})
    result = {"정적검사": checks, "설정오류": failures,
              "컨테이너실행검증": "미실행: 이 검사기는 Docker 런타임을 실행하지 않음",
              "NAS검증": "미실행: 실제 장비 접속을 수행하지 않음"}
    (BASE / "validation/result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if all(check["통과"] for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())

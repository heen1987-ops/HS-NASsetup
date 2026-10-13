#!/usr/bin/env bash
set -euo pipefail

# 현재 Ubuntu WSL에 Docker 공식 저장소로 Engine·Compose를 설치합니다.
if [[ $(id -u) != 0 ]]; then
  echo 'WSL의 관리자 계정으로 실행해야 합니다.' >&2
  exit 1
fi
. /etc/os-release
if [[ "$ID" != ubuntu ]]; then
  echo '이 스크립트는 Ubuntu 전용입니다.' >&2
  exit 1
fi
for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
    echo "기존 패키지와의 영향 검토가 필요하여 중단합니다: $package" >&2
    exit 1
  fi
done

key_path=/etc/apt/keyrings/docker-nas.asc
source_path=/etc/apt/sources.list.d/docker-nas.sources
if [[ -e "$source_path" || -e "$key_path" ]]; then
  echo '이 준비 작업의 저장소 파일이 이미 있습니다. 재설치 대신 현재 설치 상태를 확인하세요.' >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg -o "$key_path"
chmod 0644 "$key_path"
cat > "$source_path" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: $key_path
EOF

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker version
docker compose version

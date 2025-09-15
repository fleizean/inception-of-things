#!/usr/bin/env bash
set -euxo pipefail

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }

: "${USE_INGRESS:=true}"
: "${CONFS_DIR:=/vagrant/confs}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release git unzip \
                   software-properties-common apt-transport-https jq

# Docker
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
else
  log "Docker zaten kurulu."
fi

# vagrant kullanıcısına docker erişimi
usermod -aG docker vagrant || true

# kubectl (stable)
if ! command -v kubectl >/dev/null 2>&1; then
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  chmod 0755 /usr/local/bin/kubectl
fi

# k3d
if ! command -v k3d >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# argocd cli
if ! command -v argocd >/dev/null 2>&1; then
  ARGOCD_VERSION="$(curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest \
    | grep -oE '\"tag_name\":\s*\"v[^"]+' | cut -d\" -f4)"
  curl -fsSLo /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x /usr/local/bin/argocd
fi

log "install.sh tamam"

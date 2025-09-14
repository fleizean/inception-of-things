#!/usr/bin/env bash
set -euo pipefail

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "[INFO] Sistem güncelleniyor..."
$SUDO apt-get update -y

echo "[INFO] Gerekli paketler kuruluyor..."
$SUDO apt-get install -y \
    ca-certificates \
    curl \
    git \
    docker.io \
    jq

echo "[INFO] Docker yapılandırılıyor..."
$SUDO systemctl enable --now docker
$SUDO usermod -aG docker vagrant || true

echo "[INFO] kubectl kuruluyor..."
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$SUDO install -m0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

echo "[INFO] k3d kuruluyor..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "[INFO] ArgoCD CLI kuruluyor..."
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
$SUDO install -m 755 argocd /usr/local/bin/argocd
rm -f argocd

# Bash completion
echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
echo 'alias k=kubectl' >> /home/vagrant/.bashrc

echo "[SUCCESS] Kurulum tamamlandı!"
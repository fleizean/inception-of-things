#!/bin/sh
set -e

echo "[INFO] Alpine paket sistemi güncelleniyor..."
apk update

echo "[INFO] Gerekli paketler kuruluyor..."
apk add --no-cache \
    curl \
    git \
    docker \
    docker-compose \
    bash \
    jq \
    ca-certificates \
    openrc

echo "[INFO] Docker servisi yapılandırılıyor..."
rc-update add docker boot
service docker start

# Vagrant kullanıcısını docker grubuna ekle
adduser vagrant docker

echo "[INFO] kubectl kuruluyor..."
KUBECTL_VERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r .tag_name)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

echo "[INFO] k3d kuruluyor..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "[INFO] ArgoCD CLI kuruluyor..."
ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r .tag_name)
curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
install -m 755 argocd /usr/local/bin/argocd
rm -f argocd

# Bash completion ve alias'lar
echo 'source <(kubectl completion bash)' >> /home/vagrant/.bashrc
echo 'alias k=kubectl' >> /home/vagrant/.bashrc

# Docker servisinin çalıştığından emin ol
while ! docker info >/dev/null 2>&1; do
    echo "[WAIT] Docker servisinin başlaması bekleniyor..."
    sleep 2
done

echo "[SUCCESS] Kurulum tamamlandı!"
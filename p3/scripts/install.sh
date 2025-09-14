#!/usr/bin/env bash
set -euo pipefail

# Root değilsek sudo gerekli
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

$SUDO apt-get update -y
$SUDO apt-get install -y ca-certificates curl git docker.io

# Docker
$SUDO systemctl enable --now docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$SUDO install -m0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo ">>> install.sh tamam."

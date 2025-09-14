#!/usr/bin/env bash
set -euo pipefail

# k3d cluster: VM içinde LB 80 -> VM localhost:8888
k3d cluster create iot --servers 1 --agents 1 -p "8888:80@loadbalancer"

# Namespace'ler
kubectl create namespace argocd || true
kubectl create namespace dev || true

# Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Biraz bekleyip pod durumu göster (opsiyonel)
sleep 10
kubectl -n argocd get pods

# Argo CD Application (senkronize klasör /vagrant'tan)
kubectl apply -f /vagrant/confs/application.yaml

echo ">>> setup.sh tamam. Test için: curl http://localhost:8888 (host makineden)."

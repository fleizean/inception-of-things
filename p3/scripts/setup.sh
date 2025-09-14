#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="iot"

echo "[INFO] k3d cluster oluşturuluyor..."
k3d cluster delete $CLUSTER_NAME 2>/dev/null || true

k3d cluster create $CLUSTER_NAME \
    --servers 1 \
    --agents 1 \
    --port "8888:80@loadbalancer" \
    --api-port 6443 \
    --wait

echo "[SUCCESS] Cluster hazır"
kubectl get nodes

echo "[INFO] Namespace'ler oluşturuluyor..."
kubectl create namespace argocd || true
kubectl create namespace dev || true

echo "[INFO] ArgoCD kuruluyor..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "[INFO] ArgoCD bekleniyor..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "[INFO] ArgoCD NodePort yapılandırılıyor..."
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'

echo "[INFO] ArgoCD Application oluşturuluyor..."
kubectl apply -f /vagrant/confs/application.yaml

# Admin şifresi
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "admin")

echo ""
echo "=============== KURULUM TAMAMLANDI ==============="
echo "ArgoCD URL: http://localhost:30080"
echo "Kullanıcı: admin"
echo "Şifre: $ARGOCD_PASSWORD"
echo "Test: curl http://localhost:8888"
echo "=============================================="
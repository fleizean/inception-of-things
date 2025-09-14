#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot"

echo "[INFO] k3d cluster oluşturuluyor..."
k3d cluster delete $CLUSTER_NAME 2>/dev/null || true

k3d cluster create $CLUSTER_NAME \
    --servers 1 \
    --agents 1 \
    --port "8888:80@loadbalancer" \
    --port "30080:30080@loadbalancer" \
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
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "[INFO] ArgoCD NodePort yapılandırılıyor..."
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080,"targetPort":8080}]}}'

echo "[INFO] ArgoCD Application oluşturuluyor..."
kubectl apply -f /vagrant/confs/application.yaml

# Admin şifresi alma
echo "[INFO] ArgoCD admin şifresi alınıyor..."
sleep 10  # Secret'ın oluşması için bekle
ARGOCD_PASSWORD=""
for i in {1..30}; do
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [ -n "$ARGOCD_PASSWORD" ]; then
        break
    fi
    echo "[WAIT] Admin secret bekleniyor... ($i/30)"
    sleep 5
done

if [ -z "$ARGOCD_PASSWORD" ]; then
    ARGOCD_PASSWORD="admin"
    echo "[WARN] Admin secret alınamadı, varsayılan şifre kullanılacak"
fi

echo ""
echo "=============== KURULUM TAMAMLANDI ==============="
echo "VM IP: 192.168.56.110"
echo "ArgoCD URL: http://192.168.56.110:30080"
echo "Test App URL: http://192.168.56.110:8888"
echo "Kullanıcı: admin"
echo "Şifre: $ARGOCD_PASSWORD"
echo ""
echo "Alternatif Erişim (Port Forward):"
echo "ArgoCD: http://localhost:30080"
echo "Test App: http://localhost:8888"
echo "=============================================="

# Test için basic service deploy et
echo "[INFO] Test servisi deploy ediliyor..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: test-app
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-app
  namespace: dev
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
EOF

echo "[SUCCESS] Test servisi deploy edildi!"
echo "ArgoCD'de 'playground' aplikasyonunu kontrol edebilirsiniz."
#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot"

echo "[INFO] Docker sistem temizliği..."
docker system prune -f
docker network prune -f

echo "[INFO] Eski k3d cluster'ları temizleniyor..."
k3d cluster delete $CLUSTER_NAME 2>/dev/null || true

# Daha basit konfigürasyon - registry olmadan
echo "[INFO] k3d cluster oluşturuluyor (basit konfigürasyon)..."
k3d cluster create $CLUSTER_NAME \
    --servers 1 \
    --agents 1 \
    --port "8888:80@loadbalancer" \
    --port "30080:30080@loadbalancer" \
    --wait \
    --timeout 300s

echo "[SUCCESS] Cluster oluşturuldu!"

# Kubeconfig ayarla
export KUBECONFIG="$(k3d kubeconfig write $CLUSTER_NAME)"

echo "[INFO] Node durumu kontrol ediliyor..."
kubectl get nodes

# Node'ların hazır olmasını bekle
echo "[INFO] Node'ların Ready durumuna gelmesi bekleniyor..."
for i in {1..30}; do
    if kubectl get nodes | grep -q " Ready "; then
        echo "[SUCCESS] Node'lar hazır!"
        break
    fi
    echo "[WAIT] Node'lar henüz hazır değil... ($i/30)"
    sleep 10
done

kubectl get nodes -o wide

echo "[INFO] Namespace'ler oluşturuluyor..."
kubectl create namespace argocd 2>/dev/null || echo "argocd namespace zaten var"
kubectl create namespace dev 2>/dev/null || echo "dev namespace zaten var"

echo "[INFO] ArgoCD kuruluyor..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "[INFO] ArgoCD deploymentların hazır olması bekleniyor..."
sleep 30  # Başlangıç için bekle

# ArgoCD server'ın hazır olmasını bekle
for i in {1..60}; do
    if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        if kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
            echo "[SUCCESS] ArgoCD server hazır!"
            break
        fi
    fi
    echo "[WAIT] ArgoCD server bekleniyor... ($i/60)"
    sleep 10
    
    # Debug bilgisi
    if [ $((i % 6)) -eq 0 ]; then
        echo "[DEBUG] ArgoCD pod durumu:"
        kubectl get pods -n argocd | head -5
    fi
done

echo "[INFO] ArgoCD servis konfigürasyonu..."
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080,"targetPort":8080}]}}'

echo "[INFO] ArgoCD admin şifresi alınıyor..."
sleep 10
ARGOCD_PASSWORD=""
for i in {1..20}; do
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [ -n "$ARGOCD_PASSWORD" ]; then
        break
    fi
    echo "[WAIT] Admin secret bekleniyor... ($i/20)"
    sleep 5
done

if [ -z "$ARGOCD_PASSWORD" ]; then
    ARGOCD_PASSWORD="admin"
    echo "[WARN] Admin secret alınamadı, varsayılan şifre: admin"
fi

echo "[INFO] Test aplikasyonu deploy ediliyor..."
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
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
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
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-app
  namespace: dev
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app
            port:
              number: 80
EOF

sleep 15

echo ""
echo "=============== KURULUM TAMAMLANDI ==============="
echo ""
echo "🌐 Erişim Bilgileri:"
echo "   ArgoCD UI: http://192.168.56.110:30080"
echo "   Test App:  http://192.168.56.110:8888"
echo ""
echo "🔐 ArgoCD Giriş:"
echo "   Kullanıcı: admin"
echo "   Şifre:     $ARGOCD_PASSWORD"
echo ""
echo "🔧 Test Komutları:"
echo "   curl http://192.168.56.110:8888"
echo "   kubectl get all -n dev"
echo "   kubectl get all -n argocd"
echo ""
echo "==============================================="

# Son durum kontrol
echo ""
echo "📊 Cluster Durumu:"
kubectl get nodes
echo ""
echo "📊 Namespace Durumu:"
kubectl get pods --all-namespaces | grep -v kube-system
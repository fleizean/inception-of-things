#!/bin/bash
set -e

echo "==> Paket listeleri güncelleniyor..."
sudo apt-get update -y

echo "==> Gerekli paketler kuruluyor..."
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  unzip \
  software-properties-common \
  apt-transport-https

################################################################################
# Docker installation - Ubuntu için düzeltildi
################################################################################
if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Eski Docker depo dosyaları temizleniyor..."
  sudo rm -f /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/docker.gpg

  echo "[SETUP] Docker container motoru kuruluma başlıyor..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "[SERVICE] Docker hizmeti etkinleştiriliyor..."
  sudo systemctl enable docker
  sudo systemctl start docker
  
  # Kullanıcıyı docker grubuna ekle
  sudo usermod -aG docker $USER
  echo "[SUCCESS] Kullanıcı Docker grubuna başarıyla eklendi."
else
  echo "[SKIP] Docker zaten mevcut, kurulum atlanıyor."
fi

# Docker grup değişikliğini aktif etmek için
echo "[CHECK] Docker kullanıcı izinleri kontrol ediliyor..."
sudo usermod -aG docker $USER

# Docker permission'ını test et
if ! docker ps >/dev/null 2>&1; then
  echo "[WARN] Docker yönetici izni gerekiyor, sudo kullanılacak..."
  DOCKER_CMD="sudo docker"
  K3D_CMD="sudo k3d"
else
  echo "[OK] Docker kullanıcı erişimi başarılı."
  DOCKER_CMD="docker"
  K3D_CMD="k3d"
fi

# Docker pull işlemleri
echo "[DOWNLOAD] Container imajları indiriliyor..."
$DOCKER_CMD pull argoproj/argocd || true
$DOCKER_CMD pull ghcr.io/dexidp/dex || true

################################################################################
# kubectl installation
################################################################################
if ! command -v kubectl >/dev/null 2>&1; then
  echo "[DOWNLOAD] Kubernetes CLI aracı indiriliyor..."
  curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
else
  echo "[SKIP] kubectl zaten kurulu, geçiliyor."
fi

################################################################################
# k3d installation
################################################################################
if ! command -v k3d >/dev/null 2>&1; then
  echo "[SETUP] k3d cluster yöneticisi kuruluyor..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "[SKIP] k3d zaten mevcut."
fi

################################################################################
# ArgoCD CLI installation
################################################################################
if ! command -v argocd >/dev/null 2>&1; then
  echo "[DOWNLOAD] ArgoCD komut satırı aracı indiriliyor..."
  ARGOCD_VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x argocd
  sudo mv argocd /usr/local/bin/
else
  echo "[SKIP] ArgoCD CLI mevcut."
fi

################################################################################
# K3d cluster installation - Docker permission fix ile
################################################################################
CLUSTER_NAME="p3-cluster"

# Mevcut cluster'ı kontrol et ve sil
if $K3D_CMD cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  echo "[CLEANUP] Var olan $CLUSTER_NAME kümesi temizleniyor..."
  $K3D_CMD cluster delete "$CLUSTER_NAME"
fi

echo "[CREATE] $CLUSTER_NAME Kubernetes kümesi oluşturuluyor..."
$K3D_CMD cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents 0 \
  --api-port 6550 \
  --port '8082:80@loadbalancer' \
  --port '30080:30080@server:0' \
  --wait

echo "[CONFIG] Cluster bağlantı ayarları yapılandırılıyor..."
mkdir -p "$HOME/.kube"
$K3D_CMD kubeconfig get "$CLUSTER_NAME" > "$HOME/.kube/config"
sudo chown $USER:$USER "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

echo "[STATUS] Cluster node durumu:"
kubectl get nodes

echo "[NAMESPACE] ArgoCD çalışma alanı oluşturuluyor..."
kubectl create namespace argocd

echo "[DEPLOY] ArgoCD uygulaması kümeye yükleniyor..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "[WAIT] ArgoCD servislerinin hazır olması bekleniyor..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# ArgoCD server'ı insecure modda çalıştır (HTTP için)
echo "[CONFIG] ArgoCD HTTP erişimi için yapılandırılıyor..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd

echo "[DEPLOY] Uygulama deploymentları uygulanıyor..."
kubectl apply -f ../confs/app-deployment.yaml

echo "[DEPLOY] ArgoCD otomatik dağıtım kuralları uygulanıyor..."
kubectl apply -f ../confs/argocd-application.yaml

echo "[COMPLETE] Kurulum başarıyla tamamlandı!"
echo ""
echo "[ACCESS] Erişim bilgileri:"
echo "ArgoCD Yönetim Paneli: http://localhost:8080"
echo "Test Uygulaması: http://localhost:8888"
echo ""
echo "[AUTH] ArgoCD yönetici şifresi:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "[NETWORK] Port yönlendirmeleri başlatılıyor..."
echo "ArgoCD panel erişimi aktifleştiriliyor..."
kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
echo "Test uygulaması erişimi aktifleştiriliyor..."
kubectl port-forward svc/playground-svc -n dev 8888:80 >/dev/null 2>&1 &

echo ""
echo "[READY] Tüm servisler aktif!"
echo "ArgoCD: http://localhost:8080"
echo "Playground: http://localhost:8888"
echo ""
echo "Port yönlendirmelerini durdurmak için: sudo pkill -f 'kubectl port-forward'"
echo ""
echo "[INFO] Sistem hazır, geliştirmeye başlayabilirsiniz!"
#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# IoT p3 - k3d + Argo CD kurulum scripti (güvenli/idempotent)
# Özelleştirilebilir:
#  USE_INGRESS=true|false, CLUSTER_NAME, KUBECTL_VER, ARGOCD_CLI_VER, DOCKER_CHANNEL
###############################################################################

: "${USE_INGRESS:=true}"
: "${CLUSTER_NAME:=p3-cluster}"
: "${KUBECTL_VER:=v1.30.5}"
: "${ARGOCD_CLI_VER:=v2.11.3}"
: "${DOCKER_CHANNEL:=stable}"

LB_HTTP_HOST_PORT=30080
APP_FWD_LOCAL_PORT=8888
APP_SVC_PORT=80
APP_TGT_PORT=8888
K3D_API_PORT=6550

# Yol çözümü -> /vagrant/confs veya script konumu/../confs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFS_DIR="${REPO_ROOT}/confs"

log()   { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn()  { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err()   { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
trap 'err "Bir hata oluştu (satır: $LINENO)"; exit 1' ERR

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' gerekli ama bulunamadı."; }
require_files() { for f in "$@"; do [[ -f "$f" ]] || die "Gerekli dosya yok: $f"; done; }

log "Paket listeleri güncelleniyor..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y

log "Gerekli paketler kuruluyor..."
sudo apt-get install -y \
  ca-certificates curl gnupg lsb-release git unzip software-properties-common \
  apt-transport-https jq  # <- test.sh için gerekli

# Docker
if ! command -v docker >/dev/null 2>&1; then
  log "Docker kurulumu başlıyor..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  codename="$(lsb_release -cs)"; arch="$(dpkg --print-architecture)"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${codename} ${DOCKER_CHANNEL}" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
else
  log "Docker zaten yüklü."
fi

# Hızlandırma amaçlı image pull (opsiyonel)
log "Kritik imajlar çekiliyor (opsiyonel)..."
docker pull argoproj/argocd:latest || true
docker pull ghcr.io/dexidp/dex:latest || true
docker pull docker.io/wil42/playground:v1 || true
docker pull docker.io/wil42/playground:v2 || true

# kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  log "kubectl ${KUBECTL_VER} indiriliyor..."
  tmp="$(mktemp)"
  curl -fsSLo "$tmp" "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
  chmod +x "$tmp"
  file "$tmp" | grep -qi 'executable' || die "kubectl dosyası yürütülebilir görünmüyor."
  sudo mv "$tmp" /usr/local/bin/kubectl
else
  log "kubectl zaten kurulu: $(kubectl version --client=true --output=yaml | head -n 1 || true)"
fi

# k3d
if ! command -v k3d >/dev/null 2>&1; then
  log "k3d kuruluyor..."
  tmp="$(mktemp)"
  curl -fsSLo "$tmp" https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh
  grep -q 'k3d' "$tmp" || die "k3d installer beklenen içeriği taşımıyor."
  chmod +x "$tmp"
  sudo "$tmp"
  rm -f "$tmp"
else
  log "k3d zaten kurulu: $(k3d version | tr -s ' ')"
fi

# argocd cli
if ! command -v argocd >/dev/null 2>&1; then
  log "Argo CD CLI ${ARGOCD_CLI_VER} indiriliyor..."
  tmp="$(mktemp)"
  curl -fsSLo "$tmp" "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VER}/argocd-linux-amd64"
  chmod +x "$tmp"
  file "$tmp" | grep -qi 'executable' || die "argocd dosyası yürütülebilir görünmüyor."
  sudo mv "$tmp" /usr/local/bin/argocd
else
  log "argocd zaten kurulu: $(argocd version --client 2>/dev/null || echo 'yüklü')"
fi

# cluster
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}\b"; then
  warn "${CLUSTER_NAME} zaten var. Yeniden kurulum için siliyorum..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

log "k3d cluster oluşturuluyor: ${CLUSTER_NAME}"
K3S_ARGS=()
if [[ "${USE_INGRESS}" != "true" ]]; then
  K3S_ARGS+=(--k3s-arg "--disable=traefik@server:0")
fi

k3d cluster create "${CLUSTER_NAME}" \
  --servers 1 \
  --agents 0 \
  --api-port "${K3D_API_PORT}" \
  --port "${LB_HTTP_HOST_PORT}:80@loadbalancer" \
  --wait \
  "${K3S_ARGS[@]}"

# kubeconfig
mkdir -p "$HOME/.kube"
k3d kubeconfig get "${CLUSTER_NAME}" > "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

log "Node durumu:"
kubectl get nodes -o wide

# namespaces + ArgoCD
log "Namespaces oluşturuluyor (argocd, dev)..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
kubectl get ns dev    >/dev/null 2>&1 || kubectl create namespace dev

log "Argo CD manifest uygulanıyor..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Argo CD bileşenleri hazırlanıyor..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s || true
kubectl -n argocd get pods -o wide

# Ingress (opsiyonel)
if [[ "${USE_INGRESS}" == "true" ]]; then
  log "Ingress kullanılacak. Manifest uygulanıyor."
  require_files "${CONFS_DIR}/argocd-server-ingress.yaml"
  kubectl apply -f "${CONFS_DIR}/argocd-server-ingress.yaml"
else
  warn "USE_INGRESS=false: Ingress atlandı. Argo CD için port-forward:"
  echo "  kubectl -n argocd port-forward svc/argocd-server 30080:80"
fi

# App + Application
require_files "${CONFS_DIR}/application.yaml"
log "Uygulama manifesti (dev) uygulanıyor..."
kubectl apply -f "${CONFS_DIR}/application.yaml"

log "Dev rollout bekleme..."
kubectl -n dev rollout status deploy/playground-app --timeout=120s || true
kubectl -n dev get all

# İlk şifre
log "Argo CD ilk admin şifresi:"
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true
  echo
else
  warn "Secret henüz oluşmamış olabilir; sonra deneyin:"
  echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
fi

log "Kurulum tamamlandı. k3d + Argo CD hazır."

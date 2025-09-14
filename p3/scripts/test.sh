#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# k3d + Argo CD ortam doğrulama (başarılıysa özet verir)
###############################################################################

: "${USE_INGRESS:=true}"
: "${CLUSTER_NAME:=p3-cluster}"
: "${K3D_API_PORT:=6550}"
: "${LB_HTTP_HOST_PORT:=30080}"
: "${APP_FWD_LOCAL_PORT:=8888}"
: "${APP_SVC_PORT:=80}"
: "${APP_TGT_PORT:=8888}"
: "${ARGO_APP_NAME:=my-app}"
: "${ARGO_NS:=argocd}"
: "${DEV_NS:=dev}"

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m[x] %s\033[0m\n" "$*" >&2; }
die()  { err "$*"; exit 1; }
trap 'err "Hata (satır $LINENO). Arka plan süreçleri temizleniyor."; cleanup' ERR INT TERM

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' gerekli ama yok."; }

PF_PIDS=()
cleanup() {
  if ((${#PF_PIDS[@]})); then
    for pid in "${PF_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
    done
  fi
}
finish_ok() { cleanup; exit 0; }

retry() {
  local tries=$1; shift
  local delay=$1; shift
  for ((i=1; i<=tries; i++)); do
    if "$@"; then return 0; fi
    sleep "$delay"
  done
  return 1
}

http_ok() {
  local url="$1"
  curl -fsS -m 5 -o /dev/null -w "%{http_code}" "$url" | grep -qE '^(200|30[12])$'
}

need_cmd docker
need_cmd k3d
need_cmd kubectl
need_cmd curl
need_cmd grep
need_cmd awk
need_cmd sed
need_cmd jq

log "Docker servis durumu kontrol..."
if ! (sudo systemctl is-active --quiet docker || docker info >/dev/null 2>&1); then
  die "Docker çalışmıyor görünüyor."
fi

log "Cluster kontrol: ${CLUSTER_NAME}"
if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}\b"; then
  die "Cluster bulunamadı: ${CLUSTER_NAME}"
fi

export KUBECONFIG="${HOME}/.kube/config"
[[ -f "$KUBECONFIG" ]] || die "~/.kube/config yok."
log "Aktif context: $(kubectl config current-context || echo 'bilinmiyor')"

log "Node'ların Ready olmasını bekliyorum..."
retry 30 3 bash -c 'kubectl get nodes --no-headers | awk "{print \$2}" | grep -q "^Ready$"' \
  || die "Node Ready olmadı."
kubectl get nodes -o wide

log "Namespace kontrolleri..."
kubectl get ns "${ARGO_NS}" >/dev/null 2>&1 || die "Namespace yok: ${ARGO_NS}"
kubectl get ns "${DEV_NS}"  >/dev/null 2>&1 || die "Namespace yok: ${DEV_NS}"

log "Argo CD rollout durumu..."
retry 30 4 kubectl -n "${ARGO_NS}" rollout status deploy/argocd-server >/dev/null 2>&1 || \
  warn "argocd-server rollout tamamlanmadı."
kubectl -n "${ARGO_NS}" get pods -o wide

ARGO_PWD="<unknown>"
if kubectl -n "${ARGO_NS}" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  ARGO_PWD="$(kubectl -n "${ARGO_NS}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true)"
fi

log "Application bekleniyor: ${ARGO_APP_NAME}"
retry 40 5 bash -c \
'kubectl -n "'"${ARGO_NS}"'" get application "'"${ARGO_APP_NAME}"'" -o json \
  | jq -e ".status.sync.status==\"Synced\" and .status.health.status==\"Healthy\"" >/dev/null' \
  || warn "Application Synced/Healthy olmadı (devam)."

APP_SYNC="$(kubectl -n "${ARGO_NS}" get application "${ARGO_APP_NAME}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo '-')"
APP_HEALTH="$(kubectl -n "${ARGO_NS}" get application "${ARGO_APP_NAME}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo '-')"

log "Dev deployment & service kontrol..."
retry 30 4 kubectl -n "${DEV_NS}" rollout status deploy/playground-app >/dev/null 2>&1 || \
  warn "playground-app rollout tamamlanmadı."
kubectl -n "${DEV_NS}" get deploy,svc,pods -l app=playground-app -o wide

log "Uygulama servis erişim testi (port-forward → localhost:${APP_FWD_LOCAL_PORT})"
kubectl -n "${DEV_NS}" port-forward svc/playground-svc "${APP_FWD_LOCAL_PORT}:${APP_SVC_PORT}" >/dev/null 2>&1 &
PF_PIDS+=($!)
sleep 2
retry 10 1 http_ok "http://127.0.0.1:${APP_FWD_LOCAL_PORT}/" \
  || die "Uygulama HTTP testi başarısız (localhost:${APP_FWD_LOCAL_PORT})."

ARGO_URL=""
if [[ "${USE_INGRESS}" == "true" ]]; then
  ARGO_URL="http://localhost:${LB_HTTP_HOST_PORT}/"
  log "ArgoCD UI (Ingress/LB) testi: ${ARGO_URL}"
  retry 20 3 http_ok "${ARGO_URL}" || warn "ArgoCD UI HTTP testi başarısız (Ingress)."
else
  log "ArgoCD UI port-forward testi (localhost:${LB_HTTP_HOST_PORT})"
  kubectl -n "${ARGO_NS}" port-forward svc/argocd-server "${LB_HTTP_HOST_PORT}:80" >/dev/null 2>&1 &
  PF_PIDS+=($!)
  sleep 2
  ARGO_URL="http://localhost:${LB_HTTP_HOST_PORT}/"
  retry 20 3 http_ok "${ARGO_URL}" || warn "ArgoCD UI HTTP testi başarısız (port-forward)."
fi

echo
echo "===================== ✅ ORTAM DOĞRULAMA BAŞARILI ====================="
echo "Cluster          : ${CLUSTER_NAME}"
echo "Kube Context     : $(kubectl config current-context || echo '-')"
echo "Nodes            :"
kubectl get nodes --no-headers | awk '{print "  - "$1" ("$2")"}'
echo
echo "Argo CD"
echo "  URL            : ${ARGO_URL}"
if [[ -n "${ARGO_PWD}" && "${ARGO_PWD}" != "<unknown>" ]]; then
  echo "  Admin kullanıcı: admin"
  echo "  İlk şifre      : ${ARGO_PWD}"
else
  echo "  İlk şifre      : (secret henüz oluşmamış olabilir)"
fi
echo "  Application    : ${ARGO_APP_NAME}"
echo "    Sync         : ${APP_SYNC}"
echo "    Health       : ${APP_HEALTH}"
echo
echo "Uygulama (dev)"
echo "  Service        : playground-svc.${DEV_NS} (port ${APP_SVC_PORT} → target ${APP_TGT_PORT})"
echo "  Local Test URL : http://127.0.0.1:${APP_FWD_LOCAL_PORT}/"
echo "======================================================================="
echo

finish_ok

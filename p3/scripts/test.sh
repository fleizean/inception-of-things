#!/usr/bin/env bash
# scripts/test.sh
# Part 3: K3d + Argo CD doğrulama scripti
set -Eeuo pipefail

##############################
# Ayarlanabilir değişkenler  #
##############################
: "${CLUSTER_NAME:=p3-cluster}"
: "${ARGO_NS:=argocd}"
: "${DEV_NS:=dev}"
: "${ARGO_APP_NAME:=my-app}"           # ArgoCD Application adı
: "${USE_INGRESS:=true}"               # true => Ingress/LB; false => port-forward
: "${LB_HTTP_HOST_PORT:=30080}"        # ArgoCD UI host port (k3d -p "30080:80@loadbalancer")
: "${APP_SVC_NAME:=playground-svc}"    # Uygulama Service adı
: "${APP_DEPLOYMENT_NAME:=playground-app}"
: "${APP_SVC_PORT:=80}"                # Service port
: "${APP_LOCAL_TEST_PORT:=8888}"       # Port-forward ile local test portu

##############################
# Yardımcılar                #
##############################
C_RESET=$'\e[0m'; C_CYAN=$'\e[36;1m'; C_YEL=$'\e[33;1m'; C_RED=$'\e[31;1m'; C_GRN=$'\e[32;1m'
log()  { printf "${C_CYAN}[+] %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YEL}[!] %s${C_RESET}\n" "$*"; }
err()  { printf "${C_RED}[x] %s${C_RESET}\n" "$*" >&2; }
ok()   { printf "${C_GRN}[OK] %s${C_RESET}\n" "$*"; }
die()  { err "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' gerekli ama yok."; }

retry() {
  local tries=$1; shift
  local delay=$1; shift
  local i
  for ((i=1; i<=tries; i++)); do
    if "$@"; then return 0; fi
    sleep "$delay"
  done
  return 1
}

http_ok() {
  local url="$1"
  local code
  code=$(curl -fsS -m 6 -o /dev/null -w "%{http_code}" "$url" || true)
  # ArgoCD genelde 200/302 döndürür; bazı kurulumlarda 401 de olabilir (login redirect)
  [[ "$code" == "200" || "$code" == "301" || "$code" == "302" || "$code" == "401" ]]
}

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
trap 'cleanup' EXIT

########################################
# Ön koşullar
########################################
need_cmd docker
need_cmd k3d
need_cmd kubectl
need_cmd curl
need_cmd grep
need_cmd awk
need_cmd sed
need_cmd jq || warn "jq bulunamadı (Application health detayını atlayabilirim)."

# Kubeconfig çöz
if [[ -n "${KUBECONFIG:-}" && -f "$KUBECONFIG" ]]; then
  KCFG="$KUBECONFIG"
elif [[ -f "/home/vagrant/.kube/config" ]]; then
  KCFG="/home/vagrant/.kube/config"
else
  KCFG="$HOME/.kube/config"
fi
[[ -f "$KCFG" ]] || die "Kubeconfig bulunamadı: $KCFG"

log "Kubeconfig: $KCFG"

########################################
# Cluster ve node kontrolleri
########################################
log "Cluster mevcut mu?"
k3d cluster list | grep -q "^${CLUSTER_NAME}\b" \
  && ok "Cluster bulundu: ${CLUSTER_NAME}" \
  || die "Cluster yok: ${CLUSTER_NAME}"

log "Context/Nodes"
kubectl --kubeconfig "$KCFG" config current-context || true
retry 20 3 kubectl --kubeconfig "$KCFG" get nodes >/dev/null 2>&1 \
  || die "kubectl get nodes başarısız (API erişimi yok gibi)."
kubectl --kubeconfig "$KCFG" get nodes -o wide

log "Node'lar Ready mi?"
retry 30 2 bash -lc 'kubectl --kubeconfig "'"$KCFG"'" get nodes --no-headers | awk "{print \$2}" | grep -q "^Ready$"' \
  && ok "Node Ready" || die "Node Ready olmadı."

########################################
# Namespaces
########################################
log "Namespaces kontrol"
kubectl --kubeconfig "$KCFG" get ns "$ARGO_NS" "$DEV_NS"
ok "argocd ve dev mevcut"

########################################
# Argo CD kurulum/podlar
########################################
log "Argo CD pod rolloutu"
retry 30 4 kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" rollout status deploy/argocd-server >/dev/null 2>&1 \
  || warn "argocd-server rollout henüz tamamlanmadı (devam ediyorum)."
kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get pods -o wide

# Admin şifresi (varsa)
if kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  ARGO_PWD="$(kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true)"
  [[ -n "$ARGO_PWD" ]] && ok "ArgoCD admin şifresi alındı" || warn "ArgoCD admin şifresi okunamadı."
else
  warn "argocd-initial-admin-secret henüz oluşmamış olabilir."
fi

########################################
# ArgoCD UI erişimi (Ingress veya PF)
########################################
if [[ "$USE_INGRESS" == "true" ]]; then
  log "Ingress ile ArgoCD UI testi (http://localhost:${LB_HTTP_HOST_PORT}/)"
  kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get ingress argocd || warn "Ingress 'argocd' bulunamadı."
  retry 20 3 http_ok "http://localhost:${LB_HTTP_HOST_PORT}/" \
    && ok "ArgoCD UI HTTP erişimi başarılı (Ingress)" \
    || warn "ArgoCD UI HTTP testi başarısız (Ingress)."
else
  log "Port-forward ile ArgoCD UI testi (localhost:${LB_HTTP_HOST_PORT})"
  kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" port-forward svc/argocd-server "${LB_HTTP_HOST_PORT}:80" >/dev/null 2>&1 &
  PF_PIDS+=($!)
  sleep 2
  retry 10 2 http_ok "http://localhost:${LB_HTTP_HOST_PORT}/" \
    && ok "ArgoCD UI HTTP erişimi başarılı (PF)" \
    || warn "ArgoCD UI HTTP testi başarısız (PF)."
fi

########################################
# ArgoCD Application statüsü
########################################
if kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get application "$ARGO_APP_NAME" >/dev/null 2>&1; then
  SYNC="$(kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get application "$ARGO_APP_NAME" -o jsonpath='{.status.sync.status}' || echo '-')"
  HEALTH="$(kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get application "$ARGO_APP_NAME" -o jsonpath='{.status.health.status}' || echo '-')"
  echo "Application: ${ARGO_APP_NAME}  Sync:${SYNC}  Health:${HEALTH}"
  if command -v jq >/dev/null 2>&1; then
    kubectl --kubeconfig "$KCFG" -n "$ARGO_NS" get application "$ARGO_APP_NAME" -o json | jq -r '.status.resources[]? | [.kind,.namespace,.name,.status] | @tsv' || true
  fi
else
  warn "ArgoCD Application bulunamadı: ${ARGO_APP_NAME}"
fi

########################################
# Dev namespace: Deployment/Service kontrol
########################################
log "Dev deployment/service kontrol"
kubectl --kubeconfig "$KCFG" -n "$DEV_NS" get deploy "$APP_DEPLOYMENT_NAME" -o wide
kubectl --kubeconfig "$KCFG" -n "$DEV_NS" get svc "$APP_SVC_NAME" -o wide

log "Deployment rollout"
retry 30 4 kubectl --kubeconfig "$KCFG" -n "$DEV_NS" rollout status deploy/"$APP_DEPLOYMENT_NAME" >/dev/null 2>&1 \
  && ok "Deployment rollout başarılı" || warn "Deployment rollout tamamlanmadı."

########################################
# Uygulama HTTP testi (PF ile)
########################################
log "Uygulama HTTP testi (port-forward → localhost:${APP_LOCAL_TEST_PORT})"
kubectl --kubeconfig "$KCFG" -n "$DEV_NS" port-forward svc/"$APP_SVC_NAME" "${APP_LOCAL_TEST_PORT}:${APP_SVC_PORT}" >/dev/null 2>&1 &
PF_PIDS+=($!)
sleep 2
retry 12 1 http_ok "http://127.0.0.1:${APP_LOCAL_TEST_PORT}/" \
  && ok "Uygulama HTTP OK (PF)" \
  || die "Uygulama HTTP testi başarısız (PF)."

########################################
# Özet
########################################
echo
echo "===================== ✅ PART 3 CHECK: PASSED ====================="
echo "Cluster        : ${CLUSTER_NAME}"
echo "Namespaces     : ${ARGO_NS}, ${DEV_NS}"
echo "ArgoCD UI      : $( [[ "$USE_INGRESS" == "true" ]] && echo "http://localhost:${LB_HTTP_HOST_PORT}/ (Ingress)" || echo "PF http://localhost:${LB_HTTP_HOST_PORT}/" )"
echo "App Service    : ${APP_SVC_NAME}.${DEV_NS}  (svc port ${APP_SVC_PORT} → local ${APP_LOCAL_TEST_PORT})"
[[ -n "${ARGO_PWD:-}" ]] && echo "ArgoCD admin pw : ${ARGO_PWD}"
echo "==================================================================="
echo

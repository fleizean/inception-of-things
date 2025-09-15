#!/usr/bin/env bash
set -euxo pipefail

log()  { printf "\033[1;36m[+] %s\033[0m\n" "$*"; }
: "${USE_INGRESS:=true}"
: "${CONFS_DIR:=/vagrant/confs}"
: "${CLUSTER_NAME:=p3-cluster}"

# Eski cluster’ı sil
k3d cluster delete "${CLUSTER_NAME}" || true

# Traefik AÇIK (Ingress kullanacağız)
k3d cluster create "${CLUSTER_NAME}" \
  --servers 1 \
  --agents 0 \
  --api-port 6550 \
  --port "30080:80@loadbalancer" \
  --wait

# kubeconfig (vagrant ve root)
mkdir -p /home/vagrant/.kube
k3d kubeconfig get "${CLUSTER_NAME}" > /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 600 /home/vagrant/.kube/config

mkdir -p /root/.kube
cp /home/vagrant/.kube/config /root/.kube/config
chmod 600 /root/.kube/config

KCFG="/home/vagrant/.kube/config"
kubectl --kubeconfig "$KCFG" get nodes

# Namespaces
kubectl --kubeconfig "$KCFG" create namespace argocd --dry-run=client -o yaml | kubectl --kubeconfig "$KCFG" apply -f -
kubectl --kubeconfig "$KCFG" create namespace dev    --dry-run=client -o yaml | kubectl --kubeconfig "$KCFG" apply -f -

# ArgoCD
kubectl --kubeconfig "$KCFG" apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl --kubeconfig "$KCFG" wait -n argocd --for=condition=Ready pods --all --timeout=600s

# HTTP (TLS yok) — Ingress ile 80’den sunacağız
kubectl --kubeconfig "$KCFG" -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}' || true
kubectl --kubeconfig "$KCFG" -n argocd rollout restart deploy/argocd-server
kubectl --kubeconfig "$KCFG" -n argocd rollout status deploy/argocd-server --timeout=5m

# Ingress
if [ "${USE_INGRESS}" = "true" ]; then
  kubectl --kubeconfig "$KCFG" apply -f "${CONFS_DIR}/argocd-server-ingress.yaml"
fi

log "ArgoCD UI: http://localhost:30080"
printf "Admin şifre: "
kubectl --kubeconfig "$KCFG" -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

log "setup.sh tamam"

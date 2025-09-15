#!/usr/bin/env bash
set -euxo pipefail

: "${CONFS_DIR:=/vagrant/confs}"
KCFG="/home/vagrant/.kube/config"

# API ayakta mı?
kubectl --kubeconfig "$KCFG" cluster-info

# ArgoCD Application CRD gelene kadar bekle
kubectl --kubeconfig "$KCFG" wait --for=condition=Established crd/applications.argoproj.io --timeout=300s || true

# (Varsa) app manifestleri
if [ -f "${CONFS_DIR}/app-deployment.yaml" ]; then
  kubectl --kubeconfig "$KCFG" apply -f "${CONFS_DIR}/app-deployment.yaml" --validate=false
fi

if [ -f "${CONFS_DIR}/application.yaml" ]; then
  kubectl --kubeconfig "$KCFG" apply -f "${CONFS_DIR}/application.yaml" --validate=false
fi

echo "deploy.sh tamam"

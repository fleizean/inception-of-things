#!/bin/bash

# Update package index and install required packages
apk update && apk add --no-cache curl

printf "[INFO] Initiating K3s controller installation...\n"
# Deploy K3s server with appropriate kubeconfig settings
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

printf "[INFO] Configuring K3s service management...\n"
# Add K3s to system startup services
rc-update add k3s default

# Initialize K3s service
rc-service k3s start

# Validate service status and attempt recovery if needed
MAX_ATTEMPTS=3
attempt=1

while ! rc-service k3s status | grep -q "started"; do
    printf "[WARN] Service not running (attempt %d/%d), attempting recovery...\n" $attempt $MAX_ATTEMPTS
    /usr/local/bin/k3s server --write-kubeconfig-mode 644 &
    sleep 5
done

# Define shared token location
SHARED_TOKEN="/vagrant/token"

printf "[INFO] Awaiting K3s initialization process...\n"
# Monitor for K3s infrastructure setup completion
max_wait=60
elapsed=0
while [ ! -f /var/lib/rancher/k3s/server/node-token ] && [ $elapsed -lt $max_wait ]; do
    sleep 2
    elapsed=$((elapsed + 2))
    printf "K3s initialization in progress... (%d/%d seconds elapsed)\n" $elapsed $max_wait
done


printf "[INFO] Verifying API server availability...\n"
max_wait=60
elapsed=0
until curl -k -s https://127.0.0.1:6443/readyz >/dev/null 2>&1 || [ $elapsed -ge $max_wait ]; do
    sleep 3
    elapsed=$((elapsed + 3))
    printf "API server health check... (%d/%d seconds)\n" $elapsed $max_wait
done

# Export node token for worker nodes
cat /var/lib/rancher/k3s/server/node-token > "$SHARED_TOKEN"
chmod 644 "$SHARED_TOKEN"

printf "[SUCCESS] K3s controller configuration completed!\n"

# Verify cluster functionality
kubectl get nodes


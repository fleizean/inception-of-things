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
if ! rc-service k3s status | grep -q "started"; then
    printf "[WARN] Service startup failed, attempting manual initialization...\n"
    /usr/local/bin/k3s server --write-kubeconfig-mode 644 &
    sleep 10
fi

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

# Handle initialization failure
if [ ! -f /var/lib/rancher/k3s/server/node-token ]; then
    printf "[ERROR] K3s initialization timeout after %d seconds\n" $max_wait
    printf "Current processes:\n"
    ps aux | grep k3s
    printf "System logs:\n"
    tail -20 /var/log/k3s.log 2>/dev/null || printf "Log file unavailable\n"
    exit 1
fi

printf "[INFO] Verifying API server availability...\n"
max_wait=60
elapsed=0
until curl -k -s https://127.0.0.1:6443/readyz >/dev/null 2>&1 || [ $elapsed -ge $max_wait ]; do
    sleep 3
    elapsed=$((elapsed + 3))
    printf "API server health check... (%d/%d seconds)\n" $elapsed $max_wait
done

# Handle API server readiness failure
if [ $elapsed -ge $max_wait ]; then
    printf "[ERROR] API server unavailable after %d seconds\n" $max_wait
    printf "K3s process status:\n"
    ps aux | grep k3s
    printf "Network port status:\n"
    netstat -tlnp | grep 6443 || printf "Port 6443 not accessible\n"
    exit 1
fi

# Export node token for worker nodes
cat /var/lib/rancher/k3s/server/node-token > "$SHARED_TOKEN"
chmod 644 "$SHARED_TOKEN"

printf "[SUCCESS] K3s controller configuration completed!\n"
printf "Authentication token exported to: %s\n" "$SHARED_TOKEN"
printf "API server operational status: READY\n"

# Verify cluster functionality
printf "[INFO] Performing cluster connectivity test...\n"
kubectl get nodes

printf "[SUCCESS] Master node deployment finished!\n"
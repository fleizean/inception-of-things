#!/bin/bash

# Update package manager and install dependencies
apk update && apk add --no-cache curl

# Configuration variables
AUTH_TOKEN_FILE="/vagrant/token"
CONTROL_PLANE_IP="192.168.56.110"

printf "[INFO] Awaiting controller node initialization...\n"

# Monitor for authentication token availability
while [ ! -f "$AUTH_TOKEN_FILE" ] || [ ! -s "$AUTH_TOKEN_FILE" ]; do
     sleep 2
     printf "Monitoring for cluster authentication token...\n"
done

# Retrieve cluster join token
CLUSTER_TOKEN=$(cat "$AUTH_TOKEN_FILE")

printf "[INFO] Authentication credentials located, initiating cluster join process...\n"

# Deploy K3s in worker/agent configuration
curl -sfL https://get.k3s.io | K3S_URL="https://$CONTROL_PLANE_IP:6443" K3S_TOKEN="$CLUSTER_TOKEN" sh -

printf "[SUCCESS] K3s worker node configuration completed!\n"
printf "Worker node has successfully joined the cluster infrastructure.\n"
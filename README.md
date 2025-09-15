# IoT (Inception-of-Things)

A Kubernetes learning project implementing infrastructure setup with K3s, K3d, Vagrant, and ArgoCD.

## Project Overview

This project consists of three parts that progressively build a complete Kubernetes infrastructure:

- **Part 1**: K3s cluster setup with Vagrant (Server + Worker nodes)
- **Part 2**: Three web applications with Ingress routing
- **Part 3**: K3d cluster with ArgoCD for GitOps deployment

## Prerequisites

- VirtualBox
- Vagrant
- Git

## Project Structure

```
├── p1/                 # Part 1: K3s + Vagrant
│   ├── Vagrantfile
│   └── scripts/
├── p2/                 # Part 2: K3s + Applications + Ingress
│   ├── Vagrantfile
│   ├── scripts/
│   └── confs/
└── p3/                 # Part 3: K3d + ArgoCD
    ├── Vagrantfile
    ├── scripts/
    └── confs/
```

## Quick Start

### Part 1: Basic K3s Cluster
```bash
cd p1
vagrant up
vagrant ssh mukelesS
kubectl get nodes
```

### Part 2: Applications with Ingress
```bash
cd p2
vagrant up
vagrant ssh eyagizS

# Test applications
curl -H "Host: app1.com" http://192.168.56.110
curl -H "Host: app2.com" http://192.168.56.110
curl http://192.168.56.110  # default app3
```

### Part 3: GitOps with ArgoCD
```bash
cd p3
vagrant up
vagrant ssh

# Access ArgoCD UI
# URL: http://localhost:30080
# User: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Key Features

- **Infrastructure as Code**: All configurations defined in version control
- **Automated Deployment**: GitOps workflow with ArgoCD
- **Load Balancing**: Ingress-based routing for multiple applications
- **High Availability**: Multi-replica deployments
- **Development Workflow**: Easy local testing and deployment

## Applications

- **App1**: Single replica nginx with custom HTML
- **App2**: Three-replica nginx with load balancing
- **App3**: Default application for unmatched requests

## Network Configuration

- **Part 1**: 
  - Server: 192.168.56.110
  - Worker: 192.168.56.111
- **Part 2**: Single VM at 192.168.56.110
- **Part 3**: K3d cluster with port forwarding

## ArgoCD Configuration

The GitOps setup automatically deploys applications from this repository:
- Repository: https://github.com/mukeles123/mukeles42.git
- Target namespace: `dev`
- Sync policy: Automated with self-healing and pruning

## Troubleshooting

### Common Issues

1. **VM not starting**: Check VirtualBox installation and available resources
2. **kubectl connection**: Verify kubeconfig path and cluster status
3. **ArgoCD access**: Ensure port forwarding is active and services are running

### Useful Commands

```bash
# Check cluster status
kubectl get nodes -o wide
kubectl get all --all-namespaces

# ArgoCD password retrieval
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Restart cluster (Part 3)
k3d cluster stop p3-cluster
k3d cluster start p3-cluster
```

## Technology Stack

- **Kubernetes**: K3s (lightweight) / K3d (containerized)
- **Virtualization**: Vagrant + VirtualBox
- **GitOps**: ArgoCD
- **Ingress**: Traefik (default with K3s)
- **Container Runtime**: containerd

## Learning Objectives

- Understand Kubernetes fundamentals
- Practice infrastructure automation
- Implement GitOps workflows
- Configure load balancing and routing
- Master container orchestration

## Project Teammates

- [@eozmert](https://github.com/enesozmert)
- [@mukeles](https://github.com/yasirkelesh)

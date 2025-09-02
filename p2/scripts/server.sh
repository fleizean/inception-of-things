#!/bin/sh

apk update
apk add curl

curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644

rc-update add k3s default
rc-service k3s start

echo "Waiting for K3s to initialize..."
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
    echo "Waiting for k3s.yaml to be created..."
done

sleep 10

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config

echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for node to be ready..."
until kubectl get nodes | grep -q " Ready"; do
    sleep 5
    echo "Waiting for node to become ready..."
done

echo "Waiting for system pods..."
sleep 15

echo "Creating ConfigMaps..."

kubectl create configmap app-one-config \
    --from-file=index.html=/vagrant/confs/src/app1.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-two-config \
    --from-file=index.html=/vagrant/confs/src/app2.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-three-config \
    --from-file=index.html=/vagrant/confs/src/app3.html \
    --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMaps created:"
kubectl get configmaps

echo "Deploying applications..."
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml

kubectl apply -f /vagrant/confs/ingress.yaml

echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/app1 || true
kubectl wait --for=condition=available --timeout=120s deployment/app2 || true
kubectl wait --for=condition=available --timeout=120s deployment/app3 || true

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Deployments status:"
kubectl get deployments
echo ""
echo "Pods status:"
kubectl get pods
echo ""
echo "Services:"
kubectl get svc
echo ""
echo "Ingress:"
kubectl get ingress
echo ""
echo "ConfigMaps:"
kubectl get configmaps
echo ""
echo "Note: For vagrant user, use: export KUBECONFIG=/home/vagrant/.kube/config"
echo ""
echo "Test commands (run from host machine):"
echo "  curl -H 'Host: app1.com' http://192.168.56.110"
echo "  curl -H 'Host: app2.com' http://192.168.56.110"
echo "  curl http://192.168.56.110"
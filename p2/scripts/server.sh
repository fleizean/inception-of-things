#!/bin/sh

apk update
apk add curl

curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644

rc-update add k3s default
rc-service k3s start

echo "[INFO] Starting K3s initialization process..."
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
    echo "[WAIT] Checking for k3s.yaml configuration..."
done

sleep 10

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config

echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[STATUS] Checking node readiness..."
until kubectl get nodes | grep -q " Ready"; do
    sleep 5
    echo "[WAIT] Node not yet ready, waiting..."
done

echo "[INIT] Waiting for system pods to stabilize..."
sleep 15

echo "[CONFIG] Preparing application ConfigMaps..."

kubectl create configmap app-one-config \
    --from-file=index.html=/vagrant/confs/src/app1.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-two-config \
    --from-file=index.html=/vagrant/confs/src/app2.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-three-config \
    --from-file=index.html=/vagrant/confs/src/app3.html \
    --dry-run=client -o yaml | kubectl apply -f -

echo "[SUCCESS] ConfigMaps created successfully:"
kubectl get configmaps

echo "[DEPLOY] Launching application containers..."
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml

kubectl apply -f /vagrant/confs/ingress.yaml

echo "[WAIT] Ensuring deployments are available..."
kubectl wait --for=condition=available --timeout=120s deployment/app1 || true
kubectl wait --for=condition=available --timeout=120s deployment/app2 || true
kubectl wait --for=condition=available --timeout=120s deployment/app3 || true

echo ""
echo "****** SETUP COMPLETED SUCCESSFULLY ******"
echo ""
echo "[CLUSTER STATUS] Deployment Information:"
kubectl get deployments
echo ""
echo "[CLUSTER STATUS] Pod Information:"
kubectl get pods
echo ""
echo "[CLUSTER STATUS] Service Endpoints:"
kubectl get svc
echo ""
echo "[CLUSTER STATUS] Ingress Configuration:"
kubectl get ingress
echo ""
echo "[CLUSTER STATUS] Available ConfigMaps:"
kubectl get configmaps
echo ""
echo "[USER INFO] To configure kubectl for vagrant user: export KUBECONFIG=/home/vagrant/.kube/config"
echo ""
echo "[TEST INFO] Commands to verify services (run from host):"
echo "  curl -H 'Host: app1.com' http://192.168.56.110"
echo "  curl -H 'Host: app2.com' http://192.168.56.110"
echo "  curl http://192.168.56.110"
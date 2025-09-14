#!/bin/sh
apk update
apk add curl
curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644
rc-update add k3s default
rc-service k3s start

echo "[INFO] K3s başlatma işlemi başlatılıyor..."
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
    sleep 2
    echo "[WAIT] k3s.yaml konfigürasyon dosyası kontrol ediliyor..."
done

sleep 10

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[STATUS] Node hazırlık durumu kontrol ediliyor..."
until kubectl get nodes | grep -q " Ready"; do
    sleep 5
    echo "[WAIT] Node henüz hazır değil, bekleniyor..."
done

echo "[INIT] Sistem pod'larının stabilize olması bekleniyor..."
sleep 15

echo "[CONFIG] Uygulama ConfigMap'leri hazırlanıyor..."

kubectl create configmap app-one-config \
    --from-file=index.html=/vagrant/confs/src/app1.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-two-config \
    --from-file=index.html=/vagrant/confs/src/app2.html \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap app-three-config \
    --from-file=index.html=/vagrant/confs/src/app3.html \
    --dry-run=client -o yaml | kubectl apply -f -

echo "[SUCCESS] ConfigMap'ler başarıyla oluşturuldu:"
kubectl get configmaps

echo "[DEPLOY] Uygulama container'ları başlatılıyor..."
kubectl apply -f /vagrant/confs/app1.yaml
kubectl apply -f /vagrant/confs/app2.yaml
kubectl apply -f /vagrant/confs/app3.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo "[WAIT] Deployment'ların hazır olması sağlanıyor..."
kubectl wait --for=condition=available --timeout=120s deployment/app1 || true
kubectl wait --for=condition=available --timeout=120s deployment/app2 || true
kubectl wait --for=condition=available --timeout=120s deployment/app3 || true

echo ""
echo "****** KURULUM BAŞARIYLA TAMAMLANDI ******"
echo ""
echo "[CLUSTER STATUS] Deployment Bilgileri:"
kubectl get deployments
echo ""
echo "[CLUSTER STATUS] Pod Bilgileri:"
kubectl get pods
echo ""
echo "[CLUSTER STATUS] Servis Endpoint'leri:"
kubectl get svc
echo ""
echo "[CLUSTER STATUS] Ingress Konfigürasyonu:"
kubectl get ingress
echo ""
echo "[CLUSTER STATUS] Mevcut ConfigMap'ler:"
kubectl get configmaps
echo ""
echo "[USER INFO] Vagrant kullanıcısı için kubectl konfigürasyonu: export KUBECONFIG=/home/vagrant/.kube/config"
echo ""
echo "[TEST INFO] Servisleri doğrulamak için komutlar (host'tan çalıştır):"
echo "  curl -H 'Host: app1.com' http://192.168.56.110"
echo "  curl -H 'Host: app2.com' http://192.168.56.110"
echo "  curl http://192.168.56.110"
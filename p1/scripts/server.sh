#!/bin/bash
apk update
apk add curl
echo "[INFO] K3s server kurulumu başlatılıyor..."
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
echo "[INFO] K3s servisi yapılandırılıyor..."
rc-update add k3s default
rc-service k3s start
if ! rc-service k3s status | grep -q "started"; then
    echo "[WARN] Servis başlatılamadı, manuel başlatma deneniyor..."
    /usr/local/bin/k3s server --write-kubeconfig-mode 644 &
    sleep 10
fi
TOKEN_PATH="/vagrant/token"
echo "[INFO] K3s başlatma işlemi bekleniyor..."
timeout=60
counter=0
while [ ! -f /var/lib/rancher/k3s/server/node-token ] && [ $counter -lt $timeout ]; do
    sleep 2
    counter=$((counter + 2))
    echo "[WAIT] K3s başlatma işlemi devam ediyor... ($counter/$timeout saniye)"
done
if [ ! -f /var/lib/rancher/k3s/server/node-token ]; then
    echo "[ERROR] K3s $timeout saniye sonra başlatılamadı"
    echo "[DEBUG] Çalışan işlemler:"
    ps aux | grep k3s
    echo "[DEBUG] Log kontrolü:"
    tail -20 /var/log/k3s.log 2>/dev/null || echo "Log dosyası bulunamadı"
    exit 1
fi
echo "[INFO] API server hazırlık durumu kontrol ediliyor..."
timeout=60
counter=0
until curl -k -s https://127.0.0.1:6443/readyz >/dev/null 2>&1 || [ $counter -ge $timeout ]; do
    sleep 3
    counter=$((counter + 3))
    echo "[WAIT] API server bekleniyor... ($counter/$timeout saniye)"
done
if [ $counter -ge $timeout ]; then
    echo "[ERROR] API server $timeout saniye sonra hazır olmadı"
    echo "[DEBUG] K3s durum kontrolü:"
    ps aux | grep k3s
    echo "[DEBUG] Port 6443 kontrolü:"
    netstat -tlnp | grep 6443 || echo "Port 6443 dinlenmiyor"
    exit 1
fi
cat /var/lib/rancher/k3s/server/node-token > "$TOKEN_PATH"
chmod 644 "$TOKEN_PATH"

echo "[INFO] Vagrant kullanıcısı için kubeconfig ayarlanıyor..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc

echo "[SUCCESS] K3s server kurulumu tamamlandı!"
echo "[INFO] Node token kaydedildi: $TOKEN_PATH"
echo "[INFO] API server hazır durumda!"
echo "[TEST] kubectl bağlantısı test ediliyor..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
echo "[SUCCESS] Kurulum başarıyla tamamlandı!"

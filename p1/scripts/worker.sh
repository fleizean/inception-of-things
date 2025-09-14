#!/bin/bash
apk update
apk add curl

TOKEN_FILE="/vagrant/token"
SERVER_IP="192.168.56.110"

echo "[INFO] Server başlatılması ve token oluşturulması bekleniyor..."

while [ ! -f "$TOKEN_FILE" ] || [ ! -s "$TOKEN_FILE" ]; do
     sleep 2
     echo "[WAIT] Token dosyası bekleniyor..."
done

TOKEN=$(cat "$TOKEN_FILE")

echo "[INFO] Token bulundu, cluster'a agent olarak katılım başlatılıyor..."

curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$TOKEN" sh -

echo "[SUCCESS] K3s agent kurulumu tamamlandı!"
echo "[SUCCESS] Node cluster'a başarıyla katıldı!"

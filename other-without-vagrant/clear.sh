#!/bin/bash
# close.sh - IoT Project P3 Cleanup Script
# Temizlik ve kapatma işlemleri

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    printf "${BLUE}=================================================${NC}\n"
    printf "${BLUE}%s${NC}\n" "$1"
    printf "${BLUE}=================================================${NC}\n"
}

print_info() {
    printf "${BLUE}[BİLGİ] $1${NC}\n"
}

print_success() {
    printf "${GREEN}[BAŞARILI] $1${NC}\n"
}

print_warn() {
    printf "${YELLOW}[UYARI] $1${NC}\n"
}

print_error() {
    printf "${RED}[HATA] $1${NC}\n"
}

# Ana temizlik fonksiyonu
main_cleanup() {
    print_header "IoT Projesi P3 - Sistem Temizliği"
    
    print_info "Sistem kapatma işlemi başlatılıyor..."
    echo
    
    # 1. Port forwarding işlemlerini durdur
    print_info "1. Port forwarding işlemleri durduruluyor..."
    if pgrep -f "kubectl.*port-forward" >/dev/null; then
        print_warn "Aktif port-forward işlemleri bulundu, durduruluyor..."
        sudo pkill -f "kubectl.*port-forward" || true
        sleep 2
        print_success "Port forwarding işlemleri durduruldu"
    else
        print_info "Aktif port-forward işlemi bulunamadı"
    fi
    echo
    
    # 2. ArgoCD aplikasyonlarını sil
    print_info "2. ArgoCD uygulamaları temizleniyor..."
    if kubectl get applications -n argocd >/dev/null 2>&1; then
        print_warn "ArgoCD uygulamaları siliniyor..."
        kubectl delete applications --all -n argocd || true
        print_success "ArgoCD uygulamaları silindi"
    else
        print_info "ArgoCD uygulaması bulunamadı"
    fi
    echo
    
    # 3. Dev namespace kaynaklarını sil
    print_info "3. Dev namespace kaynakları temizleniyor..."
    if kubectl get namespace dev >/dev/null 2>&1; then
        print_warn "Dev namespace kaynakları siliniyor..."
        kubectl delete all --all -n dev || true
        kubectl delete namespace dev || true
        print_success "Dev namespace temizlendi"
    else
        print_info "Dev namespace bulunamadı"
    fi
    echo
    
    # 4. ArgoCD'yi tamamen kaldır
    print_info "4. ArgoCD kurulumu kaldırılıyor..."
    if kubectl get namespace argocd >/dev/null 2>&1; then
        print_warn "ArgoCD namespace ve tüm kaynakları siliniyor..."
        kubectl delete namespace argocd || true
        sleep 5
        print_success "ArgoCD tamamen kaldırıldı"
    else
        print_info "ArgoCD namespace bulunamadı"
    fi
    echo
    
    # 5. K3d cluster'ı sil
    print_info "5. K3d cluster siliniyor..."
    if k3d cluster list | grep -q "p3-cluster"; then
        print_warn "p3-cluster siliniyor..."
        k3d cluster delete p3-cluster || true
        print_success "K3d cluster silindi"
    else
        print_info "p3-cluster bulunamadı"
    fi
    echo
    
    # 6. Docker container'ları temizle
    print_info "6. Docker kaynakları temizleniyor..."
    print_warn "Kullanılmayan Docker container'ları temizleniyor..."
    docker container prune -f || true
    docker image prune -f || true
    docker network prune -f || true
    print_success "Docker kaynakları temizlendi"
    echo
    
    # 7. Kubeconfig temizle
    print_info "7. Kubeconfig temizleniyor..."
    if [ -f "$HOME/.kube/config" ]; then
        print_warn "Kubeconfig yedekleniyor ve temizleniyor..."
        cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        rm -f "$HOME/.kube/config" || true
        print_success "Kubeconfig temizlendi (yedek alındı)"
    else
        print_info "Kubeconfig bulunamadı"
    fi
    echo
    
    # 8. Dosya sistem kontrolü
    print_info "8. Dosya sistemi durumu kontrol ediliyor..."
    if lsof /mnt/c/Users/*/Desktop/inception-of-things 2>/dev/null | grep -v "COMMAND"; then
        print_warn "Bazı dosyalar hala kullanımda:"
        lsof /mnt/c/Users/*/Desktop/inception-of-things 2>/dev/null || true
        print_info "Terminal'i kapatıp yeniden açmanız önerilir"
    else
        print_success "Dosya sistemi temiz görünüyor"
    fi
    echo
    
    # Durum özeti
    print_header "Temizlik Özeti"
    printf "${GREEN}✓ Port forwarding durduruldu${NC}\n"
    printf "${GREEN}✓ ArgoCD uygulamaları silindi${NC}\n"
    printf "${GREEN}✓ Dev namespace temizlendi${NC}\n"
    printf "${GREEN}✓ ArgoCD kurulumu kaldırıldı${NC}\n"
    printf "${GREEN}✓ K3d cluster silindi${NC}\n"
    printf "${GREEN}✓ Docker kaynakları temizlendi${NC}\n"
    printf "${GREEN}✓ Kubeconfig temizlendi${NC}\n"
    echo
    
    print_success "Tüm kaynaklar başarıyla temizlendi!"
    print_info "Artık dosyalarınızı güvenle taşıyabilirsiniz."
    print_info "Yeniden başlatmak için install script'ini çalıştırın."
    echo
}

# Onay alma fonksiyonu
ask_confirmation() {
    print_warn "Bu işlem şunları yapacak:"
    echo "  - Tüm port-forward işlemlerini durduracak"
    echo "  - ArgoCD uygulamalarını silecek"
    echo "  - Dev namespace'ini tamamen silecek"
    echo "  - ArgoCD kurulumunu kaldıracak"
    echo "  - K3d cluster'ı silecek"
    echo "  - Docker kaynaklarını temizleyecek"
    echo "  - Kubeconfig'i sıfırlayacak"
    echo
    
    printf "Devam etmek istediğinizden emin misiniz? (y/N): "
    read REPLY
    case "$REPLY" in
        [Yy]|[Yy][Ee][Ss]) 
            echo "İşlem onaylandı."
            ;;
        *)
            print_info "İşlem iptal edildi."
            exit 0
            ;;
    esac
}

# Hızlı temizlik (onay olmadan)
force_cleanup() {
    print_warn "Hızlı temizlik modu aktif (onay atlandı)"
    main_cleanup
}

# Script parametrelerini kontrol et
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
    force_cleanup
else
    ask_confirmation
    main_cleanup
fi
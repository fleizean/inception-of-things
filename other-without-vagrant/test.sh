#!/bin/bash
# P3 Test Script - IoT Project Evaluation
# Tests all Part 3 requirements according to evaluation criteria

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0

print_header() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST] $1${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

print_success() {
    echo -e "${GREEN}[BAŞARILI] $1${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

print_error() {
    echo -e "${RED}[HATA] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[BİLGİ] $1${NC}"
}

# Check if running from correct directory
check_directory() {
    print_header "Dizin Yapısı Kontrolü"
    
    print_test "p3 klasörünün varlığı kontrol ediliyor"
    if [ -d "p3" ]; then
        print_success "p3 klasörü bulundu"
    else
        print_error "p3 klasörü bulunamadı. Script'i proje kök dizininden çalıştırın."
        exit 1
    fi
    
    print_test "p3/confs/ dizinindeki konfigürasyon dosyaları kontrol ediliyor"
    if [ -d "p3/confs" ]; then
        print_success "p3/confs klasörü mevcut"
        ls -la p3/confs/
    else
        print_error "p3/confs klasörü bulunamadı"
    fi
    
    print_test "p3/scripts/ dizinindeki script dosyaları kontrol ediliyor"
    if [ -d "p3/scripts" ]; then
        print_success "p3/scripts klasörü mevcut"
        ls -la p3/scripts/
    else
        print_error "p3/scripts klasörü bulunamadı"
    fi
    echo
}

# Test cluster status
test_cluster() {
    print_header "K3d Cluster Konfigürasyonu"
    
    print_test "k3d kurulumu kontrol ediliyor"
    if command -v k3d >/dev/null 2>&1; then
        print_success "k3d kurulu"
        k3d version
    else
        print_error "k3d kurulu değil"
        return 1
    fi
    
    print_test "kubectl kurulumu kontrol ediliyor"
    if command -v kubectl >/dev/null 2>&1; then
        print_success "kubectl kurulu"
        kubectl version --client
    else
        print_error "kubectl kurulu değil"
        return 1
    fi
    
    print_test "k3d cluster varlığı kontrol ediliyor"
    if k3d cluster list | grep -q "p3-cluster"; then
        print_success "p3-cluster mevcut"
        k3d cluster list
    else
        print_error "p3-cluster bulunamadı"
        echo "Mevcut cluster'lar:"
        k3d cluster list
        return 1
    fi
    
    print_test "Cluster bağlantısı test ediliyor"
    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "Cluster'a erişim başarılı"
        kubectl cluster-info
    else
        print_error "Cluster'a bağlanılamıyor"
        return 1
    fi
    echo
}

# Test namespaces
test_namespaces() {
    print_header "Namespace Gereksinimleri"
    
    print_test "Gerekli namespace'ler kontrol ediliyor (argocd ve dev)"
    
    # Check argocd namespace
    if kubectl get namespace argocd >/dev/null 2>&1; then
        print_success "argocd namespace mevcut"
    else
        print_error "argocd namespace bulunamadı"
    fi
    
    # Check dev namespace
    if kubectl get namespace dev >/dev/null 2>&1; then
        print_success "dev namespace mevcut"
    else
        print_error "dev namespace bulunamadı"
    fi
    
    print_info "Tüm namespace'ler:"
    kubectl get namespaces
    echo
}

# Test ArgoCD installation
test_argocd() {
    print_header "ArgoCD Kurulumu"
    
    print_test "argocd namespace'indeki ArgoCD pod'ları kontrol ediliyor"
    if kubectl get pods -n argocd >/dev/null 2>&1; then
        print_success "ArgoCD pod'ları bulundu"
        kubectl get pods -n argocd
    else
        print_error "ArgoCD pod'ları bulunamadı"
        return 1
    fi
    
    print_test "ArgoCD server'ın çalışıp çalışmadığı kontrol ediliyor"
    if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        print_success "ArgoCD server deployment mevcut"
        kubectl rollout status deployment argocd-server -n argocd --timeout=60s
    else
        print_error "ArgoCD server deployment bulunamadı"
    fi
    
    print_test "ArgoCD servisleri kontrol ediliyor"
    kubectl get svc -n argocd
    
    print_test "ArgoCD admin şifresi kontrol ediliyor"
    if kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; then
        print_success "ArgoCD admin secret mevcut"
        echo -n "Admin şifresi: "
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
        echo
    else
        print_error "ArgoCD admin secret bulunamadı"
    fi
    echo
}

# Test dev namespace application
test_dev_app() {
    print_header "Dev Namespace Uygulaması"
    
    print_test "dev namespace'indeki pod'lar kontrol ediliyor"
    if kubectl get pods -n dev >/dev/null 2>&1; then
        pod_count=$(kubectl get pods -n dev --no-headers | wc -l)
        if [ "$pod_count" -ge 1 ]; then
            print_success "dev namespace'inde en az 1 pod bulundu ($pod_count pod)"
            kubectl get pods -n dev -o wide
        else
            print_error "dev namespace'inde pod bulunamadı"
        fi
    else
        print_error "dev namespace'ine erişilemiyor veya pod yok"
    fi
    
    print_test "dev namespace'indeki servisler kontrol ediliyor"
    kubectl get svc -n dev
    
    print_test "dev namespace'indeki deployment'lar kontrol ediliyor"
    kubectl get deployment -n dev
    echo
}

# Test ArgoCD Application
test_argocd_application() {
    print_header "ArgoCD Uygulama Konfigürasyonu"
    
    print_test "ArgoCD uygulamaları kontrol ediliyor"
    if kubectl get applications -n argocd >/dev/null 2>&1; then
        app_count=$(kubectl get applications -n argocd --no-headers | wc -l)
        if [ "$app_count" -ge 1 ]; then
            print_success "ArgoCD uygulamaları bulundu ($app_count uygulama)"
            kubectl get applications -n argocd
        else
            print_error "ArgoCD uygulaması bulunamadı"
        fi
    else
        print_error "ArgoCD uygulamalarına erişilemiyor"
    fi
    
    print_test "Uygulama detayları kontrol ediliyor"
    kubectl get applications -n argocd -o wide
    echo
}

# Test application accessibility
test_app_access() {
    print_header "Uygulama Erişilebilirlik Testi"
    
    print_test "playground servisi varlığı kontrol ediliyor"
    if kubectl get svc playground-svc -n dev >/dev/null 2>&1; then
        print_success "playground-svc servisi bulundu"
        kubectl get svc playground-svc -n dev
    else
        print_error "playground-svc servisi bulunamadı"
        return 1
    fi
    
    print_info "Uygulama manuel test için hazır:"
    print_info "kubectl port-forward svc/playground-svc -n dev 8888:80"
    print_info "Sonra erişin: curl http://localhost:8888"
    echo
}

# Test ArgoCD web interface
test_argocd_ui() {
    print_header "ArgoCD Web Arayüzü"
    
    print_test "ArgoCD server servisi kontrol ediliyor"
    if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
        print_success "ArgoCD server servisi mevcut"
        kubectl get svc argocd-server -n argocd
    else
        print_error "ArgoCD server servisi bulunamadı"
    fi
    
    print_info "ArgoCD UI manuel erişim için:"
    print_info "kubectl port-forward svc/argocd-server -n argocd 8080:80"
    print_info "Sonra erişin: http://localhost:8080"
    print_info "Kullanıcı adı: admin"
    print_info "Şifre: (yukarıdaki komutla şifreyi alın)"
    echo
}

# Test GitHub repository configuration
test_github_config() {
    print_header "GitHub Repository Konfigürasyonu"
    
    print_test "ArgoCD uygulama kaynak konfigürasyonu kontrol ediliyor"
    if kubectl get applications -n argocd -o yaml | grep -q "repoURL"; then
        print_success "ArgoCD uygulamasında repository URL bulundu"
        echo "Repository konfigürasyonu:"
        kubectl get applications -n argocd -o yaml | grep -A 5 -B 5 "repoURL"
    else
        print_error "ArgoCD uygulamasında repository URL bulunamadı"
    fi
    echo
}

# Test Docker image configuration
test_docker_config() {
    print_header "Docker Image Konfigürasyonu"
    
    print_test "Deployment image konfigürasyonu kontrol ediliyor"
    if kubectl get deployment wil-playground -n dev -o yaml | grep -q "image:"; then
        print_success "Docker image konfigürasyonu bulundu"
        echo "Image konfigürasyonu:"
        kubectl get deployment wil-playground -n dev -o yaml | grep "image:"
    else
        print_error "Docker image konfigürasyonu bulunamadı"
    fi
    echo
}

# Main test execution
main() {
    print_header "IoT Projesi Part 3 - Test Paketi"
    echo "Part 3 gereksinimlerinin kapsamlı testi başlatılıyor..."
    echo
    
    # Run all tests
    check_directory
    test_cluster
    test_namespaces
    test_argocd
    test_dev_app
    test_argocd_application
    test_app_access
    test_argocd_ui
    test_github_config
    test_docker_config
    
    # Final results
    print_header "Test Sonuçları Özeti"
    echo -e "Toplam Test: ${TOTAL_TESTS}"
    echo -e "Başarılı: ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Geçildi: ${RED}$((TOTAL_TESTS - PASSED_TESTS))${NC}"
    
    if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
        echo -e "${GREEN}🎉 Tüm testler başarılı! Part 3 değerlendirmeye hazır.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Bazı testler başarısız. Lütfen sorunları gözden geçirin ve düzeltin.${NC}"
        exit 1
    fi
}

# Run main function
main
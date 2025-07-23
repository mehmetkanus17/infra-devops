# Kubernetes Altyapı Kurulum Projesi
Bu rapor, Azure Cloud ortamında Infrastructure as Code yaklaşımı kullanılarak oluşturulan Kubernetes cluster'ının kurulum ve konfigürasyon sürecini detaylandırmaktadır.

## 1. Genel Bakış
-**Proje Kapsamı***
Azure Cloud üzerinde on-premise mimariye benzer şekilde çalışacak, yüksek erişilebilirlik sağlayan Kubernetes cluster'ının kurulumu ve konfigürasyonu gerçekleştirilmiştir.

* **Altyapı Bileşenleri**
- Master Node'lar: 3 adet (HA için)
- Worker Node'lar: 3 adet
- Ansible Sunucu: Kubespray ile cluster kurulumu için
- HAProxy Sunucu: Load balancer ve cluster erişimi için
- NFS Sunucu: Persistent Volume Claims (PVC) için

## 2. Teknoloji Stack'i

* **Kullanılan Teknolojiler**
- Infrastructure as Code: Terraform
- Cluster Kurulumu: Kubespray (Ansible)
- Load Balancer: HAProxy
- Storage: NFS
- Container Registry: Harbor
- Monitoring: Prometheus & Grafana
- Logging: ELK Stack (Elasticsearch, Logstash, Kibana)
- GitOps: ArgoCD
- Secret Management: HashiCorp Vault

* **Otomatizasyon Script'leri** 
- Proje tamamen otomatize edilmiş olup, üç ana script dosyası ile yönetilmektedir:

    - **infra.sh:** Terraform ile altyapı oluşturma
    - **ansible.sh:** Kubernetes cluster kurulumu
    - **haproxy.sh:** Load balancer konfigürasyonu

## 3. Detaylı Kurulum Süreci

* **Altyapı Oluşturma (infra.sh)**
    - Ortam Seçimi ve SSH Anahtarı Oluşturma
    - Kullanıcıdan ortam seçimi (dev/staging/prod)
    - SSH anahtarı oluşturma ve izinlerin ayarlanması
    - Terraform workspace'in hazırlanması

* **Terraform İşlemleri**
    - terraform init ile başlatma
    - Workspace'e geçiş veya oluşturma
    - terraform plan ile değişikliklerin görüntülenmesi
    - Kullanıcı onayı ile terraform apply çalıştırma

* **Konfigürasyon Dosyalarının Hazırlanması**
    - Kubespray için hosts.yaml ve ansible.cfg oluşturma
    - HAProxy konfigürasyon dosyasının hazırlanması
    - Gerekli dosyaların tar arşivine sıkıştırılması
    - Arşivin uzak sunuculara kopyalanması

* **Uzak Kurulum İşlemleri**
    - Ansible sunucusunda Kubernetes kurulum script'inin çalıştırılması
    - HAProxy sunucusunda load balancer konfigürasyonunun yapılması

* **Kubernetes Cluster Kurulumu (ansible.sh)**
    - Ön Gereksinimler
        - SSH private key'in doğru konuma kopyalanması ve izin ayarları
        - Kubespray deposunun klonlanması (v2.24.3)
        - Python virtual environment oluşturma ve bağımlılıkların yüklenmesi

* **Kubespray Konfigürasyonu**
    - Ansible konfigürasyon dosyasının hazırlanması
    - Host inventory dosyasının kopyalanması
    - HAProxy IP'sinin SSL sertifikasına eklenmesi
    - SSH agent'ın başlatılması

* **Cluster Kurulumu**
    - Kubespray playbook'unun çalıştırılması
    - kubectl binary'sinin kurulması
    - Master node'dan admin.conf dosyasının alınması
    - Kubeconfig'in yapılandırılması

* **HAProxy Konfigürasyonu (haproxy.sh)**
    * HAProxy Kurulumu ve Konfigürasyonu
        - HAProxy paketinin kurulması
        - Konfigürasyon dosyasının kopyalanması
        - Servisin yeniden başlatılması ve durumunun kontrol edilmesi

    * Kubectl ve Yardımcı Araçların Kurulumu
        - kubectl binary'sinin kurulması
        - Bash alias'larının eklenmesi
        - SSH agent konfigürasyonu

* **Kubeconfig Ayarları**
    - Master node'dan admin.conf dosyasının alınması
    - HAProxy üzerinden cluster'a erişim için konfigürasyon

* **Kubernetes Bileşenlerinin Kurulumu**
    - Paket Yöneticileri ve Repository'ler
    - Helm kurulumu ve repository'lerin eklenmesi
    - Kustomize kurulumu
    - Namespace'ler ve Temel Bileşenler
        - Gerekli namespace'lerin oluşturulması
    - Cert-manager kurulumu (v1.16.1)
        - ClusterIssuer'ın oluşturulması
    - NGINX Ingress Controller kurulumu (NodePort yapılandırması)
    - Monitoring ve Logging Stack
        - kube-prometheus-stack kurulumu
    - Metrics Server kurulumu
    - ELK Stack bileşenlerinin kurulumu:
        - Elasticsearch
        - Filebeat
        - Logstash
        - Metricbeat
        - Kibana

    - Storage ve Database
        - NFS Provisioner kurulumu (default StorageClass)
        - PostgreSQL kurulumu

    - DevOps Araçları
        - ArgoCD kurulumu (GitOps)
        - HashiCorp Vault kurulumu (dev modu)
        - Harbor container registry
        - Locust load testing tool

    - External Secrets ve Test Araçları
        - External Secrets Operator
        - Çeşitli test ve konfigürasyon araçları

## 4. Güvenlik ve En İyi Uygulamalar

* **4.1 Güvenlik Önlemleri**
- SSH anahtarları için uygun izin ayarları (400/644)
- SSL sertifikalarına HAProxy IP'sinin dahil edilmesi
- Namespace tabanlı izolasyon
- Secret yönetimi için Vault entegrasyonu

* **4.2 Yüksek Erişilebilirlik**
- 3 Master node ile HA konfigürasyonu
- HAProxy ile load balancing
- Round-robin algoritması kullanımı

* **4.3 Monitoring ve Observability**
- Prometheus ile metric toplama
- Grafana ile görselleştirme
- ELK Stack ile log yönetimi
- Metricbeat ile sistem metrikleri

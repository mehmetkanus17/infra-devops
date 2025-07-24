# infra-mehmetkanus: Kubernetes Altyapı Kurulumu

Bu repo, Azure Cloud ortamında on-premise mimariye benzer şekilde çalışacak, Infrastructure as Code yaklaşımı kullanılarak oluşturulan Kubernetes cluster'ının kurulum ve konfigürasyon sürecini detaylandırmaktadır. Amaç, çoklu master ve çoklu worker düğümlerine sahip, yüksek erişilebilirliğe sahip bir Kubernetes ortamı oluşturmaktır. Ayrıca, bu altyapı üzerinde çalışacak uygulamaların dış dünyaya açılması için HAProxy tabanlı bir yük dengeleyici ve çeşitli Kubernetes eklentileri de kurulmaktadır.

## İçindekiler

1.  Genel Bakış
2.  Altyapı Bileşenleri
3.  Kurulum Akışı
    *   `infra.sh`: Terraform ile Sanal Makine Provizyonlama
    *   `ansible.sh`: Kubespray ile Kubernetes Kümesi Kurulumu
    *   `haproxy.sh`: HAProxy ve Kubernetes Eklentileri Kurulumu
4.  Dizin Yapısı

## 1. Genel Bakış

`infra-mehmetkanus` reposu, modern bulut yerel uygulamaları için sağlam ve ölçeklenebilir bir temel sağlamak amacıyla tasarlanmış bir Kubernetes altyapısının kurulumunu otomatikleştirmektedir. Bu altyapı, Terraform ile sanal makinelerin provizyonlanması, Kubespray ile Kubernetes kümesinin kurulması ve HAProxy ile dış erişimin sağlanması gibi adımları içerir. Depo, Infrastructure as Code (IaC) prensiplerini benimseyerek, altyapının tekrarlanabilir, sürdürülebilir ve versiyonlanabilir olmasını sağlar.

* **Altyapı Bileşenleri**
    - Master Node'lar: 3 adet (HA için)
    - Worker Node'lar: 3 adet
    - Ansible Sunucu: Kubespray ile cluster kurulumu için
    - HAProxy Sunucu: Load balancer ve cluster erişimi için
    - NFS Sunucu: Persistent Volume Claims (PVC) için

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

Kurulum süreci, aşağıdaki ana bileşenleri içerir:

*   **Sanal Makine Provizyonlama**: Terraform kullanılarak Kubernetes master, worker, HAProxy ve NFS sunucuları için sanal makineler oluşturulur.
*   **Kubernetes Kümesi Kurulumu**: Kubespray ile çoklu master ve çoklu worker düğümlerine sahip yüksek erişilebilirliğe sahip bir Kubernetes kümesi kurulur.
*   **Yük Dengeleme ve Dış Erişim**: HAProxy, Kubernetes API sunucuları ve Ingress Controller servisleri için yük dengeleme sağlayarak küme dışından erişimi mümkün kılar.
*   **NFS ve Depolama**: Kalıcı depolama (Persistent Volume Claim - PVC) ihtiyaçları için NFS tabanlı bir depolama altyapısı kurulur.
*   **HashiCorp Vault Entegrasyonu**: Kubernetes ile entegre edilmiş bir HashiCorp Vault sunucusu, sır yönetimi için merkezi bir çözüm sunar.
*   **Temel Kubernetes Eklentileri**: Cert-Manager, Nginx Ingress Controller, ArgoCD, Prometheus-Grafana, Metrics Server, External Secrets Operator ve Harbor gibi temel eklentiler küme üzerinde dağıtılır.

Bu repo, altyapı kurulumunu otomatikleştirmek ve DevOps projenin altyapı gereksinimlerini karşılamak için tasarlanmıştır.

## 2. Altyapı Bileşenleri

`infra-mehmetkanus` reposu, aşağıdaki ana altyapı bileşenlerini içerir:

*   **`terraform-infra/`**: Sanal makinelerin (master, worker, haproxy, nfs) provizyonlanması için Terraform yapılandırma dosyalarını içerir. Farklı ortamlar (`dev`, `staging`, `prod`) için `.tfvars` dosyaları bulunmaktadır.
*   **`ansible.sh`**: Kubespray kullanarak Kubernetes kümesini kurmak için Ansible komutlarını çalıştıran betik. Bu betik, Kubespray bağımlılıklarını yükler, envanter dosyasını yapılandırır ve Kubernetes kurulumunu başlatır.
*   **`haproxy.sh`**: HAProxy yük dengeleyiciyi kuran ve yapılandıran betik. Ayrıca, Kubernetes kümesi üzerinde çeşitli temel eklentileri (Helm chartları aracılığıyla) dağıtır.
*   **`argocd/`**: ArgoCD Helm chart değerlerini (`argocd-values.yaml`) içerir.
*   **`elk-stack-beats/`**: Elasticsearch, Filebeat, Kibana, Logstash ve Metricbeat gibi ELK Stack bileşenlerinin Helm chart değerlerini içerir.
*   **`harbor/`**: Harbor container registry Helm chart değerlerini (`harbor-values.yaml`) içerir.
*   **`ingress-files/`**: Çeşitli servisler için Kubernetes Ingress kaynaklarını içerir (ArgoCD, Elastic, Grafana, Locust, Vault).
*   **`locust/`**: Locust yük testi aracının Helm chart değerlerini (`locust-values.yaml`) ve örnek bir yük testi betiğini (`my_app_test.py`) içerir.
*   **`other-config-files/`**: Kubernetes kümesi için genel yapılandırma dosyalarını içerir (cluster-issuer, namespaces, serviceaccounts).
*   **`postgresql/`**: PostgreSQL veritabanının Helm chart değerlerini (`postgresql-values.yaml`) içerir.
*   **`prometheus-grafana/`**: Prometheus ve Grafana için özel uyarı kurallarını (`custom-alert-rules.yaml`) içerir.
*   **`vault-external-secret/`**: HashiCorp Vault ve External Secrets Operator entegrasyonu için gerekli Kubernetes manifestlerini içerir (clusterrolebinding, clustersecretstore, external-secret-dev/prod).

Bu bileşenler, altyapının her katmanını kapsayacak şekilde tasarlanmıştır ve Infrastructure as Code prensiplerine uygun olarak yönetilir.

## 3. Kurulum Akışı

Altyapı kurulumu, üç ana betik (`infra.sh`, `ansible.sh`, `haproxy.sh`) tarafından yönetilen sıralı bir süreçtir. Bu betikler, sanal makine provizyonlamasından Kubernetes kümesi kurulumuna ve temel servislerin dağıtımına kadar tüm adımları otomatikleştirmektedir.

### `infra.sh`: Terraform ile Sanal Makine Provizyonlama

`infra.sh` betiği, altyapı kurulumunun ilk adımıdır ve Terraform kullanarak sanal makinelerin provizyonlanmasından sorumludur. Bu betik, kullanıcının seçtiği ortama (`dev`, `staging`, `prod`) göre SSH anahtarları oluşturur, Terraform çalışma alanını ayarlar ve sanal makineleri oluşturur.

**Çalışma Mantığı ve Sıralama:**

1.  **Ortam Seçimi**: Kullanıcıdan `dev`, `staging` veya `prod` ortamlarından birini seçmesi istenir. Bu seçim, Terraform tarafından kullanılacak `.tfvars` dosyasını belirler.
2.  **SSH Anahtarı Üretimi**: Seçilen ortama özel bir SSH anahtar çifti (`ansible-<ortam>`) oluşturulur. Bu anahtarlar, daha sonra Ansible ve SSH bağlantıları için kullanılacaktır.
3.  **Terraform Başlatma ve Çalışma Alanı Ayarı**: `terraform init` komutu ile Terraform başlatılır ve seçilen ortama (`dev`, `staging`, `prod`) geçiş yapılır veya yeni bir çalışma alanı oluşturulur.
4.  **Terraform Plan ve Uygulama**: `terraform plan` ile yapılacak değişiklikler gösterilir ve kullanıcının onayı alındıktan sonra `terraform apply -auto-approve` ile sanal makineler provizyonlanır. Bu adım, Kubernetes master, worker, HAProxy ve NFS sunucusu için gerekli sanal makineleri oluşturur.
5.  **IP Adreslerinin Çıkarılması**: Terraform çıktısından Ansible host, HAProxy host, master ve worker düğümlerinin genel ve özel IP adresleri alınır. Bu IP adresleri, sonraki adımlarda Ansible envanter dosyaları ve HAProxy yapılandırması için kullanılacaktır.
6.  **Yerel Yapılandırma Dosyalarının Hazırlanması**: Ansible için `ansible.cfg` ve Kubespray için `hosts.yaml` dosyaları, provizyonlanan sanal makinelerin IP adresleri ve kullanıcı adları ile dinamik olarak oluşturulur. Ayrıca, HAProxy için `haproxy.cfg` dosyası da master ve worker düğümlerinin IP adreslerini içerecek şekilde hazırlanır.
7.  **Dosyaların Kopyalanması ve Sıkıştırılması**: `ansible.sh`, `haproxy.sh` betikleri ve diğer tüm Kubernetes bileşenlerinin yapılandırma dosyaları (`argocd`, `elk-stack-beats`, `harbor`, `ingress-files`, `locust`, `other-config-files`, `postgresql`, `prometheus-grafana`, `vault-external-secret` klasörleri) yerel bir `automation_configs` dizinine kopyalanır. Bu dizin daha sonra `automation_configs.tar.gz` olarak sıkıştırılır.
8.  **Dosyaların Uzak Sunuculara Kopyalanması**: Oluşturulan `automation_configs.tar.gz` dosyası, `scp` komutu kullanılarak Ansible host ve HAProxy host sanal makinelerine kopyalanır.
9.  **Uzak Betiklerin Çalıştırılması**: SSH üzerinden Ansible hosta bağlanılarak `automation_configs.tar.gz` dosyası açılır ve `ansible.sh` betiği çalıştırılır. Benzer şekilde, HAProxy hosta bağlanılarak `haproxy.sh` betiği çalıştırılır. Bu adımlar, Kubernetes kümesinin ve HAProxy yük dengeleyicinin kurulumunu başlatır.

Bu betik, altyapının temelini oluşturan sanal makinelerin ve ilk yapılandırma dosyalarının otomatik olarak hazırlanmasını sağlar.

### `ansible.sh`: Kubespray ile Kubernetes Kümesi Kurulumu

`ansible.sh` betiği, `infra.sh` tarafından provizyonlanan Ansible host üzerinde çalışır ve Kubespray kullanarak Kubernetes kümesini kurmaktan sorumludur. Bu betik, Kubespray bağımlılıklarını yükler, envanter dosyasını yapılandırır ve Kubernetes kurulumunu başlatır.

**Çalışma Mantığı ve Sıralama:**

1.  **SSH Anahtarının Taşınması ve İzinleri**: `infra.sh` tarafından oluşturulan SSH private key, Ansible host üzerindeki `.ssh` dizinine taşınır ve gerekli izinler (`chmod 400`) ayarlanır. Bu anahtar, Ansible'ın diğer Kubernetes düğümlerine SSH ile bağlanabilmesi için kullanılır.
2.  **Kubespray Deposunun Klonlanması**: `kubernetes-sigs/kubespray` reposu, Ansible host üzerine klonlanır. Bu repo, Kubernetes kurulumu için gerekli tüm Ansible playbook'larını ve envanter şablonlarını içerir.
3.  **Python Sanal Ortamının Oluşturulması ve Bağımlılıkların Yüklenmesi**: Kubespray'in gerektirdiği Python bağımlılıklarını izole etmek için bir Python sanal ortamı oluşturulur ve `requirements.txt` dosyasında belirtilen tüm bağımlılıklar `pip` kullanılarak yüklenir.
4.  **Kubespray Envanterinin Yapılandırılması**: `infra.sh` tarafından oluşturulan `hosts.yaml` dosyası, Kubespray'in `inventory/mycluster/hosts.yaml` dizinine kopyalanır. Bu dosya, Kubernetes kümesindeki master, worker, HAProxy ve NFS düğümlerinin IP adreslerini ve rollerini tanımlar.
5.  **HAProxy IP'sinin Sertifikaya Eklenmesi**: Kubernetes API sunucusunun sertifikasına HAProxy'nin özel IP adresi eklenir. Bu, HAProxy üzerinden Kubernetes API'sine erişirken SSL/TLS sertifika hatalarını önler.
6.  **SSH Agent Doğrulaması**: SSH agent başlatılır ve SSH private key eklenir. Bu, Ansible'ın parola sormadan diğer düğümlere SSH bağlantısı kurmasını sağlar.
7.  **Kubernetes Kümesi Kurulumu**: `ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml` komutu çalıştırılarak Kubespray'in ana playbook'u başlatılır. Bu adım, tüm Kubernetes bileşenlerini (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kube-proxy, etcd, CNI vb.) master ve worker düğümlerine kurar ve yapılandırır.
8.  **`kubectl` Binary Kurulumu**: Ansible host üzerine `kubectl` komut satırı aracı kurulur (eğer kurulu değilse). Bu, küme ile etkileşim kurmak için gereklidir.
9.  **`admin.conf` Dosyasının Çekilmesi ve Kubeconfig Yapılandırması**: Kubernetes master düğümlerinden birinden (`master-1`) `admin.conf` dosyası çekilir. Bu dosya, `kubectl`'in Kubernetes kümesiyle kimlik doğrulaması yapmasını sağlayan kimlik bilgilerini içerir. `admin.conf` dosyası, HAProxy'nin özel IP adresini işaret edecek şekilde düzenlenir ve Ansible host üzerindeki `~/.kube/config` dizinine kopyalanır.
10. **Küme Durumunun Kontrolü**: `kubectl get no` ve `kubectl get po -A` komutları çalıştırılarak Kubernetes düğümlerinin ve pod'larının durumu kontrol edilir. Bu, kümenin başarılı bir şekilde kurulduğunu doğrular.

Bu betik, Kubespray'in gücünü kullanarak karmaşık bir Kubernetes kümesinin otomatik olarak kurulmasını sağlar.

### `haproxy.sh`: HAProxy ve Kubernetes Eklentileri Kurulumu

`haproxy.sh` betiği, `infra.sh` tarafından provizyonlanan HAProxy host üzerinde çalışır ve HAProxy yük dengeleyiciyi kurup yapılandırmanın yanı sıra, Kubernetes kümesi üzerinde çeşitli temel eklentileri (Helm chartları aracılığıyla) dağıtmaktan sorumludur.

**Çalışma Mantığı ve Sıralama:**

1.  **SSH Anahtarının Taşınması ve İzinleri**: `infra.sh` tarafından oluşturulan SSH private key, HAProxy host üzerindeki `.ssh` dizinine taşınır ve gerekli izinler (`chmod 400`) ayarlanır. Bu anahtar, HAProxy hostun Kubernetes master düğümüne SSH ile bağlanabilmesi için kullanılır.
2.  **HAProxy Kurulumu**: `apt-get` kullanılarak HAProxy paketi kurulur. Bu, Kubernetes API sunucuları ve Ingress Controller servisleri için yük dengeleme sağlamak üzere HAProxy yazılımını sisteme yükler.
3.  **HAProxy Yapılandırma Dosyasının Kopyalanması**: `infra.sh` tarafından oluşturulan `haproxy.cfg` dosyası, `/etc/haproxy/haproxy.cfg` konumuna kopyalanır. Bu yapılandırma dosyası, Kubernetes master düğümlerinin 6443 portunu ve worker düğümlerinin 30080 (HTTP) ve 30443 (HTTPS) NodePort servislerini yük dengelemek için gerekli ayarları içerir.
4.  **HAProxy Servisinin Yeniden Başlatılması**: Yeni yapılandırmanın etkin olması için HAProxy servisi yeniden başlatılır ve durumu kontrol edilir.
5.  **`kubectl` Binary Kurulumu**: HAProxy host üzerine `kubectl` komut satırı aracı kurulur (eğer kurulu değilse). Bu, HAProxy hostun Kubernetes kümesiyle etkileşim kurabilmesi için gereklidir.
6.  **Kubeconfig Yapılandırması**: Kubernetes master düğümlerinden birinden (`master-1`) `admin.conf` dosyası çekilir. Bu dosya, `kubectl`'in Kubernetes kümesiyle kimlik doğrulaması yapmasını sağlayan kimlik bilgilerini içerir. `admin.conf` dosyası, HAProxy'nin özel IP adresini işaret edecek şekilde düzenlenir ve HAProxy host üzerindeki `~/.kube/config` dizinine kopyalanır. Bu sayede HAProxy host, küme yönetimi için kullanılabilir hale gelir.
7.  **Küme Durumunun Kontrolü**: `kubectl get no` ve `kubectl get po -A` komutları çalıştırılarak Kubernetes düğümlerinin ve pod'larının durumu kontrol edilir.
8.  **Helm ve Kustomize Kurulumu**: Kubernetes kümesine Helm chartları ve Kustomize ile uygulama dağıtımı yapmak için Helm ve Kustomize araçları kurulur.
9.  **Helm Chart Repolarının Eklenmesi**: Çeşitli Kubernetes eklentileri için gerekli Helm chart repoları (`jetstack`, `nginx`, `argo`, `prometheus-community`, `metrics-server`, `elastic`, `nfs-subdir-external-provisioner`, `hashicorp`, `external-secrets`, `harbor`, `bitnami`) eklenir ve güncellenir.
10. **Namespace'lerin Oluşturulması**: `other-config-files/namespaces.yaml` dosyasında tanımlanan Kubernetes namespace'leri oluşturulur.
11. **Cert-Manager Kurulumu**: Sertifika yönetimi için Cert-Manager kurulur ve `cluster-issuer.yaml` dosyası ile bir ClusterIssuer oluşturulur. Bu, Ingress kaynakları için otomatik SSL/TLS sertifikaları sağlamak için kullanılır.
12. **Nginx Ingress Controller Kurulumu**: Nginx Ingress Controller, NodePort servis tipiyle kurulur ve HAProxy tarafından yük dengeleme yapılacak 30080 (HTTP) ve 30443 (HTTPS) portlarına yönlendirilir.
13. **ArgoCD Kurulumu**: GitOps için ArgoCD, `argocd-values.yaml` dosyasındaki özel değerlerle kurulur.
14. **Kube-Prometheus-Stack Kurulumu**: Kubernetes kümesi için kapsamlı izleme ve uyarı sistemi olan Kube-Prometheus-Stack kurulur.
15. **Metrics Server Kurulumu**: Kubernetes kümesi için metrik toplama servisi olan Metrics Server kurulur.
16. **NFS Subdir External Provisioner Kurulumu**: NFS tabanlı kalıcı depolama sağlamak için NFS Subdir External Provisioner kurulur. Bu, `infra.sh` tarafından provizyonlanan NFS sunucusunu kullanır.
17. **ELK Stack Bileşenleri Kurulumu**: Elasticsearch, Filebeat, Logstash, Metricbeat ve Kibana gibi ELK Stack bileşenleri kurulur. Bu, log ve metrik yönetimi için merkezi bir platform sağlar.
18. **Locust Kurulumu**: Yük testi aracı Locust kurulur ve örnek bir Locustfile (`my_app_test.py`) ile yapılandırılır.
19. **PostgreSQL Kurulumu**: Uygulamalar için veritabanı servisi olarak PostgreSQL kurulur.
20. **HashiCorp Vault Kurulumu**: Sır yönetimi için HashiCorp Vault kurulur ve UI arayüzü etkinleştirilir.
21. **External Secrets Operator (ESO) Kurulumu**: Vault ile Kubernetes Secret'ları arasında senkronizasyon sağlamak için External Secrets Operator kurulur.
22. **Vault Entegrasyonu ve Sır Yönetimi**: Vault içinde `secret` KV2 motoru etkinleştirilir, `read-policy.hcl` ile okuma politikası tanımlanır, Kubernetes kimlik doğrulama yöntemi yapılandırılır ve `vault-role` oluşturulur. Örnek sırlar Vault'a eklenir.
23. **ClusterSecretStore ve External Secrets Oluşturulması**: External Secrets Operator'ın Vault ile iletişim kurmasını sağlayan `ClusterSecretStore` ve `dev`/`prod` namespace'leri için `ExternalSecret` kaynakları oluşturulur.
24. **Harbor Kurulumu**: Konteyner imajları için özel kayıt defteri olan Harbor kurulur.
25. **Service Ingress'lerin Oluşturulması**: Çeşitli servisler için Ingress kaynakları (`ingress-files/`) uygulanır, bu da uygulamaların dışarıdan erişilebilir olmasını sağlar.
26. **PVC Reclaim Policy Değişikliği**: Mevcut Persistent Volume Claim'lerin reclaim policy'si `Retain` olarak değiştirilir. Bu, PVC'ler silindiğinde verilerin korunmasını sağlar.

Bu betik, Kubernetes kümesinin tam işlevselliğini sağlamak için gerekli tüm temel servisleri ve eklentileri dağıtır ve yapılandırır.

## 4. Dizin Yapısı

`infra-mehmetkanus` reposunun dizin yapısı, altyapı bileşenlerinin düzenli bir şekilde organize edilmesini sağlar:

```
.
├── README.md
├── ansible.sh
├── argocd
│   └── argocd-values.yaml
├── elk-stack-beats
│   ├── elasticsearch
│   │   └── values.yaml
│   ├── filebeat
│   │   └── values.yaml
│   ├── kibana
│   │   └── values.yaml
│   ├── logstash
│   │   └── values.yaml
│   └── metricbeat
│       └── values.yaml
├── haproxy-manuel.sh
├── haproxy.sh
├── harbor
│   └── harbor-values.yaml
├── infra.sh
├── ingress-files
│   ├── argocd-ingress.yaml
│   ├── elastic-ingress.yaml
│   ├── grafana-ingress.yaml
│   ├── locust-ingress.yaml
│   └── vault-ingress.yaml
├── locust
│   ├── locust-values.yaml
│   └── my_app_test.py
├── other-config-files
│   ├── cluster-issuer.yaml
│   ├── namespaces.yaml
│   └── serviceaccounts.yaml
├── postgresql
│   └── postgresql-values.yaml
├── prometheus-grafana
│   └── custom-alert-rules.yaml
├── terraform-infra
│   ├── dev.tfvars
│   ├── main.tf
│   ├── prod.tfvars
│   ├── providers.tf
│   ├── staging.tfvars
│   └── variables.tf
└── vault-external-secret
    ├── clusterrolebinding.yaml
    ├── clustersecretstore.yaml
    ├── external-secret-dev.yaml
    └── external-secret-prod.yaml
```
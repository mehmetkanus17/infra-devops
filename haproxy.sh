#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# HAProxy HOST ÜZERİNDE ÇALIŞACAK KOMUTLAR BAŞLANGICI
echo -e "${YELLOW}HAProxy Sunucusu: HAProxy Kurulum ve Yapılandırma Betiği Başlatılıyor...${NC}"

# Başlangıç değişkenleri
REMOTE_CONFIG_DIR="${HOME}/automation_configs"
SSH_KEY_PATH="${REMOTE_CONFIG_DIR}/ansible-prod"
ARGOCD=${REMOTE_CONFIG_DIR}/argocd
ELK_STACK_BEATS=${REMOTE_CONFIG_DIR}/elk-stack-beats
HARBOR=${REMOTE_CONFIG_DIR}/harbor
HELM_INGRESS_FILES=${REMOTE_CONFIG_DIR}/ingress-files
LOCUST=${REMOTE_CONFIG_DIR}/locust
OTHER_CONFIG_FILES=${REMOTE_CONFIG_DIR}/other-config-files
POSTGRESQL=${REMOTE_CONFIG_DIR}/postgresql
PROMETHEUS_GRAFANA=${REMOTE_CONFIG_DIR}/prometheus-grafana
VAULT_EXTERNAL_SECRET=${REMOTE_CONFIG_DIR}/vault-external-secret

# automation_configs klasöründeki private key'in .ssh altına taşınması ve izinlerinin ayarlanması
cp ~/automation_configs/ansible-prod ~/.ssh/ 
chmod 400 ~/.ssh/ansible-prod

# HAProxy kurulumu
echo -e "${YELLOW}HAProxy Sunucusu: Adım 1: HAProxy Kurulumu.${NC}"
echo -e "${YELLOW}HaProxy kurulumu yapılıyor...${NC}"
sudo apt-get update
sudo apt-get install haproxy -y

if [ $? -eq 0 ]; then
    echo -e "${GREEN}HAProxy başarıyla kuruldu.${NC}"
else
    echo -e "${RED}HAProxy kurulumunda hata oluştu. Lütfen kontrol edin.${NC}"
    exit 1
fi

# Infra.sh tarafından oluşturulan haproxy.cfg'yi kopyala
echo -e "${YELLOW}HAProxy Sunucusu: Adım 2: HAProxy Yapılandırma Dosyası Kopyalanıyor (/etc/haproxy/haproxy.cfg)${NC}"
sudo cp -r "${HOME}/automation_configs/haproxy.cfg" "/etc/haproxy/haproxy.cfg"
echo -e "${GREEN}HAProxy Yapılandırma Dosyası Kopyalandı.${NC}"

# haproxy sunucusunun yeniden başlatılması
echo -e "${YELLOW}HAProxy Sunucusu: Adım 3: HAProxy Servisi Yeniden Başlatılıyor...${NC}"
sudo systemctl restart haproxy

if [ $? -eq 0 ]; then
    echo -e "${GREEN}HAProxy Sunucusu: HAProxy servisi başarıyla yeniden başlatıldı.${NC}"
else
    echo -e "${RED}HAProxy Sunucusu: HAProxy servisi yeniden başlatılırken hata oluştu. Lütfen kontrol edin.${NC}"
    exit 1
fi

# haproxy sunucu durumu
echo -e "${YELLOW}HAProxy Sunucu durumu kontrol ediliyor...${NC}"
sudo systemctl status haproxy | grep "Active:"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}HAProxy Sunucusu: HAProxy servisi ACTIVE durumda.${NC}"
else
    echo -e "${RED}HAProxy Sunucusu: HAProxy servisi çalışmıyor. Lütfen hata mesajlarını kontrol edin.${NC}"
fi

# kubectl tool'un kurulumu (eğer daha önce kurulu değilse)
echo -e "\n${YELLOW}kubectl binary kontrol ediliyor ve gerekiyorsa kuruluyor...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}kubectl bulunamadı, indiriliyor ve kuruluyor...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    echo -e "${GREEN}kubectl başarıyla kuruldu.${NC}"
else
    echo -e "${GREEN}kubectl zaten yüklü.${NC}"
fi

# alias k='kubectl' into .bashrc
echo -e "${YELLOW}alias k='kubectl' parametresi .bashrc dosyasına ekleniyor...${NC}"
sudo cat <<EOF >> ~/.bashrc
alias k='kubectl'
EOF
echo -e "${GREEN}alias k='kubeclt' parametresi .bashrc dosyasına eklendi.${NC}"

# SSH agent doğrulaması
echo -e "${YELLOW}SSH agent doğrulaması yaplıyor...${NC}"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/ansible-prod
echo -e "${GREEN}SSH agent doğrulaması yapıldı.${NC}"

# kubeconfig yapılandırılması
echo -e "\n${YELLOW}HAProxy Sunucusu: Adım 4: master-1 Node'undan admin.conf alınıyor ve kubectl yapılandırılıyor...${NC}"
MASTER1_IP=$(grep 'master-1:' ~/automation_configs/hosts.yaml -A 4 | grep 'ansible_host:' | awk '{print $2}')

HAPROXY_PRIVATE_IP=$(grep 'haproxy:' ~/automation_configs/hosts.yaml -A 4 | grep 'ansible_host:' | awk '{print $2}')

if [ -z "$HAPROXY_PRIVATE_IP" ]; then
    echo -e "${RED}HAProxy Sunucusu: HATA: haproxy IP adresi automation_configs/hosts.yaml dosyasında bulunamadı.${NC}"
    exit 1
fi

# admin.conf dosyasını master-1 node'dan kopyalanması
echo -e "${YELLOW}HAProxy Sunucusu: master-1 (${MASTER1_IP}) adresinden admin.conf çekiliyor...${NC}"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/ansible-prod "produser@${MASTER1_IP}" "sudo cat /etc/kubernetes/admin.conf" > ~/admin.conf
echo -e "${GREEN}HAProxy Sunucusu: master-1 (${MASTER1_IP}) adresinden admin.conf çekildi.${NC}"

# Dosya başarıyla indirildiyse kopyalama işlemininin yapılması
echo -e "${YELLOW}admin.conf dosyası, HAProxy sunucusu için yapılandırılıyor...${NC}"
if [ -s ~/admin.conf ]; then
    mkdir -p ~/.kube
    cp ~/admin.conf ~/.kube/config
    chown "$(id -u):$(id -g)" ~/.kube/config
    sed -i "s|https://127.0.0.1:6443|https://${HAPROXY_PRIVATE_IP}:6443|g" ~/.kube/config
    rm -f ~/admin.conf
    echo -e "\n${GREEN}HAProxy Sunucusu: HAProxy Sunucusu Yapılandırması ve kubectl Kurulumu Tamamlandı.${NC}"
else
    echo -e "${RED}admin.conf dosyası alınamadı. Kullanıcı erişimi veya sudo yetkisini kontrol edin.${NC}"
    exit 1
fi

# cluster check edilmesi
echo -e "${YELLOW}HAProxy Sunucusu: Kubernetes node'ları kontrol ediliyor...${NC}"
kubectl get no
echo -e "${YELLOW}HAProxy Sunucusu: Kubernetes pod'ları kontrol ediliyor...${NC}"
kubectl get po -A

# Proje için diğer gerekliliklerin yüklenmsi
echo -e "\n${YELLOW}Diğer gereklilikler yüklenecek.${NC}"

# helm
echo -e "\n${YELLOW}helm yükleniyor...${NC}"
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
echo -e "\n${GREEN}helm yüklendi.${NC}"

# kustomize
echo -e "\n${YELLOW}kustomize yükleniyor...${NC}"
sudo apt install kustomize
echo -e "\n${GREEN}kustomize yüklendi.${NC}"

# helm chartlar kurulacak
echo -e "\n${YELLOW}Gerekli helm chartlar yükleniyor...${NC}"
helm repo add jetstack https://charts.jetstack.io
helm repo add nginx https://kubernetes.github.io/ingress-nginx
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo add elastic https://helm.elastic.co
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add external-secrets https://charts.external-secrets.io
helm repo add harbor https://helm.goharbor.io
helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
echo -e "\n${GREEN}helm chartlar indirildi.${NC}"

# namespace'lerin oluşturulması
echo -e "\n${YELLOW}namespace'ler oluşturuluyor...${NC}"
cd ${OTHER_CONFIG_FILES}
kubectl apply -f namespaces.yaml
echo -e "\n${GREEN}namespace'ler oluşturuldu.${NC}"

# cert-manager kurulumu
echo -e "\n${YELLOW}cert-manager kuruluyor...${NC}"
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.16.1 \
    --set crds.enabled=true
echo -e "\n${GREEN}cert-manager kuruldu.${NC}"

# clusterissuer oluşturulması
echo -e "\n${YELLOW}clusterissuer oluşturuluyor...${NC}"
cd ${OTHER_CONFIG_FILES}
kubectl apply -f cluster-issuer.yaml
echo -e "\n${GREEN}clusterissuer oluşturuldu.${NC}"

# nginx ingress kurulumu:
echo -e "\n${YELLOW}nginx ingress controller kuruluyor...${NC}"
helm upgrade --install nginx-ingress nginx/ingress-nginx \
    --namespace ingress-nginx \
    --version 4.11.3 \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443 \
    --set controller.service.externalTrafficPolicy=Local
# --set controller.admissionWebhooks.enabled=false
echo -e "\n${GREEN}nginx ingress controller kuruldu.${NC}"

# argocd (gitops) kurulumu
echo -e "\n${YELLOW}argocd (gitops) kuruluyor...${NC}"
helm upgrade --install argocd argo/argo-cd --namespace argocd -f ${ARGOCD}/argocd-values.yaml
echo -e "\n${GREEN}argocd (gitops) kuruldu.${NC}"

# kube-prometheus-stack kurulumu
echo -e "\n${YELLOW}kube-prometheus-stack kuruluyor...${NC}"
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    --set grafana.adminPassword=Mkanus-123*-
echo -e "\n${GREEN}kube-prometheus-stack kuruldu.${NC}"

# Metrics Serve kurulumu
echo -e "\n${YELLOW}Metrics Serve kuruluyor...${NC}"
helm install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    --set args={--kubelet-insecure-tls}
echo -e "\n${GREEN}Metrics Serve kuruldu...${NC}"

# nfs-subdir-external-provisioner kurulumu
## NFS sunucusunun IP adresi ve dizin yolu
NFS_SERVER_IP=$(grep 'nfs:' ~/automation_configs/hosts.yaml -A 4 | grep 'ansible_host:' | awk '{print $2}')
NFS_PATH="/srv/nfs/kubedata"  # terraform NFS sunucuda export edilen dizin ile aynı olacak

## NFS Provisioner kurulumu
echo -e "${YELLOW}Helm ile NFS Provisioner kuruluyor...${NC}"
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --set nfs.server=${NFS_SERVER_IP} \
  --set nfs.path=${NFS_PATH} \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true \
  --set storageClass.reclaimPolicy=Delete
echo -e "${GREEN}NFS Provisioner kurulumu tamamlandı. StorageClass: nfs-client${NC}"

# elk-stack-beats kurulumu
echo -e "\n${YELLOW}elk-stack-beats bileşenleri kuruluyor...${NC}"
NAMESPACE="elasticsearch"
VALUES_FILE="values.yaml"
cd ${ELK_STACK_BEATS}

## elasticsearch
echo -e "\n${YELLOW}elasticsearch kuruluyor...${NC}"
cd elasticsearch
helm upgrade --install elastic elastic/elasticsearch -f ${VALUES_FILE} -n ${NAMESPACE} --version 8.5.1
sleep 15

## filebeat
echo -e "\n${YELLOW}filebeat kuruluyor...${NC}"
cd ../filebeat
helm upgrade --install filebeat elastic/filebeat -f ${VALUES_FILE} -n ${NAMESPACE} --version 8.5.1 
sleep 15

## logstash
echo -e "\n${YELLOW}logstash kuruluyor...${NC}"
cd ../logstash
helm upgrade --install logstash elastic/logstash -f ${VALUES_FILE} -n ${NAMESPACE} --version 8.5.1
sleep 15

## metricbeat
echo -e "\n${YELLOW}metricbeat kuruluyor...${NC}"
cd ../metricbeat
helm upgrade --install metricbeat elastic/metricbeat -f ${VALUES_FILE} -n ${NAMESPACE} --version 8.5.1 
sleep 15

## kibana
echo -e "\n${YELLOW}kibana kuruluyor...${NC}"
cd ../kibana
helm upgrade --install kibana elastic/kibana -f ${VALUES_FILE} -n ${NAMESPACE} --version 8.5.1
echo -e "\n${GREEN}elk-stack-beats kurulumu tamamlandı.${NC}"

# locust kurulumu
echo -e "${YELLOW}locust kuruluyor...${NC}"
cd ${LOCUST}
kubectl create configmap my-app-locustfile --from-file=my_app_test.py -n locust
helm upgrade --install locust oci://ghcr.io/deliveryhero/helm-charts/locust --namespace locust -f locust-values.yaml
echo -e "${GREEN}locust kuruldu.${NC}"

# postgresql kurulumu
echo -e "${YELLOW}postgresql kuruluyor...${NC}"
helm upgrade --install postgresql bitnami/postgresql --namespace postgresql -f ${POSTGRESQL}/postgresql-values.yaml
echo -e "${GREEN}postgresql kuruldu.${NC}"

# vault kurulumu
echo -e "${YELLOW}hashicorp/vault kuruluyor...${NC}"
## prod ortam için
# helm upgrade --install vault hashicorp/vault \
#   --namespace vault --create-namespace \
#   --set "server.ha.enabled=false" \
#   --set "server.ui.enabled=true" \
#   --set "server.service.active.enabled=false" \
#   --set "server.service.standby.enabled=false" \
#   --set "server.standalone.enabled=true" \
#   --set "server.resources.requests.memory=1Gi" \
#   --set "server.resources.requests.cpu=500m" \
#   --set "server.resources.limits.memory=2Gi" \
#   --set "server.resources.limits.cpu=1000m" \
#   --set "server.livenessProbe.enabled=true" \
#   --set "server.livenessProbe.path=/v1/sys/health?standbyok=true" \
#   --set "server.livenessProbe.initialDelaySeconds=60" \
#   --set "server.livenessProbe.periodSeconds=10" \
#   --set "server.livenessProbe.timeoutSeconds=5" \
#   --set "server.livenessProbe.failureThreshold=3"

## dev ortam için
helm upgrade --install vault hashicorp/vault \
    --namespace vault \
    --set 'server.dev.enabled=true' \
    --set 'ui.enabled=true'

echo -e "${YELLOW}Vault Pod hazır olana kadar bekleniyor...${NC}"
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault -n vault --timeout=90s
echo -e "${GREEN}hashicorp/vault kurulumu tamamlandı.${NC}"

# External Secrets Operator (ESO) (vault)
echo -e "\n${YELLOW}External Secrets Operator (ESO) kuruluyor...${NC}"
helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace \
    --set installCRDs=true
echo -e "\n${GREEN}External Secrets Operator (ESO) kuruldu.${NC}"

# external-secret için clusterrolebinding oluşturulması
echo -e "\n${YELLOW}external-secret için clusterrolebinding oluşturuluyor...${NC}"
cd ${VAULT_EXTERNAL_SECRET}
kubectl apply -f clusterrolebinding.yaml
echo -e "\n${GREEN}external-secret için clusterrolebinding oluşturuldu.${NC}"

# dev ve prod ns'lerinde serviceaccount oluşturulması
echo -e "\n${YELLOW}dev ve prod ns'lerine serviceaccount oluşturuluyor...${NC}"
cd ${OTHER_CONFIG_FILES}
kubectl apply -f serviceaccounts.yaml
echo -e "\n${GREEN}dev ve prod ns'lerine serviceaccount oluşturuldu.${NC}"

## vault ayarlamaların yapılması
echo -e "${YELLOW}vault ayarlamaları yapılıyor...${NC}"

## 1. Kubernetes API ve CA bilgileri alnıyor (cluster içinden)
echo -e "${YELLOW}Kubernetes API ve CA bilgileri alınıyor...${NC}"
KUBERNETES_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
KUBERNETES_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode)

echo "Kubernetes Host: ${KUBERNETES_HOST}"
echo "Kubernetes CA Certificate (Base64 Encoded): ${KUBERNETES_CA_CERT}"
echo -e "${GREEN}Kubernetes API ve CA bilgileri alındı.${NC}"

## 2. vault podu içinde yapılandırmalar 
echo -e "${YELLOW}Vault podunda yapılandırmalar yapılıyor...${NC}"

kubectl exec -n vault vault-0 -- /bin/sh -c "

vault secrets enable -path=secret kv2

cat <<EOF > /home/vault/read-policy.hcl
path \"secret/data/*\" {
  capabilities = [\"read\"]
}
EOF

vault policy write read-policy /home/vault/read-policy.hcl

vault auth enable kubernetes

vault write auth/kubernetes/config \
   token_reviewer_jwt=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
   kubernetes_host=${KUBERNETES_HOST} \
   kubernetes_ca_cert='${KUBERNETES_CA_CERT}'

vault write auth/kubernetes/role/vault-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets,dev,prod \
  policies=read-policy \
  ttl=24h

vault kv put secret/first-secret username=mkanus password=mkanus123
vault kv list secret
"
echo -e "${GREEN}Vault podunda yapılandırmalar yapıldı.${NC}"

# vault yapılandırmasının senkronize olması için bekleme 
echo -e "${YELLOW}External Secrets Controller ve Vault Kubernetes Auth Metodunun senkronize olması bekleniyor...${NC}"
sleep 30

# external-secret için clustersecretstore oluşturulması
echo -e "\n${YELLOW}external-secret için clustersecretstore oluşturuluyor...${NC}"
cd ${VAULT_EXTERNAL_SECRET}
kubectl apply -f clustersecretstore.yaml
echo -e "\n${GREEN}external-secret için clustersecretstore oluşturuldu.${NC}"

# dev prod namespace'leri için external-secret oluşturulması
echo -e "\n${YELLOW}dev prod namespace'leri için external-secret'lar oluşturuluyor...${NC}"
cd ${VAULT_EXTERNAL_SECRET}
kubectl apply -f external-secret-dev.yaml
kubectl apply -f external-secret-prod.yaml
echo -e "\n${GREEN}dev prod namespace'leri için external-secret'lar oluşturuldu.${NC}"

# Harbor kurulumu
echo -e "\n${YELLOW}Harbor kuruluyor...${NC}"
helm install harbor harbor/harbor --namespace harbor  -f ${HARBOR}/harbor-values.yaml
echo -e "\n${GREEN}Harbor kuruldu.${NC}"

# service ingress'lerin oluşturulması
echo -e "\n${YELLOW}service ingress'leri oluşturuluyor...${NC}"
cd ${HELM_INGRESS_FILES}
kubectl apply -f .
echo -e "\n${GREEN}service ingress'leri oluşturuldu.${NC}"

# Persistent Volume Claim Reclaim Policy değişikliği (delete)
echo -e "\n${GREEN} Persistent Volume Claim Reclaim Policy değişikliği yapılıyor...${NC}"
kubectl get pv | grep Delete | awk '{print$1}' | xargs -I %  kubectl patch pv % -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
echo -e "\n${GREEN} Persistent Volume Claim Reclaim Policy değişikliği yapıldı${NC}"

# node ve pod bilgileri son kez kontrol ediliyor
echo -e "${YELLOW}HAProxy Sunucusu: Kubernetes node'ları kontrol ediliyor:${NC}"
kubectl get no -owide
echo -e "${YELLOW}HAProxy Sunucusu: Kubernetes pod'ları kontrol ediliyor:${NC}"
kubectl get po -A -owide
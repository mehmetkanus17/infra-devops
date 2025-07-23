#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# TERRAFORM İLE ALT YAPI OLUŞTURULMASI
echo -e "${GREEN}Kubernetes Altyapı ve Kurulum Otomasyonu Başlatılıyor...${NC}"

# Yerel olarak oluşturulacak yapılandırma dosya dizinleri
LOCAL_CONFIG_DIR="${HOME}/automation_configs"
LOCAL_TAR_FILE="${HOME}/automation_configs.tar.gz"
TERRAFORM_INFRA_DIR="terraform-infra/"

# kullanıcıdan bir ortam seçmesi istenecek.
while :; do
    echo -e "\n${YELLOW}Lütfen bir Terraform ortamı seçin:${NC}"
    sleep 0.5
    echo "1) dev (Geliştirme Ortamı)"
    echo "2) staging (Staging Ortamı)"
    echo "3) prod (Üretim Ortamı)"
    echo "4) Çıkış"

    read -rp "Seçiminiz (1-4): " environment_selection

    case $environment_selection in
        1)
            WORKSPACE="dev"
            break
            ;;
        2)
            WORKSPACE="staging"
            break
            ;;
        3)
            WORKSPACE="prod"
            break
            ;;
        4)
            echo -e "${YELLOW}Çıkış yapılıyor.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Geçersiz seçim. Lütfen 1 ile 4 arasında bir sayı girin.${NC}"
            sleep 1
            ;;
    esac
done
echo -e "${GREEN}Seçilen Terraform ortamı: ${WORKSPACE}${NC}"

# SSH Key Üretimi ve İzinleri
echo -e "${YELLOW}SSH key üretiliyor ve izinler ayarlanıyor...${WORKSPACE}${NC}"
USERNAME="${WORKSPACE}-user"
SSH_KEY_PATH="${HOME}/.ssh/ansible-${WORKSPACE}"

if [ -f "${SSH_KEY_PATH}" ]; then
    read -rp "SSH anahtarı zaten mevcut (${SSH_KEY_PATH}). Üzerine yazılsın mı? (evet/hayır): " overwrite_key
    if [[ "$overwrite_key" == "evet" ]]; then
        rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
        ssh-keygen -t rsa -f "${SSH_KEY_PATH}" -C "${USERNAME}" -N ""
    else
        echo -e "${YELLOW}Mevcut SSH anahtarı kullanılacak.${NC}"
    fi
else
    ssh-keygen -t rsa -f "${SSH_KEY_PATH}" -C "${USERNAME}" -N ""
    echo -e "\n${YELLOW}SSH key üretildi.${NC}"
fi
echo -e "${YELLOW}SSH key üretildi.${WORKSPACE}${NC}"

ls -l "${HOME}/.ssh/" | grep "ansible-${WORKSPACE}"
chmod 400 "${SSH_KEY_PATH}"
chmod 644 "${SSH_KEY_PATH}.pub"
echo -e "${GREEN}SSH anahtar izinleri ayarlandı.${NC}"

# Terraform init
echo -e "\n${YELLOW}Terraform başlatılıyor...${NC}"
cd ${TERRAFORM_INFRA_DIR}
terraform init
echo -e "\n${GREEN}Terraform başlatıldı.${NC}"

# Terraform Workspace
echo -e "\n${YELLOW}Terraform workspace ayarlanıyor...${NC}"
if ! terraform workspace list | grep -q "${WORKSPACE}"; then
    echo -e "${YELLOW}Workspace ${WORKSPACE} bulunamadı, oluşturuluyor...${NC}"
    terraform workspace new "${WORKSPACE}"
    echo -e "\n${GREEN}Terraform workspace: "${WORKSPACE}" olarak ayarlandı.${NC}"
else
    echo -e "${YELLOW}Workspace ${WORKSPACE} zaten mevcut, geçiş yapılıyor...${NC}"
    terraform workspace select "${WORKSPACE}"
fi

# Terraform plan
echo -e "\n${YELLOW}Terraform plan çalıştırılıyor...${NC}"
terraform plan -var-file="${WORKSPACE}.tfvars"
echo -e "\n${GREEN}Terraform plan çalıştırıldı.${NC}"

echo -e "\n${YELLOW}Terraform apply çalıştırılıyor...${NC}"
read -rp "Terraform apply için onayınız bekleniyor... (yes/no): " apply_confirm

if [[ "$apply_confirm" == "yes" ]]; then
    echo -e "${YELLOW}Terraform değişiklikleri uygulanıyor...${NC}"
    terraform apply -var-file="${WORKSPACE}.tfvars" -auto-approve

    ANSIBLE_PUBLIC_IP=$(terraform output -raw ansible_public_ip)
    HAPROXY_PUBLIC_IP=$(terraform output -raw haproxy_public_ip)
    ADMIN_USERNAME=$(terraform output -raw admin_username)
    ALL_PRIVATE_IPS_JSON=$(terraform output -json vm_private_ips)

    MASTER_PRIVATE_IPS=$(echo "$ALL_PRIVATE_IPS_JSON" | jq -r 'to_entries[] | select(.key | startswith("master-")) | .value')
    WORKER_PRIVATE_IPS=$(echo "$ALL_PRIVATE_IPS_JSON" | jq -r 'to_entries[] | select(.key | startswith("worker-")) | .value')

    echo -e "${GREEN}Ansible host IP'si: ${ANSIBLE_PUBLIC_IP}${NC}"
    echo -e "${GREEN}HAProxy host IP'si: ${HAPROXY_PUBLIC_IP}${NC}"
    echo -e "${GREEN}Kullanıcı adı: ${ADMIN_USERNAME}${NC}"
    echo -e "${GREEN}Master Private IP'leri:${NC}"
    echo "$MASTER_PRIVATE_IPS"
    echo -e "${GREEN}Worker Private IP'leri:${NC}"
    echo "$WORKER_PRIVATE_IPS"

    echo -e "\n${YELLOW}SSH Agent başlatılıyor ve anahtar ekleniyor...${NC}"
    eval "$(ssh-agent -s)"
    ssh-add "${SSH_KEY_PATH}"
    echo -e "\n${GREEN}SSH Agent işlemleri tamamlandı.${NC}"

    echo -e "\n${YELLOW}Yapılandırma dosyaları yerel olarak hazırlanıyor: ${LOCAL_CONFIG_DIR}${NC}"
    rm -rf "${LOCAL_CONFIG_DIR}"
    mkdir -p "${LOCAL_CONFIG_DIR}"

    # --- Kubespray için ansible.cfg oluşturma ---
    echo -e "\n${YELLOW}Kubespray için ansible.cfg oluşturuluyır...${NC}"
    cat << EOF_ANSIBLE_CFG > "${LOCAL_CONFIG_DIR}/ansible.cfg"
inventory = inventory/mycluster/hosts.yaml
remote_user = ${ADMIN_USERNAME}
private_key_file = ~/.ssh/ansible-${WORKSPACE}
EOF_ANSIBLE_CFG
    echo -e "${GREEN}ansible.cfg dosyası ${LOCAL_CONFIG_DIR} içinde oluşturuldu.${NC}"

    # --- Kubespray için hosts.yaml oluşturma ---
    IFS=$'\n' read -d '' -r -a masters <<< "$MASTER_PRIVATE_IPS"
    IFS=$'\n' read -d '' -r -a workers <<< "$WORKER_PRIVATE_IPS"
    echo -e "${YELLOW}hosts.yaml dosyası ${LOCAL_CONFIG_DIR} içinde oluşturuluyor...${NC}"
    {
        echo "all:"
        echo "  hosts:"
        echo "    haproxy:"
        echo "      ansible_host: $(terraform output -json vm_private_ips | jq -r '.haproxy')"
        echo "      ip: $(terraform output -json vm_private_ips | jq -r '.haproxy')"
        echo "      access_ip: $(terraform output -json vm_private_ips | jq -r '.haproxy')"
        echo "      ansible_user: ${ADMIN_USERNAME}"

        echo "    nfs:"
        echo "      ansible_host: $(terraform output -json vm_private_ips | jq -r '.nfs')"
        echo "      ip: $(terraform output -json vm_private_ips | jq -r '.nfs')"
        echo "      access_ip: $(terraform output -json vm_private_ips | jq -r '.nfs')"
        echo "      ansible_user: ${ADMIN_USERNAME}"
        
        for i in "${!masters[@]}"; do
            echo "    master-$((i+1)):"
            echo "      ansible_host: ${masters[$i]}"
            echo "      ip: ${masters[$i]}"
            echo "      access_ip: ${masters[$i]}"
            echo "      ansible_user: ${ADMIN_USERNAME}"
        done
        for i in "${!workers[@]}"; do
            echo "    worker-$((i+1)):"
            echo "      ansible_host: ${workers[$i]}"
            echo "      ip: ${workers[$i]}"
            echo "      access_ip: ${workers[$i]}"
            echo "      ansible_user: ${ADMIN_USERNAME}"
        done
        echo "  children:"
        echo "    kube_control_plane:"
        echo "      hosts:"
        for i in "${!masters[@]}"; do
            echo "        master-$((i+1)):"
        done
        echo "    etcd:"
        echo "      hosts:"
        for i in "${!masters[@]}"; do
            echo "        master-$((i+1)):"
        done
        echo "    kube_node:"
        echo "      hosts:"
        for i in "${!workers[@]}"; do
            echo "        worker-$((i+1)):"
        done
        echo "    k8s_cluster:"
        echo "      children:"
        echo "        kube_control_plane"
        echo "        kube_node"
    } > "${LOCAL_CONFIG_DIR}/hosts.yaml"
    echo -e "${GREEN}hosts.yaml dosyası ${LOCAL_CONFIG_DIR} içinde oluşturuldu.${NC}"

    # --- HAProxy host için haproxy.cfg oluşturma ---
echo -e "${YELLOW}haproxy.cfg dosyası ${LOCAL_CONFIG_DIR} içinde oluşturuluyor...${NC}"
HAPROXY_CFG_CONTENT=$(cat <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

defaults
    log     global
    mode    tcp
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend masters
    bind *:6443
    mode tcp
    option tcplog
    default_backend masters

backend masters
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
EOF
)

for i in "${!masters[@]}"; do
    HAPROXY_CFG_CONTENT+="
    server master-$((i+1)) ${masters[$i]}:6443 check"
done

HAPROXY_CFG_CONTENT+="

frontend http_front
    bind *:80
    mode tcp
    option tcplog
    default_backend workers_http

frontend https_front
    bind *:443
    mode tcp
    option tcplog
    default_backend workers_https

backend workers_http
    mode tcp
    option tcplog
    balance roundrobin
"

for i in "${!workers[@]}"; do
    HAPROXY_CFG_CONTENT+="
    server worker-$((i+1)) ${workers[$i]}:30080 check"
done

HAPROXY_CFG_CONTENT+="

backend workers_https
    mode tcp
    option tcplog
    balance roundrobin
"

for i in "${!workers[@]}"; do
    HAPROXY_CFG_CONTENT+="
    server worker-$((i+1)) ${workers[$i]}:30443 check"
done

echo -e "$HAPROXY_CFG_CONTENT" > "${LOCAL_CONFIG_DIR}/haproxy.cfg"
echo -e "${GREEN}haproxy.cfg dosyası ${LOCAL_CONFIG_DIR} içinde oluşturuldu.${NC}"

    # infra dosyaların otomasyon klasörüne kopyalanması
    echo -e "\n${YELLOW}Gerekli infra dosyalar ${LOCAL_CONFIG_DIR} içine kopyalanıyor...${NC}"
    cd ..
    cp "./ansible.sh" "${LOCAL_CONFIG_DIR}/ansible.sh"
    cp "./haproxy.sh" "${LOCAL_CONFIG_DIR}/haproxy.sh"
    cp "${SSH_KEY_PATH}" "${LOCAL_CONFIG_DIR}/ansible-${WORKSPACE}"
    cp -r "./argocd" "${LOCAL_CONFIG_DIR}/"
    cp -r "./elk-stack-beats" "${LOCAL_CONFIG_DIR}/"
    cp -r "./harbor" "${LOCAL_CONFIG_DIR}/"
    cp -r "./ingress-files" "${LOCAL_CONFIG_DIR}/"
    cp -r "./locust" "${LOCAL_CONFIG_DIR}/"
    cp -r "./other-config-files" "${LOCAL_CONFIG_DIR}/"
    cp -r "./postgresql" "${LOCAL_CONFIG_DIR}/"
    cp -r "./prometheus-grafana" "${LOCAL_CONFIG_DIR}/"
    cp -r "./vault-external-secret" "${LOCAL_CONFIG_DIR}/"
    echo -e "\n${GREEN}Gerekli infra dosyalar ${LOCAL_CONFIG_DIR} içine kopyalandı.${NC}"

    # otomasyon klasörün tarlanması.
    echo -e "\n${YELLOW}Config klasörü tarlanıyor: ${LOCAL_TAR_FILE}${NC}"
    tar -czf "${LOCAL_TAR_FILE}" -C "${HOME}" "$(basename "${LOCAL_CONFIG_DIR}")"
    echo -e "${GREEN}Config klasörü başarıyla tarlanmış ve sıkıştırılmıştır.${NC}"

    # Tar dosyasını Ansible host'a kopyalanması
    echo -e "\n${YELLOW}Tar dosyası (${LOCAL_TAR_FILE}) Ansible host'a kopyalanıyor...${NC}"
    scp -o StrictHostKeyChecking=no "${LOCAL_TAR_FILE}" "${ADMIN_USERNAME}@${ANSIBLE_PUBLIC_IP}:~/"
    echo -e "\n${GREEN}Tar dosyası (${LOCAL_TAR_FILE}) Ansible host'a kopyalandı.${NC}"

    # Tar dosyasını HAProxy host'a kopyalanması
    echo -e "\n${YELLOW}Tar dosyasını (${LOCAL_TAR_FILE}) HAProxy host'a kopyalanıyor...${NC}"
    scp -o StrictHostKeyChecking=no "${LOCAL_TAR_FILE}" "${ADMIN_USERNAME}@${HAPROXY_PUBLIC_IP}:~/"
    echo -e "\n${GREEN}Tar dosyasını (${LOCAL_TAR_FILE}) HAProxy host'a kopyalandı.${NC}"

    # Ansible host üzerinde kubernetes kulumun yapılması
    echo -e "\n${YELLOW}Ansible host üzerinde dosyalar açılıyor ve Kubernetes kurulum betiği başlatılıyor...${NC}"
    ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "${ADMIN_USERNAME}@${ANSIBLE_PUBLIC_IP}" << 'EOF_REMOTE_COMMANDS'
        echo "Uzak sunucuda: Tar dosyası açılıyor..."
        tar -xzf "automation_configs.tar.gz" -C "${HOME}"
        echo "Uzak sunucuda: Dosyalar açıldı."    
        mv automation_configs/ansible.sh ~/ && cd ~/ && chmod +x ansible.sh
        ./ansible.sh
EOF_REMOTE_COMMANDS
    echo -e "\n${YELLOW}Ansible host üzerinde dosyalar açılıyor ve Kubernetes kurulum betiği başlatılıyor...${NC}"

    # HAProxy host üzerinde HAproxy kurulumu ve kubernetes konfigürasyosnun yapılması
    echo -e "\n${YELLOW}HAProxy host üzerinde dosyalar açılıyor ve HAProxy kurulum betiği başlatılıyor...${NC}"
    ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "${ADMIN_USERNAME}@${HAPROXY_PUBLIC_IP}" << 'EOF_REMOTE_COMMANDS'
        echo "Uzak sunucuda: Tar dosyası açılıyor..."
        tar -xzf "automation_configs.tar.gz" -C "${HOME}"
        echo "Uzak sunucuda: Dosyalar açıldı."    
        mv automation_configs/haproxy.sh ~/ && cd ~/ && chmod +x haproxy.sh
        ./haproxy.sh
EOF_REMOTE_COMMANDS
    echo -e "\n${GREEN}HAProxy host HAProxy kurulumu ve kubernetes konfigürasyonu tamamlandı..${NC}"

else
    echo -e "${RED}Terraform uygulama iptal edildi.${NC}"
fi

# Local'den ansible-host'a veya HAProxy-host'a SSH bağlantısı (isteğe bağlı)
# ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "${ADMIN_USERNAME}@${ANSIBLE_PUBLIC_IP}"
echo -e "\n${GREEN}HAProxy sunucusuna SSH ile bağlanıldı.${NC}"
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "${ADMIN_USERNAME}@${HAPROXY_PUBLIC_IP}"

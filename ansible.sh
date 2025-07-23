#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ANSIBLE HOST ÜZERİNDE ÇALIŞACAK KOMUTLAR BAŞLANGICI
echo -e "${YELLOW}Adım 1: Kubespray Ön Gereksinimleri kuruluyor...${NC}"

# automation_configs klasöründeki private key'in .ssh altına taşınması ve izinlerinin ayarlanması
echo -e "${YELLOW}ssh private key'in ilgili klasöre taşınıyor ve izinleri ayarlanıyor...${NC}"
cp ~/automation_configs/ansible-prod ~/.ssh/ 
chmod 400 ~/.ssh/ansible-prod
echo -e "${GREEN}ssh private key ayarları yapıldı.${NC}"

# kubespray deposu clone'lama
echo -e "${YELLOW}Adım 2: Kubespray Deposu Klonlanıyor...${NC}"
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# git checkout ile belirtilen vesiyon: v2.24.3
echo -e "${YELLOW}Kubespray versiyonu: $(git describe --tags)${NC}"

echo -e "${YELLOW}Adım 3: Python Virtual Environment Oluşturuluyor ve Bağımlılıklar yükleniyor...${NC}"
sudo apt update && sudo apt install -y python3.10-venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp -rfp inventory/sample inventory/mycluster
echo -e "${GREEN}Adım 3: Python Virtual Environment ve Bağımlılıklar yüklendi.${NC}"

# ansible.cfg dosyasına ansible-host bilgilerinin eklenmesi
echo -e "${YELLOW}Kubespray yapılandırma dosyaları ayarlanıyor...${NC}"
echo -e "${YELLOW}ansible.cfg dosyasına ansible-host ayarları ekleniyor...${NC}"

awk '
/^\[defaults\]/ {
    print;
    while ((getline line < "eklenecek_içerik.cfg") > 0)
        print line;
    close("eklenecek_içerik.cfg");
    next
}
{ print }
' ansible.cfg > tmpfile && mv tmpfile ansible.cfg

cp -r "${HOME}/automation_configs/hosts.yaml" "${HOME}/kubespray/inventory/mycluster/hosts.yaml"
echo -e "${GREEN}ansible.cfg dosyasına ansible-host ayarları eklendi${NC}"

# HAProxy IP'si sertifikaya eklenmesi
HAPROXY_PRIVATE_IP=$(grep 'haproxy:' ~/automation_configs/hosts.yaml -A 4 | grep 'ansible_host:' | awk '{print $2}')
echo -e "${YELLOW}HAProxy IP'si sertifikaya ekleniyor...${NC}"
cat <<EOF >> ~/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
supplementary_addresses_in_ssl_keys: [${HAPROXY_PRIVATE_IP}]
EOF
echo -e "${YELLOW}HAProxy IP'si sertifikaya eklendi.${NC}"

# SSH agent doğrulaması
echo -e "\n${YELLOW}SSH Agent başlatılıyor ve anahtar ekleniyor...${NC}"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/ansible-prod
echo -e "\n${GREEN}SSH Agent işlemleri tamamlandı.${NC}"

echo -e "${YELLOW}Adım 4: Kubernetes Cluster Kurulumu Başlatılıyor...${NC}"
sleep 3
echo -e "${GREEN}Kubernetes Cluster Kurulumu Başladı.${NC}"
sleep 1
ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml
echo -e "${GREEN}Kubernetes Cluster kurulumu başarılı bir şekilde tamamlandı.${NC}"

# kubectl binary'sini ansible-hosta kurma (eğer daha önce kurulu değilse)
echo -e "${YELLOW}Şimdi kubernetes cluster için diğer bileşenlerin kurulumuna geçiliyor...${NC}"
echo -e "\n${YELLOW}kubectl binary'si kontrol ediliyor ve gerekiyorsa kuruluyor...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}kubectl bulunamadı, indiriliyor ve kuruluyor...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    echo -e "${GREEN}kubectl başarıyla kuruldu.${NC}"
else
    echo -e "${GREEN}kubectl zaten yüklü.${NC}"
fi
echo -e "${GREEN}Ansible Host Üzerindeki Kubernetes Kurulum İşlemleri Tamamlandı.${NC}"

# master node'tan admin.conf dosyasını çekme işlemi
echo -e "${YELLOW}master-1 Node'undan admin.conf alınıyor ve kubeconfig dosyası yapılandırılıyor...${NC}"

# master-1'ın IP'sini hosts.yaml'dan çek
echo -e "${YELLOW}master-1 IP'si hosts.yaml'dan çekiliyor...${NC}"
MASTER1_IP=$(grep 'master-1:' ~/automation_configs/hosts.yaml -A 4 | grep 'ansible_host:' | awk '{print $2}')

if [ -z "$MASTER1_IP" ]; then
    echo -e "${RED}master-1 IP adresi bulunamadı. hosts.yaml dosyasını kontrol edin.${NC}"
    exit 1
fi

echo -e "${GREEN}master-1 IP'si hosts.yaml'dan çekildi.${NC}"

# admin.conf dosyasını master-1 node'dan kopyala
echo -e "${GREEN}admin.conf yapılandırması için master-1 Node'undan admin.conf alınıyor...${NC}"
if [ -z "$MASTER1_IP" ]; then
    echo -e "${RED}master-1 IP adresi bulunamadı. hosts.yaml dosyasını kontrol ediniz.${NC}"
    exit 1
fi

ssh -o StrictHostKeyChecking=no -i ~/.ssh/ansible-prod "produser@${MASTER1_IP}" "sudo cat /etc/kubernetes/admin.conf" > ~/admin.conf
echo -e "${GREEN}master-1 node'undan admin.conf dosyası alındı..${NC}"

# Eğer dosya başarıyla indirildiyse kopyalama işlemini yap
echo -e "${YELLOW}admin.conf dosyası ./kube/config olarak kaydediliyor ve ayarlamaları yapılıyor.${NC}"
if [ -s ~/admin.conf ]; then
    mkdir -p ~/.kube
    cp ~/admin.conf ~/.kube/config
    chown "$(id -u):$(id -g)" ~/.kube/config
    sed -i "s|https://127.0.0.1:6443|https://${MASTER1_IP}:6443|g" ~/.kube/config
    rm -f ~/admin.conf
    echo -e "${GREEN}Kubeconfig ayarları tamamlandı. kubernetes cluster'ı kontrol edebilirsiniz.${NC}"
else
    echo -e "${RED}Kubeconfig ayarları yapılamadı: Kullanıcı erişimi veya sudo yetkisini kontrol ediniz.${NC}"
    exit 1
fi

# node ve pod bilgileri son kez kontrol ediliyor
echo -e "${YELLOW}Kubernetes node'ları kontrol ediliyor:${NC}"
kubectl get no -owide
echo -e "${YELLOW}Kubernetes pod'ları kontrol ediliyor:${NC}"
kubectl get po -A -owide

# HAProxy sunucu yapılandırması
echo -e "${YELLOW}HAProxy Sunucusuna geçiş yapılıyor... :${NC}"

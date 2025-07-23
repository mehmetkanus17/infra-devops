resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "kubernetes-${terraform.workspace}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "kubernetes-${terraform.workspace}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  for_each            = toset(["ansible", "haproxy"])
  name                = "pip-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  zones               = ["1", "2", "3"]
}

resource "azurerm_network_security_group" "nsg_ansible_haproxy" {
  name                = "nsg-ansible-haproxy"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-K8s-API"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg_k8s_nodes" {
  name                = "kubernetes-${terraform.workspace}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH-from-ansible-haproxy"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_network_interface.nic["ansible"].private_ip_address
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-K8s-API-from-HAProxy"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = azurerm_network_interface.nic["haproxy"].private_ip_address
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg_nfs" {
  name                = "nsg-nfs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                         = "Allow-NFS-from-K8s-Subnet"
    priority                     = 1001
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "2049"
    # Adres alanına setten erişim için one() fonksiyonunu kullanıyoruz
    source_address_prefix        = one(azurerm_virtual_network.vnet.address_space)
    destination_address_prefix   = "*"
  }
}

resource "azurerm_network_interface" "nic" {
  for_each            = toset(var.vm_names)
  name                = "nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = contains(["ansible", "haproxy"], each.key) ? azurerm_public_ip.public_ip[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each = toset(var.vm_names)

  network_interface_id = azurerm_network_interface.nic[each.key].id

  network_security_group_id = (
    each.key == "nfs" ? azurerm_network_security_group.nsg_nfs.id :
    contains(["ansible", "haproxy"], each.key) ? azurerm_network_security_group.nsg_ansible_haproxy.id :
    azurerm_network_security_group.nsg_k8s_nodes.id
  )
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each            = toset(var.vm_names)
  name                = each.key
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.nic[each.key].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    name                 = "disk-${each.key}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Tüm VM'ler için custom_data ayarı
  custom_data = base64encode(
    each.key == "nfs" ? <<-EOT
      #!/bin/bash
      apt update
      apt install -y nfs-kernel-server nfs-common # nfs-common eklendi
      mkdir -p /srv/nfs/kubedata
      chown nobody:nogroup /srv/nfs/kubedata
      chmod 777 /srv/nfs/kubedata # Bu satırı eklemiştik, tutarlılık için tekrar ekliyorum
      echo "/srv/nfs/kubedata *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
      systemctl restart nfs-server
      exportfs -a
    EOT
    : # Diğer tüm VM'ler (ansible, haproxy, master-*, worker-*)
    <<-EOT
      #!/bin/bash
      apt update
      apt install -y nfs-common
    EOT
  )
}

output "ansible_public_ip" {
  value = azurerm_public_ip.public_ip["ansible"].ip_address
}

output "haproxy_public_ip" {
  value = azurerm_public_ip.public_ip["haproxy"].ip_address
}

output "nfs_private_ip" {
  value = azurerm_network_interface.nic["nfs"].private_ip_address
  description = "NFS sunucusunun özel IP adresi"
}

output "vm_private_ips" {
  value = {
    for name, nic in azurerm_network_interface.nic :
    name => nic.private_ip_address
  }
}

output "admin_username" {
  value       = var.admin_username
  description = "VM admin kullanıcısı"
}

output "master_private_ips" {
  value = [
    for name, nic in azurerm_network_interface.nic :
    nic.private_ip_address if startswith(name, "master-")
  ]
}

output "worker_private_ips" {
  value = [
    for name, nic in azurerm_network_interface.nic :
    nic.private_ip_address if startswith(name, "worker-")
  ]
}

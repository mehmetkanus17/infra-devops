variable "admin_username" {}
variable "vm_size" {}
variable "ssh_public_key_path" {}
variable "ssh_private_key_path" {}


variable "vm_names" {
  type        = list(string)
  default     = ["ansible", "haproxy", "nfs", "master-1", "master-2", "master-3", "worker-1", "worker-2", "worker-3"]
}

variable "rg_name" {
  default = "rg-ha-kubernetes"
}

variable "location" {
  default = "East US"
}
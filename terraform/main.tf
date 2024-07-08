# Define required providers
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}

variable "environment" {
  description = "Deployment environment (local or cloud)"
  type        = string
  default     = "local"
  validation {
    condition = contains(["local", "cloud"], var.environment)
    error_message = "Invalid environment. Allowed values: local or cloud."
  }
}

# Local variables
locals {
  hostname = chomp(file("/proc/sys/kernel/hostname"))
}

# Data source for existing SSH key
data "digitalocean_ssh_key" "existing" {
  count = var.environment == "cloud" ? 1 : 0
  name  = local.hostname
}

# Resource for local K3s installation
resource "null_resource" "install_local_k3s" {
  count = var.environment == "local" ? 1 : 0

  provisioner "local-exec" {
    command = "curl -sfL https://get.k3s.io | sh -"

    on_failure = fail
  }
}

# Resource for DigitalOcean Droplet
resource "digitalocean_droplet" "k3s_node" {
  count  = var.environment == "cloud" ? 1 : 0
  image  = "ubuntu-20-04-x64"
  name   = "k3s-cluster"
  region = "nyc3"
  size   = "s-1vcpu-1gb"
  ssh_keys = [data.digitalocean_ssh_key.existing[0].id]

  tags = ["k3s", "cluster"]
}

# Null resource for K3s installation
resource "null_resource" "install_k3s" {
  count      = var.environment == "cloud" ? 1 : 0
  depends_on = [digitalocean_droplet.k3s_node]

  # Connection details for SSH
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")  # Consider using a variable for the SSH key path
    host        = digitalocean_droplet.k3s_node[0].ipv4_address
  }

  # Copy K3s installation script
  provisioner "file" {
    source      = "${path.module}/../scripts/install-setup.sh"
    destination = "/root/install-setup.sh"
  }

  # Execute K3s installation script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/install-setup.sh",
      "/root/install-setup.sh",
    ]
  }
}

# Output for cluster endpoint
output "cluster_endpoint" {
  value = var.environment == "local" ? "https://127.0.0.1:6443" : digitalocean_droplet.k3s_node[0].ipv4_address
  description = "The endpoint to connect to the K3s cluster"
}

# Output for kubeconfig
output "kubeconfig" {
  value = var.environment == "local" ? "/etc/rancher/k3s/k3s.yaml" : "Run 'ssh root@${digitalocean_droplet.k3s_node[0].ipv4_address} cat /etc/rancher/k3s/k3s.yaml' to get the kubeconfig"
  description = "Path or instructions to obtain the kubeconfig for the K3s cluster"
}
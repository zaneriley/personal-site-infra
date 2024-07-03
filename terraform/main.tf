terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

locals {
  hostname = chomp(file("/proc/sys/kernel/hostname"))
}

data "digitalocean_ssh_key" "existing" {
  name = "${local.hostname}"
}

# Commented out existing Droplet
# data "digitalocean_droplet" "existing" {
#   name = "remote-homelab"
# }

# New Droplet for k3s
resource "digitalocean_droplet" "k3s_node" {
  image  = "ubuntu-20-04-x64"
  name   = "k3s-cluster"
  region = "nyc3"
  size   = "s-1vcpu-1gb"  
  ssh_keys = [data.digitalocean_ssh_key.existing.id]
}

output "droplet_ip" {
  value = digitalocean_droplet.k3s_node.ipv4_address
}

resource "null_resource" "install_k3s" {
  depends_on = [digitalocean_droplet.k3s_node]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")  # Adjust this path as needed
    host        = digitalocean_droplet.k3s_node.ipv4_address
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/install_k3s.sh"
    destination = "/root/install_k3s.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /root/install_k3s.sh",
      "/root/install_k3s.sh",
    ]
  }
}

output "kubeconfig" {
  value = "Run 'ssh root@${digitalocean_droplet.k3s_node.ipv4_address} cat /etc/rancher/k3s/k3s.yaml' to get the kubeconfig"
}
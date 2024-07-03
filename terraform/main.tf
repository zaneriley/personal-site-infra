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

# Existing Droplet
data "digitalocean_droplet" "existing" {
  name = "remote-homelab"
}

output "droplet_ip" {
  value = data.digitalocean_droplet.existing.ipv4_address
}

data "digitalocean_droplets" "all" {}

output "all_droplets" {
  value = {
    for droplet in data.digitalocean_droplets.all.droplets :
    droplet.name => {
      ip   = droplet.ipv4_address
      tags = droplet.tags
    }
  }
}

resource "null_resource" "install_k3s" {
  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")  # Adjust this path as needed
    host        = data.digitalocean_droplet.existing.ipv4_address
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
  value = null_resource.install_k3s.id != "" ? "Run 'ssh root@${data.digitalocean_droplet.existing.ipv4_address} cat /etc/rancher/k3s/k3s.yaml' to get the kubeconfig" : ""
}
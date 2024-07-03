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

# New Droplet
# resource digitalocean_droplet k3s_server {
#   image    = "ubuntu-20-04-x64"
#   name     = "k3s-server"
#   region   = "nyc3"
#   size     = "s-2vcpu-2gb"
# }

# Existing Droplet
data digitalocean_droplet existing {
  name = "remote-homelab"
}

output droplet_ip {
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
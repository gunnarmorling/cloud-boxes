terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.10"
    }
  }
}

variable "hcloud_token" {}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = "${var.hcloud_token}"
}

resource "hcloud_server" "control" {
  name        = "control"
  image       = "fedora-37"
  datacenter  = "nbg1-dc3"
  server_type = "cx11"
  keep_disk   = true
  ssh_keys    = ["key1"]
}

output "control_public_ip4" {
  value = "${hcloud_server.control.ipv4_address}"
}

terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.10"
    }
  }
}

variable "hcloud_token" {}

variable "firewall_source_ip" {
  default = "0.0.0.0"
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = "${var.hcloud_token}"
}

resource "hcloud_firewall" "common-firewall" {
  name = "common-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "${var.firewall_source_ip}/32"
    ]
  }

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "${var.firewall_source_ip}/32"
    ]
  }
}

resource "hcloud_server" "control" {
  name        = "control"
  image       = "fedora-37"
  location    = "fsn1"
  server_type = "cx11"
  keep_disk   = true
  ssh_keys    = ["key1"]
  firewall_ids = [hcloud_firewall.common-firewall.id]
}

output "control_public_ip4" {
  value = "${hcloud_server.control.ipv4_address}"
}

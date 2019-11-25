variable "hcloud_token" {}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = "${var.hcloud_token}"
  version = "~> 1.10"
}

resource "hcloud_server" "control" {
  name        = "control"
  image       = "fedora-31"
  datacenter  = "nbg1-dc3"
  server_type = "cx11"
  keep_disk   = true
  ssh_keys    = ["key1"]
}

output "control_public_ip4" {
  value = "${hcloud_server.control.ipv4_address}"
}

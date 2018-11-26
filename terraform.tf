variable "hcloud_token" {}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = "${var.hcloud_token}"
}

resource "hcloud_server" "control" {
  name        = "control"
  image       = "fedora-28"
  datacenter  = "nbg1-dc3"
  server_type = "cx11"
  keep_disk   = true
  ssh_keys    = ["key1"]
}

resource "hcloud_server" "devoxx-ma" {
  name        = "devoxx-ma"
  image       = "fedora-28"
  datacenter  = "nbg1-dc3"
  server_type = "cx11"
  keep_disk   = true
  ssh_keys    = ["key1"]
}

output "control_public_ip4" {
  value = "${hcloud_server.control.ipv4_address}"
}

output "devoxx-ma_public_ip4" {
  value = "${hcloud_server.devoxx-ma.ipv4_address}"
}

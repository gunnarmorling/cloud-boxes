terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

variable "hcloud_token" {
  sensitive = true
}

variable "firewall_source_ip" {
  default = "0.0.0.0"
}

# Custom SSH port. The real value is kept out of version control; set it in the
# gitignored local.auto.tfvars (see local.auto.tfvars.example).
variable "ssh_port" {
  default = "22"
}

# Name of the SSH key registered in your Hetzner project. Kept out of version
# control; set it in the gitignored local.auto.tfvars.
variable "ssh_key_name" {
  default = "my-hetzner-key"
}

# Local path to the private key matching ssh_key_name, used for IdentityFile in the
# generated SSH config. Kept out of version control; set it in local.auto.tfvars.
variable "ssh_private_key_path" {
  default = "~/.ssh/id_ed25519"
}

# Servers to create, keyed by hostname. The Ansible inventory (hosts) is generated
# from this. To spin up more boxes, add entries here or, better, in the gitignored
# local.auto.tfvars so your personal layout stays out of the repo.
variable "servers" {
  type = map(object({
    server_type = string
    image       = optional(string, "fedora-44")
    location    = optional(string, "nbg1")
  }))
  default = {
    control = { server_type = "cx22" }
  }
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = "${var.hcloud_token}"
}

# Public key of the registered Hetzner SSH key, injected into cloud-init so the
# box is reachable as the build user on first boot.
data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
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
    protocol  = "tcp"
    port      = var.ssh_port
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

resource "hcloud_server" "node" {
  for_each = var.servers

  name         = each.key
  image        = each.value.image
  location     = each.value.location
  server_type  = each.value.server_type
  keep_disk    = true
  ssh_keys     = [var.ssh_key_name]
  firewall_ids = [hcloud_firewall.common-firewall.id]

  # cloud-init creates the build user and configures sshd on the custom port.
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    ssh_port      = var.ssh_port
    build_ssh_key = data.hcloud_ssh_key.default.public_key
  })
}

# Generate the Ansible inventory from the created servers; rewritten on every apply.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/hosts"
  file_permission = "0644"
  content = templatefile("${path.module}/hosts.tftpl", {
    servers = { for name, s in hcloud_server.node : name => s.ipv4_address }
  })
}

# Generate an SSH config so `ssh -F ansible/ssh_config <name>` reaches a box without
# specifying port/user/key/IP. Rewritten on every apply.
resource "local_file" "ssh_config" {
  filename        = "${path.module}/../ansible/ssh_config"
  file_permission = "0600"
  content = templatefile("${path.module}/ssh_config.tftpl", {
    servers       = { for name, s in hcloud_server.node : name => s.ipv4_address }
    ssh_port      = var.ssh_port
    identity_file = var.ssh_private_key_path
  })
}

output "server_ips" {
  value = { for name, s in hcloud_server.node : name => s.ipv4_address }
}

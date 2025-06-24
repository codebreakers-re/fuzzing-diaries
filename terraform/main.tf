terraform {

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}


variable "hcloud_token" {
  sensitive = true
}

variable "server_type" {
  sensitive = false
  default   = "cpx11"
}

provider "hcloud" {
  token = var.hcloud_token
}

data "hcloud_datacenter" "nuremberg" {
  name = "nbg1-dc3"
}


data "hcloud_ssh_key" "github" {
  name = "GITHUB ACTIONS"
}

resource "tls_private_key" "exec_provider" {
  algorithm = "ED25519"
}

resource "hcloud_primary_ip" "fuzzer" {
  name          = "fuzzer_ip"
  datacenter    = data.hcloud_datacenter.nuremberg.name
  type          = "ipv4"
  assignee_type = "server"
  auto_delete   = true
}

resource "hcloud_volume" "fuzzer01" {
  name     = "fuzzer"
  location = "nbg1"
  size     = 50
}

resource "hcloud_firewall" "fuzzer" {
  name = "fuzzer-firewall"

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_server" "fuzzer" {
  name        = "fuzzer"
  image       = "ubuntu-22.04"
  server_type = var.server_type
  datacenter  = data.hcloud_datacenter.nuremberg.name

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.fuzzer.id
    ipv6_enabled = false
  }

  ssh_keys = [
    data.hcloud_ssh_key.github.id,
  ]


  firewall_ids = [
    hcloud_firewall.fuzzer.id
  ]

  user_data = <<-EOT
  #cloud-config
  runcmd:
    - curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-25.05 bash 2>&1 | tee /tmp/infect.log
  EOT
}

resource "hcloud_volume_attachment" "fuzzer" {
  volume_id = hcloud_volume.fuzzer01.id
  server_id = hcloud_server.fuzzer.id
  automount = true
}

output "fuzzer_ip" {
  value = hcloud_primary_ip.fuzzer.ip_address
}

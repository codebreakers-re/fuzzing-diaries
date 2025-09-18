terraform {

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
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


resource "hcloud_ssh_key" "terraform" {
  name       = "terraform-fuzzer-${terraform.workspace}"
  public_key = file("~/.ssh/id_ed25519_terraform.pub")
}



resource "hcloud_primary_ip" "fuzzer" {
  name          = "fuzzer_ip_${terraform.workspace}"
  datacenter    = data.hcloud_datacenter.nuremberg.name
  type          = "ipv4"
  assignee_type = "server"
  auto_delete   = true
}

resource "hcloud_volume" "fuzzer01" {
  name     = "fuzzer_${terraform.workspace}"
  location = "nbg1"
  size     = 50
}

resource "hcloud_firewall" "fuzzer" {
  name = "fuzzer-firewall-${terraform.workspace}"

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
  name        = "fuzzer-${terraform.workspace}"
  image       = "ubuntu-22.04"
  server_type = var.server_type
  datacenter  = data.hcloud_datacenter.nuremberg.name

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.fuzzer.id
    ipv6_enabled = false
  }

  ssh_keys = [
    hcloud_ssh_key.terraform.id,
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

resource "time_sleep" "wait_for_nixos_infect" {
  depends_on = [
    hcloud_server.fuzzer,
    hcloud_volume_attachment.fuzzer
  ]

  create_duration = "5m"
}

resource "time_sleep" "retry_delay" {
  create_duration = "2m"
}

resource "null_resource" "upload_binary" {
  depends_on = [
    time_sleep.wait_for_nixos_infect
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Compressing ${terraform.workspace} directory..."
      cd .. && tar -czf ${terraform.workspace}.tar.gz --exclude='${terraform.workspace}/.devenv' ${terraform.workspace}/ && cd terraform
      echo "Uploading compressed ${terraform.workspace}.tar.gz..."
      scp -i ~/.ssh/id_ed25519_terraform -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ../${terraform.workspace}.tar.gz \
        root@${hcloud_primary_ip.fuzzer.ip_address}:/root/ || \
      (echo "First attempt failed, waiting 2 more minutes..." && sleep 120 && \
       scp -i ~/.ssh/id_ed25519_terraform -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         ../${terraform.workspace}.tar.gz \
         root@${hcloud_primary_ip.fuzzer.ip_address}:/root/)
      echo "Extracting on remote server..."
      ssh -i ~/.ssh/id_ed25519_terraform -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@${hcloud_primary_ip.fuzzer.ip_address} "cd /root && tar -xzf ${terraform.workspace}.tar.gz && rm ${terraform.workspace}.tar.gz"
      echo "Uploading NixOS configuration..."
      scp -i ~/.ssh/id_ed25519_terraform -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ../nix/configuration.nix \
        root@${hcloud_primary_ip.fuzzer.ip_address}:/etc/nixos/configuration.nix
    EOT
  }
}

output "fuzzer_ip" {
  value = hcloud_primary_ip.fuzzer.ip_address
}

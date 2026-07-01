terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

provider "openstack" {}

locals {
  groups = toset([for k, v in var.vms : v.group])
}

resource "openstack_networking_network_v2" "group_net" {
  for_each       = local.groups
  name           = "hackathon-${each.key}"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "group_subnet" {
  for_each        = local.groups
  name            = "hackathon-${each.key}-subnet"
  network_id      = openstack_networking_network_v2.group_net[each.key].id
  cidr            = "10.10.0.0/24"
  ip_version      = 4
  dns_nameservers = ["1.1.1.1", "8.8.8.8"]
}

resource "openstack_networking_router_v2" "group_router" {
  for_each            = local.groups
  name                = "hackathon-${each.key}-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
}

resource "openstack_networking_router_interface_v2" "group_router_iface" {
  for_each  = local.groups
  router_id = openstack_networking_router_v2.group_router[each.key].id
  subnet_id = openstack_networking_subnet_v2.group_subnet[each.key].id
}

resource "openstack_networking_secgroup_v2" "group_sg" {
  for_each    = local.groups
  name        = "hackathon-${each.key}-sg"
  description = "Security group hackathon groupe ${each.key}"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  for_each          = local.groups
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.group_sg[each.key].id
}

resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  for_each          = local.groups
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.group_sg[each.key].id
}

resource "openstack_compute_keypair_v2" "vm_key" {
  for_each   = var.vms
  name       = "hackathon-key-${each.key}"
  public_key = each.value.ssh_public_key
}

# Port reseau explicite : cree avant la VM et la floating IP,
# ce qui garantit que l'association floating IP -> port -> VM est complete.
resource "openstack_networking_port_v2" "vm_port" {
  for_each           = var.vms
  name               = "hackathon-port-${each.key}"
  network_id         = openstack_networking_network_v2.group_net[each.value.group].id
  security_group_ids = [openstack_networking_secgroup_v2.group_sg[each.value.group].id]
  admin_state_up     = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.group_subnet[each.value.group].id
  }
}

resource "openstack_compute_instance_v2" "vm" {
  for_each    = var.vms
  name        = "vm-${each.key}"
  image_id    = var.image_id
  flavor_name = var.flavor_name
  key_pair    = openstack_compute_keypair_v2.vm_key[each.key].name

  network {
    port = openstack_networking_port_v2.vm_port[each.key].id
  }

  metadata = {
    "hackathon.end_date" = each.value.end_date
    "hackathon.group"    = each.value.group
    "hackathon.owner"    = each.value.owner
    "hackathon.template" = each.value.template
  }

  user_data = <<-CLOUD_INIT
    #cloud-config
    users:
      - name: student
        ssh_authorized_keys:
          - ${each.value.ssh_public_key}
        shell: /bin/bash
    write_files:
      - path: /etc/ssh/sshd_config.d/99-hardening.conf
        content: |
          PermitRootLogin no
          PasswordAuthentication no
    runcmd:
      - systemctl restart ssh
    CLOUD_INIT
}

# Floating IP associee au port explicite -> association garantie
resource "openstack_networking_floatingip_v2" "vm_fip" {
  for_each = var.vms
  pool     = var.floating_ip_pool
  port_id  = openstack_networking_port_v2.vm_port[each.key].id
}

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

# ---------------------------------------------------------------------------
# Etat desire : la map var.vms (alimentee par scripts/provision.sh et
# scripts/destroy_expired.sh) represente l'ensemble des VMs qui DOIVENT
# exister maintenant. Tofu se charge de creer ce qui manque et de detruire
# ce qui a ete retire de la map -> reconciliation declarative, pas de
# commande "destroy" manuelle a piloter en plus.
# ---------------------------------------------------------------------------

locals {
  groups = toset([for k, v in var.vms : v.group])
}

# Un reseau Docker dedie par groupe = isolation reseau entre groupes.
# Deux conteneurs sur deux reseaux differents ne peuvent pas se joindre
# par defaut avec le driver bridge de Docker.
resource "docker_network" "group_net" {
  for_each = local.groups
  name     = "hackathon-${each.key}"
}

resource "docker_image" "vm_base" {
  name         = var.image_tag
  keep_locally = true
}

resource "docker_container" "vm" {
  for_each = var.vms

  name  = "vm-${each.key}"
  image = docker_image.vm_base.image_id

  networks_advanced {
    name = docker_network.group_net[each.value.group].name
  }

  env = [
    "SSH_PUBLIC_KEY=${each.value.ssh_public_key}",
  ]

  labels {
    label = "hackathon.end_date"
    value = each.value.end_date
  }
  labels {
    label = "hackathon.group"
    value = each.value.group
  }
  labels {
    label = "hackathon.owner"
    value = each.value.owner
  }
  labels {
    label = "hackathon.template"
    value = each.value.template
  }

  ports {
    internal = 22
    external = each.value.ssh_port
  }

  must_run = true
  restart  = "unless-stopped"
}

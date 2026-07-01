variable "vms" {
  description = "Map des VMs actives, alimentee par les scripts."
  type = map(object({
    owner          = string
    group          = string
    template       = string
    end_date       = string # format YYYY-MM-DD
    ssh_public_key = string
  }))
  default = {}
}

variable "image_id" {
  description = "ID de l'image Ubuntu 22.04 sur Infomaniak"
  type        = string
  default     = "bdee52cf-0fd7-4323-813f-9a40a509d2dc" # Ubuntu 22.04 LTS Jammy Jellyfish
}

variable "flavor_name" {
  description = "Flavor OpenStack (taille de la VM)"
  type        = string
  default     = "a1-ram2-disk50-perf1" # 1 vCPU, 2 GB RAM, 50 GB disk
}

variable "external_network_id" {
  description = "ID du reseau externe Infomaniak pour les floating IPs"
  type        = string
  default     = "0f9c3806-bd21-490f-918d-4a6d1c648489" # ext-floating1
}

variable "floating_ip_pool" {
  description = "Nom du pool de floating IPs"
  type        = string
  default     = "ext-floating1"
}

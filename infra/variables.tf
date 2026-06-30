variable "vms" {
  description = "Map des VMs actives, alimentee automatiquement par les scripts. Cle = id de la demande."
  type = map(object({
    owner          = string
    group          = string
    template       = string
    end_date       = string # format YYYY-MM-DD
    ssh_public_key = string
    ssh_port       = number
  }))
  default = {}
}

variable "image_tag" {
  description = "Tag de l'image Docker utilisee comme base pour chaque VM"
  type        = string
  default     = "hackathon-vm-base:latest"
}

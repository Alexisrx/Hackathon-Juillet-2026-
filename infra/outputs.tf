output "vms" {
  description = "Etat de toutes les VMs actives, pretes a etre consommees par le dashboard"
  value = {
    for k, c in docker_container.vm : k => {
      name     = c.name
      owner    = var.vms[k].owner
      group    = var.vms[k].group
      template = var.vms[k].template
      end_date = var.vms[k].end_date
      ssh_port = var.vms[k].ssh_port
    }
  }
}

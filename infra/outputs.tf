output "vms" {
  description = "Etat de toutes les VMs actives avec leurs floating IPs"
  value = {
    for k, c in openstack_compute_instance_v2.vm : k => {
      name        = c.name
      owner       = var.vms[k].owner
      group       = var.vms[k].group
      template    = var.vms[k].template
      end_date    = var.vms[k].end_date
      floating_ip = openstack_networking_floatingip_v2.vm_fip[k].address
    }
  }
}

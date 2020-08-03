resource "vsphere_virtual_machine" "vm" {
  for_each = var.hostnames_ip_addresses

  name = format("%s.%s", element(split(".", each.key), 0), var.cluster_domain)

  resource_pool_id = var.resource_pool_id
  datastore_id     = var.datastore_id
  num_cpus         = var.num_cpus
  #cpu_limit        = format("%d", var.num_cpus * 2400)
  #cpu_reservation  = format("%d", var.num_cpus * 2400)
  memory           = var.memory
  memory_limit     = var.memory
  memory_reservation = var.memory
  guest_id         = var.guest_id
  folder           = var.folder_id
  enable_disk_uuid = "true"
  #latency_sensitivity = "high"

  wait_for_guest_net_timeout  = "0"
  wait_for_guest_net_routable = "false"

  network_interface {
    network_id = var.network_id
  }

  disk {
    label            = "disk0"
    size             = 120
    thin_provisioned = var.disk_thin_provisioned
  }

  clone {
    template_uuid = var.template_uuid
  }

  extra_config = {
    "guestinfo.ignition.config.data"          = base64encode(data.ignition_config.ign[each.key].rendered)
    "guestinfo.ignition.config.data.encoding" = "base64"
  }

  lifecycle {
    ignore_changes = [
      num_cpus,
      memory,
      memory_limit,
      memory_reservation,
      disk
    ]
  }
}


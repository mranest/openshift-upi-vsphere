# Openshift 4.x UPI on vSphere using Terraform

An adapted version of the UPI vSphere terraform scripts found in 
[OpenShift installer GitHub repository / UPI / vSphere](https://github.com/openshift/installer/tree/master/upi/vsphere).

## When to use

Ideally you would want to take a look into this version of the scripts if:

- You are running vSphere on-prem
- You want static IP provisioning
- You only want the bare minimal VMs (i.e. control plane, compute and optionally infra nodes)

## Pre-Requisites

* DHCP server
* terraform

## DHCP

A DHCP server is required, despite setting up static IPs. This is due to some design decision for 
RHCOS that leads to the static IP configuration not being applied early enough in the boot phase. 
My guess is that during boot the machine configuration provided by the machine config operator is 
combined with the rest of configuration that is generated by the vm/ignition terraform module in 
order to come up with the complete template.

There is no need to configure the static IPs in the DHCP server configuration files, too; a generic
 pool will suffice, along with a short lease time. See for example this sample configuration file:

```
#/etc/dhcp/dhcpd.conf
# DHCP Server Configuration file.
#   see /usr/share/doc/dhcp*/dhcpd.conf.example
#   see dhcpd.conf(5) man page
#
option domain-name "cluster.example.com";
default-lease-time 60;
max-lease-time 120;
authoritative;

subnet 192.168.1.0 netmask 255.255.255.0 {
        option routers 192.168.1.1;
        option subnet-mask 255.255.255.0;
        option domain-search "base.domain";
        option domain-name-servers 192.168.0.1;
        range 192.168.1.64 192.168.1.128;
}
```

## Build a Cluster

### Create an `install-config.yaml`

Here is a sample configuration file:

```yaml
apiVersion: v1
baseDomain: example.com
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 2
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: cluster
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
    networkType: OpenShiftSDN
    serviceNetwork:
    - 172.26.0.0/16
platform:
  vsphere:
  vcenter: vcenter.example.com
  username: username
  password: password
  datacenter: datacenter
  defaultDatastore: datastore
pullSecret: YOUR_PULL_SECRET
sshKey: YOUR_SSH_KEY
```

Don't pay attention to number of control plane and compute workers; these are actually
controlled by the terraform script. Also be sure to escape characters in vSphere settings 
as required (e.g. any `/` character must be escaped as `%2f`). These settings are used for the 
configuration of the vsphere in-tree storage driver.

See also the relevant documentation for [Manually creating the installation configuration file](https://docs.openshift.com/container-platform/4.5/installing/installing_vsphere/installing-vsphere.html#installation-initializing-manual_installing-vsphere) 
in OpenShift Documentation site for additional information on pull secrets, proxy settings
and other supported customizations.

### Run `openshift-install create ignition-configs`

The three ignition files, `bootstrap.ign`, `master.ign` and `worker.ign`, will be created.

Don't do any of the steps described in the 
[Creating Red Hat Enterprise Linux CoreOS (RHCOS) machines in vSphere](https://docs.openshift.com/container-platform/4.5/installing/installing_vsphere/installing-vsphere.html#installation-vsphere-machines_installing-vsphere)
documentation section, as terraform will be used to create all the VMs required.

### Create a `terraform.tfvars` configuraton file

There is an example `terraform.tfvars` file in this directory named `terraform.tfvars.example`. All
variables not preceded with `#` need their value properly set (some sample values are provided), 
whereas commented out variables have the default value shown.

The ignition files created in the previous step should be copied in this folder, otherwise you
must set the location for them using the corresponding variables `bootstrap_ignition_path`, 
`control_plane_ignition_path` and `compute_ignition_path`.

If you want to create infra nodes then you must provided their IP addresses in variable 
`infra_ip_addresses`. After cluster installation finishes you must follow 
[this guide](https://www.redhat.com/en/blog/openshift-container-platform-4-how-does-machine-config-pool-work) 
to properly configure infra nodes.

If you want to provide more OS configuration files through ignition you must make the necessary 
changes in file `vm/ignition.tf`. If one for example wanted to add static routes to the resulting
RHCOS VM then the following changes would create file `/etc/sysconfig/network-scripts/route-ens192` 
after the OS boots (add a `route.tmpl` file with the appropriate static routes next to the 
`ignition.tf` script):

```
data "ignition_file" "static_routes" {
  for_each = var.hostnames_ip_addresses

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/route-ens192"
  mode       = "420"

  content {
    content = file("${path.module}/route.tmpl")
  }
}

data "ignition_config" "ign" {
  ...

  files = [
    ...
    data.ignition_file.static_routes[each.key].rendered,
  ]
}
```

### Run `terraform init`

This will intitialize this working directory with all the necessary plugins.

### Run `terraform apply`

Type `yes` if everything looks ok for the VMs to be created.

### Run `openshift-install wait-for bootstrap-complete`

Wait for the bootstrapping to complete.

### Run `openshift-install wait-for install-complete`

Wait for the cluster install to finish. Enjoy your new OpenShift cluster.
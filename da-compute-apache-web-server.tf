
##################################################################################
# VARIABLES
##################################################################################

variable "vsphere_user" {
  description = "vSphere administrator username"
  type        = string
  sensitive   = true
}

variable "vsphere_password" {
  description = "vSphere administrator password"
  type        = string
  sensitive   = true
}
variable "vsphere_server" {
  description = "vSphere IP Address or FQDN"
  type        = string
  sensitive   = true
}
variable "ssh-pub-key" {
  description = "Service Account SSH pub key"
  type        = string
  sensitive   = true
}

variable "service_account_username" {
  description = "Service account username"
  type        = string
  sensitive   = true
}

variable "service_account_password" {
  description = "Service account password"
  type        = string
  sensitive   = true
}

##################################################################################
# PROVIDERS
##################################################################################

provider "vsphere" {
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

##################################################################################
# DATA
##################################################################################

data "vsphere_datacenter" "dc" {
  name = "BIT-DC01"
  #name = "DEVNET-DMZ"
}

data "vsphere_datastore" "datastore" {
  name          = "esx01-datastore1"
  #name          = "hx-demo-ds1"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_compute_cluster" "cluster" {
  name          = "General"
  #name          = "hx-demo"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "BIT-DVS01-VLAN52"
  #name          = "Management"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "CentOS-7-Template"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

resource "vsphere_virtual_machine" "vm1" {
  count            = 5
  name             = "apache-web-server-${count.index + 1}"
  resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"
  firmware         = "${var.vsphere_vm_firmware}"

  num_cpus = 2
  memory   = 4096
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "disk0"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    #eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    # eagerly_scrub    = true
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "apache-webserver-${count.index + 1}"
        domain    = "bitpass.com"
      }

      network_interface {
        ipv4_address = "192.168.52.${101 + count.index}"
        ipv4_netmask = 24
      }

      ipv4_gateway = "192.168.52.254"

    }
  }
  provisioner "file" {
    source      = "apache-web-servers.txt"
    destination = "/tmp/apache-web-servers.txt"
  }
  
  provisioner "file" {
    source      = "main.yml"
    destination = "/tmp/main.yml"
  }
  
  provisioner "file" {
    source      = "/roles"
    destination = "/tmp"
    
    connection {
    type     = "ssh"
    user     = "${var.service_account_username}"
    password = "${var.service_account_password}"
    host     = "192.168.52.${101 + count.index}"
    }
  }
  
  provisioner "remote-exec"  {
    inline = [
    "mkdir /home/.ssh",
    "chmod 700 /home/.ssh",
    "touch /home/.ssh/authorized_keys",
    "chmod 600 /home/.ssh/authorized_keys",
    "echo ${var.ssh-pub-key} >> /home/.ssh/authorized_keys",
    #"ansible-playbook -u root -i /tmp/apache-web-servers.txt /tmp/main.yml"
    ]

    connection {
    type     = "ssh"
    user     = "${var.service_account_username}"
    password = "${var.service_account_password}"
    host     = "192.168.52.${101 + count.index}"
    }
  }
  
} # "vsphere_virtual_machine" "vm1"

resource "null_resource" "ansible-playbook" {
  # Call Ansible from our local host where Terraform runs but only after the machines are created
  provisioner "local-exec" {
   command = "ansible-playbook -u root -i apache-web-servers.txt main.yml "
   }

   depends_on = [vsphere_virtual_machine.vm1] # Let's not kick off this resource until the VMs are created
}

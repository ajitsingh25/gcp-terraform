// Configure the Google Cloud provider
provider "google" {
 credentials = "${file("${var.credentials}")}"
 project     = "${var.gcp_project}"
 region      = "${var.region}"
}
// Create VPC
resource "google_compute_network" "vpc" {
 name                    = "${var.name}-vpc"
 auto_create_subnetworks = "false"
}

// Create Public Subnet
resource "google_compute_subnetwork" "public-subnet" {
 name          = "${var.name}-public-subnet"
 ip_cidr_range = "${var.public_subnet_cidr}"
 network       = "${google_compute_network.vpc.self_link}"
 region      = "${var.region}"
}

//Create Private Subnet
resource "google_compute_subnetwork" "private-subnet" {
 name          = "${var.name}-private-subnet"
 ip_cidr_range = "${var.private_subnet_cidr}"
 network       = "${google_compute_network.vpc.self_link}"
 region      = "${var.region}"
}

resource "google_compute_router" "router" {
  name    = "my-router"
  region  = "${google_compute_subnetwork.public-subnet.region}"
  network = "${google_compute_network.vpc.self_link}"

  bgp {
    asn = 64514
  }
}

// Create Router
resource "google_compute_router_nat" "nat" {
  name                               = "my-router-nat"
  router                             = "${google_compute_router.router.name}"
  region                             = "${google_compute_router.router.region}"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

// VPC firewall configuration
resource "google_compute_firewall" "allow-internal" {
 name          = "${var.name}-internal-firewall"
 network = "${google_compute_network.vpc.name}"
 
 allow {
   protocol = "icmp" 
 }

 allow {
   protocol = "tcp"
   ports    = ["0-65535"]
 }

 allow {
   protocol = "udp"
   ports    = ["0-65535"]
 }

 source_ranges = [
   "${var.public_subnet_cidr}",
   "${var.private_subnet_cidr}"
 ]
}


resource "google_compute_firewall" "allow-http" {
  name    = "${var.name}-allow-http"
  network = "${google_compute_network.vpc.name}"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  target_tags = ["http"]  
}

resource "google_compute_firewall" "allow-ssh" {
  name    = "${var.name}-allow-ssh"
  network = "${google_compute_network.vpc.name}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["ssh"]
}

resource "google_compute_instance" "vm_instance" {
  name          = "terraform-instance"
  machine_type  = "n1-standard-1"
  zone          = "${var.region}-a"
  tags          = ["ssh","http"]

  boot_disk {
    initialize_params {
      image = "centos-7"
    }
  }
  
  metadata {
    sshKeys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }

  metadata_startup_script = file("startup.sh")
  
  network_interface {
    # A default network is created for all GCP projects
    subnetwork = google_compute_subnetwork.public-subnet.self_link
    address_type = "INTERNAL"
    access_config {
    }
  }
}

resource "google_compute_instance" "vm_instance_private" {
  name          = "terraform-instance-private"
  machine_type  = "n1-standard-1"
  zone          = "${var.region}-a"
  
  boot_disk {
    initialize_params {
      image = "centos-7"
    }
  }

 
  network_interface {
    # A default network is created for all GCP projects
    subnetwork = google_compute_subnetwork.private-subnet.self_link
    address_type = "INTERNAL"
    access_config {
    }
  }
}

output "ip" {
  value = "${google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip}"
}

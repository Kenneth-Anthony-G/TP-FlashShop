# VPC, application subnet, Cloud NAT, and ingress rules for FlashShop.

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  name                     = var.subnetwork_name
  ip_cidr_range            = var.subnetwork_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_router" "cloud_router" {
  name    = var.router_name
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "cloud_nat" {
  name                               = var.nat_name
  router                             = google_compute_router.cloud_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_load_balancer" {
  name          = var.load_balancer_firewall_name
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [var.web_network_tag]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name          = var.iap_ssh_firewall_name
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.web_network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}


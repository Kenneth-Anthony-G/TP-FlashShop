output "network_id" {
  description = "ID of the FlashShop VPC network."
  value       = google_compute_network.vpc.id
}

output "network_self_link" {
  description = "Self link of the FlashShop VPC network."
  value       = google_compute_network.vpc.self_link
}

output "subnetwork_id" {
  description = "ID of the FlashShop application subnet."
  value       = google_compute_subnetwork.app.id
}

output "subnetwork_self_link" {
  description = "Self link of the FlashShop application subnet."
  value       = google_compute_subnetwork.app.self_link
}

output "router_id" {
  description = "ID of the Cloud Router used by Cloud NAT."
  value       = google_compute_router.cloud_router.id
}

output "web_network_tag" {
  description = "Network tag expected by the Load Balancer firewall rule."
  value       = var.web_network_tag
}
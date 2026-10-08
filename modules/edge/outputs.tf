output "ip_address" {
  description = "IP publique du Load Balancer"
  value       = google_compute_global_address.ip.address
}

output "backend_service_id" {
  description = "ID du backend service"
  value       = google_compute_backend_service.web.id
}
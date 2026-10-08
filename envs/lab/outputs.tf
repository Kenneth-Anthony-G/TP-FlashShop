output "load_balancer_ip" {
  description = "IP publique du Load Balancer"
  value       = module.edge.ip_address
}

output "load_balancer_url" {
  description = "URL publique de l'application"
  value       = "http://${module.edge.ip_address}"
}

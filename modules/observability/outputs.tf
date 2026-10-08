output "alert_policy_id" {
  description = "ID de la politique d'alerte CPU"
  value       = google_monitoring_alert_policy.cpu_high.id
}

output "notification_channel_id" {
  description = "ID du canal de notification"
  value       = google_monitoring_notification_channel.email.id
}
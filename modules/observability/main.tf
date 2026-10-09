# Module Observability (Monitoring, Dashboards, Alerting Policies, Log Metrics)

# Canal de notification
resource "google_monitoring_notification_channel" "email" {
  display_name = "Notification Alerte CPU"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

# Politique d'alerte CPU VM
resource "google_monitoring_alert_policy" "cpu_high" {
  display_name = "Alerte : Utilisation CPU VM > ${var.cpu_threshold_percent}%"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU supérieur à ${var.cpu_threshold_percent}%"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      threshold_value = var.cpu_threshold_percent / 100
      comparison      = "COMPARISON_GT"
      duration        = var.duration_seconds

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_NONE"
      }
    }
  }

  # Envoie l'alerte sans déclencher d'action automatique
  notification_channels = [
    google_monitoring_notification_channel.email.name
  ]

  documentation {
    content   = "L'utilisation du CPU d'une instance VM a dépassé ${var.cpu_threshold_percent}% pendant plus de ${var.duration_seconds}."
    mime_type = "text/markdown"
  }
}
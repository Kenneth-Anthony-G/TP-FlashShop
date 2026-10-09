# Variables pour le module observability

variable "cpu_threshold_percent" {
  description = "Seuil d'alerte CPU en pourcentage (ex: 70 pour 70%)"
  type        = number
  default     = 70
}

variable "duration_seconds" {
  description = "Durée pendant laquelle le seuil doit être dépassé avant de déclencher l'alerte"
  type        = string
  default     = "300s"
}

variable "notification_email" {
  description = "Adresse email recevant les alertes"
  type        = string
}
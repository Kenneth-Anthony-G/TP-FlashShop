variable "project_id" {
  description = "ID du projet GCP"
  type        = string
  default     = "flashop-prod"
}

variable "notification_email" {
  description = "Adresse e-mail pour la réception des alertes d'observabilité"
  type        = string
  default     = "zoebocquet26@gmail.com"
}

variable "region" {
  description = "Région GCP"
  type        = string
  default     = "europe-west9"
}

variable "machine_type" {
  description = "Type de machine"
  type        = string
  default     = "e2-micro"
}

variable "app_version" {
  description = "Version applicative"
  type        = string
  default     = "v1"
}

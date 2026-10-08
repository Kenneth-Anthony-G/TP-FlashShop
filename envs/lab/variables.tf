variable "project_id" {
  description = "ID du projet GCP"
  type        = string
  default     = "flashop-prod"
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

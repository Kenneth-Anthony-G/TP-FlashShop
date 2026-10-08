variable "app_version" {
  description = "Version de l'application"
  type        = string
  default     = "v1"
}

variable "network" {
  description = "ID ou nom du réseau VPC"
  type        = string
}

variable "subnetwork" {
  description = "ID ou nom du sous-réseau"
  type        = string
}

variable "web_network_tag" {
  description = "Tag réseau pour les VM web"
  type        = string
  default     = "flashshop-web"
}

variable "region" {
  description = "Région Google Cloud"
  type        = string
  default     = "europe-west9"
}

variable "machine_type" {
  description = "Type de machine pour les instances"
  type        = string
  default     = "e2-micro"
}

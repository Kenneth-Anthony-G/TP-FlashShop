variable "region" {
  description = "GCP region for the application subnet, router, and Cloud NAT."
  type        = string
  default     = "europe-west9"
}

variable "network_name" {
  description = "Name of the custom VPC network."
  type        = string
  default     = "flashshop-vpc"
}

variable "subnetwork_name" {
  description = "Name of the application subnet."
  type        = string
  default     = "flashshop-subnet-app"
}

variable "subnetwork_cidr" {
  description = "IPv4 range assigned to the application subnet."
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnetwork_cidr, 0))
    error_message = "subnetwork_cidr must be a valid IPv4 CIDR range."
  }
}

variable "router_name" {
  description = "Name of the Cloud Router used by Cloud NAT."
  type        = string
  default     = "flashshop-router"
}

variable "nat_name" {
  description = "Name of the Cloud NAT gateway."
  type        = string
  default     = "flashshop-nat"
}

variable "web_network_tag" {
  description = "Network tag applied to VM backends that accept Load Balancer traffic."
  type        = string
  default     = "flashshop-web"
}

variable "load_balancer_firewall_name" {
  description = "Name of the firewall rule allowing Google Load Balancer probes and traffic."
  type        = string
  default     = "flashshop-allow-lb-8080"
}

variable "enable_iap_ssh" {
  description = "Whether to allow SSH from the Google IAP TCP forwarding range."
  type        = bool
  default     = false
}

variable "iap_ssh_firewall_name" {
  description = "Name of the optional firewall rule allowing SSH through IAP."
  type        = string
  default     = "flashshop-allow-iap-ssh"
}


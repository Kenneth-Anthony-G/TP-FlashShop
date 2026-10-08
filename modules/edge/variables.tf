# Variables pour le module edge
variable "name_prefix" {
  type    = string
  default = "lab"
}

variable "instance_group" {
  description = "Instance group du MIG (fourni par le module compute)"
  type        = string
}

variable "named_port_name" {
  description = "Nom du port nommé défini dans le MIG"
  type        = string
  default     = "http"
}

variable "health_check_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  description = "Chemin testé par la sonde (à adapter à startup.sh)"
  type        = string
  default     = "/healthz"
}

variable "armor_rules" {
  description = "Règles Cloud Armor : blocage par plages d'IP"
  type = list(object({
    priority      = number
    action        = string # ex. deny(403)
    description   = string
    src_ip_ranges = list(string)
  }))
  default = []
}

variable "enable_waf_sqli" {
  description = "Règle WAF préconfigurée contre les injections SQL"
  type        = bool
  default     = true
}

variable "domains" {
  description = "Noms de domaine pour le certificat HTTPS. Vide = HTTP seulement"
  type        = list(string)
  default     = []
}

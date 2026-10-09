module "network" {
  source        = "../../modules/network"
  region        = var.region
  enable_iap_ssh = true
}

module "web_fleet" {
  source          = "../../modules/web_fleet"
  region          = var.region
  machine_type    = var.machine_type
  app_version     = var.app_version
  network         = module.network.network_id
  subnetwork      = module.network.subnetwork_id
  web_network_tag = module.network.web_network_tag
}

module "edge" {
  source         = "../../modules/edge"
  name_prefix    = "flashshop-lab"
  instance_group = module.web_fleet.instance_group
}

module "observability" {
  source = "../../modules/observability"

  # Variables de configuration de l'alerte
  cpu_threshold_percent = 50
  duration_seconds      = "60s"
  notification_email    = var.notification_email

  # Dépendance implicite pour s'assurer que le réseau est prêt
  depends_on = [
    module.network
  ]
}


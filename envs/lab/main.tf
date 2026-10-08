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

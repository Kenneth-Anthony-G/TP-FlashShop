# Module Web Fleet (Instance Templates, Managed Instance Groups, Autoscaling, Autohealing)

resource "google_compute_instance_template" "lab_shop_template" {
  name_prefix        = "lab-shop-"
  description = "This template is used to create app server instances."

  tags = [var.web_network_tag]

  instance_description = "description assigned to instances"
  machine_type         = var.machine_type
  can_ip_forward       = false

  // Create a new boot disk from an image
  disk {
    source_image      = "debian-cloud/debian-12"
    auto_delete       = true
    boot              = true
    disk_size_gb      = 10
  }
  metadata = {
    app-version = var.app_version
  }

  # Script de démarrage FlashShop
  metadata_startup_script = file("${path.module}/../../startup.sh")


  network_interface {
    network = var.network
    subnetwork = var.subnetwork
  }

lifecycle {
        create_before_destroy = true
    }
}

resource "google_compute_health_check" "lab_shop_hc" {
  name                = "lab-shop-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  http_health_check {
    request_path = "/healthz"
    port         = "8080"
  }
}


# Regional Managed Instance Group (MIG) répartissant les VMs sur la région
resource "google_compute_region_instance_group_manager" "lab_shop_mig" {
  name               = "lab-shop-mig"
  base_instance_name = "lab-shop"
  region             = var.region  
  target_size        = 3
  # Force une répartition égale stricte (1 VM par zone)
  # distribution_policy_target_shape = "EVEN"

  version {
    instance_template = google_compute_instance_template.lab_shop_template.id
  }

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.lab_shop_hc.id
    initial_delay_sec = 120
  }
  lifecycle { 
    ignore_changes = [target_size] 
    }
}

# Regional Autoscaler : adapte dynamiquement le nombre d'instances selon la charge CPU
resource "google_compute_region_autoscaler" "lab_autoscaler" {
  name   = "lab-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.lab_shop_mig.id

  autoscaling_policy {
    min_replicas    = 3
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.6 # Cible 60% d'utilisation CPU moyenne
    }
  }
}
# Module Web Fleet (Instance Templates, Managed Instance Groups, Autoscaling, Autohealing)

resource "google_compute_instance_template" "lab-shop_template" {
  name        = "lab-shop-instance"
  description = "This template is used to create app server instances."

  tags = ["instance-template", "lab-shop"]

  instance_description = "description assigned to instances"
  machine_type         = "e2-micro"
  can_ip_forward       = false

  // Create a new boot disk from an image
  disk {
    source_image      = "debian-cloud/debian-11"
    auto_delete       = true
    boot              = true
    disk_size_gb      = 10
  }

  network_interface {
    network = "default"
  }

lifecycle {
        create_before_destroy = true
    }
}

resource "google_compute_health_check" "lab-shop_hc" {
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
resource "google_compute_region_instance_group_manager" "lab-shop_mig" {
  name               = "lab-shop-mig"
  base_instance_name = "lab-shop"
  region             = "europe-west9"
  distribution_policy_zones = ["europe-west9-a", "europe-west9-b", "europe-west9-c"]    
  target_size        = 3

  version {
    instance_template = google_compute_instance_template.lab-shop_template.id
  }

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.lab-shop_hc.id
    initial_delay_sec = 300
  }
}

# Regional Autoscaler : adapte dynamiquement le nombre d'instances selon la charge CPU
resource "google_compute_region_autoscaler" "lab-autoscaler" {
  name   = "lab-autoscaler"
  region = "europe-west9"
  target = google_compute_region_instance_group_manager.lab-shop_mig.id

  autoscaling_policy {
    min_replicas    = 3
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.3 # Cible 60% d'utilisation CPU moyenne
    }
  }
}

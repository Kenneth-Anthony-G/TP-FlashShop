# Module Edge (Cloud Armor, Load Balancer, SSL, etc.)
resource "google_compute_health_check" "lb" {
  name                = "${var.name_prefix}-hc-lb"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }
}

resource "google_compute_security_policy" "armor" {
  name        = "${var.name_prefix}-armor"
  description = "Cloud Armor du backend service"

  dynamic "rule" {
    for_each = var.armor_rules
    content {
      priority    = rule.value.priority
      action      = rule.value.action
      description = rule.value.description
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value.src_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_waf_sqli ? [1] : []
    content {
      priority    = 1000
      action      = "deny(403)"
      description = "WAF : injections SQL"
      match {
        expr {
          expression = "evaluatePreconfiguredWaf('sqli-v33-stable')"
        }
      }
    }
  }

  # Règle par défaut obligatoire
  rule {
    priority    = 2147483647
    action      = "allow"
    description = "Règle par défaut"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_backend_service" "web" {
  name                  = "${var.name_prefix}-backend"
  protocol              = "HTTP"
  port_name             = var.named_port_name
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.lb.id]
  security_policy       = google_compute_security_policy.armor.id

  log_config {
    enable      = true
    sample_rate = 0.5
  }

  backend {
    group           = var.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "web" {
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_service.web.id
}

resource "google_compute_global_address" "ip" {
  name = "${var.name_prefix}-lb-ip"
}

# HTTP (port 80)
resource "google_compute_target_http_proxy" "http" {
  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.web.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name_prefix}-fr-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.ip.id
  port_range            = "80"
  target                = google_compute_target_http_proxy.http.id
}

# HTTPS (port 443), seulement si des domaines sont fournis
resource "google_compute_managed_ssl_certificate" "cert" {
  count = length(var.domains) > 0 ? 1 : 0
  name  = "${var.name_prefix}-cert"
  managed {
    domains = var.domains
  }
}

resource "google_compute_target_https_proxy" "https" {
  count            = length(var.domains) > 0 ? 1 : 0
  name             = "${var.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.web.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cert[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = length(var.domains) > 0 ? 1 : 0
  name                  = "${var.name_prefix}-fr-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.ip.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.https[0].id
}

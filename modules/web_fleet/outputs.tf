output "instance_group" {
  description = "Instance group du MIG"
  value       = google_compute_region_instance_group_manager.lab_shop_mig.instance_group
}

# Create VPC network for the application to use
resource "google_compute_network" "app" {
  project                 = var.project_id
  name                    = var.app_slug
  auto_create_subnetworks = false
}

# Create subnetwork for the application and enable private access to Google services.
# This will allow the application to access Google services without a public IP
resource "google_compute_subnetwork" "app_subnet_1" {
  project       = var.project_id
  purpose       = "PRIVATE"
  name          = "${var.app_slug}-subnetwork-1"
  ip_cidr_range = "10.113.0.0/24"
  network       = google_compute_network.app.self_link
  region        = var.region
  # allow access to google services from within subnetwork
  private_ip_google_access   = true
  private_ipv6_google_access = "ENABLE_OUTBOUND_VM_ACCESS_TO_GOOGLE"
}

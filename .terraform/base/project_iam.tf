# Service account for application
resource "google_service_account" "app_sa" {
  project      = var.project_id
  account_id   = var.app_slug
  display_name = "My App Service Account"
  depends_on   = [time_sleep.services_ready]
}

# Allow application SA to write logs
resource "google_project_iam_member" "app_sa_monitoring_logWriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

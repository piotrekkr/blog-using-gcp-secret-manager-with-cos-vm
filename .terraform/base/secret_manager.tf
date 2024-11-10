# Create application secret
resource "google_secret_manager_secret" "secret_file" {
  project   = var.project_id
  secret_id = "secret_file"
  replication {
    auto {}
  }
  depends_on = [time_sleep.services_ready]
}

# Grant the service account access to the secret
resource "google_secret_manager_secret_iam_member" "my_app_sa_secretAccessor_secret_file" {
  project   = google_secret_manager_secret.secret_file.project
  secret_id = google_secret_manager_secret.secret_file.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app_sa.email}"
}

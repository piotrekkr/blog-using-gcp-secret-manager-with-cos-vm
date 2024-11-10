# Create artifact registry repository for application Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  project       = var.project_id
  location      = "europe"
  repository_id = var.app_slug
  description   = "${var.app_name} Docker Repository"
  format        = "DOCKER"
  depends_on    = [time_sleep.services_ready]
}

# Grant the service account access to the repository
resource "google_artifact_registry_repository_iam_member" "my_app_sa_artifactregistry_reader" {
  project    = google_artifact_registry_repository.docker_repo.project
  location   = google_artifact_registry_repository.docker_repo.location
  repository = google_artifact_registry_repository.docker_repo.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.app_sa.email}"
}

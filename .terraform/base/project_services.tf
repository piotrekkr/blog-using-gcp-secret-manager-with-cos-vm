resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Wait for services to be ready
resource "time_sleep" "services_ready" {
  depends_on = [
    google_project_service.compute,
    google_project_service.iam,
    google_project_service.secretmanager,
    google_project_service.artifactregistry,
  ]

  create_duration = "1m"
}

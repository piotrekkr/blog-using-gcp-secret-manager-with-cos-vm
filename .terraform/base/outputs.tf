output "service_account_email" {
  value = google_service_account.app_sa.email
}

output "secret_id" {
  value = google_secret_manager_secret.secret_file.id
}

output "docker_registry_url" {
  value = format(
    "%s-docker.pkg.dev/%s/%s",
    google_artifact_registry_repository.docker_repo.location,
    google_artifact_registry_repository.docker_repo.project,
    google_artifact_registry_repository.docker_repo.repository_id
  )
}

output "network_self_link" {
  value = google_compute_network.app.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.app_subnet_1.self_link
}

variable "project_id" {
  description = "The GCP project ID"
}

variable "app_slug" {
  description = "The application slug, e.g. my-app"
}

variable "app_image_url" {
  description = "The URL of the Docker image"
}

variable "secret_id" {
  description = "The secret ID, e.g. projects/my-project/secrets/my-secret"
}

variable "service_account_email" {
  description = "The email of the service account"
}

variable "network_self_link" {
  description = "The self link of the network"
}

variable "subnetwork_self_link" {
  description = "The self link of the subnetwork"
}

variable "zone" {
  description = "The GCP zone"
}

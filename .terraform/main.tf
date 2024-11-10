provider "google" {
  project = var.project_id
}

# Base infrastructure
module "base" {
  source     = "./base"
  project_id = var.project_id
  app_name   = var.app_name
  app_slug   = var.app_slug
  region     = var.region
}

# Deploy infrastructure
module "deploy" {
  source                = "./deploy"
  project_id            = var.project_id
  app_slug              = var.app_slug
  app_image_url         = "${module.base.docker_registry_url}/${var.app_slug}:latest"
  secret_id             = module.base.secret_id
  service_account_email = module.base.service_account_email
  zone                  = var.zone
  network_self_link     = module.base.network_self_link
  subnetwork_self_link  = module.base.subnetwork_self_link
}

# Output the Docker image tag so it can be used when building the image
output "docker_image_tag" {
  value = format("%s/my-app:latest", module.base.docker_registry_url)
}

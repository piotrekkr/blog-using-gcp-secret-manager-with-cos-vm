# Using GCP Secret Manager With Container-Optimized OS VM

Using Google Cloud Platform [Secret Manager](https://cloud.google.com/security/products/secret-manager?hl=en) service is 
a convenient way to store and manage secrets. It has many features like automatic rotation, audit logging, access control 
and many others. It is integrated with GCP services like 
[Cloud Functions](https://cloud.google.com/functions/docs/configuring/secrets), 
[Cloud Run](https://cloud.google.com/run/docs/configuring/services/secrets), 
[GKE](https://cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component) (and probably some other), 
provides a REST API to access secrets and has a client library for many programming languages.

Sadly, there seems to be no easy way to use it with [Google Compute Engine](https://cloud.google.com/products/compute?hl=en) 
VMs, especially with [Container-Optimized OS (COS)](https://cloud.google.com/container-optimized-os/docs) VM image, 
which I use quite often when dealing with containerized applications.

This is a guide on how to integrate GCP Secret Manager with Container-Optimized OS VM.

## Assumptions

* [gcloud](https://cloud.google.com/sdk/docs/install) CLI tool is installed, and you are authenticated in GCP.
* You have a fresh and empty project in GCP that you have permissions to manage (like owner or similar role).
* Docker and [OpenTofu](https://opentofu.org/docs/intro/install/) is installed on your machine.

## The plan

1. Infrastructure configuration will be kept in a Terraform modules and OpenTofu will be used to apply changes.
2. Terraform config will be split into two modules:
    * `base` - infrastructure that do not change on deploy, like project services, artifact registry, VPC configuration, 
      secret manager secret, service accounts, IAM permissions etc.
    * `deploy` - infrastructure that is applied on deploy, like VM configuration, `cloudinit` and container 
      specification etc.
3. Simple bash script will be created that reads secrets from file and prints them to `stdout`.
4. Script will be containerized and pushed to Artifact Registry.
5. Applying Terraform `deploy` module will create a VM with Container-Optimized OS that will pull secrets from 
   Secret Manager and run application container with secret mounted inside app container.
6. While running, the application will generate logs that should contain secret contents.

## Terraform setup

Let's create a new Terraform configuration inside `.terraform/` directory at the root of the project. It should contain 
two submodules, `base` and `deploy`, and a root module configuration that will use both of them.

### Base sub-module

Base infrastructure should contain all the necessary resources that will be used by the `deploy` submodule. Those 
resources should not change often. Base infrastructure contains:

* Enabled project services like Secret Manager, Artifact Registry, Compute Engine API etc.
* Service account that will be used as runtime identity for VM.
* Secret manager secret with some secret value.
* Artifact Registry repository to store application docker image.
* IAM permissions for service account to access secret, app image in Artifact Registry, create VMs etc.
* VPC network and subnet configuration with [Google Private Access](https://cloud.google.com/vpc/docs/private-google-access) 
  enabled to allow VM with private IP to access GCP resources.

Directory structure:

```
.terraform/base
├── artifact_registry.tf        # Artifact Registry repository configuration
├── outputs.tf                  # Outputs definition, needed by deploy module
├── project_iam.tf              # Project IAM permissions configuration
├── project_services.tf         # Project services configuration
├── providers.tf                # Required providers configuration
├── secret_manager.tf           # Secret Manager secret configuration
├── variables.tf                # Required variables definition 
└── vpc.tf                      # VPC network and subnet configuration
```

#### `.terraform/base/variables.tf`

```hcl
variable "project_id" {
  description = "The GCP project ID"
}

variable "app_name" {
  description = "The application name, e.g.: My App"
}

variable "app_slug" {
  description = "The application slug, e.g. my-app"
}

variable "region" {
  description = "The GCP region to use for subnetwork"
}
```

#### `.terraform/base/providers.tf`

Specify required providers and their versions.

```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}
```

#### `.terraform/base/project_services.tf`

GCP services APIs need to be enabled in the project to be able to use them.

```hcl
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
```

#### `.terraform/base/project_iam.tf`

```hcl
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
```

#### `.terraform/base/artifact_registry.tf`

```hcl
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
```

#### `.terraform/base/secret_manager.tf`

```hcl
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
```

#### `.terraform/base/outputs.tf`

```hcl
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
```

### Deploy submodule

Deploy infrastructure should contain all the necessary resources that will be created or updated on each deploy. Base 
infrastructure contains:

* [`cloud-init`](https://cloud-init.io/) configuration that will be used to set up VM instance including fetching 
  secret and storing it on disk.
* Compute Engine VM instance using Container-Optimized OS image and container specification that will mount this secret 
  to running container .

Directory structure:

```
.terraform/deploy
├── cloudinit.yaml.tpl
├── compute_engine.tf
├── providers.tf
└── variables.tf
```

#### `.terraform/deploy/variables.tf`

```hcl
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
```

#### `.terraform/deploy/providers.tf`

```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}
```

#### `.terraform/deploy/cloudinit.yaml.tpl`

Cloud-init is the industry standard multi-distribution method for cross-platform cloud instance initialization. It is 
supported across all major public cloud providers, provisioning systems for private cloud infrastructure, and bare-metal 
installations. The `cloudinit.yaml.tpl` file is a template that will be used to generate `cloud-config` file that will 
be used to:

* create empty secret file on disk
* create a script that reads secret from Secret Manager and writes it to empty secret file
* configure VM instance to run this script on startup

The scrip itself is using GCP metadata server to fetch workload identity service account access token, then uses this 
token to fetch secret from Secret Manager and write it to `/etc/secret_file`.

```yaml
#cloud-config

write_files:
  # Create empty file so it will always exist when mounting a volume to container.
  # When source file or directory is missing, docker will create a root-owned directory with same path and then
  # mount it inside container.
  - path: /etc/secret_file
    permissions: '0644'
    owner: root
    content: ''

  # Script that will take care of fetching the secret from secret manager, using VM service account access token
  - path: /etc/scripts/fetch-secret.sh
    permissions: '0755'
    owner: root
    content: |
      #!/bin/bash

      # this script:
      #   1. generates access token using google metadata server
      #   2. fetches the secret version contents
      #   3. decodes it and writes it to the /etc/secret_file

      set -e

      secret_version_id="${secret_id}/versions/${secret_version}"

      access_token=$(
        curl http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
         -H 'Metadata-Flavor: Google' \
        | cut -d'"' -f 4
      )

      curl "https://secretmanager.googleapis.com/v1/$secret_version_id:access?fields=payload.data&prettyPrint=false" \
        -H "Authorization: Bearer $access_token" \
        -H 'Accept: application/json' | cut -d '"' -f 6 | base64 -d > /etc/secret_file

runcmd:
  - /etc/scripts/fetch-secret.sh
```

#### `.terraform/deploy/compute_engine.tf`

```hcl
locals {
  # Docker container specification
  container_spec = {
    spec = {
      restartPolicy = "OnFailure"
      # Volumes that will be mounted to the application container
      volumes = [
        {
          name = "secret"
          hostPath = {
            # Path inside VM where the secret file is located
            path = "/etc/secret_file"
          }
        },
      ]

      containers = [{
        name  = var.app_slug
        image = var.app_image_url
        # Define what volumes to mount inside the container
        volumeMounts = [
          {
            # Path inside application container to mount the secret file
            mountPath = "/secret"
            name      = "secret"
            readOnly  = true
          },
        ]

        env = [
          {
            name  = "MY_ENV_VAR"
            value = "my-env-var-value"
          },
        ]
      }]
    }
  }
}

# Get the latest stable Container-Optimized OS image data
data "google_compute_image" "cos" {
  family  = "cos-stable"
  project = "cos-cloud"
}

# Generate a cloud-init configuration based on template file `cloudinit.yaml.tpl`.
# It will be used to setup the VM.
data "template_file" "cloudinit" {
  template = file("${path.module}/cloudinit.yaml.tpl")
  vars = {
    project_id     = var.project_id
    secret_id      = var.secret_id
    secret_version = "latest"
  }
}

locals {
  # Container specification need to be passed in yaml format in VM metadata
  container_spec_yaml = yamlencode(local.container_spec)

  # MD5 hash made from container spec and cloud-init file content.
  machine_config_hash = md5(
    format(
      "%s-%s",
      local.container_spec_yaml,
      data.template_file.cloudinit.rendered
    )
  )
  # Use config hash inside instance name to ensure that the instance is recreated when the configuration changes.
  compute_instance_name = format("%s-%s", var.app_slug, substr(local.machine_config_hash, 0, 5))
}

# Create a VM instance for the application
resource "google_compute_instance" "my_app_vm" {
  project                   = var.project_id
  name                      = local.compute_instance_name
  machine_type              = "f1-micro"
  zone                      = var.zone
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos.self_link
      size  = 10
      type  = "pd-ssd"
    }
  }

  metadata = {
    google-logging-enabled = "true"
    # Define containers spec
    gce-container-declaration = local.container_spec_yaml
    enable-oslogin            = "TRUE"
    # Set cloud-init file contents
    user-data              = data.template_file.cloudinit.rendered
    block-project-ssh-keys = true
  }

  # Setup network interface for the VM, it will only have a private IP address
  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnetwork_self_link
  }

  # Set service account for the VM to identify itself to other services in GCP
  service_account {
    scopes = ["cloud-platform"]
    email  = var.service_account_email
  }
}
```

### Root Terraform module

The root module will use both `base` and `deploy` submodules to create the whole infrastructure.

Directory structure should look like this: Structure should look like this:

```
.terraform              # Root of the terraform project
├── base                # Base submodule directory 
├── deploy              # Deploy submodule directory
├── main.tf             # Main terraform configuration which uses base and deploy submodules
├── terraform.tfvars    # Terraform variables values file for conveniance (not tracked by GIT)
└── variables.tf        # Terraform variables definition file
```

#### `.terraform/variables.tf`

```hcl
variable "project_id" {
  description = "The GCP project ID"
}

variable "app_name" {
  description = "The application name, e.g.: My App"
}

variable "app_slug" {
  description = "The application slug, e.g. my-app"
}

variable "region" {
  description = "The GCP region"
}

variable "zone" {
  description = "The GCP zone"
}
```

#### `.terraform/main.tf`

```hcl
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
```

#### `.terraform/terraform.tfvars`

The `terraform.tfvars` file will contain all the necessary variable values that will be used when applying changes. 
It is done to avoid specifying variables on the command line each time when applying changes. This file should not be 
tracked by VCS and is used only for convenience.

```hcl
project_id = "my-app-project"
app_name   = "My App"
app_slug   = "my-app"
region     = "europe-west1"
zone       = "europe-west1-b"
```

## Apply base infrastructure

```shell
tofu apply -target module.base
```

## Create `Dockerfile` in project root

It will be based on stable Debian image, create a script "inline" that reads secret from file and prints it to `stdout`. 
This script will be used as default container command to run.

```dockerfile
# syntax=docker/dockerfile:1

FROM debian:stable-slim

COPY <<EOF /app.sh
#!/usr/bin/env bash
set -Eeuo pipefail
while true; do
  [[ -f /secret ]] && echo "Secret file contains: $(cat /secret)" || echo "Secret file does not exist!";
  sleep 30;
done
EOF

RUN chmod +x /app.sh

CMD ["/app.sh"]
```

## Build and push application image

```shell
docker build -t europe-docker.pkg.dev/my-app-project/my-app/my-app:latest .
docker push europe-docker.pkg.dev/my-app-project/my-app/my-app:latest
```

## Create secret version

When applying base submodule, a secret was created in Secret Manager. However, it is only a "container" for secret 
versions and by itself does not represent any secret value. We should create a secret version that contains actual 
secret value.

```shell
printf "my-secret-value" | gcloud secrets versions add secret_file --data-file=- --project=my-app-project
```

## Apply deploy infrastructure

```shell
tofu apply -target module.deploy
```

## Check logs

After the VM is created, it should start the container and print the secret value to container `stdout` every 30 seconds. 
We should wait few minutes and then read the logs. Before that however, we need to find the instance ID.

```shell
$ gcloud compute instances list --format="table(name, id)" --project=my-app-project
NAME          ID
my-app-38ec6  2322076665855158865
```

Now we can read the logs to confirm all works as expected:

```shell
$ gcloud logging read 'resource.type="gce_instance" resource.labels.instance_id="2322076665855158865"' \
  --project=my-app-project \
  --format="table(timestamp, jsonPayload.message)" \
  --limit 5
TIMESTAMP                       MESSAGE
2024-11-04T14:21:31.613754143Z  Secret file contains: my-secret-value
2024-11-04T14:21:01.610290064Z  Secret file contains: my-secret-value
2024-11-04T14:20:31.605553541Z  Secret file contains: my-secret-value
2024-11-04T14:20:01.602425176Z  Secret file contains: my-secret-value
2024-11-04T14:19:31.597518758Z  Secret file contains: my-secret-value
```

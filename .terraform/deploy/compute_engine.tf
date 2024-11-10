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

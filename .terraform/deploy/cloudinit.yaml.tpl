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

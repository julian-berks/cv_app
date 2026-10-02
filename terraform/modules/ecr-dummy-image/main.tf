# Seeds a dummy :latest image into a fresh ECR repo so the container-image Lambda
# can be created BEFORE the CI pipeline pushes real code. A valid public Lambda
# base image is retagged and pushed; CI later overwrites it via update-function-code.
#
# Requires docker + aws CLI on the apply host (present in CI). Only runs at apply.

locals {
  registry = split("/", var.ecr_repository_url)[0]
}

resource "null_resource" "dummy_image" {
  triggers = {
    repository = var.ecr_repository_name
    image_tag  = var.ecr_image_tag
    dependency = jsonencode(var.dependency)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.registry}
      docker pull ${var.base_image}
      docker tag ${var.base_image} ${var.ecr_repository_url}:${var.ecr_image_tag}
      docker push ${var.ecr_repository_url}:${var.ecr_image_tag}
    EOT
  }
}

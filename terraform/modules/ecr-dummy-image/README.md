# module: ecr-dummy-image

Seeds a dummy `:latest` image into a fresh ECR repo (BUILT) so a container-image
Lambda can be created before CI pushes real code. A valid public Lambda base image
is retagged + pushed via `local-exec` (needs docker + aws CLI on the apply host;
runs at apply only).

Inputs: `ecr_repository_url`, `ecr_repository_name`, `ecr_image_tag`, `base_image`,
`region`, `dependency`. Output: `id`.

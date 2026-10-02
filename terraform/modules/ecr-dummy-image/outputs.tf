output "id" {
  description = "ID of the dummy-image seed resource (use as a dependency handle)."
  value       = null_resource.dummy_image.id
}

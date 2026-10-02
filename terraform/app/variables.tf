
variable "name" {
   type = string
   default = "julian-cv"
   description = "Name of the CV application"
}


variable "container_deployed" {
   type = bool
   default = false
   description = "Flag to indicate if the container has been deployed"
}     

variable "tags" {
   type = map(string)
   default = {}
   description = "Tags to apply to resources"
}

variable "region" {
   type = string
   default = "eu-west-2"
   description = "AWS region for the resources"
}  


##variable "image_uri" {
#   type = string
#   description = "URI of the container image to deploy"
#   default = "594542138399.dkr.ecr.eu-west-2.amazonaws.com/julian-cv-ecr:latest"
#}  
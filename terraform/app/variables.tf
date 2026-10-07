
variable "name" {
   type = string
   default = "julian-cv"
   description = "Name of the CV application"
}

variable "container_deployed" {
   type = bool
   default = true
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

variable "model_id" {
   type = string
   default = "amazon.nova-micro-v1:0"
   description = "ID of the model to use"
}


variable "domain_name" {
   type = string
   default = "cv.julianberks.com"
   description = "Domain name for the application"
}

terraform {
  required_version = ">= 1.11"
  
  backend "s3" {
    bucket         = "594542138399-tfstate"
    key            = "cv-app/terraform.tfstate"
    region         = "eu-west-2"
    use_lockfile   = true
    encrypt        = true
  }
}

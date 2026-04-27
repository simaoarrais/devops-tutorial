variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
  default     = "devops-tutorial"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"   # free tier eligible
}
data "aws_ami" "image" {
  most_recent = true
  owners = ["self"]
  filter {                       
    name = "tag:OS_Version"     
    values = ["CentOS"]
  }                              
}

output "ami_id" {
  value = data.aws_ami.image.id
}

output "elb" {
  value = aws_elb.web.dns_name
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-west-1"
}

variable "instance_size" {
  description = "Instance sizes for control plane and machine nodes"
  default     = "t2.medium"
}

variable "private_key" {
  description = "Path to private SSH key"
  default     = "~/macos/mbagnara-key.pem"
}

variable "key_name" {
  description = "AWS SSH keypair"
  default = "mbagnara-key"
}
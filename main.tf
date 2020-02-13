# Specify the provider and access details
provider "aws" {
  region = var.aws_region
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "k8s-terraform"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "k8s-terraform"
  }
}

resource "aws_route_table" "default" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id             = aws_internet_gateway.default.id
  }

  tags = {
    Name = "k8s-terraform"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.default.id
  route_table_id = aws_route_table.default.id
}



# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-terraform"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }
}


# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All traffic internal to VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-terraform"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }
} 

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id


  # HTTPS access from anywhere
  ingress {
    from_port   = 6443 
    to_port     = 6443 
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "web" {
  name = "terraform-control-plane-elb"
  //availability_zones = aws_instance.control-plane[*].availability_zone

  # The instances are registered automatically
  instances = aws_instance.control-plane[*].id

  subnets = [aws_subnet.default.id]

  # Our Security group to allow HTTP and SSH access
  security_groups = [aws_security_group.elb.id]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"

  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:6443"
    interval            = 12
  }
}


//resource "aws_key_pair" "auth" {
//  key_name   = "${var.key_name}"
//  public_key = "${file(var.public_key_path)}"
//}

resource "aws_instance" "control-plane" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "centos"
    host = self.public_ip
    private_key = file(var.private_key)

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = var.instance_size

  ami = data.aws_ami.image.id

  # The name of our SSH keypair we created above.
  key_name = var.key_name

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.default.id]

  subnet_id = aws_subnet.default.id

  iam_instance_profile = aws_iam_instance_profile.control-plane-instance.id

  count = 3

  tags = {
    Name = "control-plane"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }

  provisioner "remote-exec" {
    inline = [
      "date"
    ]
  }

}

resource "aws_instance" "node" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "centos"
    host = self.public_ip
    private_key = file(var.private_key)

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = var.instance_size

  ami = data.aws_ami.image.id

  # The name of our SSH keypair we created above.
  key_name = var.key_name

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.default.id]

  subnet_id = aws_subnet.default.id

  iam_instance_profile = aws_iam_instance_profile.worker-node-instance.id

  count = 2

  tags = {
    Name = "node1"
    "kubernetes.io/cluster/terraform-k8s-cluster" = "yes"
  }

  provisioner "remote-exec" {
    inline = [
      "date"
    ]
  }

}

resource "aws_iam_policy" "control-plane-policy" {
  name        = "control-plane-policy"
  path        = "/"
  description = "IAM for control plane nodes"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyVolume",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DetachVolume",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeVpcs",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:AttachLoadBalancerToSubnets",
        "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:ConfigureHealthCheck",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancerListeners",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DetachLoadBalancerFromSubnets",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancerPolicies",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
        "iam:CreateServiceLinkedRole",
        "kms:DescribeKey"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "control-plane-role" {
  name = "control-plane-role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "control-plane-attach" {
  name       = "control-plane-attach"
  roles      = [aws_iam_role.control-plane-role.name]
  policy_arn = aws_iam_policy.control-plane-policy.arn
}

resource "aws_iam_instance_profile" "control-plane-instance" {
	name = "control-plane-instance"
	role = aws_iam_role.control-plane-role.id
}

resource "aws_iam_policy" "worker-node-policy" {
  name        = "worker-node-policy"
  path        = "/"
  description = "IAM for worker nodes"

  policy = <<EOF
{
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Action": [
                  "ec2:DescribeInstances",
                  "ec2:DescribeRegions",
                  "ecr:GetAuthorizationToken",
                  "ecr:BatchCheckLayerAvailability",
                  "ecr:GetDownloadUrlForLayer",
                  "ecr:GetRepositoryPolicy",
                  "ecr:DescribeRepositories",
                  "ecr:ListImages",
                  "ecr:BatchGetImage"
              ],
              "Resource": "*"
          } 
      ]
  }
EOF
}


resource "aws_iam_role" "worker-node-role" {
  name = "worker-node-role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "worker-node-attach" {
  name       = "worker-node-attach"
  roles      = [aws_iam_role.worker-node-role.name]
  policy_arn = aws_iam_policy.worker-node-policy.arn
}

resource "aws_iam_instance_profile" "worker-node-instance" {
	name = "worker-node-instance"
	role = aws_iam_role.worker-node-role.id
}
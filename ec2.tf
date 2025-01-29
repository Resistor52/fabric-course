# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create the setup script from template
data "template_file" "setup" {
  template = file("${path.module}/setup.tpl")
  vars = {
    DOMAIN              = var.domain
    EMAIL               = var.email
    DUCKDNS_TOKEN      = var.duckdns_token
    NUM_USERS           = var.number_of_users
  }
}

resource "aws_instance" "fabric_course" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "g5.2xlarge"
  key_name      = var.ssh_key_name

  # Required for GPU instances
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.fabric_course.id]
  associate_public_ip_address = true

  user_data = base64encode(data.template_file.setup.rendered)

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
      user_data_base64
    ]
  }

  tags = {
    Name = "fabric-course"
    Environment = "production"
  }
}

# Associate the Elastic IP with the instance
resource "aws_eip_association" "fabric_course" {
  instance_id   = aws_instance.fabric_course.id
  allocation_id = aws_eip.fabric_course.id
}

# Update the outputs to use the Elastic IP
output "public_ip" {
  value = aws_eip.fabric_course.public_ip
  depends_on = [aws_eip_association.fabric_course]
}

output "ssh_command" {
  value = "ssh -i ${var.ssh_pem_file} ubuntu@${aws_eip.fabric_course.public_ip}"
  depends_on = [aws_eip_association.fabric_course]
} 
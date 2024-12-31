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
    DOMAIN         = var.domain
    EMAIL          = var.email
    DUCKDNS_TOKEN  = var.duckdns_token
    CODE_SERVER_PASSWORD = var.code_server_password
  }
}

resource "aws_instance" "fabric_course" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = "aws3-use1v2"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.fabric_course.id]
  associate_public_ip_address = true

  user_data = base64encode(data.template_file.setup.rendered)

  root_block_device {
    volume_size = 20
  }

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

# Output the public IP of the instance
output "public_ip" {
  value = aws_instance.fabric_course.public_ip
  depends_on = [aws_instance.fabric_course]
}

# Add SSH command output
output "ssh_command" {
  value = "ssh -i aws3-use1v2.pem ubuntu@${aws_instance.fabric_course.public_ip}"
  depends_on = [aws_instance.fabric_course]
} 
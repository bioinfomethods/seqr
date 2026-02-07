packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "prefix" {
  type    = string
  default = "mcri"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "clickhouse_version" {
  type    = string
  default = "25.12"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to launch the Packer build instance in"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.prefix}-seqr-${var.environment}-clickhouse-${local.timestamp}"
}

source "amazon-ebs" "clickhouse" {
  ami_name                    = local.ami_name
  instance_type               = "t3.medium"
  region                      = var.aws_region
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  
  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }
  
  ssh_username = "ec2-user"
  
  tags = {
    Name              = local.ami_name
    Project           = "seqr"
    Environment       = var.environment
    ManagedBy         = "packer"
    ClickhouseVersion = var.clickhouse_version
    BuildDate         = local.timestamp
  }
}

build {
  sources = ["source.amazon-ebs.clickhouse"]

  # Install Docker and AWS CLI
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker and AWS CLI...'",
      "sudo dnf install -y docker aws-cli",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ec2-user",
      "echo 'Installing Docker Compose plugin...'",
      "sudo mkdir -p /usr/local/lib/docker/cli-plugins",
      "sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose",
      "sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose",
      "docker compose version"
    ]
  }

  # Create directory structure
  provisioner "shell" {
    inline = [
      "echo 'Creating directory structure...'",
      "mkdir -p /home/ec2-user/clickhouse/config",
      "mkdir -p /home/ec2-user/clickhouse/scripts",
      "sudo mkdir -p /var/lib/clickhouse",
      "mkdir -p /tmp/clickhouse-configs"
    ]
  }

  # Copy configuration files
  provisioner "file" {
    source      = "configs/"
    destination = "/tmp/clickhouse-configs/"
  }

  # Move configs to final location
  provisioner "shell" {
    inline = [
      "echo 'Installing configuration files...'",
      "mv /tmp/clickhouse-configs/config.xml /home/ec2-user/clickhouse/config/",
      "mv /tmp/clickhouse-configs/users.xml /home/ec2-user/clickhouse/config/",
      "mv /tmp/clickhouse-configs/named_collections.xml /home/ec2-user/clickhouse/config/",
      "mv /tmp/clickhouse-configs/init-permissions.sql /home/ec2-user/clickhouse/config/",
      "mv /tmp/clickhouse-configs/docker-compose.yml /home/ec2-user/clickhouse/"
    ]
  }

  # Copy startup script
  provisioner "file" {
    source      = "scripts/start-clickhouse.sh"
    destination = "/tmp/start-clickhouse.sh"
  }

  provisioner "shell" {
    inline = [
      "mv /tmp/start-clickhouse.sh /home/ec2-user/clickhouse/scripts/",
      "chmod +x /home/ec2-user/clickhouse/scripts/start-clickhouse.sh"
    ]
  }

  # Pre-pull Clickhouse Docker image
  provisioner "shell" {
    inline = [
      "echo 'Pre-pulling Clickhouse Docker image...'",
      "sudo docker pull clickhouse/clickhouse-server:${var.clickhouse_version}"
    ]
  }

  # Create systemd service
  provisioner "file" {
    content = <<-EOF
[Unit]
Description=Clickhouse Server
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
User=ec2-user
Group=ec2-user
ExecStart=/home/ec2-user/clickhouse/scripts/start-clickhouse.sh

[Install]
WantedBy=multi-user.target
EOF
    destination = "/tmp/clickhouse.service"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/clickhouse.service /etc/systemd/system/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable clickhouse.service"
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "sudo rm -rf /tmp/*",
      "sudo dnf clean all"
    ]
  }
}

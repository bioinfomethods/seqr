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

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.prefix}-seqr-${var.environment}-clickhouse-${local.timestamp}"
}

source "amazon-ebs" "clickhouse" {
  ami_name      = local.ami_name
  instance_type = "t3.medium"
  region        = var.aws_region
  
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
      "sudo usermod -aG docker ec2-user"
    ]
  }

  # Create directory structure
  provisioner "shell" {
    inline = [
      "echo 'Creating directory structure...'",
      "sudo mkdir -p /opt/clickhouse/config",
      "sudo mkdir -p /opt/clickhouse/scripts",
      "sudo mkdir -p /var/lib/clickhouse"
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
      "sudo mv /tmp/clickhouse-configs/* /opt/clickhouse/config/",
      "sudo chown -R root:root /opt/clickhouse/config"
    ]
  }

  # Copy startup script
  provisioner "file" {
    source      = "scripts/start-clickhouse.sh"
    destination = "/tmp/start-clickhouse.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/start-clickhouse.sh /opt/clickhouse/scripts/",
      "sudo chmod +x /opt/clickhouse/scripts/start-clickhouse.sh"
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
ExecStart=/opt/clickhouse/scripts/start-clickhouse.sh

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

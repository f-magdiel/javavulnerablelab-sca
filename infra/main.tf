terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "web" {
  name        = "jvl-web"
  description = "Acceso web y administracion"

  ingress {
    description = "SSH solo desde la red interna"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Aplicacion web"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida solo por HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  tags = {
    owner = "equipo-jvl"
  }

  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  monitoring             = true
  ebs_optimized          = true
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }
}

resource "aws_s3_bucket" "logs" {
  # Excepción única del repositorio. Se acepta el riesgo porque este bucket solo
  # guarda logs de acceso de un entorno de laboratorio, sin datos de producción,
  # y replicarlo a otra región duplicaría costo sin reducir un riesgo real.
  # Aprobó: Responsable de seguridad de la materia | Ref: SEC-001 | Vence: 2027-03-31
  # checkov:skip=CKV_AWS_144: Logs de laboratorio sin datos sensibles; aprobado SEC-001; vence 2027-03-31
  tags = {
    owner = "equipo-jvl"
  }

  bucket = "jvl-logs-demo"
}

resource "aws_db_instance" "mysql" {
  tags = {
    owner = "equipo-jvl"
  }

  identifier          = "jvl-db"
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "Cambiar123!"
  publicly_accessible = false
  storage_encrypted   = true
  skip_final_snapshot = true

  multi_az                            = true
  deletion_protection                 = true
  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true
  backup_retention_period             = 7
  enabled_cloudwatch_logs_exports     = ["error", "general", "slowquery"]
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_monitoreo.arn
}

resource "aws_iam_role" "rds_monitoreo" {
  name = "jvl-rds-monitoreo"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoreo" {
  role       = aws_iam_role.rds_monitoreo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_kms_key" "datos" {
  description         = "Clave para cifrar datos de JavaVulnerableLab"
  enable_key_rotation = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AdministracionDeLaCuenta"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.actual.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

data "aws_caller_identity" "actual" {}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.datos.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "logs" {
  bucket        = aws_s3_bucket.logs.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "acceso/"
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expirar-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_sns_topic" "eventos_logs" {
  name              = "jvl-eventos-logs"
  kms_master_key_id = aws_kms_key.datos.id
}

resource "aws_s3_bucket_notification" "logs" {
  bucket = aws_s3_bucket.logs.id

  topic {
    topic_arn = aws_sns_topic.eventos_logs.arn
    events    = ["s3:ObjectRemoved:*"]
  }
}

resource "aws_iam_role" "app" {
  name = "jvl-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "jvl-app"
  role = aws_iam_role.app.name
}

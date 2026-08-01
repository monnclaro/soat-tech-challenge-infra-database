# Recursos criados:
#   - Security Group do RDS (5432 liberado para a CIDR das subnets privadas)
#   - DB Subnet Group (subnets privadas da VPC do infra-k8s)
#   - Credenciais geradas pelo Terraform, publicadas como SSM SecureString
#     (não Secrets Manager — prioridade de custo, ver ADR 0008. SecureString
#     usa a chave gerenciada padrão da AWS, sem precisar criar KMS key própria,
#     o que também evita esbarrar nas restrições de IAM do AWS Academy)
#   - RDS PostgreSQL (Multi-AZ opcional, storage autoscaling, backups)
#   - Parâmetros SSM com endpoint/porta/nome/credenciais do banco para os demais repos consumirem

data "aws_ssm_parameter" "vpc_id" {
  name = "/soat/${var.environment}/network/vpc-id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/soat/${var.environment}/network/private-subnet-ids"
}

data "aws_ssm_parameter" "vpc_cidr" {
  name = "/soat/${var.environment}/network/vpc-cidr"
}

locals {
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}

resource "aws_security_group" "rds" {
  name        = "soat-rds-${var.environment}"
  description = "Permite acesso Postgres a partir de qualquer recurso nas subnets privadas da VPC"
  vpc_id      = local.vpc_id

  # Liberado por CIDR (não por SG específico) de propósito: tanto os nodes do
  # EKS quanto o Lambda de autenticação (ambos configurados nas subnets
  # privadas) precisam acessar o RDS, e amarrar o SG do RDS a um SG específico
  # de outro repositório criaria uma dependência circular de apply entre os
  # três repos. Ver ADR "Split de infraestrutura entre repositórios".
  ingress {
    description = "Postgres a partir das subnets privadas da VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_ssm_parameter.vpc_cidr.value]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "soat-rds-${var.environment}"
  subnet_ids = local.private_subnet_ids
}

# Senha gerada pelo Terraform e guardada só como SSM SecureString — nunca sai
# como output em texto plano nem fica em .tfvars versionado.
resource "random_password" "master" {
  length      = 32
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/soat/${var.environment}/rds/password"
  type  = "SecureString"
  value = random_password.master.result
}

resource "aws_db_parameter_group" "this" {
  name   = "soat-rds-${var.environment}"
  family = "postgres16"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "soat-rds-${var.environment}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.master.result
  port     = 5432

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.allocated_storage_gb * 3
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"

  deletion_protection       = var.environment == "producao"
  skip_final_snapshot       = var.environment != "producao"
  final_snapshot_identifier = var.environment == "producao" ? "soat-rds-producao-final" : null

  performance_insights_enabled = true
}

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/soat/${var.environment}/rds/endpoint"
  type  = "String"
  value = aws_db_instance.this.address
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/soat/${var.environment}/rds/port"
  type  = "String"
  value = tostring(aws_db_instance.this.port)
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/soat/${var.environment}/rds/db-name"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/soat/${var.environment}/rds/username"
  type  = "String"
  value = var.db_username
}

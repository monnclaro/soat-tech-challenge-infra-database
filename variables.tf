variable "aws_region" {
  description = "Região AWS onde os recursos são provisionados."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deploy. Só existe 'producao' nesta fase — sem homologação, para minimizar custo (AWS Academy)."
  type        = string
  default     = "producao"

  validation {
    condition     = var.environment == "producao"
    error_message = "environment deve ser 'producao' — não há ambiente de homologação nesta fase."
  }
}

# ── Rede (publicada pelo repo soat-tech-challenge-infra-k8s via SSM) ────────
# A VPC é criada uma única vez pelo infra-k8s (um cluster/VPC por ambiente);
# este repo apenas a consome, para evitar dois repositórios Terraform
# disputando o mesmo recurso de rede (ver ADR "Split de infraestrutura entre
# repositórios"). Os nomes dos parâmetros são compostos com `environment` em
# main.tf — homologação e produção têm VPCs e paths SSM distintos.

# ── Banco ─────────────────────────────────────────────────────────────────
variable "db_name" {
  description = "Nome do banco de dados inicial."
  type        = string
  default     = "soattechchallenge"
}

variable "db_username" {
  description = "Usuário master do RDS."
  type        = string
  default     = "soat_admin"
}

variable "engine_version" {
  description = "Versão do PostgreSQL."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Classe da instância RDS. db.t3.micro cabe no free tier (conta com menos de 12 meses)."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Armazenamento inicial (GB), com autoscaling até 3x via max_allocated_storage."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Habilita Multi-AZ (alta disponibilidade). Recomendado apenas em produção."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Dias de retenção de backup automático."
  type        = number
  default     = 7
}

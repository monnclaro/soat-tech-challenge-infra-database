output "db_endpoint" {
  description = "Endpoint (host) do RDS."
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_password_ssm_parameter" {
  description = "Nome do parâmetro SSM SecureString com a senha do RDS."
  value       = aws_ssm_parameter.db_password.name
}

output "db_security_group_id" {
  value = aws_security_group.rds.id
}

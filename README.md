# soat-tech-challenge-infra-database

> Infraestrutura como código (Terraform) do banco de dados gerenciado da oficina — parte da Fase 3 do Tech Challenge FIAP, que separa a solução em 4 repositórios independentes: [app](https://github.com/monnclaro/soat-tech-challenge) · [infra-k8s](https://github.com/monnclaro/soat-tech-challenge-infra-k8s) · [lambda](https://github.com/monnclaro/soat-tech-challenge-lambda) · **infra-database** (este repositório).

## Propósito

Provisiona um banco **PostgreSQL gerenciado (Amazon RDS)** para a aplicação da oficina, com credenciais no SSM Parameter Store e rede isolada dentro da VPC criada pelo [infra-k8s](https://github.com/monnclaro/soat-tech-challenge-infra-k8s). Não contém nenhuma lógica de aplicação — só a infraestrutura de dados.

## Tecnologias

| Componente | Tecnologia |
|---|---|
| IaC | Terraform ~> 1.9 |
| Provider | AWS (`hashicorp/aws` ~> 5.60) |
| Banco | Amazon RDS PostgreSQL 16 |
| Segredos | SSM Parameter Store (`SecureString`) — não Secrets Manager, ver nota de custo abaixo |
| Descoberta de config cross-repo | AWS SSM Parameter Store |
| CI/CD | GitHub Actions (credenciais estáticas de sessão — ver nota AWS Academy) |

### Nota: AWS Academy e prioridade de custo

Esta infraestrutura foi ajustada para caber no **AWS Academy Learner Lab**: sem Secrets Manager (~$0,40/segredo/mês — trocado por SSM `SecureString`, que usa a chave gerenciada padrão da AWS sem custo e sem precisar criar KMS key própria). O Academy também bloqueia credenciais de longa duração e criação de IAM roles — o CI/CD usa `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` como secrets do GitHub, que expiram junto com a sessão do Lab e precisam ser atualizados manualmente. Detalhes completos: ADR "Prioridade de custo e AWS Academy" no repositório principal (`soat-tech-challenge/docs/adr`).

## Arquitetura

```
                         ┌────────────────────────────┐
                         │   infra-k8s (outro repo)    │
                         │  cria VPC + subnets + EKS   │
                         └─────────────┬───────────────┘
                                        │ publica em SSM:
                                        │  /soat/producao/network/vpc-id
                                        │  /soat/producao/network/private-subnet-ids
                                        │  /soat/producao/network/vpc-cidr
                                        ▼
┌───────────────────────────────────────────────────────────────┐
│                    soat-tech-challenge-infra-database          │
│                                                                  │
│  data.aws_ssm_parameter ──▶ aws_security_group (5432 via CIDR)  │
│                                        │                         │
│                                        ▼                         │
│                              aws_db_subnet_group                 │
│                                        │                         │
│                                        ▼                         │
│                          aws_db_instance (RDS Postgres 16)       │
│                                        │                         │
│                                        ▼                         │
│                    SSM (endpoint, porta, dbname, username,       │
│                         password como SecureString)              │
└───────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
                    App (soat-tech-challenge) e Lambda leem
                    endpoint/credenciais direto do SSM Parameter Store
```

Por que a VPC não é criada aqui: para não ter dois repositórios Terraform administrando o mesmo recurso de rede (risco de drift/conflito de state). O infra-k8s é o dono da VPC; este repo só a consome via SSM. Justificativa completa no ADR "VPC única, criada pelo infra-k8s" (repositório central de documentação, `soat-tech-challenge/docs/adr`).

## Backend remoto

O state fica em S3 (`soat-tech-challenge-tfstate-augusto`) com lock via DynamoDB (`soat-tech-challenge-tfstate-lock-augusto`), compartilhado entre execuções de CI/CD. Esses dois recursos ficam fora do Terraform gerenciado por este repo — do contrário seria "quem provisiona o backend do próprio backend" — mas **não** são um bootstrap manual único: como a AWS Academy reseta a conta entre sessões, o workflow (`.github/workflows/terraform.yml`) cria bucket e tabela automaticamente, se não existirem, antes de cada `terraform init`. Rodando localmente (fora do CI/CD), você precisa criá-los manualmente antes do primeiro `terraform init` (`aws s3api create-bucket`/`aws dynamodb create-table`, mesmos nomes acima).

## Execução

```bash
terraform init
terraform plan
terraform apply
```

`environment` tem default `"producao"` — só existe esse ambiente nesta fase (sem homologação, para minimizar custo).

## CI/CD

Pipeline em [.github/workflows/terraform.yml](.github/workflows/terraform.yml), acionado em `main`: PR roda `terraform plan`, push roda `terraform apply` (gated por aprovação manual do GitHub Environment `producao`, que se refere ao ambiente AWS de destino, não a uma branch).

Autenticação com a AWS via credenciais estáticas de sessão do AWS Academy (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` como GitHub Secrets) — expiram com a sessão do Lab, precisam ser atualizadas manualmente antes de cada rodada de CI/CD.

`main` exige Pull Request para merge (proteção de branch configurada diretamente no GitHub).

## Links

- Diagrama de componentes completo e ADRs: [soat-tech-challenge/docs](https://github.com/monnclaro/soat-tech-challenge/tree/main/docs)

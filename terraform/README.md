# Terraform — infraestructura del proyecto

Dos configuraciones independientes:

| Carpeta | Qué crea | Estado | Quién la ejecuta |
|---|---|---|---|
| `bootstrap/` | Bucket de estado, proveedor OIDC de GitHub y los 3 roles de pipeline | Local | Una vez, a mano, con credenciales de administrador |
| `.` (raíz) | VPC, ALB, ECR, ECS Fargate, DynamoDB | S3 (`use_lockfile`) | Pipeline 1 (o a mano) |

Requisitos: Terraform **>= 1.10** (por `use_lockfile`) y credenciales AWS locales para el bootstrap.
El ID de cuenta nunca está fijo en los archivos: se obtiene con `aws_caller_identity`.

## 1. Bootstrap (una sola vez)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # editar github_repository = "owner/repo"
terraform init
terraform apply
terraform output github_variables              # valores para las variables de GitHub
```

- Si la cuenta ya tiene el proveedor OIDC de GitHub, use `create_github_oidc_provider = false`.
- Los roles solo confían en tokens con `aud = sts.amazonaws.com` y `sub` igual a
  `repo:<owner/repo>:ref:refs/heads/main` o `repo:<owner/repo>:environment:production`.
- El estado local de `bootstrap/` (`terraform.tfstate`) **no** se versiona; consérvelo mientras viva el proyecto.
- Cargue las variables en GitHub con `pipelines/scripts/configure-github-vars.sh`
  (`AWS_REGION`, `AWS_ROLE_INFRA`, `AWS_ROLE_BUILD`, `AWS_ROLE_DEPLOY`, `TF_STATE_BUCKET`, `PROJECT_PREFIX`).

Permisos de los roles:

- `infra`: tres políticas administradas (`triplepipe-github-infra-{network,compute,iam}`) con ec2/elbv2/ecs/ecr/logs/dynamodb/iam
  acotados a `triplepipe-*` donde el servicio lo permite, más lectura/escritura/borrado de objetos del bucket de estado (incluye `.tflock`).
  Las acciones `Describe*` de EC2/ELBv2, `logs:DescribeLogGroups` y las de task definitions de ECS requieren `Resource: "*"`;
  las de creación de EC2 se acotan por región. No gestiona los roles `triplepipe-github-*` (solo `triplepipe-demo-*`).
- `build`: `ecr:GetAuthorizationToken` (`*`) y push/lectura solo en los dos repos.
- `deploy`: registrar task definitions, `Describe*`, `UpdateService`, lectura de ECR, `elbv2:Describe*` y `iam:PassRole`
  solo a los roles de ECS con `iam:PassedToService = ecs-tasks.amazonaws.com`.

## 2. Infraestructura (raíz)

```bash
cd terraform
cp backend.hcl.example backend.hcl             # poner el bucket (salida tf_state_bucket)
cp terraform.tfvars.example terraform.tfvars   # opcional
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
terraform output alb_url
```

El pipeline 1 hace lo mismo con `-backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=$AWS_REGION"`.

Los servicios ECS nacen con `desired_count = 0` y una task definition con la imagen `:bootstrap` (inexistente a propósito).
Terraform ignora cambios de `task_definition` y `desired_count`: el pipeline 3 es dueño de la versión en ejecución.
Hasta que corran los pipelines 2 y 3 la URL del ALB responderá 503.

### Módulos

`network` (VPC, 2 subredes públicas, sin NAT, SGs), `ecr` (repos inmutables, scan on push, conserva 10, `force_delete`),
`alb` (HTTP:80, `/api/*` → backend), `ecs` (clúster, roles, task definitions, servicios, logs 7 días), `data` (DynamoDB).

Seguridad de red: el SG de las tareas solo acepta tráfico del SG del ALB en 8080 y 8000; sale únicamente por 443.

## 3. Costo y destrucción

Con todo arriba ≈ **$0.07/hora** (ALB, 2 tareas Fargate mínimas, 4 IPv4 públicas). Para no dejar gasto:

```bash
terraform destroy                # raíz (o pipeline 1 con action=destroy y confirm=triplepipe-demo)
cd bootstrap && terraform destroy   # opcional; el bucket de estado tiene versionado y puede requerir vaciarse a mano
```

Destruya primero la raíz y después el bootstrap (el bootstrap borra el bucket que guarda el estado de la raíz).
Los repos ECR usan `force_delete`, así que se eliminan aunque contengan imágenes.

## 4. Validación local sin instalar Terraform

```bash
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.10 fmt -check -recursive
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.10 init -backend=false
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.10 validate
```

## Limitaciones y mejoras

HTTP sin TLS (no hay dominio), sin autenticación, un solo ambiente, sin autoscaling, sin NAT ni VPC endpoints,
sin flow logs ni claves KMS propias (por costo). Todos son candidatos a mejora.

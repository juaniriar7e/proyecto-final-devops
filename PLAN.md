# Plan y contrato técnico — Proyecto final: tres pipelines DevOps en AWS

Este documento es el contrato común. Todo nombre, puerto, variable y ruta aquí definidos son obligatorios
para los tres componentes. Si algo no se puede cumplir, se reporta; no se improvisa un nombre distinto.

Idioma: README, comentarios y mensajes de pipeline en español. Identificadores de código en inglés.

## Decisiones de arquitectura

| Decisión | Elección | Motivo |
|---|---|---|
| CI/CD | GitHub Actions | Gratis, nativo con OIDC, ya hay cuenta de GitHub |
| Credenciales AWS | OIDC con roles IAM por pipeline; sin llaves estáticas | Requisito de no incluir secretos; mínimo privilegio |
| Región | `us-east-1` (variable) | Configurada en la cuenta |
| Cómputo | ECS Fargate, 2 servicios (`frontend`, `backend`) | Requisito |
| Acceso | ALB HTTP:80; `/api/*` → backend, resto → frontend | Mismo origen, sin CORS; sin dominio no hay TLS (documentar) |
| Red | VPC propia, 2 AZ, subredes públicas, sin NAT | NAT ≈ $32/mes es injustificable en una demo. Tareas solo aceptan tráfico del SG del ALB |
| Persistencia | DynamoDB `PAY_PER_REQUEST` | Los datos sobreviven a un despliegue: útil en la demo y demuestra rol de tarea |
| Estado Terraform | S3 con `use_lockfile` (Terraform ≥ 1.10), versionado y cifrado | Sin DynamoDB de locks |
| Etiquetas de imagen | `sha-<7 chars>`, ECR inmutable, sin `latest` | Trazabilidad y rollback exacto |
| Primer despliegue | Terraform crea servicios con `desired_count = 0` e ignora cambios de `task_definition` y `desired_count` | Rompe el ciclo: ECR vacío al aplicar infraestructura. El pipeline 3 es dueño de la versión en ejecución |
| Errores en despliegue | Circuit breaker de ECS con rollback + smoke test que revierte a la revisión anterior | Se debe explicar en la demo |

Costo estimado con todo arriba: ≈ $0.07/hora (ALB, 2 tareas Fargate mínimas, 4 IPv4 públicas). Incluir destrucción en el README.

## Nombres (contrato)

- `project_name` = `triplepipe`, `environment` = `demo`; prefijo `triplepipe-demo`.
- ECR: `triplepipe-demo-frontend`, `triplepipe-demo-backend`
- ECS cluster: `triplepipe-demo-cluster`; servicios: `triplepipe-demo-frontend`, `triplepipe-demo-backend`
- Familias de task definition: iguales a los servicios. Nombre del contenedor: `frontend` / `backend`
- ALB: `triplepipe-demo-alb`
- DynamoDB: `triplepipe-demo-tasks` (partition key `id`, tipo String)
- Log groups: `/ecs/triplepipe-demo-frontend`, `/ecs/triplepipe-demo-backend`
- Roles de ECS: `triplepipe-demo-ecs-execution`, `triplepipe-demo-backend-task`, `triplepipe-demo-frontend-task`
- Roles de pipelines: `triplepipe-github-infra`, `triplepipe-github-build`, `triplepipe-github-deploy`

## Aplicación (`aplicacion/`)

Gestor de tareas. Debe poder demostrarse visualmente que el frontend habla con el backend y qué versión corre.

- `backend/`: Python 3.12 + FastAPI, puerto **8000**. Dockerfile multi-stage, usuario no root.
  - `GET /api/health` → `{"status":"ok"}` (health check del ALB)
  - `GET /api/version` → `{"version": <env APP_VERSION o "dev">, "service":"backend"}`
  - `GET /api/tasks`, `POST /api/tasks` (`{"title"}` no vacío, 201), `PATCH /api/tasks/{id}` (`{"done"}`), `DELETE /api/tasks/{id}` (204); 404/422 correctos.
  - Almacenamiento: DynamoDB si existe `TASKS_TABLE` (región por `AWS_REGION`), memoria si no.
  - Tests con pytest, sin AWS real (`backend/tests/`).
- `frontend/`: React + Vite, servido por nginx sin privilegios en puerto **8080**. Build multi-stage.
  - `GET /health` en nginx → 200 (health check del ALB).
  - Llama a la API con rutas relativas `/api/...`. Muestra lista, crear, completar, borrar, estados de carga y error, y un pie con versión de frontend y de backend.
  - Versión del frontend: `/version.json` generado al arrancar el contenedor desde `APP_VERSION` (no al compilar).
  - Test: al menos Vitest de un componente; `npm run build` y `npm test` deben pasar. Incluir `package-lock.json`.
- `docker-compose.yml`: frontend, backend y un `gateway` nginx en `localhost:8081` con el mismo ruteo que el ALB.
- `.dockerignore` por componente.

## Terraform (`terraform/`)

- `terraform/bootstrap/`: se ejecuta **una vez** con credenciales locales y estado local. Crea bucket de estado (`triplepipe-tfstate-<account_id>`), proveedor OIDC de GitHub y los 3 roles. Variable `github_repository` (`owner/repo`), sin valor por defecto. Salidas: lo necesario para las variables de GitHub.
  - Confianza: `aud = sts.amazonaws.com`; `sub` limitado al repo, a `ref:refs/heads/main` y `environment:production`.
  - `infra`: permisos sobre ec2/ecs/ecr/elbv2/logs/dynamodb/iam acotados a lo necesario y a `triplepipe-*` donde el servicio lo permita, más el bucket de estado. No usar `AdministratorAccess`.
  - `build`: `ecr:GetAuthorizationToken` y push/lectura solo en los dos repos.
  - `deploy`: `ecs:RegisterTaskDefinition`, `Describe*`, `UpdateService`, lectura de imágenes ECR, `elbv2:Describe*`, `iam:PassRole` solo a los roles de ECS con condición `iam:PassedToService = ecs-tasks.amazonaws.com`.
- `terraform/` raíz: `versions.tf`, `backend.tf` (backend S3 parcial, con `backend.hcl.example`), `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, y módulos en `modules/{network,ecr,alb,ecs,data}`.
  - ECR: `IMMUTABLE`, `scan_on_push`, lifecycle que conserva las últimas 10.
  - ALB: listener 80, default → frontend, regla `/api/*` → backend; target groups `ip`; health `/health` y `/api/health`.
  - ECS: Fargate 256 CPU / 512 MB; `deployment_circuit_breaker { enable = true, rollback = true }`; Container Insights desactivado; logs a CloudWatch con retención de 7 días; `ignore_changes = [task_definition, desired_count]`.
  - Task definition inicial con imagen `<repo>:bootstrap` (no existe aún, por eso `desired_count = 0`). Backend con env `TASKS_TABLE`, `AWS_REGION`, `APP_VERSION=bootstrap`. Frontend con `APP_VERSION=bootstrap`.
  - Rol de tarea backend: solo `GetItem/PutItem/UpdateItem/DeleteItem/Scan` sobre la tabla.
  - Salidas: `alb_url`, repos, cluster, servicios.
- `terraform/README.md`: instrucciones de ejecución.

## Pipelines (`pipelines/`)

Requisito de entrega: las definiciones viven en `pipelines/`. GitHub solo lee `.github/workflows/`, así que:

- Fuente canónica: `pipelines/workflows/{1-infra,2-build,3-deploy}.yml`. Copia exacta en `.github/workflows/`, generada por `pipelines/scripts/sync-workflows.sh` (con `--check` que falla si difieren).
- La lógica va en scripts Bash en `pipelines/scripts/` (`set -euo pipefail`, ejecutables también en local). Los YAML quedan delgados.
- Variables de GitHub (no secretos): `AWS_REGION`, `AWS_ROLE_INFRA`, `AWS_ROLE_BUILD`, `AWS_ROLE_DEPLOY`, `TF_STATE_BUCKET`, `PROJECT_PREFIX=triplepipe-demo`. Script `pipelines/scripts/configure-github-vars.sh` las carga con `gh variable set` desde las salidas del bootstrap.
- Acciones fijadas a versión mayor oficial; `permissions` mínimos (`id-token: write`, `contents: read`) en cada workflow.

1. **`1-infra.yml`** — `push` a `main` en `terraform/**`, `pull_request` (solo plan, sin rol si es fork) y `workflow_dispatch` con `action: plan|apply|destroy`. Pasos: `fmt -check`, `validate`, `plan -out` como artefacto; `apply` del plan guardado en job con `environment: production`. `destroy` exige input `confirm == triplepipe-demo`. Debe vaciar ECR antes o usar `force_delete` en los repos.
2. **`2-build.yml`** — `push` a `main` en `aplicacion/**` y `workflow_dispatch`. Tests de backend y frontend, luego build Docker de ambos, etiqueta `sha-<7>`, push a ECR. Si la etiqueta ya existe, se omite (ECR inmutable) sin fallar. Trivy o resultado del scan de ECR se reporta. Resumen en `$GITHUB_STEP_SUMMARY` con URIs. Lógica en `build-and-push.sh`.
3. **`3-deploy.yml`** — `workflow_run` al completar con éxito `2-build` en `main`, y `workflow_dispatch` con `image_tag` (permite redesplegar o revertir). Job con `environment: production`. Pasos:
   - `deploy.sh`: verifica que la imagen existe en ambos repos (falla claro si no); lee la task definition actual; reemplaza `image` y `APP_VERSION`; elimina campos de solo lectura con `jq`; registra revisión; `update-service --desired-count ${DESIRED_COUNT:-1}`, backend primero; `aws ecs wait services-stable`.
   - `smoke-test.sh <url> <version>`: reintentos con espera; `/health`-equivalente vía `/`, `/api/health`, `/api/version` igual a la versión esperada, `/version.json` igual, y CRUD completo sobre `/api/tasks` limpiando lo creado.
   - Si falla: `rollback.sh` vuelve a las revisiones previas guardadas por `deploy.sh` y el job termina en rojo.

## Fuera de alcance

HTTPS y dominio propio, autenticación de usuarios, multi-ambiente, autoscaling. Mencionarlos como mejoras en el README.

## Prohibido

Claves, tokens, contraseñas o IDs de cuenta reales en archivos. Nada de `git init`, `git commit`, `git push`, `terraform apply`, ni llamadas a AWS o a GitHub desde los subagentes.

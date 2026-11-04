# Pipelines

Fuente canónica en `pipelines/workflows/`; GitHub solo lee `.github/workflows/`, así que la copia se genera con
`pipelines/scripts/sync-workflows.sh` (`--check` falla si difieren). Tras editar un workflow, sincroniza.

## Orden de ejecución

1. `terraform/bootstrap` (una vez, local): crea bucket de estado, OIDC y los 3 roles.
2. `pipelines/scripts/configure-github-vars.sh owner/repo`: carga las variables de GitHub. Crea además el
   environment `production` (con revisores) en Settings > Environments.
3. **`1-infra`**: `terraform/**` en `main` o manual (`plan|apply|destroy`). `destroy` exige `confirm = triplepipe-demo`.
4. **`2-build`**: `aplicacion/**` en `main`. Pruebas, build, push a ECR con etiqueta `sha-<7>` (omite si ya existe).
5. **`3-deploy`**: automático al terminar `2-build` con éxito, o manual con `image_tag` (redespliegue o reversión).
   `deploy.sh` -> `smoke-test.sh` -> si algo falla, `rollback.sh` y el job queda en rojo.

## Variables de GitHub (Settings > Variables, no secretos)

`AWS_REGION`, `AWS_ROLE_INFRA`, `AWS_ROLE_BUILD`, `AWS_ROLE_DEPLOY`, `TF_STATE_BUCKET`, `PROJECT_PREFIX` (`triplepipe-demo`).

## Notas

- `TF_STATE_BUCKET` y las demás variables salen de las salidas del bootstrap (`configure-github-vars.sh`); el backend (`key`, cifrado, `use_lockfile`) lo define `terraform/backend.tf`, el pipeline solo pasa `bucket` y `region`.
- En `pull_request` solo corren `fmt -check` y `validate` (`init -backend=false`): los PR no reciben rol OIDC.
- `plan` guarda `tfplan` como artefacto; `apply` (environment `production`) aplica exactamente ese plan.
- El primer despliegue parte de imágenes `:bootstrap` con `desired_count = 0`; si falla, el rollback deja `desired-count 0`.
- Pruebas locales de los scripts de despliegue (sin AWS real): `pipelines/tests/run-tests.sh`.

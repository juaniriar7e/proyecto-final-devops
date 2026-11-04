#!/usr/bin/env bash
# Pasos de Terraform del pipeline 1. Subcomandos:
#   check            fmt -check + init -backend=false + validate (sin credenciales AWS)
#   plan             init con backend, plan -out=tfplan (con TF_ACTION=destroy usa -destroy)
#   apply            init con backend y aplica exactamente el plan guardado tfplan
#   confirm-destroy  verifica que CONFIRM == PROJECT_PREFIX
# Variables: AWS_REGION, PROJECT_PREFIX, TF_STATE_BUCKET (plan/apply), TF_DIR (opcional).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT/terraform}"
CMD="${1:-}"
require_cmd terraform
[[ -d "$TF_DIR" ]] || die "No existe el directorio de Terraform $TF_DIR."

# Variables de entrada por TF_VAR_ (las no declaradas se ignoran sin error).
export_tf_vars() {
  require_vars PROJECT_PREFIX AWS_REGION
  export TF_VAR_aws_region="$AWS_REGION"
  export TF_VAR_project_name="${PROJECT_PREFIX%-*}"
  export TF_VAR_environment="${PROJECT_PREFIX##*-}"
  export TF_IN_AUTOMATION=1
}

tf_init_backend() {
  require_vars TF_STATE_BUCKET
  terraform -chdir="$TF_DIR" init -input=false \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$AWS_REGION"
}

case "$CMD" in
  check)
    log "Comprobando formato (terraform fmt -check)..."
    terraform -chdir="$TF_DIR" fmt -check -recursive -diff \
      || die "El formato de Terraform es incorrecto. Ejecuta 'terraform fmt -recursive' en terraform/."
    log "Inicializando sin backend y validando..."
    terraform -chdir="$TF_DIR" init -backend=false -input=false
    terraform -chdir="$TF_DIR" validate
    ;;
  plan)
    export_tf_vars
    tf_init_backend
    args=(-input=false -out=tfplan -lock-timeout=5m)
    [[ "${TF_ACTION:-}" == "destroy" ]] && args+=(-destroy)
    terraform -chdir="$TF_DIR" plan "${args[@]}"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        printf '### Plan de Terraform (%s)\n\n```\n' "${TF_ACTION:-plan}"
        terraform -chdir="$TF_DIR" show -no-color tfplan | head -c 60000
        printf '\n```\n'
      } >>"$GITHUB_STEP_SUMMARY"
    fi
    ;;
  apply)
    export_tf_vars
    [[ -f "$TF_DIR/tfplan" ]] || die "No se encontró $TF_DIR/tfplan. Descarga el artefacto del job 'plan' antes de aplicar."
    tf_init_backend
    terraform -chdir="$TF_DIR" apply -input=false -lock-timeout=5m tfplan
    ;;
  confirm-destroy)
    require_vars PROJECT_PREFIX
    [[ "${CONFIRM:-}" == "$PROJECT_PREFIX" ]] \
      || die "Para destruir debes escribir '$PROJECT_PREFIX' en el campo 'confirm'."
    ;;
  *)
    die "Subcomando desconocido '$CMD'. Uso: terraform-ci.sh check|plan|apply|confirm-destroy"
    ;;
esac

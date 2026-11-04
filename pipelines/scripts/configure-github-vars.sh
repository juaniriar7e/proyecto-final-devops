#!/usr/bin/env bash
# Carga las variables de GitHub (no secretos) con `gh variable set`, a partir de las
# salidas de terraform/bootstrap. Requiere `gh` autenticado y `terraform` con el estado local.
# Uso: configure-github-vars.sh [owner/repo]
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd gh terraform
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOT="$ROOT/terraform/bootstrap"
REPO="${1:-${GITHUB_REPOSITORY:-}}"
[[ -n "$REPO" ]] || die "Indica el repositorio: configure-github-vars.sh owner/repo (o define GITHUB_REPOSITORY)."
[[ -d "$BOOT" ]] || die "No existe $BOOT."

tf_out() {
  local v
  v="$(terraform -chdir="$BOOT" output -raw "$1" 2>/dev/null)" && [[ -n "$v" ]] \
    || die "No se encontró la salida '$1' en terraform/bootstrap. ¿Ejecutaste terraform apply allí?"
  printf '%s' "$v"
}

set_var() { gh variable set "$1" --repo "$REPO" --body "$2" >/dev/null; log "Variable $1 configurada."; }

set_var AWS_REGION      "$(tf_out aws_region)"
set_var PROJECT_PREFIX  "$(tf_out project_prefix)"
set_var AWS_ROLE_INFRA  "$(tf_out role_infra_arn)"
set_var AWS_ROLE_BUILD  "$(tf_out role_build_arn)"
set_var AWS_ROLE_DEPLOY "$(tf_out role_deploy_arn)"
set_var TF_STATE_BUCKET "$(tf_out tf_state_bucket)"
log "Listo. Recuerda crear el environment 'production' (con revisores) en Settings > Environments."

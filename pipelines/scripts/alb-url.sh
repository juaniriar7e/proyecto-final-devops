#!/usr/bin/env bash
# Imprime la URL HTTP del ALB (por nombre ${PROJECT_PREFIX}-alb).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_cmd aws jq
require_vars AWS_REGION PROJECT_PREFIX
dns="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "${PROJECT_PREFIX}-alb" --output json \
  | jq -r '.LoadBalancers[0].DNSName // empty')" \
  || die "No se pudo consultar el ALB ${PROJECT_PREFIX}-alb."
[[ -n "$dns" ]] || die "El ALB ${PROJECT_PREFIX}-alb no existe. ¿Se aplicó la infraestructura (pipeline 1)?"
printf 'http://%s\n' "$dns"

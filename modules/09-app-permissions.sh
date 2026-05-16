#!/bin/bash
# =============================================================================
# MÓDULO 09 — PERMISSÕES DA APLICAÇÃO LARAVEL
# =============================================================================
# Responsável por:
#   - Criar estrutura básica de pastas (storage/, bootstrap/cache/)
#   - chown deploy:www-data
#   - setgid em diretórios — novos arquivos herdam grupo www-data
#   - umask 002 em .bashrc/.profile — arquivos criados ficam g+rw
#
# Por que setgid + umask:
#   Sem isso, sempre que deploy roda 'git pull' ou 'composer install',
#   www-data não consegue escrever nos arquivos criados → "permission denied"
#   ao acessar storage/. A combinação setgid + umask 002 resolve.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "9.1 ESTRUTURA DE PASTAS"

mkdir -p "${APP_DIR}/storage"
mkdir -p "${APP_DIR}/bootstrap/cache"
mkdir -p "${APP_DIR}/storage/app/public"
mkdir -p "${APP_DIR}/storage/framework/cache"
mkdir -p "${APP_DIR}/storage/framework/sessions"
mkdir -p "${APP_DIR}/storage/framework/views"
mkdir -p "${APP_DIR}/storage/logs"

log_section "9.2 OWNERSHIP E PERMISSÕES"

# Verifica que deploy user existe (módulo 08 deve ter rodado antes)
if ! id "$DEPLOY_USER" &>/dev/null; then
    log_error "Usuário '${DEPLOY_USER}' não existe. Rode o módulo 08 (deploy-user) antes."
fi

# Dono: deploy, grupo: www-data
chown -R ${DEPLOY_USER}:www-data "$APP_DIR"

# Setgid: novos arquivos em diretórios herdam grupo www-data
# Modo 2775 nas pastas, 664 nos arquivos
find "$APP_DIR" -type d -exec chmod 2775 {} \;
find "$APP_DIR" -type f -exec chmod 664 {} \;

chmod -R 2775 "${APP_DIR}/storage"
chmod -R 2775 "${APP_DIR}/bootstrap/cache"

log_section "9.3 UMASK 002 EM .BASHRC/.PROFILE"

# Idempotente: ensure_line_in_file não duplica
ensure_line_in_file 'umask 002' /home/${DEPLOY_USER}/.bashrc
ensure_line_in_file 'umask 002' /home/${DEPLOY_USER}/.profile
ensure_line_in_file 'umask 002' /home/${APP_USER}/.bashrc
ensure_line_in_file 'umask 002' /home/${APP_USER}/.profile

log_ok "Permissões configuradas"
log_ok "Módulo 09 concluído"

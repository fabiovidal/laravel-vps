#!/bin/bash
# =============================================================================
# MÓDULO 07 — SUPERVISOR
# =============================================================================
# Responsável por:
#   - Instalar supervisor
#   - Configurar worker da queue (database driver)
#   - Configurar processo do schedule:run (1x por minuto via loop)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "7. SUPERVISOR"

apt-get install -y -qq supervisor
systemctl enable supervisor
systemctl start supervisor

cat > /etc/supervisor/conf.d/${APP_NAME}-worker.conf << EOF
[program:${APP_NAME}-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_DIR}/artisan queue:work database --sleep=3 --tries=3 --max-time=3600 --memory=128
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=${APP_DIR}/storage/logs/worker.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stopwaitsecs=3600

[program:${APP_NAME}-scheduler]
process_name=%(program_name)s
command=/bin/bash -c 'while true; do php ${APP_DIR}/artisan schedule:run >> ${APP_DIR}/storage/logs/scheduler.log 2>&1; sleep 60; done'
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=${APP_DIR}/storage/logs/scheduler.log
stdout_logfile_maxbytes=5MB
stdout_logfile_backups=3
EOF

systemctl restart supervisor
log_ok "Supervisor configurado"
log_ok "Módulo 07 concluído"

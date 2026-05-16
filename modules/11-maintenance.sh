#!/bin/bash
# =============================================================================
# MÓDULO 11 — MANUTENÇÃO (LOGROTATE + UNATTENDED-UPGRADES)
# =============================================================================
# Responsável por:
#   - Logrotate dos logs da aplicação (storage/logs/*.log)
#   - Atualizações automáticas de segurança (sem reboot)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "11.1 LOGROTATE"

cat > /etc/logrotate.d/${APP_NAME} << EOF
${APP_DIR}/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 664 www-data www-data
    sharedscripts
    postrotate
        supervisorctl restart all > /dev/null 2>&1 || true
    endscript
}
EOF

log_ok "Logrotate configurado"

log_section "11.2 ATUALIZAÇÕES AUTOMÁTICAS DE SEGURANÇA"

apt-get install -y -qq unattended-upgrades

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades
log_ok "Atualizações de segurança automáticas ativadas"
log_ok "Módulo 11 concluído"

#!/bin/bash
# =============================================================================
# MÓDULO 10 — SEGURANÇA (UFW + FAIL2BAN + SSH HARDENING)
# =============================================================================
# Responsável por:
#   - Firewall UFW: 22/80/443 abertos, MySQL/Redis bloqueados externamente
#   - Fail2ban: jails para sshd, nginx-http-auth, nginx-limit-req
#   - SSH: root bloqueado, MaxAuthTries 3, AllowUsers só APP_USER e DEPLOY_USER
#
# ⚠️ ATENÇÃO:
#   Este módulo ALTERA SSH e UFW. Se algo der errado e você não tem console
#   direto na VPS (KVM/console do provedor), pode se trancar fora.
#   Antes de rodar:
#     - Confirme que sua chave SSH está em /home/${APP_USER}/.ssh/authorized_keys
#     - Tenha uma sessão SSH PARALELA aberta como segurança
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "10.1 FIREWALL UFW"

ufw --force reset > /dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw deny 3306/tcp
ufw deny 6379/tcp
ufw --force enable
log_ok "Firewall configurado"

log_section "10.2 FAIL2BAN"

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled = true
filter  = nginx-http-auth
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
filter  = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
EOF

systemctl restart fail2ban
systemctl enable fail2ban
log_ok "Fail2ban configurado"

log_section "10.3 HARDENING SSH"

# Backup com timestamp pra não sobrescrever em re-execuções
if [ ! -f /etc/ssh/sshd_config.bak ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    log_info "Backup salvo em /etc/ssh/sshd_config.bak"
fi

cat > /etc/ssh/sshd_config << EOF
Port 22
Protocol 2

PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

AllowUsers ${APP_USER} ${DEPLOY_USER}

X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*

ClientAliveInterval 300
ClientAliveCountMax 2

Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Valida config antes de restartar (sshd -t)
if ! sshd -t 2>/dev/null; then
    log_warn "sshd_config inválido, restaurando backup..."
    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    log_error "Hardening SSH abortado — verifique a config manualmente."
fi

systemctl restart sshd
log_ok "SSH endurecido"
log_ok "Módulo 10 concluído"

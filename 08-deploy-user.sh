#!/bin/bash
# =============================================================================
# MÓDULO 08 — USUÁRIO DE DEPLOY (CI/CD)
# =============================================================================
# Responsável por:
#   - Criar usuário 'deploy' (DEPLOY_USER)
#   - Gerar 2 pares de chaves SSH:
#     - github_actions_key: GitHub Actions usa pra ENTRAR na VPS
#     - github_deploy:      VPS usa pra fazer git pull no GitHub
#   - Adicionar github.com ao known_hosts (idempotente)
#   - Configurar sudoers SEM wildcard (causa erro em algumas versões do Ubuntu)
#   - Configurar git safe.directory
#   - Adicionar deploy e ubuntu ao grupo www-data
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "8.1 USUÁRIO ${DEPLOY_USER}"

if ! id "$DEPLOY_USER" &>/dev/null; then
    useradd --shell /bin/bash --create-home "$DEPLOY_USER"
    log_ok "Usuário '${DEPLOY_USER}' criado"
else
    log_warn "Usuário '${DEPLOY_USER}' já existe"
fi

chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}

log_section "8.2 DIRETÓRIO .SSH E CHAVES"

mkdir -p /home/${DEPLOY_USER}/.ssh
chmod 700 /home/${DEPLOY_USER}/.ssh
chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh

# Chave 1: GitHub Actions usa pra entrar na VPS (secret DEPLOY_SSH_KEY)
if [ ! -f /home/${DEPLOY_USER}/.ssh/github_actions_key ]; then
    sudo -u ${DEPLOY_USER} ssh-keygen -t ed25519 -C "github-actions-deploy" \
        -f /home/${DEPLOY_USER}/.ssh/github_actions_key -N ""
    cat /home/${DEPLOY_USER}/.ssh/github_actions_key.pub \
        >> /home/${DEPLOY_USER}/.ssh/authorized_keys
    chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys
    chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys
    log_ok "Chave SSH para GitHub Actions (entrada na VPS) gerada"
else
    log_warn "Chave github_actions_key já existe, pulando geração"
fi

# Chave 2: deploy user usa pra fazer git pull do GitHub
if [ ! -f /home/${DEPLOY_USER}/.ssh/github_deploy ]; then
    sudo -u ${DEPLOY_USER} ssh-keygen -t ed25519 -C "deploy-github-pull" \
        -f /home/${DEPLOY_USER}/.ssh/github_deploy -N ""
    log_ok "Chave SSH para git pull (saída para GitHub) gerada"
else
    log_warn "Chave github_deploy já existe, pulando geração"
fi

log_section "8.3 SSH CONFIG E KNOWN_HOSTS"

cat > /home/${DEPLOY_USER}/.ssh/config << EOF
Host github.com
  IdentityFile /home/${DEPLOY_USER}/.ssh/github_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking no
EOF
chmod 600 /home/${DEPLOY_USER}/.ssh/config
chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/config

# known_hosts: adiciona github.com só se ainda não estiver lá (idempotente)
KNOWN_HOSTS="/home/${DEPLOY_USER}/.ssh/known_hosts"
touch "$KNOWN_HOSTS"
if ! grep -q "github.com" "$KNOWN_HOSTS" 2>/dev/null; then
    ssh-keyscan github.com >> "$KNOWN_HOSTS" 2>/dev/null
    log_ok "github.com adicionado ao known_hosts"
else
    log_warn "github.com já em known_hosts, pulando"
fi
chmod 600 "$KNOWN_HOSTS"
chown ${DEPLOY_USER}:${DEPLOY_USER} "$KNOWN_HOSTS"

log_section "8.4 GIT SAFE.DIRECTORY"

# Evita "fatal: detected dubious ownership" no git pull
sudo -u ${DEPLOY_USER} git config --global --add safe.directory "${APP_DIR}" 2>/dev/null || true
sudo -u ${APP_USER}    git config --global --add safe.directory "${APP_DIR}" 2>/dev/null || true

log_section "8.5 GRUPOS"

usermod -aG www-data ${DEPLOY_USER}
usermod -aG www-data ${APP_USER}

log_section "8.6 SUDOERS"

# Sem wildcard * — quebra em algumas versões. Caminhos explícitos.
cat > /etc/sudoers.d/${DEPLOY_USER} << EOF
Defaults:${DEPLOY_USER} !requiretty
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart php${PHP_VERSION}-fpm
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl restart all
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl reload
EOF
chmod 440 /etc/sudoers.d/${DEPLOY_USER}

# Valida sintaxe do sudoers (importante para não trancar o sudo)
if ! visudo -cf /etc/sudoers.d/${DEPLOY_USER} >/dev/null 2>&1; then
    rm /etc/sudoers.d/${DEPLOY_USER}
    log_error "Sintaxe inválida em sudoers — arquivo removido."
fi

log_ok "Deploy user configurado"
log_ok "Módulo 08 concluído"

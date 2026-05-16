#!/bin/bash
# =============================================================================
# MÓDULO 01 — SISTEMA BASE
# =============================================================================
# Responsável por:
#   - Configurar timezone
#   - apt update + upgrade
#   - Instalar pacotes essenciais (curl, git, ufw, fail2ban, acl, etc.)
#   - Criar e ativar swap
#   - Tunar parâmetros de kernel (swappiness, vfs_cache_pressure)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/lib/helpers.sh"
# shellcheck source=../lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "1.1 TIMEZONE"
timedatectl set-timezone "$TIMEZONE"
log_ok "Timezone: $TIMEZONE"

log_section "1.2 ATUALIZAÇÃO DO SISTEMA + PACOTES BASE"

log_info "apt update + upgrade..."
apt-get update -qq
apt-get upgrade -y -qq

log_info "Instalando pacotes essenciais..."
apt-get install -y -qq \
    curl wget git unzip zip \
    software-properties-common \
    apt-transport-https ca-certificates gnupg2 \
    ufw fail2ban \
    htop iotop ncdu \
    build-essential \
    acl \
    cron

log_ok "Sistema base pronto"

log_section "1.3 SWAP"

if [ -f /swapfile ] && swapon --show | grep -q /swapfile; then
    log_warn "Swap já configurado e ativo, pulando..."
else
    if [ ! -f /swapfile ]; then
        log_info "Criando swap de ${SWAP_SIZE}..."
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile

    # /etc/fstab: adiciona só se ainda não estiver lá
    ensure_line_in_file '/swapfile none swap sw 0 0' /etc/fstab

    # /etc/sysctl.conf: tunings de swap (idempotente via ensure_line_in_file)
    ensure_line_in_file 'vm.swappiness=10' /etc/sysctl.conf
    ensure_line_in_file 'vm.vfs_cache_pressure=50' /etc/sysctl.conf

    sysctl -p > /dev/null 2>&1
    log_ok "Swap de ${SWAP_SIZE} configurado"
fi

log_ok "Módulo 01 concluído"

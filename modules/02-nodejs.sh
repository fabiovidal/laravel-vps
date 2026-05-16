#!/bin/bash
# =============================================================================
# MÓDULO 02 — NODE.JS 20
# =============================================================================
# Responsável por:
#   - Instalar Node.js 20 via NodeSource (Vite exige Node 18+)
#   - Remover versão antiga do Ubuntu se existir
#
# Idempotência:
#   Se Node 20 já está instalado, pula tudo.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "2. NODE.JS 20"

# Verifica se Node 20 já está instalado
if command -v node >/dev/null 2>&1; then
    current_major=$(node -v | sed 's/^v\([0-9]*\).*/\1/')
    if [ "$current_major" = "20" ]; then
        log_warn "Node.js 20 já instalado ($(node -v)), pulando..."
        log_ok "Módulo 02 concluído"
        exit 0
    else
        log_info "Versão atual: $(node -v). Atualizando para Node 20..."
    fi
fi

log_info "Removendo Node.js antigo se existir..."
apt-get remove --purge nodejs libnode-dev libnode72 npm -y -qq 2>/dev/null || true
apt-get autoremove -y -qq 2>/dev/null || true
rm -rf /var/cache/apt/archives/nodejs* 2>/dev/null || true

log_info "Instalando Node.js 20 via NodeSource..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
apt-get install -y -qq nodejs

log_ok "Node.js $(node -v) instalado"
log_ok "Módulo 02 concluído"

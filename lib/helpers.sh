#!/bin/bash
# =============================================================================
# HELPERS COMPARTILHADOS — funções de log, validações, idempotência
# =============================================================================
# Carregado por TODOS os módulos. Não deve ter efeito colateral além de
# definir funções e variáveis de formatação.
# =============================================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funções de log
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
log_section() {
    echo -e "\n${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}"
}

# Garante execução como root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Execute com sudo: sudo bash $0"
    fi
}

# Adiciona linha a arquivo apenas se ainda não existir (idempotente).
# Uso: ensure_line_in_file "umask 002" /home/deploy/.bashrc
ensure_line_in_file() {
    local line="$1"
    local file="$2"
    if [ ! -f "$file" ]; then
        echo "$line" > "$file"
        return
    fi
    grep -qxF -- "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Gera segredo seguro sem caracteres problemáticos para URLs/configs.
# Uso: SENHA=$(generate_secret)
generate_secret() {
    openssl rand -base64 48 | tr -d '/+=\n' | head -c 32
}

# Verifica se um pacote está instalado (sem reinstalar).
# Uso: is_pkg_installed nginx && echo "ja tem"
is_pkg_installed() {
    dpkg -s "$1" 2>/dev/null | grep -q "Status:.*installed"
}

#!/bin/bash
# =============================================================================
# SETUP LARAVEL VPS — ORQUESTRADOR
# =============================================================================
# Roda todos os módulos em ordem. Se um falhar, CONTINUA os demais e reporta
# tudo no final. Cada módulo gera log isolado em /var/log/laravel-vps-setup/.
#
# Uso:
#   sudo bash setup.sh                       # roda tudo
#   sudo bash setup.sh --only mysql,redis    # roda só os módulos listados
#   sudo bash setup.sh --skip security       # roda tudo menos os listados
#   sudo bash setup.sh --list                # lista módulos disponíveis
#   sudo bash setup.sh --help                # ajuda
# =============================================================================

# Note: NÃO usar set -e aqui — queremos continuar mesmo se módulo falhar.
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/helpers.sh
source "${SCRIPT_DIR}/lib/helpers.sh"

# Nota: state.sh é carregado APÓS require_root pois cria /root/.laravel_vps_state.env.
# --help/--list funcionam sem sudo.

# =============================================================================
# CATÁLOGO DE MÓDULOS
# =============================================================================
# alias → arquivo
declare -A MODULES=(
    [base]="01-base-system.sh"
    [nodejs]="02-nodejs.sh"
    [php]="03-php.sh"
    [nginx]="04-nginx.sh"
    [mysql]="05-mysql.sh"
    [redis]="06-redis.sh"
    [supervisor]="07-supervisor.sh"
    [deploy-user]="08-deploy-user.sh"
    [permissions]="09-app-permissions.sh"
    [security]="10-security.sh"
    [maintenance]="11-maintenance.sh"
    [artifacts]="12-deploy-artifacts.sh"
)

# Ordem de execução (importa: nginx depende de PHP, permissions depende de
# deploy-user, etc.)
MODULE_ORDER=(
    base
    nodejs
    php
    nginx
    mysql
    redis
    supervisor
    deploy-user
    permissions
    security
    maintenance
    artifacts
)

# =============================================================================
# PARSING DE ARGUMENTOS
# =============================================================================
ONLY=""
SKIP=""

print_help() {
    cat <<HELP
Uso: sudo bash setup.sh [OPÇÕES]

Opções:
  --only LIST   Roda apenas os módulos listados (separados por vírgula).
                Ex: --only mysql,redis,security
  --skip LIST   Pula os módulos listados.
                Ex: --skip security,maintenance
  --list        Lista módulos disponíveis na ordem de execução
  -h, --help    Mostra esta ajuda

Módulos disponíveis: $(IFS=,; echo "${MODULE_ORDER[*]}")

Logs por módulo: ${SETUP_LOG_DIR}/NN-nome.log
Estado persistente: ${STATE_FILE}
HELP
}

print_list() {
    echo "Módulos disponíveis (ordem de execução):"
    local i=1
    for alias in "${MODULE_ORDER[@]}"; do
        printf "  %2d. %-14s → modules/%s\n" "$i" "$alias" "${MODULES[$alias]}"
        ((i++))
    done
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --only)  ONLY="$2"; shift 2;;
        --skip)  SKIP="$2"; shift 2;;
        --list)  print_list; exit 0;;
        -h|--help) print_help; exit 0;;
        *) log_warn "Argumento desconhecido: $1"; shift;;
    esac
done

# Após o parsing, agora sim exigimos root para a execução real
require_root
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"
mkdir -p "$SETUP_LOG_DIR"

# =============================================================================
# RESOLVE LISTA DE MÓDULOS A EXECUTAR
# =============================================================================
declare -a TO_RUN=()

if [ -n "$ONLY" ]; then
    IFS=',' read -ra requested <<< "$ONLY"
    for m in "${requested[@]}"; do
        if [ -n "${MODULES[$m]:-}" ]; then
            TO_RUN+=("$m")
        else
            log_error "Módulo desconhecido: '$m'. Use --list para ver os disponíveis."
        fi
    done
else
    IFS=',' read -ra skipped <<< "${SKIP:-}"
    for m in "${MODULE_ORDER[@]}"; do
        local_skip=0
        for s in "${skipped[@]:-}"; do
            if [ "$m" = "$s" ]; then local_skip=1; break; fi
        done
        [ "$local_skip" = "0" ] && TO_RUN+=("$m")
    done
fi

if [ ${#TO_RUN[@]} -eq 0 ]; then
    log_error "Nenhum módulo selecionado para execução."
fi

# =============================================================================
# EXECUÇÃO
# =============================================================================
log_section "INICIANDO SETUP LARAVEL VPS"
log_info "Módulos a executar: $(IFS=,; echo "${TO_RUN[*]}")"
log_info "Logs em: ${SETUP_LOG_DIR}"
log_info "Estado em: ${STATE_FILE}"

declare -a SUCCESS=()
declare -a FAILED=()

for m in "${TO_RUN[@]}"; do
    LOG_FILE="${SETUP_LOG_DIR}/${MODULES[$m]%.sh}.log"

    log_section "▶ Módulo: ${m} (${MODULES[$m]})"

    # tee duplica stdout para arquivo. Capturamos exit code do bash com PIPESTATUS.
    bash "${SCRIPT_DIR}/modules/${MODULES[$m]}" 2>&1 | tee "$LOG_FILE"
    rc=${PIPESTATUS[0]}

    if [ "$rc" = "0" ]; then
        SUCCESS+=("$m")
        log_ok "Módulo '$m' concluído"
    else
        FAILED+=("$m")
        log_warn "Módulo '$m' FALHOU (exit=$rc)  →  $LOG_FILE"
    fi
done

# =============================================================================
# RELATÓRIO FINAL
# =============================================================================
log_section "RELATÓRIO FINAL"

echo -e "${GREEN}Sucesso (${#SUCCESS[@]}):${NC}"
for m in "${SUCCESS[@]}"; do
    echo -e "  ${GREEN}✓${NC} $m"
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Falhas (${#FAILED[@]}):${NC}"
    for m in "${FAILED[@]}"; do
        echo -e "  ${RED}✗${NC} $m  →  ${SETUP_LOG_DIR}/${MODULES[$m]%.sh}.log"
    done

    echo ""
    failed_csv=$(IFS=,; echo "${FAILED[*]}")
    log_warn "Após corrigir, retente os módulos que falharam com:"
    echo -e "  ${CYAN}sudo bash $0 --only ${failed_csv}${NC}"
    echo ""
    exit 1
fi

echo ""
log_ok "Todos os módulos concluídos com sucesso."
echo ""
log_info "Veja credenciais e próximos passos em: ${CREDS_FILE}"

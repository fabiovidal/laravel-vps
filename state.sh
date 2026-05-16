#!/bin/bash
# =============================================================================
# STATE PERSISTENTE — senhas geradas e flags de execução
# =============================================================================
# Por que existe:
#   Senhas (MYSQL_ROOT_PASS, MYSQL_DB_PASS) são geradas com openssl na PRIMEIRA
#   execução e persistidas em /root/.laravel_vps_state.env. Em re-execuções,
#   o arquivo é lido e as senhas reutilizadas — evita quebrar conexões que
#   já estavam funcionando.
#
# Como usar:
#   source lib/state.sh   # já carrega tudo e gera senhas se faltarem
#   state_set FLAG_NAME 1 # marca uma flag (ex: MYSQL_CONFIGURED=1)
#
# Variáveis disponíveis após o source:
#   MYSQL_ROOT_PASS, MYSQL_DB_PASS, e qualquer coisa que módulos tenham gravado
# =============================================================================

# STATE_FILE vem de config.sh; fallback se ainda não foi carregado
STATE_FILE="${STATE_FILE:-/root/.laravel_vps_state.env}"

# Cria o arquivo se não existir, com permissão restritiva
if [ ! -f "$STATE_FILE" ]; then
    umask 077
    touch "$STATE_FILE"
    chmod 600 "$STATE_FILE"
fi

# Carrega o estado atual como variáveis no shell
set -a
# shellcheck disable=SC1090
source "$STATE_FILE"
set +a

# Atualiza/adiciona uma chave no state file (idempotente)
# Uso: state_set MYSQL_CONFIGURED 1
state_set() {
    local key="$1"
    local value="$2"
    if grep -qE "^${key}=" "$STATE_FILE"; then
        # Usa | como delimitador para evitar conflito com / em senhas
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$STATE_FILE"
    else
        echo "${key}=\"${value}\"" >> "$STATE_FILE"
    fi
    export "${key}=${value}"
}

# Lê uma chave (retorna vazio se não existir)
state_get() {
    local key="$1"
    grep -E "^${key}=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2- | tr -d '"'
}

# Gera e persiste senhas se ainda não existirem (ONE-TIME)
# Se você apagar o state file, na próxima execução senhas NOVAS serão geradas
# e provavelmente quebrarão a conexão com o MySQL existente. Cuidado.
if [ -z "${MYSQL_ROOT_PASS:-}" ]; then
    state_set MYSQL_ROOT_PASS "$(openssl rand -base64 48 | tr -d '/+=\n' | head -c 32)"
fi

if [ -z "${MYSQL_DB_PASS:-}" ]; then
    state_set MYSQL_DB_PASS "$(openssl rand -base64 48 | tr -d '/+=\n' | head -c 32)"
fi

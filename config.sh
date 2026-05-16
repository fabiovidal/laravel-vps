#!/bin/bash
# =============================================================================
# CONFIGURAÇÕES - EDITE AQUI ANTES DE RODAR
# =============================================================================
# Este arquivo é o ÚNICO lugar onde você deve mexer em valores.
# Senhas são geradas automaticamente em lib/state.sh e persistidas em
# /root/.laravel_vps_state.env (não são regeradas em re-execuções).
# =============================================================================

APP_NAME="meuapp"                              # Nome da aplicação (sem espaços/hífens)
APP_DOMAIN="meuapp.com"                        # Domínio principal
APP_DIR="/var/www/${APP_NAME}"                 # Diretório do código
APP_USER="ubuntu"                              # Usuário humano que loga via SSH
PHP_VERSION="8.3"                              # Versão do PHP (precisa de PPA ondrej)
DEPLOY_USER="deploy"                           # Usuário exclusivo para CI/CD
SWAP_SIZE="2G"                                 # Tamanho do swapfile
TIMEZONE="America/Sao_Paulo"                   # Timezone do sistema

# Derivados de APP_NAME (geralmente não precisam mudar)
MYSQL_DB_NAME="${APP_NAME}"
MYSQL_DB_USER="${APP_NAME}_user"

# Diretório onde o orquestrador grava logs de cada módulo
SETUP_LOG_DIR="/var/log/laravel-vps-setup"

# Arquivo de estado persistente (senhas geradas, flags de execução)
STATE_FILE="/root/.laravel_vps_state.env"

# Arquivo final de credenciais consolidadas (gerado pelo módulo 12)
CREDS_FILE="/root/.laravel_vps_credentials"

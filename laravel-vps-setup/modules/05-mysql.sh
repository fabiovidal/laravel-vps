#!/bin/bash
# =============================================================================
# MÓDULO 05 — MYSQL 8.0
# =============================================================================
# Responsável por:
#   - Instalar MySQL 8.0
#   - Aplicar config de produção (innodb buffer, conexões, charset utf8mb4)
#   - Criar database e usuário da aplicação com mysql_native_password
#     (compat com TablePlus / DBeaver / clientes externos)
#
# Re-execução segura:
#   Senhas vêm do state.env (geradas UMA vez). Se este módulo já rodou antes,
#   tentamos conectar com a senha do state. Se funcionar, apenas sincronizamos
#   o usuário/database. Se não funcionar, é primeira execução — configura a
#   senha do root.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "5.1 INSTALAÇÃO MYSQL"

apt-get install -y -qq mysql-server

log_section "5.2 CONFIG DE PRODUÇÃO"

# ATENÇÃO: parâmetros removidos no MySQL 8.0 que causam falha ao iniciar:
#   - query_cache_type / query_cache_size (removidos completamente)
#   - symbolic-links (deprecated e removido)
#   - innodb_log_file_size (substituído por innodb_redo_log_capacity)
cat > /etc/mysql/mysql.conf.d/99-laravel-optimized.cnf << 'EOF'
[mysqld]
# Segurança
bind-address                    = 127.0.0.1
local-infile                    = 0
skip-show-database

# Performance InnoDB (MySQL 8.0+)
innodb_buffer_pool_size         = 2G
innodb_buffer_pool_instances    = 2
innodb_redo_log_capacity        = 134217728
innodb_flush_log_at_trx_commit  = 2
innodb_flush_method             = O_DIRECT
innodb_file_per_table           = 1
innodb_read_io_threads          = 4
innodb_write_io_threads         = 4

# Conexões
max_connections                 = 150
max_connect_errors              = 100000
wait_timeout                    = 300
interactive_timeout             = 300

# Logs
slow_query_log                  = 1
slow_query_log_file             = /var/log/mysql/slow.log
long_query_time                 = 2

# Charset
character-set-server            = utf8mb4
collation-server                = utf8mb4_unicode_ci

[client]
default-character-set           = utf8mb4
EOF

systemctl restart mysql
systemctl enable mysql

log_section "5.3 DATABASE E USUÁRIO"

# Detecta se root já foi configurado com a senha do state.env
export MYSQL_PWD="${MYSQL_ROOT_PASS}"
if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
    log_info "Root já configurado com a senha do state. Sincronizando DB/user..."
    ROOT_NEEDS_PASSWORD=0
else
    # Primeira execução: tenta sem senha (instalação fresh do MySQL)
    unset MYSQL_PWD
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        log_info "Root sem senha detectado. Aplicando senha do state.env..."
        ROOT_NEEDS_PASSWORD=1
    else
        log_error "Não consegui conectar no MySQL. Senha do state divergente do MySQL existente. Reset manual: 'sudo mysql_secure_installation' ou apague o state e reinstale."
    fi
fi

if [ "$ROOT_NEEDS_PASSWORD" = "1" ]; then
    log_info "Definindo senha do root..."
    mysql -u root << SQL
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
SQL
    export MYSQL_PWD="${MYSQL_ROOT_PASS}"
fi

log_info "Criando/sincronizando database '${MYSQL_DB_NAME}' e usuário '${MYSQL_DB_USER}'..."
mysql -u root << SQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${MYSQL_DB_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_DB_PASS}';
ALTER USER '${MYSQL_DB_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_DB_PASS}';

GRANT ALL PRIVILEGES ON \`${MYSQL_DB_NAME}\`.* TO '${MYSQL_DB_USER}'@'localhost';
GRANT SHOW DATABASES ON *.* TO '${MYSQL_DB_USER}'@'localhost';

FLUSH PRIVILEGES;
SQL

unset MYSQL_PWD

state_set MYSQL_CONFIGURED 1
log_ok "MySQL configurado e seguro"
log_ok "Módulo 05 concluído"

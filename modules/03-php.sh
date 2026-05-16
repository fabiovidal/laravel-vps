#!/bin/bash
# =============================================================================
# MÓDULO 03 — PHP + COMPOSER + TUNING
# =============================================================================
# Responsável por:
#   - Adicionar PPA ondrej/php
#   - Instalar PHP-FPM, CLI e extensões necessárias para Laravel
#   - Aplicar config de produção (memory_limit, opcache, FPM pool)
#   - Instalar Composer global
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "3.1 PHP ${PHP_VERSION} + EXTENSÕES"

log_info "Adicionando repositório PHP (Ondrej)..."
add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1
apt-get update -qq

log_info "Instalando PHP ${PHP_VERSION} e extensões..."
apt-get install -y -qq \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-pgsql \
    php${PHP_VERSION}-redis \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-xmlrpc \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-opcache \
    php${PHP_VERSION}-readline \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-tokenizer

log_section "3.2 TUNING PHP PARA PRODUÇÃO"

cat > /etc/php/${PHP_VERSION}/fpm/conf.d/99-laravel-production.ini << EOF
; PHP Otimizado para Laravel em Produção
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php${PHP_VERSION}-fpm-errors.log
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

memory_limit = 256M
max_execution_time = 60
max_input_time = 60
post_max_size = 64M
upload_max_filesize = 64M
max_input_vars = 3000

session.cookie_secure = 1
session.cookie_httponly = 1
session.cookie_samesite = Strict
session.use_strict_mode = 1
session.gc_maxlifetime = 1440

date.timezone = ${TIMEZONE}
realpath_cache_size = 4096K
realpath_cache_ttl = 600
EOF

cat > /etc/php/${PHP_VERSION}/fpm/conf.d/10-opcache.ini << 'EOF'
; OPcache - Performance maxima para Laravel
zend_extension=opcache
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.max_wasted_percentage = 10
opcache.validate_timestamps = 0
opcache.revalidate_freq = 0
opcache.fast_shutdown = 1
opcache.enable_file_override = 1
opcache.huge_code_pages = 1
opcache.preload_user = www-data
EOF

cat > /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf << EOF
[www]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500

pm.status_path = /fpm-status
ping.path = /fpm-ping

access.log = /var/log/php${PHP_VERSION}-fpm-access.log
slowlog = /var/log/php${PHP_VERSION}-fpm-slow.log
request_slowlog_timeout = 5s

security.limit_extensions = .php
EOF

systemctl restart php${PHP_VERSION}-fpm
systemctl enable php${PHP_VERSION}-fpm
log_ok "PHP ${PHP_VERSION} configurado e otimizado"

log_section "3.3 COMPOSER"

if [ -f /usr/local/bin/composer ]; then
    log_warn "Composer já instalado ($(/usr/local/bin/composer --version | head -1)), pulando..."
else
    log_info "Instalando Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1
    chmod +x /usr/local/bin/composer
    log_ok "Composer instalado"
fi

log_ok "Módulo 03 concluído"

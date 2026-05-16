#!/bin/bash
# =============================================================================
# MÓDULO 04 — NGINX
# =============================================================================
# Responsável por:
#   - Instalar Nginx
#   - Configurar nginx.conf global (workers, gzip, headers de segurança,
#     rate limits)
#   - Configurar site da aplicação com:
#     - CSP em linha única (Safari compatibility)
#     - try_files nos assets JS (Livewire/Flux via rota Laravel)
#     - Rate limit em /login, /register, /password
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "4.1 INSTALAÇÃO NGINX"

apt-get install -y -qq nginx

log_section "4.2 NGINX.CONF GLOBAL"

cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections 2048;
    multi_accept on;
    use epoll;
}

http {
    charset utf-8;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    types_hash_max_size 2048;
    client_max_body_size 64M;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log combined buffer=512k flush=1m;
    error_log /var/log/nginx/error.log warn;

    keepalive_timeout 30;
    keepalive_requests 100;
    client_body_timeout 15;
    client_header_timeout 15;
    send_timeout 15;
    reset_timedout_connection on;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/rss+xml
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/svg+xml
        image/x-icon
        text/css
        text/plain
        text/x-component;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=60r/m;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

log_section "4.3 SITE DA APLICAÇÃO (${APP_DOMAIN})"

# IMPORTANTE:
#   - CSP em linha única — quebra de linha causa "cannot parse response" no Safari
#   - try_files no bloco de assets — permite que Livewire/Flux sirvam JS via rota Laravel
cat > /etc/nginx/sites-available/${APP_NAME} << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${APP_DOMAIN} www.${APP_DOMAIN};
    root ${APP_DIR}/public;

    index index.php;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' data: https:; img-src 'self' data:; connect-src 'self';" always;

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ ^/(login|register|password) {
        limit_req zone=login burst=10 nodelay;
        limit_conn addr 10;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    # try_files garante que assets de vendors (Livewire, Flux) servidos via rota
    # Laravel funcionem corretamente quando o arquivo físico não existe
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|svg|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        try_files \$uri /index.php?\$query_string;
    }

    location ~* /(storage|vendor)/.*\.php$ {
        deny all;
    }

    client_max_body_size 64M;
}
EOF

ln -sf /etc/nginx/sites-available/${APP_NAME} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

log_info "Testando configuração do Nginx..."
nginx -t

systemctl restart nginx
systemctl enable nginx
log_ok "Nginx configurado e otimizado"
log_ok "Módulo 04 concluído"

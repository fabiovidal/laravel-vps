#!/bin/bash
# =============================================================================
# MÓDULO 06 — REDIS
# =============================================================================
# Responsável por:
#   - Instalar redis-server
#   - Aplicar config (bind localhost, maxmemory 256mb, AOF, protected-mode)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "6. REDIS"

apt-get install -y -qq redis-server

cat > /etc/redis/redis.conf << 'EOF'
bind 127.0.0.1
protected-mode yes
port 6379

maxmemory 256mb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes

save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec

loglevel notice
logfile /var/log/redis/redis-server.log
EOF

systemctl restart redis-server
systemctl enable redis-server
log_ok "Redis configurado"
log_ok "Módulo 06 concluído"

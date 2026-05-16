#!/bin/bash
# =============================================================================
# MÓDULO 12 — ARTEFATOS DE DEPLOY (deploy.sh + workflow + credenciais)
# =============================================================================
# Responsável por:
#   - Gerar /home/deploy/deploy.sh (script chamado pelo GitHub Actions)
#   - Gerar /home/ubuntu/.github-actions-example/deploy.yml (workflow exemplo)
#   - Consolidar credenciais em /root/.laravel_vps_credentials
#   - Imprimir resumo final com próximos passos
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/state.sh"

require_root

log_section "12.1 SCRIPT DE DEPLOY (/home/${DEPLOY_USER}/deploy.sh)"

# Verifica que deploy user existe
if ! id "$DEPLOY_USER" &>/dev/null; then
    log_error "Usuário '${DEPLOY_USER}' não existe. Rode o módulo 08 (deploy-user) antes."
fi

cat > /home/${DEPLOY_USER}/deploy.sh << DEPLOY_SCRIPT
#!/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR}"
PHP_VERSION="${PHP_VERSION}"

echo "[DEPLOY] Iniciando em \$(date)"

cd "\$APP_DIR"

php artisan down --retry=60

git pull origin main

composer install --no-dev --optimize-autoloader --no-interaction --quiet

# Publica assets de vendors servidos via rota Laravel (Livewire, Flux)
php artisan vendor:publish --tag=livewire:assets --force 2>/dev/null || true
php artisan vendor:publish --tag=flux-assets --force 2>/dev/null || true

php artisan migrate --force --no-interaction
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache
php artisan storage:link 2>/dev/null || true
php artisan queue:restart

sudo /bin/systemctl restart php\${PHP_VERSION}-fpm
sudo /usr/bin/supervisorctl restart all
sudo /bin/systemctl reload nginx

php artisan up

echo "[DEPLOY] Concluido em \$(date)"
DEPLOY_SCRIPT

chmod +x /home/${DEPLOY_USER}/deploy.sh
chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/deploy.sh
log_ok "Script de deploy criado"

log_section "12.2 WORKFLOW GITHUB ACTIONS (EXEMPLO)"

mkdir -p /home/${APP_USER}/.github-actions-example

cat > /home/${APP_USER}/.github-actions-example/deploy.yml << 'GITHUB_WORKFLOW'
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20

      # Build dos assets no CI — não na VPS (mais rápido, sem problema de permissões)
      - name: Build assets
        run: |
          npm ci
          npm run build

      # Envia assets compilados para a VPS
      - name: Copia assets para VPS
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.VPS_USERNAME }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          port: ${{ secrets.SERVER_PORT }}
          source: "public/build"
          target: "/var/www/NOME_DO_APP/public"
          overwrite: true

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.VPS_USERNAME }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          port: ${{ secrets.SERVER_PORT }}
          timeout: 120s
          script: /home/deploy/deploy.sh

      - name: Notify on failure
        if: failure()
        run: echo "Deploy falhou! Verifique os logs."
GITHUB_WORKFLOW

chown -R ${APP_USER}:${APP_USER} /home/${APP_USER}/.github-actions-example
log_ok "Workflow de exemplo gerado em /home/${APP_USER}/.github-actions-example/deploy.yml"

log_section "12.3 CREDENCIAIS CONSOLIDADAS"

DEPLOY_PUB_KEY=$(cat /home/${DEPLOY_USER}/.ssh/github_deploy.pub 2>/dev/null || echo "(ver arquivo: /home/${DEPLOY_USER}/.ssh/github_deploy.pub)")

cat > "$CREDS_FILE" << EOF
# =============================================================
# CREDENCIAIS DA VPS — GUARDE EM LOCAL SEGURO E APAGUE ESTE ARQUIVO
# Gerado em: $(date)
# =============================================================

# MySQL
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS}"
MYSQL_DB_NAME="${MYSQL_DB_NAME}"
MYSQL_DB_USER="${MYSQL_DB_USER}"
MYSQL_DB_PASS="${MYSQL_DB_PASS}"

# Laravel .env (cole no seu .env)
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${MYSQL_DB_NAME}
DB_USERNAME=${MYSQL_DB_USER}
DB_PASSWORD=${MYSQL_DB_PASS}

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
CACHE_DRIVER=redis
QUEUE_CONNECTION=database
SESSION_DRIVER=database

# ─────────────────────────────────────────────────────────────
# GITHUB ACTIONS — Secrets necessários no repositório:
# ─────────────────────────────────────────────────────────────
# SECRET: SERVER_HOST    = IP da sua VPS
# SECRET: SERVER_PORT    = 22
# SECRET: VPS_USERNAME   = ${DEPLOY_USER}
# SECRET: DEPLOY_SSH_KEY = conteúdo de /home/${DEPLOY_USER}/.ssh/github_actions_key
#
# DEPLOY KEY para git pull (Repositório > Settings > Deploy Keys):
# ${DEPLOY_PUB_KEY}
# =============================================================
EOF

chmod 600 "$CREDS_FILE"
log_ok "Credenciais salvas em: $CREDS_FILE"

# =============================================================================
# RESUMO FINAL
# =============================================================================
log_section "SETUP CONCLUÍDO"

echo -e "${GREEN}"
cat << 'SUMMARY'
╔══════════════════════════════════════════════════════════════╗
║              VPS LARAVEL CONFIGURADA COM SUCESSO             ║
╠══════════════════════════════════════════════════════════════╣
║  ✓ Node.js 20 (Vite compatível)                              ║
║  ✓ PHP 8.3 + OPcache + extensões otimizadas                  ║
║  ✓ Nginx + gzip + CSP linha única (Safari compatível)        ║
║  ✓ Nginx: try_files para Livewire/Flux via rota Laravel      ║
║  ✓ MySQL 8.0 compatível (sem query_cache/symbolic-links)     ║
║  ✓ MySQL: mysql_native_password para clientes externos       ║
║  ✓ Redis para cache e sessão                                 ║
║  ✓ Supervisor para workers e scheduler                       ║
║  ✓ Deploy user com SSH + known_hosts + git safe.directory    ║
║  ✓ Permissões setgid + umask 002 (deploy e ubuntu)           ║
║  ✓ Firewall UFW + Fail2ban                                   ║
║  ✓ SSH: root bloqueado, senha + chave habilitados            ║
║  ✓ Logrotate + Atualizações de segurança automáticas         ║
╚══════════════════════════════════════════════════════════════╝
SUMMARY
echo -e "${NC}"

echo -e "${YELLOW}PRÓXIMOS PASSOS:${NC}"
echo ""
echo "1. Adicione a Deploy Key no GitHub (para git pull funcionar):"
echo -e "   ${CYAN}cat /home/${DEPLOY_USER}/.ssh/github_deploy.pub${NC}"
echo "   Repositório > Settings > Deploy Keys > Add deploy key"
echo ""
echo "2. Copie a chave privada para o secret DEPLOY_SSH_KEY no GitHub:"
echo -e "   ${CYAN}cat /home/${DEPLOY_USER}/.ssh/github_actions_key${NC}"
echo ""
echo "3. Adicione todos os secrets no GitHub Actions:"
echo -e "   ${CYAN}cat ${CREDS_FILE}${NC}"
echo "   SERVER_HOST, SERVER_PORT (22), VPS_USERNAME (${DEPLOY_USER}), DEPLOY_SSH_KEY"
echo ""
echo "4. Copie o workflow para seu repositório:"
echo -e "   ${CYAN}cat /home/${APP_USER}/.github-actions-example/deploy.yml${NC}"
echo ""
echo "5. Clone o repositório:"
echo -e "   ${CYAN}sudo mkdir -p ${APP_DIR}${NC}"
echo -e "   ${CYAN}sudo chown ${APP_USER}:${APP_USER} ${APP_DIR}${NC}"
echo -e "   ${CYAN}git clone git@github.com:usuario/repo.git ${APP_DIR}${NC}"
echo -e "   ${CYAN}sudo chown -R ${DEPLOY_USER}:www-data ${APP_DIR}${NC}"
echo ""
echo "6. Configure o .env e inicialize o Laravel:"
echo -e "   ${CYAN}cd ${APP_DIR} && cp .env.example .env${NC}"
echo -e "   ${CYAN}composer install --no-dev --optimize-autoloader${NC}"
echo -e "   ${CYAN}php artisan key:generate${NC}"
echo -e "   ${CYAN}php artisan migrate --force${NC}"
echo -e "   ${CYAN}php artisan config:cache && php artisan route:cache${NC}"
echo ""
echo "7. Instale SSL (após DNS apontado para a VPS):"
echo -e "   ${CYAN}apt install certbot python3-certbot-nginx -y${NC}"
echo -e "   ${CYAN}certbot --nginx -d ${APP_DOMAIN}${NC}"
echo ""
echo -e "${RED}IMPORTANTE:${NC}"
echo "  Após anotar as credenciais em local seguro, apague:"
echo -e "    ${CYAN}shred -u ${CREDS_FILE}${NC}"
echo "  O state file (${STATE_FILE}) deve ser preservado se você quiser"
echo "  re-executar módulos sem regerar senhas."
echo ""
echo -e "${GREEN}Módulo 12 concluído. Sua VPS está pronta para produção!${NC}"

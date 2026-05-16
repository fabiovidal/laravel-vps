# Laravel VPS Setup — Modular

Setup completo de VPS Ubuntu 22.04/24.04 para Laravel, dividido em módulos para facilitar debug e re-execução parcial.

## Estrutura

```
laravel-vps/
├── README.md                       # este arquivo
├── setup.sh                        # orquestrador principal
├── config.sh                       # ✏️  EDITE AQUI antes de rodar
├── lib/
│   ├── helpers.sh                  # logs, cores, utilitários
│   └── state.sh                    # senhas e flags persistentes
└── modules/
    ├── 01-base-system.sh           # apt + pacotes + timezone + swap
    ├── 02-nodejs.sh                # Node.js 20 via NodeSource
    ├── 03-php.sh                   # PHP-FPM + OPcache + Composer
    ├── 04-nginx.sh                 # Nginx + site config
    ├── 05-mysql.sh                 # MySQL 8.0 + DB/user
    ├── 06-redis.sh                 # Redis
    ├── 07-supervisor.sh            # Workers + scheduler
    ├── 08-deploy-user.sh           # User deploy + SSH keys + sudoers
    ├── 09-app-permissions.sh       # chown/chmod/setgid/umask
    ├── 10-security.sh              # UFW + Fail2ban + SSH hardening
    ├── 11-maintenance.sh           # Logrotate + unattended-upgrades
    └── 12-deploy-artifacts.sh      # deploy.sh + workflow + credenciais
```

## Uso

### 1. Edite `config.sh`

```bash
APP_NAME="meuapp"
APP_DOMAIN="meuapp.com"
APP_USER="ubuntu"
PHP_VERSION="8.3"
# ...
```

### 2. Rode tudo

```bash
sudo bash setup.sh
```

### 3. Rode módulos específicos

```bash
# Apenas MySQL e Redis (ex: trocar de banco depois)
sudo bash setup.sh --only mysql,redis

# Tudo menos security (já configurou SSH manualmente)
sudo bash setup.sh --skip security

# Lista todos os módulos
sudo bash setup.sh --list

# Ajuda
sudo bash setup.sh --help
```

### 4. Rodar módulo isoladamente (debug)

```bash
sudo bash modules/05-mysql.sh
```

## Como funciona

### Estado persistente (`/root/.laravel_vps_state.env`)

Senhas são geradas **uma vez** na primeira execução e persistidas. Em re-execuções, são lidas desse arquivo — **não são regeradas**. Isso permite rodar `--only mysql` várias vezes sem quebrar conexões existentes.

```bash
# Conteúdo típico do state:
MYSQL_ROOT_PASS="abc..."
MYSQL_DB_PASS="xyz..."
MYSQL_CONFIGURED="1"
```

⚠️ Se você **apagar** o state file, a próxima execução gera senhas novas e provavelmente quebra o MySQL existente. Mantenha esse arquivo backupado em local seguro.

### Logs por módulo (`/var/log/laravel-vps-setup/`)

Cada módulo gera log isolado:

```
/var/log/laravel-vps-setup/
├── 01-base-system.log
├── 02-nodejs.log
├── 03-php.log
├── ...
└── 12-deploy-artifacts.log
```

Quando algo quebra, o orquestrador aponta diretamente para o log relevante.

### Continua mesmo com falha

Se um módulo falhar, o orquestrador **não para** — registra o erro e segue. No final, mostra:

```
RELATÓRIO FINAL
Sucesso (10):
  ✓ base
  ✓ nodejs
  ...
Falhas (2):
  ✗ mysql  →  /var/log/laravel-vps-setup/05-mysql.log
  ✗ security  →  /var/log/laravel-vps-setup/10-security.log

Após corrigir, retente os módulos que falharam com:
  sudo bash setup.sh --only mysql,security
```

## Aliases dos módulos

| Alias         | Arquivo                       |
|---------------|-------------------------------|
| `base`        | 01-base-system.sh             |
| `nodejs`      | 02-nodejs.sh                  |
| `php`         | 03-php.sh                     |
| `nginx`       | 04-nginx.sh                   |
| `mysql`       | 05-mysql.sh                   |
| `redis`       | 06-redis.sh                   |
| `supervisor`  | 07-supervisor.sh              |
| `deploy-user` | 08-deploy-user.sh             |
| `permissions` | 09-app-permissions.sh         |
| `security`    | 10-security.sh                |
| `maintenance` | 11-maintenance.sh             |
| `artifacts`   | 12-deploy-artifacts.sh        |

## Dependências entre módulos

A ordem importa. Alguns módulos dependem de outros:

- `nginx` precisa de `php` (usa `php-fpm.sock`)
- `permissions` precisa de `deploy-user` (referencia o usuário)
- `artifacts` precisa de `deploy-user` (cria deploy.sh em `/home/deploy/`)
- `security` é o último na ordem para garantir que nada quebre antes do firewall subir

Se rodar `--only nginx` sem ter `php` configurado, o nginx vai reclamar do socket.

## ⚠️ Atenção ao módulo `security`

Esse módulo altera `sshd_config` e ativa o UFW. Antes de rodá-lo:

1. Confirme que sua chave SSH está em `/home/${APP_USER}/.ssh/authorized_keys`
2. Mantenha **uma sessão SSH paralela aberta** como rede de segurança
3. Tenha acesso ao console do provedor (KVM/VNC) caso precise recuperar

O módulo valida `sshd -t` antes de reiniciar e restaura o backup automaticamente se a config estiver inválida.

## Idempotência

Todos os módulos podem ser executados N vezes sem efeito colateral:

- Pacotes apt: idempotentes por natureza
- Configs: sempre sobrescritas com o template oficial
- Usuários e chaves: verificadas antes de criar
- `.bashrc`/`.profile`/`known_hosts`: linhas só são adicionadas se ainda não existem
- MySQL: detecta se já tem senha root configurada e age conforme

## Após o setup

1. Adicione a deploy key no GitHub: `cat /home/deploy/.ssh/github_deploy.pub`
2. Configure os secrets no GitHub Actions (conteúdo em `/root/.laravel_vps_credentials`)
3. Clone o repositório em `${APP_DIR}`
4. Configure `.env` com as credenciais MySQL
5. Instale SSL: `certbot --nginx -d seudominio.com`
6. Apague o arquivo de credenciais: `shred -u /root/.laravel_vps_credentials`

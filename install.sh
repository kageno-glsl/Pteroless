#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
RESET='\033[0m'
info() {
printf "${CYAN}[INFO]${RESET} %s\n" "$1"
}
ok() {
printf "${GREEN}[ OK ]${RESET} %s\n" "$1"
}
warn() {
printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}
fail() {
printf "${RED}[FAIL]${RESET} %s\n" "$1" >&2
exit 1
}
step() {
printf "\n${BLUE}==>${RESET} ${WHITE}%s${RESET}\n" "$1"
}
trap 'printf "\n${RED}[FAIL]${RESET} Installation failed at line %s.\n" "$LINENO" >&2' ERR
AUTOMATIC_SETUP=false
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin123"
ADMIN_EMAIL="admin@example.com"
ADMIN_FIRST_NAME="Admin"
ADMIN_LAST_NAME="User"
APP_URL="http://127.0.0.1:8080"
PHPV=""
for arg in "$@"; do
case "$arg" in
--automaticsetup)
AUTOMATIC_SETUP=true
;;
-h|--help)
cat <<EOF
Pteroless Installer
Usage:
sudo ./install.sh
sudo ./install.sh --automaticsetup
Modes:
Normal
Opens the setup form and asks for:
- Admin username
- Admin password
- Admin email
- First name
- Last name
- App URL
Automatic
Uses these defaults:
Username : admin
Password : admin123
Email: admin@example.com
Name : Admin User
App URL: http://127.0.0.1:8080
EOF
exit 0
;;
*)
fail "Unknown argument: $arg"
;;
esac
done
clear 2>/dev/null || true
printf "\n"
printf "${WHITE}Pteroless Installer${RESET}\n"
printf "${CYAN}Simple installation for Debian / Ubuntu${RESET}\n"
printf "\n"
if [[ "${EUID}" -ne 0 ]]; then
fail "Please run installer as root: sudo ./install.sh"
fi
if ! command -v apt-get >/dev/null 2>&1; then
fail "apt-get was not found. This installer supports Debian/Ubuntu systems."
fi
if [[ "$AUTOMATIC_SETUP" == true ]]; then
ADMIN_PASSWORD="admin123"
printf "${WHITE}Automatic setup enabled.${RESET}\n"
printf "\n"
printf "Username : ${CYAN}%s${RESET}\n" "$ADMIN_USERNAME"
printf "Password : ${CYAN}%s${RESET}\n" "$ADMIN_PASSWORD"
printf "Email: ${CYAN}%s${RESET}\n" "$ADMIN_EMAIL"
printf "Name : ${CYAN}%s %s${RESET}\n" \
"$ADMIN_FIRST_NAME" \
"$ADMIN_LAST_NAME"
printf "App URL: ${CYAN}%s${RESET}\n" "$APP_URL"
printf "\n"
else
printf "${WHITE}Pteroless Setup${RESET}\n"
printf "Enter the information for your first administrator.\n"
printf "\n"
read -r -p "Admin username [admin]: " INPUT_USERNAME
ADMIN_USERNAME="${INPUT_USERNAME:-admin}"
while true; do
read -r -s -p "Admin password [admin123]: " INPUT_PASSWORD
printf '%s\n' ""
ADMIN_PASSWORD="${INPUT_PASSWORD:-admin123}"
break
done
read -r -p "Admin email [admin@example.com]: " INPUT_EMAIL
ADMIN_EMAIL="${INPUT_EMAIL:-admin@example.com}"
read -r -p "First name [Admin]: " INPUT_FIRST
ADMIN_FIRST_NAME="${INPUT_FIRST:-Admin}"
read -r -p "Last name [User]: " INPUT_LAST
ADMIN_LAST_NAME="${INPUT_LAST:-User}"
read -r -p "App URL [http://127.0.0.1:8080]: " INPUT_URL
APP_URL="${INPUT_URL:-http://127.0.0.1:8080}"
printf "\n"
printf "${WHITE}Setup summary${RESET}\n"
printf '%s\n' '----------------------------------------'
printf "Username : %s\n" "$ADMIN_USERNAME"
printf "Password : ********\n"
printf "Email: %s\n" "$ADMIN_EMAIL"
printf "Name : %s %s\n" "$ADMIN_FIRST_NAME" "$ADMIN_LAST_NAME"
printf "App URL: %s\n" "$APP_URL"
printf '%s\n' '----------------------------------------'
read -r -p "Continue installation? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
printf "\n"
warn "Installation cancelled."
exit 0
fi
fi
step "Updating package lists"
apt-get update
ok "Package lists updated."
step "Installing system dependencies"
apt-get install -y \
ca-certificates \
curl \
unzip \
git \
openssl \
python3 \
python3-venv \
default-jre-headless \
golang-go \
sqlite3
ok "System dependencies installed."
step "Checking PHP"
# Use distribution-provided PHP meta-packages instead of hard-coding
# php8.x-* package names. This also handles environments that ship a
# separate/custom PHP build under /usr/local/php.
PHP_PACKAGES=(
php
php-cli
php-fpm
php-sqlite3
php-mysql
php-mbstring
php-xml
php-curl
php-zip
php-bcmath
php-gd
php-intl
php-opcache
)

info "Installing/refreshing the Debian/Ubuntu PHP package set."
apt-get install -y "${PHP_PACKAGES[@]}"

# Some dev containers put a custom PHP before /usr/bin in PATH. Prefer the
# package-managed PHP because its extensions are installed by apt and match
# the system ABI.
SYSTEM_PHP=""
if [[ -x "/usr/bin/php" ]]; then
SYSTEM_PHP="/usr/bin/php"
else
for candidate in /usr/bin/php8.4 /usr/bin/php8.3 /usr/bin/php8.2; do
if [[ -x "$candidate" ]]; then
SYSTEM_PHP="$candidate"
break
fi
done
fi

if [[ -n "$SYSTEM_PHP" ]]; then
PHP_VERSION="$("$SYSTEM_PHP" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
if [[ "$PHP_VERSION" =~ ^8\.[2-9]$ ]]; then
# Ensure commands such as composer (which use /usr/bin/env php) also resolve
# to the system PHP instead of /usr/local/php.
export PATH="/usr/bin:/bin:${PATH}"
hash -r 2>/dev/null || true
ok "Using system PHP ${PHP_VERSION} (${SYSTEM_PHP})"
else
fail "The system PHP at ${SYSTEM_PHP} is unsupported: ${PHP_VERSION:-unknown}. Requires PHP 8.2+."
fi
else
fail "Could not locate a package-managed PHP binary in /usr/bin."
fi

# Install all required extensions for the same package-managed PHP.
step "Installing PHP extensions"
apt-get install -y "${PHP_PACKAGES[@]}"

# Verify the exact extensions Composer will check.
REQUIRED_EXTENSIONS=(zip pdo_mysql sodium bcmath mbstring xml curl gd intl)
MISSING_EXTENSIONS=()
for ext in "${REQUIRED_EXTENSIONS[@]}"; do
if ! php -m 2>/dev/null | grep -Eiq "^${ext}$"; then
MISSING_EXTENSIONS+=("$ext")
fi
done

# OPcache is reported by `php -m` as "Zend OPcache", not "opcache".
if ! php -m 2>/dev/null | grep -Eiq "^Zend OPcache$"; then
MISSING_EXTENSIONS+=("opcache")
fi

if [[ "${#MISSING_EXTENSIONS[@]}" -gt 0 ]]; then
fail "PHP ${PHP_VERSION} is missing extensions: ${MISSING_EXTENSIONS[*]}"
fi

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
PHPV="$PHP_VERSION"
ok "PHP ${PHPV} and required extensions are ready."
step "Checking Composer"
if ! command -v composer >/dev/null 2>&1; then
info "Installing Composer."
EXPECTED_SIGNATURE="$(curl -fsSL https://composer.github.io/installer.sig)"
php -r "copy(
'https://getcomposer.org/installer',
'/tmp/composer-setup.php'
);"
ACTUAL_SIGNATURE="$(php -r \
"echo hash_file('sha384', '/tmp/composer-setup.php');"
)"
if [[ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]]; then
rm -f /tmp/composer-setup.php
fail "Composer installer signature verification failed."
fi
php /tmp/composer-setup.php \
--install-dir=/usr/local/bin \
--filename=composer
rm -f /tmp/composer-setup.php
ok "Composer installed."
else
ok "Composer already installed."
fi
step "Checking Node.js"
NODE_OK=false
if command -v node >/dev/null 2>&1; then
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -ge 26 ]]; then
NODE_OK=true
ok "Node.js $(node --version) already installed."
else
warn "Node.js $(node --version) is older than 26."
fi
fi
if [[ "$NODE_OK" != true ]]; then
info "Installing Node.js 26."
curl -fsSL https://deb.nodesource.com/setup_26.x | bash -
apt-get install -y nodejs
ok "Node.js $(node --version) installed."
fi
if ! command -v npm >/dev/null 2>&1; then
fail "npm was not installed with Node.js."
fi
ok "npm $(npm --version)"
step "Checking Python"
if ! command -v python3 >/dev/null 2>&1; then
fail "Python 3 is not available."
fi
if ! python3 -m venv --help >/dev/null 2>&1; then
fail "Python virtual environment support is unavailable."
fi
ok "Python $(python3 --version)"
step "Checking Java"
if ! command -v java >/dev/null 2>&1; then
fail "Java is not available."
fi
ok "$(java -version 2>&1 | head -n 1)"
step "Checking Go"
if ! command -v go >/dev/null 2>&1; then
fail "Go is not available."
fi
ok "$(go version)"
step "Preparing SQLite"
mkdir -p "$ROOT/database"
DB_FILE="$ROOT/database/database.sqlite"
USE_EXISTING_DB=false

# If the installer has been run before and a database already exists, let
# normal interactive installs choose whether to keep it or start fresh.
if [[ -f "$DB_FILE" ]]; then
if [[ "$AUTOMATIC_SETUP" == true ]]; then
info "Automatic setup enabled: replacing the existing database with a fresh one."
rm -f "$DB_FILE"
else
printf "\n"
warn "An existing SQLite database was found:"
printf "  %s\n" "$DB_FILE"
printf "\n"
read -r -p "Use existing database? [Y/n]: " USE_DB_CONFIRM
USE_DB_CONFIRM="${USE_DB_CONFIRM:-Y}"

if [[ "$USE_DB_CONFIRM" =~ ^[Yy]$ ]]; then
USE_EXISTING_DB=true
ok "Using existing database."
else
info "Replacing existing database with a fresh one."
rm -f "$DB_FILE"
fi
fi
fi

if [[ "$USE_EXISTING_DB" != true ]]; then
touch "$DB_FILE"
chmod 664 "$DB_FILE"
ok "Fresh SQLite database ready."
else
chmod 664 "$DB_FILE"
fi
step "Configuring environment"
if [[ ! -f "$ROOT/.env" ]]; then
if [[ -f "$ROOT/.env.example" ]]; then
cp "$ROOT/.env.example" "$ROOT/.env"
ok ".env created from .env.example."
else
info ".env.example not found. Creating a default .env file."
cat > "$ROOT/.env" <<EOF
APP_NAME=Pteroless
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=${APP_URL}

LOG_CHANNEL=stack
LOG_LEVEL=warning

DB_CONNECTION=sqlite
DB_DATABASE=${DB_FILE}

BROADCAST_CONNECTION=log
CACHE_STORE=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

MAIL_MAILER=log

# Pteroless / application defaults
APP_ENVIRONMENT_ONLY=false
CACHE_DRIVER=file
EOF
ok ".env created with default settings."
fi
else
info ".env already exists. Keeping existing file."
fi
set_env() {
local key="$1"
local value="$2"
if grep -qE "^${key}=" "$ROOT/.env"; then
sed -i "s|^${key}=.*|${key}=${value}|" "$ROOT/.env"
else
printf "%s=%s\n" "$key" "$value" >> "$ROOT/.env"
fi
}
set_env "APP_ENV" "production"
set_env "APP_DEBUG" "false"
set_env "APP_ENVIRONMENT_ONLY" "false"
set_env "APP_URL" "$APP_URL"
set_env "DB_CONNECTION" "sqlite"
set_env "DB_DATABASE" "$DB_FILE"
set_env "CACHE_DRIVER" "file"
set_env "CACHE_STORE" "file"
set_env "SESSION_DRIVER" "file"
set_env "QUEUE_CONNECTION" "sync"
if grep -qE '^MAIL_HOST=' "$ROOT/.env"; then
MAIL_HOST_VALUE="$(grep '^MAIL_HOST=' "$ROOT/.env" | head -n1 | cut -d'=' -f2- || true)"
if [[ -z "$MAIL_HOST_VALUE" || "$MAIL_HOST_VALUE" == "smtp.example.com" ]]; then
set_env "MAIL_MAILER" "log"
fi
else
set_env "MAIL_MAILER" "log"
fi
ok "Environment configured."
step "Generating application key"
# Laravel's Composer scripts can invoke Artisan before vendor dependencies
# finish installing, so APP_KEY must exist before `composer install`.
CURRENT_APP_KEY="$(grep -E '^APP_KEY=' "$ROOT/.env" | head -n1 | cut -d'=' -f2- || true)"
if [[ -n "$CURRENT_APP_KEY" && "$CURRENT_APP_KEY" != "null" ]]; then
ok "Application key already exists."
else
APP_KEY_VALUE="$(php -r 'echo "base64:".base64_encode(random_bytes(32));')"
if [[ -z "$APP_KEY_VALUE" ]]; then
fail "Could not generate an application encryption key."
fi
set_env "APP_KEY" "$APP_KEY_VALUE"
ok "Application key generated."
fi

step "Preparing Laravel storage"
# Laravel may boot during Composer post-install scripts. The compiled view
# path and framework cache directories must already exist at that point.
mkdir -p \
"$ROOT/storage/framework/cache/data" \
"$ROOT/storage/framework/sessions" \
"$ROOT/storage/framework/views" \
"$ROOT/storage/logs" \
"$ROOT/bootstrap/cache"
chmod -R 775 \
"$ROOT/storage" \
"$ROOT/bootstrap/cache"
ok "Laravel storage directories prepared."

step "Installing PHP dependencies"
composer install \
--no-dev \
--optimize-autoloader \
--no-interaction \
--prefer-dist
ok "PHP dependencies installed."

step "Preparing Laravel"
php artisan config:clear
php artisan cache:clear || true
php artisan view:clear || true
ok "Laravel prepared."
step "Running database migrations"
php artisan migrate \
--force \
--no-interaction
ok "Database migrations completed."
step "Checking administrator account"
if [[ "$USE_EXISTING_DB" == true ]]; then
ADMIN_EXISTS="0"

if sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -qx "users"; then
ADMIN_EXISTS="$(sqlite3 "$DB_FILE" \
"SELECT COUNT(*) FROM users WHERE CAST(root_admin AS TEXT) IN ('1','true');" \
2>/dev/null || echo 0)"
fi

if [[ "$ADMIN_EXISTS" =~ ^[0-9]+$ ]] && [[ "$ADMIN_EXISTS" -gt 0 ]]; then
ok "An administrator already exists in the existing database. Skipping account creation."
else
EMAIL_SQL="$(printf '%s' "$ADMIN_EMAIL" | sed "s/'/''/g")"
USERNAME_SQL="$(printf '%s' "$ADMIN_USERNAME" | sed "s/'/''/g")"

EMAIL_TAKEN="$(sqlite3 "$DB_FILE" \
"SELECT COUNT(*) FROM users WHERE email = '${EMAIL_SQL}';" 2>/dev/null || echo 0)"
USERNAME_TAKEN="$(sqlite3 "$DB_FILE" \
"SELECT COUNT(*) FROM users WHERE username = '${USERNAME_SQL}';" 2>/dev/null || echo 0)"

if [[ "$EMAIL_TAKEN" =~ ^[0-9]+$ ]] && [[ "$EMAIL_TAKEN" -gt 0 ]] ||
   [[ "$USERNAME_TAKEN" =~ ^[0-9]+$ ]] && [[ "$USERNAME_TAKEN" -gt 0 ]]; then
warn "Requested administrator username/email is already in use in the existing database."
info "Skipping administrator creation to avoid changing the existing user."
else
info "Creating administrator account."
php artisan p:user:make \
--email="$ADMIN_EMAIL" \
--username="$ADMIN_USERNAME" \
--password="$ADMIN_PASSWORD" \
--name-first="$ADMIN_FIRST_NAME" \
--name-last="$ADMIN_LAST_NAME" \
--admin=1 \
--no-interaction
ok "Administrator account created."
fi
fi
else
info "Creating administrator account."
php artisan p:user:make \
--email="$ADMIN_EMAIL" \
--username="$ADMIN_USERNAME" \
--password="$ADMIN_PASSWORD" \
--name-first="$ADMIN_FIRST_NAME" \
--name-last="$ADMIN_LAST_NAME" \
--admin=1 \
--no-interaction
ok "Administrator account created."
fi
step "Installing frontend dependencies"
# Some Pteroless/Pterodactyl source revisions import Signals but omit the
# dependency from package.json/yarn.lock. Add the compatible upstream package
# before a frozen Yarn install when it is missing.
if [[ -f "$ROOT/package.json" ]]; then
if ! node -e 'const p=require("./package.json"); const d={...(p.dependencies||{}), ...(p.devDependencies||{})}; process.exit(d["@preact/signals-react"] ? 0 : 1);' 2>/dev/null; then
info "Missing @preact/signals-react dependency. Adding compatible version."
yarn add "@preact/signals-react@^1.2.1" --ignore-scripts --non-interactive
ok "@preact/signals-react dependency added."
fi
fi

if [[ -f "$ROOT/yarn.lock" ]]; then
if ! command -v yarn >/dev/null 2>&1; then
info "Yarn not found. Installing Yarn."
npm install --global yarn
ok "Yarn installed."
fi
yarn install \
--frozen-lockfile \
--non-interactive
ok "Frontend dependencies installed with Yarn."
else
if [[ -f "$ROOT/package-lock.json" ]]; then
npm ci --no-audit --no-fund
else
npm install --no-audit --no-fund
fi
ok "Frontend dependencies installed with npm."
fi
step "Building frontend"
# The project's `yarn clean` script expects public/assets to exist.
# Fresh checkouts may not contain this generated directory yet.
mkdir -p "$ROOT/public/assets"
ok "Frontend asset directory ready."
if [[ -f "$ROOT/yarn.lock" ]]; then
yarn run build:production
else
npm run build:production
fi
ok "Frontend build completed."
step "Optimizing Laravel"
php artisan config:cache
php artisan route:cache || true
php artisan view:cache || true
ok "Laravel optimized."
step "Setting permissions"
mkdir -p \
"$ROOT/storage" \
"$ROOT/storage/framework" \
"$ROOT/storage/framework/cache/data" \
"$ROOT/storage/framework/sessions" \
"$ROOT/storage/framework/views" \
"$ROOT/storage/logs" \
"$ROOT/storage/app" \
"$ROOT/storage/app/servers" \
"$ROOT/bootstrap/cache"

# The installer itself runs as root via sudo, but `start.sh` is intended to
# run as the normal Codespaces/dev user. Give that user ownership so Laravel
# can write logs, cache, sessions, compiled views, and SQLite data.
INSTALL_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$INSTALL_USER" || "$INSTALL_USER" == "root" ]]; then
INSTALL_USER="$(logname 2>/dev/null || true)"
fi

if [[ -z "$INSTALL_USER" || "$INSTALL_USER" == "root" ]]; then
warn "Could not determine the non-root installer user. Leaving ownership unchanged."
else
INSTALL_GROUP="$(id -gn "$INSTALL_USER" 2>/dev/null || echo "$INSTALL_USER")"

chown -R "${INSTALL_USER}:${INSTALL_GROUP}" \
"$ROOT/storage" \
"$ROOT/bootstrap/cache"
chown "${INSTALL_USER}:${INSTALL_GROUP}" "$DB_FILE" 2>/dev/null || true
chown "${INSTALL_USER}:${INSTALL_GROUP}" "$ROOT/.env" 2>/dev/null || true

chmod -R u+rwX,g+rwX \
"$ROOT/storage" \
"$ROOT/bootstrap/cache"
chmod 664 "$DB_FILE"
chmod 640 "$ROOT/.env"
ok "Writable permissions configured for ${INSTALL_USER}."
fi
step "Writing installation information"
cat > "$ROOT/.Pteroless-installed" <<EOF
Pteroless installation completed.
APP_URL=${APP_URL}
DB_CONNECTION=sqlite
DB_DATABASE=${DB_FILE}
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S %Z')
EOF
chmod 600 "$ROOT/.Pteroless-installed"
ok "Installation information saved."
printf "\n"
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${GREEN} Pteroless installation completed successfully${RESET}\n"
printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "\n"
printf "Panel URL: ${CYAN}%s${RESET}\n" "$APP_URL"
printf "Username : ${CYAN}%s${RESET}\n" "$ADMIN_USERNAME"
printf "Email: ${CYAN}%s${RESET}\n" "$ADMIN_EMAIL"
if [[ "$AUTOMATIC_SETUP" == true ]]; then
printf "Password : ${CYAN}%s${RESET}\n" "$ADMIN_PASSWORD"
printf "\n"
printf "${YELLOW}Automatic setup credentials:${RESET}\n"
printf "Username : %s\n" "$ADMIN_USERNAME"
printf "Password : %s\n" "$ADMIN_PASSWORD"
printf "Email: %s\n" "$ADMIN_EMAIL"
else
printf "Password : ${CYAN}(configured during setup)${RESET}\n"
fi
printf "\n"
printf "Start with:\n"
printf "${WHITE}./start${RESET}\n"
printf "\n"
if [[ "$AUTOMATIC_SETUP" == true ]]; then
printf "${YELLOW}Keep the credentials above somewhere safe.${RESET}\n"
printf "\n"
fi

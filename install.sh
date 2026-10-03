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
ADMIN_PASSWORD=""
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
read -r -s -p "Admin password: " INPUT_PASSWORD
printf "\n"
if [[ -z "$INPUT_PASSWORD" ]]; then
warn "Password cannot be empty."
continue
fi
ADMIN_PASSWORD="$INPUT_PASSWORD"
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
printf "----------------------------------------\n"
printf "Username : %s\n" "$ADMIN_USERNAME"
printf "Password : ********\n"
printf "Email: %s\n" "$ADMIN_EMAIL"
printf "Name : %s %s\n" "$ADMIN_FIRST_NAME" "$ADMIN_LAST_NAME"
printf "App URL: %s\n" "$APP_URL"
printf "----------------------------------------\n"
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
for version in 8.4 8.3 8.2; do
if apt-cache show "php${version}-cli" >/dev/null 2>&1; then
if command -v php >/dev/null 2>&1; then
CURRENT_PHP="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
if [[ "$CURRENT_PHP" == "$version" ]]; then
PHPV="$version"
break
fi
fi
fi
done
if [[ -z "$PHPV" ]]; then
if command -v php >/dev/null 2>&1; then
CURRENT_MAJOR="$(php -r 'echo PHP_MAJOR_VERSION;' 2>/dev/null || echo 0)"
CURRENT_MINOR="$(php -r 'echo PHP_MINOR_VERSION;' 2>/dev/null || echo 0)"
if [[ "$CURRENT_MAJOR" -eq 8 ]] &&
 [[ "$CURRENT_MINOR" -ge 2 ]] &&
 [[ "$CURRENT_MINOR" -lt 5 ]]; then
PHPV="${CURRENT_MAJOR}.${CURRENT_MINOR}"
fi
fi
fi
if [[ -z "$PHPV" ]]; then
for version in 8.4 8.3 8.2; do
if apt-cache show "php${version}-cli" >/dev/null 2>&1; then
PHPV="$version"
break
fi
done
fi
if [[ -z "$PHPV" ]]; then
fail "Could not find PHP 8.2, 8.3 or 8.4 in the configured repositories."
fi
info "Using PHP ${PHPV}"
step "Installing PHP ${PHPV}"
apt-get install -y \
"php${PHPV}-cli" \
"php${PHPV}-fpm" \
"php${PHPV}-sqlite3" \
"php${PHPV}-mysql" \
"php${PHPV}-mbstring" \
"php${PHPV}-xml" \
"php${PHPV}-curl" \
"php${PHPV}-zip" \
"php${PHPV}-bcmath" \
"php${PHPV}-gd" \
"php${PHPV}-intl" \
"php${PHPV}-opcache"
ok "PHP ${PHPV} installed."
if ! command -v php >/dev/null 2>&1; then
fail "PHP installation failed."
fi
PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
ok "PHP version: ${PHP_VERSION}"
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
touch "$ROOT/database/database.sqlite"
chmod 664 "$ROOT/database/database.sqlite"
ok "SQLite database ready."
step "Configuring environment"
if [[ ! -f "$ROOT/.env" ]]; then
if [[ ! -f "$ROOT/.env.example" ]]; then
fail ".env.example was not found."
fi
cp "$ROOT/.env.example" "$ROOT/.env"
ok ".env created."
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
set_env "DB_DATABASE" "$ROOT/database/database.sqlite"
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
if grep -qE '^APP_KEY=.+$' "$ROOT/.env"; then
ok "Application key already exists."
else
php artisan key:generate --force
ok "Application key generated."
fi
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
ADMIN_EXISTS="0"
ADMIN_EXISTS="$(php artisan tinker --execute='
echo \App\Models\User::where("root_admin", true)->count();
' 2>/dev/null || echo 0)"
if [[ "$ADMIN_EXISTS" =~ ^[0-9]+$ ]] && [[ "$ADMIN_EXISTS" -gt 0 ]]; then
ok "Administrator already exists. Skipping account creation."
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
"$ROOT/storage/logs" \
"$ROOT/storage/app" \
"$ROOT/storage/app/servers" \
"$ROOT/bootstrap/cache"
chown -R www-data:www-data \
"$ROOT/storage" \
"$ROOT/bootstrap/cache"
chown www-data:www-data \
"$ROOT/database/database.sqlite"
chmod -R 775 \
"$ROOT/storage" \
"$ROOT/bootstrap/cache"
chmod 664 \
"$ROOT/database/database.sqlite"
chown www-data:www-data "$ROOT/.env"
chmod 640 "$ROOT/.env"
ok "Permissions configured."
step "Writing installation information"
cat > "$ROOT/.Pteroless-installed" <<EOF
Pteroless installation completed.
APP_URL=${APP_URL}
DB_CONNECTION=sqlite
DB_DATABASE=${ROOT}/database/database.sqlite
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
printf "Password : ${CYAN}(the password you entered)${RESET}\n"
fi
printf "\n"
printf "Start with:\n"
printf "${WHITE}./start${RESET}\n"
printf "\n"
if [[ "$AUTOMATIC_SETUP" == true ]]; then
printf "${YELLOW}Keep the credentials above somewhere safe.${RESET}\n"
printf "\n"
fi
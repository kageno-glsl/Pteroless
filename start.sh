#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
if [[ "${CODESPACES:-false}" == "true" ]]; then
HOST="${HOST:-localhost}"
else
HOST="${HOST:-0.0.0.0}"
fi
PORT="${PORT:-8080}"
printf '\n'
printf '%s\n' '██████╗ ████████╗███████╗██████╗██████╗ ██╗ ███████╗███████╗███████╗'
printf '%s\n' '██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██═══██╗██║ ██╔════╝██╔════╝██╔════╝'
printf '%s\n' '██████╔╝ ██║ █████╗██████╔╝██║ ██║██║ █████╗███████╗███████╗'
printf '%s\n' '██╔═══╝██║ ██╔══╝██╔══██╗██║ ██║██║ ██╔══╝╚════██║╚════██║'
printf '%s\n' '██║██║ ███████╗██║██║╚██████╔╝███████╗███████╗███████║███████║'
printf '%s\n' '╚═╝╚═╝ ╚══════╝╚═╝╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝'
printf '\n'
printf '%s\n' 'Pteroless Panel - Dev By @kagenouReal Based On Pterodactyl'
printf '\n'
if [[ ! -f vendor/autoload.php ]]; then
echo "[Pteroless] vendor/autoload.php is missing. Run ./install.sh first." >&2
exit 1
fi
if [[ ! -f .env ]]; then
echo "[Pteroless] .env is missing. Run ./install.sh first." >&2
exit 1
fi
if [[ "${EUID}" -eq 0 ]]; then
if command -v runuser >/dev/null 2>&1 && id www-data >/dev/null 2>&1; then
if [[ "${CODESPACES:-false}" == "true" ]]; then
printf '[Pteroless] Codespaces detected. Port %s is available at http://localhost:%s\n' "$PORT" "$PORT"
fi
exec runuser -u www-data -- env \
HOME=/var/www \
HOST="$HOST" \
PORT="$PORT" \
php artisan serve --host="$HOST" --port="$PORT"
fi
echo "[Pteroless] Refusing to run the panel as root." >&2
exit 1
fi
if [[ "${CODESPACES:-false}" == "true" ]]; then
printf '[Pteroless] Codespaces detected. Port %s is available at http://localhost:%s\n' "$PORT" "$PORT"
fi
exec php artisan serve --host="$HOST" --port="$PORT"


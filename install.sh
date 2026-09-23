#!/usr/bin/env bash
set -Eeuo pipefail

# TrustTunnel_exp
# Fully automatic TrustTunnel bootstrap for a clean Ubuntu/Debian VPS.
# Creates 3 independent profiles:
#   Vadim_PC
#   Vadim_laptop
#   Vadim_phone
#
# Secrets are generated ONLY on the VPS and are never sent to GitHub.

TT_DIR="/opt/trusttunnel"
CLIENT_DIR="/root/trusttunnel-clients"
TT_VERSION="${TT_VERSION:-1.1.0}"
TT_HOSTNAME="${TT_HOSTNAME:-vpn.endpoint}"
LISTEN_ADDR="0.0.0.0:443"
CLIENTS=("Vadim_PC" "Vadim_laptop" "Vadim_phone")

C_RESET='\033[0m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'

step() { printf "\n%b==> %s%b\n" "$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf "%b[OK] %s%b\n" "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf "%b[!] %s%b\n" "$C_YELLOW" "$*" "$C_RESET"; }
die()  { printf "%b[ERROR] %s%b\n" "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

on_error() {
    local line="$1"
    local code="$2"
    printf "\n%bInstallation stopped at line %s (exit code %s).%b\n" "$C_RED" "$line" "$code" "$C_RESET" >&2
    printf "Useful diagnostics:\n  systemctl status trusttunnel --no-pager\n  journalctl -u trusttunnel -n 100 --no-pager\n" >&2
}
trap 'on_error "$LINENO" "$?"' ERR

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd is required."

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) warn "This script was tested for Ubuntu/Debian. Detected: ${PRETTY_NAME:-unknown}" ;;
    esac
fi

step "1/10 - Updating the operating system"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get full-upgrade -y
ok "System packages updated."

step "2/10 - Installing required packages"
apt-get install -y \
    curl \
    ca-certificates \
    openssl \
    qrencode \
    ufw \
    iproute2
ok "Dependencies installed."

step "3/10 - Detecting the public IPv4 address"
PUBLIC_IP="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    PUBLIC_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
fi
[[ "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Could not determine public IPv4."
ok "Public IPv4: $PUBLIC_IP"

step "4/10 - Preparing a clean TrustTunnel installation"
if systemctl list-unit-files trusttunnel.service >/dev/null 2>&1; then
    systemctl stop trusttunnel 2>/dev/null || true
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -d "$TT_DIR" ]]; then
    BACKUP="${TT_DIR}.backup.${STAMP}"
    mv "$TT_DIR" "$BACKUP"
    warn "Previous $TT_DIR moved to $BACKUP"
fi
if [[ -d "$CLIENT_DIR" ]]; then
    CLIENT_BACKUP="${CLIENT_DIR}.backup.${STAMP}"
    mv "$CLIENT_DIR" "$CLIENT_BACKUP"
    warn "Previous client files moved to $CLIENT_BACKUP"
fi
mkdir -p "$CLIENT_DIR"
chmod 700 "$CLIENT_DIR"

step "5/10 - Installing official TrustTunnel Endpoint v$TT_VERSION"
curl -fsSL https://raw.githubusercontent.com/TrustTunnel/TrustTunnel/refs/heads/master/scripts/install.sh \
    | sh -s - -V "$TT_VERSION" -a y

[[ -x "$TT_DIR/trusttunnel_endpoint" ]] || die "trusttunnel_endpoint was not installed."
[[ -x "$TT_DIR/setup_wizard" ]] || die "setup_wizard was not installed."
ok "TrustTunnel package installed to $TT_DIR."

step "6/10 - Generating the server configuration and 3 client accounts"
declare -A PASSWORDS
for CLIENT in "${CLIENTS[@]}"; do
    PASSWORDS["$CLIENT"]="$(openssl rand -hex 24)"
done

cd "$TT_DIR"

# Use the official non-interactive setup wizard so that vpn.toml,
# hosts.toml, rules.toml and the self-signed ECDSA certificate use
# TrustTunnel's own current defaults for v1.1.0.
./setup_wizard \
    --mode non-interactive \
    --address "$LISTEN_ADDR" \
    --creds "Vadim_PC:${PASSWORDS[Vadim_PC]}" \
    --hostname "$TT_HOSTNAME" \
    --lib-settings vpn.toml \
    --hosts-settings hosts.toml \
    --cert-type self-signed

# setup_wizard creates the first client. Add the other two independent
# credentials to the same official credentials.toml format.
cat >> "$TT_DIR/credentials.toml" <<EOF_CREDS

[[client]]
username = "Vadim_laptop"
password = "${PASSWORDS[Vadim_laptop]}"

[[client]]
username = "Vadim_phone"
password = "${PASSWORDS[Vadim_phone]}"
EOF_CREDS

chmod 600 "$TT_DIR/credentials.toml"
[[ -f "$TT_DIR/certs/key.pem" ]] && chmod 600 "$TT_DIR/certs/key.pem"
[[ -f "$TT_DIR/certs/cert.pem" ]] && chmod 644 "$TT_DIR/certs/cert.pem"

for CLIENT in "${CLIENTS[@]}"; do
    grep -q "username = \"$CLIENT\"" "$TT_DIR/credentials.toml" \
        || die "Client $CLIENT is missing from credentials.toml."
done
ok "Created Vadim_PC, Vadim_laptop and Vadim_phone."

step "7/10 - Installing the systemd service"
cp "$TT_DIR/trusttunnel.service.template" /etc/systemd/system/trusttunnel.service
systemctl daemon-reload
systemctl enable trusttunnel >/dev/null
systemctl restart trusttunnel
sleep 2

if ! systemctl is-active --quiet trusttunnel; then
    journalctl -u trusttunnel -n 100 --no-pager >&2 || true
    die "TrustTunnel service did not start."
fi
ok "trusttunnel.service is active."

step "8/10 - Configuring UFW"
SSH_PORT="$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}' || true)"
SSH_PORT="${SSH_PORT:-22}"

ufw allow "${SSH_PORT}/tcp" >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
ufw --force enable >/dev/null
ok "UFW enabled: SSH/${SSH_PORT}, 443/TCP and 443/UDP are allowed."

step "9/10 - Exporting deep links and QR codes"
LINKS_FILE="$CLIENT_DIR/links.txt"
: > "$LINKS_FILE"
chmod 600 "$LINKS_FILE"

ACTUAL_VERSION="$("$TT_DIR/trusttunnel_endpoint" --version 2>/dev/null | head -n 1 || true)"

{
    echo "============================================================"
    echo "TrustTunnel client profiles"
    echo "============================================================"
    echo "Server: $PUBLIC_IP:443"
    echo "Hostname/SNI: $TT_HOSTNAME"
    echo "Version: ${ACTUAL_VERSION:-$TT_VERSION}"
    echo "Generated: $(date -Is)"
    echo
    echo "IMPORTANT: tt:// links contain credentials. Keep this file private."
    echo
} >> "$LINKS_FILE"

for CLIENT in "${CLIENTS[@]}"; do
    LINK="$(cd "$TT_DIR" && ./trusttunnel_endpoint vpn.toml hosts.toml \
        --client_config "$CLIENT" \
        --address "$PUBLIC_IP:443" \
        --name "TrustTunnel - $CLIENT")"

    [[ "$LINK" == tt://\?* ]] || die "Could not generate tt:// link for $CLIENT."

    printf '%s\n' "$LINK" > "$CLIENT_DIR/${CLIENT}.link"
    chmod 600 "$CLIENT_DIR/${CLIENT}.link"

    # Keep QR generation local so credentials are not sent to an external QR website.
    if qrencode -l L -s 7 -m 2 -o "$CLIENT_DIR/${CLIENT}.png" "$LINK"; then
        chmod 600 "$CLIENT_DIR/${CLIENT}.png"
    else
        warn "PNG QR generation failed for $CLIENT; the deep link is still valid."
    fi

    if qrencode -l L -t UTF8 "$LINK" > "$CLIENT_DIR/${CLIENT}.qr.txt"; then
        chmod 600 "$CLIENT_DIR/${CLIENT}.qr.txt"
    fi

    {
        echo "[$CLIENT]"
        echo "Username: $CLIENT"
        echo "Password: ${PASSWORDS[$CLIENT]}"
        echo "Deep link: $LINK"
        echo "QR PNG: $CLIENT_DIR/${CLIENT}.png"
        echo "QR terminal file: $CLIENT_DIR/${CLIENT}.qr.txt"
        echo
    } >> "$LINKS_FILE"
done

cat > "$CLIENT_DIR/show-clients.sh" <<'EOF_SHOW'
#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

cat "$DIR/links.txt"

for NAME in Vadim_PC Vadim_laptop Vadim_phone; do
    echo
    echo "==================== $NAME QR ===================="
    qrencode -l L -t ANSIUTF8 "$(cat "$DIR/$NAME.link")"
done
EOF_SHOW
chmod 700 "$CLIENT_DIR/show-clients.sh"

ln -sf "$CLIENT_DIR/show-clients.sh" /usr/local/bin/tt-clients

step "10/10 - Final verification"
systemctl is-enabled --quiet trusttunnel || die "trusttunnel.service is not enabled."
systemctl is-active --quiet trusttunnel || die "trusttunnel.service is not active."

if ! ss -lnt | awk '$4 ~ /:443$/ {found=1} END{exit !found}'; then
    die "Nothing is listening on TCP port 443."
fi
if ! ss -lnu | awk '$4 ~ /:443$/ {found=1} END{exit !found}'; then
    die "Nothing is listening on UDP port 443."
fi

ok "TCP/443 and UDP/443 are listening."
ok "Installation completed successfully."

printf "\n%b============================================================%b\n" "$C_GREEN" "$C_RESET"
printf "%bTrustTunnel is ready.%b\n" "$C_GREEN" "$C_RESET"
printf "%b============================================================%b\n\n" "$C_GREEN" "$C_RESET"

cat "$LINKS_FILE"

printf "\nShow all links and scannable QR codes later with:\n"
printf "  %btt-clients%b\n" "$C_YELLOW" "$C_RESET"
printf "\nOr only view the saved links:\n"
printf "  %bcat %s%b\n" "$C_YELLOW" "$LINKS_FILE" "$C_RESET"
printf "\nService status:\n"
printf "  %bsystemctl status trusttunnel --no-pager%b\n" "$C_YELLOW" "$C_RESET"

if [[ -f /var/run/reboot-required ]]; then
    printf "\n%bSystem updates require a reboot.%b\n" "$C_YELLOW" "$C_RESET"
    printf "All TrustTunnel files are already saved; reboot when convenient:\n"
    printf "  %breboot%b\n" "$C_YELLOW" "$C_RESET"
fi

#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '[OK] %s\n' "$description"
        PASS=$((PASS + 1))
    else
        printf '[FAIL] %s (expected: %s; actual: %s)\n' "$description" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}
printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%F %R')"
echo '[1] SSH'
ssh_config=$(sudo sshd -T) || exit 1
ssh_value() { awk -v key="$1" '$1 == key {print $2}' <<< "$ssh_config"; }
check 'Root login disabled' no "$(ssh_value permitrootlogin)"
check 'Password authentication disabled' no "$(ssh_value passwordauthentication)"
ports=$(ssh_value port)
nonstandard=no
if [[ -n "$ports" ]] && ! grep -qx 22 <<< "$ports"; then nonstandard=yes; fi
check 'SSH uses a nonstandard port' yes "$nonstandard"
check 'MaxAuthTries' 3 "$(ssh_value maxauthtries)"
echo '[2] Firewall'
firewall=$(sudo ufw status verbose) || exit 1
check 'UFW active' active "$(awk '/^Status:/ {print $2}' <<< "$firewall")"
check 'Incoming denied by default' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$firewall")"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd
echo '[4] Web server'
check 'Nginx service active' active "$(systemctl is-active nginx)"
syntax_ok=no
if sudo nginx -t >/dev/null 2>&1; then syntax_ok=yes; fi
check 'Nginx configuration syntax' yes "$syntax_ok"
certificate_ok=no
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${CERT_MIN_SECONDS:-2592000}" >/dev/null 2>&1; then certificate_ok=yes; fi
check 'Certificate valid for required remaining period' yes "$certificate_ok"
site_ok=no
if [[ -d /var/www/devops-site ]] && bad=$(find /var/www/devops-site -perm -o+w -print -quit) && [[ -z "$bad" ]] && [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)" == 600 ]]; then
    site_ok=yes
fi
check 'No world-writable site files; private key mode 600' yes "$site_ok"
echo '[5] Containerization'
check 'Docker service active' active "$(systemctl is-active docker)"
check 'Database container healthy' healthy "$(docker inspect -f '{{if .State.Running}}{{.State.Health.Status}}{{else}}stopped{{end}}' app-db-1 2>/dev/null)"
ports_ok=no
if ss -H -ltn | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {bad=1} END {exit bad}'; then ports_ok=yes; fi
check 'App and database ports are loopback-only' yes "$ports_ok"
APP_DIR="${APP_DIR:-/home/devops/app}"
check 'Application env mode 600' 600 "$(stat -c '%a' "$APP_DIR/.env" 2>/dev/null)"
echo '[6] KR2'
kr_redis_id=$(docker compose --project-directory /home/devops/kr2 ps -q redis 2>/dev/null)
check 'Redis container healthy' healthy "$(docker inspect -f '{{if .State.Running}}{{.State.Health.Status}}{{else}}stopped{{end}}' "$kr_redis_id" 2>/dev/null)"
check 'KR2 port published only on loopback' '127.0.0.1:8004' "$(docker compose --project-directory /home/devops/kr2 port app 8004 2>/dev/null)"
check 'KR2 env mode 600' 600 "$(stat -c '%a' /home/devops/kr2/.env 2>/dev/null)"
kr_cert_ok=no
if openssl x509 -in /etc/ssl/certs/kr2.crt -noout -checkend 2592000 >/dev/null 2>&1; then kr_cert_ok=yes; fi
check 'KR2 certificate valid at least 30 days' yes "$kr_cert_ok"
kr_enabled=no
if [[ -L /etc/nginx/sites-enabled/kr2 ]] && [[ -f /etc/nginx/sites-enabled/kr2 ]]; then kr_enabled=yes; fi
check 'KR2 site enabled' yes "$kr_enabled"
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

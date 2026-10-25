#!/usr/bin/env bash
set -Eeuo pipefail

case_name="$1"
mkdir -p /tmp/mockbin /tmp/installer-test
export MOCK_RESPONSE=/tmp/installer-test/response.json
export MOCK_CAPTURE_ARGS=/tmp/installer-test/agent-args
export MOCK_AGENT_COUNT=/tmp/installer-test/agent-count
export OFFICIAL_SCRIPT_FIXTURE=/official/agent/install.sh
export TEST_SECRET='test-secret-only-1234'

cat >/tmp/mockbin/curl <<'EOF_CURL'
#!/usr/bin/env bash
out=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        http*://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "$url" in
    */api/v2/server/machine/nezha-config)
        [ "${EXPECT_NODE_STARTED:-0}" -eq 0 ] || [ -f /tmp/installer-test/node-started ] || exit 20
        [ "${MOCK_FAIL_CONFIG:-0}" -eq 0 ] || exit 22
        cp "$MOCK_RESPONSE" "$out" ;;
    *raw.githubusercontent.com*) tr -d '\r' < "$OFFICIAL_SCRIPT_FIXTURE" > "$out" ;;
    *github.com/nezhahq/agent*) [ "${MOCK_FAIL_AGENT:-0}" -eq 0 ] || exit 22; : > "$out" ;;
    *) : ;;
esac
EOF_CURL
cat >/tmp/mockbin/unzip <<'EOF_UNZIP'
#!/usr/bin/env bash
cat >/opt/nezha/agent/nezha-agent <<'EOF_AGENT'
#!/usr/bin/env bash
printf '%s' "$*" > "$MOCK_CAPTURE_ARGS"
count=0
[ ! -f "$MOCK_AGENT_COUNT" ] || count=$(cat "$MOCK_AGENT_COUNT")
printf '%s' "$((count + 1))" > "$MOCK_AGENT_COUNT"
printf '%s' "$NZ_CLIENT_SECRET" > /opt/nezha/agent/config.yml
EOF_AGENT
chmod 700 /opt/nezha/agent/nezha-agent
EOF_UNZIP
cat >/tmp/mockbin/systemctl <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 0
EOF_SYSTEMCTL
chmod 700 /tmp/mockbin/*
export PATH="/tmp/mockbin:$PATH"

source <(head -n -1 /src/install.sh)
TMP_DIR=$(mktemp -d)
OS=debian
PANEL_URL='https://panel.example'
MACHINE_ID=7
TOKEN='test-machine-token'

case "$case_name" in
    normal|repeat|agent_failed|node_survives_agent_failure|node_survives_config_failure|upgrade_uninstall)
        printf '%s' '{"enabled":true,"server":"monitor.example:8008","tls":false,"client_secret":"test-secret-only-1234"}' > "$MOCK_RESPONSE" ;;
    disabled)
        printf '%s' '{"enabled":false}' > "$MOCK_RESPONSE" ;;
    malformed)
        printf '%s' '{"enabled":true,"server":"$(touch /tmp/pwn):8008","tls":false,"client_secret":"test-secret-only-1234"}' > "$MOCK_RESPONSE" ;;
    fetch_failed)
        export MOCK_FAIL_CONFIG=1
        printf '%s' '{}' > "$MOCK_RESPONSE" ;;
    *) exit 2 ;;
esac
if [ "$case_name" = node_survives_config_failure ]; then export MOCK_FAIL_CONFIG=1; fi
if [[ "$case_name" == agent_failed || "$case_name" == node_survives_agent_failure ]]; then
    export MOCK_FAIL_AGENT=1
fi

if [[ "$case_name" == normal || "$case_name" == disabled || "$case_name" == node_survives_agent_failure || "$case_name" == node_survives_config_failure ]]; then
    export EXPECT_NODE_STARTED=1
    validate_install_request() { :; }
    detect_current_state() { :; }
    ensure_dirs() { :; }
    stage_binary() { :; }
    stage_xbctl() { :; }
    render_config() { :; }
    render_service() { :; }
    backup_existing_state() { :; }
    install_staged_files() { :; }
    start_service() { : > /tmp/installer-test/node-started; }
    INSTALL_NEZHA=1
    perform_install > /tmp/installer-test/output 2>&1
    [ -f /tmp/installer-test/node-started ]
    grep -q 'Installation succeeded' /tmp/installer-test/output
    if [[ "$case_name" == node_survives_agent_failure || "$case_name" == node_survives_config_failure ]]; then
        grep -q 'Nezha Agent setup failed' /tmp/installer-test/output
    fi
elif [[ "$case_name" == malformed || "$case_name" == fetch_failed || "$case_name" == agent_failed ]]; then
    if install_nezha_agent > /tmp/installer-test/output 2>&1; then exit 1; fi
    [ ! -e /tmp/pwn ]
    [ ! -f "$MOCK_AGENT_COUNT" ]
elif [ "$case_name" = upgrade_uninstall ]; then
    install_nezha_agent > /tmp/installer-test/output 2>&1
    before=$(sha256sum /opt/nezha/agent/config.yml | cut -d' ' -f1)
    mkdir -p /etc/xboard-node /etc/systemd/system /usr/local/bin
    printf 'old' > /etc/xboard-node/config.yml
    printf 'old' > /usr/local/bin/xboard-node
    chmod 755 /usr/local/bin/xboard-node
    printf 'old' > /etc/systemd/system/xboard-node.service
    stage_binary() { printf 'new' > "$TMP_DIR/xboard-node"; }
    stage_xbctl() { printf 'new' > "$TMP_DIR/xbctl"; }
    render_service() { printf 'new' > "$TMP_DIR/xboard-node.service"; }
    HEALTH_ENABLED=0
    perform_upgrade >> /tmp/installer-test/output 2>&1
    [ "$(sha256sum /opt/nezha/agent/config.yml | cut -d' ' -f1)" = "$before" ]
    YES=1
    PURGE=1
    perform_uninstall >> /tmp/installer-test/output 2>&1
    [ "$(sha256sum /opt/nezha/agent/config.yml | cut -d' ' -f1)" = "$before" ]
else
    install_nezha_agent > /tmp/installer-test/output 2>&1
    [ "$(cat "$MOCK_AGENT_COUNT")" = 1 ]
    install_nezha_agent >> /tmp/installer-test/output 2>&1
    [ "$(cat "$MOCK_AGENT_COUNT")" = 1 ]
fi

if [[ "$case_name" == normal || "$case_name" == repeat ]]; then
    [ "$(cat "$MOCK_AGENT_COUNT")" = 1 ]
    [ "$(cat /opt/nezha/agent/config.yml)" = "$TEST_SECRET" ]
    [ "$(stat -c %a /opt/nezha/agent/config.yml)" = 600 ]
fi
if [ "$case_name" = disabled ]; then [ ! -f "$MOCK_AGENT_COUNT" ]; fi
! grep -q "$TEST_SECRET" /tmp/installer-test/output
if [ -f "$MOCK_CAPTURE_ARGS" ]; then ! grep -q "$TEST_SECRET" "$MOCK_CAPTURE_ARGS"; fi
printf 'PASS %s\n' "$case_name"

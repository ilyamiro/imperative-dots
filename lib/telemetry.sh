#!/usr/bin/env bash

send_telemetry() {
    local mode=$1

    # Silent guard: prevent unsupported OS data from reaching analytics
    if [[ "$OS_NAME" =~ "Fedora" ]] || [[ "$DETECTED_OS" == "fedora" ]]; then
        return 0
    fi

    [[ -z "$WORKER_URL" || "$WORKER_URL" == *"YOUR_USERNAME"* ]] && return 0

    local payload=""

    case "$mode" in
        init)
            payload=$(cat <<EOF
{
  "type": "init",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "os": "${OS_NAME//\"/\\\"}"
}
EOF
)
            ;;
        full)
            payload=$(cat <<EOF
{
  "type": "full",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "os": "${OS_NAME//\"/\\\"}"
}
EOF
)
            ;;
        done)
            if [[ "$ENABLE_TELEMETRY" == true ]]; then
                local failed_str="${FAILED_PKGS[*]}"
                local ram=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "Unknown")
                local kernel=$(uname -r 2>/dev/null || echo "Unknown")
                local current_de=${XDG_CURRENT_DESKTOP:-"TTY / Unknown"}
                payload=$(cat <<EOF
{
  "type": "done",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "telemetry_enabled": true,
  "failed_packages": "${failed_str//\"/\\\"}",
  "os": "${OS_NAME//\"/\\\"}",
  "kernel": "${kernel//\"/\\\"}",
  "ram": "${ram//\"/\\\"}",
  "de": "${current_de//\"/\\\"}",
  "cpu": "${CPU_INFO//\"/\\\"}",
  "gpu": "${GPU_INFO//\"/\\\"}"
}
EOF
)
            else
                payload=$(cat <<EOF
{
  "type": "done",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "telemetry_enabled": false,
  "os": "${OS_NAME//\"/\\\"}"
}
EOF
)
            fi
            ;;
    esac

    curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &
}

init_telemetry_id() {
    mkdir -p "$(dirname "$VERSION_FILE")"

    if [ -z "$TELEMETRY_ID" ]; then
        if command -v uuidgen &>/dev/null; then
            TELEMETRY_ID=$(uuidgen)
        else
            TELEMETRY_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null \
                || head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
        fi
        echo "TELEMETRY_ID=\"$TELEMETRY_ID\"" >> "$VERSION_FILE"
    fi
}
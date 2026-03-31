#!/usr/bin/env bash
set -euo pipefail

PAIR_CODE=""
EXPIRES=600
PORT=4500

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pair-code)
      PAIR_CODE="${2:-}"
      shift 2
      ;;
    --expires)
      EXPIRES="${2:-600}"
      shift 2
      ;;
    --port)
      PORT="${2:-4500}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PAIR_CODE" ]]; then
  echo "Missing --pair-code" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  cat >&2 <<'EOF'
`codex` not found.
Install Codex first, then rerun this command.
EOF
  exit 1
fi

WORK_DIR="${TMPDIR:-/tmp}/codexbridge-${PAIR_CODE}"
mkdir -p "$WORK_DIR"
APP_LOG="$WORK_DIR/app-server.log"
TUN_LOG="$WORK_DIR/tunnel.log"

cleanup() {
  [[ -n "${APP_PID:-}" ]] && kill "$APP_PID" >/dev/null 2>&1 || true
  [[ -n "${TUN_PID:-}" ]] && kill "$TUN_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "[1/3] Starting codex app-server on 127.0.0.1:${PORT} ..."
codex app-server --listen "ws://127.0.0.1:${PORT}" >"$APP_LOG" 2>&1 &
APP_PID=$!

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/readyz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${PORT}/readyz" >/dev/null 2>&1; then
  echo "app-server did not become ready. See $APP_LOG" >&2
  exit 1
fi

PUBLIC_HTTPS=""

if command -v cloudflared >/dev/null 2>&1; then
  echo "[2/3] Starting cloudflared quick tunnel ..."
  cloudflared tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate >"$TUN_LOG" 2>&1 &
  TUN_PID=$!

  for _ in $(seq 1 45); do
    PUBLIC_HTTPS="$(grep -Eo 'https://[a-z0-9.-]+\.trycloudflare\.com' "$TUN_LOG" | tail -n1 || true)"
    [[ -n "$PUBLIC_HTTPS" ]] && break
    sleep 1
  done
elif command -v ngrok >/dev/null 2>&1; then
  echo "[2/3] Starting ngrok tunnel ..."
  ngrok http "127.0.0.1:${PORT}" --log=stdout >"$TUN_LOG" 2>&1 &
  TUN_PID=$!

  for _ in $(seq 1 45); do
    PUBLIC_HTTPS="$(curl -fsS http://127.0.0.1:4040/api/tunnels 2>/dev/null | sed -n 's/.*"public_url":"\(https:[^"]*\)".*/\1/p' | head -n1 || true)"
    [[ -n "$PUBLIC_HTTPS" ]] && break
    sleep 1
  done
else
  cat >&2 <<'EOF'
No tunnel client found. Install one of:
- cloudflared
- ngrok
EOF
  exit 1
fi

if [[ -z "$PUBLIC_HTTPS" ]]; then
  echo "failed to get public tunnel URL. See $TUN_LOG" >&2
  exit 1
fi

PUBLIC_WSS="${PUBLIC_HTTPS/https:\/\//wss://}"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat <<EOF
[3/3] Tunnel ready.

Pair code : ${PAIR_CODE}
WS URL    : ${PUBLIC_WSS}
Expires   : ${EXPIRES}s

Send this to mobile app scanner payload:
{"pair_code":"${PAIR_CODE}","ws_url":"${PUBLIC_WSS}","expires_in":${EXPIRES},"generated_at":"${GENERATED_AT}"}

Logs:
- app server: ${APP_LOG}
- tunnel    : ${TUN_LOG}

Keep this terminal running. Press Ctrl+C to stop.
EOF

wait "$APP_PID"
